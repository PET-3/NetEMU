package com.netemu.netemu.backend

import android.content.Context
import android.util.Log
import java.util.concurrent.atomic.AtomicReference

/**
 * Central backend lifecycle manager.
 * - Detects available backends
 * - Selects best (Root > Shizuku > ADB > VPN) or forced mode
 * - Start / stop / hot-apply / switch with cleanup
 * - Health check and fallback
 */
class BackendManager(context: Context) {

    private val appContext = context.applicationContext
    val root = RootBackend()
    val shizuku = ShizukuBackend(appContext)
    val adb = AdbBackend()
    val vpn = VpnBackend(appContext)

    private val all: List<Backend> = listOf(root, shizuku, adb, vpn)

    private val current = AtomicReference<Backend?>(null)
    private var currentIface: String? = null

    val activeBackendId: String
        get() = current.get()?.id ?: "none"

    val isRunning: Boolean
        get() = current.get() != null

    fun detect(): Map<String, Any> {
        return mapOf(
            "root" to root.isAvailable(),
            "shizuku" to mapOf(
                "installed" to shizuku.isInstalled(),
                "running" to shizuku.isRunning(),
                "authorized" to shizuku.isAuthorized(),
                "message" to shizuku.statusMessage(),
            ),
            "adb" to true,
            "vpn" to true,
            "recommended" to selectBest().id,
        )
    }

    fun selectBest(): Backend {
        // Priority order: Root > Shizuku > VPN (ADB never auto-selected as primary runner)
        if (root.isAvailable()) return root
        if (shizuku.isAvailable()) return shizuku
        return vpn
    }

    fun resolve(requested: String?): Backend {
        val req = requested?.lowercase() ?: "auto"
        if (req == "auto") return selectBest()
        return when (req) {
            "root" -> if (root.isAvailable()) root else {
                Log.w(TAG, "Root requested but unavailable, fallback")
                selectBest()
            }
            "shizuku" -> if (shizuku.isAvailable()) shizuku else {
                Log.w(TAG, "Shizuku requested but unavailable, fallback")
                selectBest()
            }
            "adb" -> adb
            else -> vpn
        }
    }

    /**
     * Start simulation on the resolved backend.
     * Stops previous backend first if switching.
     */
    fun start(requestedBackend: String?, iface: String?): Pair<Boolean, String> {
        val target = resolve(requestedBackend)
        val prev = current.get()
        if (prev != null && prev.id != target.id) {
            Log.i(TAG, "Switching ${prev.id} -> ${target.id}")
            prev.stop(currentIface)
            current.set(null)
        }
        currentIface = iface
        val ok = when (target) {
            is ShizukuBackend -> {
                val r = target.applyTc(iface)
                val success = r.exitCode == 0
                if (success) current.set(target)
                success
            }
            is AdbBackend -> {
                target.start(iface)
                // ADB does not set current as "running"
                false
            }
            else -> {
                val success = target.start(iface)
                if (success) current.set(target)
                if (target is VpnBackend) target.markActive(success)
                success
            }
        }
        Log.i(TAG, "start backend=${target.id} ok=$ok")
        return ok to target.id
    }

    fun stop() {
        val b = current.getAndSet(null)
        b?.stop(currentIface)
        // Also ensure VPN service is stopped even if state drifted
        if (b !is VpnBackend) {
            // no-op
        } else {
            b.stop(currentIface)
        }
        // Always try clear root/shizuku qdisc if they might have left state
        try {
            if (root.isAvailable()) root.stop(currentIface)
        } catch (_: Exception) {}
        Log.i(TAG, "stopped")
    }

    fun hotApply(iface: String? = null): Boolean {
        val b = current.get() ?: return false
        val ifc = iface ?: currentIface
        return b.hotApply(ifc)
    }

    /**
     * Switch mode while running: stop old, start new.
     */
    fun switchBackend(requested: String?, iface: String?): Pair<Boolean, String> {
        stop()
        return start(requested, iface)
    }

    fun healthCheck(): Boolean {
        val b = current.get() ?: return false
        if (!b.healthCheck()) {
            Log.w(TAG, "Health check failed for ${b.id}, stopping")
            stop()
            return false
        }
        return true
    }

    fun getAdbCommands(iface: String?): List<String> =
        ShellBackend.exportAdbCommands(iface ?: currentIface)

    fun destroy() {
        stop()
        shizuku.destroy()
    }

    companion object {
        private const val TAG = "NetEmuBackendMgr"
    }
}
