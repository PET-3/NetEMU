package com.netemu.netemu.emulator

import java.util.concurrent.atomic.AtomicLong
import kotlin.math.ln
import kotlin.math.sqrt
import kotlin.random.Random

/**
 * Independent network condition simulator used by ALL backends.
 * Supports:
 * - Random loss
 * - Continuous (burst) loss: packet-count mode OR time-duration mode
 * - Latency + jitter (uniform or approximate normal distribution)
 * - Token-bucket bandwidth with optional blocking wait (no hard drop on rate limit)
 */
class NetworkEmulator(private val direction: DirectionParams) {

    // Packet-count continuous state
    private var contState = 0 // 0=pass phase, 1=drop phase
    private var contCounter = 0

    // Time-based continuous state
    private var timePhaseStartMs = 0L
    private var timeInDropPhase = false

    private var tokens = 0.0
    private var lastRefillNs = System.nanoTime()

    // For speed calculation
    private var lastBytes = 0L
    private var lastSpeedTs = System.currentTimeMillis()
    @Volatile
    var currentSpeedBps = 0.0
        private set

    val bytesPassed = AtomicLong(0)
    val packetsPassed = AtomicLong(0)
    val randomLoss = AtomicLong(0)
    val continuousLoss = AtomicLong(0)

    /** Returns true if packet should be dropped (loss models only). */
    fun shouldDrop(): Boolean {
        val passN = direction.continuousPass
        val dropN = direction.continuousDrop
        if (passN > 0 && dropN > 0) {
            return if (direction.continuousMode == "time") {
                shouldDropTimeMode(passN, dropN)
            } else {
                shouldDropPacketMode(passN, dropN)
            }
        }
        val loss = direction.lossPercent
        if (loss > 0 && Random.nextDouble() * 100.0 < loss) {
            randomLoss.incrementAndGet()
            return true
        }
        return false
    }

    private fun shouldDropPacketMode(passN: Int, dropN: Int): Boolean {
        if (contState == 0) {
            contCounter++
            if (contCounter >= passN) {
                contState = 1
                contCounter = 0
            }
            return false
        } else {
            contCounter++
            if (contCounter >= dropN) {
                contState = 0
                contCounter = 0
            }
            continuousLoss.incrementAndGet()
            return true
        }
    }

    private fun shouldDropTimeMode(passMs: Int, dropMs: Int): Boolean {
        val now = System.currentTimeMillis()
        if (timePhaseStartMs == 0L) {
            timePhaseStartMs = now
            timeInDropPhase = false
        }
        val elapsed = now - timePhaseStartMs
        if (!timeInDropPhase) {
            if (elapsed >= passMs) {
                timeInDropPhase = true
                timePhaseStartMs = now
            }
            return false
        } else {
            if (elapsed >= dropMs) {
                timeInDropPhase = false
                timePhaseStartMs = now
            }
            continuousLoss.incrementAndGet()
            return true
        }
    }

    /**
     * Delay in milliseconds to apply (0 = no extra delay).
     * Supports uniform jitter or approximate normal distribution when
     * DirectionParams.jitterDistribution == "normal".
     */
    fun computeDelayMs(): Long {
        val base = direction.delayMs
        val jitter = direction.jitterMs
        if (base <= 0 && jitter <= 0) return 0
        val j = if (jitter > 0) {
            if (direction.jitterDistribution == "normal") {
                // Box-Muller approx, clamp to ±3σ ≈ ±jitter
                val u1 = Random.nextDouble().coerceAtLeast(1e-12)
                val u2 = Random.nextDouble()
                val z = sqrt(-2.0 * ln(u1)) * kotlin.math.cos(2.0 * Math.PI * u2)
                (z * (jitter / 3.0)).toInt().coerceIn(-jitter, jitter)
            } else {
                Random.nextInt(-jitter, jitter + 1)
            }
        } else 0
        return (base + j).coerceAtLeast(0).toLong()
    }

    /**
     * Token-bucket bandwidth.
     * @param size bytes to consume
     * @param blockIfInsufficient if true, sleep until tokens available (stable rate, no spike drop)
     * @return true if allowed to pass (always true when blockIfInsufficient and kbps>0 after wait)
     */
    @Synchronized
    fun consumeBandwidth(size: Int, blockIfInsufficient: Boolean = true): Boolean {
        val kbps = direction.bandwidthKbps
        if (kbps <= 0) return true
        val rateBps = kbps * 1000.0 / 8.0
        val maxBurst = rateBps * 1.5 // small burst allowance

        fun refill() {
            val now = System.nanoTime()
            val elapsed = (now - lastRefillNs) / 1_000_000_000.0
            tokens = (tokens + rateBps * elapsed).coerceAtMost(maxBurst)
            lastRefillNs = now
        }

        refill()
        if (tokens >= size) {
            tokens -= size
            return true
        }
        if (!blockIfInsufficient) return false

        // Wait for enough tokens (capped to avoid indefinite block)
        val need = size - tokens
        val waitMs = ((need / rateBps) * 1000.0).toLong().coerceIn(1, 5000)
        try {
            Thread.sleep(waitMs)
        } catch (_: InterruptedException) {
            return false
        }
        refill()
        if (tokens >= size) {
            tokens -= size
            return true
        }
        // Still short after wait: allow with debt to avoid total stall
        tokens = (tokens - size).coerceAtLeast(-rateBps)
        return true
    }

    fun recordPass(size: Int) {
        bytesPassed.addAndGet(size.toLong())
        packetsPassed.incrementAndGet()
        updateSpeed()
    }

    private fun updateSpeed() {
        val now = System.currentTimeMillis()
        val dt = now - lastSpeedTs
        if (dt >= 1000) {
            val cur = bytesPassed.get()
            currentSpeedBps = (cur - lastBytes) * 1000.0 / dt
            lastBytes = cur
            lastSpeedTs = now
        }
    }

    fun resetStats() {
        bytesPassed.set(0)
        packetsPassed.set(0)
        randomLoss.set(0)
        continuousLoss.set(0)
        contState = 0
        contCounter = 0
        timePhaseStartMs = 0L
        timeInDropPhase = false
        tokens = 0.0
        lastRefillNs = System.nanoTime()
        lastBytes = 0
        lastSpeedTs = System.currentTimeMillis()
        currentSpeedBps = 0.0
    }
}
