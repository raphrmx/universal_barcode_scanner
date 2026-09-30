package be.comapps.universal_barcode_scanner

/** Error codes shared with the Dart side's `ScannerErrorCode`. */
internal object ScanErrors {
    const val PERMISSION_DENIED = "camera_permission_denied"
    const val CAMERA_UNAVAILABLE = "camera_unavailable"
    const val ALREADY_ACTIVE = "already_active"
    const val INVALID_IMAGE = "invalid_image"
    const val UNKNOWN = "unknown"
}
