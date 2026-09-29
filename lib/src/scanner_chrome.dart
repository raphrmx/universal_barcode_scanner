import 'package:flutter/widgets.dart';
import 'package:universal_barcode_scanner/src/scanner_bar.dart';
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

  /// What a screen reader says for the close button.
  final String closeLabel;

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
            alignment: buttonsAlignment,
            inset: EdgeInsets.fromLTRB(
              padding.left + 12 + (besideClose ? 52 : 0),
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
          child: _CloseButton(onPressed: onClose, label: closeLabel),
        ),
      ],
    );
  }
}

/// A round button with a cross, over the camera.
class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed, required this.label});

  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: const SizedBox.square(
        dimension: 44,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0x99000000),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: CustomPaint(size: Size.square(14), painter: _Cross()),
          ),
        ),
      ),
    ),
  );
}

class _Cross extends CustomPainter {
  const _Cross();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = _barForeground
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(Offset.zero, Offset(size.width, size.height), paint)
      ..drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(_Cross oldDelegate) => false;
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
class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed, required this.label, this.icon});

  final VoidCallback? onPressed;
  final String label;
  final Widget? icon;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: _barHeight,
        height: _barHeight,
        child: Center(
          child:
              icon ??
              const CustomPaint(size: Size.square(20), painter: _Chevron()),
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
