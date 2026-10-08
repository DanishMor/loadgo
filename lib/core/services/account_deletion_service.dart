import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';
import '../identity/identity_index.dart';
import 'backend.dart';
import 'session_watcher.dart';

/// The account still has trips in progress.
class ActiveTripsException implements Exception {
  final int count;
  const ActiveTripsException(this.count);

  @override
  String toString() => 'ActiveTripsException($count)';
}

/// Suspended, banned or restricted accounts are deleted by support, so a
/// ban cannot be dodged by deleting the account and registering again.
class AccountRestrictedException implements Exception {
  const AccountRestrictedException();
}

/// Deletes the signed-in user's own data from the app (no Cloud Functions):
/// private sub-collections, notifications, open loads, vehicles and their
/// number reservations, then - in the last batch - the profile together with
/// the `identity_index` entries it owns (the rules allow that delete only
/// when the profile goes in the same batch), and finally the Auth user.
///
/// Kept on purpose (8 years, docs/DATA_RETENTION.md): bookings, invoices,
/// ledger, ratings, chats, LRs (tax records; their share links are revoked).
/// Cannot be removed from the app, rules forbid it:
/// `users/{uid}/credits`, `admin_notes`, truck posts and requests, offers, the
/// deletion request. TODO(functions): scrub those and the personal fields on
/// kept records with the Admin SDK.
class AccountDeletionService {
  AccountDeletionService._();

  /// Private lists under users/{uid} that the owner may delete.
  static const subcollections = [
    'blocked', 'saved_places', 'saved_searches', 'load_templates', 'favourite_drivers',
    'blocked_drivers', 'branches', 'favourite_routes', 'devices',
  ];

  static const _restricted = ['restricted', 'suspended', 'banned'];

  /// Bookings of this user (as customer or driver) that are not finished.
  static Future<int> activeTripCount() async {
    final uid = Backend.requireUid();
    final ids = <String>{};
    // A transporter's company trips and the trips a driver was assigned count too.
    for (final field in ['customerId', 'driverId', 'assignedDriverId', 'fleetOwnerId']) {
      final snap = await Backend.db.collection('bookings').where(field, isEqualTo: uid).get();
      for (final d in snap.docs) {
        final s = d.data()['status'];
        if (s != BookingStatus.delivered && s != BookingStatus.cancelled) ids.add(d.id);
      }
    }
    return ids.length;
  }

  static Future<bool> isRestricted() async {
    final d = (await Backend.db.collection('users').doc(Backend.requireUid()).get()).data();
    return _restricted.contains(d?['riskTier']);
  }

  /// Throws [ActiveTripsException] / [AccountRestrictedException] when the
  /// account cannot be deleted yet.
  static Future<void> assertCanDelete() async {
    if (await isRestricted()) throw const AccountRestrictedException();
    final n = await activeTripCount();
    if (n > 0) throw ActiveTripsException(n);
  }

  /// Deletes everything described above. [deleteAuthUser] removes the Auth
  /// user (the screen re-authenticates first; it must not be skipped).
  static Future<void> deleteAccount({required Future<void> Function() deleteAuthUser}) async {
    await assertCanDelete();
    final db = Backend.db;
    final uid = Backend.requireUid();
    final userRef = db.collection('users').doc(uid);
    final profile = (await userRef.get()).data() ?? const <String, dynamic>{};

    final refs = <DocumentReference<Map<String, dynamic>>>[];

    // Vehicles first, each next to its number reservation: the rules free a
    // number only in the batch that deletes (or renumbers) its vehicle.
    final vehicles = await db.collection('vehicles').where('ownerId', isEqualTo: uid).get();
    for (final v in vehicles.docs) {
      refs.add(v.reference);
      final number = v.data()['number'];
      if (number is String && number.isNotEmpty) refs.add(db.collection('vehicle_numbers').doc(number));
    }

    // Driver network: stop sharing, end connections, delete own groups and
    // leave the others. Messages stay under their parents (rules forbid
    // deleting them); TODO(functions): scrub them.
    refs.add(db.collection('driver_presence').doc(uid));
    refs.addAll((await db.collection('driver_links').where('members', arrayContains: uid).get()).docs.map((d) => d.reference));
    for (final g in (await db.collection('driver_groups').where('memberIds', arrayContains: uid).get()).docs) {
      if (g.data()['ownerId'] == uid) {
        refs.add(g.reference);
      } else {
        await g.reference.update({
          'memberIds': [for (final m in List<String>.from(g.data()['memberIds'] as List)) if (m != uid) m],
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    for (final sub in subcollections) {
      refs.addAll((await userRef.collection(sub).get()).docs.map((d) => d.reference));
    }
    refs.addAll((await db.collection('notifications').where('userId', isEqualTo: uid).get()).docs.map((d) => d.reference));
    // A transporter's private books (Task 67). Violations and call records stay as safety evidence (docs/DATA_RETENTION.md).
    refs.addAll((await db.collection('transporter_accounts').where('ownerId', isEqualTo: uid).get()).docs.map((d) => d.reference));

    // Bilty share links stay out of the deletion (the rules never delete
    // them) but are switched off: nobody can open the LR through them after
    // the account is gone (MASTER-5 Task 6). Trip links end by themselves
    // within 49 hours; a delivered trip's link already says "ended".
    await _revokeLrShares(db, uid);

    // Open loads only (the rules refuse deleting a matched one; there are none
    // left that matter because active trips were checked above).
    final loads = await db.collection('loads').where('shipperId', isEqualTo: uid).get();
    refs.addAll(loads.docs.where((d) => d.data()['status'] == 'open').map((d) => d.reference));

    // Plain deletes first, in chunks well under the 500-write batch limit.
    for (var i = 0; i < refs.length; i += 400) {
      final batch = db.batch();
      for (final r in refs.skip(i).take(400)) {
        batch.delete(r);
      }
      await batch.commit();
    }

    // Last: identity entries and the profile, atomically.
    final last = db.batch();
    final hashes = profile['identityHashes'];
    if (hashes is Map) {
      for (final h in hashes.values) {
        if (h is String && h.length == 64) last.delete(db.collection(IdentityIndex.collection).doc(h));
      }
    }
    last.delete(userRef);
    await last.commit();

    SessionWatcher.expectSignOut();
    await deleteAuthUser();
  }

  /// Revokes every live LR link the user created. A failure here must not
  /// block the deletion: the links still end at their own date.
  static Future<void> _revokeLrShares(FirebaseFirestore db, String uid) async {
    try {
      final shares = await db.collection('lr_shares').where('ownerId', isEqualTo: uid).get();
      final batch = db.batch();
      var any = false;
      for (final d in shares.docs) {
        if (d.data()['revoked'] == true) continue;
        batch.update(d.reference, {'revoked': true, 'statusAt': FieldValue.serverTimestamp()});
        any = true;
      }
      if (any) await batch.commit();
    } on FirebaseException {
      // see above
    }
  }
}
