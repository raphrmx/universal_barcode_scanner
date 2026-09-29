import 'package:example/main.dart';
import 'package:flutter/foundation.dart';
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

  testWidgets('mirrors the camera by default on a desktop, and toggles', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(const ExampleApp());
      FilterChip chip(String label) => tester.widget<FilterChip>(
            find.widgetWithText(FilterChip, label),
          );

      expect(chip('Flip horizontally').selected, isTrue);
      expect(chip('Flip vertically').selected, isFalse);

      await tester.tap(find.text('Flip horizontally'));
      await tester.tap(find.text('Flip vertically'));
      await tester.pump();
      expect(chip('Flip horizontally').selected, isFalse);
      expect(chip('Flip vertically').selected, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
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
