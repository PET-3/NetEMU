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
import com.netemu.netemu.backend.ShellBackend
import com.netemu.netemu.emulator.EmulatorConfig
import com.netemu.netemu.emulator.EmulatorStats
import com.netemu.netemu.vpn.NetEmuVpnService
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
    private var currentBackend = "vpn"
    private var currentIface: String? = null
    private var simulationRunning = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "detectBackends" -> result.success(detectBackends())
                    "startSimulation" -> {
                        val args = call.arguments as? Map<*, *>
                        startSimulation(args, result)
                    }
                    "stopSimulation" -> {
                        stopSimulation()
                        result.success(true)
                    }
                    "getBackend" -> result.success(currentBackend)
                    "getInterfaces" -> result.success(ShellBackend.listInterfaces())
                    "updateConfig" -> {
                        val args = call.arguments as? Map<*, *>
                        applyConfig(args)
                        // Hot-apply to active backend without restart
                        if (simulationRunning) {
                            hotApply(args)
                        }
                        result.success(true)
                    }
                    "getStatistics" -> result.success(
                        EmulatorStats.toMap(currentBackend, currentIface ?: "", NetEmuVpnService.instance != null)
                    )
                    "executeCommand" -> {
                        val cmd = (call.arguments as? Map<*, *>)?.get("command") as? String ?: ""
                        val r = ShellBackend.exec(cmd, useRoot = ShellBackend.isRootAvailable())
                        result.success(mapOf("exitCode" to r.exitCode, "stdout" to r.stdout, "stderr" to r.stderr))
                    }
                    "requestVpnPermission" -> requestVpnPermission(result)
                    "getShizukuStatus" -> result.success(getShizukuStatus())
                    "isRootAvailable" -> result.success(ShellBackend.isRootAvailable())
                    "exportAdbCommands" -> {
                        result.success(ShellBackend.exportAdbCommands(currentIface))
                    }
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
        val root = ShellBackend.isRootAvailable()
        val shizuku = getShizukuStatus()
        return mapOf(
            "root" to root,
            "shizuku" to shizuku,
            "adb" to false, // in-app adb not available; use exportAdbCommands
            "vpn" to true,
        )
    }

    private fun getShizukuStatus(): Map<String, Any> {
        return try {
            val pm = packageManager
            val installed = try {
                pm.getPackageInfo("moe.shizuku.privileged.api", 0); true
            } catch (_: Exception) {
                try { pm.getPackageInfo("rikka.shizuku", 0); true } catch (_: Exception) { false }
            }
            mapOf(
                "installed" to installed,
                "running" to installed,
                "authorized" to false,
                "message" to if (installed)
                    "Shizuku installed — open Shizuku app to authorize (API binding requires Shizuku lib)"
                else "Shizuku not installed",
            )
        } catch (e: Exception) {
            mapOf("installed" to false, "running" to false, "authorized" to false, "message" to (e.message ?: ""))
        }
    }

    private fun applyConfig(args: Map<*, *>?) {
        EmulatorConfig.applyFromMap(args)
        currentIface = args?.get("interfaceName") as? String
        val backend = args?.get("backend") as? String ?: "auto"
        if (backend != "auto") currentBackend = backend
    }

    private fun resolveBackend(requested: String?): String {
        val req = requested ?: "auto"
        if (req != "auto") return req
        if (ShellBackend.isRootAvailable()) return "root"
        val sh = getShizukuStatus()
        if (sh["authorized"] == true) return "shizuku"
        // adb is export-only
        return "vpn"
    }

    private fun startSimulation(args: Map<*, *>?, result: MethodChannel.Result) {
        applyConfig(args)
        val backend = resolveBackend(args?.get("backend") as? String)
        currentBackend = backend
        EmulatorStats.reset()

        when (backend) {
            "root" -> {
                val r = ShellBackend.applyTc(currentIface, useRoot = true)
                simulationRunning = r.exitCode == 0
                sendLog("Root/tc started: exit=${r.exitCode} ${r.stderr}")
                result.success(simulationRunning)
            }
            "shizuku" -> {
                // Without Shizuku API binding, fall back to non-root shell (usually fails for tc)
                val r = ShellBackend.applyTc(currentIface, useRoot = false)
                simulationRunning = r.exitCode == 0
                sendLog("Shizuku/shell tc: exit=${r.exitCode}. ${if (!simulationRunning) "Authorize Shizuku or use Root/VPN." else "ok"}")
                result.success(simulationRunning)
            }
            "adb" -> {
                val cmds = ShellBackend.exportAdbCommands(currentIface)
                simulationRunning = false
                sendLog("ADB mode: run these on PC:\n" + cmds.joinToString("\n"))
                result.success(false)
            }
            else -> {
                // VPN
                val intent = VpnService.prepare(this)
                if (intent != null) {
                    pendingStartResult = result
                    startActivityForResult(intent, VPN_REQUEST_CODE)
                } else {
                    startVpnService()
                    simulationRunning = true
                    result.success(true)
                }
            }
        }
    }

    private fun hotApply(args: Map<*, *>?) {
        when (currentBackend) {
            "root" -> ShellBackend.applyTc(currentIface, useRoot = true)
            "shizuku" -> ShellBackend.applyTc(currentIface, useRoot = false)
            "vpn" -> {
                // EmulatorConfig already updated; VPN proxies read it live
                val i = Intent(this, NetEmuVpnService::class.java).apply {
                    action = NetEmuVpnService.ACTION_UPDATE
                }
                startService(i)
            }
            "adb" -> sendLog("ADB commands updated:\n" + ShellBackend.exportAdbCommands(currentIface).joinToString("\n"))
        }
        sendLog("Config hot-applied (backend=$currentBackend)")
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
        currentBackend = "vpn"
        sendLog("VPN service started")
    }

    private fun stopSimulation() {
        when (currentBackend) {
            "root" -> ShellBackend.clearTc(currentIface, useRoot = true)
            "shizuku" -> ShellBackend.clearTc(currentIface, useRoot = false)
            else -> {
                val intent = Intent(this, NetEmuVpnService::class.java).apply {
                    action = NetEmuVpnService.ACTION_STOP
                }
                startService(intent)
            }
        }
        simulationRunning = false
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

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                startVpnService()
                simulationRunning = true
                pendingStartResult?.success(true)
            } else {
                simulationRunning = false
                pendingStartResult?.success(false)
                sendLog("VPN permission denied")
            }
            pendingStartResult = null
        }
    }

    private fun startStatsEmitter() {
        executor.execute {
            while (eventSink != null) {
                try {
                    val stats = EmulatorStats.toMap(
                        currentBackend,
                        currentIface ?: ShellBackend.detectDefaultIface(),
                        NetEmuVpnService.instance != null,
                    ).toMutableMap()
                    stats["type"] = "stats"
                    runOnUiThread { eventSink?.success(stats) }
                    Thread.sleep(1000)
                } catch (_: Exception) {
                    break
                }
            }
        }
    }

    private fun sendLog(msg: String) {
        Log.i(TAG, msg)
        runOnUiThread {
            eventSink?.success(mapOf("type" to "log", "message" to msg))
        }
    }
}
