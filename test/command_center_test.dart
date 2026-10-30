import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/fleet/command_center.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/offer.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/fleet/command_center_view.dart';

final now = DateTime(2027, 5, 20, 12);
final _db = FakeFirebaseFirestore();
final _v = <String, Vehicle>{};
final _o = <String, Offer>{};

Future<void> _fixtures() async {
  Future<void> v(String id, String number, {String status = 'active', Map<String, Object?> docs = const {}}) async {
    await _db.doc('vehicles/$id').set({'ownerId': 'f1', 'number': number, 'type': '14ft', 'status': status, 'docs': docs});
    _v[id] = Vehicle.fromDoc(await _db.doc('vehicles/$id').get());
  }

  await v('a', 'MH01AA1111');
  await v('b', 'MH01BB2222');
  await v('c', 'MH01CC3333', docs: {'insurance': {'expiry': Timestamp.fromDate(DateTime(2027, 5, 1))}});
  await v('d', 'MH01DD4444', status: 'inactive');
  await v('e', 'MH01EE5555', docs: {'puc': {'expiry': Timestamp.fromDate(DateTime(2027, 6, 1))}});
  for (final (id, status) in [('o1', 'pending'), ('o2', 'countered'), ('o3', 'rejected')]) {
    await _db.doc('offers/$id').set({'loadId': 'L$id', 'driverId': 'f1', 'pickup': 'Pune', 'drop': 'Surat', 'pricePaise': 2000000, 'counterPaise': status == 'countered' ? 1800000 : null, 'status': status});
    _o[id] = Offer.fromDoc(await _db.doc('offers/$id').get());
  }
}

Booking b(String id, String vehicleId, String status) => Booking.fromMap(id, {'vehicleId': vehicleId, 'vehicleNumber': 'x', 'status': status, 'pickup': 'Pune', 'drop': 'Surat', 'fleetOwnerId': 'f1'});

/// E23: the transporter command center.
void main() {
  setUpAll(_fixtures);

  test('board: on trip, booked, free, papers expired, not active; sorted by state', () {
    final cc = CommandCenter.compute(
      vehicles: _v.values,
      bookings: [b('B1', 'a', 'in_transit'), b('B2', 'b', 'accepted'), b('B3', 'e', 'delivered')],
      bids: _o.values,
      idleDays: const {'e': 20, 'b': 25},
      dues: const [(name: 'Sharma Traders', duePaise: 500000), (name: 'Paid Co', duePaise: 0)],
      now: now,
    );
    expect([for (final x in cc.board) (x.vehicle.id, x.state)], [
      ('a', VehicleState.onTrip),
      ('b', VehicleState.assigned),
      ('e', VehicleState.available),
      ('c', VehicleState.blocked),
      ('d', VehicleState.off),
    ]);
    expect(cc.board.first.booking!.id, 'B1');
    expect(cc.pendingBids.map((o) => o.id).toSet(), {'o1', 'o2'});
    expect(cc.alerts.map((a) => a.kind), [AlertKind.papersExpired, AlertKind.counterOffer, AlertKind.papersSoon, AlertKind.idleTruck, AlertKind.idleTruck, AlertKind.partyDue]);
    expect(cc.alerts.where((a) => a.kind == AlertKind.partyDue).single.subject, 'Sharma Traders');
    expect(cc.counts[VehicleState.onTrip], 1);
  });

  test('a truck on a trip is never called idle; nothing at all gives an empty center', () {
    final cc = CommandCenter.compute(vehicles: [_v['a']!], bookings: [b('B1', 'a', 'loading')], bids: const [], idleDays: const {'a': 29}, dues: const [], now: now);
    expect(cc.alerts, isEmpty);
    final empty = CommandCenter.compute(vehicles: const [], bookings: const [], bids: const [], idleDays: const {}, dues: const [], now: now);
    expect(empty.board, isEmpty);
    expect(empty.alerts, isEmpty);
  });

  Widget host(Widget child, {AppLanguage lang = AppLanguage.english, Brightness b = Brightness.light, double scale = 1}) => LanguageScope(
        notifier: ValueNotifier(lang),
        child: MaterialApp(
          theme: AppTheme.build(b, style: ThemeStyle.signature),
          builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: Directionality(textDirection: lang.textDirection, child: w!)),
          home: Scaffold(body: ListView(padding: const EdgeInsets.all(16), children: [child])),
        ),
      );

  FleetCommandCenter view({Stream<List<Offer>>? bids, List<String>? opened}) => FleetCommandCenter(
        vehicles: _v.values.toList(),
        bookings: [b('B1', 'a', 'in_transit')],
        members: const [],
        accounts: Stream.value(const []),
        bids: bids ?? Stream.value(_o.values.toList()),
        onOpenBooking: (id) => opened?.add('b:$id'),
        onOpenBids: () => opened?.add('bids'),
        now: () => now,
      );

  testWidgets('skeleton, then counts, alerts, the board and open bids; a running truck opens its trip', (t) async {
    t.view.physicalSize = const Size(400, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final opened = <String>[];
    await t.pumpWidget(host(view(opened: opened)));
    expect(find.byKey(const ValueKey('ccSkeleton')), findsOneWidget);
    await t.pumpAndSettle();
    expect(find.text('On trip: 1'), findsOneWidget);
    expect(find.textContaining('MH01CC3333: 1 paper(s) expired'), findsOneWidget);
    expect(find.text('Counter price waiting: Pune → Surat'), findsOneWidget);
    expect(find.byKey(const ValueKey('ccVehicle_d')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('ccVehicle_a')));
    await t.tap(find.byKey(const ValueKey('ccAllBids')));
    expect(opened, ['b:B1', 'bids']);
  });

  testWidgets('a broken list says so', (t) async {
    await t.pumpWidget(host(view(bids: Stream.error(StateError('x')))));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('ccBody')), findsNothing);
    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
  });

  for (final (lang, br) in [(AppLanguage.hindi, Brightness.light), (AppLanguage.urdu, Brightness.dark), (AppLanguage.tamil, Brightness.dark)]) {
    testWidgets('no overflow at 320 dp and 2.0x: ${lang.name} ${br.name}', (t) async {
      t.view.physicalSize = const Size(320, 4000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(host(view(), lang: lang, b: br, scale: 2));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('ccBody')), findsOneWidget);
    });
  }
}
