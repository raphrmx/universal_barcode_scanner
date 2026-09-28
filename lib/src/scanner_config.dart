import 'dart:convert';
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
  /// desktop and from the query string on the web. [host] is `web` or
  /// `desktop`, which changes what the page tells the user when the camera
  /// does not start.
  ///
  /// The background is always sent, black when null: the desktop page is kept
  /// between two scans and would otherwise keep the previous one's colour.
  Map<String, String> toPage({required String host, Color? background}) =>
      <String, String>{
        'host': host,
        'line': colorToCssHex(lineColor),
        'background': colorToCssHex(background ?? const Color(0xFF000000)),
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

/// A message from the bundled page: a code, or the user asking to close.
///
/// The page posts JSON rather than the bare code, so that no code can be
/// mistaken for a command.
sealed class PageMessage {
  const PageMessage();

  /// Reads what the page posted, or null when it is not one of its messages.
  static PageMessage? parse(Object? data) {
    if (data is! String || data.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final Object? code = decoded['code'];
    if (code is String && code.isNotEmpty) return PageCode(code);
    if (decoded['close'] == true) return const PageClose();
    return null;
  }
}

/// A code the page read.
final class PageCode extends PageMessage {
  /// Wraps [code].
  const PageCode(this.code);

  /// The payload.
  final String code;
}

/// The user asked the page to close, with the Escape key.
final class PageClose extends PageMessage {
  /// Creates the message.
  const PageClose();
}
