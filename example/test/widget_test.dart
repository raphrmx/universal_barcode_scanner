import 'package:example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the menu offers the three ways to scan', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('Embedded view'), findsOneWidget);

    // The other cards are below the fold of the test window, so the list has
    // not built them yet.
    for (final String mode in <String>['Scan once', 'Scan continuously']) {
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
}
