import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/bilty/inspection_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/device_service.dart';
import 'package:transport_app/core/services/rate_limit_service.dart';
import 'package:transport_app/core/services/server_clock.dart';

/// MASTER-5 Task 20: pre-checks follow the server's time, not a wrong phone clock.
void main() {
  final server = DateTime.utc(2026, 10, 8, 12, 0, 0);
  setUp(ServerClock.reset);
  tearDown(ServerClock.reset);

  test('without a sample the phone clock is used', () {
    final phone = DateTime.utc(2026, 10, 5);
    ServerClock.deviceNow = () => phone;
    expect(ServerClock.now(), phone);
    expect(ServerClock.known, isFalse);
  });

  test('a phone set three days back is corrected from a server-stamped time', () {
    final phone = server.subtract(const Duration(days: 3));
    ServerClock.deviceNow = () => phone;
    ServerClock.observe(server);
    expect(ServerClock.now().difference(server).abs() < const Duration(seconds: 1), isTrue);
    expect(ServerClock.deviceClockOk(), isFalse);
  });

  test('a phone set ahead is corrected too, and a small delay is not an offset', () {
    ServerClock.deviceNow = () => server.add(const Duration(hours: 5));
    ServerClock.observe(server);
    expect(ServerClock.offset, const Duration(hours: -5));
    ServerClock.observe(server, receivedAt: server.add(const Duration(milliseconds: 900)));
    expect(ServerClock.offset, Duration.zero);
    expect(ServerClock.deviceClockOk(), isTrue);
  });

  test('an inspection grant is valid or over by server time even if the phone is wrong', () {
    final grantEnd = server.add(const Duration(hours: 1));
    // phone 3 days behind: by its own clock the grant would look valid for 3 days + 1 hour
    ServerClock.deviceNow = () => server.subtract(const Duration(days: 3));
    ServerClock.observe(server);
    final grant = InspectionGrant(driverId: 'd1', kind: 'approved', expiresAt: grantEnd);
    expect(grant.isValid(InspectionService.now()), isTrue);
    // two hours later on the server the grant is over, though the phone says it is still day -3
    ServerClock.deviceNow = () => server.subtract(const Duration(days: 3)).add(const Duration(hours: 2));
    expect(grant.isValid(InspectionService.now()), isFalse);
  });

  test('the device record teaches the clock at sign-in: a phone three days behind is corrected', () async {
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'u1');
    DeviceService.resetForTest();
    final id = await DeviceService.deviceId();
    await db.collection('users').doc('u1').collection('devices').doc(id).set({'label': 'android', 'trusted': true, 'revoked': false});
    final phone = DateTime.now().subtract(const Duration(days: 3));
    ServerClock.deviceNow = () => phone;
    await DeviceService.syncClock(force: true);
    expect(ServerClock.known, isTrue);
    expect(ServerClock.offset.inHours, inInclusiveRange(71, 73));
    expect(ServerClock.deviceClockOk(), isFalse);
    // it does not write again within six hours
    final before = (await db.collection('users').doc('u1').collection('devices').doc(id).get()).data()!['lastSeenAt'];
    await DeviceService.syncClock();
    expect((await db.collection('users').doc('u1').collection('devices').doc(id).get()).data()!['lastSeenAt'], before);
  });

  test('no device record yet or signed out: the phone clock stays', () async {
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => null);
    await DeviceService.syncClock(force: true);
    expect(ServerClock.known, isFalse);
    Backend.useFakes(db: db, uid: () => 'u1');
    await DeviceService.syncClock(force: true);
    expect(ServerClock.known, isFalse);
  });

  test('the hourly limit follows the server clock: a phone 3 hours ahead does not restart the window early', () async {
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'u1');
    final real = DateTime.now();
    final started = Timestamp.fromDate(real.subtract(const Duration(minutes: 40)));
    await db.collection('rate_limits').doc('u1_load').set({'count': 5, 'windowStart': started, 'last': 'x'});

    ServerClock.deviceNow = () => real.add(const Duration(hours: 3)); // the phone is wrong
    final wrong = await RateLimit.prepare(RateLimit.loadKind, docId: 'L1');
    expect(wrong.count, 1, reason: 'by the phone clock the window looks over (this is what broke posting)');

    ServerClock.observe(real, receivedAt: ServerClock.deviceNow()); // learned the real time
    final right = await RateLimit.prepare(RateLimit.loadKind, docId: 'L1');
    expect(right.count, 6);
    expect(right.windowStart, started);
  });
}
