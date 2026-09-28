package be.comapps.universal_barcode_scanner

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.widget.Button
import android.widget.ImageView
import androidx.activity.OnBackPressedCallback
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.TorchState
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updateLayoutParams
import androidx.core.view.updatePadding
import be.comapps.universal_barcode_scanner.camera.CameraSetup
import be.comapps.universal_barcode_scanner.camera.ScannerOverlay
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.lang.ref.WeakReference
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Full screen scanner: a CameraX preview with an ML Kit analyser on every
 * frame.
 *
 * A single scan ends with the activity's result: the code, nothing when
 * cancelled, or an error code. A continuous scan pushes every code to the
 * event channel and says so when it closes, whichever way it closes.
 */
class BarcodeCaptureActivity : AppCompatActivity(), View.OnClickListener {

    private lateinit var options: ScanOptions
    private lateinit var gate: ReadGate

    private lateinit var previewView: PreviewView
    private lateinit var flashButton: ImageView
    private lateinit var switchButton: ImageView

    private lateinit var scaleGestureDetector: ScaleGestureDetector
    private lateinit var gestureDetector: GestureDetector

    private var cameraProvider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var preview: Preview? = null
    private var analysis: ImageAnalysis? = null
    private var scanner: BarcodeScanner? = null
    private var analysisExecutor: ExecutorService? = null
    private val handler = Handler(Looper.getMainLooper())

    private var lensFacing = CameraSelector.LENS_FACING_BACK

    /** Mirrors the camera's own torch state, which it turns off by itself. */
    private var torchOn = false

    /** Set once the scan has an outcome, so nothing reports twice. */
    private val finished = AtomicBoolean(false)

    // Registered before the activity starts, as the result API requires.
    private val permissionRequest =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) {
                startCamera()
            } else {
                // The app tells its user in its own way: the scanner only reports.
                finishWithError(ScanErrors.PERMISSION_DENIED, "The camera permission was refused.")
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Edge to edge, as Android 15 enforces anyway: the bottom bar is
        // padded by the navigation bar below instead of sitting under it.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
        options = ScanOptions.fromIntent(intent)
        current = WeakReference(this)
        if (launchingSession == options.session) launchingSession = null

        // Closed from Dart before this activity existed.
        if (closedEarly.remove(options.session)) {
            finishCancelled()
            return
        }

        setContentView(R.layout.barcode_capture)
        applyInsets()

        gate = ReadGate(options.delayMillis.toLong())
        lensFacing = options.lensFacing

        findViewById<Button>(R.id.btnBarcodeCaptureCancel).apply {
            text = options.cancelButtonText
            setOnClickListener(this@BarcodeCaptureActivity)
        }

        // Both shown once the camera says it has a flash, or another lens.
        flashButton = findViewById<ImageView>(R.id.imgViewBarcodeCaptureUseFlash).apply {
            setOnClickListener(this@BarcodeCaptureActivity)
            visibility = View.GONE
        }
        switchButton = findViewById<ImageView>(R.id.imgViewSwitchCamera).apply {
            setOnClickListener(this@BarcodeCaptureActivity)
            visibility = View.GONE
        }

        findViewById<ScannerOverlay>(R.id.scannerOverlay)
            .configure(options.lineColor, options.squareWindow)

        previewView = findViewById(R.id.preview)
        scanner = BarcodeScanning.getClient(options.mlKitOptions())
        analysisExecutor = Executors.newSingleThreadExecutor()

        gestureDetector = GestureDetector(this, CaptureGestureListener())
        scaleGestureDetector = ScaleGestureDetector(this, ScaleListener())

        // Replaces onBackPressed, which predictive back no longer calls.
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                finishCancelled()
            }
        })

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            == PackageManager.PERMISSION_GRANTED
        ) {
            startCamera()
        } else if (savedInstanceState == null) {
            // Only the first time: after a recreation the pending request's
            // answer is delivered to the new callback, and asking again would
            // be answered at once, with a refusal.
            permissionRequest.launch(Manifest.permission.CAMERA)
        }
    }

    /** Pads the bottom bar by the navigation bar and any display cutout. */
    private fun applyInsets() {
        val bar = findViewById<View>(R.id.layoutBottom)
        val barHeight = bar.layoutParams.height
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.topLayout)) { _, insets ->
            val bars = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout(),
            )
            bar.updatePadding(left = bars.left, right = bars.right, bottom = bars.bottom)
            bar.updateLayoutParams { height = barHeight + bars.bottom }
            insets
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // The activity is not recreated on rotation, so the use cases are told.
        val rotation = displayRotation()
        preview?.targetRotation = rotation
        analysis?.targetRotation = rotation
    }

    private fun displayRotation(): Int = ContextCompat.getDisplayOrDefault(this).rotation

    /**
     * Waits for the camera provider, then binds. CameraX follows the activity
     * lifecycle from there, so pause and resume need nothing of their own.
     */
    private fun startCamera() {
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            // Too late: this instance is gone, and its failure is not the
            // scan's.
            if (isDestroyed || isFinishing) return@addListener
            cameraProvider = try {
                future.get()
            } catch (e: Exception) {
                finishWithError(
                    ScanErrors.CAMERA_UNAVAILABLE,
                    "The camera could not be started: ${e.message}",
                )
                return@addListener
            }
            if (!hasLens(lensFacing)) {
                // The asked-for lens is missing: take whichever exists.
                lensFacing = otherLens(lensFacing)
            }
            if (!bindCamera()) {
                finishWithError(ScanErrors.CAMERA_UNAVAILABLE, "No camera could be opened.")
                return@addListener
            }
            switchButton.visibility =
                if (hasLens(otherLens(lensFacing))) View.VISIBLE else View.GONE
        }, ContextCompat.getMainExecutor(this))
    }

    private fun hasLens(facing: Int): Boolean {
        val provider = cameraProvider ?: return false
        return try {
            provider.hasCamera(CameraSelector.Builder().requireLensFacing(facing).build())
        } catch (e: Exception) {
            false
        }
    }

    /** Binds preview and analysis to [lensFacing]; false if it failed. */
    private fun bindCamera(): Boolean {
        val provider = cameraProvider ?: return false
        val executor = analysisExecutor ?: return false
        if (isDestroyed || isFinishing) return false

        // Only what this screen bound: the camera may be held elsewhere too.
        camera?.cameraInfo?.torchState?.removeObservers(this)
        val previous = listOfNotNull(preview, analysis)
        if (previous.isNotEmpty()) provider.unbind(*previous.toTypedArray())

        val rotation = displayRotation()
        val newPreview = CameraSetup.preview(rotation).also {
            it.setSurfaceProvider(previewView.surfaceProvider)
        }
        val newAnalysis = CameraSetup.analysis(rotation).also {
            it.setAnalyzer(executor, ::analyse)
        }
        preview = newPreview
        analysis = newAnalysis

        val selector = CameraSelector.Builder().requireLensFacing(lensFacing).build()
        val bound = try {
            provider.bindToLifecycle(this, selector, newPreview, newAnalysis)
        } catch (e: Exception) {
            Log.e(TAG, "bindCamera: ${e.message}")
            camera = null
            return false
        }
        camera = bound

        val hasFlash = bound.cameraInfo.hasFlashUnit()
        flashButton.visibility =
            if (options.showFlashIcon && hasFlash) View.VISIBLE else View.GONE
        bound.cameraInfo.torchState.observe(this) { state ->
            torchOn = state == TorchState.ON
            renderTorch()
        }
        return true
    }

    @OptIn(markerClass = [ExperimentalGetImage::class])
    private fun analyse(proxy: ImageProxy) {
        // Read once: onDestroy may clear the fields from the main thread.
        val image = proxy.image
        val current = scanner
        if (image == null || current == null || finished.get()) {
            proxy.close()
            return
        }
        val input = InputImage.fromMediaImage(image, proxy.imageInfo.rotationDegrees)
        current.process(input)
            .addOnSuccessListener(CameraSetup.direct, ::onBarcodes)
            .addOnFailureListener(CameraSetup.direct) { e -> Log.e(TAG, "analyse: ${e.message}") }
            .addOnCompleteListener(CameraSetup.direct) { proxy.close() }
    }

    private fun onBarcodes(barcodes: List<Barcode>) {
        val now = SystemClock.elapsedRealtime()
        for (barcode in barcodes) {
            val value = barcode.rawValue?.takeIf { it.isNotEmpty() } ?: continue
            if (options.continuous) {
                // Every code in the frame goes through the gate, which
                // follows each one on its own.
                if (gate.accept(value, now)) ScanEvents.code(options.session, value)
            } else if (finished.compareAndSet(false, true)) {
                handler.post {
                    setResult(RESULT_OK, Intent().putExtra(EXTRA_CODE, value))
                    finish()
                }
                return
            }
        }
    }

    /** Leaves without a code. */
    internal fun finishCancelled() {
        if (!finished.compareAndSet(false, true)) return
        if (!options.continuous) setResult(RESULT_CANCELED)
        finish()
    }

    private fun finishWithError(code: String, message: String) {
        if (!finished.compareAndSet(false, true)) return
        if (options.continuous) {
            ScanEvents.error(options.session, code, message)
        } else {
            setResult(
                RESULT_CANCELED,
                Intent()
                    .putExtra(EXTRA_ERROR_CODE, code)
                    .putExtra(EXTRA_ERROR_MESSAGE, message),
            )
        }
        finish()
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        // The preview starts at the top left of the window, edge to edge, so
        // window coordinates are the preview's.
        val scaled = scaleGestureDetector.onTouchEvent(event)
        val tapped = gestureDetector.onTouchEvent(event)
        return scaled || tapped || super.onTouchEvent(event)
    }

    override fun onClick(v: View) {
        when (v.id) {
            R.id.imgViewBarcodeCaptureUseFlash -> {
                val bound = camera ?: return
                if (bound.cameraInfo.hasFlashUnit()) bound.cameraControl.enableTorch(!torchOn)
            }
            R.id.btnBarcodeCaptureCancel -> finishCancelled()
            R.id.imgViewSwitchCamera -> {
                val previous = lensFacing
                lensFacing = otherLens(lensFacing)
                if (!bindCamera()) {
                    lensFacing = previous
                    bindCamera()
                }
            }
        }
    }

    private fun renderTorch() {
        flashButton.setImageResource(
            if (torchOn) R.drawable.ubs_ic_flash_on else R.drawable.ubs_ic_flash_off,
        )
        // Read out as selected when on, for a screen reader.
        flashButton.isSelected = torchOn
    }

    override fun onDestroy() {
        super.onDestroy()
        if (current.get() === this) current = WeakReference(null)
        handler.removeCallbacksAndMessages(null)
        analysis?.clearAnalyzer()
        analysisExecutor?.shutdown()
        scanner?.close()
        // Every way out of a continuous scan ends here: the cancel button, the
        // back gesture, an error, or the plugin closing it.
        if (isFinishing && ::options.isInitialized && options.continuous) {
            ScanEvents.closed(options.session)
        }
    }

    /** A tap focuses the preview where it landed. */
    private inner class CaptureGestureListener : GestureDetector.SimpleOnGestureListener() {
        override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
            val bound = camera ?: return false
            if (e.y > previewView.height) return false
            val point = previewView.meteringPointFactory.createPoint(e.x, e.y)
            bound.cameraControl.startFocusAndMetering(FocusMeteringAction.Builder(point).build())
            return true
        }
    }

    /** A pinch scales the current zoom ratio. */
    private inner class ScaleListener : ScaleGestureDetector.OnScaleGestureListener {
        override fun onScale(detector: ScaleGestureDetector): Boolean {
            val bound = camera ?: return false
            val state = bound.cameraInfo.zoomState.value ?: return false
            bound.cameraControl.setZoomRatio(state.zoomRatio * detector.scaleFactor)
            return true
        }

        override fun onScaleBegin(detector: ScaleGestureDetector): Boolean = true

        override fun onScaleEnd(detector: ScaleGestureDetector) {}
    }

    internal companion object {
        private const val TAG = "BarcodeCaptureActivity"

        /** Key of the string extra carrying the code back to the plugin. */
        const val EXTRA_CODE = "be.comapps.universal_barcode_scanner.code"
        const val EXTRA_ERROR_CODE = "be.comapps.universal_barcode_scanner.errorCode"
        const val EXTRA_ERROR_MESSAGE = "be.comapps.universal_barcode_scanner.errorMessage"

        /** How long a started activity counts as opening before it is given up on. */
        private const val LAUNCH_TIMEOUT_MS = 5000L

        /** The scanner on screen, so the plugin can close it. Weak: never kept. */
        private var current = WeakReference<BarcodeCaptureActivity>(null)

        /** The session whose activity was started but not created yet. */
        private var launchingSession: Int? = null
        private var launchedAt = 0L

        /** Sessions closed from Dart before their activity was created. */
        private val closedEarly = mutableSetOf<Int>()

        /** Whether a scanner is on screen or on its way. */
        val isBusy: Boolean
            get() {
                if (current.get()?.isFinishing == false) return true
                return launchingSession != null &&
                    SystemClock.elapsedRealtime() - launchedAt < LAUNCH_TIMEOUT_MS
            }

        /** Records that [session]'s activity has been started. */
        fun launching(session: Int) {
            launchingSession = session
            launchedAt = SystemClock.elapsedRealtime()
        }

        fun launchFailed(session: Int) {
            if (launchingSession == session) launchingSession = null
        }

        /**
         * Closes [session]'s scanner, as if the user had cancelled, even
         * before its activity exists. [ScanOptions.NO_SESSION] closes
         * whichever is open.
         */
        fun close(session: Int) {
            val open = current.get()
            if (open != null && !open.isFinishing &&
                (session == ScanOptions.NO_SESSION || open.options.session == session)
            ) {
                open.finishCancelled()
            } else if (session != ScanOptions.NO_SESSION && launchingSession == session) {
                closedEarly += session
            }
        }

        fun codeFrom(data: Intent?): String? = data?.getStringExtra(EXTRA_CODE)

        private fun otherLens(facing: Int): Int =
            if (facing == CameraSelector.LENS_FACING_FRONT) {
                CameraSelector.LENS_FACING_BACK
            } else {
                CameraSelector.LENS_FACING_FRONT
            }
    }
}
