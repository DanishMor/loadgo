import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// MASTER-5 Task 11: queries that need a composite index have one. The pairs
/// below are the equality field + `createdAt` (or geohash) queries in lib/;
/// a new ordered query must be added here and to firestore.indexes.json.
void main() {
  final idx = jsonDecode(File('firestore.indexes.json').readAsStringSync())['indexes'] as List;
  bool has(String collection, List<String> fields) => idx.any((i) =>
      i['collectionGroup'] == collection &&
      (i['fields'] as List).map((f) => f['fieldPath']).toList().join(',') == fields.join(','));

  test('paged lists (newestPage) have their composite index', () {
    expect(has('loads', ['shipperId', 'createdAt']), isTrue);
    expect(has('loads', ['status', 'createdAt']), isTrue);
    expect(has('bookings', ['driverId', 'createdAt']), isTrue);
    expect(has('bookings', ['customerId', 'createdAt']), isTrue);
  });

  test('nearby queries have theirs', () {
    expect(has('loads', ['status', 'pickupGeohash']), isTrue);
    expect(has('driver_presence', ['mode', 'geohash']), isTrue);
  });

  test('newestPage is only called with an indexed field', () {
    final used = <String>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      for (final m in RegExp(r"newestPage\(\s*_col\.where\('(\w+)'").allMatches(f.readAsStringSync())) {
        used.add(m.group(1)!);
      }
    }
    expect(used.difference({'shipperId', 'status'}), isEmpty, reason: 'new newestPage field needs an index');
  });

  test('no index is declared twice', () {
    final keys = [for (final i in idx) '${i['collectionGroup']}:${(i['fields'] as List).map((f) => '${f['fieldPath']} ${f['order'] ?? f['arrayConfig']}').join(',')}'];
    expect(keys.toSet().length, keys.length);
  });
}
