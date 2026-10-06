import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'account_deletion_service.dart';
import 'backend.dart';

/// "Download my data" (privacy, BE18): a JSON copy of what the signed-in
/// user owns, read with the same queries the app uses. Other people's private
/// fields are not part of it (the rules would refuse them anyway).
class DataExportService {
  DataExportService._();

  static Object? _plain(Object? v) {
    if (v is Timestamp) return v.toDate().toUtc().toIso8601String();
    if (v is DateTime) return v.toUtc().toIso8601String();
    if (v is GeoPoint) return {'lat': v.latitude, 'lng': v.longitude};
    if (v is DocumentReference) return v.path;
    if (v is Map) return {for (final e in v.entries) e.key.toString(): _plain(e.value)};
    if (v is Iterable) return [for (final e in v) _plain(e)];
    return v;
  }

  static List<Map<String, Object?>> _rows(QuerySnapshot<Map<String, dynamic>> s) =>
      [for (final d in s.docs) {'id': d.id, ...(_plain(d.data()) as Map).cast<String, Object?>()}];

  static Future<Map<String, Object?>> build() async {
    final uid = Backend.requireUid();
    final db = Backend.db;
    final me = db.collection('users').doc(uid);
    final out = <String, Object?>{
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'uid': uid,
      'profile': _plain((await me.get()).data()),
    };
    for (final sub in AccountDeletionService.subcollections) {
      out[sub] = _rows(await me.collection(sub).get());
    }
    out['loads'] = _rows(await db.collection('loads').where('shipperId', isEqualTo: uid).get());
    out['bookingsAsCustomer'] = _rows(await db.collection('bookings').where('customerId', isEqualTo: uid).get());
    out['bookingsAsDriver'] = _rows(await db.collection('bookings').where('driverId', isEqualTo: uid).get());
    out['vehicles'] = _rows(await db.collection('vehicles').where('ownerId', isEqualTo: uid).get());
    out['ratingsReceived'] = _rows(await db.collection('ratings').where('ratedId', isEqualTo: uid).get());
    out['notifications'] = _rows(await db.collection('notifications').where('userId', isEqualTo: uid).get());
    return out;
  }

  static Future<String> buildJson() async => const JsonEncoder.withIndent('  ').convert(await build());
}
