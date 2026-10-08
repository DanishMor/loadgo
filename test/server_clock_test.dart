import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/bilty/inspection_service.dart';
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
}
