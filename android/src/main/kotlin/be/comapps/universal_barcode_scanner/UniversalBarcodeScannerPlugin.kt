package be.comapps.universal_barcode_scanner

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.lifecycle.FlutterLifecycleAdapter
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * Entry point on Android.
 *
 * `scanBarcode` opens [ScannerActivity]. A single scan answers with the
 * code, or null when cancelled; a continuous one answers as soon as the
 * scanner is up and sends its codes on the event channel. `close` closes the
 * scanner of the session it names.
 */
class UniversalBarcodeScannerPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    PluginRegistry.ActivityResultListener,
    PluginRegistry.RequestPermissionsResultListener {

    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var eventChannel: EventChannel? = null

    private var activityBinding: ActivityPluginBinding? = null
    private var activity: Activity? = null
    private var lifecycle: Lifecycle? = null

    /** The single scan waiting for its activity result. */
    private var pendingResult: MethodChannel.Result? = null

    /** Embedded views waiting for the camera permission. */
    private val permissionCallbacks = mutableListOf<(Boolean) -> Unit>()
    private var permissionRequested = false

    /** Embedded views following the activity's lifecycle. */
    private val hostListeners = mutableListOf<(Lifecycle?) -> Unit>()

    /** What the embedded views get from the activity through this plugin. */
    private val host = object : ScannerHost {
        override val hostLifecycle: Lifecycle?
            get() = lifecycle

        override fun addHostListener(listener: (Lifecycle?) -> Unit) {
            hostListeners += listener
        }

        override fun removeHostListener(listener: (Lifecycle?) -> Unit) {
            hostListeners -= listener
        }

        override fun requestCameraPermission(onResult: (granted: Boolean) -> Unit) {
            val current = activity
            if (current == null) {
                onResult(false)
                return
            }
            if (ContextCompat.checkSelfPermission(current, Manifest.permission.CAMERA)
                == PackageManager.PERMISSION_GRANTED
            ) {
                onResult(true)
                return
            }
            permissionCallbacks += onResult
            // One request answers every view that asked in the meantime.
            if (!permissionRequested) {
                permissionRequested = true
                ActivityCompat.requestPermissions(
                    current, arrayOf(Manifest.permission.CAMERA), RC_VIEW_PERMISSION,
                )
            }
        }
    }

    // region FlutterPlugin

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(binding.binaryMessenger, EVENTS).also {
            it.setStreamHandler(this)
        }
        binding.platformViewRegistry.registerViewFactory(
            VIEW_TYPE, EmbeddedScannerFactory(binding.binaryMessenger, host),
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        channel = null
        eventChannel = null
        appContext = null
        ScanEvents.attach(null)
    }

    // endregion

    // region ActivityAware

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        activity = binding.activity
        lifecycle = FlutterLifecycleAdapter.getActivityLifecycle(binding)
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
        notifyHost()
    }

    override fun onDetachedFromActivityForConfigChanges() = release()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        release()
        // For good this time: nobody will answer a permission request any
        // more, and the embedded views have no activity to follow.
        failPermissionRequests()
        notifyHost()
    }

    private fun release() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
        lifecycle = null
    }

    private fun notifyHost() {
        val current = lifecycle
        hostListeners.toList().forEach { it(current) }
    }

    private fun failPermissionRequests() {
        val callbacks = permissionCallbacks.toList()
        permissionCallbacks.clear()
        permissionRequested = false
        callbacks.forEach { it(false) }
    }

    // endregion

    // region MethodCallHandler

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        when (call.method) {
            "scanBarcode" -> scan(arguments, result)
            "close" -> {
                ScannerActivity.close(ScanOptions.sessionOf(arguments))
                result.success(null)
            }
            "beep" -> {
                beep(ToneGenerator.TONE_PROP_BEEP, 120)
                result.success(null)
            }
            "rejectedBeep" -> {
                // The system's "not acknowledged": two low tones.
                beep(ToneGenerator.TONE_PROP_NACK, 300)
                result.success(null)
            }
            "rejected" -> {
                ScannerActivity.rejected(
                    ScanOptions.sessionOf(arguments),
                    (arguments?.get("message") as? String).orEmpty(),
                )
                result.success(null)
            }
            "scanImage" -> {
                val bytes = arguments?.get("bytes") as? ByteArray
                val context = appContext
                if (bytes == null || context == null) {
                    result.error(ScanErrors.INVALID_IMAGE, "No image to read.", null)
                } else {
                    ImageReader.read(
                        context,
                        bytes,
                        (arguments["scanFormat"] as? String) ?: "ALL_FORMATS",
                        result,
                    )
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun scan(arguments: Map<*, *>?, result: MethodChannel.Result) {
        val current = activity
        if (current == null) {
            result.error(ScanErrors.CAMERA_UNAVAILABLE, "No activity to open the scanner from.", null)
            return
        }
        if (pendingResult != null || ScannerActivity.isBusy) {
            result.error(ScanErrors.ALREADY_ACTIVE, "A scanner is already open.", null)
            return
        }

        val options = ScanOptions.fromMap(arguments)
        val intent = options.writeTo(Intent(current, ScannerActivity::class.java))
        try {
            ScannerActivity.launching(options.session)
            if (options.continuous) {
                current.startActivity(intent)
                result.success(null)
            } else {
                pendingResult = result
                current.startActivityForResult(intent, RC_BARCODE_CAPTURE)
            }
        } catch (e: RuntimeException) {
            ScannerActivity.launchFailed(options.session)
            pendingResult = null
            result.error(
                ScanErrors.CAMERA_UNAVAILABLE,
                "The scanner could not be opened: ${e.message}",
                null,
            )
        }
    }

    // endregion

    // region Results

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != RC_BARCODE_CAPTURE) return false
        val result = pendingResult ?: return true
        pendingResult = null

        val errorCode = data?.getStringExtra(ScannerActivity.EXTRA_ERROR_CODE)
        if (errorCode != null) {
            result.error(
                errorCode,
                data.getStringExtra(ScannerActivity.EXTRA_ERROR_MESSAGE),
                null,
            )
            return true
        }
        val code = if (resultCode == Activity.RESULT_OK) ScannerActivity.codeFrom(data) else null
        result.success(
            code?.let { mapOf("code" to it, "format" to ScannerActivity.formatFrom(data)) },
        )
        return true
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != RC_VIEW_PERMISSION) return false
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        val callbacks = permissionCallbacks.toList()
        permissionCallbacks.clear()
        permissionRequested = false
        callbacks.forEach { it(granted) }
        return true
    }

    // endregion

    /** Plays [tone] for [millis], at the notification volume. */
    private fun beep(tone: Int, millis: Int) {
        val generator = try {
            ToneGenerator(AudioManager.STREAM_NOTIFICATION, 80)
        } catch (e: RuntimeException) {
            // No tone to be had, a device with its audio busy for one.
            return
        }
        generator.startTone(tone, millis)
        Handler(Looper.getMainLooper()).postDelayed({ generator.release() }, millis + 130L)
    }

    // region StreamHandler

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        ScanEvents.attach(events)
    }

    override fun onCancel(arguments: Any?) {
        ScanEvents.attach(null)
    }

    // endregion

    private companion object {
        const val CHANNEL = "universal_barcode_scanner"
        const val EVENTS = "universal_barcode_scanner/events"
        const val VIEW_TYPE = "universal_barcode_scanner/view"

        const val RC_BARCODE_CAPTURE = 9001
        const val RC_VIEW_PERMISSION = 9002
    }
}
