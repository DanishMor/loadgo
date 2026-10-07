import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/booking.dart';
import '../services/backend.dart';
import '../share/share_links.dart';

/// A link anyone can open to see where a trip is (family, a customer's
/// office): `https://{host}/trip/{token}`. The token is the secret; the page
/// (hosting/trip.html) reads `trip_shares/{token}` without signing in and
/// sees only the route, the status, the vehicle number and the driver's first
/// name. The link ends after [validFor]; the owner can stop it earlier.
/// The status follows the trip while the driver moves it forward (best
/// effort, written by the app of whoever advances the trip). Live position on
/// the page is LATER(paid): needs Maps and a server.
class TripShareService {
  TripShareService._();

  static const validFor = Duration(hours: 24);
  static const tokenLength = 24;
  static const _alphabet = 'abcdefghijkmnpqrstuvwxyz23456789';

  static CollectionReference<Map<String, dynamic>> get _col => Backend.db.collection('trip_shares');

  /// 24 random letters and digits (no look-alikes), from a secure source.
  static String newToken([Random? random]) {
    final r = random ?? Random.secure();
    return List.generate(tokenLength, (_) => _alphabet[r.nextInt(_alphabet.length)]).join();
  }

  static String linkFor(String token) => 'https://${ShareLinks.host}/trip/$token';

  /// The token of a trip link, or null.
  static String? parseToken(String? link) {
    if (link == null) return null;
    final uri = Uri.tryParse(link.trim());
    if (uri == null || uri.scheme != 'https') return null;
    final seg = uri.pathSegments;
    if (seg.length != 2 || seg[0] != 'trip' || !RegExp('^[$_alphabet]{$tokenLength}\$').hasMatch(seg[1])) return null;
    return seg[1];
  }

  static String firstName(String name) {
    final t = name.trim();
    final i = t.indexOf(RegExp(r'\s'));
    final f = i < 0 ? t : t.substring(0, i);
    return f.length > 40 ? f.substring(0, 40) : f;
  }

  /// The public fields of a share (what the web page can read).
  static Map<String, Object?> publicFields(Booking b) => {
        'bookingId': b.id,
        'pickup': _cut(b.pickup, 200),
        'drop': _cut(b.drop, 200),
        'status': b.status,
        'vehicleNumber': _cut(b.vehicleNumber, 20),
        'driverName': firstName(b.driverName),
      };

  static String _cut(String s, int n) => s.length > n ? s.substring(0, n) : s;

  /// The signed-in user's live link for [booking]: reuses one that has not
  /// ended, else creates a new one. Returns the token.
  static Future<String> createOrReuse(Booking booking, {DateTime? now, Random? random}) async {
    final uid = Backend.requireUid();
    final at = now ?? DateTime.now();
    final existing = await _col.where('bookingId', isEqualTo: booking.id).where('ownerId', isEqualTo: uid).get();
    for (final d in existing.docs) {
      final ends = (d.data()['expiresAt'] as Timestamp?)?.toDate();
      if (ends != null && ends.isAfter(at.add(const Duration(hours: 1)))) return d.id;
    }
    final token = newToken(random);
    await _col.doc(token).set({
      ...publicFields(booking),
      'ownerId': uid,
      'statusAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(at.add(validFor)),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return token;
  }

  /// Keeps the live links of [bookingId] on the current [status]. Never throws.
  static Future<void> syncStatus(String bookingId, String status, {DateTime? now}) async {
    try {
      final at = now ?? DateTime.now();
      final snap = await _col.where('bookingId', isEqualTo: bookingId).get();
      for (final d in snap.docs) {
        final ends = (d.data()['expiresAt'] as Timestamp?)?.toDate();
        if (ends == null || !ends.isAfter(at) || d.data()['status'] == status) continue;
        await d.reference.update({'status': status, 'statusAt': FieldValue.serverTimestamp()});
      }
    } catch (_) {}
  }

  /// Ends a link now (owner only).
  static Future<void> stop(String token) => _col.doc(token).delete();
}
