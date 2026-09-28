package be.comapps.universal_barcode_scanner;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.lifecycle.Lifecycle;

/**
 * What an embedded scanner view needs from the activity it lives in, which a
 * platform view cannot reach by itself.
 */
public interface ScannerHost {

    /** The activity's lifecycle, or null when there is no activity. */
    @Nullable
    Lifecycle hostLifecycle();

    /** Asks for the camera if needed, then says whether it was granted. */
    void requestCameraPermission(@NonNull PermissionCallback callback);

    interface PermissionCallback {
        void onResult(boolean granted);
    }
}
