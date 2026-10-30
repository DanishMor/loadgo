import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/adapters/connect_adapters.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/photos/photo_quality.dart';
import 'package:transport_app/core/photos/photo_service.dart';
import 'package:transport_app/core/photos/photo_widgets.dart';
import 'package:transport_app/core/photos/vehicle_photos.dart';
import 'package:transport_app/core/photos/vehicle_photos_screen.dart';
import 'package:transport_app/core/theme/app_theme.dart';

class _Picker implements PhotoPickerSource {
  bool? lastCamera;
  @override
  Future<PickedPhoto?> pick(bool camera) async {
    lastCamera = camera;
    return PickedPhoto(Uint8List.fromList([1, 2, 3]), 'image/jpeg');
  }
}

class _Store implements StorageGateway {
  @override
  Future<void> put(String path, Uint8List bytes, String contentType, {void Function(double)? onProgress}) async {}
  @override
  Future<Uint8List?> get(String path, {int maxSize = 5 * 1024 * 1024}) async => null;
  @override
  Future<void> delete(String path) async {}
}

/// E18b: the driver's vehicle photo screen.
void main() {
  setUp(() {
    PhotoService.gateway = _Store();
    PhotoImage.clearCache();
  });
  tearDown(() => PhotoService.gateway = const FirebaseStorageGateway());

  String en(String k) => T.get(k, AppLanguage.english);

  Widget host(Widget child, {AppLanguage lang = AppLanguage.english, Brightness b = Brightness.light, double scale = 1}) => LanguageScope(
        notifier: ValueNotifier(lang),
        child: MaterialApp(
          theme: AppTheme.build(b, style: ThemeStyle.signature),
          builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: Directionality(textDirection: lang.textDirection, child: w!)),
          home: child,
        ),
      );

  VehiclePhotosScreen screen({
    List<VehiclePhotoRecord> records = const [],
    PhotoBadge? badge,
    VehiclePhotoUpload? upload,
    OcrReader ocr = const NoOcrReader(),
    PhotoPickerSource? picker,
    Stream<List<VehiclePhotoRecord>> Function()? stream,
  }) =>
      VehiclePhotosScreen(
        vehicleId: 'v1',
        vehicleNumber: 'MH12AB1234',
        vehicleType: '14ft',
        picker: picker ?? _Picker(),
        ocr: ocr,
        records: stream ?? () => Stream.value(records),
        badge: () async => badge,
        upload: upload ?? (id, slot, p, {bool anyway = false}) async => VehiclePhotoRecord(slot: slot, path: 'x', status: VehiclePhotoStatus.pending),
        now: () => DateTime(2027, 5, 20),
      );

  Future<void> openGuide(WidgetTester t, String slot) async {
    await t.scrollUntilVisible(find.byKey(ValueKey('vpAdd_$slot')), 150, scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(find.byKey(ValueKey('vpAdd_$slot')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(ValueKey('vpAdd_$slot')));
    await t.pumpAndSettle();
  }

  testWidgets('loading, then every slot with its state; progress counts approved required slots', (t) async {
    final ctl = StreamController<List<VehiclePhotoRecord>>();
    await t.pumpWidget(host(screen(stream: () => ctl.stream)));
    expect(find.byKey(const ValueKey('vpProgress')), findsNothing);
    ctl.add(const [
      VehiclePhotoRecord(slot: VehiclePhotoSlot.front, path: 'a', status: VehiclePhotoStatus.approved),
      VehiclePhotoRecord(slot: VehiclePhotoSlot.rear, path: 'b', status: VehiclePhotoStatus.rejected, reason: 'blurry'),
      VehiclePhotoRecord(slot: VehiclePhotoSlot.cab, path: 'c', status: VehiclePhotoStatus.approved),
    ]);
    await t.pumpAndSettle();
    expect(find.text(en('vpProgress').replaceAll('{n}', '1').replaceAll('{m}', '7')), findsOneWidget);
    expect(find.text(en('vpReason_blurry')), findsOneWidget);
    expect(find.text(en('vpPrivacy')), findsOneWidget);
    await ctl.close();
  });

  testWidgets('a broken list shows an error with retry', (t) async {
    var calls = 0;
    await t.pumpWidget(host(screen(stream: () => ++calls == 1 ? Stream.error(Exception('x')) : Stream.value(const []))));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('vpRetry')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('vpProgress')), findsOneWidget);
  });

  testWidgets('a slot shows its guide first, then the camera or the gallery', (t) async {
    final picker = _Picker();
    VehiclePhotoSlot? sent;
    await t.pumpWidget(host(screen(picker: picker, upload: (id, slot, p, {bool anyway = false}) async {
      sent = slot;
      return VehiclePhotoRecord(slot: slot, path: 'x', status: VehiclePhotoStatus.pending);
    })));
    await t.pumpAndSettle();
    await openGuide(t, 'left');
    expect(find.text(en('vpGuide_side')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('vpGallery')));
    await t.pumpAndSettle();
    expect(picker.lastCamera, isFalse);
    expect(sent, VehiclePhotoSlot.left);
  });

  testWidgets('an unclear photo explains why and can be sent anyway', (t) async {
    final calls = <bool>[];
    await t.pumpWidget(host(screen(upload: (id, slot, p, {bool anyway = false}) async {
      calls.add(anyway);
      if (!anyway) throw const PhotoNotClear([PhotoIssue.tooDark, PhotoIssue.blurry]);
      return VehiclePhotoRecord(slot: slot, path: 'x', status: VehiclePhotoStatus.pending);
    })));
    await t.pumpAndSettle();
    await openGuide(t, 'front');
    await t.tap(find.byKey(const ValueKey('vpCamera')));
    await t.pumpAndSettle();
    expect(find.text(en('vpIssue_tooDark')), findsOneWidget);
    expect(find.text(en('vpIssue_blurry')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('vpSendAnyway')));
    await t.pumpAndSettle();
    expect(calls, [false, true]);
  });

  testWidgets('a failed send says so calmly', (t) async {
    await t.pumpWidget(host(screen(upload: (id, slot, p, {bool anyway = false}) async => throw Exception('offline'))));
    await t.pumpAndSettle();
    await openGuide(t, 'front');
    await t.tap(find.byKey(const ValueKey('vpCamera')));
    await t.pumpAndSettle();
    expect(find.text(en('vpFailed')), findsOneWidget);
  });

  testWidgets('the plate is read back and a different number is pointed out', (t) async {
    await t.pumpWidget(host(screen(ocr: const FakeOcrReader({OcrKind.plate: {'plate': 'MH12AB9999'}}))));
    await t.pumpAndSettle();
    await openGuide(t, 'plate');
    await t.tap(find.byKey(const ValueKey('vpCamera')));
    await t.pumpAndSettle();
    expect(find.textContaining('MH12AB9999'), findsOneWidget);
  });

  testWidgets('the badge shows its date and a reminder in its last two weeks', (t) async {
    await t.pumpWidget(host(screen(badge: PhotoBadge(DateTime(2027, 6, 1)))));
    await t.pumpAndSettle();
    expect(find.textContaining(en('vpBadgeUntil').split('{').first), findsOneWidget);
    expect(find.byKey(const ValueKey('vpRenew')), findsOneWidget);
  });

  for (final (lang, b) in [(AppLanguage.hindi, Brightness.light), (AppLanguage.urdu, Brightness.dark), (AppLanguage.tamil, Brightness.dark)]) {
    testWidgets('no overflow at 320 dp and 2.0x: ${lang.name} ${b.name}, including the guide', (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(host(screen(records: const [VehiclePhotoRecord(slot: VehiclePhotoSlot.rear, path: 'b', status: VehiclePhotoStatus.rejected, reason: 'plate_mismatch')], badge: PhotoBadge(DateTime(2027, 6, 1))), lang: lang, b: b, scale: 2.0));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await openGuide(t, 'rc');
      expect(find.byKey(const ValueKey('vpGuide')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('every add button says which photo it adds', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(host(screen()));
    await t.pumpAndSettle();
    expect(find.byTooltip(en('vpAddSlot').replaceAll('{slot}', en('vpSlot_front'))), findsOneWidget);
    handle.dispose();
  });
}
