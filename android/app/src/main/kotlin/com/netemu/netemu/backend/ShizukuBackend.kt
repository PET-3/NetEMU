package com.netemu.netemu.backend

import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import rikka.shizuku.Shizuku
import java.io.BufferedReader
import java.io.InputStreamReader

/**
 * Shizuku backend: executes privileged shell commands via Shizuku API
 * without requiring full root on the device.
 *
 * Requires:
 * - Shizuku app installed and running
 * - User has granted permission to this app in Shizuku
 */
class ShizukuBackend(private val context: Context) : Backend {
    override val id = BackendId.SHIZUKU.id
    override val priority = BackendId.SHIZUKU.priority

    private var lastIface: String? = null
    @Volatile private var active = false

    private val binderReceivedListener = Shizuku.OnBinderReceivedListener {
        Log.i(TAG, "Shizuku binder received")
    }
    private val binderDeadListener = Shizuku.OnBinderDeadListener {
        Log.w(TAG, "Shizuku binder dead")
        active = false
    }

    init {
        try {
            Shizuku.addBinderReceivedListener(binderReceivedListener)
            Shizuku.addBinderDeadListener(binderDeadListener)
        } catch (e: Exception) {
            Log.w(TAG, "Shizuku listener setup: ${e.message}")
        }
    }

    override fun isAvailable(): Boolean {
        return try {
            if (!isShizukuInstalled()) return false
            if (!Shizuku.pingBinder()) return false
            Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
        } catch (e: Exception) {
            Log.d(TAG, "isAvailable: ${e.message}")
            false
        }
    }

    fun isInstalled(): Boolean = isShizukuInstalled()

    fun isRunning(): Boolean = try {
        isShizukuInstalled() && Shizuku.pingBinder()
    } catch (_: Exception) {
        false
    }

    fun isAuthorized(): Boolean = try {
        Shizuku.pingBinder() &&
            Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
    } catch (_: Exception) {
        false
    }

    /** Request user authorization. Call from UI thread / activity. */
    fun requestPermission(requestCode: Int = REQUEST_CODE) {
        try {
            if (Shizuku.isPreV11()) {
                // Pre-v11 uses different API; fall through to startUserService style not available
                Log.w(TAG, "Shizuku pre-v11: open Shizuku app to authorize")
                return
            }
            if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) {
                Shizuku.requestPermission(requestCode)
            }
        } catch (e: Exception) {
            Log.e(TAG, "requestPermission: ${e.message}")
        }
    }

    override fun statusMessage(): String {
        return when {
            !isInstalled() -> "Shizuku not installed"
            !isRunning() -> "Shizuku installed but not running — open Shizuku app"
            !isAuthorized() -> "Shizuku running — tap to authorize"
            else -> "Shizuku authorized"
        }
    }

    override fun start(iface: String?): Boolean {
        if (!isAvailable()) {
            Log.w(TAG, "Shizuku not available: ${statusMessage()}")
            return false
        }
        lastIface = iface
        val r = execViaShizuku(buildApplyCommands(iface))
        active = r.exitCode == 0
        Log.i(TAG, "Shizuku start: exit=${r.exitCode} stderr=${r.stderr}")
        return active
    }

    override fun stop(iface: String?) {
        if (isRunning() && isAuthorized()) {
            execViaShizuku(buildClearCommands(iface ?: lastIface))
        }
        active = false
        Log.i(TAG, "Shizuku stopped")
    }

    override fun hotApply(iface: String?): Boolean {
        if (!active || !isAvailable()) return false
        val r = execViaShizuku(buildApplyCommands(iface ?: lastIface))
        return r.exitCode == 0
    }

    override fun healthCheck(): Boolean = active && isAvailable()

    private fun isShizukuInstalled(): Boolean {
        val pm = context.packageManager
        return try {
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
    }

    private fun buildApplyCommands(iface: String?): List<String> {
        // Reuse ShellBackend logic but return command strings for Shizuku
        val dev = iface?.takeIf { it.isNotBlank() } ?: ShellBackend.detectDefaultIface()
        // applyTc already does clear + set; we invoke via shell under Shizuku
        return listOf("true") // placeholder; real apply uses ShellBackend path with Shizuku exec
    }

    private fun buildClearCommands(iface: String?): List<String> {
        val dev = iface?.takeIf { it.isNotBlank() } ?: "wlan0"
        return listOf("tc qdisc del dev $dev root 2>/dev/null || true")
    }

    /**
     * Execute shell via Shizuku.
     * Shizuku.newProcess is private in API 13.x public stubs — call via reflection.
     */
    fun execViaShizuku(commands: List<String>): ShellBackend.Result {
        if (commands.isEmpty()) return ShellBackend.Result(0, "", "")
        return try {
            val joined = commands.joinToString(" && ")
            val process = newShizukuProcess(arrayOf("sh", "-c", joined))
                ?: return ShellBackend.Result(-1, "", "Shizuku process is null (authorize Shizuku?)")
            val stdout = BufferedReader(InputStreamReader(process.inputStream)).readText()
            val stderr = BufferedReader(InputStreamReader(process.errorStream)).readText()
            val code = process.waitFor()
            ShellBackend.Result(code, stdout, stderr)
        } catch (e: Exception) {
            Log.e(TAG, "execViaShizuku: ${e.message}")
            ShellBackend.Result(-1, "", e.message ?: "error")
        }
    }

    /** Reflectively invoke Shizuku.newProcess (non-public in 13.x). */
    private fun newShizukuProcess(cmd: Array<String>): Process? {
        return try {
            val m = Shizuku::class.java.getDeclaredMethod(
                "newProcess",
                Array<String>::class.java,
                Array<String>::class.java,
                String::class.java,
            )
            m.isAccessible = true
            m.invoke(null, cmd, null, null) as? Process
        } catch (e: Exception) {
            Log.e(TAG, "newShizukuProcess: ${e.message}")
            null
        }
    }

    /** Apply tc using current EmulatorConfig via Shizuku. */
    fun applyTc(iface: String?): ShellBackend.Result {
        if (!isAvailable()) {
            return ShellBackend.Result(-1, "", statusMessage())
        }
        val dev = iface?.takeIf { it.isNotBlank() } ?: ShellBackend.detectDefaultIface()
        // Build same commands as ShellBackend but run under Shizuku
        // Clear first
        execViaShizuku(listOf("tc qdisc del dev $dev root 2>/dev/null || true"))
        // Use a helper that constructs the full apply script
        val script = ShellBackend.buildApplyScript(dev)
        if (script.isEmpty()) return ShellBackend.Result(0, "cleared", "")
        return execViaShizuku(listOf(script))
    }

    fun destroy() {
        try {
            Shizuku.removeBinderReceivedListener(binderReceivedListener)
            Shizuku.removeBinderDeadListener(binderDeadListener)
        } catch (_: Exception) {}
    }

    companion object {
        private const val TAG = "NetEmuShizuku"
        const val REQUEST_CODE = 0x1E21
    }
}
