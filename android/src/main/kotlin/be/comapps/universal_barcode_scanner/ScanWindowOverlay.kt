package be.comapps.universal_barcode_scanner

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.os.SystemClock
import android.provider.Settings
import android.util.AttributeSet
import android.view.View

/**
 * Draws the scan window over the camera preview: the surround dimmed, the
 * window outlined, and a line sweeping across it.
 *
 * The line's position is taken from the clock rather than moved a fixed step
 * per frame, so it sweeps at the same speed on a 60 Hz and a 120 Hz screen.
 * Everything it draws with is allocated once.
 */
class ScanWindowOverlay @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {

    private val density = context.resources.displayMetrics.density
    private val animate = animationsEnabled(context)

    private val dimPaint = Paint().apply { color = 0x80000000.toInt() }
    private val framePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xCCFFFFFF.toInt()
        style = Paint.Style.STROKE
        strokeWidth = 2 * density
    }
    private val linePaint = Paint().apply {
        color = Color.RED
        strokeWidth = 2 * density
    }
    private val window = RectF()

    private var square = true

    /** False for no window: nothing is drawn, and the whole view counts. */
    private var shown = true

    /**
     * Least time between two frames of the line, zero for every display
     * frame. Inside a platform view every frame of the line is a frame
     * Flutter has to composite, so the embedded view asks for fewer.
     */
    var frameIntervalMs = 0L

    /** Where the sweep's clock starts, moved on a resume so the line carries on. */
    private var sweepOrigin = 0L

    /** Where in the sweep the line stopped, while paused. */
    private var pausedAt = 0L

    /**
     * Holds the line where it is, for a view that has stopped reading, and
     * sets it off again from there.
     */
    var paused = false
        set(value) {
            if (field == value) return
            val now = SystemClock.uptimeMillis()
            if (value) {
                pausedAt = (now - sweepOrigin) % SWEEP_MS
            } else {
                sweepOrigin = now - pausedAt
            }
            field = value
            invalidate()
        }

    /** Requested window size in pixels, or zero for the default. */
    private var requestedWidth = 0f
    private var requestedHeight = 0f

    /** Colour of the line, and whether the window is square, wide or absent. */
    fun configure(lineColor: Int, squareWindow: Boolean, hasWindow: Boolean) {
        linePaint.color = lineColor
        square = squareWindow
        shown = hasWindow
        updateWindow(width, height)
        invalidate()
    }

    /** A window of a given size, in logical pixels. Zero keeps the default. */
    fun setWindowSize(widthDp: Double, heightDp: Double) {
        requestedWidth = (widthDp * density).toFloat()
        requestedHeight = (heightDp * density).toFloat()
        updateWindow(width, height)
        invalidate()
    }

    /** The scan window in this view's coordinates, copied. */
    @Synchronized
    fun copyWindow(): RectF = RectF(window)

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        updateWindow(w, h)
    }

    @Synchronized
    private fun updateWindow(w: Int, h: Int) {
        if (w <= 0 || h <= 0) {
            window.setEmpty()
            return
        }
        if (!shown) {
            window.set(0f, 0f, w.toFloat(), h.toFloat())
            return
        }
        val boxWidth: Float
        val boxHeight: Float
        if (requestedWidth > 0 && requestedHeight > 0) {
            boxWidth = minOf(requestedWidth, w.toFloat())
            boxHeight = minOf(requestedHeight, h.toFloat())
        } else if (square) {
            boxWidth = minOf(minOf(w, h) * 0.75f, MAX_WINDOW_DP * density)
            boxHeight = boxWidth
        } else {
            boxWidth = minOf(w * 0.85f, MAX_WINDOW_DP * 1.3f * density)
            boxHeight = minOf(boxWidth * 0.5f, h * 0.8f)
        }
        val left = (w - boxWidth) / 2f
        val top = (h - boxHeight) / 2f
        window.set(left, top, left + boxWidth, top + boxHeight)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (!shown) return
        val box = copyWindow()
        if (box.isEmpty) return
        val w = width.toFloat()
        val h = height.toFloat()

        canvas.drawRect(0f, 0f, w, box.top, dimPaint)
        canvas.drawRect(0f, box.top, box.left, box.bottom, dimPaint)
        canvas.drawRect(box.right, box.top, w, box.bottom, dimPaint)
        canvas.drawRect(0f, box.bottom, w, h, dimPaint)
        canvas.drawRect(box, framePaint)

        val y = if (animate) {
            val elapsed = if (paused) {
                pausedAt
            } else {
                (SystemClock.uptimeMillis() - sweepOrigin) % SWEEP_MS
            }
            val phase = elapsed / SWEEP_MS.toFloat()
            val progress = if (phase < 0.5f) phase * 2 else (1 - phase) * 2
            box.top + progress * box.height()
        } else {
            box.centerY()
        }
        canvas.drawLine(box.left, y, box.right, y, linePaint)

        if (animate && !paused) {
            // Only while drawn: a hidden view is not asked to draw, so the
            // loop stops by itself and resumes with the next frame.
            if (frameIntervalMs > 0) {
                postInvalidateDelayed(frameIntervalMs)
            } else {
                postInvalidateOnAnimation()
            }
        }
    }

    private companion object {
        /** One sweep down and back up. */
        const val SWEEP_MS = 3000L

        /** Cap on the window's width, so a tablet does not get a huge one. */
        const val MAX_WINDOW_DP = 320

        /** Honours the system setting that turns animations off. */
        fun animationsEnabled(context: Context): Boolean = Settings.Global.getFloat(
            context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f,
        ) != 0f
    }
}
