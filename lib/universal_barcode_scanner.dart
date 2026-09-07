/// Barcode and QR code scanner for Flutter, on Android, iOS, web and Windows.
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

export 'src/barcode_app_bar.dart';
export 'src/barcode_view_controller.dart'
    show BarcodeScannerViewCreated, BarcodeViewController;
export 'src/enums.dart';
export 'src/scanner.dart';
