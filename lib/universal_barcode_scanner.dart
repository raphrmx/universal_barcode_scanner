/// Barcode and QR code scanner for Flutter, on Android, iOS, Linux, macOS, web
/// and Windows.
///
/// One entry point, [UniversalBarcodeScanner]. Use its static [
/// UniversalBarcodeScanner.scan] to open the scanner as a route and get a code
/// back, [UniversalBarcodeScanner.stream] to keep reading, or the widget itself
/// to embed the camera in your own layout on Android and iOS.
///
/// ```dart
/// final String? code = await UniversalBarcodeScanner.scan(context);
/// ```
library;

export 'src/enums.dart';
export 'src/scan_result.dart';
export 'src/scanner.dart';
export 'src/scanner_bar.dart';
export 'src/scanner_button_style.dart';
export 'src/scanner_controller.dart'
    show ScannerController, ScannerCreatedCallback;
export 'src/scanner_exception.dart';
export 'src/scanner_labels.dart';
