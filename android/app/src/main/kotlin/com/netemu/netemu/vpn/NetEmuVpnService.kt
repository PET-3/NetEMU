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
import com.netemu.netemu.emulator.EmulatorStats
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * VpnService: TUN -> TcpProxy / UdpProxy with independent NetworkEmulator.
 * Zero extra delay when emulator delay=0.
 */
class NetEmuVpnService : VpnService() {

    companion object {
        const val TAG = "NetEmuVpn"
        const val ACTION_START = "com.netemu.netemu.START"
        const val ACTION_STOP = "com.netemu.netemu.STOP"
        const val ACTION_UPDATE = "com.netemu.netemu.UPDATE"
        const val NOTIFICATION_ID = 1001
        const val CHANNEL_ID = "netemu_vpn"

        @Volatile
        var instance: NetEmuVpnService? = null
    }

    private var vpnInterface: ParcelFileDescriptor? = null
    private val running = AtomicBoolean(false)
    private val executor = Executors.newSingleThreadExecutor()
    private var tcpProxy: TcpProxy? = null
    private var udpProxy: UdpProxy? = null

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
        tcpProxy = TcpProxy(this, output, running)
        udpProxy = UdpProxy(this, output, running)

        running.set(true)
        startForeground(NOTIFICATION_ID, buildNotification())
        executor.execute { tunnelLoop(fd) }
        Log.i(TAG, "VPN started (TCP+UDP proxy)")
    }

    private fun stopVpn() {
        running.set(false)
        tcpProxy?.shutdown()
        udpProxy?.shutdown()
        tcpProxy = null
        udpProxy = null
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
                    PacketUtil.PROTO_ICMP -> { /* skip ICMP for now */ }
                }
            } catch (e: Exception) {
                if (running.get()) Log.e(TAG, "Tunnel error", e)
                break
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
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("NetEmu")
            .setContentText("网络模拟运行中 · VPN")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        running.set(false)
        instance = null
        tcpProxy?.shutdown()
        udpProxy?.shutdown()
        try { vpnInterface?.close() } catch (_: Exception) {}
        executor.shutdownNow()
        super.onDestroy()
    }
}
