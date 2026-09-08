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

/// Sentinel the native scanners emit when the user cancels a continuous scan.
const String kCancelValue = '-2';

/// Sentinel the native scanners return when a single scan is cancelled. It is
/// mapped to `null` before it reaches the caller.
const String kNoResultValue = '-1';

/// Default colour of the scan line.
const Color kDefaultLineColor = Color(0xFFFF6666);

/// Largest size the webview scanner is given, in logical pixels. Below that it
/// takes the whole viewport. Web and desktop share it so the scanner looks the
/// same on both.
const double kMaxScannerWidth = 640;

/// Companion of [kMaxScannerWidth].
const double kMaxScannerHeight = 480;

/// Renders [color] as `#RRGGBB`, which is what CSS expects. The alpha channel
/// is dropped: the scan line carries its own opacity.
String colorToCssHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Renders [color] as `#AARRGGBB`, the only form both native scanners parse.
String colorToHex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
