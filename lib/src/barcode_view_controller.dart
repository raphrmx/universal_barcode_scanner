import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Called once the embedded scanner view exists, with the controller that
/// drives it.
typedef BarcodeScannerViewCreated =
    void Function(BarcodeViewController controller);

/// Drives an embedded scanner view: flash, pause, resume.
///
/// An instance is handed to `onBarcodeViewCreated` once the platform view is
/// up. There is one channel per view, keyed on the view id.
class BarcodeViewController {
  /// Binds to the platform view with the given [id].
  BarcodeViewController.data(int id)
    : _channel = MethodChannel('universal_barcode_scanner/view_$id') {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  final MethodChannel _channel;

  /// Called with every code the view reads. Assign it before the first scan.
  ValueChanged<String>? onScanned;

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onBarcodeDetected':
        final Object? code = call.arguments;
        if (code is String) onScanned?.call(code);
      case 'onError':
        debugPrint('universal_barcode_scanner: ${call.arguments}');
      default:
        debugPrint('universal_barcode_scanner: unhandled ${call.method}');
    }
  }

  /// Toggles the torch.
  Future<void> toggleFlash() => _channel.invokeMethod('toggleFlash');

  /// Stops reading without tearing the camera down.
  Future<void> pauseScanning() => _channel.invokeMethod('pauseScanning');

  /// Resumes after [pauseScanning].
  Future<void> resumeScanning() => _channel.invokeMethod('resumeScanning');
}
