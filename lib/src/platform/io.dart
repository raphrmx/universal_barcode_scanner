import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:universal_barcode_scanner/src/barcode_app_bar.dart';
import 'package:universal_barcode_scanner/src/barcode_view_controller.dart';
import 'package:universal_barcode_scanner/src/native_scanner.dart';
import 'package:universal_barcode_scanner/src/platform/desktop.dart';
import 'package:universal_barcode_scanner/src/scanner_config.dart';
import 'package:universal_barcode_scanner/src/scanner_exception.dart';

/// Platforms that reach a native scanner over the method channel.
bool get _hasNativeScanner => switch (defaultTargetPlatform) {
  TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.macOS => true,
  _ => false,
};

/// Platforms that run the bundled page in a webview.
bool get _hasWebviewScanner => switch (defaultTargetPlatform) {
  TargetPlatform.windows || TargetPlatform.linux => true,
  _ => false,
};

/// Full-screen scanner for the platforms that have `dart:io`.
///
/// Android, iOS and macOS go through their native scanner, which covers this
/// page; Windows and Linux through a webview running the bundled scanner page.
class BarcodeScannerPage extends StatefulWidget {
  /// Creates the scanner page.
  const BarcodeScannerPage({
    super.key,
    required this.config,
    required this.onScanned,
    required this.onClose,
    this.onError,
    this.child,
    this.barcodeAppBar,
    this.flip = false,
    this.backgroundColor,
  });

  /// What to scan and how.
  final ScannerConfig config;

  /// Called with every code read.
  final ValueChanged<String> onScanned;

  /// Called when the scanner closes without a code: the user backed out, or a
  /// continuous scan ended.
  final VoidCallback onClose;

  /// Called when the camera cannot be used.
  final ValueChanged<ScannerException>? onError;

  /// Drawn over the webview scanner.
  final Widget? child;

  /// App bar above the webview scanner, or null for none.
  final BarcodeAppBar? barcodeAppBar;

  /// Whether the webview preview is mirrored.
  final bool flip;

  /// Colour behind the camera. Black when null.
  final Color? backgroundColor;

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  StreamSubscription<String>? _codes;

  /// Whether the native scanner has answered for good, so there is nothing
  /// left to close.
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    if (_hasNativeScanner) {
      // After the first frame, so the route is on screen before the native
      // scanner covers it.
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  @override
  void dispose() {
    // Cancelling the stream closes the native scanner.
    final Future<void>? cancelling = _codes?.cancel();
    if (cancelling != null) {
      unawaited(cancelling);
    } else if (_hasNativeScanner && !_settled) {
      // The route went away under an open scanner.
      unawaited(NativeScanner.close());
    }
    super.dispose();
  }

  void _start() {
    if (!mounted) return;
    if (widget.config.continuous) {
      _codes = NativeScanner.stream(widget.config).listen(
        widget.onScanned,
        onError: (Object error) => _fail(ScannerException.from(error)),
        onDone: () {
          _settled = true;
          if (mounted) widget.onClose();
        },
      );
    } else {
      unawaited(_scanOnce());
    }
  }

  Future<void> _scanOnce() async {
    try {
      final String? code = await NativeScanner.scan(widget.config);
      _settled = true;
      if (!mounted) return;
      if (code == null) {
        widget.onClose();
      } else {
        widget.onScanned(code);
      }
    } on ScannerException catch (error) {
      _settled = true;
      _fail(error);
    }
  }

  void _fail(ScannerException error) {
    if (!mounted) return;
    final ValueChanged<ScannerException>? onError = widget.onError;
    if (onError == null) {
      widget.onClose();
    } else {
      onError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasWebviewScanner) {
      return DesktopBarcodeScannerPage(
        config: widget.config,
        backgroundColor: widget.backgroundColor,
        onScanned: widget.onScanned,
        onClose: widget.onClose,
        barcodeAppBar: widget.barcodeAppBar,
        flip: widget.flip,
        child: widget.child,
      );
    }

    final Color background = widget.backgroundColor ?? const Color(0xFF000000);
    if (!_hasNativeScanner) {
      return ColoredBox(
        color: background,
        child: Center(
          child: Text(
            '$defaultTargetPlatform is not supported yet',
            style: const TextStyle(color: Color(0xFFFFFFFF)),
          ),
        ),
      );
    }

    return ColoredBox(
      color: background,
      child: const Center(child: _Spinner()),
    );
  }
}

/// Shown for the moment between this route appearing and the native scanner
/// covering it.
class _Spinner extends StatefulWidget {
  const _Spinner();

  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _turn,
    child: CustomPaint(size: const Size.square(36), painter: _Arc()),
  );
}

class _Arc extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Offset.zero & size, 0, 4.2, false, paint);
  }

  @override
  bool shouldRepaint(_Arc oldDelegate) => false;
}

/// Embedded scanner view for Android and iOS.
class BarcodeScannerView extends StatelessWidget {
  /// Creates the embedded view.
  const BarcodeScannerView({
    super.key,
    required this.config,
    required this.onBarcodeViewCreated,
    this.onScanned,
    this.onError,
    this.scanWindowSize,
    this.child,
    this.flip = false,
  });

  /// What to scan and how.
  final ScannerConfig config;

  /// Called once the view exists.
  final BarcodeScannerViewCreated onBarcodeViewCreated;

  /// Called with every code read.
  final ValueChanged<String>? onScanned;

  /// Called when the camera cannot be used.
  final ValueChanged<ScannerException>? onError;

  /// Size of the scan window in logical pixels, or null for a default.
  final Size? scanWindowSize;

  /// Drawn over the camera.
  final Widget? child;

  /// Whether the preview is mirrored.
  final bool flip;

  static const String _viewType = 'universal_barcode_scanner/view';

  Map<String, Object?> get _creationParams => <String, Object?>{
    ...config.toNative(),
    'scanWindowWidth': scanWindowSize?.width,
    'scanWindowHeight': scanWindowSize?.height,
  };

  void _onPlatformViewCreated(int id) {
    final BarcodeViewController controller = BarcodeViewController.data(id)
      ..onScanned = onScanned
      ..onError = onError;
    onBarcodeViewCreated(controller);
  }

  @override
  Widget build(BuildContext context) {
    final Widget view;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        view = AndroidView(
          viewType: _viewType,
          onPlatformViewCreated: _onPlatformViewCreated,
          creationParams: _creationParams,
          creationParamsCodec: const StandardMessageCodec(),
        );
      case TargetPlatform.iOS:
        view = UiKitView(
          viewType: _viewType,
          onPlatformViewCreated: _onPlatformViewCreated,
          creationParams: _creationParams,
          creationParamsCodec: const StandardMessageCodec(),
        );
      default:
        return Center(
          child: Text('$defaultTargetPlatform has no embedded scanner view'),
        );
    }

    final Widget? child = this.child;
    final Widget camera = flip
        ? Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(-1, 1, 1),
            child: view,
          )
        : view;
    if (child == null) return camera;
    return Stack(fit: StackFit.expand, children: <Widget>[camera, child]);
  }
}
