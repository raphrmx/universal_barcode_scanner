import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:universal_barcode_scanner/src/enums.dart';
import 'package:universal_barcode_scanner/src/scanner_controller.dart';

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
  }) : _flipHorizontal = flipHorizontal,
       _flipVertical = flipVertical;

  /// Shows the camera flipped as the buttons now say.
  final void Function(bool horizontal, bool vertical) onFlip;

  /// The scanner's controller, once there is one: until then the pause and
  /// torch buttons do nothing.
  ScannerController? controller;

  bool _flipHorizontal;
  bool _flipVertical;
  bool _paused = false;
  bool _torch = false;
  bool _torchBusy = false;

  /// Whether the camera is shown mirrored left to right.
  bool get flipHorizontal => _flipHorizontal;

  /// Whether the camera is shown upside down.
  bool get flipVertical => _flipVertical;

  /// Whether reading is paused, the camera left running.
  bool get paused => _paused;

  /// Whether the torch is on, as the scanner last said.
  bool get torch => _torch;

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
    final ScannerController? controller = this.controller;
    if (controller == null) return;
    _paused = !_paused;
    notifyListeners();
    await (_paused ? controller.pauseScanning() : controller.resumeScanning());
  }

  /// A view that is not continuous pauses on its own after a code.
  void pausedByScanner() {
    if (_paused) return;
    _paused = true;
    notifyListeners();
  }

  /// The button changes once the scanner answers: most webcams have no
  /// torch, and the answer is then off.
  Future<void> toggleTorch() async {
    final ScannerController? controller = this.controller;
    if (controller == null || _torchBusy) return;
    _torchBusy = true;
    try {
      final bool on = await controller.toggleFlash();
      if (on != _torch) {
        _torch = on;
        notifyListeners();
      }
    } finally {
      _torchBusy = false;
    }
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
  });

  final ScannerButtons state;
  final Set<ScannerButton> buttons;
  final AlignmentGeometry alignment;
  final EdgeInsets inset;

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
  });

  final ScannerButtons state;
  final Set<ScannerButton> buttons;
  final Axis direction;

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
            label: 'Torch',
            on: state.torch,
            onPressed: () => unawaited(state.toggleTorch()),
            icon: const _Bolt(),
          ),
          ScannerButton.pause => _RoundButton(
            // Says what a tap does: the icon shows it too.
            label: state.paused ? 'Resume' : 'Pause',
            on: state.paused,
            onPressed: () => unawaited(state.togglePause()),
            icon: _PausePlay(paused: state.paused),
          ),
          ScannerButton.flipHorizontal => _RoundButton(
            label: 'Flip horizontally',
            on: state.flipHorizontal,
            onPressed: state.toggleFlipHorizontal,
            icon: const _Flip(vertical: false),
          ),
          ScannerButton.flipVertical => _RoundButton(
            label: 'Flip vertically',
            on: state.flipVertical,
            onPressed: state.toggleFlipVertical,
            icon: const _Flip(vertical: true),
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

/// Two triangles either side of a dashed axis: the usual flip icon, turned a
/// quarter for the vertical one.
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
    canvas
      ..drawPath(
        Path()
          ..moveTo(w * 0.40, h * 0.12)
          ..lineTo(w * 0.40, h * 0.88)
          ..lineTo(w * 0.04, h * 0.88)
          ..close(),
        fill,
      )
      ..drawPath(
        Path()
          ..moveTo(w * 0.60, h * 0.12)
          ..lineTo(w * 0.60, h * 0.88)
          ..lineTo(w * 0.96, h * 0.88)
          ..close(),
        stroke,
      );
    for (double y = 0; y < h; y += h / 5) {
      canvas.drawLine(
        Offset(w / 2, y),
        Offset(w / 2, math.min(h, y + h / 10)),
        stroke,
      );
    }
    canvas.restore();
  }

  @override
  bool operator ==(Object other) =>
      other is _Flip && other.vertical == vertical;

  @override
  int get hashCode => vertical.hashCode;
}
