import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/photos/photo_service.dart';
import 'package:transport_app/core/photos/photo_widgets.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/connectivity_service.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';

class FakeStorage implements StorageGateway {
  final puts = <String, Uint8List>{};
  Object? failWith;
  @override
  Future<void> put(String path, Uint8List bytes, String contentType, {void Function(double)? onProgress}) async {
    if (failWith != null) throw failWith!;
    onProgress?.call(0.5);
    puts[path] = bytes;
  }

  @override
  Future<Uint8List?> get(String path, {int maxSize = 5 * 1024 * 1024}) async => puts[path];
  @override
  Future<void> delete(String path) async => puts.remove(path);
}

class FakePicker implements PhotoPickerSource {
  PickedPhoto? next;
  bool? lastCamera;
  FakePicker(this.next);
  @override
  Future<PickedPhoto?> pick(bool camera) async {
    lastCamera = camera;
    return next;
  }
}

Widget host(Widget w, {AppLanguage lang = AppLanguage.english, double scale = 1.0, Brightness b = Brightness.light}) => LanguageScope(
      notifier: ValueNotifier(lang),
      child: MaterialApp(
        theme: AppTheme.build(b),
        builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true), child: child!),
        home: Scaffold(body: SingleChildScrollView(child: w)),
      ),
    );

/// Real time for the fake services, frames for the screen.
Future<void> settleReal(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// F29: the add-photo card.
void main() {
  late FakeStorage storage;
  late FakeFirebaseFirestore db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'u1');
    storage = FakeStorage();
    PhotoService.gateway = storage;
    PhotoImage.clearCache();
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.photoUploads: true});
    ConnectivityService.online.value = true;
  });
  tearDown(() {
    PhotoService.gateway = const FirebaseStorageGateway();
    FeaturesService.reset();
  });

  final photo = PickedPhoto(Uint8List.fromList(List.filled(1000, 1)), 'image/jpeg', localPath: '/tmp/a.jpg');

  testWidgets('with the switch off nothing shows', (t) async {
    FeaturesService.notifier.value = const Features();
    await t.pumpWidget(host(PhotoAttach(target: const PhotoTarget(PhotoKind.licence), picker: FakePicker(photo))));
    expect(find.byKey(const ValueKey('photoAdd')), findsNothing);
  });

  testWidgets('add: choose the camera, the photo is stored, the card says so and the owner is told', (t) async {
    final picker = FakePicker(photo);
    UploadedPhoto? got;
    await t.pumpWidget(host(PhotoAttach(target: const PhotoTarget(PhotoKind.licence), picker: picker, onUploaded: (u) => got = u)));
    expect(find.text('Driving licence'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('photoAdd')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('photoCamera')));
    await settleReal(t);
    expect(picker.lastCamera, isTrue);
    expect(find.byKey(const ValueKey('photoDone')), findsOneWidget);
    expect(got, isNotNull);
    expect(storage.puts.keys.single, got!.path);
    expect((await db.collection('users').doc('u1').collection('uploads').get()).docs.length, 1);
  });

  testWidgets('the gallery works too; closing the picker without a photo changes nothing', (t) async {
    final picker = FakePicker(null);
    await t.pumpWidget(host(PhotoAttach(target: const PhotoTarget(PhotoKind.rc), picker: picker)));
    await t.tap(find.byKey(const ValueKey('photoAdd')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('photoGallery')));
    await settleReal(t);
    expect(picker.lastCamera, isFalse);
    expect(find.byKey(const ValueKey('photoDone')), findsNothing);
    expect(storage.puts, isEmpty);
  });

  testWidgets('a photo that is too big says so and offers no pointless retry', (t) async {
    final big = PickedPhoto(Uint8List(5 * 1024 * 1024), 'image/jpeg');
    await t.pumpWidget(host(PhotoAttach(target: const PhotoTarget(PhotoKind.licence), picker: FakePicker(big))));
    await t.tap(find.byKey(const ValueKey('photoAdd')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('photoGallery')));
    await settleReal(t);
    expect(find.text(T.get('photoTooBig', AppLanguage.english)), findsOneWidget);
    expect(find.byKey(const ValueKey('photoRetry')), findsNothing);
  });

  testWidgets('a refusal from the server shows the message with Retry, and Retry sends the same photo', (t) async {
    storage.failWith = FirebaseException(plugin: 'storage', code: 'unauthorized');
    await t.pumpWidget(host(PhotoAttach(target: const PhotoTarget(PhotoKind.licence), picker: FakePicker(photo))));
    await t.tap(find.byKey(const ValueKey('photoAdd')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('photoGallery')));
    await settleReal(t);
    expect(find.byKey(const ValueKey('photoFailed')), findsOneWidget);
    storage.failWith = null;
    await t.tap(find.byKey(const ValueKey('photoRetry')));
    await settleReal(t);
    expect(find.byKey(const ValueKey('photoDone')), findsOneWidget);
  });

  testWidgets('offline: the photo is kept on the phone and the card says it will be sent later', (t) async {
    ConnectivityService.online.value = false;
    storage.failWith = FirebaseException(plugin: 'storage', code: 'unavailable');
    await t.pumpWidget(host(PhotoAttach(target: const PhotoTarget(PhotoKind.pickup, bookingId: 'B1'), picker: FakePicker(photo))));
    await t.tap(find.byKey(const ValueKey('photoAdd')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('photoGallery')));
    // Three tries with a pause between them (fake time).
    for (var i = 0; i < 8; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump(const Duration(seconds: 2));
      if (find.byKey(const ValueKey('photoQueued')).evaluate().isNotEmpty) break;
    }
    expect(find.byKey(const ValueKey('photoQueued')), findsOneWidget);
    expect((await PhotoQueue.items()).single.localPath, '/tmp/a.jpg');
  });

  testWidgets('PhotoImage reads with the sign-in (no link) and keeps the last ones in memory', (t) async {
    storage.puts['users/u1/docs/licence/x.jpg'] = Uint8List.fromList(_png);
    await t.pumpWidget(host(const PhotoImage('users/u1/docs/licence/x.jpg')));
    await settleReal(t);
    expect(find.byType(Image), findsOneWidget);
    storage.puts.clear();
    await t.pumpWidget(host(const SizedBox()));
    await t.pumpWidget(host(const PhotoImage('users/u1/docs/licence/x.jpg')));
    await settleReal(t);
    expect(find.byType(Image), findsOneWidget, reason: 'from memory, the file is gone from the fake storage');
    await t.pumpWidget(host(const PhotoImage('users/u1/docs/licence/missing.jpg')));
    await settleReal(t);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });

  for (final lang in [AppLanguage.english, AppLanguage.hindi, AppLanguage.urdu]) {
    for (final b in Brightness.values) {
      testWidgets('fits 360x640 at 2.0x text: ${lang.name} ${b.name}', (t) async {
        t.view.physicalSize = const Size(360, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final dir = lang == AppLanguage.urdu ? TextDirection.rtl : TextDirection.ltr;
        await t.pumpWidget(host(
          Directionality(
            textDirection: dir,
            child: Column(children: [
              for (final k in PhotoTarget.docKinds) PhotoAttach(target: PhotoTarget(k), picker: FakePicker(photo)),
              const PhotoAttach(target: PhotoTarget(PhotoKind.truck, vehicleId: 'v1', view: 'front'), titleKey: 'photoView_front'),
            ]),
          ),
          lang: lang,
          scale: 2.0,
          b: b,
        ));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  }
}

// A 1x1 transparent PNG.
const _png = [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xff, 0xff, 0x3f, 0x00, 0x05, 0xfe, 0x02, 0xfe, 0xa7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
];
