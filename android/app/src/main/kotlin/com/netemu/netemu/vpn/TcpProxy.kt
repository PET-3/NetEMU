package com.netemu.netemu.vpn

import android.net.VpnService
import android.util.Log
import com.netemu.netemu.emulator.EmulatorConfig
import com.netemu.netemu.emulator.EmulatorStats
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.random.Random

/**
 * Userspace TCP proxy: completes handshake with client over TUN,
 * opens protected Socket to remote, relays both directions with emulator.
 */
class TcpProxy(
    private val vpn: VpnService,
    private val tunOut: FileOutputStream,
    private val running: AtomicBoolean,
) {
    companion object {
        private const val TAG = "NetEmuTcp"
        private const val FLAG_FIN = 0x01
        private const val FLAG_SYN = 0x02
        private const val FLAG_RST = 0x04
        private const val FLAG_PSH = 0x08
        private const val FLAG_ACK = 0x10
    }

    data class Key(val src: InetAddress, val sport: Int, val dst: InetAddress, val dport: Int)

    private val sessions = ConcurrentHashMap<Key, Session>()
    private val pool: ExecutorService = Executors.newCachedThreadPool()

    private class Session(
        val key: Key,
        val remote: Socket,
        val remoteIn: InputStream,
        val remoteOut: OutputStream,
        // sequence numbers as seen by client (our TUN side)
        var clientNextSeq: AtomicInteger, // what we expect from client
        var serverSeq: AtomicInteger,     // what we send to client as seq
        @Volatile var closed: Boolean = false,
        @Volatile var lastActiveMs: Long = System.currentTimeMillis(),
    )

    fun handlePacket(packet: ByteArray) {
        if (!PacketUtil.isIpv4(packet)) return
        if (!EmulatorConfig.shouldProcessProtocol(6)) return  // TCP=6
        val ihl = PacketUtil.ihl(packet)
        if (packet.size < ihl + 20) return
        val src = PacketUtil.srcAddr(packet)
        val dst = PacketUtil.dstAddr(packet)
        val sport = PacketUtil.srcPort(packet, ihl)
        val dport = PacketUtil.dstPort(packet, ihl)
        val flags = PacketUtil.tcpFlags(packet, ihl)
        val seq = PacketUtil.readInt(packet, ihl + 4)
        val ack = PacketUtil.readInt(packet, ihl + 8)
        val payload = PacketUtil.tcpPayload(packet, ihl)
        val key = Key(src, sport, dst, dport)

        // Upload path emulation for non-empty / SYN
        if (payload.isNotEmpty() || (flags and FLAG_SYN) != 0) {
            if (EmulatorStats.upload.shouldDrop()) return
            if (!EmulatorStats.upload.consumeBandwidth(packet.size)) return
            EmulatorStats.upload.recordPass(packet.size)
        }

        val delay = EmulatorStats.upload.computeDelayMs()
        val action: () -> Unit = {
            try {
                if (delay > 0 && ((flags and FLAG_SYN) != 0 || payload.isNotEmpty())) {
                    Thread.sleep(delay)
                }
                process(key, src, sport, dst, dport, flags, seq, ack, payload)
            } catch (e: Exception) {
                Log.w(TAG, "TCP process: ${e.message}")
            }
            Unit
        }
        if (delay > 0) pool.execute(action) else action()
    }

    private fun process(
        key: Key,
        src: InetAddress,
        sport: Int,
        dst: InetAddress,
        dport: Int,
        flags: Int,
        seq: Int,
        ack: Int,
        payload: ByteArray,
    ) {
        if ((flags and FLAG_RST) != 0) {
            closeSession(key)
            return
        }

        var session = sessions[key]

        // SYN: open remote + reply SYN-ACK
        if ((flags and FLAG_SYN) != 0 && (flags and FLAG_ACK) == 0) {
            if (session != null) return
            try {
                val sock = Socket()
                vpn.protect(sock)
                sock.tcpNoDelay = true
                sock.connect(InetSocketAddress(dst, dport), 8000)
                val serverSeq = Random.nextInt(1, Int.MAX_VALUE / 2)
                val clientNext = seq + 1
                session = Session(
                    key, sock, sock.getInputStream(), sock.getOutputStream(),
                    AtomicInteger(clientNext), AtomicInteger(serverSeq),
                )
                sessions[key] = session
                // SYN-ACK to client
                injectTcp(
                    dst, src, dport, sport,
                    serverSeq, clientNext,
                    FLAG_SYN or FLAG_ACK,
                )
                session.serverSeq.set(serverSeq + 1)
                pool.execute { remoteReadLoop(session!!) }
            } catch (e: Exception) {
                Log.w(TAG, "TCP connect $dst:$dport failed: ${e.message}")
                // RST
                injectTcp(dst, src, dport, sport, 0, seq + 1, FLAG_RST or FLAG_ACK)
            }
            return
        }

        session ?: return
        if (session.closed) return

        // Client ACK after handshake / data
        if (payload.isNotEmpty()) {
            try {
                session.remoteOut.write(payload)
                session.remoteOut.flush()
                session.clientNextSeq.addAndGet(payload.size)
                // ACK to client
                injectTcp(
                    session.key.dst, session.key.src,
                    session.key.dport, session.key.sport,
                    session.serverSeq.get(), session.clientNextSeq.get(),
                    FLAG_ACK,
                )
            } catch (e: Exception) {
                Log.w(TAG, "TCP write remote: ${e.message}")
                closeSession(key)
            }
        }

        if ((flags and FLAG_FIN) != 0) {
            try {
                session.clientNextSeq.incrementAndGet()
                injectTcp(
                    session.key.dst, session.key.src,
                    session.key.dport, session.key.sport,
                    session.serverSeq.get(), session.clientNextSeq.get(),
                    FLAG_ACK,
                )
                session.remote.shutdownOutput()
            } catch (_: Exception) {}
        }
    }

    private fun remoteReadLoop(session: Session) {
        val buf = ByteArray(32 * 1024)
        try {
            while (running.get() && !session.closed) {
                val n = session.remoteIn.read(buf)
                if (n < 0) break
                val data = buf.copyOf(n)

                if (EmulatorStats.download.shouldDrop()) continue
                if (!EmulatorStats.download.consumeBandwidth(data.size + 40)) continue
                val delay = EmulatorStats.download.computeDelayMs()
                EmulatorStats.download.recordPass(data.size)

                val inject: () -> Unit = {
                    try {
                        if (delay > 0) Thread.sleep(delay)
                        val seq = session.serverSeq.getAndAdd(data.size)
                        injectTcp(
                            session.key.dst, session.key.src,
                            session.key.dport, session.key.sport,
                            seq, session.clientNextSeq.get(),
                            FLAG_PSH or FLAG_ACK,
                            data,
                        )
                    } catch (e: Exception) {
                        Log.w(TAG, "TCP inject: ${e.message}")
                    }
                    Unit
                }
                if (delay > 0) pool.execute(inject) else inject()
            }
        } catch (e: Exception) {
            if (running.get() && !session.closed) Log.d(TAG, "remote read end: ${e.message}")
        } finally {
            // FIN to client
            try {
                val seq = session.serverSeq.getAndIncrement()
                injectTcp(
                    session.key.dst, session.key.src,
                    session.key.dport, session.key.sport,
                    seq, session.clientNextSeq.get(),
                    FLAG_FIN or FLAG_ACK,
                )
            } catch (_: Exception) {}
            closeSession(session.key)
        }
    }

    private fun injectTcp(
        src: InetAddress, dst: InetAddress,
        sport: Int, dport: Int,
        seq: Int, ack: Int, flags: Int,
        payload: ByteArray = ByteArray(0),
    ) {
        val pkt = PacketUtil.buildTcpPacket(src, dst, sport, dport, seq, ack, flags, payload)
        synchronized(tunOut) {
            tunOut.write(pkt)
        }
    }

    private fun closeSession(key: Key) {
        val s = sessions.remove(key) ?: return
        s.closed = true
        try { s.remote.close() } catch (_: Exception) {}
    }

    fun shutdown() {
        sessions.keys.toList().forEach { closeSession(it) }
        pool.shutdownNow()
    }
}
