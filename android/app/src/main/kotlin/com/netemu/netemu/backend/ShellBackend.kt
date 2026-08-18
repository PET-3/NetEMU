package com.netemu.netemu.backend

import android.util.Log
import com.netemu.netemu.emulator.EmulatorConfig
import java.io.BufferedReader
import java.io.InputStreamReader

/**
 * Shared shell helpers for Root / Shizuku / ADB-style tc netem.
 */
object ShellBackend {
    private const val TAG = "NetEmuShell"

    data class Result(val exitCode: Int, val stdout: String, val stderr: String)

    fun exec(command: String, useRoot: Boolean = false): Result {
        return try {
            val cmd = if (useRoot) arrayOf("su", "-c", command) else arrayOf("sh", "-c", command)
            val p = Runtime.getRuntime().exec(cmd)
            val stdout = p.inputStream.bufferedReader().readText()
            val stderr = p.errorStream.bufferedReader().readText()
            val code = p.waitFor()
            Result(code, stdout, stderr)
        } catch (e: Exception) {
            Result(-1, "", e.message ?: "error")
        }
    }

    fun isRootAvailable(): Boolean {
        val r = exec("id", useRoot = true)
        return r.exitCode == 0 && r.stdout.contains("uid=0")
    }

    fun detectDefaultIface(): String {
        val r = exec("ip route | grep default | head -1")
        val parts = r.stdout.trim().split(Regex("\\s+"))
        val idx = parts.indexOf("dev")
        return if (idx >= 0 && idx + 1 < parts.size) parts[idx + 1] else "wlan0"
    }

    fun listInterfaces(): List<Map<String, Any?>> {
        val list = mutableListOf<Map<String, Any?>>()
        val r = exec("ip -o addr show")
        for (line in r.stdout.lines()) {
            val parts = line.trim().split(Regex("\\s+"))
            if (parts.size < 4) continue
            val name = parts[1]
            if (name == "lo") continue
            val type = when {
                name.startsWith("wlan") || name.startsWith("wifi") -> "wifi"
                name.startsWith("rmnet") || name.startsWith("ccmni") -> "mobile"
                name.startsWith("tun") || name.startsWith("ppp") -> "vpn"
                else -> "other"
            }
            val ip = parts.getOrNull(3)?.substringBefore("/")
            list.add(mapOf("name" to name, "type" to type, "ip" to ip, "isDefault" to name.startsWith("wlan")))
        }
        if (list.isEmpty()) {
            list.add(mapOf("name" to "wlan0", "type" to "wifi", "ip" to null, "isDefault" to true))
        }
        return list
    }

    /**
     * Apply tc netem + optional tbf from EmulatorConfig (upload side on egress).
     */
    fun applyTc(iface: String?, useRoot: Boolean): Result {
        val dev = iface?.takeIf { it.isNotBlank() } ?: detectDefaultIface()
        val up = EmulatorConfig.upload
        // clear
        exec("tc qdisc del dev $dev root 2>/dev/null", useRoot)

        val delay = up.delayMs
        val jitter = up.jitterMs
        val loss = up.lossPercent
        val bw = up.bandwidthKbps

        if (delay <= 0 && jitter <= 0 && loss <= 0.0 && bw <= 0) {
            Log.i(TAG, "tc cleared on $dev")
            return Result(0, "cleared", "")
        }

        // Prefer netem for delay/loss; if bandwidth set, use HTB/TBF parent — simplify: netem only or tbf only
        if (bw > 0) {
            val rate = if (bw >= 1024) "${bw / 1024}mbit" else "${bw}kbit"
            val r1 = exec("tc qdisc add dev $dev root handle 1: tbf rate $rate burst 32kbit latency 400ms", useRoot)
            if (r1.exitCode != 0) return r1
            if (delay > 0 || jitter > 0 || loss > 0) {
                val parts = mutableListOf("tc qdisc add dev $dev parent 1:1 handle 10: netem")
                if (delay > 0) {
                    parts.add("delay ${delay}ms")
                    if (jitter > 0) parts.add("${jitter}ms")
                }
                if (loss > 0) parts.add("loss ${loss}%")
                return exec(parts.joinToString(" "), useRoot)
            }
            return r1
        }

        val parts = mutableListOf("tc qdisc add dev $dev root netem")
        if (delay > 0) {
            parts.add("delay ${delay}ms")
            if (jitter > 0) parts.add("${jitter}ms")
        }
        if (loss > 0) parts.add("loss ${loss}%")
        val cmd = parts.joinToString(" ")
        Log.i(TAG, "tc: $cmd")
        return exec(cmd, useRoot)
    }

    fun clearTc(iface: String?, useRoot: Boolean): Result {
        val dev = iface?.takeIf { it.isNotBlank() } ?: detectDefaultIface()
        return exec("tc qdisc del dev $dev root 2>/dev/null", useRoot)
    }

    /** Generate adb shell commands for PC-assisted mode (no fake execution). */
    fun exportAdbCommands(iface: String?): List<String> {
        val dev = iface?.takeIf { it.isNotBlank() } ?: "wlan0"
        val up = EmulatorConfig.upload
        val cmds = mutableListOf<String>()
        cmds.add("adb shell tc qdisc del dev $dev root 2>/dev/null")
        if (up.delayMs > 0 || up.jitterMs > 0 || up.lossPercent > 0) {
            val sb = StringBuilder("adb shell tc qdisc add dev $dev root netem")
            if (up.delayMs > 0) {
                sb.append(" delay ${up.delayMs}ms")
                if (up.jitterMs > 0) sb.append(" ${up.jitterMs}ms")
            }
            if (up.lossPercent > 0) sb.append(" loss ${up.lossPercent}%")
            cmds.add(sb.toString())
        }
        if (up.bandwidthKbps > 0) {
            val rate = if (up.bandwidthKbps >= 1024) "${up.bandwidthKbps / 1024}mbit" else "${up.bandwidthKbps}kbit"
            cmds.add("adb shell tc qdisc add dev $dev root tbf rate $rate burst 32kbit latency 400ms")
        }
        return cmds
    }
}
