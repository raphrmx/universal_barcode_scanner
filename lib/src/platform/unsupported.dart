import 'package:flutter/widgets.dart';
import 'package:universal_barcode_scanner/src/barcode_app_bar.dart';
import 'package:universal_barcode_scanner/src/barcode_view_controller.dart';
import 'package:universal_barcode_scanner/src/scanner_config.dart';
import 'package:universal_barcode_scanner/src/scanner_exception.dart';

/// Fallback for a platform with neither `dart:io` nor `dart:js_interop`.
///
/// Nothing reaches this in practice; it exists so the conditional export in
/// `shared.dart` always has a default.
class BarcodeScannerPage extends StatelessWidget {
  /// Creates the fallback page.
  const BarcodeScannerPage({
    super.key,
    required this.config,
    required this.onScanned,
    required this.onClose,
    this.onError,
    this.child,
    this.barcodeAppBar,
    this.flip = false,
    this.backgroundColor,
  });

  /// What to scan and how.
  final ScannerConfig config;

  /// Called with every code read.
  final ValueChanged<String> onScanned;

  /// Called when the scanner closes without a code.
  final VoidCallback onClose;

  /// Called when the camera cannot be used.
  final ValueChanged<ScannerException>? onError;

  /// Drawn over the scanner.
  final Widget? child;

  /// App bar shown above the scanner, or null for none.
  final BarcodeAppBar? barcodeAppBar;

  /// Whether the preview is mirrored.
  final bool flip;

  /// Colour behind the camera.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Platform not supported'));
}

/// Fallback embedded view.
class BarcodeScannerView extends StatelessWidget {
  /// Creates the fallback view.
  const BarcodeScannerView({
    super.key,
    required this.config,
    required this.onBarcodeViewCreated,
    this.onScanned,
    this.onError,
    this.scanWindowSize,
    this.child,
    this.flip = false,
  });

  /// What to scan and how.
  final ScannerConfig config;

  /// Called once the view exists.
  final BarcodeScannerViewCreated onBarcodeViewCreated;

  /// Called with every code read.
  final ValueChanged<String>? onScanned;

  /// Called when the camera cannot be used.
  final ValueChanged<ScannerException>? onError;

  /// Size of the scan window.
  final Size? scanWindowSize;

  /// Drawn over the camera.
  final Widget? child;

  /// Whether the preview is mirrored.
  final bool flip;

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Platform not supported'));
}
