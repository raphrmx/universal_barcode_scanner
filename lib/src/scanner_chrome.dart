import 'package:flutter/widgets.dart';
import 'package:universal_barcode_scanner/src/barcode_app_bar.dart';

/// Default colours of the scanner bar, dark because it sits over a camera.
const Color _barBackground = Color(0xFF000000);
const Color _barForeground = Color(0xFFFFFFFF);

/// Height of the bar, above the status bar inset.
const double _barHeight = 56;

/// The page the scanner fills: an optional bar above the camera.
///
/// This is what a `Scaffold` was doing, drawn with `widgets.dart` alone so the
/// package imposes neither Material nor any other design system on the app
/// that embeds it.
class ScannerChrome extends StatelessWidget {
  /// Creates the page around [body].
  const ScannerChrome({
    super.key,
    required this.body,
    this.bar,
    this.onClose,
    this.backgroundColor,
  });

  /// The camera and whatever is drawn over it.
  final Widget body;

  /// The bar to show, or null for a camera that fills the page.
  final BarcodeAppBar? bar;

  /// Called by the back button, when the bar shows one.
  final VoidCallback? onClose;

  /// Colour behind the camera. Black when null.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final BarcodeAppBar? bar = this.bar;
    return ColoredBox(
      color: backgroundColor ?? _barBackground,
      child: Column(
        children: <Widget>[
          if (bar != null)
            _ScannerBar(bar: bar, onClose: onClose)
          else
            SizedBox(height: MediaQuery.paddingOf(context).top),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// The bar itself: a title, and a back button when one is asked for.
class _ScannerBar extends StatelessWidget {
  const _ScannerBar({required this.bar, this.onClose});

  final BarcodeAppBar bar;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final Color foreground = bar.foregroundColor ?? _barForeground;
    final String? title = bar.appBarTitle;
    final bool back = bar.enableBackButton == true;

    final Widget label = title == null
        ? const SizedBox.shrink()
        : Text(
            title,
            style: TextStyle(
              color: foreground,
              fontSize: 20,
              fontWeight: FontWeight.w500,
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
                _BackButton(onPressed: onClose, icon: bar.backButtonIcon)
              else
                const SizedBox(width: 16),
              if (bar.centerTitle ?? false) ...<Widget>[
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

/// A tappable square holding the back icon, in place of Material's
/// `IconButton`. There is no ripple: drawing one would mean a design system.
class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed, this.icon});

  final VoidCallback? onPressed;
  final Icon? icon;

  @override
  Widget build(BuildContext context) => GestureDetector(
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
