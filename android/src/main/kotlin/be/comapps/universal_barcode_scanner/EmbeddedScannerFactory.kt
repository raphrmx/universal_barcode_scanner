package be.comapps.universal_barcode_scanner

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

internal class EmbeddedScannerFactory(
    private val messenger: BinaryMessenger,
    private val host: ScannerHost,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        EmbeddedScannerView(context, messenger, host, viewId, args as? Map<*, *>)
}
