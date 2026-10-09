import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_dispatch_screen.dart';
import 'package:transport_app/core/admin/dispatch.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/pilot/dispatch_card.dart';
import 'package:transport_app/core/services/admin_console_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/server_clock.dart';

import 'test_utils.dart';

/// MASTER-6 Task 4: manual dispatch (suggest, call-back note).
void main() {
  late FakeFirebaseFirestore db;

  Future<Load> seedLoad({String id = 'L1', String shipper = 'c1', Duration age = const Duration(hours: 1)}) async {
    await db.collection('loads').doc(id).set({
      'shipperId': shipper, 'pickup': 'Karol Bagh, Delhi', 'drop': 'Jaipur', 'cargoType': 'Rice', 'weight': 3, 'vehicleType': 'Mini', 'status': 'open',
      'createdAt': Timestamp.fromDate(DateTime.now().subtract(age)),
    });
    return Load.fromDoc(await db.collection('loads').doc(id).get());
  }

  Future<void> seedVehicle(String id, String owner, {num capacity = 5, String type = 'Mini', String availability = 'available'}) =>
      db.collection('vehicles').doc(id).set({'ownerId': owner, 'number': 'DL1C${id.toUpperCase()}', 'type': type, 'capacity': capacity, 'status': 'active', 'availability': availability, 'rcNumber': 'RC'});

  setUp(() {
    ServerClock.reset();
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'admin1');
  });

  test('suggest: fitting free vehicles only, nearest driver first, unknown spots last, never the poster', () async {
    final load = await seedLoad();
    await seedVehicle('v1', 'near');
    await seedVehicle('v2', 'far');
    await seedVehicle('v3', 'nowhere');
    await seedVehicle('v4', 'small', capacity: 1);
    await seedVehicle('v5', 'busy', availability: 'on_trip');
    await seedVehicle('v6', 'c1'); // the customer's own
    final vehicles = [for (final d in (await db.collection('vehicles').get()).docs) (d.id, d)];
    final list = Dispatch.suggest(
      load,
      [for (final v in await Future.wait([for (final x in vehicles) db.collection('vehicles').doc(x.$1).get()])) Vehicle.fromDoc(v)],
      spotOf: (v) => switch (v.ownerId) { 'near' => (lat: 28.7, lng: 77.2), 'far' => (lat: 19.0, lng: 72.8), _ => null },
      now: DateTime.now(),
    );
    expect(list.map((c) => c.driverId), ['near', 'far', 'nowhere']);
    expect(list.first.km, lessThan(50));
    expect(list.last.km, isNull);
  });

  test('the service: unfilled loads are the open ones older than 30 minutes; suggest and call-back notes are audited', () async {
    final old = await seedLoad(id: 'old');
    await seedLoad(id: 'fresh', age: const Duration(minutes: 5));
    expect((await AdminConsoleService.unfilledLoads()).map((l) => l.id), ['old']);
    await AdminConsoleService.suggestLoad(old, 'd1', note: 'Please call the customer first');
    final s = (await db.collection('dispatch_suggestions').doc('old_d1').get()).data()!;
    expect(s['status'], 'suggested');
    expect(s['by'], 'admin1');
    expect(s['note'], 'Please call the customer first');
    await AdminConsoleService.callbackNote(old, 'Wants a call after 6 pm');
    final notes = await db.collection('users').doc('c1').collection('admin_notes').get();
    expect(notes.docs.single.data()['text'], contains('Wants a call after 6 pm'));
    final actions = (await db.collection('audit_events').get()).docs.map((e) => e.data()['data']['action']);
    expect(actions, containsAll(['dispatch_suggest', 'callback_note']));
  });

  testWidgets('the screen lists waiting loads, suggests a driver with a note and saves a call-back note', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final load = await seedLoad();
    String? sentTo, sentNote, callback;
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(
        home: AdminDispatchScreen(
          loadLoads: () async => [load],
          candidates: (_) async => [(c: const DispatchCandidate(driverId: 'd1', vehicleId: 'v1', vehicleNumber: 'DL1C0001', km: 12.4), name: 'Anil')],
          suggest: (l, d, n) async {
            sentTo = d;
            sentNote = n;
          },
          callback: (l, t) async => callback = t,
        ),
      ),
    ));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('dispSuggest_L1')));
    await settle(tester);
    expect(find.text('12 km from pickup'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('dispNote')), 'Urgent');
    await tester.tap(find.byKey(const ValueKey('dispSend_d1')));
    await settle(tester);
    expect(sentTo, 'd1');
    expect(sentNote, 'Urgent');
    await tester.tap(find.byKey(const ValueKey('dispCall_L1')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('dispCallbackText')), 'Call at 6');
    await tester.tap(find.byKey(const ValueKey('dispCallbackSave')));
    await settle(tester);
    expect(callback, 'Call at 6');
  });

  testWidgets('driver card shows the suggestion; "Not for me" removes it', (tester) async {
    Backend.useFakes(db: db, uid: () => 'd1');
    await db.collection('dispatch_suggestions').doc('L1_d1').set({'loadId': 'L1', 'driverId': 'd1', 'pickup': 'Delhi', 'drop': 'Jaipur', 'weight': 3, 'vehicleType': 'Mini', 'note': 'Call first', 'by': 'a', 'status': 'suggested'});
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: Scaffold(body: DispatchSuggestionsCard()))));
    await settle(tester);
    expect(find.text('Delhi → Jaipur'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dispDismiss_L1_d1')));
    await settle(tester);
    expect(find.byKey(const ValueKey('dispatchCard')), findsNothing);
  });
}
