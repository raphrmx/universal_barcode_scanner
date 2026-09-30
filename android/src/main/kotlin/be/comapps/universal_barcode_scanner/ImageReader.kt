package be.comapps.universal_barcode_scanner

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

/**
 * Reads every code in an encoded image, with ML Kit and without the camera.
 *
 * The bytes go through a file in the cache: `InputImage.fromFilePath` is the
 * form that opens any format the platform decodes and turns the picture the
 * way its EXIF says, so a photo taken sideways reads as it was shot.
 */
internal object ImageReader {

    fun read(context: Context, bytes: ByteArray, scanFormat: String, result: MethodChannel.Result) {
        // Only the header is read here: whether the bytes are an image at all.
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            result.error(ScanErrors.INVALID_IMAGE, "The bytes are not an image Android opens.", null)
            return
        }

        val file = try {
            File.createTempFile("universal_barcode_scanner", ".img", context.cacheDir)
                .apply { writeBytes(bytes) }
        } catch (e: IOException) {
            result.error(ScanErrors.UNKNOWN, "The image could not be written to the cache: ${e.message}", null)
            return
        }
        val image = try {
            InputImage.fromFilePath(context, Uri.fromFile(file))
        } catch (e: IOException) {
            file.delete()
            result.error(ScanErrors.INVALID_IMAGE, e.message, null)
            return
        }

        val scanner = BarcodeScanning.getClient(ScanOptions.mlKitOptionsFor(scanFormat))
        scanner.process(image)
            .addOnSuccessListener { barcodes ->
                result.success(
                    barcodes.mapNotNull { barcode ->
                        barcode.rawValue?.takeIf { it.isNotEmpty() }?.let {
                            mapOf("code" to it, "format" to ScanOptions.formatName(barcode.format))
                        }
                    },
                )
            }
            .addOnFailureListener { e -> result.error(ScanErrors.UNKNOWN, e.message, null) }
            .addOnCompleteListener {
                scanner.close()
                file.delete()
            }
    }
}
