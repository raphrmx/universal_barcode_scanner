import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// An icon drawn in a square of any size, in one colour.
abstract class ScannerIcon {
  const ScannerIcon();

  void paint(Canvas canvas, Size size, Paint fill, Paint stroke);
}

/// Paints a [ScannerIcon] in [color]: its fills solid, its lines round-ended.
class ScannerIconPainter extends CustomPainter {
  const ScannerIconPainter(this.icon, this.color);

  final ScannerIcon icon;
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
  bool shouldRepaint(ScannerIconPainter oldDelegate) =>
      oldDelegate.icon != icon || oldDelegate.color != color;
}

/// A lightning bolt.
class BoltIcon extends ScannerIcon {
  const BoltIcon();

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
class PausePlayIcon extends ScannerIcon {
  const PausePlayIcon({required this.paused});

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
      other is PausePlayIcon && other.paused == paused;

  @override
  int get hashCode => paused.hashCode;
}

/// Two arrows going opposite ways, one above the other: ⇄ for the
/// horizontal flip, and turned a quarter, ⇅, for the vertical one.
class FlipIcon extends ScannerIcon {
  const FlipIcon({required this.vertical});

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
      other is FlipIcon && other.vertical == vertical;

  @override
  int get hashCode => vertical.hashCode;
}

/// A camera with two arrows going round inside it.
class SwitchCameraIcon extends ScannerIcon {
  const SwitchCameraIcon();

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
class ZoomIcon extends ScannerIcon {
  const ZoomIcon(this.zoom);

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
  bool operator ==(Object other) => other is ZoomIcon && other.zoom == zoom;

  @override
  int get hashCode => zoom.hashCode;
}
