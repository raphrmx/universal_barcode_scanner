package be.comapps.universal_barcode_scanner

/**
 * Decides which of the codes read frame after frame are worth reporting.
 *
 * A code held in front of the camera is read on every frame. It is reported
 * once, and again only after it has been out of sight for
 * [SAME_CODE_GAP_MS]. Each code is followed on its own, so two codes in sight
 * are each reported once rather than alternately. No two codes are reported
 * less than [delayMillis] apart; a code the delay held back goes out as soon
 * as the delay allows, if it is still in sight.
 */
internal class ReadGate(delayMillis: Long) {

    private class Sighting(var seen: Long, var reported: Boolean)

    private val delayMillis = delayMillis.coerceAtLeast(0)
    private val sightings = HashMap<String, Sighting>()
    private var lastEmit: Long? = null

    @Synchronized
    fun accept(value: String, now: Long): Boolean {
        sightings.values.removeAll { now - it.seen >= SAME_CODE_GAP_MS }
        val sighting = sightings.getOrPut(value) { Sighting(now, reported = false) }
        sighting.seen = now
        if (sighting.reported) return false

        val emitted = lastEmit
        if (emitted != null && now - emitted < delayMillis) return false

        sighting.reported = true
        lastEmit = now
        return true
    }

    /** Forgets every code, so the ones in sight are reported again. */
    @Synchronized
    fun reset() {
        sightings.clear()
        lastEmit = null
    }

    companion object {
        const val SAME_CODE_GAP_MS = 1000L
    }
}
