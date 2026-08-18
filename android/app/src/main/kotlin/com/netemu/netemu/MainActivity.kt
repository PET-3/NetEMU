package com.netemu.netemu

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.netemu.netemu.vpn.NetEmuVpnService
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "NetEmuMain"
        private const val METHOD_CHANNEL = "com.netemu.netemu/method"
        private const val EVENT_CHANNEL = "com.netemu.netemu/events"
        private const val VPN_REQUEST_CODE = 1001
    }

    private var eventSink: EventChannel.EventSink? = null
    private val executor = Executors.newSingleThreadExecutor()
    private var pendingStartResult: MethodChannel.Result? = null
    private var currentConfig: Map<*, *>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "detectBackends" -> result.success(detectBackends())
                    "startSimulation" -> {
                        val args = call.arguments as? Map<*, *>
                        currentConfig = args
                        startSimulation(args, result)
                    }
                    "stopSimulation" -> {
                        stopSimulation()
                        result.success(true)
                    }
                    "getBackend" -> result.success(getActiveBackend())
                    "getInterfaces" -> result.success(getInterfaces())
                    "updateConfig" -> {
                        val args = call.arguments as? Map<*, *>
                        currentConfig = args
                        applyConfig(args)
                        result.success(true)
                    }
                    "getStatistics" -> result.success(getStatistics())
                    "executeCommand" -> {
                        val cmd = (call.arguments as? Map<*, *>)?.get("command") as? String ?: ""
                        result.success(executeShell(cmd))
                    }
                    "requestVpnPermission" -> requestVpnPermission(result)
                    "getShizukuStatus" -> result.success(getShizukuStatus())
                    "isRootAvailable" -> result.success(isRootAvailable())
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    startStatsEmitter()
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    private fun detectBackends(): Map<String, Any> {
        val root = isRootAvailable()
        val shizuku = getShizukuStatus()
        // ADB in-app is generally not available without special setup
        val adb = false
        return mapOf(
            "root" to root,
            "shizuku" to shizuku,
            "adb" to adb,
            "vpn" to true
        )
    }

    private fun isRootAvailable(): Boolean {
        return try {
            val p = Runtime.getRuntime().exec(arrayOf("su", "-c", "id"))
            val exit = p.waitFor()
            exit == 0
        } catch (e: Exception) {
            false
        }
    }

    private fun getShizukuStatus(): Map<String, Any> {
        // Without Shizuku dependency compiled in, we detect package presence only.
        // Full Shizuku API requires the library; we report install status.
        return try {
            val pm = packageManager
            val installed = try {
                pm.getPackageInfo("moe.shizuku.privileged.api", 0)
                true
            } catch (_: Exception) {
                try {
                    pm.getPackageInfo("rikka.shizuku", 0)
                    true
                } catch (_: Exception) {
                    false
                }
            }
            mapOf(
                "installed" to installed,
                "running" to installed,
                "authorized" to false, // needs Shizuku API binding
                "message" to if (installed) "Shizuku installed (authorize in Shizuku app)" else "Shizuku not installed"
            )
        } catch (e: Exception) {
            mapOf(
                "installed" to false,
                "running" to false,
                "authorized" to false,
                "message" to (e.message ?: "error")
            )
        }
    }

    private fun getActiveBackend(): String {
        return if (NetEmuVpnService.instance != null) "vpn" else "vpn"
    }

    private fun getInterfaces(): List<Map<String, Any?>> {
        val list = mutableListOf<Map<String, Any?>>()
        try {
            val p = Runtime.getRuntime().exec(arrayOf("sh", "-c", "ip -o addr show"))
            val reader = BufferedReader(InputStreamReader(p.inputStream))
            var line: String?
            while (reader.readLine().also { line = it } != null) {
                val parts = line!!.trim().split("\\s+".toRegex())
                if (parts.size >= 4) {
                    val name = parts[1]
                    if (name == "lo") continue
                    val type = when {
                        name.startsWith("wlan") || name.startsWith("wifi") -> "wifi"
                        name.startsWith("rmnet") || name.startsWith("ccmni") || name.startsWith("//") -> "mobile"
                        name.startsWith("tun") || name.startsWith("ppp") -> "vpn"
                        else -> "other"
                    }
                    val ip = parts.getOrNull(3)?.substringBefore("/")
                    list.add(mapOf(
                        "name" to name,
                        "type" to type,
                        "ip" to ip,
                        "isDefault" to (name.startsWith("wlan") || name.startsWith("rmnet"))
                    ))
                }
            }
            p.waitFor()
        } catch (e: Exception) {
            Log.w(TAG, "getInterfaces: ${e.message}")
        }
        if (list.isEmpty()) {
            list.add(mapOf("name" to "wlan0", "type" to "wifi", "ip" to null, "isDefault" to true))
        }
        return list
    }

    private fun executeShell(command: String): Map<String, Any> {
        return try {
            // Prefer root if available
            val useRoot = isRootAvailable()
            val cmd = if (useRoot) arrayOf("su", "-c", command) else arrayOf("sh", "-c", command)
            val p = Runtime.getRuntime().exec(cmd)
            val stdout = p.inputStream.bufferedReader().readText()
            val stderr = p.errorStream.bufferedReader().readText()
            val exit = p.waitFor()
            mapOf(
                "exitCode" to exit,
                "stdout" to stdout,
                "stderr" to stderr
            )
        } catch (e: Exception) {
            mapOf(
                "exitCode" to -1,
                "stdout" to "",
                "stderr" to (e.message ?: "error")
            )
        }
    }

    private fun applyConfig(args: Map<*, *>?) {
        if (args == null) return
        val upload = args["upload"] as? Map<*, *> ?: return
        val download = args["download"] as? Map<*, *> ?: return

        NetEmuVpnService.uploadDelayMs = (upload["delayMs"] as? Number)?.toInt() ?: 0
        NetEmuVpnService.uploadJitterMs = (upload["jitterMs"] as? Number)?.toInt() ?: 0
        NetEmuVpnService.uploadBandwidthKbps = (upload["bandwidthKbps"] as? Number)?.toInt() ?: 0
        NetEmuVpnService.uploadLossPercent = (upload["lossPercent"] as? Number)?.toDouble() ?: 0.0
        NetEmuVpnService.uploadContPass = (upload["continuousPass"] as? Number)?.toInt() ?: 0
        NetEmuVpnService.uploadContDrop = (upload["continuousDrop"] as? Number)?.toInt() ?: 0

        NetEmuVpnService.downloadDelayMs = (download["delayMs"] as? Number)?.toInt() ?: 0
        NetEmuVpnService.downloadJitterMs = (download["jitterMs"] as? Number)?.toInt() ?: 0
        NetEmuVpnService.downloadBandwidthKbps = (download["bandwidthKbps"] as? Number)?.toInt() ?: 0
        NetEmuVpnService.downloadLossPercent = (download["lossPercent"] as? Number)?.toDouble() ?: 0.0
        NetEmuVpnService.downloadContPass = (download["continuousPass"] as? Number)?.toInt() ?: 0
        NetEmuVpnService.downloadContDrop = (download["continuousDrop"] as? Number)?.toInt() ?: 0

        // Also try tc if root/shizuku
        val backend = args["backend"] as? String ?: "auto"
        if (backend == "root" || (backend == "auto" && isRootAvailable())) {
            applyTc(args)
        }
    }

    private fun applyTc(args: Map<*, *>) {
        val iface = (args["interfaceName"] as? String) ?: detectDefaultIface()
        val upload = args["upload"] as? Map<*, *> ?: return
        val delay = (upload["delayMs"] as? Number)?.toInt() ?: 0
        val jitter = (upload["jitterMs"] as? Number)?.toInt() ?: 0
        val loss = (upload["lossPercent"] as? Number)?.toDouble() ?: 0.0

        // Clear existing
        executeShell("tc qdisc del dev $iface root 2>/dev/null")
        if (delay > 0 || jitter > 0 || loss > 0) {
            val parts = mutableListOf("tc qdisc add dev $iface root netem")
            if (delay > 0) {
                parts.add("delay ${delay}ms")
                if (jitter > 0) parts.add("${jitter}ms")
            }
            if (loss > 0) parts.add("loss ${loss}%")
            val cmd = parts.joinToString(" ")
            val res = executeShell(cmd)
            Log.i(TAG, "tc: $cmd -> ${res["exitCode"]}")
        }
        val bw = (upload["bandwidthKbps"] as? Number)?.toInt() ?: 0
        if (bw > 0) {
            // tbf rate
            val rate = if (bw >= 1024) "${bw / 1024}mbit" else "${bw}kbit"
            executeShell("tc qdisc add dev $iface root tbf rate $rate burst 32kbit latency 400ms")
        }
    }

    private fun detectDefaultIface(): String {
        return try {
            val p = Runtime.getRuntime().exec(arrayOf("sh", "-c", "ip route | grep default | head -1"))
            val line = p.inputStream.bufferedReader().readLine() ?: return "wlan0"
            p.waitFor()
            val parts = line.split("\\s+".toRegex())
            val idx = parts.indexOf("dev")
            if (idx >= 0 && idx + 1 < parts.size) parts[idx + 1] else "wlan0"
        } catch (_: Exception) {
            "wlan0"
        }
    }

    private fun startSimulation(args: Map<*, *>?, result: MethodChannel.Result) {
        applyConfig(args)
        val backend = args?.get("backend") as? String ?: "auto"
        val useRoot = backend == "root" || (backend == "auto" && isRootAvailable())
        if (useRoot) {
            // Root mode uses tc only, no VPN needed
            result.success(true)
            sendLog("Started in Root/tc mode")
            return
        }
        // VPN path
        val intent = VpnService.prepare(this)
        if (intent != null) {
            pendingStartResult = result
            startActivityForResult(intent, VPN_REQUEST_CODE)
        } else {
            startVpnService()
            result.success(true)
        }
    }

    private fun startVpnService() {
        val intent = Intent(this, NetEmuVpnService::class.java).apply {
            action = NetEmuVpnService.ACTION_START
        }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        sendLog("VPN service started")
    }

    private fun stopSimulation() {
        // Stop VPN
        val intent = Intent(this, NetEmuVpnService::class.java).apply {
            action = NetEmuVpnService.ACTION_STOP
        }
        startService(intent)
        // Clear tc if any
        val iface = detectDefaultIface()
        executeShell("tc qdisc del dev $iface root 2>/dev/null")
        sendLog("Simulation stopped")
    }

    private fun requestVpnPermission(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            pendingStartResult = result
            startActivityForResult(intent, VPN_REQUEST_CODE)
        } else {
            result.success(true)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                startVpnService()
                pendingStartResult?.success(true)
            } else {
                pendingStartResult?.success(false)
                sendLog("VPN permission denied")
            }
            pendingStartResult = null
        }
    }

    private fun getStatistics(): Map<String, Any> {
        return mapOf(
            "uploadBytes" to NetEmuVpnService.uploadBytes.get(),
            "downloadBytes" to NetEmuVpnService.downloadBytes.get(),
            "uploadSpeedBps" to 0.0,
            "downloadSpeedBps" to 0.0,
            "uploadPackets" to NetEmuVpnService.uploadPackets.get(),
            "downloadPackets" to NetEmuVpnService.downloadPackets.get(),
            "randomLossCount" to NetEmuVpnService.randomLossCount.get(),
            "continuousLossCount" to NetEmuVpnService.continuousLossCount.get(),
            "backend" to getActiveBackend(),
            "interfaceName" to detectDefaultIface(),
            "vpnActive" to (NetEmuVpnService.instance != null)
        )
    }

    private fun startStatsEmitter() {
        executor.execute {
            while (eventSink != null) {
                try {
                    val stats = getStatistics().toMutableMap()
                    stats["type"] = "stats"
                    runOnUiThread {
                        eventSink?.success(stats)
                    }
                    Thread.sleep(1000)
                } catch (_: Exception) {
                    break
                }
            }
        }
    }

    private fun sendLog(msg: String) {
        runOnUiThread {
            eventSink?.success(mapOf("type" to "log", "message" to msg))
        }
    }
}
