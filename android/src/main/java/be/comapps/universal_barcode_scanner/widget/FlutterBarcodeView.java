package be.comapps.universal_barcode_scanner.widget;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.RectF;
import android.media.Image;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;
import android.view.animation.Animation;
import android.view.animation.TranslateAnimation;
import android.widget.FrameLayout;
import android.widget.ImageView;

import androidx.annotation.NonNull;
import androidx.annotation.OptIn;
import androidx.camera.core.Camera;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.ExperimentalGetImage;
import androidx.camera.core.ImageAnalysis;
import androidx.camera.core.ImageProxy;
import androidx.camera.core.Preview;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.view.PreviewView;
import androidx.core.content.ContextCompat;
import androidx.lifecycle.Lifecycle;
import androidx.lifecycle.LifecycleOwner;
import androidx.lifecycle.LifecycleRegistry;

import com.google.common.util.concurrent.ListenableFuture;
import com.google.mlkit.vision.barcode.BarcodeScanner;
import com.google.mlkit.vision.barcode.BarcodeScannerOptions;
import com.google.mlkit.vision.barcode.BarcodeScanning;
import com.google.mlkit.vision.barcode.common.Barcode;
import com.google.mlkit.vision.common.InputImage;

import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.platform.PlatformView;

/**
 * The scanner embedded in a Flutter widget: a CameraX preview with an ML Kit
 * analyser, reporting only the codes that fall inside the scan window.
 *
 * <p>A platform view has no lifecycle of its own, so this one holds a registry
 * that CameraX can bind to and that ends with {@link #dispose()}.
 */
public class FlutterBarcodeView implements PlatformView, LifecycleOwner {

    private static final String TAG = "FlutterBarcodeView";

    private final Context context;
    private final FrameLayout frameLayout;
    private final PreviewView previewView;
    private final ImageView scanLine;
    private final MethodChannel methodChannel;
    private final LifecycleRegistry lifecycleRegistry;

    private ProcessCameraProvider cameraProvider;
    private Camera camera;
    private Preview preview;
    private ImageAnalysis analysis;
    private BarcodeScanner scanner;
    private ExecutorService analysisExecutor;

    private boolean isDetecting = true;
    private boolean scanLineStarted;
    private boolean isFlashOn = false;

    /** Scan window, in pixels. Smaller than the preview it sits on. */
    private int scanAreaWidth = 400;
    private int scanAreaHeight = 200;

    /** Preview size, kept up to date on the main thread for the analyser. */
    private volatile int viewWidth;
    private volatile int viewHeight;

    @SuppressWarnings("unchecked")
    public FlutterBarcodeView(Context context, BinaryMessenger messenger, int id, Object creationParams) {
        this.context = context;

        ParamData paramData = ParamData.fromMap((Map<String, Object>) creationParams);
        if (paramData.getScannerWidth() != null) {
            scanAreaWidth = paramData.getScannerWidth();
        }
        if (paramData.getScannerHeight() != null) {
            scanAreaHeight = paramData.getScannerHeight();
        }

        lifecycleRegistry = new LifecycleRegistry(this);
        lifecycleRegistry.setCurrentState(Lifecycle.State.CREATED);

        frameLayout = new FrameLayout(context);
        frameLayout.setLayoutParams(new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));

        previewView = new PreviewView(context);
        previewView.setScaleType(PreviewView.ScaleType.FILL_CENTER);
        // A platform view composes into a texture, which a SurfaceView cannot
        // join.
        previewView.setImplementationMode(PreviewView.ImplementationMode.COMPATIBLE);
        frameLayout.addView(previewView, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));
        previewView.addOnLayoutChangeListener(
                (v, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom) -> {
                    viewWidth = right - left;
                    viewHeight = bottom - top;
                    if (!scanLineStarted && viewWidth > 0 && viewHeight > 0) {
                        scanLineStarted = true;
                        startScanLineAnimation();
                    }
                });

        ScannerOverlay scannerOverlay = new ScannerOverlay(context);
        frameLayout.addView(scannerOverlay, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));

        scanLine = new ImageView(context);
        scanLine.setBackgroundColor(Color.RED);
        frameLayout.addView(
                scanLine, new FrameLayout.LayoutParams(Math.max(1, scanAreaWidth - 40), 5));

        methodChannel = new MethodChannel(messenger, "universal_barcode_scanner/view_" + id);
        methodChannel.setMethodCallHandler(this::onMethodCall);

        scanner = BarcodeScanning.getClient(new BarcodeScannerOptions.Builder()
                .setBarcodeFormats(Barcode.FORMAT_ALL_FORMATS)
                .build());
        analysisExecutor = Executors.newSingleThreadExecutor();

        startCamera();
        lifecycleRegistry.setCurrentState(Lifecycle.State.RESUMED);
    }

    @NonNull
    @Override
    public Lifecycle getLifecycle() {
        return lifecycleRegistry;
    }

    @Override
    public View getView() {
        return frameLayout;
    }

    private void startCamera() {
        final ListenableFuture<ProcessCameraProvider> future =
                ProcessCameraProvider.getInstance(context);
        future.addListener(() -> {
            try {
                cameraProvider = future.get();
                bindCamera();
            } catch (Exception e) {
                Log.e(TAG, "startCamera: " + e.getMessage());
                methodChannel.invokeMethod("onError", "Camera unavailable: " + e.getMessage());
            }
        }, ContextCompat.getMainExecutor(context));
    }

    private void bindCamera() {
        if (cameraProvider == null) {
            return;
        }
        preview = new Preview.Builder().build();
        preview.setSurfaceProvider(previewView.getSurfaceProvider());

        analysis = new ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build();
        analysis.setAnalyzer(analysisExecutor, this::analyse);

        camera = cameraProvider.bindToLifecycle(
                this, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis);
    }

    @OptIn(markerClass = ExperimentalGetImage.class)
    private void analyse(@NonNull ImageProxy proxy) {
        if (!isDetecting || scanner == null) {
            proxy.close();
            return;
        }
        Image image = proxy.getImage();
        if (image == null) {
            proxy.close();
            return;
        }
        final int rotation = proxy.getImageInfo().getRotationDegrees();
        final int frameWidth = proxy.getWidth();
        final int frameHeight = proxy.getHeight();
        scanner.process(InputImage.fromMediaImage(image, rotation))
                .addOnSuccessListener(barcodes ->
                        onBarcodes(barcodes, rotation, frameWidth, frameHeight))
                .addOnFailureListener(e -> Log.e(TAG, "analyse: " + e.getMessage()))
                .addOnCompleteListener(task -> proxy.close());
    }

    private void onBarcodes(@NonNull List<Barcode> barcodes, int rotation, int frameWidth, int frameHeight) {
        if (!isDetecting || barcodes.isEmpty() || viewWidth == 0 || viewHeight == 0) {
            return;
        }

        RectF scanArea = new RectF(
                (viewWidth - scanAreaWidth) / 2f,
                (viewHeight - scanAreaHeight) / 2f,
                (viewWidth + scanAreaWidth) / 2f,
                (viewHeight + scanAreaHeight) / 2f);

        for (Barcode barcode : barcodes) {
            Rect box = barcode.getBoundingBox();
            String value = barcode.getRawValue();
            if (box == null || value == null || value.isEmpty()) {
                continue;
            }
            // The whole code has to sit inside the window.
            if (scanArea.contains(mapToView(box, rotation, frameWidth, frameHeight))) {
                methodChannel.invokeMethod("onBarcodeDetected", value);
                return;
            }
        }
    }

    /**
     * Maps a box from the upright analysed frame onto the preview, which is
     * centre cropped to fill the view.
     */
    private RectF mapToView(@NonNull Rect box, int rotation, int frameWidth, int frameHeight) {
        boolean swapped = rotation == 90 || rotation == 270;
        float imageWidth = swapped ? frameHeight : frameWidth;
        float imageHeight = swapped ? frameWidth : frameHeight;

        float scale = Math.max(viewWidth / imageWidth, viewHeight / imageHeight);
        float offsetX = (viewWidth - imageWidth * scale) / 2f;
        float offsetY = (viewHeight - imageHeight * scale) / 2f;

        return new RectF(
                box.left * scale + offsetX,
                box.top * scale + offsetY,
                box.right * scale + offsetX,
                box.bottom * scale + offsetY);
    }

    private void startScanLineAnimation() {
        scanLine.post(() -> {
            int scanAreaTop = (viewHeight - scanAreaHeight) / 2;
            int scanAreaLeft = (viewWidth - scanAreaWidth) / 2;

            scanLine.setX(scanAreaLeft + 20);
            scanLine.setY(scanAreaTop);

            TranslateAnimation animation = new TranslateAnimation(
                    0, 0,
                    0, scanAreaHeight - 5);

            animation.setDuration(3000);
            animation.setRepeatCount(Animation.INFINITE);
            animation.setRepeatMode(Animation.REVERSE);

            scanLine.startAnimation(animation);
        });
    }

    /** Dims everything but the scan window and outlines it. */
    private class ScannerOverlay extends View {
        private final Paint boxPaint;
        private final Paint overlayPaint;

        ScannerOverlay(Context context) {
            super(context);

            boxPaint = new Paint();
            boxPaint.setColor(Color.WHITE);
            boxPaint.setStyle(Paint.Style.STROKE);
            boxPaint.setStrokeWidth(5f);

            overlayPaint = new Paint();
            overlayPaint.setColor(Color.parseColor("#80000000"));
            overlayPaint.setStyle(Paint.Style.FILL);
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);

            int width = getWidth();
            int height = getHeight();

            int left = (width - scanAreaWidth) / 2;
            int top = (height - scanAreaHeight) / 2;
            int right = left + scanAreaWidth;
            int bottom = top + scanAreaHeight;

            canvas.drawRect(0, 0, width, top, overlayPaint);
            canvas.drawRect(0, top, left, bottom, overlayPaint);
            canvas.drawRect(right, top, width, bottom, overlayPaint);
            canvas.drawRect(0, bottom, width, height, overlayPaint);

            canvas.drawRect(left, top, right, bottom, boxPaint);
        }
    }

    private void toggleFlash(MethodChannel.Result result) {
        if (camera == null) {
            result.error("CAMERA_ERROR", "Camera not available", null);
            return;
        }
        if (!camera.getCameraInfo().hasFlashUnit()) {
            result.error("FLASH_ERROR", "This camera has no flash", null);
            return;
        }
        isFlashOn = !isFlashOn;
        camera.getCameraControl().enableTorch(isFlashOn);
        result.success(isFlashOn);
    }

    private void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "pauseScanning":
                isDetecting = false;
                result.success(null);
                break;
            case "resumeScanning":
                isDetecting = true;
                result.success(null);
                break;
            case "toggleFlash":
                toggleFlash(result);
                break;
            default:
                result.notImplemented();
        }
    }

    @Override
    public void dispose() {
        isDetecting = false;
        methodChannel.setMethodCallHandler(null);
        scanLine.clearAnimation();
        lifecycleRegistry.setCurrentState(Lifecycle.State.DESTROYED);
        if (cameraProvider != null && preview != null && analysis != null) {
            cameraProvider.unbind(preview, analysis);
        }
        cameraProvider = null;
        preview = null;
        analysis = null;
        camera = null;
        if (analysisExecutor != null) {
            analysisExecutor.shutdown();
            analysisExecutor = null;
        }
        if (scanner != null) {
            scanner.close();
            scanner = null;
        }
    }
}
