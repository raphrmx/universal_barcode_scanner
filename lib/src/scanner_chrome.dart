import 'package:flutter/widgets.dart';
import 'package:universal_barcode_scanner/src/pointer_shield.dart';
import 'package:universal_barcode_scanner/src/scanner_bar.dart';
import 'package:universal_barcode_scanner/src/scanner_button_style.dart';
import 'package:universal_barcode_scanner/src/scanner_buttons.dart';

/// Default colours of the scanner bar, dark because it sits over a camera.
const Color _barBackground = Color(0xFF000000);
const Color _barForeground = Color(0xFFFFFFFF);

/// Height of the bar, above the status bar inset.
const double _barHeight = 56;

/// The page the scanner fills: an optional bar above the camera.
///
/// Built from `widgets.dart` alone: no Material, no Cupertino.
class ScannerChrome extends StatelessWidget {
  /// Creates the page around [body].
  const ScannerChrome({
    super.key,
    required this.body,
    this.bar,
    this.onClose,
    this.backgroundColor,
    this.buttons,
    this.buttonsAlignment = Alignment.centerRight,
    this.closeLabel = 'Close',
    this.buttonStyle = const ScannerButtonStyle(),
  });

  /// The camera and whatever is drawn over it.
  final Widget body;

  /// The bar to show, or null for a camera that fills the page.
  final ScannerBar? bar;

  /// Called by the back button, when the bar shows one.
  final VoidCallback? onClose;

  /// Colour behind the camera. Black when null.
  final Color? backgroundColor;

  /// The buttons over the camera, or null for none.
  final ScannerButtonGroup? buttons;

  /// Where [buttons] sit over the camera.
  final AlignmentGeometry buttonsAlignment;

  /// What the close button says, to a screen reader and in its tooltip.
  final String closeLabel;

  /// How [buttons] and the close button look.
  final ScannerButtonStyle buttonStyle;

  @override
  Widget build(BuildContext context) {
    final ScannerBar? bar = this.bar;
    final EdgeInsets padding = MediaQuery.paddingOf(context);
    final ScannerButtonGroup? buttons = this.buttons;
    Widget body = this.body;
    if (buttons != null) {
      final Alignment at = buttonsAlignment.resolve(
        Directionality.maybeOf(context),
      );
      // Without a bar the close button holds the top left corner.
      final bool besideClose = bar == null && at.x < 0 && at.y < 0;
      body = Stack(
        fit: StackFit.expand,
        children: <Widget>[
          body,
          ScannerButtonsOverlay(
            state: buttons.state,
            buttons: buttons.buttons,
            labels: buttons.labels,
            style: buttonStyle,
            alignment: buttonsAlignment,
            inset: EdgeInsets.fromLTRB(
              padding.left + 12 + (besideClose ? buttonStyle.size + 8 : 0),
              12,
              padding.right + 12,
              padding.bottom + 12,
            ),
          ),
        ],
      );
    }
    final Widget page = ColoredBox(
      color: backgroundColor ?? _barBackground,
      child: Column(
        children: <Widget>[
          if (bar != null)
            _ScannerBar(bar: bar, onClose: onClose)
          else
            SizedBox(height: padding.top),
          Expanded(child: body),
        ],
      ),
    );
    if (bar != null) return page;

    // Without a bar there has to be another way out: a desktop has no back
    // gesture, and the page the camera runs in holds the keyboard.
    return Stack(
      children: <Widget>[
        page,
        Positioned(
          top: padding.top + 12,
          left: padding.left + 12,
          child: PointerShield(
            child: ScannerRoundButton(
              label: closeLabel,
              onPressed: onClose,
              style: buttonStyle,
              tooltip: AxisDirection.right,
              painter: _Cross.new,
            ),
          ),
        ),
      ],
    );
  }
}

/// A cross, for the close button.
class _Cross extends CustomPainter {
  const _Cross(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    // The cross is lighter than the other icons: a little inside the square.
    final Rect box = Offset.zero & size;
    final Rect inner = box.deflate(size.shortestSide * 0.15);
    canvas
      ..drawLine(inner.topLeft, inner.bottomRight, paint)
      ..drawLine(inner.topRight, inner.bottomLeft, paint);
  }

  @override
  bool shouldRepaint(_Cross oldDelegate) => oldDelegate.color != color;
}

/// The bar itself: a title, and a back button when one is asked for.
class _ScannerBar extends StatelessWidget {
  const _ScannerBar({required this.bar, this.onClose});

  final ScannerBar bar;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final Color foreground = bar.foregroundColor ?? _barForeground;
    final String? title = bar.title;
    final bool back = bar.showBackButton;

    final Widget label = title == null
        ? const SizedBox.shrink()
        : Text(
            title,
            style: TextStyle(
              color: foreground,
              fontSize: 20,
              fontWeight: FontWeight.w500,
              // Without a Material ancestor the ambient style is Flutter's
              // fallback, which underlines in yellow.
              decoration: TextDecoration.none,
            ),
            overflow: TextOverflow.ellipsis,
          );

    return ColoredBox(
      color: bar.backgroundColor ?? _barBackground,
      child: Padding(
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        child: SizedBox(
          height: _barHeight,
          child: Row(
            children: <Widget>[
              if (back)
                _BackButton(
                  onPressed: onClose,
                  label: bar.cancelLabel,
                  icon: bar.backIcon,
                  focusColor: foreground,
                )
              else
                const SizedBox(width: 16),
              if (bar.centerTitle) ...<Widget>[
                Expanded(child: Center(child: label)),
                SizedBox(width: back ? _barHeight : 16),
              ] else
                Expanded(child: label),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tappable square holding the back icon. No ink ripple.
class _BackButton extends StatefulWidget {
  const _BackButton({
    required this.onPressed,
    required this.label,
    required this.focusColor,
    this.icon,
  });

  final VoidCallback? onPressed;
  final String label;
  final Widget? icon;

  /// The ring around it when the keyboard is on it.
  final Color focusColor;

  @override
  State<_BackButton> createState() => _BackButtonState();
}

class _BackButtonState extends State<_BackButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label,
    excludeSemantics: true,
    // Reached with Tab and pressed with Enter or Space too, the hand over it.
    child: FocusableActionDetector(
      enabled: widget.onPressed != null,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (bool focused) =>
          setState(() => _focused = focused),
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (ActivateIntent _) {
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: _barHeight,
          height: _barHeight,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: _focused
                    ? Border.all(color: widget.focusColor, width: 2)
                    : null,
              ),
              child: SizedBox.square(
                dimension: 40,
                child: Center(
                  child:
                      widget.icon ??
                      const CustomPaint(
                        size: Size.square(20),
                        painter: _Chevron(),
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A back chevron, so a bar with no icon of its own still has one.
class _Chevron extends CustomPainter {
  const _Chevron();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = _barForeground
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Path path = Path()
      ..moveTo(size.width * 0.65, 0)
      ..lineTo(size.width * 0.25, size.height / 2)
      ..lineTo(size.width * 0.65, size.height);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_Chevron oldDelegate) => false;
}
