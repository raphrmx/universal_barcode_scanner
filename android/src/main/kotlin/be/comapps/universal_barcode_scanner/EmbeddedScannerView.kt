package be.comapps.universal_barcode_scanner

import android.content.Context
import android.graphics.Rect
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.annotation.OptIn
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.TorchState
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The scanner embedded in a Flutter widget: a CameraX preview with an ML Kit
 * analyser, reporting only the codes that fall inside the scan window.
 *
 * A platform view has no lifecycle of its own. This one holds a registry that
 * follows the host activity, so the camera stops when the app goes to the
 * background, follows the next activity when the engine moves to another one,
 * and ends with [dispose].
 */
internal class EmbeddedScannerView(
    private val context: Context,
    messenger: BinaryMessenger,
    private val host: ScannerHost,
    id: Int,
    params: Map<*, *>?,
) : PlatformView, LifecycleOwner {

    private val options = ScanOptions.fromMap(params)
    private val gate = ReadGate(options.delayMillis.toLong())
    private val main = Handler(Looper.getMainLooper())

    private val lifecycleRegistry = LifecycleRegistry(this).apply {
        currentState = Lifecycle.State.CREATED
    }

    private val previewView = PreviewView(context).apply {
        scaleType = PreviewView.ScaleType.FILL_CENTER
        // A platform view composes into a texture, which a SurfaceView cannot
        // join.
        implementationMode = PreviewView.ImplementationMode.COMPATIBLE
    }

    private val scanOverlay = ScanWindowOverlay(context).apply {
        configure(options.lineColor, options.squareWindow, options.hasWindow)
        setWindowSize(
            ScanOptions.optionalDouble(params, "scanWindowWidth"),
            ScanOptions.optionalDouble(params, "scanWindowHeight"),
        )
        // About 30 frames a second: each one is a frame Flutter composites.
        frameIntervalMs = 33
    }

    private val frameLayout = FrameLayout(context).apply {
        layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
        addView(previewView, matchParent())
        addView(scanOverlay, matchParent())
    }

    private val methodChannel =
        MethodChannel(messenger, "universal_barcode_scanner/view_$id")

    /** The activity lifecycle this view mirrors: the camera runs while it is started. */
    private var hostLifecycle: Lifecycle? = null
    private val hostObserver = LifecycleEventObserver { _, event ->
        if (!disposed && event != Lifecycle.Event.ON_DESTROY) {
            lifecycleRegistry.currentState = event.targetState
        }
    }
    private val hostListener: (Lifecycle?) -> Unit = { follow(it) }

    private var cameraProvider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var preview: Preview? = null
    private var analysis: ImageAnalysis? = null
    private var scanner: BarcodeScanner? = null
    private var analysisExecutor: ExecutorService? = null

    @Volatile
    private var detecting = true

    /** Whether the bound camera faces the user, whose preview is mirrored. */
    @Volatile
    private var mirrored = false

    /** Preview size, kept up to date on the main thread for the analyser. */
    @Volatile
    private var viewWidth = 0

    @Volatile
    private var viewHeight = 0

    private var displayRotation = -1
    private var disposed = false

    /** Whether Flutter has been told the first frame is on screen. */
    private var announcedStart = false

    override val lifecycle: Lifecycle
        get() = lifecycleRegistry

    init {
        previewView.addOnLayoutChangeListener { _, left, top, right, bottom, _, _, _, _ ->
            viewWidth = right - left
            viewHeight = bottom - top
            updateRotation()
        }
        methodChannel.setMethodCallHandler(::onMethodCall)
        // Streaming is the preview showing frames, not merely the camera
        // being bound: what Flutter waits for to fade the view in.
        previewView.previewStreamState.observe(this) { state ->
            if (state == PreviewView.StreamState.STREAMING && !announcedStart && !disposed) {
                announcedStart = true
                methodChannel.invokeMethod("onCameraStarted", null)
            }
        }

        host.requestCameraPermission { granted ->
            if (disposed) return@requestCameraPermission
            if (granted) {
                startCamera()
            } else {
                reportError(ScanErrors.PERMISSION_DENIED, "The camera permission was refused.")
            }
        }
    }

    override fun getView(): View = frameLayout

    /** Mirrors [lifecycle], or stops the camera when there is none. */
    private fun follow(lifecycle: Lifecycle?) {
        hostLifecycle?.removeObserver(hostObserver)
        hostLifecycle = lifecycle
        if (lifecycle != null) {
            // Adding the observer replays the host's current state.
            lifecycle.addObserver(hostObserver)
        } else if (!disposed) {
            lifecycleRegistry.currentState = Lifecycle.State.CREATED
        }
    }

    /**
     * The Flutter activity handles rotation itself, so the use cases are not
     * rebuilt: without this, frames would keep the old orientation and the
     * window check would compare boxes turned a quarter.
     */
    private fun updateRotation() {
        val rotation = previewView.display?.rotation ?: return
        if (rotation == displayRotation) return
        displayRotation = rotation
        preview?.targetRotation = rotation
        analysis?.targetRotation = rotation
    }

    private fun startCamera() {
        scanner = BarcodeScanning.getClient(options.mlKitOptions())
        analysisExecutor = Executors.newSingleThreadExecutor()

        host.addHostListener(hostListener)
        follow(host.hostLifecycle)

        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            if (disposed) return@addListener
            try {
                cameraProvider = future.get()
                bindCamera()
            } catch (e: Exception) {
                Log.e(TAG, "startCamera: ${e.message}")
                reportError(
                    ScanErrors.CAMERA_UNAVAILABLE,
                    "The camera could not be started: ${e.message}",
                )
            }
        }, ContextCompat.getMainExecutor(context))
    }

    private fun bindCamera() {
        val provider = cameraProvider ?: return
        val executor = analysisExecutor ?: return

        val rotation = previewView.display?.rotation ?: 0
        displayRotation = rotation
        val newPreview = CameraSetup.preview(rotation).also {
            it.setSurfaceProvider(previewView.surfaceProvider)
        }
        val newAnalysis = CameraSetup.analysis(rotation).also {
            it.setAnalyzer(executor, ::analyse)
        }
        preview = newPreview
        analysis = newAnalysis

        val wanted = options.lensFacing
        val other = if (wanted == CameraSelector.LENS_FACING_FRONT) {
            CameraSelector.LENS_FACING_BACK
        } else {
            CameraSelector.LENS_FACING_FRONT
        }
        var selector = CameraSelector.Builder().requireLensFacing(wanted).build()
        if (!provider.hasCamera(selector)) {
            // The asked-for lens is missing: take the other one.
            selector = CameraSelector.Builder().requireLensFacing(other).build()
        }
        val bound = provider.bindToLifecycle(this, selector, newPreview, newAnalysis)
        camera = bound
        mirrored = bound.cameraInfo.lensFacing == CameraSelector.LENS_FACING_FRONT
    }

    @OptIn(markerClass = [ExperimentalGetImage::class])
    private fun analyse(proxy: ImageProxy) {
        // Read once: dispose may clear the field from the main thread.
        val current = scanner
        val image = proxy.image
        if (!detecting || current == null || image == null) {
            proxy.close()
            return
        }
        val rotation = proxy.imageInfo.rotationDegrees
        val frameWidth = proxy.width
        val frameHeight = proxy.height
        current.process(InputImage.fromMediaImage(image, rotation))
            .addOnSuccessListener(CameraSetup.direct) { barcodes ->
                onBarcodes(barcodes, rotation, frameWidth, frameHeight)
            }
            .addOnFailureListener(CameraSetup.direct) { e -> Log.e(TAG, "analyse: ${e.message}") }
            .addOnCompleteListener(CameraSetup.direct) { proxy.close() }
    }

    private fun onBarcodes(barcodes: List<Barcode>, rotation: Int, frameWidth: Int, frameHeight: Int) {
        if (!detecting || barcodes.isEmpty() || viewWidth == 0 || viewHeight == 0) return
        val window = scanOverlay.copyWindow()
        if (window.isEmpty) return

        val now = SystemClock.elapsedRealtime()
        for (barcode in barcodes) {
            val box = barcode.boundingBox ?: continue
            val value = barcode.rawValue?.takeIf { it.isNotEmpty() } ?: continue
            // The whole code has to sit inside the window.
            if (!window.contains(mapToView(box, rotation, frameWidth, frameHeight))) continue
            // Every code in the window goes through the gate, which follows
            // each one on its own.
            if (!gate.accept(value, now)) continue

            main.post {
                if (!disposed) methodChannel.invokeMethod("onBarcodeDetected", value)
            }
            if (!options.continuous) {
                // Waits for resumeScanning before reading another one.
                detecting = false
                main.post { scanOverlay.paused = true }
                return
            }
        }
    }

    /**
     * Maps a box from the upright analysed frame onto the preview, which is
     * centre cropped to fill the view, and mirrored for a front camera.
     */
    private fun mapToView(box: Rect, rotation: Int, frameWidth: Int, frameHeight: Int): RectF {
        val swapped = rotation == 90 || rotation == 270
        val imageWidth = (if (swapped) frameHeight else frameWidth).toFloat()
        val imageHeight = (if (swapped) frameWidth else frameHeight).toFloat()

        val scale = maxOf(viewWidth / imageWidth, viewHeight / imageHeight)
        val offsetX = (viewWidth - imageWidth * scale) / 2f
        val offsetY = (viewHeight - imageHeight * scale) / 2f

        val left = if (mirrored) imageWidth - box.right else box.left.toFloat()
        val right = if (mirrored) imageWidth - box.left else box.right.toFloat()

        return RectF(
            left * scale + offsetX,
            box.top * scale + offsetY,
            right * scale + offsetX,
            box.bottom * scale + offsetY,
        )
    }

    private fun reportError(code: String, message: String) {
        val error = mapOf("code" to code, "message" to message)
        main.post {
            if (!disposed) methodChannel.invokeMethod("onError", error)
        }
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pauseScanning" -> {
                detecting = false
                scanOverlay.paused = true
                result.success(null)
            }
            "resumeScanning" -> {
                // The code that paused a single-shot view counts as new again.
                gate.reset()
                detecting = true
                scanOverlay.paused = false
                result.success(null)
            }
            "toggleFlash" -> {
                val bound = camera
                if (bound == null || !bound.cameraInfo.hasFlashUnit()) {
                    result.success(false)
                    return
                }
                // From the camera's own state: it turns the torch off by
                // itself when it closes, which a copy kept here would miss.
                val on = bound.cameraInfo.torchState.value != TorchState.ON
                bound.cameraControl.enableTorch(on)
                result.success(on)
            }
            else -> result.notImplemented()
        }
    }

    override fun dispose() {
        disposed = true
        detecting = false
        methodChannel.setMethodCallHandler(null)
        main.removeCallbacksAndMessages(null)
        host.removeHostListener(hostListener)
        hostLifecycle?.removeObserver(hostObserver)
        hostLifecycle = null
        if (lifecycleRegistry.currentState != Lifecycle.State.INITIALIZED) {
            lifecycleRegistry.currentState = Lifecycle.State.DESTROYED
        }
        val bound = listOfNotNull(preview, analysis)
        if (bound.isNotEmpty()) cameraProvider?.unbind(*bound.toTypedArray())
        analysis?.clearAnalyzer()
        cameraProvider = null
        preview = null
        analysis = null
        camera = null
        analysisExecutor?.shutdown()
        analysisExecutor = null
        scanner?.close()
        scanner = null
    }

    private companion object {
        const val TAG = "EmbeddedScannerView"

        fun matchParent() = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
    }
}
