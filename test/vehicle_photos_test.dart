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

  group('E18c review', () {
    Map<String, dynamic> rec(String slot, String status, int day, [String vid = 'v1']) =>
        {'slot': slot, 'path': 'users/d/vphotos/$vid/$slot', 'status': status, 'at': Timestamp.fromDate(DateTime(2027, 1, day))};

    test('groupPending keeps pending rows that parse, oldest vehicle first, slots in screen order', () {
      final g = groupPending([
        ('v2', VehiclePhotoRecord.fromMap(rec('rear', 'pending', 5, 'v2'))),
        ('v1', VehiclePhotoRecord.fromMap(rec('rc', 'pending', 3))),
        ('v1', VehiclePhotoRecord.fromMap(rec('front', 'pending', 4))),
        ('v3', VehiclePhotoRecord.fromMap(rec('front', 'approved', 1, 'v3'))),
        ('v4', VehiclePhotoRecord.fromMap({'slot': 'roof'})),
        (null, VehiclePhotoRecord.fromMap(rec('left', 'pending', 1))),
      ]);
      expect(g.keys, ['v1', 'v2']);
      expect(g['v1']!.map((r) => r.slot), [VehiclePhotoSlot.front, VehiclePhotoSlot.rc]);
    });

    test('the queue reads pending records across vehicles, skipping the badge and reviewed ones', () async {
      await db.doc('vehicles/v1/photos/front').set(rec('front', 'pending', 2));
      await db.doc('vehicles/v1/photos/rear').set(rec('rear', 'approved', 1));
      await db.doc('vehicles/v2/photos/plate').set(rec('plate', 'pending', 1, 'v2'));
      await db.doc('vehicles/v2/photos/badge').set({'until': Timestamp.now(), 'by': 'a', 'at': Timestamp.now()});
      final g = await VehiclePhotoService.pendingQueue().first;
      expect(g.keys, ['v2', 'v1']);
      expect(g['v1']!.single.slot, VehiclePhotoSlot.front);
    });

    test('review writes exactly the fields the rules allow; a rejection needs a known reason', () async {
      uid = 'verifier1';
      await db.doc('vehicles/v1/photos/front').set(rec('front', 'pending', 2));
      await db.doc('vehicles/v1/photos/rc').set(rec('rc', 'pending', 2));
      await VehiclePhotoService.review('v1', VehiclePhotoSlot.front, approve: true);
      await VehiclePhotoService.review('v1', VehiclePhotoSlot.rc, approve: false, reason: 'blurry');
      final f = (await db.doc('vehicles/v1/photos/front').get()).data()!;
      final r = (await db.doc('vehicles/v1/photos/rc').get()).data()!;
      expect([f['status'], f['reviewedBy'], f.containsKey('reason')], ['approved', 'verifier1', false]);
      expect([r['status'], r['reason']], ['rejected', 'blurry']);
      expect(() => VehiclePhotoService.review('v1', VehiclePhotoSlot.rc, approve: false, reason: 'ugly'), throwsArgumentError);
    });

    test('grantBadge sets until about six months ahead, inside the 190-day rule limit; vehicleNumber reads the typed number', () async {
      uid = 'verifier1';
      final now = DateTime(2027, 1, 1);
      await VehiclePhotoService.grantBadge('v1', now);
      final b = (await db.doc('vehicles/v1/photos/badge').get()).data()!;
      expect(b.keys.toSet(), {'until', 'by', 'at'});
      final days = (b['until'] as Timestamp).toDate().difference(now).inDays;
      expect(days, inInclusiveRange(180, 190));
      await db.doc('vehicles/v1').set({'number': 'MH12AB1234'});
      expect(await VehiclePhotoService.vehicleNumber('v1'), 'MH12AB1234');
      expect(await VehiclePhotoService.vehicleNumber('nope'), isNull);
    });
  });

  test('plate and RC are private slots; the rest are seen from the road', () {
    expect(VehiclePhotoSlot.values.where((s) => !s.exterior), [VehiclePhotoSlot.plate, VehiclePhotoSlot.rc]);
    expect(VehiclePhotoSlot.required, isNot(contains(VehiclePhotoSlot.cab)));
  });
}
