package com.netemu.netemu.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import com.netemu.netemu.MainActivity
import com.netemu.netemu.emulator.EmulatorConfig
import com.netemu.netemu.emulator.EmulatorStats
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * VpnService: TUN <-> TcpProxy / UdpProxy / ICMP with independent NetworkEmulator.
 * Full bidirectional path:
 *   App -> TUN -> proxy -> remote
 *   remote -> proxy -> TUN -> App
 * Zero extra delay when emulator delay=0.
 */
class NetEmuVpnService : VpnService() {

    companion object {
        const val TAG = "NetEmuVpn"
        const val ACTION_START = "com.netemu.netemu.START"
        const val ACTION_STOP = "com.netemu.netemu.STOP"
        const val ACTION_UPDATE = "com.netemu.netemu.UPDATE"
        const val ACTION_TOGGLE = "com.netemu.netemu.TOGGLE"
        const val NOTIFICATION_ID = 1001
        const val CHANNEL_ID = "netemu_vpn"
        @Volatile var notificationEnabled: Boolean = true

        @Volatile
        var instance: NetEmuVpnService? = null
    }

    private var vpnInterface: ParcelFileDescriptor? = null
    private val running = AtomicBoolean(false)
    private val executor = Executors.newSingleThreadExecutor()
    private val notifyScheduler = Executors.newSingleThreadScheduledExecutor()
    private var notifyTask: java.util.concurrent.ScheduledFuture<*>? = null
    private var tcpProxy: TcpProxy? = null
    private var udpProxy: UdpProxy? = null
    private var tunOut: FileOutputStream? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startVpn()
            ACTION_STOP -> stopVpn()
            ACTION_UPDATE -> { /* config applied via EmulatorConfig directly */ }
            ACTION_TOGGLE -> {
                if (running.get()) stopVpn() else startVpn()
            }
        }
        return START_STICKY
    }

    private fun startVpn() {
        if (running.get()) return
        EmulatorStats.reset()

        val builder = Builder()
            .setSession("NetEmu")
            .addAddress("10.8.0.2", 32)
            .addRoute("0.0.0.0", 0)
            .addDnsServer("8.8.8.8")
            .addDnsServer("1.1.1.1")
            .setMtu(1500)
            .setBlocking(true)

        try {
            builder.addDisallowedApplication(packageName)
        } catch (_: Exception) {}

        vpnInterface = builder.establish()
        if (vpnInterface == null) {
            Log.e(TAG, "Failed to establish VPN")
            stopSelf()
            return
        }

        val fd = vpnInterface!!
        val output = FileOutputStream(fd.fileDescriptor)
        tunOut = output
        tcpProxy = TcpProxy(this, output, running)
        udpProxy = UdpProxy(this, output, running)

        running.set(true)
        startForeground(NOTIFICATION_ID, buildNotification())
        notifyTask?.cancel(false)
        notifyTask = notifyScheduler.scheduleAtFixedRate({
            refreshNotification()
        }, 1, 1, java.util.concurrent.TimeUnit.SECONDS)
        executor.execute { tunnelLoop(fd) }
        Log.i(TAG, "VPN started (TCP+UDP+ICMP proxy)")
    }

    private fun stopVpn() {
        running.set(false)
        tcpProxy?.shutdown()
        udpProxy?.shutdown()
        tcpProxy = null
        udpProxy = null
        try { tunOut?.close() } catch (_: Exception) {}
        tunOut = null
        try { vpnInterface?.close() } catch (_: Exception) {}
        vpnInterface = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        Log.i(TAG, "VPN stopped")
    }

    private fun tunnelLoop(fd: ParcelFileDescriptor) {
        val input = FileInputStream(fd.fileDescriptor)
        val buffer = ByteArray(32767)
        while (running.get()) {
            try {
                val length = input.read(buffer)
                if (length <= 0) continue
                val packet = buffer.copyOf(length)
                if (!PacketUtil.isIpv4(packet)) continue
                when (PacketUtil.protocol(packet)) {
                    PacketUtil.PROTO_UDP -> udpProxy?.handlePacket(packet)
                    PacketUtil.PROTO_TCP -> tcpProxy?.handlePacket(packet)
                    PacketUtil.PROTO_ICMP -> handleIcmp(packet)
                }
            } catch (e: Exception) {
                if (running.get()) Log.e(TAG, "Tunnel error", e)
                break
            }
        }
    }

    /** Basic ICMP Echo Request -> Echo Reply so ping works. */
    private fun handleIcmp(packet: ByteArray) {
        if (!EmulatorConfig.shouldProcessProtocol(1)) return
        val ihl = PacketUtil.ihl(packet)
        if (PacketUtil.icmpType(packet, ihl) != 8) return // only Echo Request

        if (EmulatorStats.upload.shouldDrop()) return
        if (!EmulatorStats.upload.consumeBandwidth(packet.size, blockIfInsufficient = true)) return
        EmulatorStats.upload.recordPass(packet.size)

        val delayUp = EmulatorStats.upload.computeDelayMs()
        val reply = PacketUtil.buildIcmpEchoReply(packet) ?: return

        executor.execute {
            try {
                if (delayUp > 0) Thread.sleep(delayUp)
                if (EmulatorStats.download.shouldDrop()) return@execute
                if (!EmulatorStats.download.consumeBandwidth(reply.size, blockIfInsufficient = true)) return@execute
                val delayDown = EmulatorStats.download.computeDelayMs()
                EmulatorStats.download.recordPass(reply.size)
                if (delayDown > 0) Thread.sleep(delayDown)
                val out = tunOut ?: return@execute
                synchronized(out) {
                    out.write(reply)
                }
            } catch (e: Exception) {
                Log.w(TAG, "ICMP reply: ${e.message}")
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "NetEmu Network Simulation",
                NotificationManager.IMPORTANCE_LOW,
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pi = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val up = EmulatorStats.upload
        val down = EmulatorStats.download
        val tcpN = tcpProxy?.activeSessionCount() ?: 0
        val udpN = udpProxy?.activeSessionCount() ?: 0
        EmulatorStats.tcpSessions = tcpN
        EmulatorStats.udpSessions = udpN
        fun spd(bps: Double): String = when {
            bps >= 1_000_000 -> String.format("%.1fMB/s", bps / 1_000_000)
            bps >= 1_000 -> String.format("%.0fKB/s", bps / 1_000)
            else -> String.format("%.0fB/s", bps)
        }
        val body = "↑${spd(up.currentSpeedBps)} ↓${spd(down.currentSpeedBps)} · 丢包${up.randomLoss.get() + down.randomLoss.get()} · TCP:$tcpN UDP:$udpN"
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("NetEmu 运行中")
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pi)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .addAction(
                if (running.get()) android.R.drawable.ic_media_pause
                else android.R.drawable.ic_media_play,
                if (running.get()) "暂停" else "开始",
                PendingIntent.getService(
                    this, 2,
                    Intent(this, NetEmuVpnService::class.java).setAction(ACTION_TOGGLE),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
            .build()
    }

    fun refreshNotification() {
        if (!running.get() || !notificationEnabled) return
        try {
            val nm = getSystemService(NotificationManager::class.java)
            nm.notify(NOTIFICATION_ID, buildNotification())
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        notifyTask?.cancel(false)
        notifyTask = null
        try { notifyScheduler.shutdownNow() } catch (_: Exception) {}
        running.set(false)
        instance = null
        tcpProxy?.shutdown()
        udpProxy?.shutdown()
        try { tunOut?.close() } catch (_: Exception) {}
        try { vpnInterface?.close() } catch (_: Exception) {}
        executor.shutdownNow()
        super.onDestroy()
    }
}
