package be.comapps.universal_barcode_scanner.widget

import android.content.Context
import be.comapps.universal_barcode_scanner.ScannerHost
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

internal class BarcodeViewFactory(
    private val messenger: BinaryMessenger,
    private val host: ScannerHost,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        FlutterBarcodeView(context, messenger, host, viewId, args as? Map<*, *>)
}
