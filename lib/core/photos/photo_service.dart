import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/features.dart';
import '../services/backend.dart';
import '../services/features_service.dart';

/// What a photo is for. The first six are papers; the others belong to a truck or a trip.
enum PhotoKind { licence, rc, insurance, puc, permit, fitness, truck, pickup, delivery, pod, damage }

/// One image read from the camera or the gallery, already made smaller by the picker.
class PickedPhoto {
  final Uint8List bytes;
  final String mime;

  /// Where the phone keeps it (null on the web); used to try again later when offline.
  final String? localPath;
  const PickedPhoto(this.bytes, this.mime, {this.localPath});
}

/// Where a photo goes (F29). The paths follow storage.rules exactly.
class PhotoTarget {
  final PhotoKind kind;
  final String? bookingId;

  /// For a truck photo: the vehicle and which view (front, side, rear, load).
  /// For a paper of one vehicle (RC, insurance ...): the vehicle, kept in the record so admins see which truck it is for.
  final String? vehicleId;
  final String? view;

  const PhotoTarget(this.kind, {this.bookingId, this.vehicleId, this.view});

  static const docKinds = [PhotoKind.licence, PhotoKind.rc, PhotoKind.insurance, PhotoKind.puc, PhotoKind.permit, PhotoKind.fitness];
  static const tripKinds = [PhotoKind.pickup, PhotoKind.delivery, PhotoKind.pod, PhotoKind.damage];
  static const truckViews = ['front', 'side', 'rear', 'load'];

  bool get isDoc => docKinds.contains(kind);
  bool get isTrip => tripKinds.contains(kind);
  bool get isTruck => kind == PhotoKind.truck;

  /// Null when the target is complete, else what is missing.
  String? get problem {
    if (isTrip && !_safe(bookingId)) return 'booking';
    if (isTruck && (!_safe(vehicleId) || !truckViews.contains(view))) return 'vehicle';
    if (isDoc && vehicleId != null && !_safe(vehicleId)) return 'vehicle';
    return null;
  }

  static bool _safe(String? v) => v != null && RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(v);

  String folder(String uid) {
    if (isDoc) return 'users/$uid/docs/${kind.name}';
    if (isTruck) return 'users/$uid/trucks/$vehicleId';
    return 'bookings/$bookingId/${kind.name}';
  }

  /// The record that says what the file is: papers and trip proof have one, truck photos do not.
  DocumentReference<Map<String, dynamic>>? record(String uid, String id) {
    if (isDoc) return Backend.db.collection('users').doc(uid).collection('uploads').doc(id);
    if (isTrip) return Backend.db.collection('bookings').doc(bookingId).collection('proofs').doc(id);
    return null;
  }
}

/// A photo that was stored.
class UploadedPhoto {
  final String path;
  final String? recordId;
  const UploadedPhoto(this.path, this.recordId);
}

/// The photo could not be taken in; [reason] is `empty`, `too_big`, `type` or `target`.
class PhotoRejected implements Exception {
  final String reason;
  const PhotoRejected(this.reason);

  @override
  String toString() => 'PhotoRejected($reason)';
}

/// The few Storage calls the app needs. Tests use a fake.
abstract class StorageGateway {
  Future<void> put(String path, Uint8List bytes, String contentType, {void Function(double)? onProgress});
  Future<Uint8List?> get(String path, {int maxSize = 5 * 1024 * 1024});
  Future<void> delete(String path);
}

class FirebaseStorageGateway implements StorageGateway {
  const FirebaseStorageGateway();

  @override
  Future<void> put(String path, Uint8List bytes, String contentType, {void Function(double)? onProgress}) async {
    final task = FirebaseStorage.instance.ref(path).putData(bytes, SettableMetadata(contentType: contentType));
    final sub = task.snapshotEvents.listen((s) {
      if (s.totalBytes > 0) onProgress?.call(s.bytesTransferred / s.totalBytes);
    });
    try {
      await task;
    } finally {
      await sub.cancel();
    }
  }

  // Read with the sign-in, never with a download link (a link would be readable by anyone who gets it).
  @override
  Future<Uint8List?> get(String path, {int maxSize = 5 * 1024 * 1024}) => FirebaseStorage.instance.ref(path).getData(maxSize);

  @override
  Future<void> delete(String path) => FirebaseStorage.instance.ref(path).delete();
}

class PhotoService {
  PhotoService._();

  static StorageGateway gateway = const FirebaseStorageGateway();

  static const maxBytes = 5 * 1024 * 1024 - 1;
  static const mimes = {'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/heic': 'heic', 'image/heif': 'heif'};

  static final _random = Random.secure();

  static String newId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return String.fromCharCodes([for (var i = 0; i < 16; i++) chars.codeUnitAt(_random.nextInt(chars.length))]);
  }

  /// The file name of an upload: a fixed view name for a truck, else the new id.
  static String _name(PhotoTarget t, String id, String ext) => t.isTruck ? '${t.view}.$ext' : '$id.$ext';

  /// Checks, stores (up to three tries for a bad network), then writes the record.
  /// Throws [PhotoRejected] for a photo the rules would refuse. Any other
  /// error is the network or the server: the caller may queue the photo.
  static Future<UploadedPhoto> upload(PhotoTarget target, PickedPhoto photo, {void Function(double)? onProgress, List<Duration> backoff = const [Duration(seconds: 1), Duration(seconds: 3)]}) async {
    if (target.problem != null) throw const PhotoRejected('target');
    if (photo.bytes.isEmpty) throw const PhotoRejected('empty');
    if (photo.bytes.length > maxBytes) throw const PhotoRejected('too_big');
    final ext = mimes[photo.mime];
    if (ext == null) throw const PhotoRejected('type');
    final uid = Backend.requireUid();
    final id = newId();
    final path = '${target.folder(uid)}/${_name(target, id, ext)}';
    Object? last;
    for (var attempt = 0; attempt <= backoff.length; attempt++) {
      try {
        await gateway.put(path, photo.bytes, photo.mime, onProgress: onProgress);
        last = null;
        break;
      } catch (e) {
        last = e;
        if (!isTransient(e) || attempt == backoff.length) break;
        await Future<void>.delayed(backoff[attempt]);
      }
    }
    if (last != null) throw last;
    final rec = target.record(uid, id);
    if (rec != null) {
      final data = <String, Object?>{
        'kind': target.kind.name,
        'path': path,
        'size': photo.bytes.length,
        'contentType': photo.mime,
        if (target.isTrip) 'by': uid,
        if (target.isDoc && target.vehicleId != null) 'vehicleId': target.vehicleId,
        'createdAt': FieldValue.serverTimestamp(),
      };
      await rec.set(data);
    }
    return UploadedPhoto(path, rec == null ? null : id);
  }

  /// The picture to print on the LR: the signed proof of delivery if there is one, else the delivery photo.
  /// Null when the switch is off, there is none, or anything goes wrong (the LR must print without it).
  static Future<Uint8List?> proofImage(String bookingId) async {
    try {
      if (!FeaturesService.isOn(FeatureKey.photoUploads)) return null;
      final snap = await Backend.db.collection('bookings').doc(bookingId).collection('proofs').limit(30).get();
      final docs = [for (final d in snap.docs) if (d.data()['path'] is String) d.data()];
      for (final kind in const ['pod', 'delivery']) {
        for (final d in docs) {
          if (d['kind'] == kind) {
            final bytes = await gateway.get(d['path'] as String);
            if (bytes != null && bytes.isNotEmpty) return bytes;
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Network trouble that may pass (worth another try or the queue), as opposed to a refusal.
  static bool isTransient(Object e) {
    if (e is FirebaseException) {
      return const {'unavailable', 'retry-limit-exceeded', 'canceled', 'unknown', 'network-request-failed', 'deadline-exceeded'}.contains(e.code);
    }
    final n = e.runtimeType.toString();
    return n == 'SocketException' || n == 'TimeoutException' || n == 'ClientException' || n == 'HandshakeException';
  }
}

/// A photo waiting for the network (F29): kept on the phone as a path and sent when the phone is online again.
class PendingPhoto {
  final PhotoKind kind;
  final String? bookingId;
  final String? vehicleId;
  final String? view;
  final String localPath;
  final String mime;

  /// Who took it. A photo is only ever sent by the same account (two people may share a phone).
  final String uid;
  const PendingPhoto({required this.kind, required this.localPath, required this.mime, required this.uid, this.bookingId, this.vehicleId, this.view});

  String get key => '$uid|${kind.name}|$bookingId|$vehicleId|$view|$localPath';

  PhotoTarget get target => PhotoTarget(kind, bookingId: bookingId, vehicleId: vehicleId, view: view);

  Map<String, Object?> toJson() => {'kind': kind.name, 'localPath': localPath, 'mime': mime, 'uid': uid, 'bookingId': bookingId, 'vehicleId': vehicleId, 'view': view};

  static PendingPhoto? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = PhotoKind.values.where((k) => k.name == j['kind']).firstOrNull;
    final path = j['localPath'];
    final mime = j['mime'];
    final uid = j['uid'];
    if (kind == null || path is! String || path.isEmpty || mime is! String || uid is! String || uid.isEmpty) return null;
    String? s(Object? v) => v is String ? v : null;
    return PendingPhoto(kind: kind, localPath: path, mime: mime, uid: uid, bookingId: s(j['bookingId']), vehicleId: s(j['vehicleId']), view: s(j['view']));
  }
}

/// Reads a file the phone kept (null when it is gone). Replaced in tests.
typedef FileReader = Future<Uint8List?> Function(String path);

/// Removes a picture the phone kept for the upload (papers must not stay in the cache). Replaced in tests.
typedef FileCleaner = Future<void> Function(String path);

class PhotoQueue {
  PhotoQueue._();

  static const _key = 'photo_queue';
  static const maxItems = 10;

  static Future<List<PendingPhoto>> items() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return [];
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return [for (final j in list) ?PendingPhoto.fromJson(j)];
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<PendingPhoto> list) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode([for (final p in list) p.toJson()]));
    } catch (_) {}
  }

  // Reads and writes of the list happen one after the other, so a photo added while others are
  // being sent is never lost.
  static Future<void> _tail = Future<void>.value();

  static Future<T> _locked<T>(Future<T> Function() job) {
    final done = _tail.then((_) => job());
    _tail = done.then<void>((_) {}, onError: (_) {});
    return done;
  }

  /// Adds a photo. Returns false when it cannot be kept (no file path, as on the web, nobody signed in, or the queue is full).
  static Future<bool> add(PhotoTarget target, PickedPhoto photo) {
    final path = photo.localPath;
    final uid = Backend.uid;
    if (path == null || path.isEmpty || uid == null) return Future.value(false);
    return _locked(() async {
      final list = await items();
      if (list.length >= maxItems) return false;
      list.add(PendingPhoto(kind: target.kind, localPath: path, mime: photo.mime, uid: uid, bookingId: target.bookingId, vehicleId: target.vehicleId, view: target.view));
      await _save(list);
      return true;
    });
  }

  /// Sends what is waiting for the signed-in account. A photo whose file is gone or that the rules
  /// refuse is dropped; one that fails on the network stays; another account's photos are left alone.
  /// Returns how many were sent.
  static Future<int> flush(FileReader read, {FileCleaner? clean}) async {
    final uid = Backend.uid;
    if (uid == null) return 0;
    final mine = [for (final p in await items()) if (p.uid == uid) p];
    if (mine.isEmpty) return 0;
    final done = <String>{}; // sent, gone or refused: these leave the queue
    var sent = 0;
    for (final p in mine) {
      try {
        final bytes = await read(p.localPath);
        if (bytes != null) {
          await PhotoService.upload(p.target, PickedPhoto(bytes, p.mime), backoff: const []);
          sent++;
        }
        done.add(p.key); // sent, or the file is gone
      } on PhotoRejected {
        done.add(p.key); // never going to work
      } catch (e) {
        if (!PhotoService.isTransient(e)) done.add(p.key); // a refusal by the rules; a network problem stays
      }
    }
    if (clean != null) {
      for (final p in mine) {
        if (done.contains(p.key)) await clean(p.localPath).catchError((_) {});
      }
    }
    // Take out only what was handled, from the list as it is now (photos added meanwhile stay).
    await _locked(() async => _save([for (final p in await items()) if (!done.contains(p.key)) p]));
    return sent;
  }
}
