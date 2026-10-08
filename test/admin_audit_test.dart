import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/services/admin_console_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/payout_service.dart';
import 'package:transport_app/core/services/rating_service.dart';
import 'package:transport_app/core/services/rewards_service.dart';

/// MASTER-5 Task 5: every admin write leaves an audit event in the same batch.
void main() {
  late FakeFirebaseFirestore db;

  setUp(() async {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'admin1');
    for (final c in ['vehicles', 'users', 'sos_alerts', 'reports', 'tickets', 'deletion_requests', 'rating_flags', 'payouts']) {
      await db.collection(c).doc('x1').set({'status': 'open', 'availability': 'available'});
    }
  });

  Future<List<Map<String, dynamic>>> audit() async => [for (final d in (await db.collection('audit_events').get()).docs) d.data()];

  final cases = <String, Future<void> Function()>{
    'vehicle availability': () => AdminConsoleService.setVehicleAvailability('x1', VehicleAvailability.suspended),
    'licence override': () => AdminConsoleService.overrideLicence('x1'),
    'sos status': () => AdminConsoleService.setSosStatus('x1', 'resolved', note: 'ok'),
    'report resolve': () => AdminConsoleService.resolveReport('x1'),
    'ticket update': () => AdminConsoleService.updateTicket('x1', status: 'closed'),
    'deletion status': () => AdminConsoleService.setDeletionStatus('x1', 'done'),
    'rating flag': () => RatingService.resolveFlag('x1', 'dismissed'),
    'payout': () => PayoutService.setStatus('x1', 'paid'),
    'credits': () => RewardsService.grantCredits('x1', 5000, note: 'sorry'),
    'referral bonus': () => RewardsService.setReferralBonus(10000),
  };

  for (final e in cases.entries) {
    test('${e.key} writes one audit event by the admin', () async {
      await e.value();
      final events = await audit();
      expect(events, hasLength(1));
      expect(events.single['actorId'], 'admin1');
      expect(events.single['type'], anyOf('user_action', 'config_change'));
    });
  }
}
