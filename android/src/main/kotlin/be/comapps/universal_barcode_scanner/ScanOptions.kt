package be.comapps.universal_barcode_scanner

import android.content.Intent
import androidx.camera.core.CameraSelector
import androidx.core.graphics.toColorInt
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.common.Barcode

/**
 * What the Dart side asked for, parsed once.
 *
 * It travels to the scanner activity as intent extras rather than through
 * static fields, so it survives the activity being recreated, and two
 * scanners never read each other's settings.
 */
internal data class ScanOptions(
    /** Tags every answer and event of this scan; see `NativeScanner`. */
    val session: Int,
    val lineColor: Int,
    val cancelButtonText: String,
    val showFlashIcon: Boolean,
    val continuous: Boolean,
    /** `qr`, `barcode` or `defaultMode`. */
    val scanType: String,
    /** `back` or `front`. */
    val cameraFace: String,
    /** `ALL_FORMATS`, `ONLY_QR_CODE` or `ONLY_BARCODE`. */
    val scanFormat: String,
    val delayMillis: Int,
) {

    /** Whether the scan window is square, for QR codes, rather than wide. */
    val squareWindow: Boolean
        get() = scanType != "barcode"

    val lensFacing: Int
        get() = if (cameraFace == "front") {
            CameraSelector.LENS_FACING_FRONT
        } else {
            CameraSelector.LENS_FACING_BACK
        }

    /**
     * The symbologies ML Kit looks for. Fewer formats is less work on every
     * frame, so a restricted list is also the faster one.
     */
    fun mlKitOptions(): BarcodeScannerOptions {
        val builder = BarcodeScannerOptions.Builder()
        when (scanFormat) {
            "ONLY_QR_CODE" -> builder.setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            "ONLY_BARCODE" -> builder.setBarcodeFormats(
                Barcode.FORMAT_CODABAR,
                Barcode.FORMAT_CODE_128,
                Barcode.FORMAT_CODE_39,
                Barcode.FORMAT_CODE_93,
                Barcode.FORMAT_EAN_13,
                Barcode.FORMAT_EAN_8,
                Barcode.FORMAT_ITF,
                Barcode.FORMAT_PDF417,
                Barcode.FORMAT_UPC_A,
                Barcode.FORMAT_UPC_E,
            )
            else -> builder.setBarcodeFormats(Barcode.FORMAT_ALL_FORMATS)
        }
        return builder.build()
    }

    fun writeTo(intent: Intent): Intent = intent
        .putExtra(EXTRA_PREFIX + "session", session)
        .putExtra(EXTRA_PREFIX + "lineColor", lineColor)
        .putExtra(EXTRA_PREFIX + "cancelButtonText", cancelButtonText)
        .putExtra(EXTRA_PREFIX + "showFlashIcon", showFlashIcon)
        .putExtra(EXTRA_PREFIX + "continuous", continuous)
        .putExtra(EXTRA_PREFIX + "scanType", scanType)
        .putExtra(EXTRA_PREFIX + "cameraFace", cameraFace)
        .putExtra(EXTRA_PREFIX + "scanFormat", scanFormat)
        .putExtra(EXTRA_PREFIX + "delayMillis", delayMillis)

    companion object {
        private const val EXTRA_PREFIX = "be.comapps.universal_barcode_scanner."

        /** Fallback when the colour cannot be read: the Dart default. */
        private const val DEFAULT_LINE_COLOR = 0xFFFF6666.toInt()

        /** Reads the arguments of a channel call, tolerating missing keys. */
        fun fromMap(map: Map<*, *>?): ScanOptions = ScanOptions(
            session = sessionOf(map),
            lineColor = parseColor(map?.get("lineColor") as? String),
            cancelButtonText = (map?.get("cancelButtonText") as? String).orIfEmpty("Cancel"),
            showFlashIcon = map?.get("showFlashIcon") == true,
            continuous = map?.get("continuous") == true,
            scanType = (map?.get("scanType") as? String).orIfEmpty("barcode"),
            cameraFace = (map?.get("cameraFace") as? String).orIfEmpty("back"),
            scanFormat = (map?.get("scanFormat") as? String).orIfEmpty("ALL_FORMATS"),
            // The codec sends an int or a long depending on the size.
            delayMillis = ((map?.get("delayMillis") as? Number)?.toInt() ?: 0).coerceAtLeast(0),
        )

        fun fromIntent(intent: Intent): ScanOptions = ScanOptions(
            session = intent.getIntExtra(EXTRA_PREFIX + "session", NO_SESSION),
            lineColor = intent.getIntExtra(EXTRA_PREFIX + "lineColor", DEFAULT_LINE_COLOR),
            cancelButtonText = intent.getStringExtra(EXTRA_PREFIX + "cancelButtonText").orIfEmpty("Cancel"),
            showFlashIcon = intent.getBooleanExtra(EXTRA_PREFIX + "showFlashIcon", false),
            continuous = intent.getBooleanExtra(EXTRA_PREFIX + "continuous", false),
            scanType = intent.getStringExtra(EXTRA_PREFIX + "scanType").orIfEmpty("barcode"),
            cameraFace = intent.getStringExtra(EXTRA_PREFIX + "cameraFace").orIfEmpty("back"),
            scanFormat = intent.getStringExtra(EXTRA_PREFIX + "scanFormat").orIfEmpty("ALL_FORMATS"),
            delayMillis = intent.getIntExtra(EXTRA_PREFIX + "delayMillis", 0),
        )

        /** Marks a call that named no session. */
        const val NO_SESSION = -1

        /** The session a channel call names, or [NO_SESSION]. */
        fun sessionOf(map: Map<*, *>?): Int =
            (map?.get("session") as? Number)?.toInt() ?: NO_SESSION

        /** A dimension that may be absent, in logical pixels; zero when it is. */
        fun optionalDouble(map: Map<*, *>?, key: String): Double =
            (map?.get(key) as? Number)?.toDouble() ?: 0.0

        /** Reads `#AARRGGBB` or `#RRGGBB`. */
        private fun parseColor(hex: String?): Int {
            if (hex.isNullOrEmpty()) return DEFAULT_LINE_COLOR
            return try {
                hex.toColorInt()
            } catch (e: IllegalArgumentException) {
                DEFAULT_LINE_COLOR
            }
        }

        private fun String?.orIfEmpty(fallback: String): String =
            if (isNullOrEmpty()) fallback else this
    }
}
