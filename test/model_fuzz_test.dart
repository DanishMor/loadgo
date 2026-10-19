import 'dart:collection';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/services/safe_docs.dart';
import 'package:transport_app/core/announcement/announcement.dart';
import 'package:transport_app/core/app_control/app_control.dart';
import 'package:transport_app/core/bilty/inspection_service.dart';
import 'package:transport_app/core/bilty/lr_model.dart';
import 'package:transport_app/core/bilty/lr_service.dart';
import 'package:transport_app/core/call/call_models.dart';
import 'package:transport_app/core/dispatch/dispatch_models.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/khata/khata_models.dart';
import 'package:transport_app/core/location/live_location_policy.dart';
import 'package:transport_app/core/models/app_notification.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/business.dart';
import 'package:transport_app/core/models/business_ops.dart';
import 'package:transport_app/core/models/chat_message.dart';
import 'package:transport_app/core/models/claim.dart';
import 'package:transport_app/core/models/driver_extras.dart';
import 'package:transport_app/core/models/driver_network.dart';
import 'package:transport_app/core/models/enterprise.dart';
import 'package:transport_app/core/models/fleet.dart';
import 'package:transport_app/core/models/fraud_case.dart';
import 'package:transport_app/core/models/handover.dart';
import 'package:transport_app/core/models/invoice.dart';
import 'package:transport_app/core/models/ledger_entry.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/load_filter.dart';
import 'package:transport_app/core/models/offer.dart';
import 'package:transport_app/core/models/payout.dart';
import 'package:transport_app/core/models/rating.dart';
import 'package:transport_app/core/models/recurring.dart';
import 'package:transport_app/core/models/repeat.dart';
import 'package:transport_app/core/models/saved_place.dart';
import 'package:transport_app/core/models/saved_search.dart';
import 'package:transport_app/core/models/support_ticket.dart';
import 'package:transport_app/core/models/trip_evidence.dart';
import 'package:transport_app/core/models/truck_board.dart';
import 'package:transport_app/core/models/user_settings.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/models/vehicle_expense.dart';
import 'package:transport_app/core/models/vehicle_type.dart';
import 'package:transport_app/core/offers/offers_switch.dart';
import 'package:transport_app/core/offers/promo.dart';
import 'package:transport_app/core/pricing/fare_calculator.dart';
import 'package:transport_app/core/pricing/pricing_config.dart';
import 'package:transport_app/core/pricing/route_rates.dart';
import 'package:transport_app/core/pricing/surge.dart';
import 'package:transport_app/core/risk/risk_config.dart';
import 'package:transport_app/core/scheduling/schedule.dart';
import 'package:transport_app/core/services/admin_service.dart';
import 'package:transport_app/core/services/device_service.dart';
import 'package:transport_app/core/services/error_log_service.dart';
import 'package:transport_app/core/services/feedback_service.dart';
import 'package:transport_app/core/services/safety_service.dart';
import 'package:transport_app/core/services/strike_appeal_service.dart';
import 'package:transport_app/core/services/support_config.dart';
import 'package:transport_app/core/transporter/transporter_logic.dart';
import 'package:transport_app/core/trust/public_trust.dart';

/// Part 5 (H17): defensive parsing. A document in Firestore can be old, half written, edited by hand in the console or
/// written by a modified app. Reading one must never crash a screen. Every model is read from a "chaos map": whatever
/// key it asks for, it gets a hostile value of the kind under test (null, wrong type, NaN, huge, negative, a list where
/// a text is expected, a map of the same kind inside...). A model may return its defaults, but it may not throw.
class ChaosMap extends MapBase<String, dynamic> {
  final Object? value;
  final int depth;

  ChaosMap(this.value, [this.depth = 0]);

  @override
  dynamic operator [](Object? key) => value is _Nested ? ChaosMap((value as _Nested).inner, depth + 1) : value;

  @override
  bool containsKey(Object? key) => true;

  @override
  Iterable<String> get keys => const [];

  @override
  void operator []=(String key, dynamic v) {}

  @override
  void clear() {}

  @override
  dynamic remove(Object? key) => null;
}

class _Nested {
  final Object? inner;

  const _Nested(this.inner);
}

// ignore: subtype_of_sealed_class (a test fake: the models only read id, exists and data())
/// A document snapshot that answers with a chaos map.
class ChaosSnap implements DocumentSnapshot<Map<String, dynamic>> {
  final Object? value;

  ChaosSnap(this.value);

  @override
  String get id => 'doc1';

  @override
  bool get exists => true;

  @override
  Map<String, dynamic>? data() => ChaosMap(value);

  @override
  dynamic get(Object field) => value;

  @override
  dynamic operator [](Object field) => value;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final _hostile = <String, Object?>{
  'null': null,
  'empty text': '',
  'text': 'abc',
  'long text': 'x' * 20000,
  'negative': -1,
  'zero': 0,
  'huge int': 1 << 62,
  'fraction': 1.5,
  'NaN': double.nan,
  'infinity': double.infinity,
  'true': true,
  'false': false,
  'empty list': <Object?>[],
  'list of junk': <Object?>[1, 'a', null, <Object?>[], {'x': 1}],
  'big list': List<Object?>.generate(20000, (i) => i),
  'empty map': <String, Object?>{},
  'map': <String, Object?>{'x': 1, 'y': 'z'},
  'timestamp': Timestamp.fromMillisecondsSinceEpoch(0),
  'future timestamp': Timestamp.fromMillisecondsSinceEpoch(4102444800000),
  'geopoint': const GeoPoint(0, 0),
  'chaos inside': const _Nested(null),
  'chaos inside text': const _Nested('abc'),
  'chaos inside number': const _Nested(-7),
  'chaos inside list': const _Nested(<Object?>[1, 2]),
};

typedef _Make = Object? Function(Map<String, dynamic> d);
typedef _MakeDoc = Object? Function(String id, Map<String, dynamic> d);
typedef _MakeSnap = Object? Function(DocumentSnapshot<Map<String, dynamic>> s);

void main() {
  // (name, reader). Each reader receives a chaos map and must not throw.
  final byMap = <String, _Make>{
    'AppControl.fromMap': AppControl.fromMap,
    'Announcement.fromMap': Announcement.fromMap,
    'DispatchConfig.fromMap': DispatchConfig.fromMap,
    'AutoAccept.fromMap': AutoAccept.fromMap,
    'Features.fromMap': Features.fromMap,
    'LiveLocationConfig.fromMap': LiveLocationConfig.fromMap,
    'LrDetails.fromMap': LrDetails.fromMap,
    'LrCompliance.fromMap': LrCompliance.fromMap,
    'BookingBreakdown.fromMap': BookingBreakdown.fromMap,
    'PickupProof.fromMap': PickupProof.fromMap,
    'DeliveryProof.fromMap': DeliveryProof.fromMap,
    'BookingCancellation.fromMap': BookingCancellation.fromMap,
    'Detention.fromMap': Detention.fromMap,
    'BusinessProfile.fromMap': BusinessProfile.fromMap,
    'LoadFilter.fromMap': LoadFilter.fromMap,
    'TruckFilter.fromMap': TruckFilter.fromMap,
    'NotificationPrefs.fromMap': NotificationPrefs.fromMap,
    'Consents.fromMap': Consents.fromMap,
    'VehicleDocInfo.fromMap': VehicleDocInfo.fromMap,
    'VehicleProfile.fromMap': VehicleProfile.fromMap,
    'VehicleTypeInfo.fromMap': VehicleTypeInfo.fromMap,
    'OffersSwitch.fromMap': OffersSwitch.fromMap,
    'PricingConfig.fromMap': PricingConfig.fromMap,
    'MoversDetails.fromMap': MoversDetails.fromMap,
    'CancellationPolicy.fromMap': CancellationPolicy.fromMap,
    'FareBreakdown.fromMap': FareBreakdown.fromMap,
    'RouteRates.rangeFromDoc': RouteRates.fromDoc,
    'SurgeRule.fromMap': SurgeRule.fromMap,
    'RiskConfig.fromMap': RiskConfig.fromMap,
    'ScheduleRules.fromMap': (d) => ScheduleRules.fromMap(d),
    'EmergencyContact.fromMap': EmergencyContact.fromMap,
    'SupportConfig.fromMap': SupportConfig.fromMap,
    'Booking.fromMap': (d) => Booking.fromMap('b1', d),
  };

  final byDoc = <String, _MakeDoc>{
    'InspectionGrant.fromDoc': InspectionGrant.fromDoc,
    'InspectionLogEntry.fromMap': InspectionLogEntry.fromMap,
    'InspectionRequest.fromDoc': InspectionRequest.fromDoc,
    'LrPublic.fromDoc': LrPublic.fromDoc,
    'LrShare.fromDoc': LrShare.fromDoc,
    'CallDoc.fromMap': CallDoc.fromMap,
    'KhataParty.fromDoc': KhataParty.fromDoc,
    'KhataEntry.fromDoc': KhataEntry.fromDoc,
    'BusinessInvite.fromDoc': BusinessInvite.fromDoc,
    'BusinessMember.fromDoc': BusinessMember.fromDoc,
    'BizExpense.fromDoc': BizExpense.fromDoc,
    'ContractVehicle.fromDoc': ContractVehicle.fromDoc,
    'Claim.fromDoc': Claim.fromDoc,
    'ClaimEvent.fromDoc': ClaimEvent.fromDoc,
    'Tip.fromDoc': Tip.fromDoc,
    'Incentive.fromDoc': Incentive.fromDoc,
    'IncentiveClaim.fromDoc': IncentiveClaim.fromDoc,
    'FleetInvite.fromDoc': FleetInvite.fromDoc,
    'FleetMember.fromDoc': FleetMember.fromDoc,
    'FraudCase.fromDoc': FraudCase.fromDoc,
    'CaseNote.fromDoc': CaseNote.fromDoc,
    'TripInvoice.fromDoc': TripInvoice.fromDoc,
    'Payout.fromDoc': Payout.fromDoc,
    'RatingFlag.fromDoc': RatingFlag.fromDoc,
    'RecurringLoad.fromDoc': RecurringLoad.fromDoc,
    'LoadTemplate.fromDoc': LoadTemplate.fromDoc,
    'FavouriteDriver.fromDoc': FavouriteDriver.fromDoc,
    'BlockedDriver.fromDoc': BlockedDriver.fromDoc,
    'SavedSearch.fromDoc': SavedSearch.fromDoc,
    'CargoDoc.fromDoc': CargoDoc.fromDoc,
    'TruckPost.fromDoc': TruckPost.fromDoc,
    'TruckRequest.fromDoc': TruckRequest.fromDoc,
    'VehicleExpense.fromDoc': VehicleExpense.fromDoc,
    'Promo.fromMap': Promo.fromMap,
    'CreditLine.fromDoc': CreditLine.fromDoc,
    'UserDevice.fromDoc': UserDevice.fromDoc,
    'AppError.fromDoc': AppError.fromDoc,
    'FeedbackEntry.fromDoc': FeedbackEntry.fromDoc,
    'StrikeAppeal.fromDoc': StrikeAppeal.fromDoc,
    'TripAccount.fromMap': TripAccount.fromMap,
    'PublicTrust.fromMap': PublicTrust.fromMap,
  };

  final bySnap = <String, _MakeSnap>{
    'AppNotification.fromDoc': AppNotification.fromDoc,
    'Booking.fromDoc': Booking.fromDoc,
    'ChatMessage.fromDoc': ChatMessage.fromDoc,
    'DriverLink.fromDoc': DriverLink.fromDoc,
    'DriverGroup.fromDoc': DriverGroup.fromDoc,
    'NetworkMessage.fromDoc': NetworkMessage.fromDoc,
    'Branch.fromDoc': Branch.fromDoc,
    'Shipment.fromDoc': Shipment.fromDoc,
    'Handover.fromDoc': Handover.fromDoc,
    'LedgerEntry.fromDoc': LedgerEntry.fromDoc,
    'Load.fromDoc': Load.fromDoc,
    'Offer.fromDoc': Offer.fromDoc,
    'Rating.fromDoc': Rating.fromDoc,
    'SavedPlace.fromDoc': SavedPlace.fromDoc,
    'SupportTicket.fromDoc': SupportTicket.fromDoc,
    'TicketReply.fromDoc': TicketReply.fromDoc,
    'Vehicle.fromDoc': Vehicle.fromDoc,
    'DriverVerification.fromDoc': DriverVerification.fromDoc,
  };

  // Which models throw on at least one hostile kind of value. Most read a field with `as String?`, which throws when an old or
  // hand-edited document holds another type. The list screens are protected by SafeDocs.parse (one bad document is skipped, the
  // rest is shown); this test is a ratchet on top: a model may leave the list when it is made defensive, and no new one may join.
  Map<String, List<String>> failures() {
    final out = <String, List<String>>{};
    void run(String name, void Function(Object? v) read) {
      final bad = <String>[];
      for (final h in _hostile.entries) {
        try {
          read(h.value);
        } catch (_) {
          bad.add(h.key);
        }
      }
      if (bad.isNotEmpty) out[name] = bad;
    }

    byMap.forEach((n, f) => run(n, (v) => f(ChaosMap(v))));
    byDoc.forEach((n, f) => run(n, (v) => f('id1', ChaosMap(v))));
    bySnap.forEach((n, f) => run(n, (v) => f(ChaosSnap(v))));
    return out;
  }

  test('no new model joins the list of those that throw on hostile data; none stays on it once fixed', () {
    final file = File('test/model_fuzz_known.txt');
    final now = failures().keys.toList()..sort();
    if (Platform.environment['UPDATE_FUZZ_BASELINE'] == '1') {
      file.writeAsStringSync('${now.join('\n')}\n');
      return;
    }
    final known = file.existsSync() ? file.readAsLinesSync().where((l) => l.trim().isNotEmpty).toList() : <String>[];
    final joined = now.where((n) => !known.contains(n)).toList();
    final fixed = known.where((n) => !now.contains(n)).toList();
    expect(joined, isEmpty, reason: 'these models now throw on hostile data: make them defensive');
    expect(fixed, isEmpty, reason: 'these models are fixed: remove them from test/model_fuzz_known.txt');
  });

  test('empty (old) documents of every model read without throwing', () {
    for (final e in byDoc.entries) {
      expect(() => e.value('id1', <String, dynamic>{}), returnsNormally, reason: e.key);
    }
    for (final e in byMap.entries) {
      expect(() => e.value(<String, dynamic>{}), returnsNormally, reason: e.key);
    }
  });

  test('one damaged document is skipped and the rest of the list is shown', () async {
    final db = FakeFirebaseFirestore();
    final col = db.collection('loads');
    await col.doc('good1').set({'shipperId': 'c1', 'pickup': 'Delhi', 'drop': 'Jaipur', 'weight': 2, 'status': 'open', 'cargoType': 'FMCG', 'vehicleType': '14ft', 'notes': ''});
    await col.doc('bad1').set({'shipperId': 5, 'pickup': ['x'], 'weight': 'heavy', 'status': {'a': 1}});
    await col.doc('good2').set({'shipperId': 'c2', 'pickup': 'Pune', 'drop': 'Goa', 'weight': 1, 'status': 'open', 'cargoType': 'FMCG', 'vehicleType': '14ft', 'notes': ''});
    final before = SafeDocsStats.skipped;
    final list = (await col.get()).docs.parse(Load.fromDoc);
    expect(list.map((l) => l.id).toSet(), {'good1', 'good2'});
    expect(SafeDocsStats.skipped, before + 1);
  });

  test('no list in lib/ is still built with docs.map(X.fromDoc).toList() (it would crash on one damaged document)', () {
    final offenders = <String>[];
    final pattern = RegExp(r'\.docs\.map\(\w+\.\w+\)\.toList\(\)');
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      if (pattern.hasMatch(f.readAsStringSync())) offenders.add(f.path);
    }
    expect(offenders, isEmpty);
  });
}
