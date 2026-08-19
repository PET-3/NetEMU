package com.netemu.netemu.backend

/**
 * Unified backend interface for network simulation.
 * Implementations: RootBackend, ShizukuBackend, AdbBackend, VpnBackend.
 */
interface Backend {
    val id: String
    val priority: Int  // higher = preferred (Root=100, Shizuku=80, Adb=40, Vpn=20)

    /** Whether this backend can be used right now. */
    fun isAvailable(): Boolean

    /** Human-readable status for UI. */
    fun statusMessage(): String

    /**
     * Start simulation with current EmulatorConfig.
     * @return true if started successfully
     */
    fun start(iface: String?): Boolean

    /** Stop and clean up (e.g. clear qdisc). */
    fun stop(iface: String?)

    /** Hot-apply config without full restart when possible. */
    fun hotApply(iface: String?): Boolean

    /** Health check while running. */
    fun healthCheck(): Boolean = true
}

enum class BackendId(val id: String, val priority: Int) {
    ROOT("root", 100),
    SHIZUKU("shizuku", 80),
    ADB("adb", 40),
    VPN("vpn", 20);

    companion object {
        fun from(s: String?): BackendId? =
            values().find { it.id.equals(s, ignoreCase = true) }
    }
}
