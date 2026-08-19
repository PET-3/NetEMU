package com.netemu.netemu.emulator

object EmulatorStats {
    val upload = NetworkEmulator(EmulatorConfig.upload)
    val download = NetworkEmulator(EmulatorConfig.download)

    @Volatile
    var tcpSessions: Int = 0
    @Volatile
    var udpSessions: Int = 0

    fun reset() {
        upload.resetStats()
        download.resetStats()
        tcpSessions = 0
        udpSessions = 0
    }

    fun toMap(backend: String, iface: String, vpnActive: Boolean): Map<String, Any> {
        return mapOf(
            "uploadBytes" to upload.bytesPassed.get(),
            "downloadBytes" to download.bytesPassed.get(),
            "uploadSpeedBps" to upload.currentSpeedBps,
            "downloadSpeedBps" to download.currentSpeedBps,
            "uploadPackets" to upload.packetsPassed.get(),
            "downloadPackets" to download.packetsPassed.get(),
            "randomLossCount" to (upload.randomLoss.get() + download.randomLoss.get()),
            "continuousLossCount" to (upload.continuousLoss.get() + download.continuousLoss.get()),
            "backend" to backend,
            "interfaceName" to iface,
            "vpnActive" to vpnActive,
            "protocolFilter" to EmulatorConfig.protocolFilter,
            "tcpSessions" to tcpSessions,
            "udpSessions" to udpSessions,
        )
    }
}
