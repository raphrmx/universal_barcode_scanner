package be.comapps.universal_barcode_scanner.camera;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.PorterDuff;
import android.graphics.PorterDuffXfermode;
import android.graphics.RectF;
import android.util.AttributeSet;
import android.view.View;

import be.comapps.universal_barcode_scanner.BarcodeCaptureActivity;
import be.comapps.universal_barcode_scanner.UniversalBarcodeScannerPlugin;
import be.comapps.universal_barcode_scanner.constants.AppConstants;
import be.comapps.universal_barcode_scanner.utils.AppUtil;

/**
 * Draws the scan window over the camera preview: the dimmed surround is this
 * view's own background, and the window is cleared out of it.
 *
 * <p>The sweeping line redraws the view on every frame, so everything it draws
 * with is allocated once.
 */
public class ScannerOverlay extends View {

    private final Paint eraser = new Paint();
    private final Paint linePaint = new Paint();
    private final RectF window = new RectF();

    private final int rectWidth;
    private final int rectHeight;
    private final int frames;

    private float endY;
    private boolean revAnimation;

    public ScannerOverlay(Context context, AttributeSet attrs) {
        super(context, attrs);

        rectWidth = AppUtil.dpToPx(context, AppConstants.BARCODE_RECT_WIDTH);
        rectHeight = AppUtil.dpToPx(context,
                BarcodeCaptureActivity.SCAN_MODE == BarcodeCaptureActivity.SCAN_MODE_ENUM.QR.ordinal()
                        ? AppConstants.BARCODE_RECT_HEIGHT
                        : (int) (AppConstants.BARCODE_RECT_HEIGHT / 1.5));
        frames = AppConstants.BARCODE_FRAMES;

        eraser.setAntiAlias(true);
        eraser.setXfermode(new PorterDuffXfermode(PorterDuff.Mode.CLEAR));

        linePaint.setColor(Color.parseColor(UniversalBarcodeScannerPlugin.lineColor));
        linePaint.setStrokeWidth(AppConstants.BARCODE_LINE_WIDTH);
    }

    @Override
    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
        float left = (w - rectWidth) / 2f;
        float top = (h - rectHeight) / 2f;
        window.set(left, top, left + rectWidth, top + rectHeight);
        endY = top;
        super.onSizeChanged(w, h, oldw, oldh);
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);

        canvas.drawRect(window, eraser);

        if (endY >= window.bottom + frames) {
            revAnimation = true;
        } else if (endY <= window.top + frames) {
            revAnimation = false;
        }
        endY += revAnimation ? -frames : frames;

        canvas.drawLine(window.left, endY, window.right, endY, linePaint);
        invalidate();
    }
}
