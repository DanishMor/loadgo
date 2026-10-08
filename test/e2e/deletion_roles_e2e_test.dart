import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/services/account_deletion_service.dart';
import 'package:transport_app/core/services/backend.dart';

/// MASTER-5 Tasks 6 and 47: deleting an account for every role. What the app
/// may delete goes, what must be kept (docs/DATA_RETENTION.md) stays, and
/// nothing of anyone else is touched.
void main() {
  for (final role in ['customer', 'driver', 'fleet']) {
    test('$role: own data goes, kept records stay, LR links are switched off, others untouched', () async {
      final db = FakeFirebaseFirestore();
      Backend.useFakes(db: db, uid: () => 'u1');
      SharedPreferences.setMockInitialValues({});
      await db.collection('users').doc('u1').set({'role': role, 'selectedRole': role});
      await db.collection('users').doc('u2').set({'role': 'customer'});
      await db.collection('users').doc('u1').collection('saved_places').doc('p').set({'label': 'x'});
      await db.collection('notifications').add({'userId': 'u1'});
      await db.collection('transporter_accounts').doc('B1').set({'ownerId': 'u1'});
      // kept records
      await db.collection('lrs').doc('LR1').set({'issuerId': 'u1', 'bookingId': 'B1', 'status': 'issued'});
      await db.collection('violations').doc('u1_1').set({'userId': 'u1'});
      await db.collection('calls').doc('c1').set({'callerId': 'u1', 'calleeId': 'u2'});
      await db.collection('bookings').doc('B1').set({'customerId': 'u1', 'driverId': 'u2', 'status': 'delivered'});
      // links
      await db.collection('lr_shares').doc('mine').set({'ownerId': 'u1', 'revoked': false, 'status': 'issued'});
      await db.collection('lr_shares').doc('mineOld').set({'ownerId': 'u1', 'revoked': true, 'status': 'issued'});
      await db.collection('lr_shares').doc('theirs').set({'ownerId': 'u2', 'revoked': false, 'status': 'issued'});

      var authDeleted = false;
      await AccountDeletionService.deleteAccount(deleteAuthUser: () async => authDeleted = true);

      expect(authDeleted, isTrue);
      expect((await db.collection('users').doc('u1').get()).exists, isFalse);
      expect((await db.collection('users').doc('u1').collection('saved_places').get()).docs, isEmpty);
      expect((await db.collection('notifications').get()).docs, isEmpty);
      expect((await db.collection('transporter_accounts').get()).docs, isEmpty);
      expect((await db.collection('users').doc('u2').get()).exists, isTrue);

      for (final c in ['lrs', 'violations', 'calls', 'bookings']) {
        expect((await db.collection(c).get()).docs, hasLength(1), reason: '$c is kept');
      }
      expect((await db.collection('lr_shares').doc('mine').get()).data()!['revoked'], isTrue);
      expect((await db.collection('lr_shares').doc('theirs').get()).data()!['revoked'], isFalse);
    });
  }
}
