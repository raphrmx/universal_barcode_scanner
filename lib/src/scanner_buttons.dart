import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:universal_barcode_scanner/src/enums.dart';
import 'package:universal_barcode_scanner/src/pointer_shield.dart';
import 'package:universal_barcode_scanner/src/scanner_button_style.dart';
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
/// right, across otherwise, and with its tooltips towards the middle.
class ScannerButtonsOverlay extends StatelessWidget {
  /// Shows [buttons] at [alignment].
  const ScannerButtonsOverlay({
    super.key,
    required this.state,
    required this.buttons,
    required this.alignment,
    this.inset = const EdgeInsets.all(12),
    this.labels = ScannerLabels.english,
    this.style = const ScannerButtonStyle(),
  });

  final ScannerButtons state;
  final Set<ScannerButton> buttons;
  final AlignmentGeometry alignment;
  final EdgeInsets inset;
  final ScannerLabels labels;
  final ScannerButtonStyle style;

  @override
  Widget build(BuildContext context) {
    final Alignment resolved = alignment.resolve(
      Directionality.maybeOf(context),
    );
    final bool alongSide = resolved.x.abs() == 1 && resolved.y.abs() < 1;
    // Towards the middle of the view, where there is room.
    final AxisDirection tooltips = alongSide
        ? (resolved.x > 0 ? AxisDirection.left : AxisDirection.right)
        : (resolved.y < 0 ? AxisDirection.down : AxisDirection.up);
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
            style: style,
            tooltips: tooltips,
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
    this.style = const ScannerButtonStyle(),
    this.tooltips = AxisDirection.left,
  });

  final ScannerButtons state;
  final Set<ScannerButton> buttons;
  final Axis direction;

  /// What each button says, to a screen reader and in its tooltip.
  final ScannerLabels labels;

  /// How the buttons look.
  final ScannerButtonStyle style;

  /// Where the tooltips open.
  final AxisDirection tooltips;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (BuildContext context, Widget? _) {
      final List<Widget> children = <Widget>[];
      void add(String label, bool on, VoidCallback onPressed, _Icon icon) {
        if (children.isNotEmpty) {
          children.add(SizedBox.square(dimension: style.spacing));
        }
        children.add(
          ScannerRoundButton(
            label: label,
            on: on,
            onPressed: onPressed,
            style: style,
            tooltip: tooltips,
            painter: (Color color) => _IconPainter(icon, color),
          ),
        );
      }

      for (final ScannerButton button in ScannerButton.values) {
        if (!buttons.contains(button)) continue;
        switch (button) {
          case ScannerButton.torch:
            add(
              labels.torch,
              state.torch,
              () => unawaited(state.toggleTorch()),
              const _Bolt(),
            );
          case ScannerButton.pause:
            // Says what a tap does: the icon shows it too.
            add(
              state.paused ? labels.resume : labels.pause,
              state.paused,
              () => unawaited(state.togglePause()),
              _PausePlay(paused: state.paused),
            );
          case ScannerButton.flipHorizontal:
            add(
              labels.flipHorizontal,
              state.flipHorizontal,
              state.toggleFlipHorizontal,
              const _Flip(vertical: false),
            );
          case ScannerButton.flipVertical:
            add(
              labels.flipVertical,
              state.flipVertical,
              state.toggleFlipVertical,
              const _Flip(vertical: true),
            );
          case ScannerButton.zoom:
            add(
              labels.zoom,
              state.zoom > 1.01,
              () => unawaited(state.cycleZoom()),
              _Zoom(state.zoom),
            );
          case ScannerButton.switchCamera:
            // An action rather than a state: never shown on.
            add(
              labels.switchCamera,
              false,
              state.switchCamera,
              const _SwitchCamera(),
            );
        }
      }
      return PointerShield(
        child: Flex(
          direction: direction,
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      );
    },
  );
}

/// A button over the camera: tapped, clicked, or reached with Tab and
/// pressed with Enter or Space. It shows the hand over it, a ring when the
/// keyboard is on it, and says what it does in a tooltip.
class ScannerRoundButton extends StatefulWidget {
  /// A button reading [label], drawn by [painter] in the colour it is given.
  const ScannerRoundButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.painter,
    this.on = false,
    this.style = const ScannerButtonStyle(),
    this.tooltip = AxisDirection.left,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Draws the icon in a colour.
  final CustomPainter Function(Color color) painter;

  /// Whether what the button turns on is on.
  final bool on;
  final ScannerButtonStyle style;

  /// Where the tooltip opens.
  final AxisDirection tooltip;

  @override
  State<ScannerRoundButton> createState() => _ScannerRoundButtonState();
}

class _ScannerRoundButtonState extends State<ScannerRoundButton> {
  /// How long the mouse rests on a button before it says what it does.
  static const Duration _tooltipDelay = Duration(milliseconds: 500);

  /// How far the focus ring stands out from the button.
  static const double _ringOffset = 4;

  final OverlayPortalController _tooltip = OverlayPortalController();
  final LayerLink _link = LayerLink();
  Timer? _tooltipTimer;
  bool _hovered = false;
  bool _focused = false;

  @override
  void dispose() {
    _tooltipTimer?.cancel();
    super.dispose();
  }

  void _press() {
    _hideTooltip();
    widget.onPressed?.call();
  }

  void _onHover(bool hovered) {
    setState(() => _hovered = hovered);
    if (hovered) {
      _tooltipTimer?.cancel();
      _tooltipTimer = Timer(_tooltipDelay, _showTooltip);
    } else if (!_focused) {
      _hideTooltip();
    }
  }

  void _onFocus(bool focused) {
    setState(() => _focused = focused);
    if (focused) {
      _showTooltip();
    } else if (!_hovered) {
      _hideTooltip();
    }
  }

  void _showTooltip() {
    if (mounted && widget.style.showTooltips) _tooltip.show();
  }

  void _hideTooltip() {
    _tooltipTimer?.cancel();
    _tooltipTimer = null;
    if (_tooltip.isShowing) _tooltip.hide();
  }

  @override
  Widget build(BuildContext context) {
    final ScannerButtonStyle style = widget.style;
    final Color background = widget.on
        ? style.activeBackgroundColor
        : style.backgroundColor;
    final Color foreground = widget.on
        ? style.activeForegroundColor
        : style.foregroundColor;
    final BorderRadius? radius = style.borderRadius;
    final BoxShape shape = radius == null
        ? BoxShape.circle
        : BoxShape.rectangle;

    final Widget button = Semantics(
      button: true,
      toggled: widget.on,
      label: widget.label,
      excludeSemantics: true,
      // Hovered whatever input came last: a tooltip is for the mouse.
      child: MouseRegion(
        cursor: widget.onPressed == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        onEnter: (PointerEnterEvent _) => _onHover(true),
        onExit: (PointerExitEvent _) => _onHover(false),
        child: FocusableActionDetector(
          enabled: widget.onPressed != null,
          onShowFocusHighlight: _onFocus,
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (ActivateIntent _) {
                _press();
                return null;
              },
            ),
          },
          child: GestureDetector(
            onTap: widget.onPressed == null ? null : _press,
            behavior: HitTestBehavior.opaque,
            child: SizedBox.square(
              dimension: style.size,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // The icon's colour laid lightly over the fill on hover.
                  color: _hovered
                      ? Color.alphaBlend(
                          foreground.withValues(alpha: 0.14),
                          background,
                        )
                      : background,
                  shape: shape,
                  borderRadius: radius,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Center(
                      child: CustomPaint(
                        size: Size.square(style.iconSize),
                        painter: widget.painter(foreground),
                      ),
                    ),
                    // Around the button with a gap rather than on its edge,
                    // so it shows whatever the fill.
                    if (_focused)
                      Positioned.fill(
                        left: -_ringOffset,
                        top: -_ringOffset,
                        right: -_ringOffset,
                        bottom: -_ringOffset,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: shape,
                              borderRadius: radius == null
                                  ? null
                                  : radius + BorderRadius.circular(_ringOffset),
                              border: Border.all(
                                color: style.focusColor,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // A tooltip needs an overlay to open in; a view put somewhere with none
    // simply goes without.
    if (Overlay.maybeOf(context) == null) return button;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _tooltip,
        overlayChildBuilder: (BuildContext context) =>
            _Tooltip(link: _link, side: widget.tooltip, label: widget.label),
        child: button,
      ),
    );
  }
}

/// What a button does, next to it.
class _Tooltip extends StatelessWidget {
  const _Tooltip({required this.link, required this.side, required this.label});

  final LayerLink link;
  final AxisDirection side;
  final String label;

  @override
  Widget build(BuildContext context) {
    const double gap = 8;
    final (
      Alignment target,
      Alignment follower,
      Offset offset,
    ) = switch (side) {
      AxisDirection.left => (
        Alignment.centerLeft,
        Alignment.centerRight,
        const Offset(-gap, 0),
      ),
      AxisDirection.right => (
        Alignment.centerRight,
        Alignment.centerLeft,
        const Offset(gap, 0),
      ),
      AxisDirection.up => (
        Alignment.topCenter,
        Alignment.bottomCenter,
        const Offset(0, -gap),
      ),
      AxisDirection.down => (
        Alignment.bottomCenter,
        Alignment.topCenter,
        const Offset(0, gap),
      ),
    };
    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: link,
        targetAnchor: target,
        followerAnchor: follower,
        offset: offset,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xE6202124),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Text(
                label,
                // Read out by the button itself.
                semanticsLabel: '',
                style: const TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 12,
                  // Without a Material ancestor the ambient style is
                  // Flutter's fallback, which underlines in yellow.
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
