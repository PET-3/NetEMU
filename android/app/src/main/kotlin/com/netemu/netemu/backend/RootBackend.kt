package com.netemu.netemu.backend

import android.util.Log

class RootBackend : Backend {
    override val id = BackendId.ROOT.id
    override val priority = BackendId.ROOT.priority

    private var lastIface: String? = null
    @Volatile private var active = false

    override fun isAvailable(): Boolean = ShellBackend.isRootAvailable()

    override fun statusMessage(): String =
        if (isAvailable()) "Root available (uid=0)" else "Root not available"

    override fun start(iface: String?): Boolean {
        lastIface = iface
        val dev = iface?.takeIf { it.isNotBlank() } ?: ShellBackend.detectDefaultIface()
        val script = ShellBackend.buildApplyScript(dev)
        val r = ShellBackend.exec(script, useRoot = true)
        active = r.exitCode == 0
        if (!active) {
            // fallback to legacy applyTc path
            val r2 = ShellBackend.applyTc(iface, useRoot = true)
            active = r2.exitCode == 0
            Log.i(TAG, "Root start fallback: exit=${r2.exitCode} ${r2.stderr}")
        } else {
            Log.i(TAG, "Root start: exit=${r.exitCode}")
        }
        return active
    }

    override fun stop(iface: String?) {
        ShellBackend.clearTc(iface ?: lastIface, useRoot = true)
        active = false
        Log.i(TAG, "Root stopped, qdisc cleared")
    }

    override fun hotApply(iface: String?): Boolean {
        if (!active) return false
        val r = ShellBackend.applyTc(iface ?: lastIface, useRoot = true)
        return r.exitCode == 0
    }

    override fun healthCheck(): Boolean {
        if (!active) return false
        return ShellBackend.isRootAvailable()
    }

    companion object {
        private const val TAG = "NetEmuRoot"
    }
}
