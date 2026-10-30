import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/photos/cargo_photos.dart';
import 'package:transport_app/core/photos/photo_quality.dart';
import 'package:transport_app/core/photos/photo_service.dart';
import 'package:transport_app/core/photos/vehicle_photos.dart';
import 'package:transport_app/core/services/backend.dart';

class _Store implements StorageGateway {
  final files = <String, Uint8List>{};
  bool failDelete = false;
  @override
  Future<void> put(String path, Uint8List bytes, String contentType, {void Function(double)? onProgress}) async => files[path] = bytes;
  @override
  Future<Uint8List?> get(String path, {int maxSize = 5 * 1024 * 1024}) async => files[path];
  @override
  Future<void> delete(String path) async {
    if (failDelete) throw StateError('offline');
    files.remove(path);
  }
}

/// E19a: goods photos of a load and the seal photo kind (fake storage, fake database).
void main() {
  late FakeFirebaseFirestore db;
  late _Store store;
  String? uid = 'cust1';
  Future<PhotoQuality> good(Uint8List _) async => const PhotoQuality(120, 300);
  Future<PhotoQuality> blurry(Uint8List _) async => const PhotoQuality(120, 2);

  setUp(() {
    db = FakeFirebaseFirestore();
    store = _Store();
    uid = 'cust1';
    Backend.useFakes(db: db, uid: () => uid);
    PhotoService.gateway = store;
  });
  tearDown(() => PhotoService.gateway = const FirebaseStorageGateway());

  final jpegWithGps = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1, 0, 8, ...'GPS!!!'.codeUnits, 0xFF, 0xDA, 0, 4, 1, 2, 9, 9, 0xFF, 0xD9]);

  test('upload stores the cleaned file at the rules path and a record with only slot, path and time', () async {
    final r = await CargoPhotoService.upload('L1', CargoSlot.goods2, PickedPhoto(jpegWithGps, 'image/jpeg'), measure: good);
    expect(r.path, 'loads/L1/cargo/goods2');
    expect(String.fromCharCodes(store.files['loads/L1/cargo/goods2']!), isNot(contains('GPS')));
    final d = (await db.doc('loads/L1/cargo/goods2').get()).data()!;
    expect(d.keys.toSet(), {'slot', 'path', 'at'});
    expect(d['slot'], 'goods2');
  });

  test('refusals: signed out, odd load id, empty, wrong type, too big, unclear unless sent anyway', () async {
    final ok = PickedPhoto(jpegWithGps, 'image/jpeg');
    uid = null;
    await expectLater(CargoPhotoService.upload('L1', CargoSlot.goods1, ok, measure: good), throwsA(isA<PhotoRejected>()));
    uid = 'cust1';
    await expectLater(CargoPhotoService.upload('L1/../x', CargoSlot.goods1, ok, measure: good), throwsA(isA<PhotoRejected>()));
    await expectLater(CargoPhotoService.upload('L1', CargoSlot.goods1, PickedPhoto(Uint8List(0), 'image/jpeg'), measure: good), throwsA(isA<PhotoRejected>()));
    await expectLater(CargoPhotoService.upload('L1', CargoSlot.goods1, PickedPhoto(jpegWithGps, 'image/svg+xml'), measure: good), throwsA(isA<PhotoRejected>()));
    await expectLater(CargoPhotoService.upload('L1', CargoSlot.goods1, PickedPhoto(Uint8List(CargoPhotoService.maxBytes + 1), 'image/png'), measure: good),
        throwsA(isA<PhotoRejected>().having((e) => e.reason, 'reason', 'too_big')));
    await expectLater(CargoPhotoService.upload('L1', CargoSlot.goods1, ok, measure: blurry), throwsA(isA<PhotoNotClear>()));
    expect(store.files, isEmpty);
    await CargoPhotoService.upload('L1', CargoSlot.goods1, ok, anyway: true, measure: blurry);
    expect(store.files.keys, ['loads/L1/cargo/goods1']);
  });

  test('records parse defensively: unknown slot, missing or foreign path give nothing', () {
    expect(CargoPhotoRecord.fromMap('L1', null), isNull);
    expect(CargoPhotoRecord.fromMap('L1', {'slot': 'goods9', 'path': 'loads/L1/cargo/goods9'}), isNull);
    expect(CargoPhotoRecord.fromMap('L1', {'slot': 'goods1'}), isNull);
    expect(CargoPhotoRecord.fromMap('L1', {'slot': 'goods1', 'path': 'loads/L2/cargo/goods1'}), isNull);
    final r = CargoPhotoRecord.fromMap('L1', {'slot': 'goods1', 'path': 'loads/L1/cargo/goods1', 'at': Timestamp.fromDate(DateTime(2027))})!;
    expect(r.at, DateTime(2027));
  });

  test('list and watch return the three slots in order; freeSlot finds the next empty one', () async {
    for (final s in [CargoSlot.goods3, CargoSlot.goods1]) {
      await CargoPhotoService.upload('L1', s, PickedPhoto(jpegWithGps, 'image/jpeg'), measure: good);
    }
    await db.doc('loads/L1/cargo/junk').set({'slot': 'nope'});
    final l = await CargoPhotoService.list('L1');
    expect(l.map((r) => r.slot), [CargoSlot.goods1, CargoSlot.goods3]);
    expect((await CargoPhotoService.watch('L1').first).map((r) => r.slot), [CargoSlot.goods1, CargoSlot.goods3]);
    expect(CargoPhotoService.freeSlot(l), CargoSlot.goods2);
    expect(CargoPhotoService.freeSlot([...l, const CargoPhotoRecord(slot: CargoSlot.goods2, path: 'x')]), isNull);
  });

  test('remove takes the record off even when the file cannot be deleted', () async {
    await CargoPhotoService.upload('L1', CargoSlot.goods1, PickedPhoto(jpegWithGps, 'image/jpeg'), measure: good);
    store.failDelete = true;
    await CargoPhotoService.remove('L1', CargoSlot.goods1);
    expect((await db.doc('loads/L1/cargo/goods1').get()).exists, isFalse);
  });

  test('seal is a trip photo kind with its own folder, record and words in every language', () {
    const t = PhotoTarget(PhotoKind.seal, bookingId: 'B1');
    expect(t.isTrip, isTrue);
    expect(t.problem, isNull);
    expect(t.folder('drv1'), 'bookings/B1/seal');
    expect(t.record('drv1', 'p1')!.path, 'bookings/B1/proofs/p1');
    for (final l in AppLanguage.values) {
      expect(T.get('photoKind_seal', l), isNot('photoKind_seal'), reason: l.name);
    }
  });
}
