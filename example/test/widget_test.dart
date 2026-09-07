import 'package:example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the menu offers the three ways to scan', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('Scan once'), findsOneWidget);
    expect(find.text('Scan continuously'), findsOneWidget);
    expect(find.text('Embedded view (Android and iOS)'), findsOneWidget);
    expect(find.text('Result: '), findsOneWidget);
  });
}
