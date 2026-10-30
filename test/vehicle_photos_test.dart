import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/photos/photo_quality.dart';
import 'package:transport_app/core/photos/photo_service.dart';
import 'package:transport_app/core/photos/vehicle_photos.dart';
import 'package:transport_app/core/services/backend.dart';

class _Store implements StorageGateway {
  final files = <String, Uint8List>{};
  @override
  Future<void> put(String path, Uint8List bytes, String contentType, {void Function(double)? onProgress}) async => files[path] = bytes;
  @override
  Future<Uint8List?> get(String path, {int maxSize = 5 * 1024 * 1024}) async => files[path];
  @override
  Future<void> delete(String path) async => files.remove(path);
}

/// E18: vehicle photo records, badge, plate check and the upload path (fake storage, fake database).
void main() {
  late FakeFirebaseFirestore db;
  late _Store store;
  String? uid = 'driver1';
  Future<PhotoQuality> good(Uint8List _) async => const PhotoQuality(120, 300);
  Future<PhotoQuality> dark(Uint8List _) async => const PhotoQuality(10, 300);

  setUp(() {
    db = FakeFirebaseFirestore();
    store = _Store();
    uid = 'driver1';
    Backend.useFakes(db: db, uid: () => uid);
    PhotoService.gateway = store;
  });
  tearDown(() => PhotoService.gateway = const FirebaseStorageGateway());

  final jpegWithGps = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1, 0, 8, ...'GPS!!!'.codeUnits, 0xFF, 0xDA, 0, 4, 1, 2, 9, 9, 0xFF, 0xD9]);

  test('upload stores the cleaned file at the rules path and a pending record', () async {
    final r = await VehiclePhotoService.upload('v1', VehiclePhotoSlot.front, PickedPhoto(jpegWithGps, 'image/jpeg'), measure: good);
    expect(r.path, 'users/driver1/vphotos/v1/front');
    expect(String.fromCharCodes(store.files[r.path]!).contains('GPS'), isFalse, reason: 'location removed before it leaves the phone');
    final rec = (await db.doc('vehicles/v1/photos/front').get()).data()!;
    expect(rec.keys.toSet(), {'slot', 'path', 'status', 'at'});
    expect(rec['status'], 'pending');
  });

  test('an unclear photo is refused with the reason unless the driver sends it anyway', () async {
    await expectLater(VehiclePhotoService.upload('v1', VehiclePhotoSlot.rear, PickedPhoto(jpegWithGps, 'image/jpeg'), measure: dark), throwsA(isA<PhotoNotClear>().having((e) => e.issues, 'issues', [PhotoIssue.tooDark])));
    expect(store.files, isEmpty);
    await VehiclePhotoService.upload('v1', VehiclePhotoSlot.rear, PickedPhoto(jpegWithGps, 'image/jpeg'), measure: dark, anyway: true);
    expect(store.files, hasLength(1));
  });

  test('empty, wrong type, too big, bad vehicle id and signed-out uploads are refused before anything is sent', () async {
    Future<void> bad(String vid, PickedPhoto p, String reason) =>
        expectLater(VehiclePhotoService.upload(vid, VehiclePhotoSlot.front, p, measure: good), throwsA(isA<PhotoRejected>().having((e) => e.reason, 'reason', reason)));
    await bad('v1', PickedPhoto(Uint8List(0), 'image/jpeg'), 'empty');
    await bad('v1', PickedPhoto(Uint8List(10), 'image/svg+xml'), 'type');
    await bad('v1', PickedPhoto(Uint8List(VehiclePhotoService.maxBytes + 1), 'image/png'), 'too_big');
    await bad('../x', PickedPhoto(Uint8List(10), 'image/png'), 'target');
    uid = null;
    await bad('v1', PickedPhoto(Uint8List(10), 'image/png'), 'target');
    expect(store.files, isEmpty);
  });

  test('records parse defensively; the badge record is not listed as a photo', () async {
    expect(VehiclePhotoRecord.fromMap(null), isNull);
    expect(VehiclePhotoRecord.fromMap({'slot': 'roof', 'path': 'x'}), isNull);
    expect(VehiclePhotoRecord.fromMap({'slot': 'front', 'path': 'p', 'status': 'weird', 'reason': 'made up'})!.status, VehiclePhotoStatus.pending);
    expect(VehiclePhotoRecord.fromMap({'slot': 'front', 'path': 'p', 'status': 'rejected', 'reason': 'made up'})!.reason, isNull);
    await db.doc('vehicles/v1/photos/front').set({'slot': 'front', 'path': 'p', 'status': 'approved'});
    await db.doc('vehicles/v1/photos/badge').set({'until': Timestamp.now(), 'by': 'a', 'at': Timestamp.now()});
    final list = await VehiclePhotoService.watch('v1').first;
    expect(list.map((r) => r.slot), [VehiclePhotoSlot.front]);
  });

  test('the badge needs every required slot approved, lasts until its date and reminds two weeks before', () {
    final approved = [for (final s in VehiclePhotoSlot.required) VehiclePhotoRecord(slot: s, path: 'p', status: VehiclePhotoStatus.approved)];
    expect(readyForBadge(approved), isTrue);
    expect(readyForBadge(approved.where((r) => r.slot != VehiclePhotoSlot.plate)), isFalse);
    expect(readyForBadge([...approved.skip(1), VehiclePhotoRecord(slot: approved.first.slot, path: 'p', status: VehiclePhotoStatus.pending)]), isFalse);
    final b = PhotoBadge(DateTime(2027, 6, 1));
    expect(b.activeAt(DateTime(2027, 5, 1)), isTrue);
    expect(b.remindAt(DateTime(2027, 5, 1)), isFalse);
    expect(b.remindAt(DateTime(2027, 5, 20)), isTrue);
    expect(b.activeAt(DateTime(2027, 6, 2)), isFalse);
    expect(PhotoBadge.fromMap({'until': 'soon'}), isNull);
  });

  test('plate check ignores spaces, dashes and case, and says when it could not read', () {
    expect(checkPlate('mh 12-ab 1234', 'MH12AB1234'), PlateCheck.match);
    expect(checkPlate('MH12AB1284', 'MH12AB1234'), PlateCheck.mismatch);
    expect(checkPlate('MH1', 'MH12AB1234'), PlateCheck.unread);
    expect(checkPlate(null, 'MH12AB1234'), PlateCheck.unread);
  });

  test('plate and RC are private slots; the rest are seen from the road', () {
    expect(VehiclePhotoSlot.values.where((s) => !s.exterior), [VehiclePhotoSlot.plate, VehiclePhotoSlot.rc]);
    expect(VehiclePhotoSlot.required, isNot(contains(VehiclePhotoSlot.cab)));
  });
}
