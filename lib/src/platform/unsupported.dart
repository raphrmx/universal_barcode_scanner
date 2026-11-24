import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:universal_barcode_scanner/src/enums.dart';
import 'package:universal_barcode_scanner/src/scan_result.dart';
import 'package:universal_barcode_scanner/src/scanner_bar.dart';
import 'package:universal_barcode_scanner/src/scanner_button_style.dart';
import 'package:universal_barcode_scanner/src/scanner_config.dart';
import 'package:universal_barcode_scanner/src/scanner_controller.dart';
import 'package:universal_barcode_scanner/src/scanner_exception.dart';
import 'package:universal_barcode_scanner/src/scanner_verdict.dart';

/// Fallback for a platform with neither `dart:io` nor `dart:js_interop`.
///
/// Nothing reaches this in practice; it exists so the conditional export in
/// `shared.dart` always has a default.
class const ScannerPage({
  super.key,

  /// What to scan and how.
  required final ScannerConfig config,

  /// Called with every code read.
  required final ValueChanged<ScanResult> onScanned,

  /// Called when the scanner closes without a code.
  required final VoidCallback onClose,

  /// Called when the camera cannot be used.
  final ValueChanged<ScannerException>? onError,

  /// Drawn over the scanner.
  final Widget? child,

  /// App bar shown above the scanner, or null for none.
  final ScannerBar? bar,

  /// Colour behind the camera.
  final Color? backgroundColor,

  /// The buttons over the camera, on Windows and Linux.
  final Set<ScannerButton> buttons = const <ScannerButton>{},

  /// Where [buttons] sit.
  final AlignmentGeometry buttonsAlignment = Alignment.centerRight,

  /// How the buttons look.
  final ScannerButtonStyle buttonStyle = const ScannerButtonStyle(),

  /// The verdict on each code read, each one shown over the camera.
  final ScanVerdicts? verdicts,
}) extends StatelessWidget {
  /// Creates the fallback page.
  this;

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Platform not supported'));
}

/// Fallback embedded view.
class const EmbeddedScanner({
  super.key,

  /// What to scan and how.
  required final ScannerConfig config,

  /// Called once the view exists.
  required final ScannerCreatedCallback onCreated,

  /// Called with every code read.
  final ValueChanged<String>? onScanned,

  /// Called when the camera cannot be used.
  final ValueChanged<ScannerException>? onError,

  /// Size of the scan window.
  final Size? scanWindowSize,

  /// Drawn over the camera.
  final Widget? child,
}) extends StatelessWidget {
  /// Creates the fallback view.
  this;

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Platform not supported'));
}

/// No sound to play here.
void playBeep() {}

/// No sound to play here.
void playRejectedBeep() {}

/// Nothing to read an image with here.
Future<List<ScanResult>> readImage(Uint8List bytes, ScanFormat format) async =>
    throw const ScannerException(
      ScannerErrorCode.unknown,
      'No image reader on this platform.',
    );
