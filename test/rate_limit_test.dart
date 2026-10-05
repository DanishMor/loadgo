import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/chat_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/offer_service.dart';
import 'package:transport_app/core/services/rate_limit_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
  });

  Future<void> seed(String user, String kind, int count, int minutesAgo) =>
      db.collection('rate_limits').doc('${user}_$kind').set({
        'count': count,
        'windowStart': Timestamp.fromDate(DateTime.now().subtract(Duration(minutes: minutesAgo))),
        'last': 'seed',
      });

  Future<String> post() => LoadService.post(
      pickup: 'Delhi', drop: 'Mumbai', cargoType: 'FMCG', weight: 8, vehicleType: '20ft', budget: 25000, pickupDate: DateTime(2026, 10, 5), notes: '');

  test('prepare: a new window starts at 1; inside a window it counts up; the limit stops it; an old window restarts', () async {
    uid = 'u1';
    var b = await RateLimit.prepare('load', docId: 'a');
    expect((b.count, b.windowStart, b.last), (1, null, 'a'));
    await seed('u1', 'load', 7, 10);
    b = await RateLimit.prepare('load', docId: 'b');
    expect((b.count, b.windowStart != null), (8, true));
    await seed('u1', 'load', 30, 10);
    await expectLater(RateLimit.prepare('load', docId: 'c'), throwsA(isA<RateLimitException>().having((e) => e.minutesLeft, 'min', inInclusiveRange(49, 51))));
    await seed('u1', 'load', 30, 61);
    b = await RateLimit.prepare('load', docId: 'd');
    expect((b.count, b.windowStart), (1, null));
    await seed('u1', 'offer', 59, 5);
    expect((await RateLimit.prepare('offer', docId: 'x')).count, 60);
    await seed('u1', 'offer', 60, 5);
    await expectLater(RateLimit.prepare('offer', docId: 'x'), throwsA(isA<RateLimitException>()));
    await seed('u1', 'message', 119, 5);
    expect((await RateLimit.prepare('message', docId: 'x')).count, 120);
    await seed('u1', 'message', 120, 5);
    await expectLater(RateLimit.prepare('message', docId: 'x'), throwsA(isA<RateLimitException>()));
  });

  test('posting loads writes the counter with the load id; the 31st in an hour is refused', () async {
    uid = 'customer1';
    final first = await post();
    var c = (await db.collection('rate_limits').doc('customer1_load').get()).data()!;
    expect((c['count'], c['last']), (1, first));
    final second = await post();
    c = (await db.collection('rate_limits').doc('customer1_load').get()).data()!;
    expect((c['count'], c['last']), (2, second));
    await seed('customer1', 'load', 30, 20);
    await expectLater(post(), throwsA(isA<RateLimitException>()));
    expect((await db.collection('loads').get()).docs.length, 2, reason: 'nothing was written');
  });

  test('offers and chat messages are counted too', () async {
    uid = 'customer1';
    final loadId = await post();
    final load = (await LoadService.watchMine().first).single;
    uid = 'driver1';
    final vid = await VehicleService.add(number: 'MH12AB1000', type: '20ft', capacity: 10, rcNumber: 'RC1');
    final vehicle = (await VehicleService.fetchMyActive()).firstWhere((v) => v.id == vid);
    final offerId = await OfferService.send(load: load, vehicle: vehicle, pricePaise: 2000000);
    var c = (await db.collection('rate_limits').doc('driver1_offer').get()).data()!;
    expect((c['count'], c['last']), (1, offerId));

    uid = 'driver1';
    final bookingId = await BookingService.accept(loadId: loadId, vehicle: vehicle);
    final booking = Booking.fromDoc(await db.collection('bookings').doc(bookingId).get());
    await ChatService.send(booking, 'hello');
    await ChatService.send(booking, 'again');
    c = (await db.collection('rate_limits').doc('driver1_message').get()).data()!;
    expect(c['count'], 2);
    final last = (await db.collection('bookings').doc(bookingId).collection('messages').get()).docs.map((d) => d.id);
    expect(last, contains(c['last']));
    await seed('driver1', 'message', 120, 5);
    await expectLater(ChatService.send(booking, 'one too many'), throwsA(isA<RateLimitException>()));
    expect((await db.collection('bookings').doc(bookingId).collection('messages').get()).docs.length, 2);
  });
}
