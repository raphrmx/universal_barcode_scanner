package be.comapps.universal_barcode_scanner;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.media.Image;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.view.GestureDetector;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.view.View;
import android.widget.Button;
import android.widget.ImageView;

import androidx.activity.OnBackPressedCallback;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
import androidx.appcompat.app.AppCompatActivity;
import androidx.camera.core.Camera;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.ExperimentalGetImage;
import androidx.camera.core.FocusMeteringAction;
import androidx.camera.core.ImageAnalysis;
import androidx.camera.core.ImageProxy;
import androidx.camera.core.MeteringPoint;
import androidx.camera.core.Preview;
import androidx.camera.core.ZoomState;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.view.PreviewView;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import com.google.common.util.concurrent.ListenableFuture;
import com.google.mlkit.vision.barcode.BarcodeScanner;
import com.google.mlkit.vision.barcode.BarcodeScanning;
import com.google.mlkit.vision.barcode.common.Barcode;
import com.google.mlkit.vision.common.InputImage;

import java.lang.ref.WeakReference;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

import be.comapps.universal_barcode_scanner.camera.ScannerOverlay;

/**
 * Full screen scanner: a CameraX preview with an ML Kit analyser on every
 * frame.
 *
 * <p>A single scan ends with the activity's result: the code, nothing when
 * cancelled, or an error code. A continuous scan pushes every code to the
 * event channel and says so when it closes, whichever way it closes.
 */
public final class BarcodeCaptureActivity extends AppCompatActivity implements View.OnClickListener {

    private static final String TAG = "BarcodeCaptureActivity";

    // Permission request codes need to be < 256.
    private static final int RC_HANDLE_CAMERA_PERM = 2;

    /** Key of the string extra carrying the code back to the plugin. */
    static final String EXTRA_CODE = "be.comapps.universal_barcode_scanner.code";
    static final String EXTRA_ERROR_CODE = "be.comapps.universal_barcode_scanner.errorCode";
    static final String EXTRA_ERROR_MESSAGE = "be.comapps.universal_barcode_scanner.errorMessage";

    /** The scanner on screen, so the plugin can close it. Weak: never kept. */
    private static WeakReference<BarcodeCaptureActivity> current = new WeakReference<>(null);

    private ScanOptions options;
    private ReadGate gate;

    private PreviewView previewView;
    private ImageView flashButton;
    private ImageView switchButton;

    private ScaleGestureDetector scaleGestureDetector;
    private GestureDetector gestureDetector;

    private ProcessCameraProvider cameraProvider;
    private Camera camera;
    private Preview preview;
    private ImageAnalysis analysis;
    private BarcodeScanner scanner;
    private ExecutorService analysisExecutor;
    private final Handler handler = new Handler(Looper.getMainLooper());

    private int lensFacing;
    private boolean torchOn;

    /** Set once the scan has an outcome, so nothing reports twice. */
    private final AtomicBoolean finished = new AtomicBoolean(false);

    static boolean isOpen() {
        BarcodeCaptureActivity activity = current.get();
        return activity != null && !activity.isFinishing();
    }

    /** Closes the scanner on screen, as if the user had cancelled. */
    static void closeCurrent() {
        BarcodeCaptureActivity activity = current.get();
        if (activity != null) {
            activity.finishCancelled();
        }
    }

    @Override
    public void onCreate(Bundle icicle) {
        super.onCreate(icicle);
        current = new WeakReference<>(this);
        setContentView(R.layout.barcode_capture);

        options = ScanOptions.fromIntent(getIntent());
        gate = new ReadGate(options.delayMillis);
        lensFacing = options.lensFacing();

        Button cancelButton = findViewById(R.id.btnBarcodeCaptureCancel);
        cancelButton.setText(options.cancelButtonText);
        cancelButton.setOnClickListener(this);

        flashButton = findViewById(R.id.imgViewBarcodeCaptureUseFlash);
        flashButton.setOnClickListener(this);
        // Shown once the camera says it has a flash.
        flashButton.setVisibility(View.GONE);

        switchButton = findViewById(R.id.imgViewSwitchCamera);
        switchButton.setOnClickListener(this);
        switchButton.setVisibility(View.GONE);

        ScannerOverlay overlay = findViewById(R.id.scannerOverlay);
        overlay.configure(options.lineColor, options.squareWindow());

        previewView = findViewById(R.id.preview);
        scanner = BarcodeScanning.getClient(options.mlKitOptions());
        analysisExecutor = Executors.newSingleThreadExecutor();

        gestureDetector = new GestureDetector(this, new CaptureGestureListener());
        scaleGestureDetector = new ScaleGestureDetector(this, new ScaleListener());

        // Replaces onBackPressed, which predictive back no longer calls.
        getOnBackPressedDispatcher().addCallback(this, new OnBackPressedCallback(true) {
            @Override
            public void handleOnBackPressed() {
                finishCancelled();
            }
        });

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
                == PackageManager.PERMISSION_GRANTED) {
            startCamera();
        } else {
            ActivityCompat.requestPermissions(
                    this, new String[]{Manifest.permission.CAMERA}, RC_HANDLE_CAMERA_PERM);
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode,
                                           @NonNull String[] permissions,
                                           @NonNull int[] grantResults) {
        if (requestCode != RC_HANDLE_CAMERA_PERM) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults);
            return;
        }
        if (grantResults.length != 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            startCamera();
        } else {
            // The app says it its own way: the scanner only reports.
            finishWithError(ScanErrors.PERMISSION_DENIED, "The camera permission was refused.");
        }
    }

    /**
     * Waits for the camera provider, then binds. CameraX follows the activity
     * lifecycle from there, so pause and resume need nothing of their own.
     */
    private void startCamera() {
        final ListenableFuture<ProcessCameraProvider> future =
                ProcessCameraProvider.getInstance(this);
        future.addListener(() -> {
            try {
                cameraProvider = future.get();
            } catch (Exception e) {
                finishWithError(ScanErrors.CAMERA_UNAVAILABLE,
                        "The camera could not be started: " + e.getMessage());
                return;
            }
            if (!hasLens(lensFacing)) {
                // The asked-for lens is missing: take whichever exists.
                lensFacing = otherLens(lensFacing);
            }
            if (!bindCamera()) {
                finishWithError(ScanErrors.CAMERA_UNAVAILABLE, "No camera could be opened.");
                return;
            }
            switchButton.setVisibility(hasLens(otherLens(lensFacing)) ? View.VISIBLE : View.GONE);
        }, ContextCompat.getMainExecutor(this));
    }

    private boolean hasLens(int facing) {
        if (cameraProvider == null) {
            return false;
        }
        try {
            return cameraProvider.hasCamera(
                    new CameraSelector.Builder().requireLensFacing(facing).build());
        } catch (Exception e) {
            return false;
        }
    }

    private static int otherLens(int facing) {
        return facing == CameraSelector.LENS_FACING_FRONT
                ? CameraSelector.LENS_FACING_BACK : CameraSelector.LENS_FACING_FRONT;
    }

    /** Binds preview and analysis to {@link #lensFacing}; false if it failed. */
    private boolean bindCamera() {
        if (cameraProvider == null || isFinishing()) {
            return false;
        }
        // Only what this screen bound: the camera may be held elsewhere too.
        if (preview != null && analysis != null) {
            cameraProvider.unbind(preview, analysis);
        }

        preview = new Preview.Builder().build();
        preview.setSurfaceProvider(previewView.getSurfaceProvider());

        analysis = new ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build();
        analysis.setAnalyzer(analysisExecutor, this::analyse);

        CameraSelector selector = new CameraSelector.Builder()
                .requireLensFacing(lensFacing)
                .build();

        try {
            camera = cameraProvider.bindToLifecycle(this, selector, preview, analysis);
        } catch (Exception e) {
            Log.e(TAG, "bindCamera: " + e.getMessage());
            camera = null;
            return false;
        }

        boolean hasFlash = camera.getCameraInfo().hasFlashUnit();
        flashButton.setVisibility(options.showFlashIcon && hasFlash ? View.VISIBLE : View.GONE);
        torchOn = torchOn && hasFlash;
        setTorch(torchOn);
        return true;
    }

    @OptIn(markerClass = ExperimentalGetImage.class)
    private void analyse(@NonNull ImageProxy proxy) {
        Image image = proxy.getImage();
        if (image == null || finished.get()) {
            proxy.close();
            return;
        }
        InputImage input =
                InputImage.fromMediaImage(image, proxy.getImageInfo().getRotationDegrees());
        // Results stay on the analysis thread; only a report goes to the main
        // one.
        scanner.process(input)
                .addOnSuccessListener(analysisExecutor, this::onBarcodes)
                .addOnFailureListener(analysisExecutor, e -> Log.e(TAG, "analyse: " + e.getMessage()))
                .addOnCompleteListener(analysisExecutor, task -> proxy.close());
    }

    private void onBarcodes(@NonNull List<Barcode> barcodes) {
        for (Barcode barcode : barcodes) {
            String value = barcode.getRawValue();
            if (value == null || value.isEmpty()) {
                continue;
            }
            if (options.continuous) {
                if (gate.accept(value, SystemClock.elapsedRealtime())) {
                    ScanEvents.code(value);
                }
            } else if (finished.compareAndSet(false, true)) {
                handler.post(() -> {
                    setResult(RESULT_OK, new Intent().putExtra(EXTRA_CODE, value));
                    finish();
                });
            }
            return;
        }
    }

    /** Leaves without a code. */
    void finishCancelled() {
        if (!finished.compareAndSet(false, true)) {
            return;
        }
        if (!options.continuous) {
            setResult(RESULT_CANCELED);
        }
        finish();
    }

    private void finishWithError(@NonNull String code, @NonNull String message) {
        if (!finished.compareAndSet(false, true)) {
            return;
        }
        if (options.continuous) {
            ScanEvents.error(code, message);
        } else {
            setResult(RESULT_CANCELED, new Intent()
                    .putExtra(EXTRA_ERROR_CODE, code)
                    .putExtra(EXTRA_ERROR_MESSAGE, message));
        }
        finish();
    }

    @Override
    public boolean onTouchEvent(MotionEvent e) {
        boolean scaled = scaleGestureDetector.onTouchEvent(e);
        boolean tapped = gestureDetector.onTouchEvent(e);
        return scaled || tapped || super.onTouchEvent(e);
    }

    @Override
    public void onClick(View v) {
        int id = v.getId();
        if (id == R.id.imgViewBarcodeCaptureUseFlash) {
            torchOn = !torchOn;
            setTorch(torchOn);
        } else if (id == R.id.btnBarcodeCaptureCancel) {
            finishCancelled();
        } else if (id == R.id.imgViewSwitchCamera) {
            int previous = lensFacing;
            lensFacing = otherLens(lensFacing);
            if (!bindCamera()) {
                lensFacing = previous;
                bindCamera();
            }
        }
    }

    private void setTorch(boolean on) {
        flashButton.setImageResource(
                on ? R.drawable.ic_barcode_flash_on : R.drawable.ic_barcode_flash_off);
        if (camera != null && camera.getCameraInfo().hasFlashUnit()) {
            camera.getCameraControl().enableTorch(on);
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (current.get() == this) {
            current = new WeakReference<>(null);
        }
        handler.removeCallbacksAndMessages(null);
        if (analysisExecutor != null) {
            analysisExecutor.shutdown();
        }
        if (scanner != null) {
            scanner.close();
        }
        // Every way out of a continuous scan ends here: the cancel button, the
        // back gesture, an error, or the plugin closing it. A rotation does
        // not, since the activity is not finishing then.
        if (isFinishing() && options != null && options.continuous) {
            ScanEvents.closed();
        }
    }

    /** A tap focuses the preview where it landed. */
    private class CaptureGestureListener extends GestureDetector.SimpleOnGestureListener {
        @Override
        public boolean onSingleTapConfirmed(@NonNull MotionEvent e) {
            if (camera == null || previewView == null || e.getY() > previewView.getHeight()) {
                return false;
            }
            MeteringPoint point =
                    previewView.getMeteringPointFactory().createPoint(e.getX(), e.getY());
            camera.getCameraControl().startFocusAndMetering(
                    new FocusMeteringAction.Builder(point).build());
            return true;
        }
    }

    /** A pinch scales the current zoom ratio. */
    private class ScaleListener implements ScaleGestureDetector.OnScaleGestureListener {
        @Override
        public boolean onScale(@NonNull ScaleGestureDetector detector) {
            if (camera == null) {
                return false;
            }
            ZoomState state = camera.getCameraInfo().getZoomState().getValue();
            if (state == null) {
                return false;
            }
            camera.getCameraControl().setZoomRatio(state.getZoomRatio() * detector.getScaleFactor());
            return true;
        }

        @Override
        public boolean onScaleBegin(@NonNull ScaleGestureDetector detector) {
            return true;
        }

        @Override
        public void onScaleEnd(@NonNull ScaleGestureDetector detector) {
        }
    }

    @Nullable
    static String codeFrom(@Nullable Intent data) {
        return data == null ? null : data.getStringExtra(EXTRA_CODE);
    }
}
