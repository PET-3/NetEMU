package com.netemu.netemu.emulator

import java.util.concurrent.atomic.AtomicLong
import kotlin.random.Random

/**
 * Independent network condition simulator used by ALL backends.
 * Applies: random loss, continuous (burst) loss, latency+jitter, token-bucket bandwidth.
 */
class NetworkEmulator(private val direction: DirectionParams) {

    private var contState = 0 // 0=pass phase, 1=drop phase
    private var contCounter = 0

    private var tokens = 0.0
    private var lastRefillNs = System.nanoTime()

    val bytesPassed = AtomicLong(0)
    val packetsPassed = AtomicLong(0)
    val randomLoss = AtomicLong(0)
    val continuousLoss = AtomicLong(0)

    /** Returns true if packet should be dropped. */
    fun shouldDrop(): Boolean {
        val passN = direction.continuousPass
        val dropN = direction.continuousDrop
        if (passN > 0 && dropN > 0) {
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
        val loss = direction.lossPercent
        if (loss > 0 && Random.nextDouble() * 100.0 < loss) {
            randomLoss.incrementAndGet()
            return true
        }
        return false
    }

    /** Delay in milliseconds to apply (0 = no extra delay). */
    fun computeDelayMs(): Long {
        val base = direction.delayMs
        val jitter = direction.jitterMs
        if (base <= 0 && jitter <= 0) return 0
        val j = if (jitter > 0) Random.nextInt(-jitter, jitter + 1) else 0
        return (base + j).coerceAtLeast(0).toLong()
    }

    /**
     * Token-bucket bandwidth check.
     * @return true if [size] bytes may pass now.
     */
    @Synchronized
    fun consumeBandwidth(size: Int): Boolean {
        val kbps = direction.bandwidthKbps
        if (kbps <= 0) return true
        val now = System.nanoTime()
        val rateBps = kbps * 1000.0 / 8.0
        val elapsed = (now - lastRefillNs) / 1_000_000_000.0
        tokens = (tokens + rateBps * elapsed).coerceAtMost(rateBps)
        lastRefillNs = now
        if (tokens >= size) {
            tokens -= size
            return true
        }
        return false
    }

    fun recordPass(size: Int) {
        bytesPassed.addAndGet(size.toLong())
        packetsPassed.incrementAndGet()
    }

    fun resetStats() {
        bytesPassed.set(0)
        packetsPassed.set(0)
        randomLoss.set(0)
        continuousLoss.set(0)
        contState = 0
        contCounter = 0
        tokens = 0.0
        lastRefillNs = System.nanoTime()
    }
}
