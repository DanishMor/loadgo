import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The emulator does not ask for composite indexes; the real Firestore does. Every query in
/// functions/src that needs one is listed here with the index it needs (found in a review).
void main() {
  final json = jsonDecode(File('firestore.indexes.json').readAsStringSync()) as Map<String, dynamic>;
  final have = <String>{
    for (final i in json['indexes'] as List)
      '${i['collectionGroup']}|${i['queryScope']}|${[for (final f in i['fields'] as List) '${f['fieldPath']}'].join(',')}',
  };

  // (collection, scope, fields, who needs it)
  const needed = [
    ('loads', 'COLLECTION', 'shipperId,createdAt', 'limits.js (loads in the last minute and hour)'),
    ('offers', 'COLLECTION', 'driverId,createdAt', 'limits.js'),
    ('calls', 'COLLECTION', 'callerId,createdAt', 'limits.js'),
    ('tickets', 'COLLECTION', 'userId,createdAt', 'limits.js'),
    ('messages', 'COLLECTION_GROUP', 'senderId,createdAt', 'limits.js (messages of one person, all chats)'),
    ('messages', 'COLLECTION', 'senderId,createdAt', 'chatScan.js (the last texts of the sender in one chat)'),
    ('loads', 'COLLECTION', 'status,pickupDate', 'jobs.js (expire old loads)'),
    ('loads', 'COLLECTION', 'status,createdAt', 'jobs.js and push.js (open loads by age)'),
    ('bookings', 'COLLECTION', 'driverId,status,createdAt', 'trust.js (E34 reliability: the newest 100 finished trips of a driver)'),
    ('bookings', 'COLLECTION', 'status,scheduledAt', 'jobs.js (scheduled bookings)'),
    ('users', 'COLLECTION', 'role,lastLocation.geohash', 'push.js (drivers near a load)'),
  ];

  for (final n in needed) {
    test('${n.$1} ${n.$3} (${n.$4})', () {
      expect(have, contains('${n.$1}|${n.$2}|${n.$3}'));
    });
  }

  test('no index is listed twice', () {
    final list = [
      for (final i in json['indexes'] as List) '${i['collectionGroup']}|${i['queryScope']}|${[for (final f in i['fields'] as List) '${f['fieldPath']}:${f['order']}'].join(',')}',
    ];
    expect(list.toSet().length, list.length);
  });
}
