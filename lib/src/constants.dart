import 'dart:ui' show Color;

/// Where the scanner page lives inside the package assets.
///
/// Desktop reads it from the bundle on disk, web from the served asset
/// directory, hence the two spellings of the same file.
abstract final class ScannerAsset {
  /// Path handed to the Windows webview, resolved against the bundle.
  static const String desktopPath =
      'packages/universal_barcode_scanner/assets/barcode.html';

  /// URL the web iframe loads.
  static const String webPath =
      'assets/packages/universal_barcode_scanner/assets/barcode.html';
}

/// Title shown when the caller does not provide one.
const String kScanPageTitle = 'Scan barcode/qrcode';

/// Sentinel the native scanners emit when the user cancels a continuous scan.
const String kCancelValue = '-2';

/// Sentinel the native scanners return when a single scan is cancelled. It is
/// mapped to `null` before it reaches the caller.
const String kNoResultValue = '-1';

/// Default colour of the scan line.
const Color kDefaultLineColor = Color(0xFFFF6666);

/// Renders [color] as `#AARRGGBB`, the only form both native scanners parse.
String colorToHex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
