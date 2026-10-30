// Part 5 (rules contract): runs the REAL services against fake Firestore and records exactly what
// each one writes (a before/after diff of the whole database). firestore_rules_test/contract.test.mjs
// replays every recorded write against firestore.rules on the emulator and expects it to be allowed.
//
// So when a rule gets a field whitelist or a new check, a service that sends a field the rule does
// not know fails there, not on a driver's phone. docs/RULES_CONTRACT.md lists what is covered.
//
// Regenerate the fixture:  flutter test test/rules_contract_capture_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/dispatch/dispatch_models.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/offer.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/offers/offers_switch.dart';
import 'package:transport_app/core/photos/cargo_photos.dart';
import 'package:transport_app/core/photos/photo_service.dart';
import 'package:transport_app/core/pricing/fare_calculator.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/offer_service.dart';
import 'package:transport_app/core/services/offers_switch_service.dart';
import 'package:transport_app/core/services/pricing_service.dart';
import 'package:transport_app/core/services/rewards_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/core/services/chat_service.dart';
import 'package:transport_app/core/services/payment_service.dart';
import 'package:transport_app/core/services/claim_service.dart';
import 'package:transport_app/core/services/driver_extras_service.dart' hide ClaimException;
import 'package:transport_app/core/services/safety_service.dart';
import 'package:transport_app/core/safety/trip_share_service.dart';
import 'package:transport_app/core/models/claim.dart';
import 'package:transport_app/core/services/support_service.dart';
import 'package:transport_app/core/services/rating_service.dart';
import 'package:transport_app/core/services/payout_service.dart';
import 'package:transport_app/core/services/truck_board_service.dart';
import 'package:transport_app/core/bilty/lr_service.dart';
import 'package:transport_app/core/models/support_ticket.dart';
import 'package:transport_app/core/services/trip_otp_attempts.dart';
import 'package:transport_app/core/offers/promo.dart';
import 'package:transport_app/core/constants/logistics.dart';


late FakeFirebaseFirestore db;
String? uid;

/// Everything under [db] as path -> typed JSON. Timestamps become {"$ts": ms, "$server": true when "now"}.
Future<Map<String, Map<String, Object?>>> snapshot(DateTime from, DateTime to) async {
  final tree = jsonDecode(db.dump()) as Map<String, dynamic>;
  final out = <String, Map<String, Object?>>{};
  Object? enc(Object? v) {
    if (v is Timestamp) {
      final d = v.toDate();
      final now = !d.isBefore(from.subtract(const Duration(seconds: 2))) && !d.isAfter(to.add(const Duration(seconds: 2)));
      return {r'$ts': v.millisecondsSinceEpoch, r'$server': now};
    }
    if (v is DateTime) return enc(Timestamp.fromDate(v));
    if (v is GeoPoint) return {r'$geo': [v.latitude, v.longitude]};
    if (v is Map) return {for (final e in v.entries) e.key as String: enc(e.value)};
    if (v is Iterable) return [for (final e in v) enc(e)];
    return v;
  }

  Future<void> walk(String collectionPath, Map<String, dynamic> docs) async {
    for (final id in docs.keys) {
      final path = '$collectionPath/$id';
      final snap = await db.doc(path).get();
      if (snap.exists) out[path] = (enc(snap.data()) as Map).cast<String, Object?>();
      final node = docs[id];
      if (node is Map<String, dynamic>) {
        for (final e in node.entries) {
          final v = e.value;
          if (v is Map<String, dynamic> && v.isNotEmpty && v.values.every((x) => x is Map)) {
            if ((await db.collection('$path/${e.key}').get()).docs.isNotEmpty) await walk('$path/${e.key}', v);
          }
        }
      }
    }
  }

  for (final e in tree.entries) {
    if (e.value is Map<String, dynamic>) await walk(e.key, e.value as Map<String, dynamic>);
  }
  return out;
}

final scenarios = <Map<String, Object?>>[];

/// Runs [act] as [actor] on a fresh database prepared by [setup]; stores the writes of [act].
Future<void> scenario(String name, String actor, List<String> covers, Future<void> Function() act, {Future<void> Function()? setup, List<Future<void> Function()> then = const []}) async {
  db = FakeFirebaseFirestore();
  Backend.useFakes(db: db, uid: () => uid);
  uid = actor;
  if (setup != null) await setup();
  uid = actor;
  final first = await snapshot(DateTime(2000), DateTime(2000));
  var before = first;
  final steps = <List<Map<String, Object?>>>[];
  for (final step in [act, ...then]) {
    final t0 = DateTime.now();
    await step();
    final t1 = DateTime.now();
    final after = await snapshot(t0, t1);
    // The "server" flag only says a timestamp is close to now; two reads of the same instant are the same value.
    String j(Object? o) => jsonEncode(o).replaceAll(r',"$server":true', '').replaceAll(r',"$server":false', '');
    final ops = <Map<String, Object?>>[];
    for (final e in after.entries) {
      final old = before[e.key];
      if (old == null) {
        ops.add({'op': 'create', 'path': e.key, 'data': e.value});
      } else if (j(old) != j(e.value)) {
        // A map field that changed in one key (the booking timeline) is replayed as that key only, with a dotted path, the way the app writes it.
        final changed = <String, Object?>{};
        for (final k in e.value.keys) {
          if (j(old[k]) == j(e.value[k])) continue;
          final was = old[k], after = e.value[k];
          if (was is Map && after is Map && k == 'timeline') {
            for (final sub in after.keys) {
              if (j(was[sub]) != j(after[sub])) changed['$k.$sub'] = after[sub];
            }
          } else {
            changed[k] = after;
          }
        }
        // Fake Firestore drops the other fields of a user document on set(..., merge: true) with an increment (real Firestore
        // keeps them), so for users/ a missing field is never replayed as a delete. Elsewhere a removed field is a real delete
        // (the load loses driverId, bookingId and matchedAt when a driver cancels).
        final removed = e.key.startsWith('users/') ? <String>[] : [for (final k in old.keys) if (!e.value.containsKey(k)) k];
        ops.add({'op': 'update', 'path': e.key, 'changed': changed, 'removed': removed});
      }
    }
    for (final p in before.keys) {
      if (!after.containsKey(p)) ops.add({'op': 'delete', 'path': p});
    }
    expect(ops, isNotEmpty, reason: '$name wrote nothing in one of its steps');
    steps.add(ops);
    before = after;
  }
  scenarios.add({'name': name, 'actor': actor, 'covers': covers, 'before': first, 'steps': steps});
}

Future<void> user(String id, Map<String, Object?> data) => db.collection('users').doc(id).set({'createdAt': Timestamp.now(), ...data});

Future<Vehicle> vehicleFor(String driver, String number, {String type = '14ft'}) async {
  final was = uid;
  uid = driver;
  final id = await VehicleService.add(number: number, type: type, capacity: 4, rcNumber: 'RC1');
  uid = was;
  return Vehicle.fromDoc(await db.collection('vehicles').doc(id).get());
}

Future<String> post({
  String pickup = 'Delhi',
  String drop = 'Jaipur',
  num? budget = 25000,
  FareBreakdown? estimate,
  String? distanceSource,
  List<String> extraPickups = const [],
  List<String> extraDrops = const [],
  String pickupSlot = PickupSlot.any,
  String paymentMode = 'cash',
  String containerNumber = '',
  String sealNumber = '',
  String? branchId,
  String? shipmentId,
  int? shipmentLeg,
  String bookingType = BookingType.freight,
  int helpers = 0,
  int? rentalHours,
  MoversDetails? movers,
  PromoApplication? promo,
  int creditsUsedPaise = 0,
  bool fragile = false,
  bool highValue = false,
  int? declaredValuePaise,
  DateTime? scheduledAt,
  String? invitedDriverId,
  String? businessId,
  String? costCenter,
  String visibility = LoadVisibility.public,
  List<String> allowedDriverIds = const [],
  bool instant = false,
  LoadMode mode = LoadMode.instant,
  DateTime? bidWindowEnds,
  AutoAccept? autoAccept,
}) =>
    LoadService.post(
      pickup: pickup, drop: drop, cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: budget,
      pickupDate: DateTime.now().add(const Duration(days: 2)), notes: 'Handle with care',
      estimate: estimate, distanceSource: distanceSource, extraPickups: extraPickups, extraDrops: extraDrops, pickupSlot: pickupSlot,
      paymentMode: paymentMode, containerNumber: containerNumber, sealNumber: sealNumber, branchId: branchId, shipmentId: shipmentId,
      shipmentLeg: shipmentLeg, bookingType: bookingType, helpers: helpers, rentalHours: rentalHours, movers: movers, promo: promo,
      creditsUsedPaise: creditsUsedPaise, fragile: fragile, highValue: highValue, declaredValuePaise: declaredValuePaise,
      scheduledAt: scheduledAt, invitedDriverId: invitedDriverId, businessId: businessId, costCenter: costCenter,
      visibility: visibility, allowedDriverIds: allowedDriverIds, instant: instant, mode: mode, bidWindowEnds: bidWindowEnds,
      autoAccept: autoAccept,
    );

Future<Load> loadOf(String id) async => Load.fromDoc(await db.collection('loads').doc(id).get());
Future<Offer> offerOf(String id) async => Offer.fromDoc(await db.collection('offers').doc(id).get());

void main() {
  setUpAll(() {
    OffersSwitchService.notifier.value = const OffersSwitch(promo: true, credits: true, referral: true);
  });
  tearDownAll(() {
    OffersSwitchService.reset();
    final file = File('firestore_rules_test/contract/captured.json')..createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent(' ').convert({'capturedAtMs': DateTime.now().millisecondsSinceEpoch, 'scenarios': scenarios}));
  });

  // ------------------------------------------------------------------ vehicles
  test('vehicle: add (vehicle + number reservation)', () async {
    await scenario('vehicle add', 'drv1', ['vehicles', 'vehicle_numbers'], () => vehicleFor('drv1', 'MH12AB1234'), setup: () => user('drv1', {'role': 'driver', 'driverName': 'Ramesh'}));
  });

  // ------------------------------------------------------------------ loads
  Future<void> loadCase(String name, Future<String> Function() act, {Future<void> Function()? extraSetup}) => scenario(
        name, 'cust1', ['loads', 'rate_limits'], act,
        setup: () async {
          await user('cust1', {'role': 'customer', 'name': 'Asha'});
          await extraSetup?.call();
        },
      );
  final inTwoDays = DateTime.now().add(const Duration(days: 2));

  group('loads: every variant LoadService.post can send', () {
    test('plain, no budget', () => loadCase('load plain without budget', () => post(budget: null)));
    test('plain with budget', () => loadCase('load plain with budget', () => post()));
    test('freight with an estimate', () => loadCase('load freight estimate', () => post(
          estimate: PricingService.quote(vehicleType: '14ft', distanceKm: 280), distanceSource: 'maps')));
    test('extra pickup and drop, slot, UPI', () => loadCase('load extra stops slot upi', () => post(
          extraPickups: ['Gurgaon'], extraDrops: ['Ajmer'], pickupSlot: PickupSlot.morning, paymentMode: 'upi_direct',
          estimate: PricingService.quote(vehicleType: '14ft', distanceKm: 300, extraStops: 2))));
    test('container and seal', () => loadCase('load container seal', () => post(containerNumber: 'MSCU1234567', sealNumber: 'SEAL-001')));
    test('branch, shipment, leg', () => loadCase('load branch shipment leg', () => post(branchId: 'br1', shipmentId: 'sh1', shipmentLeg: 2)));
    test('helpers', () => loadCase('load helpers', () => post(helpers: 2, estimate: PricingService.quote(vehicleType: '14ft', distanceKm: 40, helpers: 2))));
    test('rental 8 hours', () => loadCase('load rental', () => post(
          bookingType: BookingType.rental, rentalHours: 8, estimate: PricingService.quoteRental(vehicleType: '14ft', hours: 8))));
    test('movers', () {
      const m = MoversDetails(items: {'sofa': 1, 'boxes': 20}, floor: 3, hasLift: false, packingNeeded: true);
      return loadCase('load movers', () => post(
          bookingType: BookingType.movers, movers: m, estimate: PricingService.quote(vehicleType: '14ft', distanceKm: 30, movers: m)));
    });
    test('fragile, high value, declared value', () => loadCase('load fragile high value', () => post(fragile: true, highValue: true, declaredValuePaise: 5000000)));
    test('cost centre and own business', () => loadCase('load cost centre business', () => post(costCenter: 'CC-7', businessId: 'cust1')));
    test('invited driver', () => loadCase('load invited driver', () => post(invitedDriverId: 'drv1')));
    test('favourites only', () => loadCase('load favourites visibility', () => post(visibility: LoadVisibility.favourites, allowedDriverIds: ['drv1', 'drv2'])));
    test('instant flag', () => loadCase('load instant flag', () => post(instant: true)));
    test('mode instant (explicit)', () => loadCase('load mode instant', () => post(mode: LoadMode.instant, estimate: PricingService.quote(vehicleType: '14ft', distanceKm: 100))));
    test('mode bid', () => loadCase('load mode bid', () => post(mode: LoadMode.bid, estimate: PricingService.quote(vehicleType: '14ft', distanceKm: 100))));
    test('mode bid with auto-accept', () => loadCase('load mode bid auto accept', () => post(
          mode: LoadMode.bid, autoAccept: const AutoAccept(maxPaise: 2500000, minRating: 4.5, verifiedOnly: true),
          estimate: PricingService.quote(vehicleType: '14ft', distanceKm: 100))));
    test('mode scheduled', () => loadCase('load mode scheduled', () => post(
          mode: LoadMode.scheduled, scheduledAt: DateTime(inTwoDays.year, inTwoDays.month, inTwoDays.day, 10), estimate: PricingService.quote(vehicleType: '14ft', distanceKm: 100))));
    test('posted by a transporter', () => loadCase('load posted by fleet', () => post(), extraSetup: () => user('cust1', {'role': 'fleet', 'name': 'Co'})));
    Future<void> promoSetup() async {
      await db.collection('config').doc('offers').set({'promoEnabled': true, 'creditsEnabled': true, 'referralEnabled': true});
      await db.collection('promos').doc('SAVE10').set(Promo(
        code: 'SAVE10', type: Promo.percent, value: 10, maxDiscountPaise: 0, minOrderPaise: 0, expiresAt: DateTime(2030), usageLimit: 100, perUserLimit: 1, active: true).toMap());
      await db.collection('users').doc('cust1').collection('credits').doc('seed').set({'amountPaise': 20000, 'kind': 'admin_grant', 'createdAt': Timestamp.now()});
    }

    test('promo only', () => loadCase('load promo only', () async {
          final quote = PricingService.quote(vehicleType: '14ft', distanceKm: 100);
          final app = await RewardsService.reserve('SAVE10', quote.total);
          return post(estimate: quote, promo: app);
        }, extraSetup: promoSetup));
    test('credits only', () => loadCase('load credits only', () => post(estimate: PricingService.quote(vehicleType: '14ft', distanceKm: 100), creditsUsedPaise: 12000), extraSetup: promoSetup));
    test('promo and credits', () => loadCase('load promo and credits', () async {
          final quote = PricingService.quote(vehicleType: '14ft', distanceKm: 100);
          final app = await RewardsService.reserve('SAVE10', quote.total);
          return post(estimate: quote, promo: app, creditsUsedPaise: 12000);
        }, extraSetup: promoSetup));
  });

  // ------------------------------------------------------------------ offers and bookings
  Future<void> offerCase(String name, String actor, List<String> covers, Future<void> Function(Load load, Vehicle v1, Vehicle v2) act,
      {LoadMode mode = LoadMode.instant, Future<void> Function(Load load, Vehicle v1, Vehicle v2)? prepare}) async {
    late Load load;
    late Vehicle v1, v2;
    await scenario(name, actor, covers, () => act(load, v1, v2), setup: () async {
      final w = await world(mode: mode);
      load = w.load;
      v1 = w.v1;
      v2 = w.v2;
      await prepare?.call(load, v1, v2);
    });
  }

  int price(Load l) => ((l.estimate?.total ?? 2000000) * 0.9).round();

  group('offers', () {
    test('send, plain', () => offerCase('offer send', 'drv1', ['offers', 'rate_limits'], (l, v1, v2) async {
          uid = 'drv1';
          await OfferService.send(load: l, vehicle: v1, pricePaise: price(l));
        }));
    test('send with ETA, note and distance', () => offerCase('offer send eta note km', 'drv1', ['offers', 'rate_limits'], (l, v1, v2) async {
          uid = 'drv1';
          await OfferService.send(load: l, vehicle: v1, pricePaise: price(l), etaMinutes: 25, note: BidNote.onTheWay, pickupKm: 6);
        }));
    test('send on a bid-mode load', () => offerCase('offer send bid mode', 'drv1', ['offers', 'rate_limits'], (l, v1, v2) async {
          uid = 'drv1';
          await OfferService.send(load: l, vehicle: v1, pricePaise: price(l), etaMinutes: 15);
        }, mode: LoadMode.bid));
    test('send as a company', () => offerCase('offer send as company', 'drv1', ['offers', 'rate_limits'], (l, v1, v2) async {
          uid = 'drv1';
          await OfferService.send(load: l, vehicle: v1, pricePaise: price(l), asCompany: true);
        }, prepare: (l, v1, v2) async {
          await db.collection('users').doc('drv1').update({'role': 'fleet', 'companyName': 'Ramesh Roadlines', 'verified': true});
        }));

    Future<void> sent(Load l, Vehicle v1, Vehicle v2) async {
      uid = 'drv1';
      await OfferService.send(load: l, vehicle: v1, pricePaise: price(l));
    }

    test('edit once', () => offerCase('offer edit once', 'drv1', ['offers'], (l, v1, v2) async {
          uid = 'drv1';
          await OfferService.edit(await offerOf('${l.id}_drv1'), pricePaise: price(l) + 10000, etaMinutes: 20, note: BidNote.flexibleTime, pickupKm: 4);
        }, prepare: sent));
    test('withdraw', () => offerCase('offer withdraw', 'drv1', ['offers'], (l, v1, v2) async {
          uid = 'drv1';
          await OfferService.withdraw('${l.id}_drv1');
        }, prepare: sent));
    test('customer counters', () => offerCase('offer counter', 'cust1', ['offers'], (l, v1, v2) async {
          uid = 'cust1';
          await OfferService.counter('${l.id}_drv1', price(l) - 20000);
        }, prepare: sent));
    test('driver accepts the counter', () => offerCase('offer accept counter', 'drv1', ['offers'], (l, v1, v2) async {
          uid = 'drv1';
          await OfferService.acceptCounter('${l.id}_drv1');
        }, prepare: (l, v1, v2) async {
          await sent(l, v1, v2);
          uid = 'cust1';
          await OfferService.counter('${l.id}_drv1', price(l) - 20000);
        }));
    test('customer rejects', () => offerCase('offer reject', 'cust1', ['offers'], (l, v1, v2) async {
          uid = 'cust1';
          await OfferService.reject('${l.id}_drv1');
        }, prepare: sent));
    test('customer selects', () => offerCase('offer select', 'cust1', ['offers'], (l, v1, v2) async {
          uid = 'cust1';
          await OfferService.select(await offerOf('${l.id}_drv1'));
        }, prepare: sent));
    test('driver confirms a selected bid (booking + load match)', () => offerCase('offer confirm to booking', 'drv1', ['bookings', 'loads', 'vehicles', 'offers'], (l, v1, v2) async {
          uid = 'drv1';
          await OfferService.confirm(await offerOf('${l.id}_drv1'));
        }, prepare: (l, v1, v2) async {
          await sent(l, v1, v2);
          uid = 'cust1';
          await OfferService.select(await offerOf('${l.id}_drv1'));
        }));
    test('customer accepts a bid directly (acceptBid)', () => offerCase('offer acceptBid', 'cust1', ['offers'], (l, v1, v2) async {
          uid = 'cust1';
          await OfferService.acceptBid(await offerOf('${l.id}_drv1'), [await offerOf('${l.id}_drv2')]);
        }, prepare: (l, v1, v2) async {
          await sent(l, v1, v2);
          uid = 'drv2';
          await OfferService.send(load: l, vehicle: v2, pricePaise: price(l) + 50000);
        }));
  });

  moreCollections();
  batch3();

  group('bookings', () {
    test('driver accepts an instant load', () => offerCase('booking accept instant', 'drv1', ['bookings', 'loads', 'vehicles'], (l, v1, v2) async {
          uid = 'drv1';
          await BookingService.accept(loadId: l.id, vehicle: v1);
        }));
    test('driver accepts a scheduled load', () => offerCase('booking accept scheduled', 'drv1', ['bookings', 'loads', 'vehicles'], (l, v1, v2) async {
          uid = 'drv1';
          await BookingService.accept(loadId: l.id, vehicle: v1);
        }, prepare: (l, v1, v2) async {
          final at = DateTime.now().add(const Duration(days: 2));
          await db.collection('loads').doc(l.id).update({'scheduledAt': Timestamp.fromDate(DateTime(at.year, at.month, at.day, 10)), 'mode': 'scheduled'});
        }));

    // Steps of a trip. The pickup / delivery codes are in secrets/otp, as the customer's app writes them.
    Future<String> accepted(Load l, Vehicle v1) async {
      uid = 'drv1';
      final id = await BookingService.accept(loadId: l.id, vehicle: v1);
      await db.collection('bookings').doc(id).collection('secrets').doc('otp').set({'pickupOtp': '123456', 'deliveryOtp': '654321', 'createdAt': Timestamp.now()});
      return id;
    }

    for (final step in ['driver_arriving', 'loading', 'picked_up', 'in_transit', 'unloading', 'delivered']) {
      test('trip step $step', () async {
        late String id;
        late Load load;
        late Vehicle vehicle;
        final needsCode = step == 'picked_up' || step == 'delivered';
        final code = step == 'picked_up' ? '123456' : '654321';
        const pickup = PickupProof(packages: 10, weightTons: 2);
        const delivery = DeliveryProof(receiverName: 'Anil');
        // The guess is stored in one commit, the step itself in the next (as the app does).
        await scenario('trip step $step', 'drv1', ['bookings', if (needsCode) 'otp_attempts', if (step == 'delivered') 'loads'], () async {
          uid = 'drv1';
          if (needsCode) {
            await TripOtpAttempts.recordGuess(id, step == 'picked_up' ? TripOtpAttempts.pickup : TripOtpAttempts.delivery, code);
          } else {
            await BookingService.advance(id);
          }
        }, then: [
          if (needsCode)
            () async {
              uid = 'drv1';
              await BookingService.advanceAfterGuess(id, otp: code, pickup: step == 'picked_up' ? pickup : null, delivery: step == 'delivered' ? delivery : null);
            },
        ], setup: () async {
          final w = await world();
          load = w.load;
          vehicle = w.v1;
          id = await accepted(load, vehicle);
          if (step != 'driver_arriving') await advanceToWithOtps(id, step);
        });
      });
    }
  });
}


Future<({Load load, Vehicle v1, Vehicle v2})> world({LoadMode mode = LoadMode.instant, bool estimate = true}) async {
  await user('cust1', {'role': 'customer', 'name': 'Asha'});
  await user('drv1', {'role': 'driver', 'driverName': 'Ramesh'});
  await user('drv2', {'role': 'driver', 'driverName': 'Suresh'});
  uid = 'cust1';
  final id = await post(mode: mode, estimate: estimate ? PricingService.quote(vehicleType: '14ft', distanceKm: 200) : null, budget: null);
  final v1 = await vehicleFor('drv1', 'MH12AB1234');
  final v2 = await vehicleFor('drv2', 'KA01CD5678');
  return (load: await loadOf(id), v1: v1, v2: v2);
}


// ---------------------------------------------------------------------- batch 2: the other collections
void moreCollections() {
  Future<({String id, Load load, Vehicle v1})> tripOn() async {
    final w = await world();
    uid = 'drv1';
    final id = await BookingService.accept(loadId: w.load.id, vehicle: w.v1);
    await db.collection('bookings').doc(id).collection('secrets').doc('otp').set({'pickupOtp': '123456', 'deliveryOtp': '654321', 'createdAt': Timestamp.now()});
    return (id: id, load: w.load, v1: w.v1);
  }

  Future<Booking> bookingOf(String id) async => Booking.fromDoc(await db.collection('bookings').doc(id).get());

  group('chat, tickets, ratings, wallet, truck board, LR', () {
    test('chat: driver and customer send', () async {
      late String id;
      for (final who in ['drv1', 'cust1']) {
        await scenario('chat message by $who', who, ['bookings', 'messages', 'rate_limits'], () async {
          uid = who;
          await ChatService.send(await bookingOf(id), 'Main 10 minute mein pahunch raha hoon');
        }, setup: () async => id = (await tripOn()).id);
      }
    });

    test('ticket: create (with booking), reply, escalate, close', () async {
      late String id;
      await scenario('ticket create about a booking', 'cust1', ['tickets', 'rate_limits'], () async {
        uid = 'cust1';
        await SupportService.create(category: TicketCategory.dispute, subject: 'Driver late', description: 'Two hours late', bookingId: id, priority: TicketPriority.high);
      }, setup: () async => id = (await tripOn()).id);
      await scenario('ticket create plain', 'cust1', ['tickets', 'rate_limits'], () async {
        uid = 'cust1';
        await SupportService.create(category: TicketCategory.account, subject: 'Change my number');
      }, setup: () async => id = (await tripOn()).id);
      late String ticketId;
      Future<void> withTicket() async {
        await tripOn();
        uid = 'cust1';
        ticketId = await SupportService.create(category: TicketCategory.other, subject: 'Help please');
      }
      await scenario('ticket escalate', 'cust1', ['tickets'], () async {
        uid = 'cust1';
        await SupportService.escalate(SupportTicket.fromDoc(await db.collection('tickets').doc(ticketId).get()));
      }, setup: withTicket);
      await scenario('ticket close', 'cust1', ['tickets'], () async {
        uid = 'cust1';
        await SupportService.close(ticketId);
      }, setup: withTicket);
    });

    test('ratings after delivery, both sides', () async {
      late String id;
      Future<void> delivered() async {
        id = (await tripOn()).id;
        await advanceToWithOtps(id, 'zzz_end');
      }
      for (final who in ['cust1', 'drv1']) {
        await scenario('rating by $who', who, ['ratings', 'bookings'], () async {
          uid = who;
          await RatingService.rate(booking: await bookingOf(id), stars: 5, comment: 'Bahut badhiya', cats: const {});
        }, setup: delivered);
      }
      await scenario('rating low stars (flag for review)', 'cust1', ['ratings', 'rating_flags'], () async {
        uid = 'cust1';
        await RatingService.rate(booking: await bookingOf(id), stars: 1, comment: 'Late');
      }, setup: delivered);
    });

    test('payout request (wallet lines in the ledger)', () async {
      await scenario('payout request', 'drv1', ['payouts', 'payout_counters', 'audit_events'], () async {
        uid = 'drv1';
        await PayoutService.request(50000);
      }, setup: () async {
        await user('drv1', {'role': 'driver', 'driverName': 'Ramesh'});
        await db.collection('ledger').doc('b1_trip_earning').set({'driverId': 'drv1', 'bookingId': 'b1', 'type': 'trip_earning', 'amountPaise': 200000, 'createdAt': Timestamp.now()});
      });
    });

    test('empty-truck board: post, request', () async {
      late Vehicle v;
      await scenario('truck post', 'drv1', ['truck_posts'], () async {
        uid = 'drv1';
        await TruckBoardService.post(vehicle: v, fromCity: 'Delhi', toCity: 'Jaipur', date: DateTime.now().add(const Duration(days: 1)), note: 'Khali wapas');
      }, setup: () async {
        await user('drv1', {'role': 'driver', 'driverName': 'Ramesh', 'verified': true, 'verificationStatus': 'approved'});
        v = await vehicleFor('drv1', 'MH12AB1234');
      });
    });

    test('LR (bilty): issue', () async {
      late String id;
      await scenario('lr issue by the customer', 'cust1', ['lrs', 'lr_series', 'audit_events'], () async {
        uid = 'cust1';
        await LrService.issue(await bookingOf(id), const LrDraft(consignorName: 'Asha Traders', consigneeName: 'Ravi Stores', goods: 'FMCG cartons', packages: 20, weightTons: 2, freightPaise: 1500000));
      }, setup: () async => id = (await tripOn()).id);
    });
  });
}


// ---------------------------------------------------------------------- batch 3: money, safety, cancellations
void batch3() {
  Future<String> acceptedTrip() async {
    final w = await world();
    uid = 'drv1';
    final id = await BookingService.accept(loadId: w.load.id, vehicle: w.v1);
    await db.collection('bookings').doc(id).collection('secrets').doc('otp').set({'pickupOtp': '123456', 'deliveryOtp': '654321', 'createdAt': Timestamp.now()});
    return id;
  }

  Future<String> deliveredTrip() async {
    final id = await acceptedTrip();
    await advanceToWithOtps(id, 'zzz_end');
    return id;
  }

  Future<Booking> bk(String id) async => Booking.fromDoc(await db.collection('bookings').doc(id).get());

  group('payments, tips, claims, safety, cancellations', () {
    test('customer marks the trip paid', () async {
      late String id;
      await scenario('payment customer marks paid', 'cust1', ['bookings'], () async {
        uid = 'cust1';
        await PaymentService.markPaid(await bk(id), 1500000);
      }, setup: () async => id = await deliveredTrip());
    });

    test('driver confirms the money (booking + two ledger lines in one batch)', () async {
      late String id;
      await scenario('payment driver confirms with ledger lines', 'drv1', ['bookings', 'ledger'], () async {
        uid = 'drv1';
        await PaymentService.confirmReceived(await bk(id));
      }, setup: () async {
        id = await deliveredTrip();
        uid = 'cust1';
        await PaymentService.markPaid(await bk(id), 1500000);
      });
    });

    test('customer adds a tip after delivery', () async {
      late String id;
      await scenario('tip after delivery', 'cust1', ['tips'], () async {
        uid = 'cust1';
        await DriverExtrasService.addTip(await bk(id), 5000);
      }, setup: () async => id = await deliveredTrip());
    });

    test('claim opened by the customer and by the driver', () async {
      late String id;
      for (final who in ['cust1', 'drv1']) {
        await scenario('claim opened by $who', who, ['claims'], () async {
          uid = who;
          await ClaimService.open(booking: await bk(id), type: ClaimType.damage, description: 'Two cartons were wet when they arrived', amountPaise: 250000);
        }, setup: () async => id = await deliveredTrip());
      }
    });

    test('driver sends an SOS and reports a breakdown on the trip', () async {
      late String id;
      await scenario('sos by the driver', 'drv1', ['sos_alerts'], () async {
        uid = 'drv1';
        await SafetyService.sendSos(booking: await bk(id), location: const GeoPoint(28.6, 77.2));
      }, setup: () async => id = await acceptedTrip());
      await scenario('breakdown reported by the driver', 'drv1', ['bookings'], () async {
        uid = 'drv1';
        await SafetyService.reportBreakdown(await bk(id), note: 'Tyre burst', needReplacement: true);
      }, setup: () async => id = await acceptedTrip());
    });

    test('customer shares the trip link', () async {
      late String id;
      await scenario('trip share link', 'cust1', ['trip_shares'], () async {
        uid = 'cust1';
        await TripShareService.createOrReuse(await bk(id));
      }, setup: () async => id = await acceptedTrip());
    });

    test('driver cancels before pickup', () async {
      late String id;
      await scenario('driver cancels before pickup', 'drv1', ['bookings', 'loads', 'users', 'audit_events'], () async {
        uid = 'drv1';
        await BookingService.cancelByDriver(id, reason: 'vehicle_problem');
      }, setup: () async => id = await acceptedTrip());
    });

    test('customer cancels an open load', () async {
      late Load load;
      await scenario('customer cancels an open load', 'cust1', ['loads', 'users', 'audit_events'], () async {
        uid = 'cust1';
        await LoadService.cancel(load.id, reason: 'plan_changed');
      }, setup: () async => load = (await world()).load);
    });

    test('E19 goods photo by the shipper and seal photo by the driver', () async {
      PhotoService.gateway = _NoStorage();
      late Load load;
      await scenario('goods photo by the shipper', 'cust1', ['loads'], () async {
        uid = 'cust1';
        await CargoPhotoService.upload(load.id, CargoSlot.goods1, PickedPhoto(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]), 'image/jpeg'), anyway: true);
      }, setup: () async => load = (await world()).load);
      late String id;
      await scenario('seal photo by the driver', 'drv1', ['bookings'], () async {
        uid = 'drv1';
        await PhotoService.upload(PhotoTarget(PhotoKind.seal, bookingId: id), PickedPhoto(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]), 'image/jpeg'));
      }, setup: () async => id = await acceptedTrip());
      PhotoService.gateway = const FirebaseStorageGateway();
    });
  });
}

/// Moves a booking forward to the step just before [target], with the right codes.
Future<void> advanceToWithOtps(String bookingId, String target) async {
  for (var i = 0; i < BookingStatus.flow.length; i++) {
    final snap = await Backend.db.collection('bookings').doc(bookingId).get();
    final status = snap.data()?['status'] as String;
    if (status == BookingStatus.flow.last) return;
    final next = BookingStatus.flow[BookingStatus.flow.indexOf(status) + 1];
    if (next == target) return;
    await BookingService.advance(
      bookingId,
      otp: next == 'picked_up' ? '123456' : '654321',
      pickup: const PickupProof(packages: 10, weightTons: 2),
      delivery: const DeliveryProof(receiverName: 'Anil'),
    );
  }
}

/// E19 scenarios store no file; only the Firestore records are replayed.
class _NoStorage implements StorageGateway {
  @override
  Future<void> put(String path, Uint8List bytes, String contentType, {void Function(double)? onProgress}) async {}
  @override
  Future<Uint8List?> get(String path, {int maxSize = 5 * 1024 * 1024}) async => null;
  @override
  Future<void> delete(String path) async {}
}
