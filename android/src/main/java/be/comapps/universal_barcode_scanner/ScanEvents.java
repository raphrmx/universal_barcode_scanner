package be.comapps.universal_barcode_scanner;

import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.util.Collections;

import io.flutter.plugin.common.EventChannel;

/**
 * The event channel of a continuous scan, reachable from the scanner activity.
 *
 * <p>An activity started by intent has no reference to the plugin, so the sink
 * is held here. Only the sink: the activity itself is never kept.
 */
final class ScanEvents {

    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    @Nullable
    private static volatile EventChannel.EventSink sink;

    private ScanEvents() {
    }

    static void attach(@Nullable EventChannel.EventSink eventSink) {
        sink = eventSink;
    }

    static void code(@NonNull String value) {
        MAIN.post(() -> {
            EventChannel.EventSink current = sink;
            if (current != null) {
                current.success(value);
            }
        });
    }

    /** The scanner is gone, whichever way it went. */
    static void closed() {
        MAIN.post(() -> {
            EventChannel.EventSink current = sink;
            if (current != null) {
                current.success(Collections.singletonMap("event", "closed"));
            }
        });
    }

    static void error(@NonNull String code, @NonNull String message) {
        MAIN.post(() -> {
            EventChannel.EventSink current = sink;
            if (current != null) {
                current.error(code, message, null);
            }
        });
    }
}
