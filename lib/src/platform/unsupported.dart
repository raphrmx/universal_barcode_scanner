import 'package:flutter/material.dart';
import 'package:universal_barcode_scanner/src/barcode_app_bar.dart';
import 'package:universal_barcode_scanner/src/barcode_view_controller.dart';
import 'package:universal_barcode_scanner/src/constants.dart';
import 'package:universal_barcode_scanner/src/enums.dart';

/// Fallback for a platform with neither `dart:io` nor `dart:js_interop`.
///
/// Nothing reaches this in practice; it exists so the conditional export in
/// `shared.dart` always has a default.
class BarcodeScannerPage extends StatelessWidget {
  /// Creates the fallback page.
  const BarcodeScannerPage({
    super.key,
    required this.onScanned,
    this.lineColor = kDefaultLineColor,
    this.cancelButtonText = 'Cancel',
    this.isShowFlashIcon = false,
    this.scanType = ScanType.barcode,
    this.cameraFace = CameraFace.back,
    this.child,
    this.barcodeAppBar,
    this.scanDelay,
    this.flip = false,
    this.onClose,
    this.scanFormat = ScanFormat.all,
  });

  /// Colour of the scan line.
  final Color lineColor;

  /// Label of the cancel button.
  final String cancelButtonText;

  /// Whether the torch toggle is shown.
  final bool isShowFlashIcon;

  /// What the scanner looks for.
  final ScanType scanType;

  /// Which camera to open.
  final CameraFace cameraFace;

  /// Called with every code read.
  final ValueChanged<String> onScanned;

  /// Drawn over the scanner.
  final Widget? child;

  /// App bar shown above the scanner, or null for none.
  final BarcodeAppBar? barcodeAppBar;

  /// Pause between two reads in continuous mode.
  final Duration? scanDelay;

  /// Whether the preview is mirrored.
  final bool flip;

  /// Called when the scanner closes.
  final VoidCallback? onClose;

  /// Symbologies to accept.
  final ScanFormat scanFormat;

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Platform not supported'));
}

/// Fallback embedded view.
class BarcodeScannerView extends StatelessWidget {
  /// Creates the fallback view.
  const BarcodeScannerView({
    super.key,
    required this.onBarcodeViewCreated,
    required this.onScanned,
    this.scannerWidth,
    this.scannerHeight,
    this.scanType = ScanType.barcode,
    this.cameraFace = CameraFace.back,
    this.continuous = false,
    this.child,
    this.scanDelay,
    this.flip = false,
    this.onClose,
    this.scanFormat = ScanFormat.all,
  });

  /// Called once the view exists.
  final BarcodeScannerViewCreated onBarcodeViewCreated;

  /// Width of the view.
  final double? scannerWidth;

  /// Height of the view.
  final double? scannerHeight;

  /// What the scanner looks for.
  final ScanType scanType;

  /// Which camera to open.
  final CameraFace cameraFace;

  /// Called with every code read.
  final ValueChanged<String>? onScanned;

  /// Drawn over the scanner.
  final Widget? child;

  /// Pause between two reads in continuous mode.
  final Duration? scanDelay;

  /// Whether the preview is mirrored.
  final bool flip;

  /// Called when the scanner closes.
  final VoidCallback? onClose;

  /// Whether reading continues after the first code.
  final bool continuous;

  /// Symbologies to accept.
  final ScanFormat scanFormat;

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Platform not supported'));
}
