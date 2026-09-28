package be.comapps.universal_barcode_scanner.camera;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.os.SystemClock;
import android.provider.Settings;
import android.util.AttributeSet;
import android.view.View;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

/**
 * Draws the scan window over the camera preview: the surround dimmed, the
 * window outlined, and a line sweeping across it.
 *
 * <p>The line's position is taken from the clock rather than moved a fixed
 * step per frame, so it sweeps at the same speed on a 60 Hz and a 120 Hz
 * screen. Everything it draws with is allocated once.
 */
public class ScannerOverlay extends View {

    /** One sweep down and back up. */
    private static final long SWEEP_MS = 3000;
    /** Cap on the window's width, so a tablet does not get a huge one. */
    private static final int MAX_WINDOW_DP = 320;

    private final Paint dimPaint = new Paint();
    private final Paint framePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint linePaint = new Paint();
    private final RectF window = new RectF();
    private final float density;
    private final boolean animate;

    private boolean square = true;
    /** Requested window size in pixels, or zero for the default. */
    private float requestedWidth;
    private float requestedHeight;

    public ScannerOverlay(Context context) {
        this(context, null);
    }

    public ScannerOverlay(Context context, @Nullable AttributeSet attrs) {
        super(context, attrs);
        density = context.getResources().getDisplayMetrics().density;
        animate = animationsEnabled(context);

        dimPaint.setColor(0x80000000);
        framePaint.setColor(0xCCFFFFFF);
        framePaint.setStyle(Paint.Style.STROKE);
        framePaint.setStrokeWidth(2 * density);
        linePaint.setColor(Color.RED);
        linePaint.setStrokeWidth(2 * density);
    }

    /** Colour of the line, and whether the window is square or wide. */
    public void configure(int lineColor, boolean squareWindow) {
        linePaint.setColor(lineColor);
        square = squareWindow;
        updateWindow(getWidth(), getHeight());
        invalidate();
    }

    /** A window of a given size, in logical pixels. Zero keeps the default. */
    public void setWindowSize(double widthDp, double heightDp) {
        requestedWidth = (float) (widthDp * density);
        requestedHeight = (float) (heightDp * density);
        updateWindow(getWidth(), getHeight());
        invalidate();
    }

    /** The scan window in this view's coordinates, copied. */
    @NonNull
    public synchronized RectF copyWindow() {
        return new RectF(window);
    }

    @Override
    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
        super.onSizeChanged(w, h, oldw, oldh);
        updateWindow(w, h);
    }

    private synchronized void updateWindow(int w, int h) {
        if (w <= 0 || h <= 0) {
            window.setEmpty();
            return;
        }
        float width;
        float height;
        if (requestedWidth > 0 && requestedHeight > 0) {
            width = Math.min(requestedWidth, w);
            height = Math.min(requestedHeight, h);
        } else if (square) {
            width = Math.min(Math.min(w, h) * 0.75f, MAX_WINDOW_DP * density);
            height = width;
        } else {
            width = Math.min(w * 0.85f, MAX_WINDOW_DP * 1.3f * density);
            height = Math.min(width * 0.5f, h * 0.8f);
        }
        float left = (w - width) / 2f;
        float top = (h - height) / 2f;
        window.set(left, top, left + width, top + height);
    }

    @Override
    protected void onDraw(@NonNull Canvas canvas) {
        super.onDraw(canvas);
        RectF box = copyWindow();
        if (box.isEmpty()) {
            return;
        }
        int w = getWidth();
        int h = getHeight();

        canvas.drawRect(0, 0, w, box.top, dimPaint);
        canvas.drawRect(0, box.top, box.left, box.bottom, dimPaint);
        canvas.drawRect(box.right, box.top, w, box.bottom, dimPaint);
        canvas.drawRect(0, box.bottom, w, h, dimPaint);
        canvas.drawRect(box, framePaint);

        float y;
        if (animate) {
            float phase = (SystemClock.uptimeMillis() % SWEEP_MS) / (float) SWEEP_MS;
            float progress = phase < 0.5f ? phase * 2 : (1 - phase) * 2;
            y = box.top + progress * box.height();
        } else {
            y = box.centerY();
        }
        canvas.drawLine(box.left, y, box.right, y, linePaint);

        if (animate) {
            // Only while drawn: a hidden view is not asked to draw, so the
            // loop stops by itself and resumes with the next frame.
            postInvalidateOnAnimation();
        }
    }

    /** Honours the system setting that turns animations off. */
    private static boolean animationsEnabled(Context context) {
        float scale = Settings.Global.getFloat(
                context.getContentResolver(), Settings.Global.ANIMATOR_DURATION_SCALE, 1f);
        return scale != 0f;
    }
}
