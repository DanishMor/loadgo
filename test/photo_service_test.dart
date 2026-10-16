import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/photos/photo_service.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/services/backend.dart';

class FakeStorage implements StorageGateway {
  final puts = <String, Uint8List>{};
  final types = <String, String>{};
  final failures = <Object>[]; // thrown one per put, in order
  int attempts = 0;

  @override
  Future<void> put(String path, Uint8List bytes, String contentType, {void Function(double)? onProgress}) async {
    attempts++;
    if (failures.isNotEmpty) throw failures.removeAt(0);
    onProgress?.call(0.5);
    onProgress?.call(1);
    puts[path] = bytes;
    types[path] = contentType;
  }

  @override
  Future<Uint8List?> get(String path, {int maxSize = 5 * 1024 * 1024}) async => puts[path];

  @override
  Future<void> delete(String path) async => puts.remove(path);
}

Uint8List bytes([int n = 100]) => Uint8List.fromList(List.filled(n, 7));

class ThrowingStorage implements StorageGateway {
  @override
  Future<void> put(String path, Uint8List bytes, String contentType, {void Function(double)? onProgress}) async => throw Exception('x');
  @override
  Future<Uint8List?> get(String path, {int maxSize = 5 * 1024 * 1024}) async => throw Exception('boom');
  @override
  Future<void> delete(String path) async {}
}

/// F29: taking in photos and papers.
void main() {
  late FakeFirebaseFirestore db;
  late FakeStorage storage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'u1');
    storage = FakeStorage();
    PhotoService.gateway = storage;
  });
  tearDown(() => PhotoService.gateway = const FirebaseStorageGateway());

  test('every vehicle paper kind of the app is a photo kind (the vehicle documents screen looks it up by name)', () {
    for (final k in VehicleDocKind.all) {
      expect(PhotoKind.values.map((e) => e.name), contains(k));
      expect(PhotoTarget.docKinds.map((e) => e.name), contains(k));
    }
  });

  group('where a photo goes', () {
    test('papers, truck photos and trip proof have the paths storage.rules expects', () {
      expect(const PhotoTarget(PhotoKind.licence).folder('u1'), 'users/u1/docs/licence');
      expect(const PhotoTarget(PhotoKind.insurance).folder('u1'), 'users/u1/docs/insurance');
      expect(const PhotoTarget(PhotoKind.truck, vehicleId: 'v1', view: 'front').folder('u1'), 'users/u1/trucks/v1');
      expect(const PhotoTarget(PhotoKind.pickup, bookingId: 'B1').folder('u1'), 'bookings/B1/pickup');
      expect(const PhotoTarget(PhotoKind.damage, bookingId: 'B1').folder('u1'), 'bookings/B1/damage');
    });

    test('an incomplete target is a problem, not a crash', () {
      expect(const PhotoTarget(PhotoKind.pickup).problem, 'booking');
      expect(const PhotoTarget(PhotoKind.pod, bookingId: '../x').problem, 'booking');
      expect(const PhotoTarget(PhotoKind.truck, vehicleId: 'v1', view: 'roof').problem, 'vehicle');
      expect(const PhotoTarget(PhotoKind.truck, view: 'front').problem, 'vehicle');
      expect(const PhotoTarget(PhotoKind.licence).problem, isNull);
    });

    test('the kinds in the app are the kinds in the rules', () {
      final rules = File('storage.rules').readAsStringSync();
      for (final k in PhotoTarget.docKinds) {
        expect(rules, contains("'${k.name}'"), reason: k.name);
      }
      for (final k in PhotoTarget.tripKinds) {
        expect(rules, contains("'${k.name}'"), reason: k.name);
      }
      final fs = File('firestore.rules').readAsStringSync();
      for (final k in [...PhotoTarget.docKinds, ...PhotoTarget.tripKinds]) {
        expect(fs, contains("'${k.name}'"), reason: k.name);
      }
    });
  });

  group('upload', () {
    test('a paper: stored at the path, with a record that has no link', () async {
      final progress = <double>[];
      final r = await PhotoService.upload(const PhotoTarget(PhotoKind.licence), PickedPhoto(bytes(2000), 'image/jpeg'), onProgress: progress.add);
      expect(r.path, startsWith('users/u1/docs/licence/'));
      expect(r.path, endsWith('.jpg'));
      expect(storage.puts.keys.single, r.path);
      expect(storage.types[r.path], 'image/jpeg');
      expect(progress, [0.5, 1]);
      final rec = (await db.collection('users').doc('u1').collection('uploads').doc(r.recordId).get()).data()!;
      expect(rec.keys.toSet(), {'kind', 'path', 'size', 'contentType', 'createdAt'});
      expect(rec['kind'], 'licence');
      expect(rec['path'], r.path);
      expect(rec['size'], 2000);
      expect(r.path.endsWith('${r.recordId}.jpg'), isTrue, reason: 'the rules want the record id in the path');
    });

    test('trip proof: the record sits under the booking and says who took it', () async {
      final r = await PhotoService.upload(const PhotoTarget(PhotoKind.delivery, bookingId: 'B7'), PickedPhoto(bytes(), 'image/png'));
      expect(r.path, startsWith('bookings/B7/delivery/'));
      expect(r.path, endsWith('.png'));
      final rec = (await db.collection('bookings').doc('B7').collection('proofs').doc(r.recordId).get()).data()!;
      expect(rec['by'], 'u1');
      expect(rec['kind'], 'delivery');
      expect(rec.keys.toSet(), {'kind', 'path', 'size', 'contentType', 'by', 'createdAt'});
    });

    test('a truck photo has a fixed name per view and no record', () async {
      final r = await PhotoService.upload(const PhotoTarget(PhotoKind.truck, vehicleId: 'v1', view: 'front'), PickedPhoto(bytes(), 'image/webp'));
      expect(r.path, 'users/u1/trucks/v1/front.webp');
      expect(r.recordId, isNull);
      expect((await db.collection('users').doc('u1').collection('uploads').get()).docs, isEmpty);
    });

    test('what the rules would refuse is refused before anything is sent', () async {
      Future<void> bad(PhotoTarget t, PickedPhoto p, String why) async {
        await expectLater(PhotoService.upload(t, p), throwsA(isA<PhotoRejected>().having((e) => e.reason, 'reason', why)));
      }

      await bad(const PhotoTarget(PhotoKind.licence), PickedPhoto(Uint8List(0), 'image/jpeg'), 'empty');
      await bad(const PhotoTarget(PhotoKind.licence), PickedPhoto(bytes(5 * 1024 * 1024), 'image/jpeg'), 'too_big');
      await bad(const PhotoTarget(PhotoKind.licence), PickedPhoto(bytes(), 'application/pdf'), 'type');
      await bad(const PhotoTarget(PhotoKind.licence), PickedPhoto(bytes(), 'image/gif'), 'type');
      await bad(const PhotoTarget(PhotoKind.pickup), PickedPhoto(bytes(), 'image/jpeg'), 'target');
      expect(storage.attempts, 0);
    });

    test('just under 5 MB goes through', () async {
      await PhotoService.upload(const PhotoTarget(PhotoKind.rc), PickedPhoto(bytes(5 * 1024 * 1024 - 1), 'image/jpeg'));
      expect(storage.puts.length, 1);
    });

    test('a bad network is tried again; a refusal is not', () async {
      storage.failures.addAll([FirebaseException(plugin: 'storage', code: 'unavailable'), FirebaseException(plugin: 'storage', code: 'retry-limit-exceeded')]);
      final r = await PhotoService.upload(const PhotoTarget(PhotoKind.licence), PickedPhoto(bytes(), 'image/jpeg'), backoff: const [Duration.zero, Duration.zero]);
      expect(storage.attempts, 3);
      expect(storage.puts.containsKey(r.path), isTrue);

      storage.attempts = 0;
      storage.failures.add(FirebaseException(plugin: 'storage', code: 'unauthorized'));
      await expectLater(PhotoService.upload(const PhotoTarget(PhotoKind.licence), PickedPhoto(bytes(), 'image/jpeg'), backoff: const [Duration.zero]), throwsA(isA<FirebaseException>()));
      expect(storage.attempts, 1, reason: 'a refusal is not repeated');
    });

    test('after the last try the error comes out and no record is written', () async {
      storage.failures.addAll([for (var i = 0; i < 5; i++) FirebaseException(plugin: 'storage', code: 'unavailable')]);
      await expectLater(PhotoService.upload(const PhotoTarget(PhotoKind.licence), PickedPhoto(bytes(), 'image/jpeg'), backoff: const [Duration.zero, Duration.zero]), throwsA(isA<FirebaseException>()));
      expect(storage.attempts, 3);
      expect((await db.collection('users').doc('u1').collection('uploads').get()).docs, isEmpty);
    });

    test('ids are random and the file name only has safe letters', () {
      final ids = {for (var i = 0; i < 200; i++) PhotoService.newId()};
      expect(ids.length, 200);
      expect(ids.every((x) => RegExp(r'^[a-z0-9]{16}$').hasMatch(x)), isTrue);
    });
  });

  group('the offline queue', () {
    const target = PhotoTarget(PhotoKind.pickup, bookingId: 'B1');

    test('a photo with a file path waits; one without (the web) cannot', () async {
      expect(await PhotoQueue.add(target, PickedPhoto(bytes(), 'image/jpeg', localPath: '/tmp/a.jpg')), isTrue);
      expect(await PhotoQueue.add(target, PickedPhoto(bytes(), 'image/jpeg')), isFalse);
      expect((await PhotoQueue.items()).single.localPath, '/tmp/a.jpg');
    });

    test('at most ten wait', () async {
      for (var i = 0; i < PhotoQueue.maxItems; i++) {
        expect(await PhotoQueue.add(target, PickedPhoto(bytes(), 'image/jpeg', localPath: '/tmp/$i.jpg')), isTrue);
      }
      expect(await PhotoQueue.add(target, PickedPhoto(bytes(), 'image/jpeg', localPath: '/tmp/x.jpg')), isFalse);
    });

    test('flush sends what is there, drops what is gone or refused, and keeps what failed on the network', () async {
      await PhotoQueue.add(target, PickedPhoto(bytes(), 'image/jpeg', localPath: '/tmp/ok.jpg'));
      await PhotoQueue.add(target, PickedPhoto(bytes(), 'image/jpeg', localPath: '/tmp/gone.jpg'));
      await PhotoQueue.add(target, PickedPhoto(bytes(), 'image/jpeg', localPath: '/tmp/net.jpg'));
      Future<Uint8List?> read(String p) async => p.endsWith('gone.jpg') ? null : bytes();
      storage.failures.addAll([]);
      // The first photo goes, the second is gone, the third meets a bad network.
      var call = 0;
      final wrapped = FakeStorageFailing(storage, () => ++call == 2 ? FirebaseException(plugin: 'storage', code: 'unavailable') : null);
      PhotoService.gateway = wrapped;
      final sent = await PhotoQueue.flush(read);
      expect(sent, 1);
      final left = await PhotoQueue.items();
      expect(left.map((p) => p.localPath), ['/tmp/net.jpg']);
    });

    test('a damaged queue reads as empty and never throws', () async {
      SharedPreferences.setMockInitialValues({'photo_queue': 'not json'});
      expect(await PhotoQueue.items(), isEmpty);
      SharedPreferences.setMockInitialValues({'photo_queue': '[1, {"kind": "nope"}, {"kind": "pickup", "localPath": "", "mime": "x"}]'});
      expect(await PhotoQueue.items(), isEmpty);
    });
  });

  group('the picture for the LR', () {
    Future<void> proof(String id, String kind, List<int> bytes) async {
      final path = 'bookings/B1/$kind/$id.jpg';
      storage.puts[path] = Uint8List.fromList(bytes);
      await db.collection('bookings').doc('B1').collection('proofs').doc(id).set({'kind': kind, 'path': path});
    }

    test('the signed proof comes first, then the delivery photo; none or switch off is null', () async {
      FeaturesService.notifier.value = const Features(flags: {FeatureKey.photoUploads: true});
      expect(await PhotoService.proofImage('B1'), isNull, reason: 'nothing yet');
      await proof('d1', 'delivery', [1, 1]);
      await proof('p0', 'pickup', [9, 9]);
      expect(await PhotoService.proofImage('B1'), [1, 1], reason: 'delivery photo, never the pickup one');
      await proof('s1', 'pod', [2, 2]);
      expect(await PhotoService.proofImage('B1'), [2, 2], reason: 'the signed proof is preferred');
      FeaturesService.notifier.value = const Features();
      expect(await PhotoService.proofImage('B1'), isNull, reason: 'switch off');
      FeaturesService.reset();
    });

    test('a missing file or a broken read never stops the LR', () async {
      FeaturesService.notifier.value = const Features(flags: {FeatureKey.photoUploads: true});
      await db.collection('bookings').doc('B1').collection('proofs').doc('x').set({'kind': 'pod', 'path': 'bookings/B1/pod/gone.jpg'});
      expect(await PhotoService.proofImage('B1'), isNull);
      PhotoService.gateway = ThrowingStorage();
      expect(await PhotoService.proofImage('B1'), isNull);
      FeaturesService.reset();
    });
  });

  group('guards: no public links', () {
    test('the photo code never asks for a download link', () {
      for (final f in Directory('lib/core/photos').listSync(recursive: true).whereType<File>()) {
        expect(f.readAsStringSync().contains('getDownloadURL'), isFalse, reason: f.path);
      }
    });
  });
}

/// Fails the n-th put with an error from [fail] (when it returns one).
class FakeStorageFailing implements StorageGateway {
  final FakeStorage inner;
  final Object? Function() fail;
  FakeStorageFailing(this.inner, this.fail);

  @override
  Future<void> put(String path, Uint8List bytes, String contentType, {void Function(double)? onProgress}) async {
    final e = fail();
    if (e != null) throw e;
    return inner.put(path, bytes, contentType, onProgress: onProgress);
  }

  @override
  Future<Uint8List?> get(String path, {int maxSize = 5 * 1024 * 1024}) => inner.get(path, maxSize: maxSize);

  @override
  Future<void> delete(String path) => inner.delete(path);
}
