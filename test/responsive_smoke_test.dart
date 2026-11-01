import 'package:dabtmateapp/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Firebase setup screen renders at phone, tablet, and desktop widths', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final width in [360.0, 768.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(const DebtMateApp(configured: false));
      await tester.pumpAndSettle();

      expect(find.text('Connect DebtMate to Firebase'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}