package com.netemu.netemu.float

import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import com.netemu.netemu.emulator.EmulatorConfig
import com.netemu.netemu.emulator.EmulatorStats
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Lightweight control + info floating windows.
 * Requires SYSTEM_ALERT_WINDOW permission.
 */
class FloatWindowService : Service() {

    companion object {
        private const val TAG = "NetEmuFloat"
        const val ACTION_SHOW_CONTROL = "com.netemu.netemu.FLOAT_CONTROL"
        const val ACTION_SHOW_INFO = "com.netemu.netemu.FLOAT_INFO"
        const val ACTION_HIDE = "com.netemu.netemu.FLOAT_HIDE"
        const val ACTION_UPDATE = "com.netemu.netemu.FLOAT_UPDATE"

        @Volatile
        var instance: FloatWindowService? = null

        fun hasOverlayPermission(ctx: Context): Boolean {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Settings.canDrawOverlays(ctx)
            } else true
        }
    }

    private var wm: WindowManager? = null
    private var controlView: View? = null
    private var infoView: View? = null
    private val running = AtomicBoolean(false)
    private val scheduler = Executors.newSingleThreadScheduledExecutor()
    private var infoTask: ScheduledFuture<*>? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW_CONTROL -> showControl()
            ACTION_SHOW_INFO -> showInfo()
            ACTION_HIDE -> hideAll()
            ACTION_UPDATE -> updateInfoText()
        }
        return START_STICKY
    }

    private fun layoutParams(width: Int, height: Int, y: Int = 200): WindowManager.LayoutParams {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE

        return WindowManager.LayoutParams(
            width, height,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 40
            this.y = y
        }
    }

    private fun showControl() {
        if (controlView != null) return
        if (!hasOverlayPermission(this)) {
            Log.w(TAG, "No overlay permission")
            return
        }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(0xCC1A1A2E.toInt())
            setPadding(24, 16, 24, 16)
        }

        val title = TextView(this).apply {
            text = "NetEmu 控制"
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 14f
        }
        root.addView(title)

        val status = TextView(this).apply {
            text = statusLine()
            setTextColor(0xFFB0BEC5.toInt())
            textSize = 12f
            tag = "status"
        }
        root.addView(status)

        val btnRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }

        fun makeBtn(label: String, action: () -> Unit): Button {
            return Button(this).apply {
                text = label
                textSize = 11f
                setOnClickListener { action() }
            }
        }

        // Quick delay presets
        btnRow.addView(makeBtn("0ms") {
            EmulatorConfig.upload.delayMs = 0
            EmulatorConfig.download.delayMs = 0
            updateStatus(root)
        })
        btnRow.addView(makeBtn("50ms") {
            EmulatorConfig.upload.delayMs = 50
            EmulatorConfig.download.delayMs = 40
            updateStatus(root)
        })
        btnRow.addView(makeBtn("150ms") {
            EmulatorConfig.upload.delayMs = 150
            EmulatorConfig.download.delayMs = 120
            updateStatus(root)
        })
        btnRow.addView(makeBtn("300ms") {
            EmulatorConfig.upload.delayMs = 300
            EmulatorConfig.download.delayMs = 300
            updateStatus(root)
        })
        root.addView(btnRow)

        val btnRow2 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        btnRow2.addView(makeBtn("丢包0%") {
            EmulatorConfig.upload.lossPercent = 0.0
            EmulatorConfig.download.lossPercent = 0.0
            updateStatus(root)
        })
        btnRow2.addView(makeBtn("丢包5%") {
            EmulatorConfig.upload.lossPercent = 5.0
            EmulatorConfig.download.lossPercent = 5.0
            updateStatus(root)
        })
        btnRow2.addView(makeBtn("丢包15%") {
            EmulatorConfig.upload.lossPercent = 15.0
            EmulatorConfig.download.lossPercent = 15.0
            updateStatus(root)
        })
        root.addView(btnRow2)

        val closeBtn = makeBtn("关闭浮窗") { hideControl() }
        root.addView(closeBtn)

        val lp = layoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            180
        )
        makeDraggable(root, lp)
        try {
            wm?.addView(root, lp)
            controlView = root
            running.set(true)
        } catch (e: Exception) {
            Log.e(TAG, "add control view failed", e)
        }
    }

    private fun showInfo() {
        if (infoView != null) return
        if (!hasOverlayPermission(this)) return

        val tv = TextView(this).apply {
            text = infoLine()
            setTextColor(0xFFE0E0E0.toInt())
            textSize = 11f
            setBackgroundColor(0xAA000000.toInt())
            setPadding(16, 10, 16, 10)
        }

        val lp = layoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            80
        )
        makeDraggable(tv, lp)
        try {
            wm?.addView(tv, lp)
            infoView = tv
            infoTask = scheduler.scheduleAtFixedRate({
                try {
                    updateInfoText()
                } catch (_: Exception) {}
            }, 1, 1, TimeUnit.SECONDS)
        } catch (e: Exception) {
            Log.e(TAG, "add info view failed", e)
        }
    }

    private fun updateInfoText() {
        val v = infoView as? TextView ?: return
        v.post { v.text = infoLine() }
    }

    private fun updateStatus(root: View) {
        val status = root.findViewWithTag<TextView>("status") ?: return
        status.text = statusLine()
    }

    private fun statusLine(): String {
        val u = EmulatorConfig.upload
        return "↑延迟${u.delayMs}ms 丢包${u.lossPercent}% 带宽${if (u.bandwidthKbps <= 0) "不限" else "${u.bandwidthKbps}kbps"}"
    }

    private fun infoLine(): String {
        val up = EmulatorStats.upload
        val down = EmulatorStats.download
        val upSpeed = formatSpeed(up.currentSpeedBps)
        val downSpeed = formatSpeed(down.currentSpeedBps)
        // 模拟路径流量，与系统全网测速口径不同
        return "模拟↑$upSpeed ↓$downSpeed | 丢${up.randomLoss.get() + down.randomLoss.get()}/连${up.continuousLoss.get() + down.continuousLoss.get()}"
    }

    private fun formatSpeed(bps: Double): String {
        return when {
            bps >= 1_000_000 -> String.format("%.1fMB/s", bps / 1_000_000)
            bps >= 1_000 -> String.format("%.1fKB/s", bps / 1_000)
            else -> String.format("%.0fB/s", bps)
        }
    }

    private fun makeDraggable(view: View, lp: WindowManager.LayoutParams) {
        var lastX = 0
        var lastY = 0
        view.setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    lastX = event.rawX.toInt()
                    lastY = event.rawY.toInt()
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX.toInt() - lastX
                    val dy = event.rawY.toInt() - lastY
                    lp.x += dx
                    lp.y += dy
                    lastX = event.rawX.toInt()
                    lastY = event.rawY.toInt()
                    try {
                        wm?.updateViewLayout(v, lp)
                    } catch (_: Exception) {}
                    true
                }
                else -> false
            }
        }
    }

    private fun hideControl() {
        controlView?.let {
            try { wm?.removeView(it) } catch (_: Exception) {}
        }
        controlView = null
    }

    private fun hideInfo() {
        infoTask?.cancel(false)
        infoTask = null
        infoView?.let {
            try { wm?.removeView(it) } catch (_: Exception) {}
        }
        infoView = null
    }

    fun hideAll() {
        hideControl()
        hideInfo()
        running.set(false)
        stopSelf()
    }

    override fun onDestroy() {
        hideAll()
        instance = null
        scheduler.shutdownNow()
        super.onDestroy()
    }
}
