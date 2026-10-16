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
  int attempts = 0;
  @override
  Future<void> put(String path, Uint8List bytes, String contentType, {void Function(double)? onProgress}) async {
    attempts++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
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
