import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/models/risk.dart';
import 'package:transport_app/core/services/admin_user_service.dart';
import 'package:transport_app/core/services/backend.dart';

/// MASTER-6 Task 12: bulk actions can be undone within the window.
void main() {
  late FakeFirebaseFirestore db;

  setUp(() async {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'admin1');
    await db.collection('users').doc('u1').set({'riskTier': 'normal', 'riskReason': ''});
    await db.collection('users').doc('u2').set({'riskTier': 'review', 'riskReason': 'checked twice'});
    await db.collection('users').doc('u3').set({'riskTier': 'banned', 'riskReason': 'fraud'});
  });

  Future<Map<String, dynamic>> user(String id) async => (await db.collection('users').doc(id).get()).data()!;

  test('hold then undo puts back each tier and the old reason, and writes an audit row per person', () async {
    final r = await AdminUserService.bulkSetTier({'u1': 'normal', 'u2': 'review', 'u3': 'banned'}, RiskTier.restricted, action: UserAction.bulkHold, reason: 'burst of ratings');
    expect((r.changed, r.skipped, r.undo.length), (2, 1, 2));
    expect((await user('u1'))['riskTier'], 'restricted');
    expect((await user('u2'))['riskReason'], 'burst of ratings');
    expect(await AdminUserService.undoBulk(r), 2);
    expect(((await user('u1'))['riskTier'], (await user('u1'))['riskReason']), ('normal', ''));
    expect(((await user('u2'))['riskTier'], (await user('u2'))['riskReason']), ('review', 'checked twice'));
    expect((await user('u3'))['riskTier'], 'banned'); // never touched
    final actions = (await db.collection('audit_events').get()).docs.map((d) => d.data()['data']['action']).toList();
    expect(actions.where((a) => a == 'bulk_undo').length, 2);
    expect(actions.where((a) => a == 'bulk_hold').length, 2);
  });

  test('someone who was changed again since is left alone', () async {
    final r = await AdminUserService.bulkSetTier({'u1': 'normal', 'u2': 'review'}, RiskTier.restricted, action: UserAction.bulkHold, reason: 'burst of ratings');
    await db.collection('users').doc('u1').update({'riskTier': 'suspended', 'riskReason': 'by support'});
    expect(await AdminUserService.undoBulk(r), 1);
    expect((await user('u1'))['riskTier'], 'suspended');
    expect((await user('u2'))['riskTier'], 'review');
  });

  test('undoing twice does nothing the second time; nothing to undo gives zero', () async {
    final r = await AdminUserService.bulkSetTier({'u1': 'normal'}, RiskTier.restricted, action: UserAction.bulkHold, reason: 'burst of ratings');
    expect(await AdminUserService.undoBulk(r), 1);
    expect(await AdminUserService.undoBulk(r), 0);
    expect(await AdminUserService.undoBulk(const BulkResult(0, 0)), 0);
  });

  test('more than 100 people are undone in several batches', () async {
    final current = <String, String>{};
    for (var i = 0; i < 230; i++) {
      await db.collection('users').doc('m$i').set({'riskTier': 'normal', 'riskReason': ''});
      current['m$i'] = 'normal';
    }
    final r = await AdminUserService.bulkSetTier(current, RiskTier.review, action: UserAction.bulkStatus, reason: 'sweep');
    expect(r.undo.length, 230);
    expect(await AdminUserService.undoBulk(r), 230);
    expect((await user('m229'))['riskTier'], 'normal');
  });

  test('the undo window is 30 seconds', () {
    expect(AdminUserService.undoWindow, const Duration(seconds: 30));
  });
}
