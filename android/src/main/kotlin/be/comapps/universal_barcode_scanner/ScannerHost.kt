package be.comapps.universal_barcode_scanner

import androidx.lifecycle.Lifecycle

/**
 * What an embedded scanner view needs from the activity it lives in, which a
 * platform view cannot reach by itself.
 */
internal interface ScannerHost {

    /** The activity's lifecycle, or null when there is no activity. */
    val hostLifecycle: Lifecycle?

    /**
     * Called with the new lifecycle whenever the engine moves to another
     * activity, or with null when it has none left.
     */
    fun addHostListener(listener: (Lifecycle?) -> Unit)

    fun removeHostListener(listener: (Lifecycle?) -> Unit)

    /** Asks for the camera if needed, then says whether it was granted. */
    fun requestCameraPermission(onResult: (granted: Boolean) -> Unit)
}
