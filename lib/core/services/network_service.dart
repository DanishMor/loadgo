import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../chat/off_platform.dart';
import '../location/geohash.dart';
import '../models/driver_network.dart';
import '../network/network_logic.dart';
import 'backend.dart';
import 'chat_service.dart';
import 'rate_limit_service.dart';
import 'user_service.dart';

/// Driver-to-driver network: who is nearby (D11), connections (D12), groups
/// (D13), chats with load cards (CH2, CH3, CH7, D14) and location privacy
/// (CH13, CH14). Records only; nothing here calls or notifies anyone.
class NetworkService {
  NetworkService._();

  static CollectionReference<Map<String, dynamic>> get _presence => Backend.db.collection('driver_presence');
  static CollectionReference<Map<String, dynamic>> get _links => Backend.db.collection('driver_links');
  static CollectionReference<Map<String, dynamic>> get _groups => Backend.db.collection('driver_groups');

  /// The name other drivers see.
  static Future<String> myName() async {
    final u = await UserService.getUser();
    final n = (u?['driverName'] ?? u?['name'] ?? '').toString().trim();
    return n.isEmpty ? 'Driver' : n;
  }

  // ---- location privacy (CH13, CH14) ----

  /// Publishes my position for [mode] until [hours] from now. For `hidden` and
  /// `trip` no position is stored at all.
  static Future<void> setLocationMode({required String mode, required String name, double? lat, double? lng, int hours = 8, DateTime? now}) async {
    final uid = Backend.requireUid();
    assert(LocationMode.all.contains(mode));
    final doc = <String, Object?>{'name': name, 'mode': mode, 'updatedAt': FieldValue.serverTimestamp()};
    if (LocationMode.publishes(mode)) {
      if (lat == null || lng == null) throw ArgumentError('position needed');
      final la = roundCoord(lat), lo = roundCoord(lng);
      doc['lat'] = la;
      doc['lng'] = lo;
      doc['geohash'] = geohashEncode(la, lo, precision: 6);
      doc['sharedUntil'] = Timestamp.fromDate((now ?? DateTime.now()).add(Duration(hours: hours)));
    }
    await _presence.doc(uid).set(doc);
  }

  /// Stops sharing (the document is removed).
  static Future<void> stopSharing() => _presence.doc(Backend.requireUid()).delete();

  static Stream<({String mode, DateTime? until})> watchMyMode() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value((mode: LocationMode.hidden, until: null));
    return _presence.doc(uid).snapshots().map((s) {
      final d = s.data();
      return (mode: d?['mode'] as String? ?? LocationMode.hidden, until: (d?['sharedUntil'] as Timestamp?)?.toDate());
    });
  }

  static DriverPresence? _presenceOf(String id, Map<String, dynamic>? d) {
    if (d == null || d['lat'] == null || d['lng'] == null) return null;
    return DriverPresence(
      uid: id,
      name: d['name'] as String? ?? '',
      lat: (d['lat'] as num).toDouble(),
      lng: (d['lng'] as num).toDouble(),
      mode: d['mode'] as String? ?? LocationMode.hidden,
      sharedUntil: (d['sharedUntil'] as Timestamp?)?.toDate(),
    );
  }

  /// Drivers who chose "nearby", in the cells around [lat]/[lng] (about 5 km
  /// wide at precision 4 ... see [geohashPrecisionForKm]); merged live queries.
  static Stream<List<DriverPresence>> watchNearby(double lat, double lng, {double radiusKm = 100}) {
    final cells = geohashCells(lat, lng, geohashPrecisionForKm(radiusKm));
    late StreamController<List<DriverPresence>> out;
    final latest = <String, List<DriverPresence>>{};
    final subs = <StreamSubscription<Object?>>[];
    void emit() => out.add([for (final l in latest.values.expand((x) => x)) l]);
    out = StreamController<List<DriverPresence>>(
      onListen: () {
        for (final cell in cells) {
          subs.add(_presence
              .where('mode', isEqualTo: LocationMode.nearby)
              .where('geohash', isGreaterThanOrEqualTo: cell)
              .where('geohash', isLessThan: '$cell~')
              .limit(50)
              .snapshots()
              .listen((s) {
            latest[cell] = [for (final d in s.docs) ?_presenceOf(d.id, d.data())];
            emit();
          }, onError: out.addError));
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return out.stream;
  }

  /// One connection's position, when they share with connections or nearby.
  static Future<DriverPresence?> connectionPresence(String uid) async {
    try {
      final s = await _presence.doc(uid).get();
      return _presenceOf(uid, s.data());
    } on FirebaseException {
      return null;
    }
  }

  // ---- connections (D12) ----

  static Stream<List<DriverLink>> watchLinks() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _links.where('members', arrayContains: uid).snapshots().map((s) => s.docs.map(DriverLink.fromDoc).toList());
  }

  static Future<void> requestConnection({required String otherUid, required String myName, required String otherName}) async {
    final uid = Backend.requireUid();
    if (otherUid == uid) throw ArgumentError('self');
    final members = [uid, otherUid]..sort();
    await _links.doc(pairIdOf(uid, otherUid)).set({
      'members': members,
      'requestedBy': uid,
      'requesterName': myName,
      'targetName': otherName,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> accept(String linkId) => _links.doc(linkId).update({'status': 'connected', 'updatedAt': FieldValue.serverTimestamp()});

  /// Declines a request, cancels mine, or ends a connection.
  static Future<void> remove(String linkId) => _links.doc(linkId).delete();

  // ---- groups (D13) ----

  static Stream<List<DriverGroup>> watchGroups() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _groups.where('memberIds', arrayContains: uid).snapshots().map((s) => s.docs.map(DriverGroup.fromDoc).toList());
  }

  static Future<String> createGroup({required String name, required String kind}) async {
    final uid = Backend.requireUid();
    final ref = _groups.doc();
    await ref.set({
      'name': name.trim(),
      'kind': kind,
      'ownerId': uid,
      'memberIds': [uid],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Owner adds one connected driver.
  static Future<void> addMember(DriverGroup g, String uid) => _groups.doc(g.id).update({
        'memberIds': [...g.memberIds, uid],
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// A member leaves, or the owner removes someone.
  static Future<void> removeMember(DriverGroup g, String uid) => _groups.doc(g.id).update({
        'memberIds': [for (final m in g.memberIds) if (m != uid) m],
        'updatedAt': FieldValue.serverTimestamp(),
      });

  static Future<void> deleteGroup(String id) => _groups.doc(id).delete();

  // ---- chat (CH2, CH3, CH7, D14) ----

  static CollectionReference<Map<String, dynamic>> _messages(String chatKind, String id) =>
      (chatKind == 'group' ? _groups : _links).doc(id).collection('messages');

  /// [chatKind] is `link` (CH2) or `group` (CH3).
  static Stream<List<NetworkMessage>> watchMessages(String chatKind, String id) => _messages(chatKind, id)
      .orderBy('createdAt', descending: true)
      .limit(200)
      .snapshots()
      .map((s) => s.docs.map(NetworkMessage.fromDoc).toList().reversed.toList());

  static Future<void> send(String chatKind, String id, {required String senderName, String text = '', SharedLoad? loadCard}) async {
    final uid = Backend.requireUid();
    final t = text.trim();
    if (t.isEmpty && loadCard == null) throw ChatSendException('empty');
    if (t.length > NetworkMessage.maxLength) throw ChatSendException('tooLong');
    final ref = _messages(chatKind, id).doc();
    final rate = await RateLimit.prepare(RateLimit.messageKind, docId: ref.id);
    try {
      final batch = Backend.db.batch();
      batch.set(ref, {
        'senderId': uid,
        'senderName': senderName,
        'text': t,
        'loadCard': ?loadCard?.toMap(),
        'flagged': looksOffPlatform(t),
        'createdAt': FieldValue.serverTimestamp(),
      });
      rate.addToBatch(batch);
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') throw ChatSendException('blocked');
      rethrow;
    }
  }
}
