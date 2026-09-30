import 'package:example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the menu offers the ways to scan', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());

    // The cards are below the fold of the test window, so the list has not
    // built them all yet.
    for (final String mode in <String>[
      'Embedded view',
      'Scan once',
      'Scan continuously',
      'Read an image',
    ]) {
      await tester.scrollUntilVisible(
        find.text(mode),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(mode), findsOneWidget);
    }
  });

  testWidgets('places the buttons on the right side, and elsewhere on request',
      (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());
    ChoiceChip chip(String label) =>
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));

    expect(chip('Right side').selected, isTrue);
    await tester.tap(find.text('Bottom'));
    await tester.pump();
    expect(chip('Right side').selected, isFalse);
    expect(chip('Bottom').selected, isTrue);
  });

  testWidgets('the result panel starts empty', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('NOTHING SCANNED YET'), findsOneWidget);
    expect(
      find.text('Pick a mode below and point the camera at a barcode.'),
      findsOneWidget,
    );
  });

  testWidgets('reads the sample image, and says what each code holds', (
    WidgetTester tester,
  ) async {
    await _readTwoAtOnce(tester);

    expect(find.text('SCANNED, image, 2 CODES'), findsOneWidget);
    expect(find.text('5412345678908'), findsOneWidget);
    expect(
      find.text('A Wi-Fi network, Universal Barcode Scanner, WPA'),
      findsOneWidget,
    );
    expect(find.textContaining('Refused'), findsNothing);
  });

  testWidgets('marks the codes the Accept row refuses', (
    WidgetTester tester,
  ) async {
    await _readTwoAtOnce(tester, accept: 'Products only');

    // The product is taken, the Wi-Fi network is not.
    expect(find.text('SCANNED, image, 2 CODES'), findsOneWidget);
    expect(find.textContaining('Refused by the Accept row'), findsOneWidget);
  });

  testWidgets('says when the Accept row refuses every code', (
    WidgetTester tester,
  ) async {
    await _readTwoAtOnce(tester, accept: 'Links only');

    expect(find.text('REFUSED, image, 2 CODES'), findsOneWidget);
    expect(find.textContaining('Refused by the Accept row'), findsNWidgets(2));
  });
}

/// Chooses [accept] in the Accept row, reads the "Two at once" sample, a
/// Wi-Fi network and a product, and scrolls back to the result tile.
Future<void> _readTwoAtOnce(WidgetTester tester, {String? accept}) async {
  // The tests run as Android: the plugin's image reader stands in.
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('universal_barcode_scanner'),
    (MethodCall call) async => call.method == 'scanImage'
        ? <Object?>[
            <String, Object?>{
              'code': 'WIFI:T:WPA;S:Universal Barcode Scanner;P:scan-me;;',
              'format': 'qr_code',
            },
            <String, Object?>{'code': '5412345678908', 'format': 'ean_13'},
          ]
        : null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('universal_barcode_scanner'),
      null,
    ),
  );
  await tester.pumpWidget(const ExampleApp());
  final Finder list = find.byType(Scrollable).first;
  if (accept != null) {
    await tester.scrollUntilVisible(find.text(accept), 200, scrollable: list);
    await tester.ensureVisible(find.text(accept));
    await tester.pumpAndSettle();
    await tester.tap(find.text(accept));
    await tester.pumpAndSettle();
  }
  await tester.scrollUntilVisible(
    find.text('Two at once'),
    200,
    scrollable: list,
  );
  await tester.ensureVisible(find.text('Two at once'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Two at once'));
  await tester.pumpAndSettle();
  // Back up to the result tile.
  await tester.drag(list, const Offset(0, 3000));
  await tester.pumpAndSettle();
}
