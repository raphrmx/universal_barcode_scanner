import 'package:flutter/widgets.dart';

/// A bar above the web, Windows and Linux scanner: a title, and a back
/// button.
///
/// Without one, the camera fills the route and a close button sits over it.
/// The native scanners of Android, iOS and macOS draw their own chrome: of
/// this they only take [cancelLabel].
class ScannerBar {
  /// Describes the bar.
  const ScannerBar({
    this.title,
    this.centerTitle = false,
    this.showBackButton = true,
    this.backIcon,
    this.backgroundColor,
    this.foregroundColor,
    this.cancelLabel = 'Cancel',
  });

  /// Title text, or null for no title.
  final String? title;

  /// Whether the title is centred.
  final bool centerTitle;

  /// Whether a back button is shown. On by default: on a desktop it is the
  /// way out of the scanner.
  final bool showBackButton;

  /// Icon of the back button, or null for a chevron.
  final Widget? backIcon;

  /// Colour behind the bar. Black when null, to sit over a camera.
  final Color? backgroundColor;

  /// Colour of the title and of the back icon, the chevron or the [Icon]
  /// given as [backIcon]. White when null.
  final Color? foregroundColor;

  /// What leaving the scanner is called: the text of the cancel button on
  /// the native scanners of Android, iOS and macOS, and what a screen reader
  /// says for the back button of this bar.
  final String cancelLabel;
}
