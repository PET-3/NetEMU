package com.netemu.netemu.emulator

/**
 * Shared simulation parameters for one direction (upload or download).
 * Hot-updatable from Flutter via MethodChannel.
 */
data class DirectionParams(
    @Volatile var delayMs: Int = 0,
    @Volatile var jitterMs: Int = 0,
    @Volatile var bandwidthKbps: Int = 0, // 0 = unlimited
    @Volatile var lossPercent: Double = 0.0,
    /** "packet" = count based, "time" = duration based (ms) */
    @Volatile var continuousMode: String = "packet",
    @Volatile var continuousPass: Int = 0,
    @Volatile var continuousDrop: Int = 0,
)

object EmulatorConfig {
    val upload = DirectionParams()
    val download = DirectionParams()

    /** "all" | "tcp" | "udp" */
    @Volatile
    var protocolFilter: String = "all"

    fun applyFromMap(args: Map<*, *>?) {
        if (args == null) return
        (args["upload"] as? Map<*, *>)?.let { applyDirection(upload, it) }
        (args["download"] as? Map<*, *>)?.let { applyDirection(download, it) }
        (args["protocol"] as? String)?.let {
            protocolFilter = when (it.lowercase()) {
                "tcp", "udp" -> it.lowercase()
                else -> "all"
            }
        }
    }

    private fun applyDirection(d: DirectionParams, m: Map<*, *>) {
        d.delayMs = (m["delayMs"] as? Number)?.toInt()?.coerceIn(0, 3000) ?: d.delayMs
        d.jitterMs = (m["jitterMs"] as? Number)?.toInt()?.coerceIn(0, 1000) ?: d.jitterMs
        d.bandwidthKbps = (m["bandwidthKbps"] as? Number)?.toInt()?.coerceAtLeast(0) ?: d.bandwidthKbps
        d.lossPercent = (m["lossPercent"] as? Number)?.toDouble()?.coerceIn(0.0, 100.0) ?: d.lossPercent
        d.continuousMode = (m["continuousMode"] as? String)?.lowercase()?.let {
            if (it == "time") "time" else "packet"
        } ?: d.continuousMode
        d.continuousPass = (m["continuousPass"] as? Number)?.toInt()?.coerceIn(0, 10000) ?: d.continuousPass
        d.continuousDrop = (m["continuousDrop"] as? Number)?.toInt()?.coerceIn(0, 10000) ?: d.continuousDrop
    }

    fun shouldProcessProtocol(protocol: Int): Boolean {
        return when (protocolFilter) {
            "tcp" -> protocol == 6
            "udp" -> protocol == 17
            else -> true // all, including ICMP etc for pass-through decisions
        }
    }
}
