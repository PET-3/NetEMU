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
            orientation = LinearLayout.HORIZONTAL
            setBackgroundColor(0xE6121A22.toInt())
            setPadding(dp(8f), dp(4f), dp(8f), dp(4f))
            minimumHeight = dp(28f)
        }

        val pill = TextView(this).apply {
            text = "N"
            setTextColor(0xFF90CAF9.toInt())
            textSize = 12f
            setPadding(dp(6f), 0, dp(6f), 0)
            setOnClickListener {
                controlExpanded = !controlExpanded
                rebuildControl(root)
            }
        }
        root.addView(pill)
        rebuildControl(root)

        val lp = baseLp(dp(48f))
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
        if (!controlExpanded) return
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        fun chip(label: String, action: () -> Unit): TextView {
            return TextView(this).apply {
                text = label
                setTextColor(0xFFE3F2FD.toInt())
                textSize = 11f
                setPadding(dp(6f), dp(2f), dp(6f), dp(2f))
                setOnClickListener { action() }
            }
        }
        row.addView(chip("0ms") {
            EmulatorConfig.upload.delayMs = 0
            EmulatorConfig.download.delayMs = 0
        })
        row.addView(chip("50") {
            EmulatorConfig.upload.delayMs = 50
            EmulatorConfig.download.delayMs = 40
        })
        row.addView(chip("150") {
            EmulatorConfig.upload.delayMs = 150
            EmulatorConfig.download.delayMs = 120
        })
        row.addView(chip("×") { hideControl() })
        root.addView(row)
    }

    private fun showInfo() {
        if (infoView != null) return
        if (!hasOverlayPermission(this)) return

        val tv = TextView(this).apply {
            text = infoLine()
            setTextColor(0xFFE0E0E0.toInt())
            textSize = 10f
            setBackgroundColor(0xCC000000.toInt())
            setPadding(dp(8f), dp(3f), dp(8f), dp(3f))
            minimumHeight = dp(24f)
            setOnClickListener {
                if ((text?.length ?: 0) > 2) text = "·" else text = infoLine()
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
                        val t = (infoView as TextView).text?.toString() ?: ""
                        if (t != "·") (infoView as TextView).text = infoLine()
                    }
                } catch (_: Exception) {}
            }, 1, 1, TimeUnit.SECONDS)
        } catch (e: Exception) {
            Log.e(TAG, "info add failed", e)
        }
    }

    private fun infoLine(): String {
        val up = EmulatorStats.upload
        val down = EmulatorStats.download
        return "↑${formatSpeed(up.currentSpeedBps)} ↓${formatSpeed(down.currentSpeedBps)} L${up.randomLoss.get() + down.randomLoss.get()}"
    }

    private fun formatSpeed(bps: Double): String {
        return when {
            bps >= 1_000_000 -> String.format("%.1fM", bps / 1_000_000)
            bps >= 1_000 -> String.format("%.0fK", bps / 1_000)
            else -> String.format("%.0f", bps)
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
