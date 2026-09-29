package be.comapps.universal_barcode_scanner

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * The event channel of a continuous scan, reachable from the scanner activity.
 *
 * An activity started by intent has no reference to the plugin, so the sink
 * is held here. Only the sink: the activity itself is never kept. Every event
 * carries the session it belongs to, so the Dart side can drop a late one from
 * a scanner that is already going away.
 */
internal object ScanEvents {

    private val main = Handler(Looper.getMainLooper())

    @Volatile
    private var sink: EventChannel.EventSink? = null

    fun attach(eventSink: EventChannel.EventSink?) {
        sink = eventSink
    }

    fun code(session: Int, value: String, format: String) {
        main.post {
            sink?.success(mapOf("session" to session, "code" to value, "format" to format))
        }
    }

    /** The scanner is gone, whichever way it went. */
    fun closed(session: Int) {
        main.post { sink?.success(mapOf("session" to session, "event" to "closed")) }
    }

    fun error(session: Int, code: String, message: String) {
        main.post { sink?.error(code, message, session) }
    }
}
