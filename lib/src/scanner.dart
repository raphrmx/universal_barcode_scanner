import 'dart:async';

import 'package:flutter/material.dart';
import 'package:universal_barcode_scanner/src/barcode_app_bar.dart';
import 'package:universal_barcode_scanner/src/barcode_view_controller.dart';
import 'package:universal_barcode_scanner/src/constants.dart';
import 'package:universal_barcode_scanner/src/enums.dart';
import 'package:universal_barcode_scanner/src/platform/shared.dart';

/// Barcode and QR code scanner.
///
/// Two ways to use it. As a route, when you just want a code back:
///
/// ```dart
/// final String? code = await UniversalBarcodeScanner.scan(context);
/// ```
///
/// Or as a widget, when the camera has to sit inside your own layout. That
/// form is Android and iOS only; elsewhere use [scan] or [stream].
///
/// ```dart
/// UniversalBarcodeScanner(
///   onScanned: (String code) => debugPrint(code),
///   onBarcodeViewCreated: (BarcodeViewController c) => controller = c,
/// );
/// ```
class UniversalBarcodeScanner extends StatelessWidget {
  /// Creates an embedded scanner view.
  const UniversalBarcodeScanner({
    super.key,
    required this.onBarcodeViewCreated,
    this.onScanned,
    this.scaleWidth,
    this.scaleHeight,
    this.scanType = ScanType.barcode,
    this.cameraFace = CameraFace.back,
    this.scanFormat = ScanFormat.all,
    this.scanDelay,
    this.child,
    this.continuous = false,
    this.flip = false,
    this.onClose,
  });

  /// Called once the platform view exists, with the controller that drives it.
  final BarcodeScannerViewCreated onBarcodeViewCreated;

  /// Called with every code read.
  final ValueChanged<String>? onScanned;

  /// Width of the view, or null to fill the constraints.
  final double? scaleWidth;

  /// Height of the view, or null to fill the constraints.
  final double? scaleHeight;

  /// What the scanner looks for.
  final ScanType scanType;

  /// Which camera to open.
  final CameraFace cameraFace;

  /// Symbologies to accept. Android and iOS only; web reads every format.
  final ScanFormat scanFormat;

  /// Pause between two reads in continuous mode.
  final Duration? scanDelay;

  /// Drawn over the scanner, for instance a manual entry field.
  final Widget? child;

  /// Whether reading continues after the first code.
  final bool continuous;

  /// Whether the preview is mirrored, for a front camera.
  final bool flip;

  /// Called when the scanner closes.
  final VoidCallback? onClose;

  /// Opens the scanner as a route and returns the code that was read.
  ///
  /// Completes with null when the user backs out without scanning.
  static Future<String?> scan(
    BuildContext context, {
    Color lineColor = kDefaultLineColor,
    String cancelButtonText = 'Cancel',
    bool isShowFlashIcon = false,
    ScanType scanType = ScanType.barcode,
    CameraFace cameraFace = CameraFace.back,
    ScanFormat scanFormat = ScanFormat.all,
    BarcodeAppBar? barcodeAppBar,
    Duration? scanDelay,
    bool flip = false,
    Widget? child,
  }) {
    return Navigator.push<String>(
      context,
      MaterialPageRoute<String>(
        builder: (BuildContext context) => BarcodeScannerPage(
          lineColor: lineColor,
          cancelButtonText: cancelButtonText,
          isShowFlashIcon: isShowFlashIcon,
          scanType: scanType,
          cameraFace: cameraFace,
          scanFormat: scanFormat,
          barcodeAppBar: barcodeAppBar,
          scanDelay: scanDelay,
          flip: flip,
          // Android and iOS answer '-1' when the user backs out. That
          // sentinel has no business reaching the caller.
          onScanned: (String code) => Navigator.pop(
            context,
            code == kNoResultValue || code.isEmpty ? null : code,
          ),
          child: child,
        ),
      ),
    );
  }

  /// Opens the scanner as a route and emits every code read until it closes.
  ///
  /// The stream is closed when the route goes away, whichever way it goes:
  /// the back button, a system gesture, or a pop from your own code.
  static Stream<String> stream(
    BuildContext context, {
    Color lineColor = kDefaultLineColor,
    String cancelButtonText = 'Cancel',
    bool isShowFlashIcon = false,
    ScanType scanType = ScanType.barcode,
    CameraFace cameraFace = CameraFace.back,
    ScanFormat scanFormat = ScanFormat.all,
    BarcodeAppBar? barcodeAppBar,
    Duration? scanDelay,
    bool flip = false,
    Widget? child,
  }) {
    final StreamController<String> codes = StreamController<String>();
    final NavigatorState navigator = Navigator.of(context);

    navigator
        .push<void>(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => BarcodeScannerPage(
              lineColor: lineColor,
              cancelButtonText: cancelButtonText,
              isShowFlashIcon: isShowFlashIcon,
              scanType: scanType,
              cameraFace: cameraFace,
              scanFormat: scanFormat,
              barcodeAppBar: barcodeAppBar,
              scanDelay: scanDelay,
              flip: flip,
              onScanned: codes.add,
              onClose: () => Navigator.pop(context),
              child: child,
            ),
          ),
        )
        // Closing on the route's own future covers every way out, including
        // the ones that never reach onClose.
        .whenComplete(codes.close);

    return codes.stream;
  }

  @override
  Widget build(BuildContext context) {
    return BarcodeScannerView(
      scannerWidth: scaleWidth,
      scannerHeight: scaleHeight,
      scanType: scanType,
      cameraFace: cameraFace,
      scanFormat: scanFormat,
      scanDelay: scanDelay,
      onScanned: onScanned,
      continuous: continuous,
      onClose: onClose,
      flip: flip,
      onBarcodeViewCreated: onBarcodeViewCreated,
      child: child,
    );
  }
}
