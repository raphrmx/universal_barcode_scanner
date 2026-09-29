import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:universal_barcode_scanner/src/enums.dart';
import 'package:universal_barcode_scanner/src/scanner_controller.dart';
import 'package:universal_barcode_scanner/src/scanner_labels.dart';

/// What the buttons over a scanner drive: pausing and the torch through its
/// [controller], the flips through [onFlip]. The same for the full-screen
/// page and the embedded view, on every platform that shows them.
///
/// The state is kept here rather than read back from the scanner, so a page
/// that loads again can be handed it.
class ScannerButtons extends ChangeNotifier {
  /// Starts with the flips the scanner opens with.
  ScannerButtons({
    required bool flipHorizontal,
    required bool flipVertical,
    required this.onFlip,
    this.onSwitchCamera,
  }) : _flipHorizontal = flipHorizontal,
       _flipVertical = flipVertical;

  /// Shows the camera flipped as the buttons now say.
  final void Function(bool horizontal, bool vertical) onFlip;

  /// Opens the other camera, or null where the scanner cannot.
  final VoidCallback? onSwitchCamera;

  /// The zooms the zoom button goes through, in turn.
  static const List<double> zoomSteps = <double>[1, 2, 3];

  ScannerController? _controller;
  bool _flipHorizontal;
  bool _flipVertical;
  bool _torchBusy = false;

  /// The scanner's controller, once there is one: until then the pause, torch
  /// and zoom buttons do nothing. Its state is what they show, whoever
  /// changed it: a button, the app through the controller, or the scanner
  /// pausing itself after a code.
  ScannerController? get controller => _controller;
  set controller(ScannerController? controller) {
    if (identical(controller, _controller)) return;
    _unlisten();
    _controller = controller;
    _zoomMost = null;
    controller?.isPaused.addListener(notifyListeners);
    controller?.isTorchOn.addListener(notifyListeners);
    controller?.zoom.addListener(notifyListeners);
    notifyListeners();
  }

  void _unlisten() {
    final ScannerController? old = _controller;
    old?.isPaused.removeListener(notifyListeners);
    old?.isTorchOn.removeListener(notifyListeners);
    old?.zoom.removeListener(notifyListeners);
  }

  /// Whether the camera is shown mirrored left to right.
  bool get flipHorizontal => _flipHorizontal;

  /// Whether the camera is shown upside down.
  bool get flipVertical => _flipVertical;

  /// Whether reading is paused, the camera left running.
  bool get paused => _controller?.isPaused.value ?? false;

  /// Whether the torch is on, as the scanner last said.
  bool get torch => _controller?.isTorchOn.value ?? false;

  /// The zoom the camera shows, `1` for none.
  double get zoom => _controller?.zoom.value ?? 1;

  void toggleFlipHorizontal() {
    _flipHorizontal = !_flipHorizontal;
    onFlip(_flipHorizontal, _flipVertical);
    notifyListeners();
  }

  void toggleFlipVertical() {
    _flipVertical = !_flipVertical;
    onFlip(_flipHorizontal, _flipVertical);
    notifyListeners();
  }

  /// Takes flips set from outside, by a widget rebuilt with others.
  void setFlip({required bool horizontal, required bool vertical}) {
    if (horizontal == _flipHorizontal && vertical == _flipVertical) return;
    _flipHorizontal = horizontal;
    _flipVertical = vertical;
    notifyListeners();
  }

  Future<void> togglePause() async {
    final ScannerController? controller = _controller;
    if (controller == null) return;
    await (paused ? controller.resumeScanning() : controller.pauseScanning());
  }

  /// The button changes once the scanner answers: most webcams have no
  /// torch, and the answer is then off.
  Future<void> toggleTorch() async {
    final ScannerController? controller = _controller;
    if (controller == null || _torchBusy) return;
    _torchBusy = true;
    try {
      await controller.toggleFlash();
    } finally {
      _torchBusy = false;
    }
  }

  /// The most the camera zoomed, once it gave less than was asked.
  double? _zoomMost;

  /// Goes to the next of [zoomSteps], and back to `1` after the last, or
  /// after the most the camera can do.
  Future<void> cycleZoom() async {
    final ScannerController? controller = _controller;
    if (controller == null) return;
    final double now = zoom;
    final double? most = _zoomMost;
    final double next = most != null && now >= most - 0.01
        ? 1
        : zoomSteps.firstWhere(
            (double step) => step > now + 0.01,
            orElse: () => 1,
          );
    final double applied = await controller.setZoom(next);
    if (next > 1 && applied < next - 0.01) _zoomMost = applied;
    // No further at all: back to the start rather than stuck.
    if (next > 1 && applied <= now + 0.01) await controller.setZoom(1);
  }

  /// Opens the other camera.
  void switchCamera() => onSwitchCamera?.call();

  @override
  void dispose() {
    _unlisten();
    super.dispose();
  }
}

/// Places a [ScannerButtonGroup] at [alignment] inside the box it is given,
/// [inset] from its edges. Along the side when centred on the left or the
/// right, across otherwise.
class ScannerButtonsOverlay extends StatelessWidget {
  /// Shows [buttons] at [alignment].
  const ScannerButtonsOverlay({
    super.key,
    required this.state,
    required this.buttons,
    required this.alignment,
    this.inset = const EdgeInsets.all(12),
    this.labels = ScannerLabels.english,
  });

  final ScannerButtons state;
  final Set<ScannerButton> buttons;
  final AlignmentGeometry alignment;
  final EdgeInsets inset;
  final ScannerLabels labels;

  @override
  Widget build(BuildContext context) {
    final Alignment resolved = alignment.resolve(
      Directionality.maybeOf(context),
    );
    final bool alongSide = resolved.x.abs() == 1 && resolved.y.abs() < 1;
    return Padding(
      padding: inset,
      child: Align(
        alignment: alignment,
        // Shrunk rather than overflowing a view too small for the group.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignment,
          child: ScannerButtonGroup(
            state: state,
            buttons: buttons,
            labels: labels,
            direction: alongSide ? Axis.vertical : Axis.horizontal,
          ),
        ),
      ),
    );
  }
}

/// The buttons asked for, in the order of [ScannerButton], along [direction].
class ScannerButtonGroup extends StatelessWidget {
  /// Shows [buttons], driving [state].
  const ScannerButtonGroup({
    super.key,
    required this.state,
    required this.buttons,
    this.direction = Axis.horizontal,
    this.labels = ScannerLabels.english,
  });

  final ScannerButtons state;
  final Set<ScannerButton> buttons;
  final Axis direction;

  /// What a screen reader says for each button.
  final ScannerLabels labels;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (BuildContext context, Widget? _) {
      final List<Widget> children = <Widget>[];
      for (final ScannerButton button in ScannerButton.values) {
        if (!buttons.contains(button)) continue;
        if (children.isNotEmpty) {
          children.add(const SizedBox.square(dimension: 8));
        }
        children.add(switch (button) {
          ScannerButton.torch => _RoundButton(
            label: labels.torch,
            on: state.torch,
            onPressed: () => unawaited(state.toggleTorch()),
            icon: const _Bolt(),
          ),
          ScannerButton.pause => _RoundButton(
            // Says what a tap does: the icon shows it too.
            label: state.paused ? labels.resume : labels.pause,
            on: state.paused,
            onPressed: () => unawaited(state.togglePause()),
            icon: _PausePlay(paused: state.paused),
          ),
          ScannerButton.flipHorizontal => _RoundButton(
            label: labels.flipHorizontal,
            on: state.flipHorizontal,
            onPressed: state.toggleFlipHorizontal,
            icon: const _Flip(vertical: false),
          ),
          ScannerButton.flipVertical => _RoundButton(
            label: labels.flipVertical,
            on: state.flipVertical,
            onPressed: state.toggleFlipVertical,
            icon: const _Flip(vertical: true),
          ),
          ScannerButton.zoom => _RoundButton(
            label: labels.zoom,
            on: state.zoom > 1.01,
            onPressed: () => unawaited(state.cycleZoom()),
            icon: _Zoom(state.zoom),
          ),
          // An action rather than a state: never shown on.
          ScannerButton.switchCamera => _RoundButton(
            label: labels.switchCamera,
            on: false,
            onPressed: state.switchCamera,
            icon: const _SwitchCamera(),
          ),
        });
      }
      return Flex(
        direction: direction,
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
    },
  );
}

/// Colours of a button, off and on.
const Color _offBackground = Color(0x99000000);
const Color _offForeground = Color(0xFFFFFFFF);
const Color _onBackground = Color(0xE6FFFFFF);
const Color _onForeground = Color(0xFF000000);

/// A round button over the camera, the size of the close button, filled in
/// white while what it turns on is on.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.label,
    required this.on,
    required this.onPressed,
    required this.icon,
  });

  final String label;
  final bool on;
  final VoidCallback onPressed;
  final _Icon icon;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    toggled: on,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: SizedBox.square(
        dimension: 44,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: on ? _onBackground : _offBackground,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: CustomPaint(
              size: const Size.square(20),
              painter: _IconPainter(icon, on ? _onForeground : _offForeground),
            ),
          ),
        ),
      ),
    ),
  );
}

/// An icon drawn in a square of any size, in one colour.
abstract class _Icon {
  const _Icon();

  void paint(Canvas canvas, Size size, Paint fill, Paint stroke);
}

class _IconPainter extends CustomPainter {
  const _IconPainter(this.icon, this.color);

  final _Icon icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    icon.paint(
      canvas,
      size,
      Paint()..color = color,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_IconPainter oldDelegate) =>
      oldDelegate.icon != icon || oldDelegate.color != color;
}

/// A lightning bolt.
class _Bolt extends _Icon {
  const _Bolt();

  @override
  void paint(Canvas canvas, Size size, Paint fill, Paint stroke) {
    final double w = size.width;
    final double h = size.height;
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.58, 0)
        ..lineTo(w * 0.18, h * 0.58)
        ..lineTo(w * 0.47, h * 0.58)
        ..lineTo(w * 0.40, h)
        ..lineTo(w * 0.82, h * 0.40)
        ..lineTo(w * 0.53, h * 0.40)
        ..close(),
      fill,
    );
  }
}

/// Two bars, or a play triangle once paused.
class _PausePlay extends _Icon {
  const _PausePlay({required this.paused});

  final bool paused;

  @override
  void paint(Canvas canvas, Size size, Paint fill, Paint stroke) {
    final double w = size.width;
    final double h = size.height;
    if (paused) {
      canvas.drawPath(
        Path()
          ..moveTo(w * 0.25, h * 0.1)
          ..lineTo(w * 0.88, h * 0.5)
          ..lineTo(w * 0.25, h * 0.9)
          ..close(),
        fill,
      );
      return;
    }
    final RRect bar = RRect.fromLTRBR(
      w * 0.22,
      h * 0.12,
      w * 0.42,
      h * 0.88,
      const Radius.circular(1.5),
    );
    canvas
      ..drawRRect(bar, fill)
      ..drawRRect(bar.shift(Offset(w * 0.36, 0)), fill);
  }

  @override
  bool operator ==(Object other) =>
      other is _PausePlay && other.paused == paused;

  @override
  int get hashCode => paused.hashCode;
}

/// Two arrows going opposite ways, one above the other: ⇄ for the
/// horizontal flip, and turned a quarter, ⇅, for the vertical one.
class _Flip extends _Icon {
  const _Flip({required this.vertical});

  final bool vertical;

  @override
  void paint(Canvas canvas, Size size, Paint fill, Paint stroke) {
    final double w = size.width;
    final double h = size.height;
    canvas.save();
    if (vertical) {
      canvas
        ..translate(w / 2, h / 2)
        ..rotate(math.pi / 2)
        ..translate(-w / 2, -h / 2);
    }
    final Paint line = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final double head = w * 0.22;

    // The upper arrow points right.
    final double top = h * 0.3;
    canvas
      ..drawLine(Offset(w * 0.1, top), Offset(w * 0.9, top), line)
      ..drawPath(
        Path()
          ..moveTo(w * 0.9 - head, top - head)
          ..lineTo(w * 0.9, top)
          ..lineTo(w * 0.9 - head, top + head),
        line,
      );

    // The lower one points left.
    final double bottom = h * 0.7;
    canvas
      ..drawLine(Offset(w * 0.9, bottom), Offset(w * 0.1, bottom), line)
      ..drawPath(
        Path()
          ..moveTo(w * 0.1 + head, bottom - head)
          ..lineTo(w * 0.1, bottom)
          ..lineTo(w * 0.1 + head, bottom + head),
        line,
      );
    canvas.restore();
  }

  @override
  bool operator ==(Object other) =>
      other is _Flip && other.vertical == vertical;

  @override
  int get hashCode => vertical.hashCode;
}

/// A camera with two arrows going round inside it.
class _SwitchCamera extends _Icon {
  const _SwitchCamera();

  @override
  void paint(Canvas canvas, Size size, Paint fill, Paint stroke) {
    final double w = size.width;
    final double h = size.height;
    final Paint line = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // The body, and the bump the lens housing makes on top.
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.34, h * 0.22)
        ..lineTo(w * 0.42, h * 0.1)
        ..lineTo(w * 0.58, h * 0.1)
        ..lineTo(w * 0.66, h * 0.22)
        ..lineTo(w * 0.88, h * 0.22)
        ..arcToPoint(
          Offset(w * 0.96, h * 0.3),
          radius: Radius.circular(w * 0.08),
        )
        ..lineTo(w * 0.96, h * 0.82)
        ..arcToPoint(
          Offset(w * 0.88, h * 0.9),
          radius: Radius.circular(w * 0.08),
        )
        ..lineTo(w * 0.12, h * 0.9)
        ..arcToPoint(
          Offset(w * 0.04, h * 0.82),
          radius: Radius.circular(w * 0.08),
        )
        ..lineTo(w * 0.04, h * 0.3)
        ..arcToPoint(
          Offset(w * 0.12, h * 0.22),
          radius: Radius.circular(w * 0.08),
        )
        ..close(),
      line,
    );

    // Two arcs round the middle, each ending in a head.
    final Offset centre = Offset(w * 0.5, h * 0.56);
    final double r = w * 0.2;
    final Rect ring = Rect.fromCircle(center: centre, radius: r);
    final double head = w * 0.09;
    for (final double start in <double>[math.pi * 1.15, math.pi * 0.15]) {
      const double sweep = math.pi * 0.7;
      canvas.drawArc(ring, start, sweep, false, line);
      final double end = start + sweep;
      final Offset tip = centre + Offset(math.cos(end), math.sin(end)) * r;
      // Along the direction of travel, and across it.
      final Offset along = Offset(-math.sin(end), math.cos(end));
      final Offset across = Offset(math.cos(end), math.sin(end));
      canvas.drawPath(
        Path()
          ..moveTo(
            tip.dx - along.dx * head + across.dx * head * 0.7,
            tip.dy - along.dy * head + across.dy * head * 0.7,
          )
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(
            tip.dx - along.dx * head - across.dx * head * 0.7,
            tip.dy - along.dy * head - across.dy * head * 0.7,
          ),
        line,
      );
    }
  }
}

/// The zoom as a figure, `1×`, `2×`: what the camera shows now.
class _Zoom extends _Icon {
  const _Zoom(this.zoom);

  final double zoom;

  @override
  void paint(Canvas canvas, Size size, Paint fill, Paint stroke) {
    final double rounded = (zoom * 10).roundToDouble() / 10;
    final String figure = rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
    final TextPainter text = TextPainter(
      text: TextSpan(
        text: '$figure\u00d7',
        style: TextStyle(
          color: fill.color,
          fontSize: size.height * 0.62,
          fontWeight: FontWeight.w700,
          // No ambient style here: none underlines it.
          decoration: TextDecoration.none,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    text
      ..paint(
        canvas,
        Offset((size.width - text.width) / 2, (size.height - text.height) / 2),
      )
      ..dispose();
  }

  @override
  bool operator ==(Object other) => other is _Zoom && other.zoom == zoom;

  @override
  int get hashCode => zoom.hashCode;
}
