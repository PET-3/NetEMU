package com.netemu.netemu.float

import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import com.netemu.netemu.emulator.EmulatorConfig
import com.netemu.netemu.emulator.EmulatorStats
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/**
 * 可最小化悬浮窗：默认紧凑，展开显示更完整信息与快捷预设。
 */
class FloatWindowService : Service() {

    companion object {
        private const val TAG = "NetEmuFloat"
        const val ACTION_SHOW_CONTROL = "com.netemu.netemu.FLOAT_CONTROL"
        const val ACTION_SHOW_INFO = "com.netemu.netemu.FLOAT_INFO"
        const val ACTION_HIDE = "com.netemu.netemu.FLOAT_HIDE"

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
    private var controlExpanded = false
    private var infoExpanded = true
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
        }
        return START_STICKY
    }

    private fun dp(v: Float): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, resources.displayMetrics).toInt()

    private fun baseLp(y: Int): WindowManager.LayoutParams {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        return WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dp(8f)
            this.y = y
        }
    }

    private fun showControl() {
        if (controlView != null) return
        if (!hasOverlayPermission(this)) return

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(0xF01A2332.toInt())
            setPadding(dp(10f), dp(8f), dp(10f), dp(8f))
            minimumWidth = dp(120f)
        }

        val title = TextView(this).apply {
            text = "NetEmu ▾"
            setTextColor(0xFF90CAF9.toInt())
            textSize = 13f
            setPadding(0, 0, 0, dp(4f))
            setOnClickListener {
                controlExpanded = !controlExpanded
                text = if (controlExpanded) "NetEmu ▴" else "NetEmu ▾"
                rebuildControl(root)
            }
        }
        root.tag = title
        root.addView(title)
        rebuildControl(root)

        val lp = baseLp(dp(56f))
        makeDraggable(root, lp)
        try {
            wm?.addView(root, lp)
            controlView = root
        } catch (e: Exception) {
            Log.e(TAG, "control add failed", e)
        }
    }

    private fun rebuildControl(root: LinearLayout) {
        while (root.childCount > 1) root.removeViewAt(1)
        if (!controlExpanded) {
            // 最小化：只保留标题条
            return
        }
        val cfg = EmulatorConfig
        val status = TextView(this).apply {
            text = "↑${cfg.upload.delayMs}ms ↓${cfg.download.delayMs}ms · 丢${cfg.upload.lossPercent.toInt()}%"
            setTextColor(0xFFB0BEC5.toInt())
            textSize = 11f
            setPadding(0, 0, 0, dp(6f))
        }
        root.addView(status)

        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        fun chip(label: String, action: () -> Unit): TextView {
            return TextView(this).apply {
                text = label
                setTextColor(0xFFE3F2FD.toInt())
                textSize = 12f
                setBackgroundColor(0xFF263238.toInt())
                setPadding(dp(8f), dp(4f), dp(8f), dp(4f))
                setOnClickListener {
                    action()
                    // 刷新状态行
                    if (root.childCount > 1) {
                        (root.getChildAt(1) as? TextView)?.text =
                            "↑${EmulatorConfig.upload.delayMs}ms ↓${EmulatorConfig.download.delayMs}ms · 丢${EmulatorConfig.upload.lossPercent.toInt()}%"
                    }
                }
            }
        }
        row.addView(chip("0ms") {
            EmulatorConfig.upload.delayMs = 0
            EmulatorConfig.download.delayMs = 0
            EmulatorConfig.upload.lossPercent = 0.0
            EmulatorConfig.download.lossPercent = 0.0
        })
        val space = { root: LinearLayout ->
            root.addView(TextView(this).apply { width = dp(6f) })
        }
        space(row)
        row.addView(chip("50ms") {
            EmulatorConfig.upload.delayMs = 50
            EmulatorConfig.download.delayMs = 40
        })
        space(row)
        row.addView(chip("150ms") {
            EmulatorConfig.upload.delayMs = 150
            EmulatorConfig.download.delayMs = 120
        })
        space(row)
        row.addView(chip("丢10%") {
            EmulatorConfig.upload.lossPercent = 10.0
            EmulatorConfig.download.lossPercent = 10.0
        })
        root.addView(row)

        val row2 = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(6f), 0, 0)
        }
        row2.addView(chip("关浮窗") { hideControl() })
        root.addView(row2)
    }

    private fun showInfo() {
        if (infoView != null) return
        if (!hasOverlayPermission(this)) return

        val tv = TextView(this).apply {
            text = infoLineFull()
            setTextColor(0xFFECEFF1.toInt())
            textSize = 12f
            setBackgroundColor(0xF0121A22.toInt())
            setPadding(dp(12f), dp(8f), dp(12f), dp(8f))
            minimumWidth = dp(160f)
            setOnClickListener {
                infoExpanded = !infoExpanded
                text = if (infoExpanded) infoLineFull() else "· NetEmu"
            }
        }
        val lp = baseLp(dp(12f))
        makeDraggable(tv, lp)
        try {
            wm?.addView(tv, lp)
            infoView = tv
            infoTask = scheduler.scheduleAtFixedRate({
                try {
                    (infoView as? TextView)?.post {
                        if (infoExpanded) {
                            (infoView as TextView).text = infoLineFull()
                        }
                    }
                } catch (_: Exception) {}
            }, 1, 1, TimeUnit.SECONDS)
        } catch (e: Exception) {
            Log.e(TAG, "info add failed", e)
        }
    }

    private fun infoLineFull(): String {
        val up = EmulatorStats.upload
        
        val down = EmulatorStats.download
        return buildString {
            append("↑${formatSpeed(up.currentSpeedBps)} ↓${formatSpeed(down.currentSpeedBps)}\n")
            append("延迟 ↑${EmulatorConfig.upload.delayMs} ↓${EmulatorConfig.download.delayMs} ms\n")
            append("丢包 随机${up.randomLoss.get() + down.randomLoss.get()} 连续${up.continuousLoss.get() + down.continuousLoss.get()}")
        }
    }

    private fun formatSpeed(bps: Double): String {
        return when {
            bps >= 1_000_000 -> String.format("%.1fM/s", bps / 1_000_000)
            bps >= 1_000 -> String.format("%.0fK/s", bps / 1_000)
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
                    false
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX.toInt() - lastX
                    val dy = event.rawY.toInt() - lastY
                    if (kotlin.math.abs(dx) > 4 || kotlin.math.abs(dy) > 4) {
                        lp.x += dx
                        lp.y += dy
                        lastX = event.rawX.toInt()
                        lastY = event.rawY.toInt()
                        try { wm?.updateViewLayout(v, lp) } catch (_: Exception) {}
                        return@setOnTouchListener true
                    }
                    false
                }
                else -> false
            }
        }
    }

    private fun hideControl() {
        controlView?.let { try { wm?.removeView(it) } catch (_: Exception) {} }
        controlView = null
        controlExpanded = false
    }

    private fun hideInfo() {
        infoTask?.cancel(false)
        infoTask = null
        infoView?.let { try { wm?.removeView(it) } catch (_: Exception) {} }
        infoView = null
    }

    fun hideAll() {
        hideControl()
        hideInfo()
        stopSelf()
    }

    override fun onDestroy() {
        hideAll()
        instance = null
        scheduler.shutdownNow()
        super.onDestroy()
    }
}
