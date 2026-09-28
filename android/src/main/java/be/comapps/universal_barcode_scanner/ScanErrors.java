package be.comapps.universal_barcode_scanner;

/** Error codes shared with the Dart side's {@code ScannerErrorCode}. */
public final class ScanErrors {

    public static final String PERMISSION_DENIED = "camera_permission_denied";
    public static final String CAMERA_UNAVAILABLE = "camera_unavailable";
    public static final String ALREADY_ACTIVE = "already_active";

    private ScanErrors() {
    }
}
