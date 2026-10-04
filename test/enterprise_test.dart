import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/ports.dart';
import 'package:transport_app/core/enterprise/bulk_loads.dart';
import 'package:transport_app/core/enterprise/route_report.dart';
import 'package:transport_app/core/enterprise/shipment_timeline.dart';
import 'package:transport_app/core/enterprise/validators.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/enterprise.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/risk.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/enterprise_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/customer/bulk_post_screen.dart';
import 'package:transport_app/customer/business_screen.dart';
import 'package:transport_app/customer/route_report_screen.dart';
import 'package:transport_app/customer/shipments_screen.dart';

import 'test_utils.dart';

const types = ['14ft', '20ft', '32ft'];

Load load(String id, String pickup, String drop, {String status = 'open', bool cancelled = false, String? branchId}) => Load(
      id: id, shipperId: 'c1', pickup: pickup, drop: drop, cargoType: 'FMCG', weight: 5, vehicleType: '20ft', budget: null,
      pickupDate: null, notes: '', status: status, cancelled: cancelled, branchId: branchId, bookingId: status == 'matched' ? 'b$id' : null);

void main() {
  group('validators', () {
    test('GSTIN format', () {
      expect(isValidGstinFormat('27AAPFU0939F1ZV'), isTrue);
      expect(isValidGstinFormat(' 27aapfu0939f1zv '), isTrue);
      expect(isValidGstinFormat('27AAPFU0939F1XV'), isFalse); // 14th char must be Z
      expect(isValidGstinFormat('27AAPFU0939F1Z'), isFalse);
      expect(isValidGstinFormat('AAAPFU0939F1ZVX'), isFalse);
      expect(isValidGstinFormat(''), isFalse);
      expect(const BusinessProfile().gstinOk, isTrue); // optional
      expect(const BusinessProfile(gstin: '123').gstinOk, isFalse);
    });

    test('ISO 6346 container numbers', () {
      expect(isValidContainerNumber('CSQU3054383'), isTrue);
      expect(isValidContainerNumber('csqu3054383'), isTrue);
      expect(isValidContainerNumber('CSQU3054384'), isFalse); // bad check digit
      expect(isValidContainerNumber('CSQ3054383'), isFalse);
      expect(isValidContainerNumber('MSKU9070322'), isTrue);
      expect(isValidContainerNumber('TEMU6079719'), isTrue);
      expect(normaliseContainer(' csqu 3054-383 '), 'CSQU3054383');
    });

    test('seal numbers', () {
      expect(isValidSealNumber('SL-9'), isTrue);
      expect(isValidSealNumber('A' * 20), isTrue);
      expect(isValidSealNumber('A' * 21), isFalse);
      expect(isValidSealNumber('bad seal!'), isFalse);
      expect(isValidSealNumber(''), isFalse);
    });

    test('ports and ICD list is searchable', () {
      expect(searchHubs('nhava').map((h) => h.code), contains('INNSA'));
      expect(searchHubs('', kind: TradeHubKind.icd).every((h) => h.kind == TradeHubKind.icd), isTrue);
      expect(searchHubs('zzz'), isEmpty);
      expect(tradeHubs.map((h) => h.code).toSet().length, tradeHubs.length);
    });
  });

  group('bulk parser', () {
    BulkParseResult parse(String t) => parseBulkLoads(t, vehicleTypeIds: types, maxTonsFor: (id) => id == '14ft' ? 4 : 20);

    test('parses valid lines (comma or tab), ignores blank lines', () {
      final r = parse('Delhi, Mumbai, FMCG, 8, 20ft, 25000\n\nPune\tNashik\tSteel\t3\t14FT');
      expect(r.ok, isTrue);
      expect(r.rows, hasLength(2));
      expect((r.rows[0].budget, r.rows[0].vehicleType), (25000, '20ft'));
      expect((r.rows[1].line, r.rows[1].vehicleType, r.rows[1].budget), (3, '14ft', null));
    });

    test('reports the bad lines with a reason', () {
      final r = parse('Delhi, Mumbai\nD, Mumbai, X, 5, 20ft\nDelhi, Mumbai, X, 0, 20ft\nDelhi, Mumbai, X, 5, rocket\nDelhi, Mumbai, X, 9, 14ft\nDelhi, Mumbai, X, 5, 20ft, abc\nDelhi, Mumbai, dynamite, 5, 20ft');
      expect(r.errors.map((e) => e.error), [
        BulkError.columns, BulkError.place, BulkError.weight, BulkError.vehicleType, BulkError.tooHeavy, BulkError.budget, BulkError.prohibited,
      ]);
      expect(r.ok, isFalse);
    });

    test('max 10 loads', () {
      final ten = List.generate(10, (i) => 'A$i city, B$i city, X, 1, 20ft').join('\n');
      expect(parse(ten).ok, isTrue);
      final eleven = '$ten\nA, B, X, 1, 20ft';
      expect(parse(eleven).tooMany, isTrue);
      expect(parse(eleven).ok, isFalse);
      expect(parse('').ok, isFalse);
    });
  });

  group('shipment timeline', () {
    test('leg stage from load and booking', () {
      expect(legStage(load('a', 'x', 'y'), null), LegStage.posted);
      expect(legStage(load('a', 'x', 'y', status: 'matched'), null), LegStage.assigned);
      expect(legStage(load('a', 'x', 'y', cancelled: true, status: 'closed'), null), LegStage.cancelled);
    });

    test('leg 2 stays pending until leg 1 is delivered', () {
      var steps = shipmentTimeline(LegStage.inTransit, LegStage.assigned);
      expect(steps.take(4).map((s) => s.state), [TimelineState.done, TimelineState.done, TimelineState.done, TimelineState.current]);
      expect(steps.skip(4).map((s) => s.state), everyElement(TimelineState.pending));

      steps = shipmentTimeline(LegStage.delivered, LegStage.assigned);
      expect(steps.take(4).map((s) => s.state), everyElement(TimelineState.done));
      expect(steps.skip(4).map((s) => s.state), [TimelineState.done, TimelineState.done, TimelineState.current, TimelineState.pending]);
      expect(shipmentComplete(LegStage.delivered, LegStage.delivered), isTrue);
      expect(shipmentComplete(LegStage.delivered, LegStage.inTransit), isFalse);

      steps = shipmentTimeline(LegStage.assigned, LegStage.cancelled);
      expect(steps.length, 8);
      steps = shipmentTimeline(LegStage.cancelled, LegStage.posted);
      expect(steps[1].state, TimelineState.cancelled);
    });
  });

  test('route report groups by normalised route and branch; CSV escapes', () async {
    final fake = FakeFirebaseFirestore();
    Future<Booking> booking(String loadId, String status, int fare) async {
      await fake.collection('bookings').doc(loadId).set({'loadId': loadId, 'status': status, 'agreedFarePaise': fare});
      return Booking.fromDoc(await fake.collection('bookings').doc(loadId).get());
    }

    final loads = [
      load('1', 'Delhi', 'Mumbai', branchId: 'b1'),
      load('2', 'New Delhi', 'Bombay', branchId: 'b1'),
      load('3', 'Pune', 'Delhi, India'),
    ];
    final r = RouteReport.from(
      loads,
      [await booking('1', 'delivered', 100000), await booking('2', 'in_transit', 5000)],
      [const Branch(id: 'b1', type: 'warehouse', name: 'Main, WH', address: '', city: '')],
    );
    expect(r.routes.first.route, 'Delhi → Mumbai');
    expect((r.routes.first.loads, r.routes.first.delivered, r.routes.first.spendPaise), (2, 1, 100000));
    expect(r.branches.single.branch, 'Main, WH');
    expect(r.branches.single.loads, 2);
    expect(r.totalSpendPaise, 100000);
    final csv = r.toCsv();
    expect(csv, contains('Delhi → Mumbai,2,1,1000.00'));
    expect(csv, contains('"Main, WH",2,1,1000.00'));
  });

  group('services and screens', () {
    late FakeFirebaseFirestore db;
    setUp(() {
      db = FakeFirebaseFirestore();
      Backend.useFakes(db: db, uid: () => 'c1');
    });

    test('business profile: normalises GSTIN, refuses a bad one', () async {
      await EnterpriseService.saveBusiness(const BusinessProfile(legalName: ' Acme ', gstin: '27aapfu0939f1zv', address: 'Pune'));
      final b = await EnterpriseService.loadBusiness();
      expect((b.legalName, b.gstin), ('Acme', '27AAPFU0939F1ZV'));
      expect(EnterpriseService.saveBusiness(const BusinessProfile(gstin: 'nope')), throwsA(isA<InvalidTradeFieldException>()));
    });

    test('branches: add, list, remove, cap at 20', () async {
      for (var i = 0; i < Branch.maxBranches; i++) {
        expect(await EnterpriseService.addBranch(type: 'factory', name: 'F$i'), isTrue);
      }
      expect(await EnterpriseService.addBranch(type: 'port', name: 'extra'), isFalse);
      final list = await EnterpriseService.watchBranches().first;
      expect(list, hasLength(20));
      await EnterpriseService.removeBranch(list.first.id);
      expect(await EnterpriseService.watchBranches().first, hasLength(19));
      expect(EnterpriseService.addBranch(type: 'moon', name: 'x'), throwsArgumentError);
    });

    test('bulk post creates one open load per row; restricted accounts are refused', () async {
      final rows = parseBulkLoads('Delhi, Mumbai, FMCG, 8, 20ft, 25000\nPune, Nashik, Steel, 3, 14ft', vehicleTypeIds: types).rows;
      final ids = await EnterpriseService.postBulk(rows, pickupDate: DateTime(2026, 10, 9));
      expect(ids, hasLength(2));
      final snap = await db.collection('loads').get();
      expect(snap.docs.map((d) => d['pickup']), unorderedEquals(['Delhi', 'Pune']));

      await db.collection('users').doc('c1').set({'riskTier': RiskTier.restricted});
      await expectLater(
          EnterpriseService.postBulk(rows, pickupDate: DateTime(2026, 10, 9)),
          throwsA(isA<BulkPostException>().having((e) => e.cause, 'cause', isA<AccountRestrictedException>())));
      expect((await db.collection('loads').get()).docs, hasLength(2));
    });

    test('two-leg shipment posts both legs, links them and tracks progress', () async {
      expect(
          EnterpriseService.createTwoLeg(
              kind: 'export', origin: 'Pune', hub: 'JNPT (Nhava Sheva), Navi Mumbai', destination: 'Mumbai', cargoType: 'General',
              weight: 8, vehicleType: '20ft', leg1Date: DateTime(2026, 10, 9), leg2Date: DateTime(2026, 10, 11), containerNumber: 'CSQU3054384'),
          throwsA(isA<InvalidTradeFieldException>()));
      final id = await EnterpriseService.createTwoLeg(
          kind: 'export', origin: 'Pune', hub: 'JNPT (Nhava Sheva), Navi Mumbai', destination: 'Mumbai', cargoType: 'General',
          weight: 8, vehicleType: '20ft', leg1Date: DateTime(2026, 10, 9), leg2Date: DateTime(2026, 10, 11),
          containerNumber: 'csqu3054383', sealNumber: 'SL-1');
      final s = Shipment.fromDoc(await db.collection('shipments').doc(id).get());
      expect((s.containerNumber, s.sealNumber, s.kind), ('CSQU3054383', 'SL-1', 'export'));
      final l1 = Load.fromDoc(await db.collection('loads').doc(s.leg1LoadId).get());
      final l2 = Load.fromDoc(await db.collection('loads').doc(s.leg2LoadId).get());
      expect((l1.pickup, l1.drop, l1.shipmentLeg, l1.shipmentId), ('Pune', s.hub, 1, id));
      expect((l2.pickup, l2.drop, l2.shipmentLeg, l2.containerNumber), (s.hub, 'Mumbai', 2, 'CSQU3054383'));

      var legs = await EnterpriseService.legsOf(s);
      expect((legs.stage1, legs.stage2, legs.complete), (LegStage.posted, LegStage.posted, false));

      // A driver takes leg 1: the booking carries container and seal numbers.
      Backend.useFakes(db: db, uid: () => 'd1');
      await VehicleService.add(number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC1');
      final vehicle = (await VehicleService.fetchMyActive()).first;
      final bookingId = await BookingService.accept(loadId: l1.id, vehicle: vehicle);
      final booking = Booking.fromDoc(await db.collection('bookings').doc(bookingId).get());
      expect((booking.containerNumber, booking.sealNumber), ('CSQU3054383', 'SL-1'));
      Backend.useFakes(db: db, uid: () => 'c1');
      legs = await EnterpriseService.legsOf(s);
      expect(legs.stage1, LegStage.assigned);
      Backend.useFakes(db: db, uid: () => 'd1');
      await advanceTo(bookingId, 'delivered');
      Backend.useFakes(db: db, uid: () => 'c1');
      legs = await EnterpriseService.legsOf(s);
      expect((legs.stage1, legs.stage2), (LegStage.delivered, LegStage.posted));
      expect(legs.timeline.where((t) => t.state == TimelineState.done).length, 5);
    });

    testWidgets('business screen: invalid GSTIN is refused, branch is added', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: BusinessScreen()));
      await settle(tester);
      expect(find.text('Not verified'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('bizGstin')), '123');
      await tester.tap(find.byKey(const ValueKey('bizSave')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid 15-character GSTIN'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('bizGstin')), '27AAPFU0939F1ZV');
      await tester.enterText(find.byKey(const ValueKey('bizName')), 'Acme Ltd');
      await tester.tap(find.byKey(const ValueKey('bizSave')));
      await settle(tester);
      expect((await db.collection('users').doc('c1').get())['business']['gstin'], '27AAPFU0939F1ZV');

      await tester.tap(find.byKey(const ValueKey('addBranch')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('branchName')), 'Bhiwandi WH');
      await tester.tap(find.byKey(const ValueKey('branchSave')));
      await settle(tester);
      expect(find.text('Bhiwandi WH'), findsOneWidget);
    });

    testWidgets('bulk post screen: shows line errors, posts when valid', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: BulkPostScreen()));
      await tester.enterText(find.byKey(const ValueKey('bulkText')), 'Delhi, Mumbai, FMCG, 8, rocket');
      await tester.pump();
      expect(find.byKey(const ValueKey('bulkError_1')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('bulkSubmit'))).onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('bulkText')), 'Delhi, Mumbai, FMCG, 8, 20ft\nPune, Nashik, Steel, 3, 14ft');
      await tester.pump();
      expect(find.text('2 loads ready to post'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bulkSubmit')));
      await settle(tester);
      expect((await db.collection('loads').get()).docs, hasLength(2));
    });

    testWidgets('route report screen lists routes', (tester) async {
      await db.collection('loads').add({'shipperId': 'c1', 'pickup': 'Delhi', 'drop': 'Mumbai', 'status': 'open'});
      await tester.pumpWidget(const MaterialApp(home: RouteReportScreen()));
      await settle(tester);
      expect(find.byKey(const ValueKey('routeRow_Delhi → Mumbai')), findsOneWidget);
      expect(find.byKey(const ValueKey('copyCsv')), findsOneWidget);
    });

    testWidgets('new shipment form validates the container and creates the shipment', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: NewShipmentScreen()));
      await tester.enterText(find.byKey(const ValueKey('shipOrigin')), 'Pune');
      await tester.enterText(find.byKey(const ValueKey('shipHub')), 'Mundra Port, Mundra');
      await tester.enterText(find.byKey(const ValueKey('shipDestination')), 'Ahmedabad');
      await tester.enterText(find.byKey(const ValueKey('shipWeight')), '8');
      await tester.enterText(find.byKey(const ValueKey('shipContainer')), 'CSQU3054384');
      await tester.ensureVisible(find.byKey(const ValueKey('shipSubmit')));
      await tester.tap(find.byKey(const ValueKey('shipSubmit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Invalid container number'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('shipContainer')), 'CSQU3054383');
      await tester.tap(find.byKey(const ValueKey('shipSubmit')));
      await settle(tester);
      expect((await db.collection('shipments').get()).docs, hasLength(1));
      expect((await db.collection('loads').get()).docs, hasLength(2));
    });

    testWidgets('shipment detail shows the 8-step timeline', (tester) async {
      final id = await EnterpriseService.createTwoLeg(
          kind: 'import', origin: 'Mundra Port, Mundra', hub: 'ICD Tughlakabad, Delhi', destination: 'Jaipur', cargoType: 'General',
          weight: 5, vehicleType: '20ft', leg1Date: DateTime(2026, 10, 9), leg2Date: DateTime(2026, 10, 11));
      final s = Shipment.fromDoc(await db.collection('shipments').doc(id).get());
      await tester.pumpWidget(MaterialApp(home: ShipmentDetailScreen(shipment: s)));
      await settle(tester);
      expect(find.byKey(const ValueKey('step_1_posted')), findsOneWidget);
      expect(find.byKey(const ValueKey('step_2_delivered')), findsOneWidget);
      expect(find.text('Load posted'), findsNWidgets(2));
    });
  });
}
