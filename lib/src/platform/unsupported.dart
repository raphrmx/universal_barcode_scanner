import 'package:flutter/widgets.dart';
import 'package:universal_barcode_scanner/src/enums.dart';
import 'package:universal_barcode_scanner/src/scan_result.dart';
import 'package:universal_barcode_scanner/src/scanner_bar.dart';
import 'package:universal_barcode_scanner/src/scanner_config.dart';
import 'package:universal_barcode_scanner/src/scanner_controller.dart';
import 'package:universal_barcode_scanner/src/scanner_exception.dart';

/// Fallback for a platform with neither `dart:io` nor `dart:js_interop`.
///
/// Nothing reaches this in practice; it exists so the conditional export in
/// `shared.dart` always has a default.
class ScannerPage extends StatelessWidget {
  /// Creates the fallback page.
  const ScannerPage({
    super.key,
    required this.config,
    required this.onScanned,
    required this.onClose,
    this.onError,
    this.child,
    this.bar,
    this.backgroundColor,
    this.buttons = const <ScannerButton>{},
    this.buttonsAlignment = Alignment.centerRight,
  });

  /// What to scan and how.
  final ScannerConfig config;

  /// Called with every code read.
  final ValueChanged<ScanResult> onScanned;

  /// Called when the scanner closes without a code.
  final VoidCallback onClose;

  /// Called when the camera cannot be used.
  final ValueChanged<ScannerException>? onError;

  /// Drawn over the scanner.
  final Widget? child;

  /// App bar shown above the scanner, or null for none.
  final ScannerBar? bar;

  /// The buttons over the camera, on Windows and Linux.
  final Set<ScannerButton> buttons;

  /// Where [buttons] sit.
  final AlignmentGeometry buttonsAlignment;

  /// Colour behind the camera.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Platform not supported'));
}

/// Fallback embedded view.
class EmbeddedScanner extends StatelessWidget {
  /// Creates the fallback view.
  const EmbeddedScanner({
    super.key,
    required this.config,
    required this.onCreated,
    this.onScanned,
    this.onError,
    this.scanWindowSize,
    this.child,
  });

  /// What to scan and how.
  final ScannerConfig config;

  /// Called once the view exists.
  final ScannerCreatedCallback onCreated;

  /// Called with every code read.
  final ValueChanged<String>? onScanned;

  /// Called when the camera cannot be used.
  final ValueChanged<ScannerException>? onError;

  /// Size of the scan window.
  final Size? scanWindowSize;

  /// Drawn over the camera.
  final Widget? child;

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Platform not supported'));
}

/// No sound to play here.
void playBeep() {}
