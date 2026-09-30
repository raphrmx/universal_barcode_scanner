import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Says a code was read but not accepted: a red edge around the camera that
/// fades, and [label] at the bottom for a couple of seconds, read out by a
/// screen reader.
///
/// Each change of [rejections] is one code refused. Drawn over the camera by
/// the web, Windows and Linux pages and by the embedded view; the native
/// screens of Android, iOS and macOS say it themselves.
class ScannerRejection extends StatefulWidget {
  /// Shows a refusal each time [rejections] changes.
  const ScannerRejection({
    super.key,
    required this.rejections,
    required this.label,
  });

  /// Counts the codes refused.
  final ValueListenable<int> rejections;

  /// What is shown and read out, or empty for the red edge alone.
  final String label;

  @override
  State<ScannerRejection> createState() => _ScannerRejectionState();
}

class _ScannerRejectionState extends State<ScannerRejection>
    with SingleTickerProviderStateMixin {
  static const Color _red = Color(0xFFE5484D);

  late final AnimationController _shown = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void initState() {
    super.initState();
    widget.rejections.addListener(_show);
  }

  @override
  void didUpdateWidget(ScannerRejection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.rejections, widget.rejections)) {
      oldWidget.rejections.removeListener(_show);
      widget.rejections.addListener(_show);
    }
  }

  @override
  void dispose() {
    widget.rejections.removeListener(_show);
    _shown.dispose();
    super.dispose();
  }

  void _show() => _shown.forward(from: 0);

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: _shown,
      builder: (BuildContext context, Widget? words) {
        final double t = _shown.value;
        if (!_shown.isAnimating) return const SizedBox.shrink();
        // The edge fades over the first half second; the words come in at
        // once, stay, and go over the last part.
        final double edge = (1 - t / 0.25).clamp(0.0, 1.0);
        final double shown = t < 0.06
            ? t / 0.06
            : t > 0.8
            ? (1 - t) / 0.2
            : 1;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (edge > 0)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _red.withValues(alpha: edge),
                    width: 4,
                  ),
                ),
              ),
            if (words != null)
              Align(
                alignment: const Alignment(0, 0.8),
                child: Opacity(opacity: shown.clamp(0.0, 1.0), child: words),
              ),
          ],
        );
      },
      child: widget.label.isEmpty
          ? null
          : Semantics(
              liveRegion: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xE6B42318),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
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
