import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/admin/admin_violations_screen.dart';
import 'package:transport_app/core/call/call_controller.dart';
import 'package:transport_app/core/call/call_models.dart';
import 'package:transport_app/core/call/call_provider.dart';
import 'package:transport_app/core/call/call_screens.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/fleet.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/offer.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/transporter/transporter_logic.dart';
import 'package:transport_app/core/widgets/common.dart';
import 'package:transport_app/driver/assigned_trips_card.dart';
import 'package:transport_app/fleet/fleet_dashboard.dart';
import 'package:transport_app/fleet/transporter_books_screen.dart';
import 'package:transport_app/fleet/transporter_loads_screen.dart';
import 'package:transport_app/fleet/transporter_shortcuts.dart';
import 'package:transport_app/fleet/transporter_trips_screen.dart';

import 'test_utils.dart';

/// The new Task 67 / 68 screens fit a 360 x 640 phone with 1.6x text, in every
/// language (the longest strings are in Tamil, Telugu and Kannada), light and dark.
class _NoCall implements CallProvider {
  @override
  bool get supported => true;
  @override
  Future<void> init() async {}
  @override
  Future<String> createOffer() async => 'v=0';
  @override
  Future<String> acceptOffer(String offerSdp) async => 'v=0';
  @override
  Future<void> setAnswer(String answerSdp) async {}
  @override
  Future<void> addRemoteCandidate(CallCandidate c) async {}
  @override
  Stream<CallCandidate> get localCandidates => const Stream.empty();
  @override
  Stream<bool> get connected => const Stream.empty();
  @override
  Future<void> setMuted(bool muted) async {}
  @override
  Future<void> setSpeaker(bool on) async {}
  @override
  Future<void> close() async {}
}

Booking _b(String id, String status, {String? assigned, Map<String, DateTime>? timeline}) => Booking(
      id: id, loadId: 'L$id', driverId: 'tr1', vehicleId: 'v1', customerId: 'c1', status: status, pickup: 'Thiruvananthapuram', drop: 'Visakhapatnam', cargoType: 'Fast moving consumer goods', weight: 12,
      vehicleType: '20ft', budget: null, pickupDate: null, notes: '', vehicleNumber: 'MH12AB1234', driverName: 'Sharma Roadlines Pvt Ltd', driverPhone: '', timeline: timeline ?? {status: DateTime(2026, 10, 8)},
      fleetOwnerId: 'tr1', assignedDriverId: assigned, assignedDriverName: assigned == null ? '' : 'Ramasubramanian', assignedVehicleNumber: assigned == null ? '' : 'TN01AB1234', agreedFarePaise: 2400000,
    );

void main() {
  final db = FakeFirebaseFirestore();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Backend.useFakes(db: db, uid: () => 'tr1');
    await db.collection('users').doc('c1').set({'name': 'Anil', 'phone': '+919800000001', 'chatStrikes': 4, 'chatBlockedUntil': Timestamp.fromDate(DateTime.now().add(const Duration(days: 3))), 'chatReview': true});
    await db.collection('violations').doc('c1_1').set({'userId': 'c1', 'bookingId': 'B', 'kind': 'app', 'excerpt': 'whatsapp pe aao ' * 6, 'createdAt': Timestamp.now()});
  });

  final screens = <String, Future<Widget> Function()>{
    'transporter trips': () async => TransporterTripsScreen(
          bookings: Stream.value([
            _b('1', BookingStatus.inTransit, assigned: 'd1', timeline: {BookingStatus.pickedUp: DateTime(2026, 10, 1)}),
            _b('2', BookingStatus.accepted),
          ]),
          offers: Stream.value(const [
            Offer(id: 'L1_tr1', loadId: 'L1', driverId: 'tr1', customerId: 'c1', vehicleId: 'v1', vehicleNumber: 'MH12AB1234', vehicleType: '20ft', driverName: 'Sharma Roadlines', pricePaise: 2400000, originalPaise: 2400000, status: OfferStatus.selected, fleetOwnerId: 'tr1', pickup: 'Thiruvananthapuram', drop: 'Visakhapatnam'),
          ]),
          members: Stream.value(const [FleetMember(id: 'tr1_d1', ownerId: 'tr1', driverId: 'd1', driverName: 'Ramasubramanian', active: true)]),
          vehicles: () async => const [],
          now: () => DateTime(2026, 10, 20),
        ),
    'transporter books': () async => TransporterBooksScreen(accounts: Stream.value(const [
          TripAccount(bookingId: 'B1', partyId: 'c1', partyName: 'Anil Traders and Sons Private Limited', revenuePaise: 12500000, driverPayPaise: 9000000, otherCostPaise: 500000, receivedPaise: 100000),
        ])),
    'transporter loads': () async => TransporterLoadsScreen(loads: Stream.value([
          Load(id: 'l1', shipperId: 'c1', pickup: 'Thiruvananthapuram', drop: 'Visakhapatnam', cargoType: 'Fast moving consumer goods', weight: 12, vehicleType: '20ft', budget: 25000, pickupDate: DateTime(2026, 10, 9), notes: '', status: 'open', postedByRole: 'fleet'),
        ])),
    // The real composition: the shortcuts are the top of the scrolling dashboard.
    'transporter dashboard': () async {
      final vehicles = Stream.value([
        Vehicle(id: 'a', ownerId: 'tr1', number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'R', status: 'active', docs: {VehicleDocKind.insurance: VehicleDocInfo(number: 'N', expiry: DateTime(2026, 10, 1))}),
      ]).asBroadcastStream();
      return FleetDashboard(
        vehicles: vehicles,
        bookings: Stream.value([_b('1', BookingStatus.inTransit, assigned: 'd1')]),
        members: Stream.value(const []),
        openLoads: Stream.value(const []),
        now: () => DateTime(2026, 10, 8),
        header: TransporterShortcuts(profile: () async => const TransporterProfile(company: 'Co'), vehicles: vehicles, now: () => DateTime(2026, 10, 8)),
      );
    },
    'transporter dashboard without vehicles': () async => FleetDashboard(
          vehicles: Stream.value(const <Vehicle>[]),
          bookings: Stream.value(const []),
          members: Stream.value(const []),
          openLoads: Stream.value(const []),
          header: TransporterShortcuts(profile: () async => const TransporterProfile(company: 'Co'), vehicles: Stream.value(const <Vehicle>[])),
        ),
    'assigned trips card': () async => AssignedTripsCard(bookings: Stream.value([_b('1', BookingStatus.loading, assigned: 'd1')]), onOpen: (_) {}),
    'violations': () async => AdminViolationsScreen(violations: Stream.value((await db.collection('violations').get()).docs)),
    'incoming call': () async => CallScreen(
          controller: CallController(_NoCall()),
          incoming: CallDoc(id: 'x', bookingId: 'B', callerId: 'c1', calleeId: 'tr1', callerName: 'Ramasubramanian Venkataraghavan', vehicleNumber: 'TN01AB1234', status: 'ringing', offerSdp: 'sdp', createdAt: DateTime.now()),
        ),
  };

  for (final lang in [AppLanguage.english, AppLanguage.tamil, AppLanguage.telugu, AppLanguage.urdu]) {
    for (final dark in [false, true]) {
      for (final e in screens.entries) {
        testWidgets('${e.key} fits 360x640 at 1.6x text (${lang.name}, ${dark ? 'dark' : 'light'})', (tester) async {
          tester.view.physicalSize = const Size(360, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          languageNotifier.value = lang;
          addTearDown(() => languageNotifier.value = AppLanguage.english);
          AppPalette.current = dark ? AppPalette.dark : AppPalette.light;
          final child = await tester.runAsync(e.value);
          await tester.pumpWidget(LanguageScope(
            notifier: languageNotifier,
            child: MaterialApp(
              theme: AppTheme.build(Brightness.light),
              darkTheme: AppTheme.build(Brightness.dark),
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.6)), child: c!),
              home: Scaffold(body: child!),
            ),
          ));
          await settle(tester);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
