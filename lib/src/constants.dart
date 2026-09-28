import 'dart:ui' show Color;

/// Where the scanner page lives inside the package assets.
///
/// Desktop hands the asset key to the webview, web loads it as a served URL,
/// hence the two spellings of the same file.
abstract final class ScannerAsset {
  /// Asset key handed to the desktop webview.
  static const String desktopPath =
      'packages/universal_barcode_scanner/assets/barcode.html';

  /// URL the web iframe loads.
  static const String webPath =
      'assets/packages/universal_barcode_scanner/assets/barcode.html';
}

/// Title shown when the caller does not provide one.
const String kScanPageTitle = 'Scan barcode/qrcode';

/// Default colour of the scan line.
const Color kDefaultLineColor = Color(0xFFFF6666);

/// Renders [color] as `#RRGGBB`, which is what CSS expects. The alpha channel
/// is dropped: the scan line carries its own opacity.
String colorToCssHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Renders [color] as `#AARRGGBB`, the only form both native scanners parse.
String colorToHex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
