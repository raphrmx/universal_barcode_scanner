import 'package:flutter/widgets.dart';

/// How the buttons over the camera look: the group asked for with `buttons`,
/// and the close button of a scanner with no bar.
///
/// Round and dark by default, filled in white while what a button turns on
/// is on, so they read over any camera. Every colour, the size and the shape
/// can be changed.
@immutable
class const ScannerButtonStyle({
  /// Width and height of a button, in logical pixels. 44 is the least a
  /// finger reliably hits.
  final double size = 44,

  /// Size of the icon inside it.
  final double iconSize = 20,

  /// Space between two buttons of the group.
  final double spacing = 8,

  /// Fill and icon of a button, off.
  final Color backgroundColor = const Color(0x99000000),
  final Color foregroundColor = const Color(0xFFFFFFFF),

  /// Fill and icon of a button whose setting is on: the torch lit, reading
  /// paused, a flip applied, a zoom.
  final Color activeBackgroundColor = const Color(0xE6FFFFFF),
  final Color activeForegroundColor = const Color(0xFF000000),

  /// The ring around the button the keyboard is on.
  final Color focusColor = const Color(0xFFFFFFFF),

  /// Corners of a button, or null for a circle.
  final BorderRadius? borderRadius,

  /// Whether a button says what it does when the mouse rests on it, or when
  /// the keyboard reaches it.
  final bool showTooltips = true,
}) {
  /// The default look, or the one given.
  this : assert(size > 0 && iconSize > 0 && spacing >= 0, 'sizes are positive');

  /// This style with the values given changed.
  ScannerButtonStyle copyWith({
    double? size,
    double? iconSize,
    double? spacing,
    Color? backgroundColor,
    Color? foregroundColor,
    Color? activeBackgroundColor,
    Color? activeForegroundColor,
    Color? focusColor,
    BorderRadius? borderRadius,
    bool? showTooltips,
  }) => ScannerButtonStyle(
    size: size ?? this.size,
    iconSize: iconSize ?? this.iconSize,
    spacing: spacing ?? this.spacing,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    foregroundColor: foregroundColor ?? this.foregroundColor,
    activeBackgroundColor: activeBackgroundColor ?? this.activeBackgroundColor,
    activeForegroundColor: activeForegroundColor ?? this.activeForegroundColor,
    focusColor: focusColor ?? this.focusColor,
    borderRadius: borderRadius ?? this.borderRadius,
    showTooltips: showTooltips ?? this.showTooltips,
  );

  @override
  bool operator ==(Object other) =>
      other is ScannerButtonStyle &&
      other.size == size &&
      other.iconSize == iconSize &&
      other.spacing == spacing &&
      other.backgroundColor == backgroundColor &&
      other.foregroundColor == foregroundColor &&
      other.activeBackgroundColor == activeBackgroundColor &&
      other.activeForegroundColor == activeForegroundColor &&
      other.focusColor == focusColor &&
      other.borderRadius == borderRadius &&
      other.showTooltips == showTooltips;

  @override
  int get hashCode => Object.hash(
    size,
    iconSize,
    spacing,
    backgroundColor,
    foregroundColor,
    activeBackgroundColor,
    activeForegroundColor,
    focusColor,
    borderRadius,
    showTooltips,
  );
}
