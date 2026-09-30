import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:universal_barcode_scanner/src/scan_feedback.dart';

/// The verdict on each code read, for [ScannerVerdict] to show: each call is
/// one code.
final class ScanVerdicts extends ChangeNotifier {
  /// Whether the last code was accepted.
  bool get lastAccepted => _lastAccepted;
  bool _lastAccepted = false;

  /// A code taken.
  void accepted() {
    _lastAccepted = true;
    notifyListeners();
  }

  /// A code the validator refused.
  void rejected() {
    _lastAccepted = false;
    notifyListeners();
  }
}

/// Shows the verdict on each code read over the camera. A code accepted
/// flashes the edge green once, with the vibration. A code refused flashes
/// it red twice, with the two pulses of its vibration, and shows
/// [rejectedLabel] at the bottom for a couple of seconds, read out by a
/// screen reader.
///
/// Drawn over the camera by the web, Windows and Linux pages and by the
/// embedded view; the native screens of Android, iOS and macOS say a refusal
/// themselves.
class ScannerVerdict extends StatefulWidget {
  /// Shows each verdict of [verdicts].
  const ScannerVerdict({
    super.key,
    required this.verdicts,
    required this.rejectedLabel,
  });

  /// The verdict on each code read.
  final ScanVerdicts verdicts;

  /// What is shown and read out for a code refused, or empty for the red
  /// edge alone.
  final String rejectedLabel;

  @override
  State<ScannerVerdict> createState() => _ScannerVerdictState();
}

class _ScannerVerdictState extends State<ScannerVerdict>
    with SingleTickerProviderStateMixin {
  static const Color _red = Color(0xFFE5484D);
  static const Color _green = Color(0xFF30C46C);

  /// How long each verdict shows: a refusal leaves time to read the words.
  static const int _acceptedMs = 300;
  static const int _rejectedMs = 2200;

  late final AnimationController _shown = AnimationController(vsync: this);

  /// The verdict showing.
  bool _accepted = false;

  @override
  void initState() {
    super.initState();
    widget.verdicts.addListener(_show);
  }

  @override
  void didUpdateWidget(ScannerVerdict oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.verdicts, widget.verdicts)) {
      oldWidget.verdicts.removeListener(_show);
      widget.verdicts.addListener(_show);
    }
  }

  @override
  void dispose() {
    widget.verdicts.removeListener(_show);
    _shown.dispose();
    super.dispose();
  }

  void _show() {
    _accepted = widget.verdicts.lastAccepted;
    _shown
      ..duration = Duration(milliseconds: _accepted ? _acceptedMs : _rejectedMs)
      ..forward(from: 0);
  }

  /// How strong the edge is [ms] after the verdict: one quick flash for a
  /// code accepted, two for a code refused, the second as the second pulse
  /// of the vibration.
  double _edge(double ms) {
    double flash(double from) {
      final double t = ms - from;
      if (t < 0) return 0;
      if (t < 40) return t / 40;
      return math.max(0, 1 - (t - 40) / 180);
    }

    if (_accepted) return flash(0);
    final double gap = ScanFeedback.rejectedPulseGap.inMilliseconds.toDouble();
    return math.max(flash(0), flash(gap));
  }

  /// How much the words show at [t] of the whole: in quickly, out slowly.
  static double _words(double t) => t < 0.06
      ? Curves.easeOut.transform(t / 0.06)
      : t > 0.82
      ? Curves.easeIn.transform((1 - t) / 0.18)
      : 1;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: _shown,
      builder: (BuildContext context, Widget? words) {
        if (!_shown.isAnimating) return const SizedBox.shrink();
        final double t = _shown.value;
        final double edge = _edge(t * (_accepted ? _acceptedMs : _rejectedMs));
        final double shown = _words(t).clamp(0.0, 1.0);
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (edge > 0)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: (_accepted ? _green : _red).withValues(alpha: edge),
                    width: 3,
                  ),
                ),
              ),
            if (words != null && !_accepted)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                  child: Opacity(
                    opacity: shown,
                    child: Transform.translate(
                      offset: Offset(0, 6 * (1 - shown)),
                      child: words,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      child: widget.rejectedLabel.isEmpty
          ? null
          : Semantics(liveRegion: true, child: _Toast(widget.rejectedLabel)),
    ),
  );
}

/// The words, as a phone says a short thing: a small dark capsule, a mark
/// and the text.
class _Toast extends StatelessWidget {
  const _Toast(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xE61C1C1E),
      borderRadius: BorderRadius.circular(100),
      boxShadow: const <BoxShadow>[
        BoxShadow(
          color: Color(0x40000000),
          blurRadius: 12,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CustomPaint(size: Size.square(15), painter: _RefusedMark()),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.25,
                letterSpacing: 0.1,
                // Without a Material ancestor the ambient style is
                // Flutter's fallback, which underlines in yellow.
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A red disc with a white bar across: not this one.
class _RefusedMark extends CustomPainter {
  const _RefusedMark();

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = size.center(Offset.zero);
    final double radius = size.shortestSide / 2;
    canvas.drawCircle(centre, radius, Paint()..color = const Color(0xFFFF453A));
    canvas.drawLine(
      centre - Offset(radius * 0.45, 0),
      centre + Offset(radius * 0.45, 0),
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..strokeWidth = size.shortestSide * 0.14
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RefusedMark oldDelegate) => false;
}
