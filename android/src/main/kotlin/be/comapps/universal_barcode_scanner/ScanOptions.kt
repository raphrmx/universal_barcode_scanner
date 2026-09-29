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
    val cancelLabel: String,
    val showTorchButton: Boolean,
    val continuous: Boolean,
    /** `square`, `wide` or `none`. */
    val scanWindow: String,
    /** `back` or `front`. */
    val cameraFace: String,
    /** `ALL_FORMATS`, `ONLY_QR_CODE` or `ONLY_BARCODE`. */
    val scanFormat: String,
    val delayMillis: Int,
    /** Size of the scan window asked for, in logical pixels; zero for the default. */
    val scanWindowWidth: Double = 0.0,
    val scanWindowHeight: Double = 0.0,
) {

    /** Whether the scan window is square, for QR codes, rather than wide. */
    val squareWindow: Boolean
        get() = scanWindow == "square"

    /** Whether a window is drawn and reading is limited to it. */
    val hasWindow: Boolean
        get() = scanWindow != "none"

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
        .putExtra(EXTRA_PREFIX + "cancelLabel", cancelLabel)
        .putExtra(EXTRA_PREFIX + "showTorchButton", showTorchButton)
        .putExtra(EXTRA_PREFIX + "continuous", continuous)
        .putExtra(EXTRA_PREFIX + "scanWindow", scanWindow)
        .putExtra(EXTRA_PREFIX + "cameraFace", cameraFace)
        .putExtra(EXTRA_PREFIX + "scanFormat", scanFormat)
        .putExtra(EXTRA_PREFIX + "delayMillis", delayMillis)
        .putExtra(EXTRA_PREFIX + "scanWindowWidth", scanWindowWidth)
        .putExtra(EXTRA_PREFIX + "scanWindowHeight", scanWindowHeight)

    companion object {
        private const val EXTRA_PREFIX = "be.comapps.universal_barcode_scanner."

        /** Fallback when the colour cannot be read: the Dart default. */
        private const val DEFAULT_LINE_COLOR = 0xFFFF6666.toInt()

        /** Reads the arguments of a channel call, tolerating missing keys. */
        fun fromMap(map: Map<*, *>?): ScanOptions = ScanOptions(
            session = sessionOf(map),
            lineColor = parseColor(map?.get("lineColor") as? String),
            cancelLabel = (map?.get("cancelLabel") as? String).orIfEmpty("Cancel"),
            showTorchButton = map?.get("showTorchButton") == true,
            continuous = map?.get("continuous") == true,
            scanWindow = (map?.get("scanWindow") as? String).orIfEmpty("wide"),
            cameraFace = (map?.get("cameraFace") as? String).orIfEmpty("back"),
            scanFormat = (map?.get("scanFormat") as? String).orIfEmpty("ALL_FORMATS"),
            // The codec sends an int or a long depending on the size.
            delayMillis = ((map?.get("delayMillis") as? Number)?.toInt() ?: 0).coerceAtLeast(0),
            scanWindowWidth = optionalDouble(map, "scanWindowWidth"),
            scanWindowHeight = optionalDouble(map, "scanWindowHeight"),
        )

        fun fromIntent(intent: Intent): ScanOptions = ScanOptions(
            session = intent.getIntExtra(EXTRA_PREFIX + "session", NO_SESSION),
            lineColor = intent.getIntExtra(EXTRA_PREFIX + "lineColor", DEFAULT_LINE_COLOR),
            cancelLabel = intent.getStringExtra(EXTRA_PREFIX + "cancelLabel").orIfEmpty("Cancel"),
            showTorchButton = intent.getBooleanExtra(EXTRA_PREFIX + "showTorchButton", false),
            continuous = intent.getBooleanExtra(EXTRA_PREFIX + "continuous", false),
            scanWindow = intent.getStringExtra(EXTRA_PREFIX + "scanWindow").orIfEmpty("wide"),
            cameraFace = intent.getStringExtra(EXTRA_PREFIX + "cameraFace").orIfEmpty("back"),
            scanFormat = intent.getStringExtra(EXTRA_PREFIX + "scanFormat").orIfEmpty("ALL_FORMATS"),
            delayMillis = intent.getIntExtra(EXTRA_PREFIX + "delayMillis", 0),
            scanWindowWidth = intent.getDoubleExtra(EXTRA_PREFIX + "scanWindowWidth", 0.0),
            scanWindowHeight = intent.getDoubleExtra(EXTRA_PREFIX + "scanWindowHeight", 0.0),
        )

        /** The name every platform gives ML Kit's [format], as the web's BarcodeDetector does. */
        fun formatName(format: Int): String = when (format) {
            Barcode.FORMAT_AZTEC -> "aztec"
            Barcode.FORMAT_CODABAR -> "codabar"
            Barcode.FORMAT_CODE_39 -> "code_39"
            Barcode.FORMAT_CODE_93 -> "code_93"
            Barcode.FORMAT_CODE_128 -> "code_128"
            Barcode.FORMAT_DATA_MATRIX -> "data_matrix"
            Barcode.FORMAT_EAN_8 -> "ean_8"
            Barcode.FORMAT_EAN_13 -> "ean_13"
            Barcode.FORMAT_ITF -> "itf"
            Barcode.FORMAT_PDF417 -> "pdf417"
            Barcode.FORMAT_QR_CODE -> "qr_code"
            Barcode.FORMAT_UPC_A -> "upc_a"
            Barcode.FORMAT_UPC_E -> "upc_e"
            else -> "unknown"
        }

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
