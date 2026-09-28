package be.comapps.universal_barcode_scanner;

import android.content.Intent;
import android.graphics.Color;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.camera.core.CameraSelector;

import com.google.mlkit.vision.barcode.BarcodeScannerOptions;
import com.google.mlkit.vision.barcode.common.Barcode;

import java.util.Map;

/**
 * What the Dart side asked for, parsed once.
 *
 * <p>It travels to the scanner activity as intent extras rather than through
 * static fields, so it survives the activity being recreated, and two
 * scanners never read each other's settings.
 */
public final class ScanOptions {

    private static final String EXTRA_PREFIX = "be.comapps.universal_barcode_scanner.";

    /** Fallback when the colour cannot be read: the Dart default. */
    private static final int DEFAULT_LINE_COLOR = 0xFFFF6666;

    public final int lineColor;
    public final String cancelButtonText;
    public final boolean showFlashIcon;
    public final boolean continuous;
    /** {@code qr}, {@code barcode} or {@code defaultMode}. */
    public final String scanType;
    /** {@code back} or {@code front}. */
    public final String cameraFace;
    /** {@code ALL_FORMATS}, {@code ONLY_QR_CODE} or {@code ONLY_BARCODE}. */
    public final String scanFormat;
    public final int delayMillis;

    private ScanOptions(int lineColor, String cancelButtonText, boolean showFlashIcon,
                        boolean continuous, String scanType, String cameraFace,
                        String scanFormat, int delayMillis) {
        this.lineColor = lineColor;
        this.cancelButtonText = cancelButtonText;
        this.showFlashIcon = showFlashIcon;
        this.continuous = continuous;
        this.scanType = scanType;
        this.cameraFace = cameraFace;
        this.scanFormat = scanFormat;
        this.delayMillis = delayMillis;
    }

    /** Reads the arguments of a channel call, tolerating missing keys. */
    @NonNull
    public static ScanOptions fromMap(@Nullable Map<?, ?> map) {
        return new ScanOptions(
                parseColor(string(map, "lineColor", null)),
                string(map, "cancelButtonText", "Cancel"),
                bool(map, "showFlashIcon"),
                bool(map, "continuous"),
                string(map, "scanType", "barcode"),
                string(map, "cameraFace", "back"),
                string(map, "scanFormat", "ALL_FORMATS"),
                Math.max(0, number(map, "delayMillis")));
    }

    @NonNull
    public static ScanOptions fromIntent(@NonNull Intent intent) {
        return new ScanOptions(
                intent.getIntExtra(EXTRA_PREFIX + "lineColor", DEFAULT_LINE_COLOR),
                orDefault(intent.getStringExtra(EXTRA_PREFIX + "cancelButtonText"), "Cancel"),
                intent.getBooleanExtra(EXTRA_PREFIX + "showFlashIcon", false),
                intent.getBooleanExtra(EXTRA_PREFIX + "continuous", false),
                orDefault(intent.getStringExtra(EXTRA_PREFIX + "scanType"), "barcode"),
                orDefault(intent.getStringExtra(EXTRA_PREFIX + "cameraFace"), "back"),
                orDefault(intent.getStringExtra(EXTRA_PREFIX + "scanFormat"), "ALL_FORMATS"),
                intent.getIntExtra(EXTRA_PREFIX + "delayMillis", 0));
    }

    @NonNull
    public Intent writeTo(@NonNull Intent intent) {
        return intent
                .putExtra(EXTRA_PREFIX + "lineColor", lineColor)
                .putExtra(EXTRA_PREFIX + "cancelButtonText", cancelButtonText)
                .putExtra(EXTRA_PREFIX + "showFlashIcon", showFlashIcon)
                .putExtra(EXTRA_PREFIX + "continuous", continuous)
                .putExtra(EXTRA_PREFIX + "scanType", scanType)
                .putExtra(EXTRA_PREFIX + "cameraFace", cameraFace)
                .putExtra(EXTRA_PREFIX + "scanFormat", scanFormat)
                .putExtra(EXTRA_PREFIX + "delayMillis", delayMillis);
    }

    /** Whether the scan window is square, for QR codes, rather than wide. */
    public boolean squareWindow() {
        return !"barcode".equals(scanType);
    }

    public int lensFacing() {
        return "front".equals(cameraFace)
                ? CameraSelector.LENS_FACING_FRONT
                : CameraSelector.LENS_FACING_BACK;
    }

    /**
     * The symbologies ML Kit looks for. Fewer formats is less work on every
     * frame, so a restricted list is also the faster one.
     */
    @NonNull
    public BarcodeScannerOptions mlKitOptions() {
        switch (scanFormat) {
            case "ONLY_QR_CODE":
                return new BarcodeScannerOptions.Builder()
                        .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
                        .build();
            case "ONLY_BARCODE":
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
            default:
                return new BarcodeScannerOptions.Builder()
                        .setBarcodeFormats(Barcode.FORMAT_ALL_FORMATS)
                        .build();
        }
    }

    /** Reads {@code #AARRGGBB} or {@code #RRGGBB}. */
    private static int parseColor(@Nullable String hex) {
        if (hex == null || hex.isEmpty()) {
            return DEFAULT_LINE_COLOR;
        }
        try {
            return Color.parseColor(hex);
        } catch (IllegalArgumentException e) {
            return DEFAULT_LINE_COLOR;
        }
    }

    @NonNull
    private static String orDefault(@Nullable String value, @NonNull String fallback) {
        return value == null || value.isEmpty() ? fallback : value;
    }

    private static String string(@Nullable Map<?, ?> map, String key, String fallback) {
        Object value = map == null ? null : map.get(key);
        return value instanceof String && !((String) value).isEmpty() ? (String) value : fallback;
    }

    private static boolean bool(@Nullable Map<?, ?> map, String key) {
        Object value = map == null ? null : map.get(key);
        return value instanceof Boolean && (Boolean) value;
    }

    /** The codec sends an int or a long depending on the size of the value. */
    private static int number(@Nullable Map<?, ?> map, String key) {
        Object value = map == null ? null : map.get(key);
        return value instanceof Number ? ((Number) value).intValue() : 0;
    }

    /** A dimension that may be absent, in logical pixels. */
    public static double optionalDouble(@Nullable Map<?, ?> map, String key) {
        Object value = map == null ? null : map.get(key);
        return value instanceof Number ? ((Number) value).doubleValue() : 0;
    }
}
