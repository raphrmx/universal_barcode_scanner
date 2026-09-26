package be.comapps.universal_barcode_scanner;

import android.Manifest;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.media.Image;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.GestureDetector;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.view.View;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.Toast;

import androidx.annotation.NonNull;
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
import com.google.mlkit.vision.barcode.BarcodeScannerOptions;
import com.google.mlkit.vision.barcode.BarcodeScanning;
import com.google.mlkit.vision.barcode.common.Barcode;
import com.google.mlkit.vision.common.InputImage;

import java.util.List;
import java.util.Objects;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Full screen scanner: a CameraX preview with an ML Kit analyser on every
 * frame. The first code read goes back to the plugin, either as the result of
 * the activity or, in continuous mode, on the event channel.
 */
public final class BarcodeCaptureActivity extends AppCompatActivity implements View.OnClickListener {

    // permission request codes need to be < 256
    private static final int RC_HANDLE_CAMERA_PERM = 2;

    private static final String TAG = "BarcodeCaptureActivity";

    /** Key of the string extra carrying the code back to the plugin. */
    public static final String BarcodeObject = "Barcode";

    public static SCAN_FORMAT_ENUM SCAN_FORMAT = SCAN_FORMAT_ENUM.ALL_FORMATS;

    public enum SCAN_FORMAT_ENUM {
        ALL_FORMATS,
        ONLY_QR_CODE,
        ONLY_BARCODE
    }

    public static int SCAN_MODE = SCAN_MODE_ENUM.QR.ordinal();

    public enum SCAN_MODE_ENUM {
        QR,
        BARCODE,
        DEFAULT
    }

    private enum USE_FLASH {
        ON,
        OFF
    }

    private PreviewView previewView;
    private ImageView imgViewBarcodeCaptureUseFlash;

    private ScaleGestureDetector scaleGestureDetector;
    private GestureDetector gestureDetector;

    private ProcessCameraProvider cameraProvider;
    private Camera camera;
    private Preview preview;
    private ImageAnalysis analysis;
    private BarcodeScanner scanner;
    private ExecutorService analysisExecutor;
    private final Handler handler = new Handler(Looper.getMainLooper());

    private int lensFacing = CameraSelector.LENS_FACING_BACK;
    private int flashStatus = USE_FLASH.OFF.ordinal();
    private int delayMillis;

    /** True while a code has been read and is waiting out the delay. */
    private boolean reporting;

    @Override
    public void onBackPressed() {
        // -2 is the code for user cancelled the scan
        UniversalBarcodeScannerPlugin.onBarcodeScanReceiver("-2");
        super.onBackPressed();
    }

    @Override
    public void onCreate(Bundle icicle) {
        super.onCreate(icicle);
        setContentView(R.layout.barcode_capture);

        String buttonText = getIntent().getStringExtra("cancelButtonText");
        String cameraFacingText = getIntent().getStringExtra("cameraFacingText");
        delayMillis = getIntent().getIntExtra("delayMillis", 0);
        lensFacing = Objects.equals(cameraFacingText, "FRONT")
                ? CameraSelector.LENS_FACING_FRONT : CameraSelector.LENS_FACING_BACK;

        Button btnBarcodeCaptureCancel = findViewById(R.id.btnBarcodeCaptureCancel);
        if (buttonText != null && !buttonText.isEmpty()) {
            btnBarcodeCaptureCancel.setText(buttonText);
        }
        btnBarcodeCaptureCancel.setOnClickListener(this);

        imgViewBarcodeCaptureUseFlash = findViewById(R.id.imgViewBarcodeCaptureUseFlash);
        imgViewBarcodeCaptureUseFlash.setOnClickListener(this);
        imgViewBarcodeCaptureUseFlash.setVisibility(
                UniversalBarcodeScannerPlugin.isShowFlashIcon ? View.VISIBLE : View.GONE);

        findViewById(R.id.imgViewSwitchCamera).setOnClickListener(this);

        previewView = findViewById(R.id.preview);
        scanner = BarcodeScanning.getClient(scannerOptions());
        analysisExecutor = Executors.newSingleThreadExecutor();

        gestureDetector = new GestureDetector(this, new CaptureGestureListener());
        scaleGestureDetector = new ScaleGestureDetector(this, new ScaleListener());

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
                == PackageManager.PERMISSION_GRANTED) {
            startCamera();
        } else {
            requestCameraPermission();
        }
    }

    /** The symbologies the analyser is allowed to report. */
    private static BarcodeScannerOptions scannerOptions() {
        if (SCAN_FORMAT == SCAN_FORMAT_ENUM.ONLY_QR_CODE) {
            return new BarcodeScannerOptions.Builder()
                    .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
                    .build();
        }
        if (SCAN_FORMAT == SCAN_FORMAT_ENUM.ONLY_BARCODE) {
            return new BarcodeScannerOptions.Builder()
                    .setBarcodeFormats(
                            Barcode.FORMAT_CODABAR,
                            Barcode.FORMAT_CODE_128,
                            Barcode.FORMAT_CODE_39,
                            Barcode.FORMAT_CODE_93,
                            Barcode.FORMAT_EAN_13,
                            Barcode.FORMAT_EAN_8,
                            Barcode.FORMAT_ITF,
                            Barcode.FORMAT_PDF417,
                            Barcode.FORMAT_UPC_A,
                            Barcode.FORMAT_UPC_E)
                    .build();
        }
        return new BarcodeScannerOptions.Builder()
                .setBarcodeFormats(Barcode.FORMAT_ALL_FORMATS)
                .build();
    }

    private void requestCameraPermission() {
        if (ActivityCompat.shouldShowRequestPermissionRationale(this, Manifest.permission.CAMERA)) {
            Toast.makeText(this, R.string.permission_camera_rationale, Toast.LENGTH_LONG).show();
        }
        ActivityCompat.requestPermissions(
                this, new String[]{Manifest.permission.CAMERA}, RC_HANDLE_CAMERA_PERM);
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
            return;
        }

        DialogInterface.OnClickListener listener = (dialog, id) -> finish();
        new AlertDialog.Builder(this)
                .setTitle("Allow permissions")
                .setMessage(R.string.no_camera_permission)
                .setPositiveButton(R.string.ok, listener)
                .show();
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
                bindCamera();
            } catch (Exception e) {
                Log.e(TAG, "startCamera: " + e.getLocalizedMessage());
                Toast.makeText(this, R.string.camera_unavailable, Toast.LENGTH_LONG).show();
            }
        }, ContextCompat.getMainExecutor(this));
    }

    private void bindCamera() {
        if (cameraProvider == null) {
            return;
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

        camera = cameraProvider.bindToLifecycle(this, selector, preview, analysis);
        applyFlash(flashStatus == USE_FLASH.ON.ordinal());
    }

    @OptIn(markerClass = ExperimentalGetImage.class)
    private void analyse(@NonNull ImageProxy proxy) {
        Image image = proxy.getImage();
        if (image == null) {
            proxy.close();
            return;
        }
        InputImage input =
                InputImage.fromMediaImage(image, proxy.getImageInfo().getRotationDegrees());
        scanner.process(input)
                .addOnSuccessListener(this::onBarcodes)
                .addOnFailureListener(e -> Log.e(TAG, "analyse: " + e.getLocalizedMessage()))
                .addOnCompleteListener(task -> proxy.close());
    }

    private void onBarcodes(@NonNull List<Barcode> barcodes) {
        if (barcodes.isEmpty() || reporting) {
            return;
        }
        String value = barcodes.get(0).getRawValue();
        if (value == null || value.isEmpty()) {
            return;
        }
        reporting = true;
        handler.postDelayed(() -> {
            reporting = false;
            report(value);
        }, delayMillis);
    }

    private void report(@NonNull String value) {
        if (isFinishing() || isDestroyed()) {
            return;
        }
        if (UniversalBarcodeScannerPlugin.isContinuousScan) {
            UniversalBarcodeScannerPlugin.onBarcodeScanReceiver(value);
        } else {
            setResult(RESULT_OK, new Intent().putExtra(BarcodeObject, value));
            finish();
        }
    }

    @Override
    public boolean onTouchEvent(MotionEvent e) {
        boolean scaled = scaleGestureDetector.onTouchEvent(e);
        boolean tapped = gestureDetector.onTouchEvent(e);
        return scaled || tapped || super.onTouchEvent(e);
    }

    @Override
    public void onClick(View v) {
        int i = v.getId();
        if (i == R.id.imgViewBarcodeCaptureUseFlash) {
            boolean turnOn = flashStatus == USE_FLASH.OFF.ordinal();
            flashStatus = turnOn ? USE_FLASH.ON.ordinal() : USE_FLASH.OFF.ordinal();
            imgViewBarcodeCaptureUseFlash.setImageResource(
                    turnOn ? R.drawable.ic_barcode_flash_on : R.drawable.ic_barcode_flash_off);
            applyFlash(turnOn);
        } else if (i == R.id.btnBarcodeCaptureCancel) {
            onBackPressed();
        } else if (i == R.id.imgViewSwitchCamera) {
            lensFacing = lensFacing == CameraSelector.LENS_FACING_FRONT
                    ? CameraSelector.LENS_FACING_BACK : CameraSelector.LENS_FACING_FRONT;
            bindCamera();
        }
    }

    private void applyFlash(boolean on) {
        if (camera == null) {
            return;
        }
        if (!camera.getCameraInfo().hasFlashUnit()) {
            if (on) {
                Toast.makeText(this, R.string.no_flash_unit, Toast.LENGTH_SHORT).show();
            }
            return;
        }
        camera.getCameraControl().enableTorch(on);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        handler.removeCallbacksAndMessages(null);
        if (analysisExecutor != null) {
            analysisExecutor.shutdown();
        }
        if (scanner != null) {
            scanner.close();
        }
    }

    /** A tap focuses the preview where it landed. */
    private class CaptureGestureListener extends GestureDetector.SimpleOnGestureListener {
        @Override
        public boolean onSingleTapConfirmed(MotionEvent e) {
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
        public boolean onScale(ScaleGestureDetector detector) {
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
        public boolean onScaleBegin(ScaleGestureDetector detector) {
            return true;
        }

        @Override
        public void onScaleEnd(ScaleGestureDetector detector) {
        }
    }
}
