package be.comapps.universal_barcode_scanner.widget;

import android.content.Context;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.util.Map;

import be.comapps.universal_barcode_scanner.ScannerHost;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;

public class BarcodeViewFactory extends PlatformViewFactory {
    private final BinaryMessenger messenger;
    private final ScannerHost host;

    public BarcodeViewFactory(@NonNull BinaryMessenger messenger, @NonNull ScannerHost host) {
        super(StandardMessageCodec.INSTANCE);
        this.messenger = messenger;
        this.host = host;
    }

    @NonNull
    @Override
    public PlatformView create(@NonNull Context context, int id, @Nullable Object creationParams) {
        Map<?, ?> params = creationParams instanceof Map ? (Map<?, ?>) creationParams : null;
        return new FlutterBarcodeView(context, messenger, host, id, params);
    }
}
