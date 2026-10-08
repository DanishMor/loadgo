import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../risk/risk_config.dart';
import 'backend.dart';
import 'server_clock.dart';
import 'ttl_cache.dart';

/// One signed-in device of a user (`users/{uid}/devices/{deviceId}`).
class UserDevice {
  final String id;
  final String label;
  final bool trusted;
  final bool revoked;
  final DateTime? firstSeenAt;
  final DateTime? lastSeenAt;

  const UserDevice({required this.id, required this.label, required this.trusted, required this.revoked, this.firstSeenAt, this.lastSeenAt});

  factory UserDevice.fromDoc(String id, Map<String, dynamic> d) => UserDevice(
        id: id,
        label: d['label'] as String? ?? '',
        trusted: d['trusted'] == true,
        revoked: d['revoked'] == true,
        firstSeenAt: (d['firstSeenAt'] as Timestamp?)?.toDate(),
        lastSeenAt: (d['lastSeenAt'] as Timestamp?)?.toDate(),
      );
}

/// What registering this device found.
enum DeviceCheck { first, known, newDevice }

/// A device that several accounts have signed in from.
class SharedDevice {
  final String deviceId;
  final List<String> uids;
  const SharedDevice(this.deviceId, this.uids);

  /// Accounts per device above which admins are told.
  static const clusterThreshold = 3;

  /// Groups `device_links` rows by device and keeps the busy ones.
  static List<SharedDevice> clusters(Iterable<({String deviceId, String uid})> links, {int? threshold}) {
    final limit = threshold ?? RiskConfigStore.current.deviceCluster;
    final by = <String, Set<String>>{};
    for (final l in links) {
      by.putIfAbsent(l.deviceId, () => {}).add(l.uid);
    }
    final out = [for (final e in by.entries) if (e.value.length >= limit) SharedDevice(e.key, e.value.toList()..sort())]
      ..sort((a, b) => b.uids.length.compareTo(a.uids.length));
    return out;
  }
}

/// Device records, trusted / revoked devices, "log out everywhere" and the
/// signals admins look at (new device, many accounts on one device).
/// A device is an id kept on the phone, not a hardware id: reinstalling the
/// app makes a new one. LATER(paid): Play Integrity / App Check attestation.
class DeviceService {
  DeviceService._();

  static const _key = 'device_id';
  static String? _cachedId;

  static FirebaseFirestore get _db => Backend.db;

  /// Stable random id for this installation.
  static Future<String> deviceId() async {
    if (_cachedId != null) return _cachedId!;
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_key);
      if (id == null) {
        final r = Random.secure();
        id = List.generate(24, (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[r.nextInt(36)]).join();
        await prefs.setString(_key, id);
      }
      return _cachedId = id;
    } catch (_) {
      return _cachedId = 'unknown-${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  @visibleForTesting
  static void resetForTest() => _cachedId = null;

  static String get platformLabel => defaultTargetPlatform.name;

  static CollectionReference<Map<String, dynamic>> _devices(String uid) => _db.collection('users').doc(uid).collection('devices');

  static final TtlCache _clockCache = TtlCache(const Duration(hours: 6));

  /// Learns the server's time (MASTER-5 Task 20): stamps this device's
  /// `lastSeenAt` with the server clock and reads it back from the server, so
  /// [ServerClock] knows how far the phone's own clock is off. One write and
  /// one read, at most every six hours; a failure just leaves the phone clock.
  static Future<void> syncClock({bool force = false}) async {
    final uid = Backend.uid;
    if (uid == null) return;
    if (!force && _clockCache.fresh) return;
    try {
      final ref = _devices(uid).doc(await deviceId());
      final sent = ServerClock.deviceNow();
      await ref.update({'lastSeenAt': FieldValue.serverTimestamp()});
      final snap = await ref.get(const GetOptions(source: Source.server));
      final received = ServerClock.deviceNow();
      final at = (snap.data()?['lastSeenAt'] as Timestamp?)?.toDate();
      if (at == null) return;
      // The stamp was made about halfway between sending and getting the answer.
      ServerClock.observe(at, receivedAt: sent.add(received.difference(sent) ~/ 2));
      _clockCache.markFetched();
    } catch (_) {
      // No device record yet, offline, or refused: keep the phone clock.
    }
  }

  /// Called after sign-in: records this device, links it to the account, and
  /// raises a risk signal when an account with other devices appears on a new one.
  static Future<DeviceCheck> register() async {
    final uid = Backend.requireUid();
    final id = await deviceId();
    final ref = _devices(uid).doc(id);
    final existing = await ref.get();
    final all = (await _devices(uid).get()).docs;
    final others = all.where((d) => d.id != id).length;
    // F5: this new device plus the ones first seen in the last 24 hours.
    final day = DateTime.now().subtract(const Duration(hours: 24));
    final recent = all.where((d) => d.id != id && ((d.data()['firstSeenAt'] as Timestamp?)?.toDate().isAfter(day) ?? false)).length + 1;
    if (existing.exists) {
      // Signing in again on a revoked device brings it back (the user just
      // proved themselves with a new OTP).
      await ref.update({
        'lastSeenAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
        'revoked': false,
      });
      syncClock(force: true).ignore();
      return DeviceCheck.known;
    }
    final batch = _db.batch();
    batch.set(ref, {
      'label': platformLabel,
      'trusted': others == 0,
      'revoked': false,
      'firstSeenAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
      'lastLoginAt': FieldValue.serverTimestamp(),
    });
    batch.set(_db.collection('device_links').doc('${id}_$uid'), {
      'deviceId': id,
      'uid': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (others > 0) {
      batch.set(_db.collection('risk_signals').doc(), {
        'uid': uid,
        'type': 'new_device',
        'deviceId': id,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    if (recent >= RiskConfigStore.current.manyDevices24h) {
      batch.set(_db.collection('risk_signals').doc(), {
        'uid': uid,
        'type': 'many_devices',
        'deviceId': id,
        'note': '$recent devices in 24 hours',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    syncClock(force: true).ignore();
    return others == 0 ? DeviceCheck.first : DeviceCheck.newDevice;
  }

  /// True when this device was revoked, or the user logged out everywhere
  /// after this device last signed in. The app signs out when it is.
  static Future<bool> sessionRevoked() async {
    final uid = Backend.uid;
    if (uid == null) return false;
    final id = await deviceId();
    final dev = await _devices(uid).doc(id).get();
    if (dev.data()?['revoked'] == true) return true;
    final user = (await _db.collection('users').doc(uid).get()).data();
    final revokedAt = (user?['sessionsRevokedAt'] as Timestamp?)?.toDate();
    final lastLogin = (dev.data()?['lastLoginAt'] as Timestamp?)?.toDate() ?? (dev.data()?['firstSeenAt'] as Timestamp?)?.toDate();
    return revokedAt != null && lastLogin != null && revokedAt.isAfter(lastLogin);
  }

  static Stream<List<UserDevice>> watchMine() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _devices(uid).snapshots().map((s) {
      final list = [for (final d in s.docs) UserDevice.fromDoc(d.id, d.data())];
      list.sort((a, b) => (b.lastSeenAt ?? DateTime(0)).compareTo(a.lastSeenAt ?? DateTime(0)));
      return list;
    });
  }

  static Future<void> trust(String deviceId) => _devices(Backend.requireUid()).doc(deviceId).update({'trusted': true});

  /// Revokes one device (it is signed out the next time the app starts).
  static Future<void> revoke(String deviceId) => _devices(Backend.requireUid()).doc(deviceId).update({'revoked': true, 'trusted': false});

  /// Signs every device out: revokes all but this one and stamps the profile;
  /// the others notice on their next start. TODO(functions): revoke refresh
  /// tokens with the Admin SDK so it takes effect at once.
  static Future<void> logOutEverywhere() async {
    final uid = Backend.requireUid();
    final mine = await deviceId();
    final batch = _db.batch();
    for (final d in (await _devices(uid).get()).docs) {
      if (d.id != mine) batch.update(d.reference, {'revoked': true, 'trusted': false});
    }
    batch.set(_db.collection('users').doc(uid), {'sessionsRevokedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    batch.update(_devices(uid).doc(mine), {'lastLoginAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  /// Admin: accounts-per-device clusters from `device_links`.
  static Future<List<SharedDevice>> sharedDevices({int limit = 1000}) async {
    final s = await _db.collection('device_links').limit(limit).get();
    return SharedDevice.clusters([for (final d in s.docs) (deviceId: d.data()['deviceId'] as String? ?? '', uid: d.data()['uid'] as String? ?? '')]);
  }

  /// Admin: latest risk signals.
  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchRiskSignals({int limit = 100}) =>
      _db.collection('risk_signals').orderBy('createdAt', descending: true).limit(limit).snapshots().map((s) => s.docs);
}
