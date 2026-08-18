package com.netemu.netemu.vpn

import android.net.VpnService
import android.util.Log
import com.netemu.netemu.emulator.EmulatorStats
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Full bidirectional UDP session mapping via protected DatagramSockets.
 */
class UdpProxy(
    private val vpn: VpnService,
    private val tunOut: FileOutputStream,
    private val running: AtomicBoolean,
) {
    companion object {
        private const val TAG = "NetEmuUdp"
        private const val IDLE_MS = 60_000L
    }

    data class Key(val src: InetAddress, val sport: Int, val dst: InetAddress, val dport: Int)

    private val sessions = ConcurrentHashMap<Key, Session>()
    private val pool: ExecutorService = Executors.newCachedThreadPool()

    private class Session(
        val socket: DatagramSocket,
        val clientAddr: InetAddress,
        val clientPort: Int,
        val remoteAddr: InetAddress,
        val remotePort: Int,
        @Volatile var lastActive: Long = System.currentTimeMillis(),
    )

    fun handlePacket(packet: ByteArray) {
        if (!PacketUtil.isIpv4(packet)) return
        val ihl = PacketUtil.ihl(packet)
        if (packet.size < ihl + 8) return
        val src = PacketUtil.srcAddr(packet)
        val dst = PacketUtil.dstAddr(packet)
        val sport = PacketUtil.srcPort(packet, ihl)
        val dport = PacketUtil.dstPort(packet, ihl)
        val payload = PacketUtil.udpPayload(packet, ihl)

        // Upload emulation
        if (EmulatorStats.upload.shouldDrop()) return
        if (!EmulatorStats.upload.consumeBandwidth(packet.size)) return
        val delay = EmulatorStats.upload.computeDelayMs()
        EmulatorStats.upload.recordPass(packet.size)

        val key = Key(src, sport, dst, dport)
        val session = sessions[key] ?: createSession(key, src, sport, dst, dport) ?: return

        val sendAction = {
            try {
                if (delay > 0) Thread.sleep(delay)
                val dp = DatagramPacket(payload, payload.size, dst, dport)
                session.socket.send(dp)
                session.lastActive = System.currentTimeMillis()
            } catch (e: Exception) {
                Log.w(TAG, "UDP send: ${e.message}")
                closeSession(key)
            }
        }
        if (delay > 0) pool.execute(sendAction) else sendAction()
    }

    private fun createSession(
        key: Key,
        client: InetAddress,
        cport: Int,
        remote: InetAddress,
        rport: Int,
    ): Session? {
        return try {
            val sock = DatagramSocket()
            vpn.protect(sock)
            sock.soTimeout = 3000
            val session = Session(sock, client, cport, remote, rport)
            sessions[key] = session
            pool.execute { receiveLoop(key, session) }
            session
        } catch (e: Exception) {
            Log.e(TAG, "createSession: ${e.message}")
            null
        }
    }

    private fun receiveLoop(key: Key, session: Session) {
        val buf = ByteArray(65535)
        while (running.get() && !session.socket.isClosed) {
            try {
                val dp = DatagramPacket(buf, buf.size)
                session.socket.receive(dp)
                session.lastActive = System.currentTimeMillis()
                val data = dp.data.copyOf(dp.length)

                // Download emulation
                if (EmulatorStats.download.shouldDrop()) continue
                if (!EmulatorStats.download.consumeBandwidth(data.size + 28)) continue
                val delay = EmulatorStats.download.computeDelayMs()
                EmulatorStats.download.recordPass(data.size)

                val inject = {
                    try {
                        if (delay > 0) Thread.sleep(delay)
                        val pkt = PacketUtil.buildUdpPacket(
                            session.remoteAddr,
                            session.clientAddr,
                            session.remotePort,
                            session.clientPort,
                            data,
                        )
                        synchronized(tunOut) {
                            tunOut.write(pkt)
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "UDP inject: ${e.message}")
                    }
                }
                if (delay > 0) pool.execute(inject) else inject()
            } catch (_: java.net.SocketTimeoutException) {
                if (System.currentTimeMillis() - session.lastActive > IDLE_MS) break
            } catch (e: Exception) {
                if (running.get()) Log.d(TAG, "UDP recv end: ${e.message}")
                break
            }
        }
        closeSession(key)
    }

    private fun closeSession(key: Key) {
        sessions.remove(key)?.socket?.close()
    }

    fun shutdown() {
        sessions.keys.toList().forEach { closeSession(it) }
        pool.shutdownNow()
    }
}
