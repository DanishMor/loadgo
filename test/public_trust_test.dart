import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/trust/public_trust.dart';

/// F19: the client side of the server's trust summary.
void main() {
  test('a normal summary', () {
    final t = PublicTrust.fromMap('d1', {'trips': 42, 'rating': 4.3, 'ratingCount': 12, 'verified': true, 'since': '2026-03', 'updatedAt': Timestamp.now()});
    expect(t.trips, 42);
    expect(t.rating, 4.3);
    expect(t.hasRating, isTrue);
    expect(t.verified, isTrue);
    expect(t.since, '2026-03');
  });

  test('no document, a damaged one and odd values all read as zeros', () {
    for (final d in <Map<String, dynamic>?>[
      null,
      {},
      {'trips': 'many', 'rating': 'good', 'ratingCount': -4, 'verified': 'yes', 'since': 5},
      {'trips': -9, 'rating': 99, 'ratingCount': double.nan, 'since': '2026-3'},
      {'trips': 1 << 62, 'rating': double.infinity},
    ]) {
      final t = PublicTrust.fromMap('d', d);
      expect(t.trips, greaterThanOrEqualTo(0));
      expect(t.trips, lessThanOrEqualTo(1000000000));
      expect(t.rating, isNull);
      expect(t.hasRating, isFalse);
      expect(t.verified, isFalse);
      expect(t.since, isNull);
    }
  });

  test('watch gives null until the server wrote the summary, then the numbers', () async {
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'c1');
    expect(await PublicTrust.watch('d1').first, isNull);
    await db.collection('public_trust').doc('d1').set({'trips': 3, 'rating': 5, 'ratingCount': 1, 'verified': false});
    final t = await PublicTrust.watch('d1').first;
    expect(t!.trips, 3);
    expect(t.rating, 5.0);
  });
}
