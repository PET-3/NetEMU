package com.netemu.netemu.emulator

object EmulatorStats {
    val upload = NetworkEmulator(EmulatorConfig.upload)
    val download = NetworkEmulator(EmulatorConfig.download)

    fun reset() {
        upload.resetStats()
        download.resetStats()
    }

    fun toMap(backend: String, iface: String, vpnActive: Boolean): Map<String, Any> {
        return mapOf(
            "uploadBytes" to upload.bytesPassed.get(),
            "downloadBytes" to download.bytesPassed.get(),
            "uploadSpeedBps" to 0.0,
            "downloadSpeedBps" to 0.0,
            "uploadPackets" to upload.packetsPassed.get(),
            "downloadPackets" to download.packetsPassed.get(),
            "randomLossCount" to (upload.randomLoss.get() + download.randomLoss.get()),
            "continuousLossCount" to (upload.continuousLoss.get() + download.continuousLoss.get()),
            "backend" to backend,
            "interfaceName" to iface,
            "vpnActive" to vpnActive,
        )
    }
}
