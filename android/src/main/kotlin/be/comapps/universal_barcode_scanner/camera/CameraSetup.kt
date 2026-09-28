package be.comapps.universal_barcode_scanner.camera

import android.util.Size
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import java.util.concurrent.Executor

/** The use cases both scanners bind, built the same way. */
internal object CameraSetup {

    /**
     * Runs a task on the thread that finished the work. ML Kit's listeners use
     * it rather than the analysis executor, which is shut down when the
     * scanner closes and would then refuse a result still in flight.
     */
    val direct = Executor { it.run() }

    /**
     * Frames of about 1280 by 960 rather than CameraX's default 640 by 480:
     * ML Kit needs a couple of pixels per module, which a dense QR code or a
     * PDF417 does not get at the default. Both use cases are 4:3, so the
     * analysed frame and the preview show the same field.
     */
    private val resolution = ResolutionSelector.Builder()
        .setAspectRatioStrategy(AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY)
        .setResolutionStrategy(
            ResolutionStrategy(
                Size(1280, 960),
                ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER,
            ),
        )
        .build()

    private val previewAspect = ResolutionSelector.Builder()
        .setAspectRatioStrategy(AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY)
        .build()

    fun preview(rotation: Int): Preview = Preview.Builder()
        .setResolutionSelector(previewAspect)
        .setTargetRotation(rotation)
        .build()

    fun analysis(rotation: Int): ImageAnalysis = ImageAnalysis.Builder()
        .setResolutionSelector(resolution)
        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
        .setTargetRotation(rotation)
        .build()
}
