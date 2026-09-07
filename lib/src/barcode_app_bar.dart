import 'package:flutter/material.dart';

/// App bar shown above the scanner.
///
/// Passing one is what makes the scanner show an app bar at all: leave it null
/// and the camera fills the route.
class BarcodeAppBar {
  /// Creates an app bar description for the scanner route.
  const BarcodeAppBar({
    this.appBarTitle,
    this.centerTitle,
    this.enableBackButton,
    this.backButtonIcon,
  });

  /// Title text, or null for no title.
  final String? appBarTitle;

  /// Whether the title is centred.
  final bool? centerTitle;

  /// Whether a back button is shown.
  final bool? enableBackButton;

  /// Icon of the back button, when one is shown.
  final Icon? backButtonIcon;
}
