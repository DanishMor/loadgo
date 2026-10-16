import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/photos/photo_service.dart';
import 'package:transport_app/core/photos/photo_widgets.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/connectivity_service.dart';
import 'package:transport_app/core/services/features_service.dart';

class FakeStorage implements StorageGateway {
  final puts = <String>[];
  Object? failWith;
  void Function()? onPut;
  int attempts = 0;
  @override
  Future<void> put(String path, Uint8List bytes, String contentType, {void Function(double)? onProgress}) async {
    attempts++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    onPut?.call();
    if (failWith != null) throw failWith!;
    puts.add(path);
  }

  @override
  Future<Uint8List?> get(String path, {int maxSize = 5 * 1024 * 1024}) async => null;
  @override
  Future<void> delete(String path) async {}
}

/// The waiting photos go out when the phone is back online, once, and only when allowed.
void main() {
  cleanupTests();
  late FakeStorage storage;
  const target = PhotoTarget(PhotoKind.pickup, bookingId: 'B1');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'u1');
    storage = FakeStorage();
    PhotoService.gateway = storage;
    PhotoSync.resetForTest();
    PhotoSync.reader = (p) async => Uint8List.fromList([1, 2, 3]);
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.photoUploads: true});
    ConnectivityService.online.value = true;
    await PhotoQueue.add(target, PickedPhoto(Uint8List(3), 'image/jpeg', localPath: '/tmp/a.jpg'));
    await PhotoQueue.add(target, PickedPhoto(Uint8List(3), 'image/jpeg', localPath: '/tmp/b.jpg'));
  });
  tearDown(() {
    PhotoService.gateway = const FirebaseStorageGateway();
    PhotoSync.resetForTest();
    FeaturesService.reset();
  });

  test('flush sends every waiting photo and empties the queue', () async {
    expect(await PhotoSync.flush(), 2);
    expect(storage.puts.length, 2);
    expect(await PhotoQueue.items(), isEmpty);
  });

  test('nothing is sent while offline, with the switch off, or signed out', () async {
    ConnectivityService.online.value = false;
    expect(await PhotoSync.flush(), 0);
    ConnectivityService.online.value = true;
    FeaturesService.notifier.value = const Features();
    expect(await PhotoSync.flush(), 0);
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.photoUploads: true});
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => null);
    expect(await PhotoSync.flush(), 0);
    expect(storage.attempts, 0);
    expect((await PhotoQueue.items()).length, 2);
  });

  test('two flushes at the same moment send each photo once', () async {
    final results = await Future.wait([PhotoSync.flush(), PhotoSync.flush(), PhotoSync.flush()]);
    expect(results.reduce((a, b) => a + b), 2);
    expect(storage.puts.length, 2, reason: 'no photo twice');
  });

  test('a network failure keeps the photos for next time', () async {
    storage.failWith = FirebaseException(plugin: 'storage', code: 'unavailable');
    expect(await PhotoSync.flush(), 0);
    expect((await PhotoQueue.items()).length, 2, reason: 'kept for the next time online');
    storage.failWith = FirebaseException(plugin: 'storage', code: 'unauthorized');
    expect(await PhotoSync.flush(), 0);
    expect(await PhotoQueue.items(), isEmpty, reason: 'a refusal will never work: dropped');
  });

  test('a photo taken by another account on the same phone is not sent as this account', () async {
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'other');
    await PhotoQueue.add(target, PickedPhoto(Uint8List(3), 'image/jpeg', localPath: '/tmp/theirs.jpg'));
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'u1');
    expect(await PhotoSync.flush(), 2, reason: 'only the two of u1');
    expect(storage.puts.every((p) => p.startsWith('bookings/B1/pickup/')), isTrue);
    final left = await PhotoQueue.items();
    expect(left.map((p) => (p.uid, p.localPath)), [('other', '/tmp/theirs.jpg')]);
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'other');
    expect(await PhotoSync.flush(), 1);
    expect(await PhotoQueue.items(), isEmpty);
  });

  test('nobody signed in: nothing is added', () async {
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => null);
    expect(await PhotoQueue.add(target, PickedPhoto(Uint8List(3), 'image/jpeg', localPath: '/tmp/x.jpg')), isFalse);
  });

  test('a photo added while others are being sent stays in the queue', () async {
    final slow = PhotoSync.flush();
    await Future<void>.delayed(const Duration(milliseconds: 5)); // the first upload is under way
    expect(await PhotoQueue.add(target, PickedPhoto(Uint8List(3), 'image/jpeg', localPath: '/tmp/late.jpg')), isTrue);
    expect(await slow, 2);
    expect((await PhotoQueue.items()).map((p) => p.localPath), ['/tmp/late.jpg']);
  });

  test('two adds at the same moment both stay', () async {
    SharedPreferences.setMockInitialValues({});
    final r = await Future.wait([
      PhotoQueue.add(target, PickedPhoto(Uint8List(3), 'image/jpeg', localPath: '/tmp/1.jpg')),
      PhotoQueue.add(target, PickedPhoto(Uint8List(3), 'image/jpeg', localPath: '/tmp/2.jpg')),
      PhotoQueue.add(target, PickedPhoto(Uint8List(3), 'image/jpeg', localPath: '/tmp/3.jpg')),
    ]);
    expect(r, [true, true, true]);
    expect((await PhotoQueue.items()).length, 3);
  });

  test('coming back online starts the send', () async {
    ConnectivityService.online.value = false;
    PhotoSync.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(storage.puts, isEmpty);
    ConnectivityService.online.value = true;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(storage.puts.length, 2);
  });
}

/// The picture the picker left behind is removed after sending, and only from the temporary folder.
void cleanupTests() {
  test('only files inside the temporary folder are deleted', () async {
    final dir = await Directory.systemTemp.createTemp('p2clean');
    addTearDown(() => dir.delete(recursive: true));
    final inside = File('${dir.path}/pic.jpg')..writeAsBytesSync([1]);
    await deleteLocalPicture(inside.path, tempDir: dir.path);
    expect(inside.existsSync(), isFalse);
    final other = await Directory.systemTemp.createTemp('p2keep');
    addTearDown(() => other.delete(recursive: true));
    final outside = File('${other.path}/mine.jpg')..writeAsBytesSync([1]);
    await deleteLocalPicture(outside.path, tempDir: dir.path);
    expect(outside.existsSync(), isTrue, reason: 'not in the temporary folder: a person\'s own photo');
    await deleteLocalPicture('${dir.path}/../${other.path.split(RegExp(r'[\/]')).last}/mine.jpg', tempDir: dir.path);
    expect(outside.existsSync(), isTrue, reason: 'no way out with ..');
    await deleteLocalPicture(null);
    await deleteLocalPicture('');
  });

  test('flush cleans what it handled, not what stays', () async {
    SharedPreferences.setMockInitialValues({});
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'u1');
    final st = FakeStorage();
    PhotoService.gateway = st;
    const t = PhotoTarget(PhotoKind.pickup, bookingId: 'B1');
    await PhotoQueue.add(t, PickedPhoto(Uint8List(3), 'image/jpeg', localPath: '/tmp/a.jpg'));
    await PhotoQueue.add(t, PickedPhoto(Uint8List(3), 'image/jpeg', localPath: '/tmp/b.jpg'));
    final cleaned = <String>[];
    var n = 0;
    st.onPut = () {
      if (++n == 2) throw FirebaseException(plugin: 'storage', code: 'unavailable');
    };
    final sent = await PhotoQueue.flush((p) async => Uint8List(3), clean: (p) async => cleaned.add(p));
    expect(sent, 1);
    expect(cleaned, ['/tmp/a.jpg']);
    expect((await PhotoQueue.items()).map((p) => p.localPath), ['/tmp/b.jpg']);
    PhotoService.gateway = const FirebaseStorageGateway();
  });
}
