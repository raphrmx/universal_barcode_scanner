import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:universal_barcode_scanner/src/enums.dart';
import 'package:universal_barcode_scanner/src/scan_result.dart';
import 'package:universal_barcode_scanner/src/scanner_config.dart';
import 'package:universal_barcode_scanner/src/scanner_controller.dart';
import 'package:universal_barcode_scanner/src/scanner_exception.dart';

/// What a host wants the bundled page to show, handed over once the page
/// listens and again whenever it changes: the flips, the camera, the scan
/// window of an embedded view, and whether reading is paused.
///
/// Every host of the page keeps one, the web and the desktop, full page and
/// embedded view alike. [call] reaches a function of the page by name, with
/// its arguments in order.
class PageLink {
  /// Wants what [config] opens the page with.
  PageLink(this.call, ScannerConfig config)
    : _flip = (config.flipHorizontal, config.flipVertical),
      _face = config.cameraFace;

  /// Calls a function of the page.
  final void Function(String name, List<Object> arguments) call;

  bool _ready = false;
  final List<VoidCallback> _whenReady = <VoidCallback>[];

  (bool, bool) _flip;
  CameraFace _face;
  Size? _window;
  bool _paused = false;

  // What the page has, once it is up.
  (bool, bool)? _pageFlip;
  CameraFace? _pageFace;
  Size? _pageWindow;
  bool _pagePaused = false;

  /// Whether the page is up and takes calls.
  bool get isReady => _ready;

  /// The flips wanted, horizontal then vertical.
  (bool, bool) get flip => _flip;

  /// The camera wanted.
  CameraFace get face => _face;

  /// Whether reading is wanted paused.
  bool get paused => _paused;

  /// [config] with the flips and the camera as now wanted, for a page
  /// configured again.
  ScannerConfig apply(ScannerConfig config) => config.copyWith(
    flipHorizontal: _flip.$1,
    flipVertical: _flip.$2,
    cameraFace: _face,
  );

  void setFlip({required bool horizontal, required bool vertical}) {
    _flip = (horizontal, vertical);
    _push();
  }

  void setFace(CameraFace face) {
    _face = face;
    _push();
  }

  /// Goes to the other camera.
  void switchFace() =>
      setFace(_face == CameraFace.front ? CameraFace.back : CameraFace.front);

  void setWindow(Size window) {
    _window = window;
    _push();
  }

  void setPaused(bool paused) {
    _paused = paused;
    _push();
  }

  /// The page paused itself, on the first code of a view that is not
  /// continuous: nothing to send.
  void pausedByPage() {
    _paused = true;
    _pagePaused = true;
  }

  /// Runs [action] now if the page is up, or once it is.
  void whenReady(VoidCallback action) {
    if (_ready) {
      action();
    } else {
      _whenReady.add(action);
    }
  }

  /// The page is up with [config]'s flips and camera, and [window] for an
  /// embedded view, not paused: whatever is wanted otherwise goes to it now.
  void ready(ScannerConfig config, {Size? window}) {
    if (_ready) return;
    _ready = true;
    _pageFlip = (config.flipHorizontal, config.flipVertical);
    _pageFace = config.cameraFace;
    _pageWindow = window;
    _pagePaused = false;
    _push();
    final List<VoidCallback> actions = List<VoidCallback>.of(_whenReady);
    _whenReady.clear();
    for (final VoidCallback action in actions) {
      action();
    }
  }

  void _push() {
    if (!_ready) return;
    if (_flip != _pageFlip) {
      _pageFlip = _flip;
      call('setFlip', <Object>[_flip.$1, _flip.$2]);
    }
    if (_face != _pageFace) {
      _pageFace = _face;
      call('setFacing', <Object>[ScannerConfig.facingToPage(_face)]);
    }
    final Size? window = _window;
    if (window != null && window != _pageWindow) {
      _pageWindow = window;
      call('setWindow', <Object>[window.width.round(), window.height.round()]);
    }
    if (_paused != _pagePaused) {
      _pagePaused = _paused;
      call(_paused ? 'pauseScanning' : 'resumeScanning', const <Object>[]);
    }
  }
}

/// The controller of a scanner that runs the bundled page, on the web,
/// Windows and Linux, full page or embedded view. It reaches the page through
/// [link] and hears back through [handle].
final class PageScannerController extends ScannerController {
  /// Drives the page behind [link]. A view that is not [continuous] pauses on
  /// its first code, as the page does.
  PageScannerController(this.link, {required bool continuous})
    : _continuous = continuous;

  /// What the page is asked to show.
  final PageLink link;
  final bool _continuous;

  /// The torch toggle waiting for the page's answer.
  Completer<bool>? _torch;

  /// The zoom waiting for the page's answer.
  Completer<double>? _zoom;

  /// How long the page is given to answer: one that never loaded never does.
  static const Duration _answerTimeout = Duration(seconds: 3);

  /// Takes what the page posted.
  void handle(PageMessage? message) {
    switch (message) {
      case PageCode(:final String code, :final BarcodeFormat format):
        if (!_continuous) {
          link.pausedByPage();
          markPaused(true);
        }
        deliverCode(code, format: format);
      case PageError(:final String code, :final String? message):
        deliverError(
          ScannerException(ScannerErrorCode.fromWire(code), message),
        );
      case PageTorch(:final bool on):
        markTorch(on);
        final Completer<bool>? torch = _torch;
        _torch = null;
        if (torch != null && !torch.isCompleted) torch.complete(on);
      case PageZoom(:final double zoom):
        markZoom(zoom);
        final Completer<double>? pending = _zoom;
        _zoom = null;
        if (pending != null && !pending.isCompleted) pending.complete(zoom);
      // The host says when the page is up, and a view has no close: the
      // Escape key is the page's, not the app's.
      case PageReady():
      case PageClose():
      case PageImage():
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
    link.whenReady(() {
      // Not sent late either: the torch would change with nobody told.
      if (identical(_torch, torch)) link.call('toggleTorch', const <Object>[]);
    });
    return torch.future.timeout(
      _answerTimeout,
      onTimeout: () {
        if (identical(_torch, torch)) _torch = null;
        return false;
      },
    );
  }

  @override
  Future<double> setZoom(double zoom) {
    if (isDisposed) return Future<double>.value(1);
    // A later zoom wins over one still waiting for its answer.
    final Completer<double> slot = _zoom = Completer<double>();
    link.whenReady(() {
      if (identical(_zoom, slot)) link.call('setZoom', <Object>[zoom]);
    });
    return slot.future.timeout(
      _answerTimeout,
      onTimeout: () {
        if (identical(_zoom, slot)) _zoom = null;
        return this.zoom.value;
      },
    );
  }

  @override
  Future<void> pauseScanning() async {
    if (isDisposed) return;
    markPaused(true);
    link.setPaused(true);
  }

  @override
  Future<void> resumeScanning() async {
    if (isDisposed) return;
    markPaused(false);
    link.setPaused(false);
  }

  @override
  void dispose() {
    final Completer<bool>? torch = _torch;
    _torch = null;
    if (torch != null && !torch.isCompleted) torch.complete(false);
    final Completer<double>? zoom = _zoom;
    _zoom = null;
    if (zoom != null && !zoom.isCompleted) zoom.complete(1);
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
    // Clear of a column of buttons at either side, and low enough in a
    // short view that the dimmed surround still frames it.
    width = math.min(size.width * 0.72, 416);
    height = math.min(width * 0.5, size.height * 0.6);
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

/// The scan window over the camera: the surround dimmed, the window cut out
/// of it with rounded corners, marked by four thin corner lines, and a line
/// sweeping across it.
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

  static final Paint _dim = Paint()..color = const Color(0x73000000);
  static final Paint _corner = Paint()
    ..color = const Color(0xF2FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round;

  /// How round the window's corners are.
  static const double _radius = 14;

  /// How far each corner runs along the window's sides, past its curve.
  static const double _arm = 14;

  /// How far the trail behind the sweeping line reaches, at most.
  static const double _trail = 40;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect box = window;
    final double radius = math.min(_radius, box.shortestSide / 6);
    final double arm = math.min(_arm, box.shortestSide / 6);
    final Radius curve = Radius.circular(radius);
    // The surround dimmed, the window cut out of it with rounded corners.
    canvas.drawDRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.zero),
      RRect.fromRectAndRadius(box, curve),
      _dim,
    );

    // The line, sweeping from side to side of the window, cut by its rounded
    // corners near the top and bottom.
    final double phase = sweep.value;
    final bool down = phase < 0.5;
    final double progress = down ? phase * 2 : (1 - phase) * 2;
    const double inset = 2;
    final double y = box.top + inset + progress * (box.height - inset * 2);
    // A faint trail behind it, growing from the side it left and fading as it
    // nears the other, so that it never jumps when the line turns.
    final double reach = math.min(_trail, box.height * 0.3);
    final double left = down ? y - box.top : box.bottom - y;
    final double ahead = down ? box.bottom - y : y - box.top;
    final double length = math.min(reach, left);
    final double fade = reach <= 0 ? 0 : math.min(1, ahead / reach);
    final double tail = down ? y - length : y + length;
    canvas
      ..save()
      ..clipRRect(RRect.fromRectAndRadius(box, curve));
    if (length > 0 && fade > 0) {
      canvas.drawRect(
        Rect.fromLTRB(
          box.left,
          math.min(y, tail),
          box.right,
          math.max(y, tail),
        ),
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, y), Offset(0, tail), [
            lineColor.withValues(alpha: lineColor.a * 0.3 * fade),
            lineColor.withValues(alpha: 0),
          ]),
      );
    }
    canvas
      ..drawLine(
        Offset(box.left, y),
        Offset(box.right, y),
        Paint()
          ..color = lineColor
          ..strokeWidth = 2,
      )
      ..restore();

    // Each corner as a thin line following the curve, a little way along
    // both sides, over the line.
    canvas
      ..drawPath(
        Path()
          ..moveTo(box.left, box.top + radius + arm)
          ..lineTo(box.left, box.top + radius)
          ..arcToPoint(Offset(box.left + radius, box.top), radius: curve)
          ..lineTo(box.left + radius + arm, box.top),
        _corner,
      )
      ..drawPath(
        Path()
          ..moveTo(box.right - radius - arm, box.top)
          ..lineTo(box.right - radius, box.top)
          ..arcToPoint(Offset(box.right, box.top + radius), radius: curve)
          ..lineTo(box.right, box.top + radius + arm),
        _corner,
      )
      ..drawPath(
        Path()
          ..moveTo(box.right, box.bottom - radius - arm)
          ..lineTo(box.right, box.bottom - radius)
          ..arcToPoint(Offset(box.right - radius, box.bottom), radius: curve)
          ..lineTo(box.right - radius - arm, box.bottom),
        _corner,
      )
      ..drawPath(
        Path()
          ..moveTo(box.left + radius + arm, box.bottom)
          ..lineTo(box.left + radius, box.bottom)
          ..arcToPoint(Offset(box.left, box.bottom - radius), radius: curve)
          ..lineTo(box.left, box.bottom - radius - arm),
        _corner,
      );
  }

  @override
  bool shouldRepaint(_WindowPainter oldDelegate) =>
      oldDelegate.window != window ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.sweep != sweep;
}
