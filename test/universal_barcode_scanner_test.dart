import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_barcode_scanner/src/constants.dart';
import 'package:universal_barcode_scanner/src/native_scanner.dart';
import 'package:universal_barcode_scanner/universal_barcode_scanner.dart';

void main() {
  group('wire format', () {
    // These strings are compared verbatim by the Android and iOS scanners, so
    // renaming an enum value must not change them.
    test('ScanFormat carries the names the native scanners expect', () {
      expect(ScanFormat.all.wireName, 'ALL_FORMATS');
      expect(ScanFormat.onlyQrCode.wireName, 'ONLY_QR_CODE');
      expect(ScanFormat.onlyBarcode.wireName, 'ONLY_BARCODE');
    });

    // The native side reads the scan mode by index, not by name.
    test('ScanMode keeps its indexes', () {
      expect(ScanMode.qr.index, 0);
      expect(ScanMode.barcode.index, 1);
      expect(ScanMode.defaultMode.index, 2);
    });

    test('CameraFace uppercases to what the plugin switches on', () {
      expect(CameraFace.back.name.toUpperCase(), 'BACK');
      expect(CameraFace.front.name.toUpperCase(), 'FRONT');
    });
  });

  group('colorToHex', () {
    test('renders eight digits, alpha first', () {
      expect(colorToHex(const Color(0xFFFF6666)), '#FFFF6666');
      expect(colorToHex(kDefaultLineColor), '#FFFF6666');
    });

    test('pads a colour whose alpha is low', () {
      expect(colorToHex(const Color(0x0A0B0C0D)), '#0A0B0C0D');
    });
  });

  group('UniversalBarcodeScanner', () {
    testWidgets('says so on a platform with no embedded view', (
      WidgetTester tester,
    ) async {
      // Reset inside the body: the framework checks foundation debug flags
      // before tearDowns run.
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;

      await tester.pumpWidget(
        MaterialApp(
          home: UniversalBarcodeScanner(
            onScanned: (String _) {},
            onBarcodeViewCreated: (BarcodeViewController _) {},
          ),
        ),
      );

      expect(find.textContaining('embedded scanner view'), findsOneWidget);
      expect(tester.takeException(), isNull);

      debugDefaultTargetPlatformOverride = null;
    });
  });
}
