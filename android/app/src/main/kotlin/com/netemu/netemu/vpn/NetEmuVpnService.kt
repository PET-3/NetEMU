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
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import kotlin.random.Random

/**
 * Real VpnService that creates a TUN interface and processes packets
 * with configurable delay, jitter, loss and bandwidth limiting.
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

        // Shared config (updated from MainActivity)
        @Volatile
        var uploadDelayMs = 0
        @Volatile
        var uploadJitterMs = 0
        @Volatile
        var uploadBandwidthKbps = 0
        @Volatile
        var uploadLossPercent = 0.0
        @Volatile
        var uploadContPass = 0
        @Volatile
        var uploadContDrop = 0

        @Volatile
        var downloadDelayMs = 0
        @Volatile
        var downloadJitterMs = 0
        @Volatile
        var downloadBandwidthKbps = 0
        @Volatile
        var downloadLossPercent = 0.0
        @Volatile
        var downloadContPass = 0
        @Volatile
        var downloadContDrop = 0

        // Stats
        val uploadBytes = AtomicLong(0)
        val downloadBytes = AtomicLong(0)
        val uploadPackets = AtomicLong(0)
        val downloadPackets = AtomicLong(0)
        val randomLossCount = AtomicLong(0)
        val continuousLossCount = AtomicLong(0)

        fun resetStats() {
            uploadBytes.set(0)
            downloadBytes.set(0)
            uploadPackets.set(0)
            downloadPackets.set(0)
            randomLossCount.set(0)
            continuousLossCount.set(0)
        }
    }

    private var vpnInterface: ParcelFileDescriptor? = null
    private val running = AtomicBoolean(false)
    private val executor = Executors.newCachedThreadPool()
    private val udpSocket = DatagramSocket()

    // Continuous loss state machines
    private var upContState = 0 // 0=pass phase, 1=drop phase
    private var upContCounter = 0
    private var downContState = 0
    private var downContCounter = 0

    // Simple bandwidth token buckets
    private var upTokens = 0L
    private var downTokens = 0L
    private var lastUpRefill = System.nanoTime()
    private var lastDownRefill = System.nanoTime()

    // Pending delayed packets
    data class DelayedPacket(
        val data: ByteArray,
        val releaseAt: Long,
        val isUpload: Boolean
    )

    private val delayQueue = LinkedBlockingQueue<DelayedPacket>()

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
        protect(udpSocket)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startVpn()
            ACTION_STOP -> stopVpn()
            ACTION_UPDATE -> applyConfigFromIntent(intent)
        }
        return START_STICKY
    }

    private fun applyConfigFromIntent(intent: Intent) {
        uploadDelayMs = intent.getIntExtra("uploadDelayMs", 0)
        uploadJitterMs = intent.getIntExtra("uploadJitterMs", 0)
        uploadBandwidthKbps = intent.getIntExtra("uploadBandwidthKbps", 0)
        uploadLossPercent = intent.getDoubleExtra("uploadLossPercent", 0.0)
        uploadContPass = intent.getIntExtra("uploadContPass", 0)
        uploadContDrop = intent.getIntExtra("uploadContDrop", 0)

        downloadDelayMs = intent.getIntExtra("downloadDelayMs", 0)
        downloadJitterMs = intent.getIntExtra("downloadJitterMs", 0)
        downloadBandwidthKbps = intent.getIntExtra("downloadBandwidthKbps", 0)
        downloadLossPercent = intent.getDoubleExtra("downloadLossPercent", 0.0)
        downloadContPass = intent.getIntExtra("downloadContPass", 0)
        downloadContDrop = intent.getIntExtra("downloadContDrop", 0)
        Log.i(TAG, "Config updated")
    }

    private fun startVpn() {
        if (running.get()) return
        resetStats()
        val builder = Builder()
            .setSession("NetEmu")
            .addAddress("10.0.0.2", 32)
            .addRoute("0.0.0.0", 0)
            .addDnsServer("8.8.8.8")
            .addDnsServer("1.1.1.1")
            .setMtu(1500)
            .setBlocking(true)

        // Exclude self to avoid loops
        try {
            builder.addDisallowedApplication(packageName)
        } catch (_: Exception) {}

        vpnInterface = builder.establish()
        if (vpnInterface == null) {
            Log.e(TAG, "Failed to establish VPN")
            stopSelf()
            return
        }

        running.set(true)
        startForeground(NOTIFICATION_ID, buildNotification())
        executor.execute { tunnelLoop() }
        executor.execute { delayWorker() }
        Log.i(TAG, "VPN started")
    }

    private fun stopVpn() {
        running.set(false)
        try {
            vpnInterface?.close()
        } catch (_: Exception) {}
        vpnInterface = null
        stopForeground(STOP_FOREGROUND_REMOVE) // API 24+
        stopSelf()
        Log.i(TAG, "VPN stopped")
    }

    private fun tunnelLoop() {
        val fd = vpnInterface ?: return
        val input = FileInputStream(fd.fileDescriptor)
        val output = FileOutputStream(fd.fileDescriptor)
        val buffer = ByteArray(32767)

        while (running.get()) {
            try {
                val length = input.read(buffer)
                if (length <= 0) {
                    Thread.sleep(1)
                    continue
                }
                val packet = buffer.copyOf(length)
                // Outbound (upload) from device
                processOutbound(packet, output)
            } catch (e: Exception) {
                if (running.get()) Log.e(TAG, "Tunnel error", e)
                break
            }
        }
    }

    private fun processOutbound(packet: ByteArray, output: FileOutputStream) {
        // Decide drop
        if (shouldDrop(true, packet.size)) {
            return
        }
        // Bandwidth
        if (!consumeBandwidth(true, packet.size)) {
            return
        }
        val delay = computeDelay(true)
        if (delay > 0) {
            delayQueue.offer(DelayedPacket(packet, System.currentTimeMillis() + delay, true))
        } else {
            forwardOutbound(packet)
        }
        uploadBytes.addAndGet(packet.size.toLong())
        uploadPackets.incrementAndGet()
    }

    private fun forwardOutbound(packet: ByteArray) {
        // Very simplified: parse IP header and send UDP/TCP via protected socket.
        // Full IP stack is complex; for a working demo we handle UDP and simple TCP SYN/ACK pass-through
        // using a basic userspace forwarder for UDP (most common for testing) and log others.
        if (packet.size < 20) return
        val version = (packet[0].toInt() shr 4) and 0x0F
        if (version != 4) return

        val ihl = (packet[0].toInt() and 0x0F) * 4
        if (packet.size < ihl) return
        val protocol = packet[9].toInt() and 0xFF
        val srcAddr = InetAddress.getByAddress(packet.copyOfRange(12, 16))
        val dstAddr = InetAddress.getByAddress(packet.copyOfRange(16, 20))

        when (protocol) {
            17 -> { // UDP
                if (packet.size < ihl + 8) return
                val srcPort = ((packet[ihl].toInt() and 0xFF) shl 8) or (packet[ihl + 1].toInt() and 0xFF)
                val dstPort = ((packet[ihl + 2].toInt() and 0xFF) shl 8) or (packet[ihl + 3].toInt() and 0xFF)
                val payload = packet.copyOfRange(ihl + 8, packet.size)
                try {
                    val dp = DatagramPacket(payload, payload.size, dstAddr, dstPort)
                    udpSocket.send(dp)
                    // Note: full bidirectional UDP mapping would need a port map + response injection.
                    // For production a complete TUN stack (like wireguard-go or custom) is needed.
                    // Here we demonstrate the simulation path; responses can be injected similarly.
                } catch (e: Exception) {
                    Log.w(TAG, "UDP forward fail: ${e.message}")
                }
            }
            1 -> { // ICMP - drop or simple echo for demo
                // skip
            }
            6 -> { // TCP - requires full stack; log for now
                Log.d(TAG, "TCP packet to $dstAddr (full TCP stack not in this minimal impl)")
            }
            else -> {}
        }
    }

    private fun delayWorker() {
        while (running.get()) {
            try {
                val item = delayQueue.poll(50, TimeUnit.MILLISECONDS) ?: continue
                val wait = item.releaseAt - System.currentTimeMillis()
                if (wait > 0) Thread.sleep(wait)
                if (item.isUpload) {
                    forwardOutbound(item.data)
                }
                // download path would write back to TUN
            } catch (_: InterruptedException) {
                break
            } catch (e: Exception) {
                Log.e(TAG, "Delay worker error", e)
            }
        }
    }

    private fun shouldDrop(isUpload: Boolean, size: Int): Boolean {
        val loss = if (isUpload) uploadLossPercent else downloadLossPercent
        val contPass = if (isUpload) uploadContPass else downloadContPass
        val contDrop = if (isUpload) uploadContDrop else downloadContDrop

        // Continuous loss state machine
        if (contPass > 0 && contDrop > 0) {
            if (isUpload) {
                if (upContState == 0) {
                    upContCounter++
                    if (upContCounter >= contPass) {
                        upContState = 1
                        upContCounter = 0
                    }
                    return false
                } else {
                    upContCounter++
                    if (upContCounter >= contDrop) {
                        upContState = 0
                        upContCounter = 0
                    }
                    continuousLossCount.incrementAndGet()
                    return true
                }
            } else {
                if (downContState == 0) {
                    downContCounter++
                    if (downContCounter >= contPass) {
                        downContState = 1
                        downContCounter = 0
                    }
                    return false
                } else {
                    downContCounter++
                    if (downContCounter >= contDrop) {
                        downContState = 0
                        downContCounter = 0
                    }
                    continuousLossCount.incrementAndGet()
                    return true
                }
            }
        }

        // Random loss
        if (loss > 0 && Random.nextDouble() * 100 < loss) {
            randomLossCount.incrementAndGet()
            return true
        }
        return false
    }

    private fun computeDelay(isUpload: Boolean): Long {
        val base = if (isUpload) uploadDelayMs else downloadDelayMs
        val jitter = if (isUpload) uploadJitterMs else downloadJitterMs
        if (base <= 0 && jitter <= 0) return 0
        val j = if (jitter > 0) Random.nextInt(-jitter, jitter + 1) else 0
        return (base + j).coerceAtLeast(0).toLong()
    }

    private fun consumeBandwidth(isUpload: Boolean, size: Int): Boolean {
        val kbps = if (isUpload) uploadBandwidthKbps else downloadBandwidthKbps
        if (kbps <= 0) return true
        val now = System.nanoTime()
        val rate = kbps * 1000L / 8 // bytes per second
        if (isUpload) {
            val elapsed = (now - lastUpRefill) / 1_000_000_000.0
            upTokens = (upTokens + (rate * elapsed).toLong()).coerceAtMost(rate)
            lastUpRefill = now
            if (upTokens >= size) {
                upTokens -= size
                return true
            }
            return false
        } else {
            val elapsed = (now - lastDownRefill) / 1_000_000_000.0
            downTokens = (downTokens + (rate * elapsed).toLong()).coerceAtMost(rate)
            lastDownRefill = now
            if (downTokens >= size) {
                downTokens -= size
                return true
            }
            return false
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "NetEmu Network Simulation",
                NotificationManager.IMPORTANCE_LOW
            )
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pi = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
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
        try {
            vpnInterface?.close()
        } catch (_: Exception) {}
        try {
            udpSocket.close()
        } catch (_: Exception) {}
        executor.shutdownNow()
        super.onDestroy()
    }
}
