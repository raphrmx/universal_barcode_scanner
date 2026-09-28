package be.comapps.universal_barcode_scanner.widget;

import android.content.Context;
import android.graphics.Rect;
import android.graphics.RectF;
import android.media.Image;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
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
import androidx.lifecycle.LifecycleEventObserver;
import androidx.lifecycle.LifecycleOwner;
import androidx.lifecycle.LifecycleRegistry;

import com.google.common.util.concurrent.ListenableFuture;
import com.google.mlkit.vision.barcode.BarcodeScanner;
import com.google.mlkit.vision.barcode.BarcodeScanning;
import com.google.mlkit.vision.barcode.common.Barcode;
import com.google.mlkit.vision.common.InputImage;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import be.comapps.universal_barcode_scanner.ReadGate;
import be.comapps.universal_barcode_scanner.ScanErrors;
import be.comapps.universal_barcode_scanner.ScanOptions;
import be.comapps.universal_barcode_scanner.ScannerHost;
import be.comapps.universal_barcode_scanner.camera.ScannerOverlay;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.platform.PlatformView;

/**
 * The scanner embedded in a Flutter widget: a CameraX preview with an ML Kit
 * analyser, reporting only the codes that fall inside the scan window.
 *
 * <p>A platform view has no lifecycle of its own. This one holds a registry
 * that follows the host activity, so the camera stops when the app goes to the
 * background, and that ends with {@link #dispose()}.
 */
public class FlutterBarcodeView implements PlatformView, LifecycleOwner {

    private static final String TAG = "FlutterBarcodeView";

    private final Context context;
    private final ScannerHost host;
    private final ScanOptions options;
    private final ReadGate gate;
    private final FrameLayout frameLayout;
    private final PreviewView previewView;
    private final ScannerOverlay overlay;
    private final MethodChannel methodChannel;
    private final LifecycleRegistry lifecycleRegistry;
    private final Handler main = new Handler(Looper.getMainLooper());

    @Nullable
    private final Lifecycle hostLifecycle;
    private final LifecycleEventObserver hostObserver;

    private ProcessCameraProvider cameraProvider;
    private Camera camera;
    private Preview preview;
    private ImageAnalysis analysis;
    private BarcodeScanner scanner;
    private ExecutorService analysisExecutor;

    private volatile boolean detecting = true;
    /** Whether the bound camera faces the user, whose preview is mirrored. */
    private volatile boolean mirrored;
    private boolean disposed;
    private boolean torchOn;

    /** Preview size, kept up to date on the main thread for the analyser. */
    private volatile int viewWidth;
    private volatile int viewHeight;

    public FlutterBarcodeView(@NonNull Context context, @NonNull BinaryMessenger messenger,
                              @NonNull ScannerHost host, int id, @Nullable Map<?, ?> params) {
        this.context = context;
        this.host = host;
        options = ScanOptions.fromMap(params);
        gate = new ReadGate(options.delayMillis);

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
                });

        overlay = new ScannerOverlay(context);
        overlay.configure(options.lineColor, options.squareWindow());
        overlay.setWindowSize(
                ScanOptions.optionalDouble(params, "scanWindowWidth"),
                ScanOptions.optionalDouble(params, "scanWindowHeight"));
        frameLayout.addView(overlay, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));

        methodChannel = new MethodChannel(messenger, "universal_barcode_scanner/view_" + id);
        methodChannel.setMethodCallHandler(this::onMethodCall);

        // Mirrors the host activity: the camera runs while it is started and
        // stops while it is in the background.
        hostLifecycle = host.hostLifecycle();
        hostObserver = (source, event) -> {
            if (!disposed && event != Lifecycle.Event.ON_DESTROY) {
                lifecycleRegistry.setCurrentState(event.getTargetState());
            }
        };

        host.requestCameraPermission(granted -> {
            if (disposed) {
                return;
            }
            if (granted) {
                startCamera();
            } else {
                reportError(ScanErrors.PERMISSION_DENIED, "The camera permission was refused.");
            }
        });
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
        scanner = BarcodeScanning.getClient(options.mlKitOptions());
        analysisExecutor = Executors.newSingleThreadExecutor();

        if (hostLifecycle != null) {
            // Adding the observer replays the host's current state.
            hostLifecycle.addObserver(hostObserver);
        } else {
            lifecycleRegistry.setCurrentState(Lifecycle.State.RESUMED);
        }

        final ListenableFuture<ProcessCameraProvider> future =
                ProcessCameraProvider.getInstance(context);
        future.addListener(() -> {
            if (disposed) {
                return;
            }
            try {
                cameraProvider = future.get();
                bindCamera();
            } catch (Exception e) {
                Log.e(TAG, "startCamera: " + e.getMessage());
                reportError(ScanErrors.CAMERA_UNAVAILABLE,
                        "The camera could not be started: " + e.getMessage());
            }
        }, ContextCompat.getMainExecutor(context));
    }

    private void bindCamera() throws Exception {
        preview = new Preview.Builder().build();
        preview.setSurfaceProvider(previewView.getSurfaceProvider());

        analysis = new ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build();
        analysis.setAnalyzer(analysisExecutor, this::analyse);

        CameraSelector selector = new CameraSelector.Builder()
                .requireLensFacing(options.lensFacing())
                .build();
        if (!cameraProvider.hasCamera(selector)) {
            // The asked-for lens is missing: take the default one instead.
            selector = CameraSelector.DEFAULT_BACK_CAMERA;
        }
        camera = cameraProvider.bindToLifecycle(this, selector, preview, analysis);
        mirrored = camera.getCameraInfo().getLensFacing() == CameraSelector.LENS_FACING_FRONT;
    }

    @OptIn(markerClass = ExperimentalGetImage.class)
    private void analyse(@NonNull ImageProxy proxy) {
        // Read once: dispose may clear the field from the main thread.
        final BarcodeScanner current = scanner;
        final ExecutorService executor = analysisExecutor;
        if (!detecting || current == null || executor == null) {
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
        current.process(InputImage.fromMediaImage(image, rotation))
                .addOnSuccessListener(executor, barcodes ->
                        onBarcodes(barcodes, rotation, frameWidth, frameHeight))
                .addOnFailureListener(executor, e -> Log.e(TAG, "analyse: " + e.getMessage()))
                .addOnCompleteListener(executor, task -> proxy.close());
    }

    private void onBarcodes(@NonNull List<Barcode> barcodes, int rotation, int frameWidth, int frameHeight) {
        if (!detecting || barcodes.isEmpty() || viewWidth == 0 || viewHeight == 0) {
            return;
        }
        RectF window = overlay.copyWindow();
        if (window.isEmpty()) {
            return;
        }

        for (Barcode barcode : barcodes) {
            Rect box = barcode.getBoundingBox();
            String value = barcode.getRawValue();
            if (box == null || value == null || value.isEmpty()) {
                continue;
            }
            // The whole code has to sit inside the window.
            if (!window.contains(mapToView(box, rotation, frameWidth, frameHeight))) {
                continue;
            }
            if (!gate.accept(value, SystemClock.elapsedRealtime())) {
                return;
            }
            if (!options.continuous) {
                // Waits for resumeScanning before reading another one.
                detecting = false;
            }
            main.post(() -> {
                if (!disposed) {
                    methodChannel.invokeMethod("onBarcodeDetected", value);
                }
            });
            return;
        }
    }

    /**
     * Maps a box from the upright analysed frame onto the preview, which is
     * centre cropped to fill the view, and mirrored for a front camera.
     */
    private RectF mapToView(@NonNull Rect box, int rotation, int frameWidth, int frameHeight) {
        boolean swapped = rotation == 90 || rotation == 270;
        float imageWidth = swapped ? frameHeight : frameWidth;
        float imageHeight = swapped ? frameWidth : frameHeight;

        float scale = Math.max(viewWidth / imageWidth, viewHeight / imageHeight);
        float offsetX = (viewWidth - imageWidth * scale) / 2f;
        float offsetY = (viewHeight - imageHeight * scale) / 2f;

        float left = box.left;
        float right = box.right;
        if (mirrored) {
            left = imageWidth - box.right;
            right = imageWidth - box.left;
        }

        return new RectF(
                left * scale + offsetX,
                box.top * scale + offsetY,
                right * scale + offsetX,
                box.bottom * scale + offsetY);
    }

    private void reportError(@NonNull String code, @NonNull String message) {
        Map<String, Object> error = new HashMap<>();
        error.put("code", code);
        error.put("message", message);
        main.post(() -> {
            if (!disposed) {
                methodChannel.invokeMethod("onError", error);
            }
        });
    }

    private void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "pauseScanning":
                detecting = false;
                result.success(null);
                break;
            case "resumeScanning":
                // The code that paused a single-shot view counts as new again.
                gate.reset();
                detecting = true;
                result.success(null);
                break;
            case "toggleFlash":
                if (camera == null || !camera.getCameraInfo().hasFlashUnit()) {
                    result.success(false);
                    break;
                }
                torchOn = !torchOn;
                camera.getCameraControl().enableTorch(torchOn);
                result.success(torchOn);
                break;
            default:
                result.notImplemented();
        }
    }

    @Override
    public void dispose() {
        disposed = true;
        detecting = false;
        methodChannel.setMethodCallHandler(null);
        main.removeCallbacksAndMessages(null);
        if (hostLifecycle != null) {
            hostLifecycle.removeObserver(hostObserver);
        }
        if (lifecycleRegistry.getCurrentState() != Lifecycle.State.INITIALIZED) {
            lifecycleRegistry.setCurrentState(Lifecycle.State.DESTROYED);
        }
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
