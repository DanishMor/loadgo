import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/push_service.dart';

void main() {
  test('saveToken stores one entry per device on the signed-in user', () async {
    final db = FakeFirebaseFirestore();
    String? uid = 'u1';
    Backend.useFakes(db: db, uid: () => uid);

    await PushService.saveToken('tokA');
    await PushService.saveToken('tokA');
    await PushService.saveToken('tokB');
    expect((await db.collection('users').doc('u1').get())['fcmTokens'], ['tokA', 'tokB']);

    uid = null;
    await PushService.saveToken('tokC'); // signed out: ignored
    expect((await db.collection('users').doc('u1').get())['fcmTokens'], ['tokA', 'tokB']);
  });
}
