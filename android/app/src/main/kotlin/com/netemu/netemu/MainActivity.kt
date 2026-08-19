package com.netemu.netemu

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.netemu.netemu.backend.BackendManager
import com.netemu.netemu.backend.ShellBackend
import com.netemu.netemu.backend.ShizukuBackend
import com.netemu.netemu.emulator.EmulatorConfig
import com.netemu.netemu.emulator.EmulatorStats
import com.netemu.netemu.float.FloatWindowService
import com.netemu.netemu.vpn.NetEmuVpnService
import rikka.shizuku.Shizuku
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
    private var pendingStartArgs: Map<*, *>? = null
    private lateinit var backendManager: BackendManager
    private var currentIface: String? = null
    private var simulationRunning = false

    private val shizukuPermissionListener =
        Shizuku.OnRequestPermissionResultListener { requestCode, grantResult ->
            val granted = grantResult == PackageManager.PERMISSION_GRANTED
            Log.i(TAG, "Shizuku permission result: $granted")
            sendLog(if (granted) "Shizuku authorized" else "Shizuku permission denied")
            runOnUiThread {
                eventSink?.success(
                    mapOf(
                        "type" to "shizuku_permission",
                        "granted" to granted,
                    )
                )
            }
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        backendManager = BackendManager(this)

        try {
            Shizuku.addRequestPermissionResultListener(shizukuPermissionListener)
        } catch (e: Exception) {
            Log.w(TAG, "Shizuku listener: ${e.message}")
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "detectBackends" -> result.success(backendManager.detect())
                    "startSimulation" -> {
                        val args = call.arguments as? Map<*, *>
                        startSimulation(args, result)
                    }
                    "stopSimulation" -> {
                        stopSimulation()
                        result.success(true)
                    }
                    "getBackend" -> result.success(backendManager.activeBackendId)
                    "getInterfaces" -> result.success(ShellBackend.listInterfaces())
                    "updateConfig" -> {
                        val args = call.arguments as? Map<*, *>
                        applyConfig(args)
                        if (simulationRunning) {
                            backendManager.hotApply(currentIface)
                        }
                        result.success(true)
                    }
                    "getStatistics" -> result.success(
                        EmulatorStats.toMap(
                            backendManager.activeBackendId,
                            currentIface ?: ShellBackend.detectDefaultIface(),
                            NetEmuVpnService.instance != null,
                        )
                    )
                    "executeCommand" -> {
                        val cmd = (call.arguments as? Map<*, *>)?.get("command") as? String ?: ""
                        val r = if (backendManager.shizuku.isAvailable()) {
                            backendManager.shizuku.execViaShizuku(listOf(cmd))
                        } else {
                            ShellBackend.exec(cmd, useRoot = ShellBackend.isRootAvailable())
                        }
                        result.success(
                            mapOf(
                                "exitCode" to r.exitCode,
                                "stdout" to r.stdout,
                                "stderr" to r.stderr,
                            )
                        )
                    }
                    "requestVpnPermission" -> requestVpnPermission(result)
                    "getShizukuStatus" -> result.success(getShizukuStatusMap())
                    "requestShizukuPermission" -> {
                        backendManager.shizuku.requestPermission(ShizukuBackend.REQUEST_CODE)
                        result.success(true)
                    }
                    "isRootAvailable" -> result.success(ShellBackend.isRootAvailable())
                    "exportAdbCommands" -> {
                        result.success(backendManager.getAdbCommands(currentIface))
                    }
                    "switchBackend" -> {
                        val args = call.arguments as? Map<*, *>
                        val backend = args?.get("backend") as? String
                        applyConfig(args)
                        val (ok, id) = backendManager.switchBackend(backend, currentIface)
                        simulationRunning = ok
                        result.success(mapOf("ok" to ok, "backend" to id))
                    }
                    "healthCheck" -> result.success(backendManager.healthCheck())
                    "requestOverlayPermission" -> requestOverlayPermission(result)
                    "showControlFloat" -> {
                        val show = (call.arguments as? Map<*, *>)?.get("show") as? Boolean ?: false
                        showFloat(control = show, info = null, result)
                    }
                    "setNotificationEnabled" -> {
                        val en = (call.arguments as? Map<*, *>)?.get("enabled") as? Boolean ?: true
                        NetEmuVpnService.notificationEnabled = en
                        NetEmuVpnService.instance?.refreshNotification()
                        result.success(true)
                    }
                    "setHideFromRecents" -> {
                        val hide = (call.arguments as? Map<*, *>)?.get("hide") as? Boolean ?: false
                        if (Build.VERSION.SDK_INT >= 21) {
                            try {
                                val am = getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
                                am.appTasks.forEach { it.setExcludeFromRecents(hide) }
                            } catch (_: Exception) {}
                        }
                        result.success(true)
                    }
                    "showInfoFloat" -> {
                        val show = (call.arguments as? Map<*, *>)?.get("show") as? Boolean ?: false
                        showFloat(control = null, info = show, result)
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

    private fun getShizukuStatusMap(): Map<String, Any> {
        return mapOf(
            "installed" to backendManager.shizuku.isInstalled(),
            "running" to backendManager.shizuku.isRunning(),
            "authorized" to backendManager.shizuku.isAuthorized(),
            "message" to backendManager.shizuku.statusMessage(),
        )
    }

    private fun applyConfig(args: Map<*, *>?) {
        EmulatorConfig.applyFromMap(args)
        currentIface = args?.get("interfaceName") as? String
    }

    private fun startSimulation(args: Map<*, *>?, result: MethodChannel.Result) {
        applyConfig(args)
        EmulatorStats.reset()
        val requested = args?.get("backend") as? String ?: "auto"
        val resolved = backendManager.resolve(requested)

        when (resolved.id) {
            "vpn" -> {
                val intent = VpnService.prepare(this)
                if (intent != null) {
                    pendingStartResult = result
                    pendingStartArgs = args
                    startActivityForResult(intent, VPN_REQUEST_CODE)
                } else {
                    val (ok, id) = backendManager.start("vpn", currentIface)
                    simulationRunning = ok
                    result.success(ok)
                    if (ok) maybeShowFloats(args)
                    sendLog("VPN started")
                }
            }
            "adb" -> {
                val cmds = backendManager.getAdbCommands(currentIface)
                simulationRunning = false
                sendLog("ADB mode — run on PC:\n" + cmds.joinToString("\n"))
                result.success(false)
            }
            else -> {
                val (ok, id) = backendManager.start(resolved.id, currentIface)
                simulationRunning = ok
                sendLog("$id started: $ok")
                result.success(ok)
                if (ok) maybeShowFloats(args)
            }
        }
    }

    private fun maybeShowFloats(args: Map<*, *>?) {
        val showControl = args?.get("showControlFloat") as? Boolean ?: false
        val showInfo = args?.get("showInfoFloat") as? Boolean ?: false
        if (showControl && FloatWindowService.hasOverlayPermission(this)) {
            startService(Intent(this, FloatWindowService::class.java).apply {
                action = FloatWindowService.ACTION_SHOW_CONTROL
            })
        }
        if (showInfo && FloatWindowService.hasOverlayPermission(this)) {
            startService(Intent(this, FloatWindowService::class.java).apply {
                action = FloatWindowService.ACTION_SHOW_INFO
            })
        }
    }

    private fun stopSimulation() {
        backendManager.stop()
        try {
            startService(Intent(this, FloatWindowService::class.java).apply {
                action = FloatWindowService.ACTION_HIDE
            })
        } catch (_: Exception) {}
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

    private fun requestOverlayPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (Settings.canDrawOverlays(this)) {
                result.success(true)
            } else {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName"),
                )
                startActivity(intent)
                result.success(false)
            }
        } else {
            result.success(true)
        }
    }

    private fun showFloat(control: Boolean?, info: Boolean?, result: MethodChannel.Result) {
        if (!FloatWindowService.hasOverlayPermission(this)) {
            result.success(false)
            return
        }
        if (control == true) {
            startService(Intent(this, FloatWindowService::class.java).apply {
                action = FloatWindowService.ACTION_SHOW_CONTROL
            })
        } else if (control == false) {
            startService(Intent(this, FloatWindowService::class.java).apply {
                action = FloatWindowService.ACTION_HIDE
            })
        }
        if (info == true) {
            startService(Intent(this, FloatWindowService::class.java).apply {
                action = FloatWindowService.ACTION_SHOW_INFO
            })
        } else if (info == false && control == null) {
            startService(Intent(this, FloatWindowService::class.java).apply {
                action = FloatWindowService.ACTION_HIDE
            })
        }
        result.success(true)
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                val (ok, _) = backendManager.start("vpn", currentIface)
                simulationRunning = ok
                pendingStartResult?.success(ok)
                if (ok) maybeShowFloats(pendingStartArgs)
                sendLog("VPN service started after permission")
            } else {
                simulationRunning = false
                pendingStartResult?.success(false)
                sendLog("VPN permission denied")
            }
            pendingStartResult = null
            pendingStartArgs = null
        }
    }

    private fun startStatsEmitter() {
        executor.execute {
            while (eventSink != null) {
                try {
                    if (simulationRunning) {
                        backendManager.healthCheck()
                    }
                    val stats = EmulatorStats.toMap(
                        backendManager.activeBackendId,
                        currentIface ?: ShellBackend.detectDefaultIface(),
                        NetEmuVpnService.instance != null,
                    ).toMutableMap()
                    stats["type"] = "stats"
                    stats["running"] = simulationRunning
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
            eventSink?.success(mapOf("type" to "log", "message" to msg, "level" to "INFO"))
        }
    }

    override fun onDestroy() {
        try {
            Shizuku.removeRequestPermissionResultListener(shizukuPermissionListener)
        } catch (_: Exception) {}
        if (::backendManager.isInitialized) {
            backendManager.destroy()
        }
        super.onDestroy()
    }
}
