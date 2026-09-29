import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:universal_barcode_scanner/src/scanner_exception.dart';

/// Called once the embedded scanner exists, with the controller that drives
/// it.
typedef ScannerCreatedCallback = void Function(ScannerController controller);

/// Drives an embedded scanner: torch, pause, resume.
///
/// The widget creates one and hands it to `onCreated` once the scanner is up.
/// Every platform has its own implementation behind this interface.
abstract class ScannerController {
  /// For the implementations of each platform.
  ScannerController();

  bool _disposed = false;

  /// Called with every code the view reads. Assign it before the first scan.
  ValueChanged<String>? onScanned;

  /// Called when the view cannot use the camera.
  ValueChanged<ScannerException>? onError;

  /// Toggles the torch and returns whether it is now on. Always false where
  /// the camera has no torch the platform lets an app drive, which is most
  /// webcams.
  Future<bool> toggleFlash();

  /// Stops reading without tearing the camera down.
  Future<void> pauseScanning();

  /// Resumes after [pauseScanning], or after the first code of a view that is
  /// not continuous.
  Future<void> resumeScanning();

  /// Stops listening to the view. The widget calls it when it goes away; the
  /// controller does nothing useful afterwards.
  @mustCallSuper
  void dispose() {
    _disposed = true;
    onScanned = null;
    onError = null;
  }

  /// Whether [dispose] has run.
  @protected
  bool get isDisposed => _disposed;

  /// Hands a code the view read to [onScanned].
  @protected
  void deliverCode(String code) {
    if (_disposed || code.isEmpty) return;
    onScanned?.call(code);
  }

  /// Hands an error to [onError], or logs it when nobody listens.
  @protected
  void deliverError(ScannerException error) {
    if (_disposed) return;
    final ValueChanged<ScannerException>? handler = onError;
    if (handler == null) {
      debugPrint('universal_barcode_scanner: $error');
    } else {
      handler(error);
    }
  }
}

/// The controller of an Android, iOS or macOS view: one channel per view,
/// keyed on the view id.
final class ChannelScannerController extends ScannerController {
  /// Binds to the platform view with the given [id].
  ChannelScannerController(int id)
    : _channel = MethodChannel('universal_barcode_scanner/view_$id') {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  final MethodChannel _channel;

  /// Called once the view's camera shows its first frame.
  VoidCallback? onCameraStarted;

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onCameraStarted':
        if (!isDisposed) onCameraStarted?.call();
      case 'onBarcodeDetected':
        final Object? code = call.arguments;
        if (code is String) deliverCode(code);
      case 'onError':
        final Object? arguments = call.arguments;
        deliverError(
          arguments is Map
              ? ScannerException(
                  ScannerErrorCode.fromWire('${arguments['code']}'),
                  arguments['message'] as String?,
                )
              : ScannerException(ScannerErrorCode.unknown, '$arguments'),
        );
    }
  }

  @override
  Future<bool> toggleFlash() async =>
      await _channel.invokeMethod<bool>('toggleFlash') ?? false;

  @override
  Future<void> pauseScanning() => _channel.invokeMethod<void>('pauseScanning');

  @override
  Future<void> resumeScanning() =>
      _channel.invokeMethod<void>('resumeScanning');

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
