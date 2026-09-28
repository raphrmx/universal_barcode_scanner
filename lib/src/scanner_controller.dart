import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:universal_barcode_scanner/src/scanner_exception.dart';

/// Called once the embedded scanner exists, with the controller that drives
/// it.
typedef ScannerCreatedCallback = void Function(ScannerController controller);

/// Drives an embedded scanner: torch, pause, resume.
///
/// An instance is handed to `onCreated` once the platform view is up. There is
/// one channel per view, keyed on the view id.
class ScannerController {
  /// Binds to the platform view with the given [id]. The widget creates it.
  ScannerController(int id)
    : _channel = MethodChannel('universal_barcode_scanner/view_$id') {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  final MethodChannel _channel;

  /// Called with every code the view reads. Assign it before the first scan.
  ValueChanged<String>? onScanned;

  /// Called when the view cannot use the camera.
  ValueChanged<ScannerException>? onError;

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onBarcodeDetected':
        final Object? code = call.arguments;
        if (code is String && code.isNotEmpty) onScanned?.call(code);
      case 'onError':
        final Object? arguments = call.arguments;
        final ScannerException error = arguments is Map
            ? ScannerException(
                ScannerErrorCode.fromWire('${arguments['code']}'),
                arguments['message'] as String?,
              )
            : ScannerException(ScannerErrorCode.unknown, '$arguments');
        final ValueChanged<ScannerException>? handler = onError;
        if (handler == null) {
          debugPrint('universal_barcode_scanner: $error');
        } else {
          handler(error);
        }
    }
  }

  /// Toggles the torch and returns whether it is now on.
  Future<bool> toggleFlash() async =>
      await _channel.invokeMethod<bool>('toggleFlash') ?? false;

  /// Stops reading without tearing the camera down.
  Future<void> pauseScanning() => _channel.invokeMethod<void>('pauseScanning');

  /// Resumes after [pauseScanning], or after the first code of a view that is
  /// not continuous.
  Future<void> resumeScanning() =>
      _channel.invokeMethod<void>('resumeScanning');

  /// Stops listening to the view. The widget calls it when it goes away; the
  /// controller does nothing useful afterwards.
  void dispose() {
    _channel.setMethodCallHandler(null);
    onScanned = null;
    onError = null;
  }
}
