import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:universal_barcode_scanner/src/enums.dart';
import 'package:universal_barcode_scanner/src/pointer_shield.dart';
import 'package:universal_barcode_scanner/src/scanner_button_style.dart';
import 'package:universal_barcode_scanner/src/scanner_controller.dart';
import 'package:universal_barcode_scanner/src/scanner_icons.dart';
import 'package:universal_barcode_scanner/src/scanner_labels.dart';
import 'package:universal_barcode_scanner/src/scanner_round_button.dart';

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
      void add(
        String label,
        bool on,
        VoidCallback onPressed,
        ScannerIcon icon,
      ) {
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
            painter: (Color color) => ScannerIconPainter(icon, color),
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
              const BoltIcon(),
            );
          case ScannerButton.pause:
            // Says what a tap does: the icon shows it too.
            add(
              state.paused ? labels.resume : labels.pause,
              state.paused,
              () => unawaited(state.togglePause()),
              PausePlayIcon(paused: state.paused),
            );
          case ScannerButton.flipHorizontal:
            add(
              labels.flipHorizontal,
              state.flipHorizontal,
              state.toggleFlipHorizontal,
              const FlipIcon(vertical: false),
            );
          case ScannerButton.flipVertical:
            add(
              labels.flipVertical,
              state.flipVertical,
              state.toggleFlipVertical,
              const FlipIcon(vertical: true),
            );
          case ScannerButton.zoom:
            add(
              labels.zoom,
              state.zoom > 1.01,
              () => unawaited(state.cycleZoom()),
              ZoomIcon(state.zoom),
            );
          case ScannerButton.switchCamera:
            // An action rather than a state: never shown on.
            add(
              labels.switchCamera,
              false,
              state.switchCamera,
              const SwitchCameraIcon(),
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
