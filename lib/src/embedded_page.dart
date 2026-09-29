import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:universal_barcode_scanner/src/enums.dart';
import 'package:universal_barcode_scanner/src/scanner_config.dart';
import 'package:universal_barcode_scanner/src/scanner_controller.dart';
import 'package:universal_barcode_scanner/src/scanner_exception.dart';

/// What the embedded view asks of the bundled page. Each name is a function
/// the page exposes.
enum PageCall {
  /// Stops reporting codes, the camera left running.
  pauseScanning,

  /// Reports codes again, every code in sight counting as new.
  resumeScanning,

  /// Turns the torch over; the page answers with its new state.
  toggleTorch,
}

/// The controller of an embedded view that runs the bundled page, on the web,
/// Windows and Linux. It talks to the page through [send] and hears back
/// through [handle].
///
/// What the app asks before the page is up is held back and sent once the
/// view calls [pageReady]: a page still loading would drop it.
final class PageScannerController extends ScannerController {
  /// Creates a controller that reaches its page through [send]. A view that
  /// is not [continuous] pauses on its first code, as the page does.
  PageScannerController(this._send, {required bool continuous})
    : _continuous = continuous;

  final void Function(PageCall call) _send;
  final bool _continuous;

  /// Whether the view has stopped reading, which stops its scan line too.
  final ValueNotifier<bool> paused = ValueNotifier<bool>(false);

  /// Whether the page is up and takes calls.
  bool _ready = false;

  /// The last pause or resume asked before the page was up.
  bool? _pausedBeforeReady;

  /// Whether a torch toggle was asked before the page was up.
  bool _torchBeforeReady = false;

  /// The torch toggle waiting for the page's answer.
  Completer<bool>? _torch;

  /// How long the page is given to answer a torch toggle: one that never
  /// loaded never answers.
  static const Duration _torchTimeout = Duration(seconds: 3);

  /// The page is up and has its settings: what was held back goes out.
  void pageReady() {
    if (_ready || isDisposed) return;
    _ready = true;
    final bool? paused = _pausedBeforeReady;
    _pausedBeforeReady = null;
    if (paused ?? false) _send(PageCall.pauseScanning);
    if (_torchBeforeReady) {
      _torchBeforeReady = false;
      _send(PageCall.toggleTorch);
    }
  }

  /// Takes what the page posted.
  void handle(PageMessage? message) {
    switch (message) {
      case PageCode(:final String code):
        if (!_continuous) paused.value = true;
        deliverCode(code);
      case PageError(:final String code, :final String? message):
        deliverError(
          ScannerException(ScannerErrorCode.fromWire(code), message),
        );
      case PageTorch(:final bool on):
        final Completer<bool>? torch = _torch;
        _torch = null;
        if (torch != null && !torch.isCompleted) torch.complete(on);
      case PageReady():
        pageReady();
      // A view has no close: the Escape key is the page's, not the app's.
      case PageClose():
      case null:
        break;
    }
  }

  @override
  Future<bool> toggleFlash() {
    if (isDisposed) return Future<bool>.value(false);
    final Completer<bool>? pending = _torch;
    if (pending != null) return pending.future;
    final Completer<bool> torch = _torch = Completer<bool>();
    if (_ready) {
      _send(PageCall.toggleTorch);
    } else {
      _torchBeforeReady = true;
    }
    return torch.future.timeout(
      _torchTimeout,
      onTimeout: () {
        if (identical(_torch, torch)) _torch = null;
        // Not sent late either: the torch would change with nobody told.
        _torchBeforeReady = false;
        return false;
      },
    );
  }

  @override
  Future<void> pauseScanning() async {
    if (isDisposed) return;
    paused.value = true;
    if (_ready) {
      _send(PageCall.pauseScanning);
    } else {
      _pausedBeforeReady = true;
    }
  }

  @override
  Future<void> resumeScanning() async {
    if (isDisposed) return;
    paused.value = false;
    if (_ready) {
      _send(PageCall.resumeScanning);
    } else {
      // A page that starts is not paused: nothing to send.
      _pausedBeforeReady = false;
    }
  }

  @override
  void dispose() {
    final Completer<bool>? torch = _torch;
    _torch = null;
    if (torch != null && !torch.isCompleted) torch.complete(false);
    paused.dispose();
    super.dispose();
  }
}

/// The scan window in a view of [size], as every platform places it: centred,
/// [requested] when given, otherwise square for QR codes and wide for
/// barcodes, capped so a tablet does not get a huge one. Null for
/// [ScanWindow.none].
Rect? scanWindowRect(Size size, ScanWindow shape, Size? requested) {
  if (shape == ScanWindow.none || size.isEmpty) return null;
  final double width;
  final double height;
  if (requested != null && requested.width > 0 && requested.height > 0) {
    width = math.min(requested.width, size.width);
    height = math.min(requested.height, size.height);
  } else if (shape == ScanWindow.square) {
    width = math.min(size.shortestSide * 0.75, 320);
    height = width;
  } else {
    width = math.min(size.width * 0.85, 416);
    height = math.min(width * 0.5, size.height * 0.8);
  }
  return Rect.fromCenter(
    center: size.center(Offset.zero),
    width: width,
    height: height,
  );
}

/// The page view of an embedded scanner, with the scan window Flutter draws
/// over it and the app's own [child] on top.
///
/// Reports the window's size through [onWindow] whenever the layout changes
/// it, [Size.zero] when there is none, so the page reads inside the same box.
class EmbeddedPageFrame extends StatelessWidget {
  /// Frames [view].
  const EmbeddedPageFrame({
    super.key,
    required this.view,
    required this.config,
    required this.onWindow,
    this.scanWindowSize,
    this.child,
    this.failed = false,
    this.paused,
  });

  /// The webview or iframe running the page.
  final Widget view;

  /// What to scan and how.
  final ScannerConfig config;

  /// Called with the scan window's size, before [view] is built.
  final ValueChanged<Size> onWindow;

  /// Size of the scan window asked for, or null for the default.
  final Size? scanWindowSize;

  /// Drawn over the camera.
  final Widget? child;

  /// Whether the camera did not start. The page then explains why, and no
  /// scan window is drawn over its words.
  final bool failed;

  /// Whether the view has stopped reading: the scan line stops with it.
  final ValueListenable<bool>? paused;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final Size size = constraints.biggest.isFinite
          ? constraints.biggest
          : Size.zero;
      final Rect? window = scanWindowRect(
        size,
        config.scanWindow,
        scanWindowSize,
      );
      // During the build, not after: the web view reads the window from its
      // address, which is set when the element is created below.
      onWindow(window?.size ?? Size.zero);

      final Widget? child = this.child;
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // The page flips the camera itself, leaving its words readable.
          view,
          if (window != null && !failed)
            IgnorePointer(
              child: ScanWindowOverlay(
                window: window,
                lineColor: config.lineColor,
                paused: paused,
              ),
            ),
          ?child,
        ],
      );
    },
  );
}

/// The scan window over the camera, as the Android and iOS views draw it: the
/// surround dimmed, the window outlined, and a line sweeping across it.
class ScanWindowOverlay extends StatefulWidget {
  /// Draws [window] with a line of [lineColor].
  const ScanWindowOverlay({
    super.key,
    required this.window,
    required this.lineColor,
    this.paused,
  });

  /// The window, in this widget's coordinates.
  final Rect window;

  /// Colour of the sweeping line.
  final Color lineColor;

  /// Stops the line where it is while true, and sets it off again from there.
  final ValueListenable<bool>? paused;

  @override
  State<ScanWindowOverlay> createState() => _ScanWindowOverlayState();
}

class _ScanWindowOverlayState extends State<ScanWindowOverlay>
    with SingleTickerProviderStateMixin {
  /// One sweep down and back up, as on Android.
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void initState() {
    super.initState();
    widget.paused?.addListener(_follow);
  }

  @override
  void didUpdateWidget(ScanWindowOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paused != widget.paused) {
      oldWidget.paused?.removeListener(_follow);
      widget.paused?.addListener(_follow);
      _follow();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow();
  }

  /// Runs the sweep, unless animations are off, where the line stays still
  /// across the window, or the view is paused, where it stops where it is.
  void _follow() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _sweep
        ..stop()
        ..value = 0.25;
    } else if (widget.paused?.value ?? false) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      // From where it stopped.
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    widget.paused?.removeListener(_follow);
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _WindowPainter(
        window: widget.window,
        lineColor: widget.lineColor,
        sweep: _sweep,
      ),
      size: Size.infinite,
    ),
  );
}

class _WindowPainter extends CustomPainter {
  _WindowPainter({
    required this.window,
    required this.lineColor,
    required this.sweep,
  }) : super(repaint: sweep);

  final Rect window;
  final Color lineColor;
  final Animation<double> sweep;

  static final Paint _dim = Paint()..color = const Color(0x80000000);
  static final Paint _frame = Paint()
    ..color = const Color(0xCCFFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect box = window;
    canvas
      ..drawRect(Rect.fromLTRB(0, 0, size.width, box.top), _dim)
      ..drawRect(Rect.fromLTRB(0, box.top, box.left, box.bottom), _dim)
      ..drawRect(
        Rect.fromLTRB(box.right, box.top, size.width, box.bottom),
        _dim,
      )
      ..drawRect(Rect.fromLTRB(0, box.bottom, size.width, size.height), _dim)
      ..drawRect(box, _frame);

    final double phase = sweep.value;
    final double progress = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
    final double y = box.top + progress * box.height;
    canvas.drawLine(
      Offset(box.left, y),
      Offset(box.right, y),
      Paint()
        ..color = lineColor
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_WindowPainter oldDelegate) =>
      oldDelegate.window != window ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.sweep != sweep;
}
