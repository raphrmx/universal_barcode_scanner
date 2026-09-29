import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:universal_barcode_scanner/src/scanner_button_style.dart';

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
