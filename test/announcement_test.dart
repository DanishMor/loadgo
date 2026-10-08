import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/announcement/announcement.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/server_clock.dart';

import 'test_utils.dart';

/// MASTER-5 Task 40: the admin's notice on the home screens.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AnnouncementService.reset();
    ServerClock.reset();
  });

  test('parsing: text per language, level, last day, roles, a stable id', () {
    final a = Announcement.fromMap({'id': 'x1', 'text': 'Closed on 12 Nov', 'text_hindi': 'बंद', 'level': 'warning', 'until': '2026-11-12', 'roles': ['driver', 3]})!;
    expect(a.textFor(AppLanguage.hindi), 'बंद');
    expect(a.textFor(AppLanguage.tamil), 'Closed on 12 Nov');
    expect(a.level, 'warning');
    expect(a.roles, ['driver']);
    expect(Announcement.fromMap({'text': 'a'})!.id, Announcement.fromMap({'text': 'a'})!.id);
    expect(Announcement.fromMap({'text': 'a', 'level': 'loud'})!.level, 'info');
    expect(Announcement.fromMap({'text': '  '}), isNull);
    expect(Announcement.fromMap({'id': 'x'}), isNull);
    expect(Announcement.fromMap(null), isNull);
  });

  test('active through the whole last day, and only for the listed roles', () {
    final a = Announcement.fromMap({'text': 'x', 'until': '2026-11-12', 'roles': ['driver']})!;
    expect(a.isActive(DateTime(2026, 11, 12, 23, 59), 'driver'), isTrue);
    expect(a.isActive(DateTime(2026, 11, 13, 0, 1), 'driver'), isFalse);
    expect(a.isActive(DateTime(2026, 11, 1), 'customer'), isFalse);
    expect(Announcement.fromMap({'text': 'x'})!.isActive(DateTime(2030), 'fleet'), isTrue);
  });

  test('the service reads config/announcement; a missing document clears it', () async {
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'u1');
    await db.collection('config').doc('announcement').set({'text': 'Hello'});
    await AnnouncementService.refresh(force: true);
    expect(AnnouncementService.current.value!.textFor(AppLanguage.english), 'Hello');
    await db.collection('config').doc('announcement').delete();
    await AnnouncementService.refresh(force: true);
    expect(AnnouncementService.current.value, isNull);
  });

  Widget app(String role) => LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: AnnouncementBanner(role: role))));

  testWidgets('the banner shows, can be closed for good, and a new id shows again', (tester) async {
    AnnouncementService.current.value = Announcement.fromMap({'id': 'n1', 'text': 'Support is closed on Sunday'});
    await tester.pumpWidget(app('customer'));
    await settle(tester);
    expect(find.text('Support is closed on Sunday'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('announcementClose')));
    await settle(tester);
    expect(find.text('Support is closed on Sunday'), findsNothing);
    // a fresh screen: still closed
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app('customer'));
    await settle(tester);
    expect(find.text('Support is closed on Sunday'), findsNothing);
    // a new announcement shows again
    AnnouncementService.current.value = Announcement.fromMap({'id': 'n2', 'text': 'New notice'});
    await settle(tester);
    expect(find.text('New notice'), findsOneWidget);
  });

  testWidgets('an urgent notice cannot be closed; a notice for other roles is hidden', (tester) async {
    AnnouncementService.current.value = Announcement.fromMap({'id': 'u1', 'text': 'App update needed', 'level': 'urgent', 'roles': ['driver']});
    await tester.pumpWidget(app('customer'));
    await settle(tester);
    expect(find.text('App update needed'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app('driver'));
    await settle(tester);
    expect(find.text('App update needed'), findsOneWidget);
    expect(find.byKey(const ValueKey('announcementClose')), findsNothing);
  });
}
