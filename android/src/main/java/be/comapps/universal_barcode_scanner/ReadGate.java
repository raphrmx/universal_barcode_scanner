package be.comapps.universal_barcode_scanner;

import androidx.annotation.NonNull;

/**
 * Decides which of the codes read frame after frame are worth reporting.
 *
 * <p>A code held in front of the camera is read on every frame. It is reported
 * once, and again only after it has been out of sight for
 * {@link #SAME_CODE_GAP_MS}. On top of that, no two codes are reported less
 * than the requested delay apart.
 */
public final class ReadGate {

    static final long SAME_CODE_GAP_MS = 1000;

    private final long delayMillis;

    private String lastValue;
    private long lastSeen;
    private long lastEmit;
    private boolean emitted;

    public ReadGate(long delayMillis) {
        this.delayMillis = Math.max(0, delayMillis);
    }

    public synchronized boolean accept(@NonNull String value, long now) {
        if (value.equals(lastValue)) {
            boolean held = now - lastSeen < SAME_CODE_GAP_MS;
            lastSeen = now;
            if (held) {
                return false;
            }
        }
        if (emitted && now - lastEmit < delayMillis) {
            return false;
        }
        lastValue = value;
        lastSeen = now;
        lastEmit = now;
        emitted = true;
        return true;
    }

    /** Forgets the last code, so the same one is reported again. */
    public synchronized void reset() {
        lastValue = null;
        emitted = false;
    }
}
