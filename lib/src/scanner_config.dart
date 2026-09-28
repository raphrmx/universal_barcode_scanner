import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:universal_barcode_scanner/src/constants.dart';
import 'package:universal_barcode_scanner/src/enums.dart';

/// Everything the scanner itself needs to know, whichever platform runs it.
///
/// What only concerns the Flutter side, such as the app bar or the widget
/// drawn over the camera, stays on the page.
@immutable
class ScannerConfig {
  /// Creates a configuration.
  const ScannerConfig({
    this.lineColor = kDefaultLineColor,
    this.cancelButtonText = 'Cancel',
    this.showFlashIcon = false,
    this.scanType = ScanType.barcode,
    this.cameraFace = CameraFace.back,
    this.scanFormat = ScanFormat.all,
    this.scanDelay,
    this.continuous = false,
  });

  /// Colour of the scan line.
  final Color lineColor;

  /// Label of the cancel button on the native scanners.
  final String cancelButtonText;

  /// Whether the native scanners show a torch toggle.
  final bool showFlashIcon;

  /// Shape of the scan window: square for QR codes, wide for barcodes.
  final ScanType scanType;

  /// Which camera to open.
  final CameraFace cameraFace;

  /// Symbologies to accept.
  final ScanFormat scanFormat;

  /// Least time between two codes in continuous mode.
  final Duration? scanDelay;

  /// Whether reading continues after the first code.
  final bool continuous;

  /// Milliseconds of [scanDelay], zero when there is none.
  int get delayMillis => scanDelay?.inMilliseconds ?? 0;

  /// Arguments of `scanBarcode` for the Android, iOS and macOS scanners.
  Map<String, Object?> toNative() => <String, Object?>{
    'lineColor': colorToHex(lineColor),
    'cancelButtonText': cancelButtonText,
    'showFlashIcon': showFlashIcon,
    'continuous': continuous,
    'scanType': scanType.name,
    'cameraFace': cameraFace.name,
    'scanFormat': scanFormat.wireName,
    'delayMillis': delayMillis,
  };

  /// Settings of the bundled page, read by its `configure` function on the
  /// desktop and from the query string on the web.
  Map<String, String> toPage({Color? background}) => <String, String>{
    'line': colorToCssHex(lineColor),
    if (background != null) 'background': colorToCssHex(background),
    'continuous': continuous ? '1' : '0',
    'delay': '$delayMillis',
    'facing': cameraFace == CameraFace.front ? 'user' : 'environment',
    'window': scanType == ScanType.barcode ? 'wide' : 'square',
    'formats': switch (scanFormat) {
      ScanFormat.all => 'all',
      ScanFormat.onlyQrCode => 'qr',
      ScanFormat.onlyBarcode => 'barcode',
    },
  };
}
