import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/photos/cargo_photo_widgets.dart';
import 'package:transport_app/core/photos/cargo_photos.dart';
import 'package:transport_app/core/photos/photo_quality.dart';
import 'package:transport_app/core/photos/photo_service.dart';
import 'package:transport_app/core/photos/photo_widgets.dart';
import 'package:transport_app/core/photos/vehicle_photos.dart';
import 'package:transport_app/core/theme/app_theme.dart';

class _Picker implements PhotoPickerSource {
  final calls = <bool>[];
  @override
  Future<PickedPhoto?> pick(bool camera) async {
    calls.add(camera);
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

CargoPhotoRecord rec(CargoSlot s) => CargoPhotoRecord(slot: s, path: 'loads/L1/cargo/${s.name}');

/// E19b: the shipper's goods photo card and the driver's goods photo sheet.
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
          home: Scaffold(body: ListView(padding: const EdgeInsets.all(16), children: [child])),
        ),
      );

  group('CargoPhotosCard', () {
    testWidgets('loading, then photos with a count; the next free slot gets camera and gallery', (t) async {
      final ctrl = StreamController<List<CargoPhotoRecord>>();
      final picker = _Picker();
      final sent = <CargoSlot>[];
      await t.pumpWidget(host(CargoPhotosCard(
        loadId: 'L1',
        editable: true,
        picker: picker,
        records: () => ctrl.stream,
        upload: (id, slot, p, {bool anyway = false}) async {
          sent.add(slot);
          return rec(slot);
        },
      )));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      ctrl.add([rec(CargoSlot.goods1), rec(CargoSlot.goods3)]);
      await t.pumpAndSettle();
      expect(find.text('2 of 3'), findsOneWidget);
      expect(find.byKey(const ValueKey('cgPhoto_goods1')), findsOneWidget);
      expect(find.text(en('cgHelp')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('cgGallery')));
      await t.pumpAndSettle();
      expect(picker.calls, [false]);
      expect(sent, [CargoSlot.goods2]);
      await ctrl.close();
    });

    testWidgets('three photos: no add buttons; remove takes one off', (t) async {
      final removed = <CargoSlot>[];
      await t.pumpWidget(host(CargoPhotosCard(
        loadId: 'L1',
        editable: true,
        records: () => Stream.value(CargoSlot.values.map(rec).toList()),
        remove: (id, slot) async => removed.add(slot),
      )));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('cgCamera')), findsNothing);
      expect(find.byTooltip(en('cgRemove')), findsNWidgets(3));
      await t.tap(find.byKey(const ValueKey('cgRemove_goods2')));
      await t.pumpAndSettle();
      expect(removed, [CargoSlot.goods2]);
    });

    testWidgets('not editable: photos only, or a plain "no photos" line', (t) async {
      await t.pumpWidget(host(CargoPhotosCard(loadId: 'L1', records: () => Stream.value(const []))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('cgEmpty')), findsOneWidget);
      expect(find.byKey(const ValueKey('cgCamera')), findsNothing);
      expect(find.text(en('cgHelp')), findsNothing);
    });

    testWidgets('an unclear photo explains why: send anyway sends it with anyway', (t) async {
      final calls = <bool>[];
      await t.pumpWidget(host(CargoPhotosCard(
        loadId: 'L1',
        editable: true,
        picker: _Picker(),
        records: () => Stream.value(const []),
        upload: (id, slot, p, {bool anyway = false}) async {
          calls.add(anyway);
          if (!anyway) throw const PhotoNotClear([PhotoIssue.blurry]);
          return rec(slot);
        },
      )));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('cgCamera')));
      await t.pumpAndSettle();
      expect(find.text(en('vpIssue_blurry')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('vpSendAnyway')));
      await t.pumpAndSettle();
      expect(calls, [false, true]);
    });

    testWidgets('a failed send and a too-big photo say so; a broken list offers retry', (t) async {
      var opened = 0;
      await t.pumpWidget(host(CargoPhotosCard(
        loadId: 'L1',
        editable: true,
        picker: _Picker(),
        records: () {
          opened++;
          return opened == 1 ? Stream.error(StateError('x')) : Stream.value(const []);
        },
        upload: (id, slot, p, {bool anyway = false}) async => throw const PhotoRejected('too_big'),
      )));
      await t.pumpAndSettle();
      final retry = find.widgetWithText(OutlinedButton, en('retry'));
      expect(retry, findsOneWidget);
      await t.tap(retry);
      await t.pumpAndSettle();
      expect(opened, 2);
      await t.tap(find.byKey(const ValueKey('cgCamera')));
      await t.pumpAndSettle();
      expect(find.text(en('photoTooBig')), findsOneWidget);
    });

    for (final (lang, b) in [(AppLanguage.hindi, Brightness.light), (AppLanguage.urdu, Brightness.dark), (AppLanguage.tamil, Brightness.dark)]) {
      testWidgets('no overflow at 320 dp and 2.0x: ${lang.name} ${b.name}', (t) async {
        t.view.physicalSize = const Size(320, 800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(host(
            CargoPhotosCard(loadId: 'L1', editable: true, records: () => Stream.value([rec(CargoSlot.goods1)])),
            lang: lang, b: b, scale: 2));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text(T.get('cgTitle', lang)), findsOneWidget);
      });
    }
  });

  group('CargoPhotosButton', () {
    testWidgets('reads nothing until tapped; the sheet shows the photos with labels', (t) async {
      final sem = t.ensureSemantics();
      var reads = 0;
      await t.pumpWidget(host(CargoPhotosButton(loadId: 'L1', list: (_) async {
        reads++;
        return [rec(CargoSlot.goods1), rec(CargoSlot.goods2)];
      })));
      expect(reads, 0);
      expect(find.byTooltip(en('cgView')), findsOneWidget);
      expect(t.getSize(find.byKey(const ValueKey('cgView_L1'))).height, greaterThanOrEqualTo(48));
      await t.tap(find.byKey(const ValueKey('cgView_L1')));
      await t.pumpAndSettle();
      expect(reads, 1);
      expect(find.byKey(const ValueKey('cgSheet_goods2')), findsOneWidget);
      expect(find.bySemanticsLabel('Goods photo 2'), findsOneWidget);
      sem.dispose();
    });

    testWidgets('no photos: a plain line', (t) async {
      await t.pumpWidget(host(CargoPhotosButton(loadId: 'L1', list: (_) async => const [])));
      await t.tap(find.byKey(const ValueKey('cgView_L1')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('photoSheetEmpty')), findsOneWidget);
    });
  });
}
