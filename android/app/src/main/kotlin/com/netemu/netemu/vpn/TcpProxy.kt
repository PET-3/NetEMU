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
 * Userspace TCP proxy with connection tracking.
 * Completes handshake with client over TUN, opens protected Socket to remote,
 * relays both directions with independent upload/download emulation.
 *
 * Improvements over basic version:
 * - Proper seq/ack tracking with AtomicInteger
 * - FIN / RST handling both directions
 * - Session idle timeout
 * - Rate-limit waits instead of hard drops
 * - Concurrent session count exposed for stats
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
        private const val IDLE_TIMEOUT_MS = 120_000L
        private const val CONNECT_TIMEOUT_MS = 10_000
    }

    data class Key(val src: InetAddress, val sport: Int, val dst: InetAddress, val dport: Int)

    private val sessions = ConcurrentHashMap<Key, Session>()
    private val pool: ExecutorService = Executors.newCachedThreadPool()
    private val cleanupScheduler = Executors.newSingleThreadScheduledExecutor()

    init {
        cleanupScheduler.scheduleAtFixedRate({
            cleanupIdleSessions()
        }, 30, 30, java.util.concurrent.TimeUnit.SECONDS)
    }

    private class Session(
        val key: Key,
        val remote: Socket,
        val remoteIn: InputStream,
        val remoteOut: OutputStream,
        var clientNextSeq: AtomicInteger,
        var serverSeq: AtomicInteger,
        @Volatile var closed: Boolean = false,
        @Volatile var lastActiveMs: Long = System.currentTimeMillis(),
        @Volatile var clientFinSeen: Boolean = false,
        @Volatile var serverFinSent: Boolean = false,
    )

    fun activeSessionCount(): Int = sessions.size

    fun handlePacket(packet: ByteArray) {
        if (!PacketUtil.isIpv4(packet)) return
        if (!EmulatorConfig.shouldProcessProtocol(6)) return
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

        // Upload path: loss + rate limit (wait) + delay
        if (payload.isNotEmpty() || (flags and FLAG_SYN) != 0) {
            if (EmulatorStats.upload.shouldDrop()) return
            if (!EmulatorStats.upload.consumeBandwidth(packet.size, blockIfInsufficient = true)) return
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
            closeSession(key, sendRst = false)
            return
        }

        var session = sessions[key]

        // SYN (no ACK): open remote + reply SYN-ACK
        if ((flags and FLAG_SYN) != 0 && (flags and FLAG_ACK) == 0) {
            if (session != null) {
                // Retransmitted SYN: re-send SYN-ACK
                injectTcp(
                    dst, src, dport, sport,
                    session.serverSeq.get() - 1, session.clientNextSeq.get(),
                    FLAG_SYN or FLAG_ACK,
                )
                return
            }
            try {
                val sock = Socket()
                vpn.protect(sock)
                sock.tcpNoDelay = true
                sock.keepAlive = true
                sock.soTimeout = 0
                sock.connect(InetSocketAddress(dst, dport), CONNECT_TIMEOUT_MS)
                val serverSeq = Random.nextInt(1, Int.MAX_VALUE / 4)
                val clientNext = seq + 1
                session = Session(
                    key, sock, sock.getInputStream(), sock.getOutputStream(),
                    AtomicInteger(clientNext), AtomicInteger(serverSeq),
                )
                sessions[key] = session
                injectTcp(
                    dst, src, dport, sport,
                    serverSeq, clientNext,
                    FLAG_SYN or FLAG_ACK,
                )
                session.serverSeq.set(serverSeq + 1)
                pool.execute { remoteReadLoop(session!!) }
            } catch (e: Exception) {
                Log.w(TAG, "TCP connect $dst:$dport failed: ${e.message}")
                injectTcp(dst, src, dport, sport, 0, seq + 1, FLAG_RST or FLAG_ACK)
            }
            return
        }

        session ?: return
        if (session.closed) return
        session.lastActiveMs = System.currentTimeMillis()

        // Data from client
        if (payload.isNotEmpty()) {
            try {
                session.remoteOut.write(payload)
                session.remoteOut.flush()
                session.clientNextSeq.addAndGet(payload.size)
                injectTcp(
                    session.key.dst, session.key.src,
                    session.key.dport, session.key.sport,
                    session.serverSeq.get(), session.clientNextSeq.get(),
                    FLAG_ACK,
                )
            } catch (e: Exception) {
                Log.w(TAG, "TCP write remote: ${e.message}")
                closeSession(key, sendRst = true)
            }
        }

        // Client FIN
        if ((flags and FLAG_FIN) != 0) {
            if (!session.clientFinSeen) {
                session.clientFinSeen = true
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
    }

    private fun remoteReadLoop(session: Session) {
        val buf = ByteArray(32 * 1024)
        try {
            while (running.get() && !session.closed) {
                val n = session.remoteIn.read(buf)
                if (n < 0) break
                val data = buf.copyOf(n)
                session.lastActiveMs = System.currentTimeMillis()

                if (EmulatorStats.download.shouldDrop()) continue
                if (!EmulatorStats.download.consumeBandwidth(data.size + 40, blockIfInsufficient = true)) continue
                val delay = EmulatorStats.download.computeDelayMs()
                EmulatorStats.download.recordPass(data.size)

                val inject: () -> Unit = {
                    try {
                        if (delay > 0) Thread.sleep(delay)
                        if (!session.closed) {
                            val seq = session.serverSeq.getAndAdd(data.size)
                            injectTcp(
                                session.key.dst, session.key.src,
                                session.key.dport, session.key.sport,
                                seq, session.clientNextSeq.get(),
                                FLAG_PSH or FLAG_ACK,
                                data,
                            )
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "TCP inject: ${e.message}")
                    }
                }
                if (delay > 0) pool.execute(inject) else inject()
            }
        } catch (e: Exception) {
            if (running.get() && !session.closed) Log.d(TAG, "remote read end: ${e.message}")
        } finally {
            if (!session.serverFinSent && !session.closed) {
                try {
                    val seq = session.serverSeq.getAndIncrement()
                    injectTcp(
                        session.key.dst, session.key.src,
                        session.key.dport, session.key.sport,
                        seq, session.clientNextSeq.get(),
                        FLAG_FIN or FLAG_ACK,
                    )
                    session.serverFinSent = true
                } catch (_: Exception) {}
            }
            closeSession(session.key, sendRst = false)
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
            try {
                tunOut.write(pkt)
            } catch (e: Exception) {
                Log.w(TAG, "tun write failed: ${e.message}")
            }
        }
    }

    private fun closeSession(key: Key, sendRst: Boolean) {
        val s = sessions.remove(key) ?: return
        s.closed = true
        if (sendRst) {
            try {
                injectTcp(
                    s.key.dst, s.key.src,
                    s.key.dport, s.key.sport,
                    s.serverSeq.get(), s.clientNextSeq.get(),
                    FLAG_RST or FLAG_ACK,
                )
            } catch (_: Exception) {}
        }
        try { s.remote.close() } catch (_: Exception) {}
    }

    private fun cleanupIdleSessions() {
        val now = System.currentTimeMillis()
        sessions.entries.removeIf { (_, s) ->
            if (s.closed || now - s.lastActiveMs > IDLE_TIMEOUT_MS) {
                s.closed = true
                try { s.remote.close() } catch (_: Exception) {}
                true
            } else false
        }
    }

    fun shutdown() {
        sessions.keys.toList().forEach { closeSession(it, sendRst = false) }
        pool.shutdownNow()
        cleanupScheduler.shutdownNow()
    }
}
