import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/repeat.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/repeat_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/customer/my_drivers_screen.dart';
import 'package:transport_app/customer/templates_screen.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth current;
  final people = <String, MockFirebaseAuth>{};
  void signIn(String uid, String phone) =>
      current = people.putIfAbsent(uid, () => MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid, phoneNumber: phone)));

  setUp(() {
    db = FakeFirebaseFirestore();
    people.clear();
    signIn('c1', '+919800000001');
    Backend.useFakes(db: db, uid: () => current.currentUser?.uid, auth: () => current);
    languageNotifier.value = AppLanguage.english;
  });

  LoadTemplate template(String name) => LoadTemplate(
      id: '', name: name, pickup: 'Pune', drop: 'Delhi', cargoType: 'FMCG', weight: 8, vehicleType: '20ft', budget: 20000, fragile: true);

  test('templates: save, list sorted, draft has no date, limit of 20, delete', () async {
    await RepeatService.saveTemplate(template('b route'));
    await RepeatService.saveTemplate(template('A route'));
    final list = await RepeatService.watchTemplates().first;
    expect(list.map((t) => t.name), ['A route', 'b route']);
    final draft = list.first.toLoadDraft();
    expect((draft.pickup, draft.drop, draft.weight, draft.fragile, draft.pickupDate), ('Pune', 'Delhi', 8, true, null));
    expect(() => RepeatService.saveTemplate(template('  ')), throwsArgumentError);
    for (var i = 2; i < LoadTemplate.maxTemplates; i++) {
      await RepeatService.saveTemplate(template('t$i'));
    }
    await expectLater(RepeatService.saveTemplate(template('one more')), throwsA(isA<TemplateLimitException>()));
    await RepeatService.deleteTemplate(list.first.id);
    await RepeatService.saveTemplate(template('one more'));
  });

  test('favourite and block are exclusive', () async {
    await RepeatService.addFavourite(driverId: 'd1', name: 'Ramesh', vehicleNumber: 'MH12AB1234');
    expect((await RepeatService.watchFavourites().first).single.name, 'Ramesh');
    await RepeatService.blockDriver(driverId: 'd1', name: 'Ramesh');
    expect(await RepeatService.watchFavourites().first, isEmpty);
    expect(await RepeatService.blockedIds(), ['d1']);
    await RepeatService.addFavourite(driverId: 'd1');
    expect(await RepeatService.blockedIds(), isEmpty);
    await RepeatService.blockDriver(driverId: 'd1');
    await RepeatService.unblockDriver('d1');
    expect(await RepeatService.blockedIds(), isEmpty);
  });

  test('block list is capped at 50', () async {
    for (var i = 0; i < BlockedDriver.maxBlocked; i++) {
      await RepeatService.blockDriver(driverId: 'd$i');
    }
    await expectLater(RepeatService.blockDriver(driverId: 'extra'), throwsA(isA<BlockLimitException>()));
    await RepeatService.blockDriver(driverId: 'd3'); // already blocked: fine
  });

  test('a blocked driver does not see the load and cannot accept it; others can', () async {
    await db.collection('users').doc('c1').set({'role': 'customer', 'name': 'C'});
    await db.collection('users').doc('bad').set({'role': 'driver', 'driverName': 'Bad', 'phone': '+919811111111', 'verified': true});
    await db.collection('users').doc('good').set({'role': 'driver', 'driverName': 'Good', 'phone': '+919822222222', 'verified': true});
    await RepeatService.blockDriver(driverId: 'bad');
    final loadId = await LoadService.post(
      pickup: 'Pune', drop: 'Delhi', cargoType: 'FMCG', weight: 5, vehicleType: '20ft', budget: 20000,
      pickupDate: DateTime.now().add(const Duration(days: 2)), notes: '',
    );
    expect(Load.fromDoc(await db.collection('loads').doc(loadId).get()).blockedDriverIds, ['bad']);

    signIn('bad', '+919811111111');
    expect(await LoadService.watchOpen().first, isEmpty);
    final v1 = await VehicleService.add(number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC1');
    final vehicle1 = (await VehicleService.fetchMyActive()).firstWhere((x) => x.id == v1);
    await expectLater(BookingService.accept(loadId: loadId, vehicle: vehicle1), throwsA(isA<LoadUnavailableException>()));

    signIn('good', '+919822222222');
    expect((await LoadService.watchOpen().first).single.id, loadId);
    final v2 = await VehicleService.add(number: 'KA01CD5678', type: '20ft', capacity: 10, rcNumber: 'RC2');
    final vehicle2 = (await VehicleService.fetchMyActive()).firstWhere((x) => x.id == v2);
    expect(await BookingService.accept(loadId: loadId, vehicle: vehicle2), isNotEmpty);
  });

  test('book again copies route, goods and vehicle but not date or driver', () {
    final b = Booking(
      id: 'b', loadId: 'b', driverId: 'd', vehicleId: 'v', customerId: 'c1', status: 'delivered', pickup: 'Pune', drop: 'Delhi',
      cargoType: 'FMCG', weight: 5, vehicleType: '20ft', budget: 9000, pickupDate: DateTime(2026, 9, 1), notes: 'gate 2',
      vehicleNumber: 'MH12AB1', driverName: 'D', driverPhone: '1', timeline: const {}, costCenter: 'Plant 2',
    );
    final d = loadDraftFromBooking(b);
    expect((d.pickup, d.drop, d.cargoType, d.weight, d.vehicleType, d.notes, d.costCenter), ('Pune', 'Delhi', 'FMCG', 5, '20ft', 'gate 2', 'Plant 2'));
    expect((d.pickupDate, d.invitedDriverId), (null, null));
  });

  testWidgets('screens: template list and driver lists show and edit', (tester) async {
    await RepeatService.saveTemplate(template('Weekly'));
    await RepeatService.addFavourite(driverId: 'd1', name: 'Ramesh');
    await RepeatService.blockDriver(driverId: 'd2', name: 'Bad one');
    await tester.pumpWidget(const MaterialApp(home: TemplatesScreen()));
    await settle(tester);
    expect(find.text('Weekly'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: MyDriversScreen()));
    await settle(tester);
    expect(find.text('Ramesh'), findsOneWidget);
    await tester.tap(find.text('Blocked drivers').last);
    await settle(tester);
    expect(find.text('Bad one'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('unblock_d2')));
    await settle(tester);
    expect(await RepeatService.blockedIds(), isEmpty);
  });
}
