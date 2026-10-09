import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_surveys_screen.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/pilot/reuse_survey.dart';
import 'package:transport_app/core/services/admin_console_service.dart';
import 'package:transport_app/core/services/backend.dart';

import 'test_utils.dart';

/// MASTER-6 Task 7: the one-tap "use it again?" survey and its admin view.
void main() {
  late FakeFirebaseFirestore db;
  late Booking booking;

  setUp(() async {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'c1');
    await db.collection('bookings').doc('b1').set({'customerId': 'c1', 'driverId': 'd1', 'status': 'delivered', 'loadId': 'l1'});
    booking = Booking.fromDoc(await db.collection('bookings').doc('b1').get());
  });

  test('stats: counts per side, percent of yes, junk rows ignored', () {
    final s = SurveyStats.compute([
      {'role': 'customer', 'answer': 'yes'},
      {'role': 'customer', 'answer': 'yes'},
      {'role': 'customer', 'answer': 'no'},
      {'role': 'driver', 'answer': 'maybe'},
      {'role': 'admin', 'answer': 'yes'},
      {'role': 'driver', 'answer': 'sure'},
    ]);
    expect(s.total('customer'), 3);
    expect(s.yesPercent('customer'), 66);
    expect(s.yesPercent('driver'), 0);
    expect(SurveyStats.compute(const []).yesPercent('driver'), isNull);
  });

  test('answer writes one document per trip and person; mine reads it back', () async {
    expect(await SurveyService.mine('b1'), isNull);
    await SurveyService.answer(booking, 'customer', 'yes');
    expect(await SurveyService.mine('b1'), 'yes');
    final d = (await db.collection('trip_surveys').doc('b1_c1').get()).data()!;
    expect(d['role'], 'customer');
    expect(d.keys.toSet(), {'bookingId', 'uid', 'role', 'answer', 'createdAt'});
  });

  testWidgets('the card asks once, then thanks', (tester) async {
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: ReuseSurveyCard(booking: booking, role: 'customer')))));
    await settle(tester);
    expect(find.textContaining('again?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sv_maybe')));
    await settle(tester);
    expect(find.text('Thank you, noted.'), findsOneWidget);
    expect(find.byKey(const ValueKey('sv_yes')), findsNothing);
    // a fresh card for the same trip does not ask again
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: ReuseSurveyCard(booking: booking, role: 'customer')))));
    await settle(tester);
    expect(find.byKey(const ValueKey('sv_yes')), findsNothing);
  });

  test('the service reads the newest answers for the admin', () async {
    await SurveyService.answer(booking, 'customer', 'yes');
    Backend.useFakes(db: db, uid: () => 'd1');
    await SurveyService.answer(booking, 'driver', 'no');
    final s = await AdminConsoleService.surveyStats();
    expect((s.total('customer'), s.total('driver')), (1, 1));
  });

  testWidgets('admin screen shows both sides', (tester) async {
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(home: AdminSurveysScreen(load: () async => SurveyStats.compute([{'role': 'customer', 'answer': 'yes'}]))),
    ));
    await settle(tester);
    expect(find.textContaining('1 answers · yes 100%'), findsOneWidget);
    expect(find.text('No answers yet.'), findsOneWidget);
  });
}
