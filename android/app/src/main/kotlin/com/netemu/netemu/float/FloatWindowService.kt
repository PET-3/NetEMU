package com.netemu.netemu.float

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
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
import android.widget.ScrollView
import android.widget.TextView
import com.netemu.netemu.emulator.EmulatorConfig
import com.netemu.netemu.emulator.EmulatorStats
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

class FloatWindowService : Service() {

    companion object {
        private const val TAG = "NetEmuFloat"
        const val ACTION_SHOW_CONTROL = "com.netemu.netemu.FLOAT_CONTROL"
        const val ACTION_SHOW_INFO = "com.netemu.netemu.FLOAT_INFO"
        const val ACTION_HIDE = "com.netemu.netemu.FLOAT_HIDE"
        /** Flutter writes selected mode here for cross-process display */
        const val PREFS = "FlutterSharedPreferences"
        const val KEY_PROFILES = "flutter.netemu_profile_names"
        const val KEY_RUN_SOURCE = "flutter.netemu_float_run_source"
        const val KEY_PROFILE_NAME = "flutter.netemu_float_profile"

        @Volatile var instance: FloatWindowService? = null

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

    private fun prefs(): SharedPreferences =
        getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun profileNames(): List<String> {
        return try {
            // Flutter StringList or joined string
            val set = prefs().getStringSet(KEY_PROFILES, null)
            if (set != null && set.isNotEmpty()) return set.toList()
            val raw = prefs().getString(KEY_PROFILES, null) ?: return emptyList()
            if (raw.contains(",")) raw.split(",").map { it.trim() }.filter { it.isNotEmpty() }
            else if (raw.isNotEmpty()) listOf(raw)
            else emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }

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
            setPadding(dp(12f), dp(10f), dp(12f), dp(10f))
            minimumWidth = dp(168f)
        }

        val title = TextView(this).apply {
            text = "NetEmu ▾"
            setTextColor(0xFF90CAF9.toInt())
            textSize = 14f
            setPadding(0, 0, 0, dp(4f))
            setOnClickListener {
                controlExpanded = !controlExpanded
                text = if (controlExpanded) "NetEmu ▴" else "NetEmu ▾"
                rebuildControl(root)
            }
        }
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

    private fun chip(label: String, action: () -> Unit): TextView {
        return TextView(this).apply {
            text = label
            setTextColor(0xFFE3F2FD.toInt())
            textSize = 12f
            setBackgroundColor(0xFF37474F.toInt())
            setPadding(dp(10f), dp(6f), dp(10f), dp(6f))
            setOnClickListener { action() }
        }
    }

    private fun rebuildControl(root: LinearLayout) {
        while (root.childCount > 1) root.removeViewAt(1)
        if (!controlExpanded) return

        // 运行模式
        root.addView(TextView(this).apply {
            text = "运行模式"
            setTextColor(0xFFB0BEC5.toInt())
            textSize = 11f
            setPadding(0, dp(4f), 0, dp(4f))
        })

        val modeRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        modeRow.addView(chip("测试") {
            prefs().edit()
                .putString(KEY_RUN_SOURCE, "test")
                .apply()
            EmulatorConfig.upload.delayMs = EmulatorConfig.upload.delayMs // touch
            (root.getChildAt(0) as? TextView)?.text = "NetEmu · 测试 ▴"
        })
        modeRow.addView(TextView(this).apply { width = dp(6f) })
        root.addView(modeRow)

        // 配置列表
        root.addView(TextView(this).apply {
            text = "配置"
            setTextColor(0xFFB0BEC5.toInt())
            textSize = 11f
            setPadding(0, dp(8f), 0, dp(4f))
        })
        val names = profileNames()
        if (names.isEmpty()) {
            root.addView(TextView(this).apply {
                text = "（应用内选择或保存配置后显示）"
                setTextColor(0xFF78909C.toInt())
                textSize = 11f
            })
        } else {
            val scroll = ScrollView(this)
            val col = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
            for (n in names.take(8)) {
                col.addView(chip(n) {
                    prefs().edit()
                        .putString(KEY_RUN_SOURCE, "profile")
                        .putString(KEY_PROFILE_NAME, n)
                        .apply()
                    (root.getChildAt(0) as? TextView)?.text = "NetEmu · $n ▴"
                }.also {
                    it.setPadding(dp(10f), dp(6f), dp(10f), dp(6f))
                    val lp = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    )
                    lp.topMargin = dp(4f)
                    it.layoutParams = lp
                })
            }
            scroll.addView(col)
            scroll.layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(120f),
            )
            root.addView(scroll)
        }

        // 快捷延迟
        root.addView(TextView(this).apply {
            text = "快捷延迟"
            setTextColor(0xFFB0BEC5.toInt())
            textSize = 11f
            setPadding(0, dp(8f), 0, dp(4f))
        })
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        fun preset(ms: Int, loss: Double = -1.0) {
            row.addView(chip(if (ms == 0) "0" else "${ms}ms") {
                EmulatorConfig.upload.delayMs = ms
                EmulatorConfig.download.delayMs = (ms * 0.8).toInt()
                if (loss >= 0) {
                    EmulatorConfig.upload.lossPercent = loss
                    EmulatorConfig.download.lossPercent = loss
                }
            })
            row.addView(TextView(this).apply { width = dp(6f) })
        }
        preset(0, 0.0)
        preset(50)
        preset(150)
        row.addView(chip("丢10%") {
            EmulatorConfig.upload.lossPercent = 10.0
            EmulatorConfig.download.lossPercent = 10.0
        })
        root.addView(row)

        root.addView(chip("关闭浮窗") { hideControl() }.also {
            val lp = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
            lp.topMargin = dp(10f)
            it.layoutParams = lp
        })
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
            minimumWidth = dp(180f)
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
                        if (infoExpanded) (infoView as TextView).text = infoLineFull()
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
        val mode = prefs().getString(KEY_RUN_SOURCE, null)
        val pname = prefs().getString(KEY_PROFILE_NAME, null)
        val modeLabel = when (mode) {
            "test" -> "测试"
            "profile" -> (pname ?: "配置")
            else -> "-"
        }
        return buildString {
            append("[$modeLabel]\n")
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
