import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:universal_barcode_scanner/src/enums.dart';
import 'package:universal_barcode_scanner/src/native_scanner.dart';
import 'package:universal_barcode_scanner/src/platform/desktop.dart';
import 'package:universal_barcode_scanner/src/scanner_bar.dart';
import 'package:universal_barcode_scanner/src/scanner_config.dart';
import 'package:universal_barcode_scanner/src/scanner_controller.dart';
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
class ScannerPage extends StatefulWidget {
  /// Creates the scanner page.
  const ScannerPage({
    super.key,
    required this.config,
    required this.onScanned,
    required this.onClose,
    this.onError,
    this.child,
    this.bar,
    this.backgroundColor,
    this.buttons = const <ScannerButton>{},
    this.buttonsAlignment = Alignment.topRight,
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
  final ScannerBar? bar;

  /// The buttons over the camera, on Windows and Linux.
  final Set<ScannerButton> buttons;

  /// Where [buttons] sit.
  final AlignmentGeometry buttonsAlignment;

  /// Colour behind the camera. Black when null.
  final Color? backgroundColor;

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  /// Tags every call and event of this page's scan, so that a late close or
  /// event from it never reaches the next scanner.
  final int _session = NativeScanner.newSession();

  StreamSubscription<String>? _codes;
  ModalRoute<Object?>? _route;

  /// Whether the native scanner has answered for good, so there is nothing
  /// left to close.
  bool _settled = false;

  /// Whether the page has let the native scanner go.
  bool _stopped = false;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    if (route != null && !identical(route, _route)) {
      _route = route;
      // The moment the route is popped or removed, not once its exit
      // transition has run: a scan opened right after this one would find
      // the native scanner still up.
      unawaited(route.popped.then((_) => _stop()));
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  /// Closes the native scanner unless it already answered.
  void _stop() {
    if (_stopped) return;
    _stopped = true;
    // Cancelling the stream closes the native scanner.
    final Future<void>? cancelling = _codes?.cancel();
    if (cancelling != null) {
      unawaited(cancelling);
    } else if (_hasNativeScanner && !_settled) {
      unawaited(NativeScanner.close(_session));
    }
  }

  void _start() {
    if (!mounted || _stopped) return;
    if (widget.config.continuous) {
      _codes = NativeScanner.stream(widget.config, session: _session).listen(
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
      final String? code = await NativeScanner.scan(
        widget.config,
        session: _session,
      );
      _settled = true;
      if (!mounted || _stopped) return;
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
    if (!mounted || _stopped) return;
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
      return DesktopScannerPage(
        config: widget.config,
        backgroundColor: widget.backgroundColor,
        onScanned: widget.onScanned,
        onClose: widget.onClose,
        bar: widget.bar,
        buttons: widget.buttons,
        buttonsAlignment: widget.buttonsAlignment,
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

/// Embedded scanner view for the platforms that have `dart:io`.
///
/// Android, iOS and macOS show their native camera in a platform view;
/// Windows and Linux the bundled page in a webview.
///
/// What to scan is read once, when the view is created: give the widget a
/// new key to apply a different configuration. The callbacks are always the
/// current widget's.
class EmbeddedScanner extends StatefulWidget {
  /// Creates the embedded view.
  const EmbeddedScanner({
    super.key,
    required this.config,
    required this.onCreated,
    this.onScanned,
    this.onError,
    this.scanWindowSize,
    this.child,
  });

  /// What to scan and how.
  final ScannerConfig config;

  /// Called once the view exists.
  final ScannerCreatedCallback onCreated;

  /// Called with every code read.
  final ValueChanged<String>? onScanned;

  /// Called when the camera cannot be used.
  final ValueChanged<ScannerException>? onError;

  /// Size of the scan window in logical pixels, or null for a default.
  final Size? scanWindowSize;

  /// Drawn over the camera.
  final Widget? child;

  @override
  State<EmbeddedScanner> createState() => _EmbeddedScannerState();
}

class _EmbeddedScannerState extends State<EmbeddedScanner> {
  static const String _viewType = 'universal_barcode_scanner/view';

  ScannerController? _controller;

  @override
  void didUpdateWidget(EmbeddedScanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller
      ?..onScanned = widget.onScanned
      ..onError = widget.onError;
  }

  @override
  void dispose() {
    // A code or an error still in flight must not reach a widget that is
    // gone.
    _controller?.dispose();
    super.dispose();
  }

  Map<String, Object?> get _creationParams => <String, Object?>{
    ...widget.config.toNative(),
    'scanWindowWidth': widget.scanWindowSize?.width,
    'scanWindowHeight': widget.scanWindowSize?.height,
  };

  void _onPlatformViewCreated(int id) {
    if (!mounted) return;
    final ScannerController controller = ChannelScannerController(id)
      ..onScanned = widget.onScanned
      ..onError = widget.onError;
    _controller = controller;
    widget.onCreated(controller);
  }

  @override
  Widget build(BuildContext context) {
    if (_hasWebviewScanner) {
      return DesktopEmbeddedScanner(
        config: widget.config,
        onCreated: widget.onCreated,
        onScanned: widget.onScanned,
        onError: widget.onError,
        scanWindowSize: widget.scanWindowSize,
        child: widget.child,
      );
    }

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
      case TargetPlatform.macOS:
        view = AppKitView(
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

    final Widget? child = widget.child;
    final ScannerConfig config = widget.config;
    final Widget camera = config.flipHorizontal || config.flipVertical
        ? Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(
              config.flipHorizontal ? -1 : 1,
              config.flipVertical ? -1 : 1,
              1,
            ),
            child: view,
          )
        : view;
    if (child == null) return camera;
    return Stack(fit: StackFit.expand, children: <Widget>[camera, child]);
  }
}
