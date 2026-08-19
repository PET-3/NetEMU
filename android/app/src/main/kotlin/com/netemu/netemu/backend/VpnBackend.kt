package com.netemu.netemu.backend

import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.util.Log
import com.netemu.netemu.vpn.NetEmuVpnService

/**
 * VPN userspace proxy backend. No root required.
 * Actual start/stop is coordinated by MainActivity (permission + service lifecycle).
 */
class VpnBackend(private val context: Context) : Backend {
    override val id = BackendId.VPN.id
    override val priority = BackendId.VPN.priority

    @Volatile var active: Boolean = false
        private set

    override fun isAvailable(): Boolean = true

    override fun statusMessage(): String =
        if (NetEmuVpnService.instance != null) "VPN running"
        else "VPN available (requires system permission)"

    /**
     * Note: full start requires VpnService.prepare() from Activity.
     * This method only starts the service when permission is already granted.
     */
    override fun start(iface: String?): Boolean {
        return try {
            val prepare = VpnService.prepare(context)
            if (prepare != null) {
                Log.i(TAG, "VPN permission required")
                return false
            }
            val intent = Intent(context, NetEmuVpnService::class.java).apply {
                action = NetEmuVpnService.ACTION_START
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            active = true
            true
        } catch (e: Exception) {
            Log.e(TAG, "VPN start failed: ${e.message}")
            false
        }
    }

    override fun stop(iface: String?) {
        try {
            val intent = Intent(context, NetEmuVpnService::class.java).apply {
                action = NetEmuVpnService.ACTION_STOP
            }
            context.startService(intent)
        } catch (e: Exception) {
            Log.w(TAG, "VPN stop: ${e.message}")
        }
        active = false
    }

    override fun hotApply(iface: String?): Boolean {
        // EmulatorConfig is read live by proxies; no restart needed
        return active || NetEmuVpnService.instance != null
    }

    override fun healthCheck(): Boolean = NetEmuVpnService.instance != null

    fun markActive(v: Boolean) {
        active = v
    }

    companion object {
        private const val TAG = "NetEmuVpnBackend"
    }
}
