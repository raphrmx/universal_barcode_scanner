import 'package:example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the menu offers the three ways to scan', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('Embedded view'), findsOneWidget);
    expect(find.text('Scan once'), findsOneWidget);

    // The third card is below the fold of the test window, so the list has
    // not built it yet.
    await tester.scrollUntilVisible(
      find.text('Scan continuously'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Scan continuously'), findsOneWidget);
  });

  testWidgets('the result panel starts empty', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('NOTHING SCANNED YET'), findsOneWidget);
    expect(
      find.text('Pick a mode below and point the camera at a barcode.'),
      findsOneWidget,
    );
  });
}
