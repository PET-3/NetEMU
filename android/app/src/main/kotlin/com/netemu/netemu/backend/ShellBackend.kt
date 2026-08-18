package com.netemu.netemu.backend

import android.util.Log
import com.netemu.netemu.emulator.EmulatorConfig

/**
 * Shared shell helpers for Root / Shizuku / ADB-style tc netem.
 * Improved qdisc layering: prefer HTB parent + netem child when both bandwidth and delay/loss needed.
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
            list.add(mapOf(
                "name" to name,
                "type" to type,
                "ip" to ip,
                "isDefault" to (name.startsWith("wlan") || name.startsWith("rmnet"))
            ))
        }
        if (list.isEmpty()) {
            list.add(mapOf("name" to "wlan0", "type" to "wifi", "ip" to null, "isDefault" to true))
        }
        return list
    }

    /**
     * Apply tc rules from EmulatorConfig (primarily upload/egress).
     * Strategy:
     * 1. Clear existing root qdisc
     * 2. If bandwidth > 0: HTB root + class, then netem as leaf (or tbf fallback)
     * 3. Else: plain netem root
     *
     * Note: On Android, true download (ingress) shaping usually requires ifb module
     * which is often unavailable without extra privileges. Document this limitation.
     */
    fun applyTc(iface: String?, useRoot: Boolean): Result {
        val dev = iface?.takeIf { it.isNotBlank() } ?: detectDefaultIface()
        val up = EmulatorConfig.upload
        val delay = up.delayMs
        val jitter = up.jitterMs
        val loss = up.lossPercent
        val bw = up.bandwidthKbps

        // Always clear first
        exec("tc qdisc del dev $dev root 2>/dev/null", useRoot)

        if (delay <= 0 && jitter <= 0 && loss <= 0.0 && bw <= 0) {
            return Result(0, "cleared", "")
        }

        if (bw > 0) {
            // Try HTB + netem leaf (more flexible)
            val rate = if (bw >= 1024) "${bw / 1024}mbit" else "${bw}kbit"
            val burst = if (bw >= 1024) "32kbit" else "16kbit"

            var r = exec(
                "tc qdisc add dev $dev root handle 1: htb default 10",
                useRoot
            )
            if (r.exitCode != 0) {
                // Fallback to TBF + netem
                Log.w(TAG, "HTB failed, fallback TBF: ${r.stderr}")
                r = exec(
                    "tc qdisc add dev $dev root handle 1: tbf rate $rate burst $burst latency 400ms",
                    useRoot
                )
                if (r.exitCode != 0) return r
                if (delay > 0 || jitter > 0 || loss > 0) {
                    val netem = buildNetemArgs(delay, jitter, loss)
                    return exec(
                        "tc qdisc add dev $dev parent 1:1 handle 10: netem $netem",
                        useRoot
                    )
                }
                return r
            }

            // HTB class
            r = exec(
                "tc class add dev $dev parent 1: classid 1:10 htb rate $rate ceil $rate burst $burst",
                useRoot
            )
            if (r.exitCode != 0) {
                Log.w(TAG, "HTB class failed: ${r.stderr}")
                // continue, try netem anyway
            }

            if (delay > 0 || jitter > 0 || loss > 0) {
                val netem = buildNetemArgs(delay, jitter, loss)
                return exec(
                    "tc qdisc add dev $dev parent 1:10 handle 10: netem $netem",
                    useRoot
                )
            }
            return Result(0, "htb only", "")
        }

        // No bandwidth limit: plain netem
        val netem = buildNetemArgs(delay, jitter, loss)
        val cmd = "tc qdisc add dev $dev root netem $netem"
        Log.i(TAG, "tc: $cmd")
        return exec(cmd, useRoot)
    }

    private fun buildNetemArgs(delay: Int, jitter: Int, loss: Double): String {
        val parts = mutableListOf<String>()
        if (delay > 0) {
            parts.add("delay ${delay}ms")
            if (jitter > 0) parts.add("${jitter}ms")
        }
        if (loss > 0) parts.add("loss ${loss}%")
        return parts.joinToString(" ")
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
        cmds.add("adb shell tc qdisc del dev $dev root 2>/dev/null || true")
        if (up.bandwidthKbps > 0) {
            val rate = if (up.bandwidthKbps >= 1024)
                "${up.bandwidthKbps / 1024}mbit"
            else
                "${up.bandwidthKbps}kbit"
            cmds.add("adb shell tc qdisc add dev $dev root handle 1: htb default 10")
            cmds.add("adb shell tc class add dev $dev parent 1: classid 1:10 htb rate $rate ceil $rate")
            if (up.delayMs > 0 || up.jitterMs > 0 || up.lossPercent > 0) {
                val netem = buildNetemArgs(up.delayMs, up.jitterMs, up.lossPercent)
                cmds.add("adb shell tc qdisc add dev $dev parent 1:10 handle 10: netem $netem")
            }
        } else if (up.delayMs > 0 || up.jitterMs > 0 || up.lossPercent > 0) {
            val netem = buildNetemArgs(up.delayMs, up.jitterMs, up.lossPercent)
            cmds.add("adb shell tc qdisc add dev $dev root netem $netem")
        }
        return cmds
    }
}
