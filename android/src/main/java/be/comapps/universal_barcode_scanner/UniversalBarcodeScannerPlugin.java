package be.comapps.universal_barcode_scanner;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.lifecycle.Lifecycle;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import be.comapps.universal_barcode_scanner.widget.BarcodeViewFactory;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.embedding.engine.plugins.lifecycle.FlutterLifecycleAdapter;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/**
 * Entry point on Android.
 *
 * <p>{@code scanBarcode} opens {@link BarcodeCaptureActivity}. A single scan
 * answers with the code, or null when cancelled; a continuous one answers as
 * soon as the scanner is up and sends its codes on the event channel.
 * {@code close} closes whichever scanner is open.
 */
public class UniversalBarcodeScannerPlugin implements FlutterPlugin, ActivityAware,
        MethodChannel.MethodCallHandler, EventChannel.StreamHandler,
        PluginRegistry.ActivityResultListener, PluginRegistry.RequestPermissionsResultListener,
        ScannerHost {

    private static final String CHANNEL = "universal_barcode_scanner";
    private static final String EVENTS = "universal_barcode_scanner/events";
    private static final String VIEW_TYPE = "universal_barcode_scanner/view";

    private static final int RC_BARCODE_CAPTURE = 9001;
    private static final int RC_VIEW_PERMISSION = 9002;

    private MethodChannel channel;
    private EventChannel eventChannel;

    @Nullable
    private ActivityPluginBinding activityBinding;
    @Nullable
    private Activity activity;
    @Nullable
    private Lifecycle lifecycle;

    /** The single scan waiting for its activity result. */
    @Nullable
    private MethodChannel.Result pendingResult;

    /** Embedded views waiting for the camera permission. */
    private final List<PermissionCallback> permissionCallbacks = new ArrayList<>();

    // region FlutterPlugin

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
        eventChannel = new EventChannel(binding.getBinaryMessenger(), EVENTS);
        eventChannel.setStreamHandler(this);
        binding.getPlatformViewRegistry().registerViewFactory(
                VIEW_TYPE, new BarcodeViewFactory(binding.getBinaryMessenger(), this));
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        eventChannel.setStreamHandler(null);
        ScanEvents.attach(null);
    }

    // endregion

    // region ActivityAware

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activityBinding = binding;
        activity = binding.getActivity();
        lifecycle = FlutterLifecycleAdapter.getActivityLifecycle(binding);
        binding.addActivityResultListener(this);
        binding.addRequestPermissionsResultListener(this);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivity() {
        if (activityBinding != null) {
            activityBinding.removeActivityResultListener(this);
            activityBinding.removeRequestPermissionsResultListener(this);
        }
        activityBinding = null;
        activity = null;
        lifecycle = null;
    }

    // endregion

    // region MethodCallHandler

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "scanBarcode":
                scan(call.arguments instanceof Map ? (Map<?, ?>) call.arguments : null, result);
                break;
            case "close":
                BarcodeCaptureActivity.closeCurrent();
                result.success(null);
                break;
            default:
                result.notImplemented();
        }
    }

    private void scan(@Nullable Map<?, ?> arguments, @NonNull MethodChannel.Result result) {
        Activity host = activity;
        if (host == null) {
            result.error(ScanErrors.CAMERA_UNAVAILABLE, "No activity to open the scanner from.", null);
            return;
        }
        if (pendingResult != null || BarcodeCaptureActivity.isOpen()) {
            result.error(ScanErrors.ALREADY_ACTIVE, "A scanner is already open.", null);
            return;
        }

        ScanOptions options = ScanOptions.fromMap(arguments);
        Intent intent = options.writeTo(new Intent(host, BarcodeCaptureActivity.class));
        try {
            if (options.continuous) {
                host.startActivity(intent);
                result.success(null);
            } else {
                pendingResult = result;
                host.startActivityForResult(intent, RC_BARCODE_CAPTURE);
            }
        } catch (RuntimeException e) {
            pendingResult = null;
            result.error(ScanErrors.CAMERA_UNAVAILABLE,
                    "The scanner could not be opened: " + e.getMessage(), null);
        }
    }

    // endregion

    // region Results

    @Override
    public boolean onActivityResult(int requestCode, int resultCode, @Nullable Intent data) {
        if (requestCode != RC_BARCODE_CAPTURE) {
            return false;
        }
        MethodChannel.Result result = pendingResult;
        pendingResult = null;
        if (result == null) {
            return true;
        }

        String errorCode = data == null ? null
                : data.getStringExtra(BarcodeCaptureActivity.EXTRA_ERROR_CODE);
        if (errorCode != null) {
            result.error(errorCode,
                    data.getStringExtra(BarcodeCaptureActivity.EXTRA_ERROR_MESSAGE), null);
            return true;
        }
        String code = resultCode == Activity.RESULT_OK ? BarcodeCaptureActivity.codeFrom(data) : null;
        result.success(code);
        return true;
    }

    @Override
    public boolean onRequestPermissionsResult(int requestCode, @NonNull String[] permissions,
                                              @NonNull int[] grantResults) {
        if (requestCode != RC_VIEW_PERMISSION) {
            return false;
        }
        boolean granted = grantResults.length > 0
                && grantResults[0] == PackageManager.PERMISSION_GRANTED;
        List<PermissionCallback> callbacks = new ArrayList<>(permissionCallbacks);
        permissionCallbacks.clear();
        for (PermissionCallback callback : callbacks) {
            callback.onResult(granted);
        }
        return true;
    }

    // endregion

    // region StreamHandler

    @Override
    public void onListen(Object arguments, EventChannel.EventSink events) {
        ScanEvents.attach(events);
    }

    @Override
    public void onCancel(Object arguments) {
        ScanEvents.attach(null);
    }

    // endregion

    // region ScannerHost

    @Nullable
    @Override
    public Lifecycle hostLifecycle() {
        return lifecycle;
    }

    @Override
    public void requestCameraPermission(@NonNull PermissionCallback callback) {
        Activity host = activity;
        if (host == null) {
            callback.onResult(false);
            return;
        }
        if (ContextCompat.checkSelfPermission(host, Manifest.permission.CAMERA)
                == PackageManager.PERMISSION_GRANTED) {
            callback.onResult(true);
            return;
        }
        permissionCallbacks.add(callback);
        // One request answers every view that asked in the meantime.
        if (permissionCallbacks.size() == 1) {
            ActivityCompat.requestPermissions(
                    host, new String[]{Manifest.permission.CAMERA}, RC_VIEW_PERMISSION);
        }
    }

    // endregion
}
