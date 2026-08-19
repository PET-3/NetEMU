package com.netemu.netemu.backend

import android.util.Log

/**
 * ADB backend does NOT execute commands on-device.
 * Ordinary apps cannot run `adb shell` with privilege.
 * This backend only exports ready-to-run commands for the user to execute on a PC.
 */
class AdbBackend : Backend {
    override val id = BackendId.ADB.id
    override val priority = BackendId.ADB.priority

    @Volatile private var lastCommands: List<String> = emptyList()

    override fun isAvailable(): Boolean = true // always "available" as export mode

    override fun statusMessage(): String =
        "ADB mode: export commands to run on PC (app cannot execute adb itself)"

    override fun start(iface: String?): Boolean {
        lastCommands = ShellBackend.exportAdbCommands(iface)
        Log.i(TAG, "ADB commands exported (${lastCommands.size} lines)")
        // Never marks simulation as "running" — user must run commands externally
        return false
    }

    override fun stop(iface: String?) {
        lastCommands = emptyList()
    }

    override fun hotApply(iface: String?): Boolean {
        lastCommands = ShellBackend.exportAdbCommands(iface)
        return false
    }

    fun getExportedCommands(): List<String> = lastCommands

    companion object {
        private const val TAG = "NetEmuAdb"
    }
}
