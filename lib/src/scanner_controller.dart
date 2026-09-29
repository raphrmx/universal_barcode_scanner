import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:universal_barcode_scanner/src/scan_result.dart';
import 'package:universal_barcode_scanner/src/scanner_exception.dart';

/// Called once the embedded scanner exists, with the controller that drives
/// it.
typedef ScannerCreatedCallback = void Function(ScannerController controller);

/// Drives an embedded scanner: torch, pause, resume, zoom.
///
/// The widget creates one and hands it to `onCreated` once the scanner is up.
/// Every platform has its own implementation behind this interface.
abstract class ScannerController {
  /// For the implementations of each platform.
  ScannerController();

  bool _disposed = false;

  /// Called with every code the view reads. Assign it before the first scan.
  ValueChanged<String>? onScanned;

  /// Called with every code the view reads, with the symbology it was
  /// printed in.
  ValueChanged<ScanResult>? onResult;

  // Never disposed: the buttons listening to them may outlive the view.
  final ValueNotifier<bool> _paused = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _torch = ValueNotifier<bool>(false);
  final ValueNotifier<double> _zoom = ValueNotifier<double>(1);

  /// Whether the view has stopped reading: through [pauseScanning], or on its
  /// own after the first code of a view that is not continuous.
  ValueListenable<bool> get isPaused => _paused;

  /// Whether the torch is on, as the view last said.
  ValueListenable<bool> get isTorchOn => _torch;

  /// The zoom the camera shows, `1` for none.
  ValueListenable<double> get zoom => _zoom;

  /// Records that the view stopped or resumed reading.
  @protected
  void markPaused(bool paused) {
    if (!_disposed) _paused.value = paused;
  }

  /// Records the torch's state as the view gave it.
  @protected
  void markTorch(bool on) {
    if (!_disposed) _torch.value = on;
  }

  /// Records the zoom the camera applied.
  @protected
  void markZoom(double zoom) {
    if (!_disposed) _zoom.value = zoom;
  }

  /// Sets the zoom, `1` for none, and returns the one the camera applied:
  /// clamped to what it can do, and `1` where it cannot zoom at all, as on
  /// most webcams.
  Future<double> setZoom(double zoom) async => 1;

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
    onResult = null;
    onError = null;
  }

  /// Whether [dispose] has run.
  @protected
  bool get isDisposed => _disposed;

  /// Hands a code the view read to [onScanned] and [onResult].
  @protected
  void deliverCode(
    String code, {
    BarcodeFormat format = BarcodeFormat.unknown,
  }) {
    if (_disposed || code.isEmpty) return;
    onScanned?.call(code);
    onResult?.call(ScanResult(code, format: format));
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
  /// Binds to the platform view with the given [id]. A view that is not
  /// [continuous] pauses on its first code.
  ChannelScannerController(int id, {bool continuous = true})
    : _continuous = continuous,
      _channel = MethodChannel('universal_barcode_scanner/view_$id') {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  final MethodChannel _channel;
  final bool _continuous;

  /// Called once the view's camera shows its first frame.
  VoidCallback? onCameraStarted;

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onCameraStarted':
        if (!isDisposed) onCameraStarted?.call();
      case 'onBarcodeDetected':
        // A map with the format, or the bare code from an older view.
        final Object? arguments = call.arguments;
        final (String? code, BarcodeFormat format) = switch (arguments) {
          {'code': final String code} => (
            code,
            BarcodeFormat.fromWire((arguments as Map)['format']),
          ),
          final String code => (code, BarcodeFormat.unknown),
          _ => (null, BarcodeFormat.unknown),
        };
        if (code == null) return;
        if (!_continuous) markPaused(true);
        deliverCode(code, format: format);
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
  Future<bool> toggleFlash() async {
    final bool on = await _channel.invokeMethod<bool>('toggleFlash') ?? false;
    markTorch(on);
    return on;
  }

  @override
  Future<void> pauseScanning() async {
    markPaused(true);
    await _channel.invokeMethod<void>('pauseScanning');
  }

  @override
  Future<void> resumeScanning() async {
    markPaused(false);
    await _channel.invokeMethod<void>('resumeScanning');
  }

  @override
  Future<double> setZoom(double zoom) async {
    double applied;
    try {
      applied = await _channel.invokeMethod<double>('setZoom', zoom) ?? 1;
    } on MissingPluginException {
      // A view from before zoom: it does not zoom.
      applied = 1;
    }
    markZoom(applied);
    return applied;
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
