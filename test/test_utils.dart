import 'package:flutter_test/flutter_test.dart';

/// Fake Firestore futures complete on real async while spinners animate, so
/// interleave frames with real time before settling.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
  }
  await tester.pumpAndSettle();
}
