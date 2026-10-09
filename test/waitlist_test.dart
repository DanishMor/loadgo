import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/pilot/waitlist.dart';
import 'package:transport_app/core/services/backend.dart';

import 'test_utils.dart';

/// MASTER-6 Task 2: pilot areas and the waitlist.
void main() {
  late FakeFirebaseFirestore db;
  setUp(() {
    PilotAreas.reset();
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'u1');
  });

  test('no list = everywhere; a list closes the other known cities; unknown places are not refused', () {
    expect(const PilotAreas([]).isOpen('Mumbai'), isTrue);
    const a = PilotAreas(['Delhi', 'Jaipur']);
    expect(a.isOpen('Karol Bagh, Delhi'), isTrue);
    expect(a.isOpen('Mumbai'), isFalse);
    expect(a.isOpen('some village'), isTrue);
    expect(a.firstClosed(['Delhi', 'Andheri, Mumbai']), 'Mumbai');
    expect(a.firstClosed(['Delhi', 'jaipur']), isNull);
    expect(PilotAreas.fromMap({'openCities': ['Delhi', 3, ' ', 'Pune']}).openCities, ['Delhi', 'Pune']);
  });

  test('refresh reads config/pilot; a failure keeps the last list', () async {
    await db.collection('config').doc('pilot').set({'openCities': ['Delhi']});
    expect((await PilotAreas.refresh(force: true)).openCities, ['Delhi']);
    expect(PilotAreas.current.isOpen('Pune'), isFalse);
  });

  test('join is one entry per route; opened lists the routes that are open now; leave removes', () async {
    final id = await WaitlistService.join(role: 'customer', from: 'Pune', to: 'Delhi');
    expect(id, 'u1_pune_delhi');
    await WaitlistService.join(role: 'customer', from: 'Pune', to: 'Delhi');
    expect((await db.collection('waitlist').get()).docs.length, 1);
    expect(await WaitlistService.opened(const PilotAreas(['Delhi', 'Jaipur'])), isEmpty);
    expect((await WaitlistService.opened(const PilotAreas(['Delhi', 'Pune']))).single.id, id);
    await WaitlistService.leave(id);
    expect(await WaitlistService.mine(), isEmpty);
  });

  testWidgets('the dialog offers the waitlist and joining saves the route', (tester) async {
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Builder(builder: (c) => TextButton(onPressed: () => showNotServed(c, role: 'customer', closedCity: 'Pune', from: 'Pune', to: 'Delhi'), child: const Text('go'))))));
    await tester.tap(find.text('go'));
    await settle(tester);
    expect(find.textContaining('We do not serve Pune yet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('wlJoin')));
    await settle(tester);
    expect((await db.collection('waitlist').get()).docs.single.data()['to'], 'Delhi');
  });

  testWidgets('the home card tells a waitlisted person the route is open and closing it leaves the list', (tester) async {
    await WaitlistService.join(role: 'customer', from: 'Pune', to: 'Delhi');
    await db.collection('config').doc('pilot').set({'openCities': ['Delhi', 'Pune']});
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: Scaffold(body: WaitlistOpenCard()))));
    await settle(tester);
    expect(find.textContaining('Pune to Delhi is open now'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('wlOpenClose')));
    await settle(tester);
    expect(find.byKey(const ValueKey('wlOpenCard')), findsNothing);
    expect(await WaitlistService.mine(), isEmpty);
  });
}
