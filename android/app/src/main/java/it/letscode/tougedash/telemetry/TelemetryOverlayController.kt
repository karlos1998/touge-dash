package it.letscode.tougedash.telemetry

import android.animation.ValueAnimator
import android.app.Service
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import it.letscode.tougedash.model.ConnectionState
import it.letscode.tougedash.model.TelemetryConnection
import it.letscode.tougedash.model.TelemetrySnapshot
import kotlin.math.abs
import kotlin.math.roundToInt

class TelemetryOverlayController(
    private val service: Service,
    private val visibilityChanged: (Boolean) -> Unit
) {
    private val windowManager = service.getSystemService(WindowManager::class.java)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var root: FrameLayout? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var mode = TelemetryOverlayPreferences.mode(service)
    private var latestSnapshot = TelemetrySnapshot()
    private var latestConnection = TelemetryConnection()
    private var edgeAnimator: ValueAnimator? = null

    val isVisible: Boolean get() = root != null

    fun show(): Boolean {
        if (!Settings.canDrawOverlays(service)) return false
        if (root != null) return true
        TelemetryOverlayPreferences.setEnabled(service, true)
        val position = TelemetryOverlayPreferences.position(service, dp(160))
        val view = FrameLayout(service).apply {
            elevation = dp(16).toFloat()
            clipToOutline = true
        }
        root = view
        layoutParams = createLayoutParams(position)
        rebuild()
        runCatching { windowManager.addView(view, layoutParams) }
            .onFailure {
                root = null
                layoutParams = null
                TelemetryOverlayPreferences.setEnabled(service, false)
                return false
            }
        clampAndPersist()
        visibilityChanged(true)
        return true
    }

    fun hide(persist: Boolean = true) {
        edgeAnimator?.cancel()
        edgeAnimator = null
        root?.let { runCatching { windowManager.removeView(it) } }
        root = null
        layoutParams = null
        if (persist) TelemetryOverlayPreferences.setEnabled(service, false)
        visibilityChanged(false)
    }

    fun toggle() {
        if (isVisible) hide() else show()
    }

    fun destroy() {
        hide(persist = false)
    }

    fun update(snapshot: TelemetrySnapshot, connection: TelemetryConnection) {
        latestSnapshot = snapshot
        latestConnection = connection
        mainHandler.post { renderValues() }
    }

    private fun createLayoutParams(position: TelemetryOverlayPosition) = WindowManager.LayoutParams(
        widthFor(mode),
        heightFor(mode),
        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
        PixelFormat.TRANSLUCENT
    ).apply {
        gravity = Gravity.TOP or Gravity.START
        x = position.x
        y = position.y
    }

    private fun rebuild() {
        val view = root ?: return
        view.removeAllViews()
        view.background = panelBackground(mode == TelemetryOverlayMode.COMPACT)
        if (mode == TelemetryOverlayMode.COMPACT) buildCompact(view) else buildExpanded(view)
        attachGestures(view)
        layoutParams?.let { params ->
            params.width = widthFor(mode)
            params.height = heightFor(mode)
            runCatching { windowManager.updateViewLayout(view, params) }
        }
        renderValues()
        clampAndPersist()
    }

    private fun buildCompact(container: FrameLayout) {
        val content = LinearLayout(service).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(5), dp(7), dp(5), dp(7))
        }
        content.addView(label("TOUGE", 8f, CYAN, Typeface.BOLD))
        content.addView(label("0.0k", 22f, Color.WHITE, Typeface.BOLD, RPM_ID))
        content.addView(label("0.00 bar", 9f, MINT, Typeface.BOLD, BOOST_ID))
        container.addView(content, FrameLayout.LayoutParams(-1, -1))
    }

    private fun buildExpanded(container: FrameLayout) {
        val content = LinearLayout(service).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(10), dp(14), dp(12))
        }
        val header = LinearLayout(service).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        header.addView(label("●", 12f, MINT, Typeface.BOLD, STATUS_DOT_ID))
        header.addView(label("  TOUGE DASH", 10f, CYAN, Typeface.BOLD), weighted())
        header.addView(label("—", 18f, MUTED, Typeface.BOLD, COLLAPSE_ID), fixed(42))
        header.addView(label("×", 20f, Color.WHITE, Typeface.NORMAL, CLOSE_ID), fixed(34))
        content.addView(header, LinearLayout.LayoutParams(-1, dp(32)))

        val hero = LinearLayout(service).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.BOTTOM
        }
        hero.addView(label("0", 38f, Color.WHITE, Typeface.BOLD, RPM_ID), weighted())
        hero.addView(label("RPM", 9f, MUTED, Typeface.BOLD).apply { setPadding(0, 0, dp(14), dp(5)) })
        hero.addView(label("0 km/h", 18f, CYAN, Typeface.BOLD, SPEED_ID).apply { gravity = Gravity.END })
        content.addView(hero, LinearLayout.LayoutParams(-1, dp(48)))

        val firstRow = LinearLayout(service).apply { orientation = LinearLayout.HORIZONTAL }
        firstRow.addView(metric("BOOST", BOOST_ID, CYAN), weighted())
        firstRow.addView(metric("AFR", AFR_ID, MINT), weighted())
        firstRow.addView(metric("OIL P", OIL_PRESSURE_ID, MINT), weighted())
        content.addView(firstRow, LinearLayout.LayoutParams(-1, dp(43)))

        val secondRow = LinearLayout(service).apply { orientation = LinearLayout.HORIZONTAL }
        secondRow.addView(metric("OIL TEMP", OIL_TEMP_ID, ORANGE), weighted())
        secondRow.addView(metric("COOLANT", COOLANT_ID, ICE), weighted())
        secondRow.addView(metric("TPS", THROTTLE_ID, Color.WHITE), weighted())
        content.addView(secondRow, LinearLayout.LayoutParams(-1, dp(43)))
        container.addView(content, FrameLayout.LayoutParams(-1, -1))
    }

    private fun metric(title: String, valueId: Int, color: Int) = LinearLayout(service).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER
        background = GradientDrawable().apply {
            cornerRadius = dp(9).toFloat()
            setColor(Color.argb(90, 18, 31, 39))
            setStroke(dp(1), Color.argb(24, 255, 255, 255))
        }
        val margin = dp(3)
        setPadding(margin, dp(4), margin, dp(4))
        addView(label(title, 7f, MUTED, Typeface.BOLD))
        addView(label("--", 14f, color, Typeface.BOLD, valueId))
    }

    private fun renderValues() {
        val view = root ?: return
        val snapshot = latestSnapshot
        if (mode == TelemetryOverlayMode.COMPACT) {
            view.findViewById<TextView>(RPM_ID)?.text = "%.1fk".format(snapshot.rpm / 1_000.0)
            view.findViewById<TextView>(BOOST_ID)?.text = "%.2f bar".format(snapshot.boostBar)
        } else {
            view.findViewById<TextView>(RPM_ID)?.text = snapshot.rpm.roundToInt().toString()
            view.findViewById<TextView>(SPEED_ID)?.text = "%.0f km/h".format(snapshot.speedKph)
            view.findViewById<TextView>(BOOST_ID)?.text = "%.2f bar".format(snapshot.boostBar)
            view.findViewById<TextView>(AFR_ID)?.text = "%.1f".format(snapshot.afr)
            view.findViewById<TextView>(OIL_PRESSURE_ID)?.text = "%.1f bar".format(snapshot.oilPressureBar)
            view.findViewById<TextView>(OIL_TEMP_ID)?.text = "%.0f°C".format(snapshot.oilTemperatureCelsius)
            view.findViewById<TextView>(COOLANT_ID)?.text = "%.0f°C".format(snapshot.coolantCelsius)
            view.findViewById<TextView>(THROTTLE_ID)?.text = "%.0f%%".format(snapshot.throttlePercent)
            view.findViewById<TextView>(STATUS_DOT_ID)?.setTextColor(
                if (latestConnection.state == ConnectionState.Connected && snapshot.isFresh) MINT else MUTED
            )
        }
        view.contentDescription = service.getString(
            it.letscode.tougedash.R.string.telemetry_hud_content_description,
            snapshot.rpm.roundToInt(),
            snapshot.boostBar,
            snapshot.oilTemperatureCelsius
        )
    }

    private fun attachGestures(view: View) {
        val touchSlop = ViewConfiguration.get(service).scaledTouchSlop
        var downRawX = 0f
        var downRawY = 0f
        var startX = 0
        var startY = 0
        var moved = false
        view.setOnTouchListener { touched, event ->
            val params = layoutParams ?: return@setOnTouchListener false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    edgeAnimator?.cancel()
                    downRawX = event.rawX
                    downRawY = event.rawY
                    startX = params.x
                    startY = params.y
                    moved = false
                    touched.animate().scaleX(.97f).scaleY(.97f).setDuration(80).start()
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downRawX
                    val dy = event.rawY - downRawY
                    if (abs(dx) > touchSlop || abs(dy) > touchSlop) moved = true
                    if (moved) {
                        params.x = startX + dx.roundToInt()
                        params.y = startY + dy.roundToInt()
                        clamp(params)
                        runCatching { windowManager.updateViewLayout(touched, params) }
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    touched.animate().scaleX(1f).scaleY(1f).setDuration(100).start()
                    if (moved) snapToEdge() else handleTap(event.x, event.y)
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    touched.animate().scaleX(1f).scaleY(1f).setDuration(100).start()
                    true
                }
                else -> false
            }
        }
    }

    private fun handleTap(x: Float, y: Float) {
        if (mode == TelemetryOverlayMode.COMPACT) {
            setMode(mode.toggled())
            return
        }
        if (y <= dp(44) && x >= widthFor(mode) - dp(43)) {
            hide()
        } else if (y <= dp(44) && x >= widthFor(mode) - dp(92)) {
            setMode(TelemetryOverlayMode.COMPACT)
        }
    }

    private fun setMode(value: TelemetryOverlayMode) {
        mode = value
        TelemetryOverlayPreferences.setMode(service, value)
        rebuild()
    }

    private fun snapToEdge() {
        val params = layoutParams ?: return
        val metrics = windowBounds()
        val margin = dp(10)
        val maximumX = (metrics.width() - params.width - margin).coerceAtLeast(margin)
        val target = if (params.x + params.width / 2 < metrics.width() / 2) margin else maximumX
        edgeAnimator?.cancel()
        edgeAnimator = ValueAnimator.ofInt(params.x, target).apply {
            duration = 180
            addUpdateListener {
                params.x = it.animatedValue as Int
                root?.let { view -> runCatching { windowManager.updateViewLayout(view, params) } }
            }
            doOnEnd { persistPosition() }
            start()
        }
    }

    private fun ValueAnimator.doOnEnd(block: () -> Unit) {
        addListener(object : android.animation.AnimatorListenerAdapter() {
            override fun onAnimationEnd(animation: android.animation.Animator) = block()
        })
    }

    private fun clampAndPersist() {
        layoutParams?.let {
            clamp(it)
            root?.let { view -> runCatching { windowManager.updateViewLayout(view, it) } }
        }
        persistPosition()
    }

    private fun clamp(params: WindowManager.LayoutParams) {
        val bounds = windowBounds()
        val margin = dp(8)
        params.x = params.x.coerceIn(margin, (bounds.width() - params.width - margin).coerceAtLeast(margin))
        params.y = params.y.coerceIn(margin, (bounds.height() - params.height - margin).coerceAtLeast(margin))
    }

    private fun persistPosition() {
        layoutParams?.let {
            TelemetryOverlayPreferences.setPosition(service, TelemetryOverlayPosition(it.x, it.y))
        }
    }

    @Suppress("DEPRECATION")
    private fun windowBounds(): Rect = if (android.os.Build.VERSION.SDK_INT >= 30) {
        windowManager.currentWindowMetrics.bounds
    } else {
        Rect(
            0,
            0,
            service.resources.displayMetrics.widthPixels,
            service.resources.displayMetrics.heightPixels
        )
    }

    private fun panelBackground(compact: Boolean) = GradientDrawable(
        GradientDrawable.Orientation.TL_BR,
        intArrayOf(Color.rgb(10, 25, 33), Color.rgb(3, 10, 14))
    ).apply {
        shape = if (compact) GradientDrawable.OVAL else GradientDrawable.RECTANGLE
        if (!compact) cornerRadius = dp(20).toFloat()
        setStroke(dp(1), Color.argb(115, 38, 215, 229))
    }

    private fun label(
        value: String,
        size: Float,
        color: Int,
        style: Int,
        id: Int = View.NO_ID
    ) = TextView(service).apply {
        this.id = id
        text = value
        textSize = size
        setTextColor(color)
        gravity = Gravity.CENTER
        typeface = Typeface.create("sans-serif", style)
        includeFontPadding = false
        maxLines = 1
    }

    private fun weighted() = LinearLayout.LayoutParams(0, -1, 1f)
    private fun fixed(width: Int) = LinearLayout.LayoutParams(dp(width), -1)
    private fun widthFor(value: TelemetryOverlayMode) = dp(if (value == TelemetryOverlayMode.COMPACT) 78 else 318)
    private fun heightFor(value: TelemetryOverlayMode) = dp(if (value == TelemetryOverlayMode.COMPACT) 78 else 188)
    private fun dp(value: Int) = (value * service.resources.displayMetrics.density).roundToInt()

    private companion object {
        const val CYAN = 0xFF26D7E5.toInt()
        const val MINT = 0xFF43E8A8.toInt()
        const val ORANGE = 0xFFFFA53D.toInt()
        const val ICE = 0xFF75CFFF.toInt()
        const val MUTED = 0xFF81939D.toInt()
        const val RPM_ID = 0x1001
        const val BOOST_ID = 0x1002
        const val SPEED_ID = 0x1003
        const val AFR_ID = 0x1004
        const val OIL_PRESSURE_ID = 0x1005
        const val OIL_TEMP_ID = 0x1006
        const val COOLANT_ID = 0x1007
        const val THROTTLE_ID = 0x1008
        const val STATUS_DOT_ID = 0x1009
        const val COLLAPSE_ID = 0x1010
        const val CLOSE_ID = 0x1011
    }
}
