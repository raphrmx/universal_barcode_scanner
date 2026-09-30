import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:universal_barcode_scanner/universal_barcode_scanner.dart';

/// The platform's own image reader, on a device: ML Kit on Android, Vision on
/// iOS and macOS, the scanner page on the web, Windows and Linux.
///
///     flutter test integration_test -d <device>
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<Uint8List> sample([String name = 'two_codes']) async {
    final ByteData image = await rootBundle.load('assets/samples/$name.png');
    return image.buffer.asUint8List(image.offsetInBytes, image.lengthInBytes);
  }

  testWidgets('reads both codes of the sample image', (WidgetTester _) async {
    final List<ScanResult> codes = await UniversalBarcodeScanner.scanImage(
      await sample(),
    );
    expect(
      <String, BarcodeFormat>{
        for (final ScanResult code in codes) code.text: code.format,
      },
      <String, BarcodeFormat>{
        'WIFI:T:WPA;S:Universal Barcode Scanner;P:scan-me;;':
            BarcodeFormat.qrCode,
        '5412345678908': BarcodeFormat.ean13,
      },
    );
  });

  testWidgets('reads only the formats asked for', (WidgetTester _) async {
    final List<ScanResult> codes = await UniversalBarcodeScanner.scanImage(
      await sample(),
      scanFormat: ScanFormat.onlyQrCode,
    );
    expect(codes.map((ScanResult code) => code.format), <BarcodeFormat>[
      BarcodeFormat.qrCode,
    ]);
  });

  testWidgets('says when the bytes are no image', (WidgetTester _) async {
    await expectLater(
      UniversalBarcodeScanner.scanImage(<int>[1, 2, 3, 4, 5]),
      throwsA(
        isA<ScannerException>().having(
          (ScannerException e) => e.code,
          'code',
          ScannerErrorCode.invalidImage,
        ),
      ),
    );
  });

  testWidgets('reads every sample, and what each one holds', (
    WidgetTester _,
  ) async {
    Future<ScanResult> only(String name) async {
      final List<ScanResult> codes = await UniversalBarcodeScanner.scanImage(
        await sample(name),
      );
      expect(codes, hasLength(1), reason: name);
      return codes.single;
    }

    final ScanResult wifi = await only('wifi');
    expect(wifi.content, isA<WifiContent>());
    expect((wifi.content! as WifiContent).password, 'scan-me');
    expect((await only('link')).content, isA<UrlContent>());
    final ScanContent? contact = (await only('contact')).content;
    expect(contact, isA<ContactContent>());
    expect((contact! as ContactContent).name, 'Jane Doe');
    expect((await only('email')).content, isA<EmailContent>());
    expect((await only('phone')).content, isA<PhoneContent>());
    expect((await only('sms')).content, isA<SmsContent>());
    expect((await only('place')).content, isA<GeoContent>());
    expect((await only('event')).content, isA<EventContent>());
    final ScanResult product = await only('product');
    expect(product.format, BarcodeFormat.ean13);
    expect(product.content, isNull);
  });
}
