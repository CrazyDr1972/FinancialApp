// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:financial_app/main.dart';

void main() {
  testWidgets('loads the private register seed on startup', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FinancialApp());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Financial App'), findsWidgets);
    expect(find.text('Επισκόπηση'), findsWidgets);
    expect(find.text('Δεν υπάρχουν δεδομένα ακόμη'), findsNothing);
  });
}
