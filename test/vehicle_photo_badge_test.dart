import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/photos/photo_service.dart';
import 'package:transport_app/core/photos/photo_widgets.dart';
import 'package:transport_app/core/photos/vehicle_photo_badge.dart';
import 'package:transport_app/core/photos/vehicle_photos.dart';
import 'package:transport_app/core/theme/app_theme.dart';

class _Store implements StorageGateway {
  @override
  Future<void> put(String path, Uint8List bytes, String contentType, {void Function(double)? onProgress}) async {}
  @override
  Future<Uint8List?> get(String path, {int maxSize = 5 * 1024 * 1024}) async => null;
  @override
  Future<void> delete(String path) async {}
}

/// E18d: the Photo-verified badge on bid cards, its cache and the driver's renew chip.
void main() {
  final now = DateTime(2027, 5, 20);
  setUp(() {
    PhotoBadgeCache.clear();
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
          home: Scaffold(body: Center(child: child)),
        ),
      );

  group('PhotoBadgeCache', () {
    test('one load per vehicle within ten minutes, again after', () async {
      var loads = 0;
      Future<PhotoBadge?> load(String id) async {
        loads++;
        return PhotoBadge(now.add(const Duration(days: 30)));
      }

      await PhotoBadgeCache.get('v1', load: load, now: now);
      await PhotoBadgeCache.get('v1', load: load, now: now.add(const Duration(minutes: 9)));
      expect(loads, 1);
      await PhotoBadgeCache.get('v2', load: load, now: now);
      expect(loads, 2);
      await PhotoBadgeCache.get('v1', load: load, now: now.add(const Duration(minutes: 11)));
      expect(loads, 3);
      expect(PhotoBadgeCache.length, 2);
    });

    test('never holds more than 100 vehicles; clear empties it', () async {
      for (var i = 0; i < 130; i++) {
        await PhotoBadgeCache.get('v$i', load: (_) async => null, now: now);
      }
      expect(PhotoBadgeCache.length, PhotoBadgeCache.maxEntries);
      PhotoBadgeCache.clear();
      expect(PhotoBadgeCache.length, 0);
    });
  });

  group('VehiclePhotoBadge', () {
    testWidgets('shows nothing without a badge, an expired one or an empty id', (t) async {
      var loads = 0;
      await t.pumpWidget(host(Column(children: [
        VehiclePhotoBadge('none', load: (_) async => null, now: () => now),
        VehiclePhotoBadge('old', load: (_) async => PhotoBadge(now.subtract(const Duration(days: 1))), now: () => now),
        VehiclePhotoBadge('', load: (_) async {
          loads++;
          return PhotoBadge(now.add(const Duration(days: 30)));
        }, now: () => now),
      ])));
      await t.pumpAndSettle();
      expect(find.text(en('vpBadge')), findsNothing);
      expect(loads, 0);
    });

    testWidgets('valid badge: labelled 48dp button; a tap shows the approved outside photos', (t) async {
      final sem = t.ensureSemantics();
      await t.pumpWidget(host(VehiclePhotoBadge(
        'v1',
        load: (_) async => PhotoBadge(now.add(const Duration(days: 60))),
        photos: (_) async => const [
          VehiclePhotoRecord(slot: VehiclePhotoSlot.front, path: 'users/d1/vphotos/v1/front', status: VehiclePhotoStatus.approved),
          VehiclePhotoRecord(slot: VehiclePhotoSlot.left, path: 'users/d1/vphotos/v1/left', status: VehiclePhotoStatus.approved),
        ],
        now: () => now,
      )));
      await t.pumpAndSettle();
      final badge = find.byKey(const ValueKey('vpBadge_v1'));
      expect(badge, findsOneWidget);
      expect(t.getSize(badge).height, greaterThanOrEqualTo(48));
      expect(find.bySemanticsLabel(en('vpBadge')), findsOneWidget);
      await t.tap(badge);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('vpSheet_front')), findsOneWidget);
      expect(find.byKey(const ValueKey('vpSheet_left')), findsOneWidget);
      expect(find.byKey(const ValueKey('vpSheet_plate')), findsNothing);
      sem.dispose();
    });

    testWidgets('sheet: a message when no photos could be loaded', (t) async {
      await t.pumpWidget(host(VehiclePhotoBadge('v1',
          load: (_) async => PhotoBadge(now.add(const Duration(days: 60))), photos: (_) async => const [], now: () => now)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('vpBadge_v1')));
      await t.pumpAndSettle();
      expect(find.text(en('vcuLoadError')), findsOneWidget);
    });

    testWidgets('Urdu, dark, text scale 2.0: no overflow', (t) async {
      await t.pumpWidget(host(VehiclePhotoBadge('v1', load: (_) async => PhotoBadge(now.add(const Duration(days: 60))), now: () => now),
          lang: AppLanguage.urdu, b: Brightness.dark, scale: 2));
      await t.pumpAndSettle();
      expect(find.text(T.get('vpBadge', AppLanguage.urdu)), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('VehiclePhotoRenewChip', () {
    testWidgets('badge in its last two weeks or expired asks for fresh photos; earlier it shows the badge', (t) async {
      await t.pumpWidget(host(Column(children: [
        VehiclePhotoRenewChip('soon', load: (_) async => PhotoBadge(now.add(const Duration(days: 5))), now: () => now),
        VehiclePhotoRenewChip('gone', load: (_) async => PhotoBadge(now.subtract(const Duration(days: 5))), now: () => now),
        VehiclePhotoRenewChip('fine', load: (_) async => PhotoBadge(now.add(const Duration(days: 90))), now: () => now),
        VehiclePhotoRenewChip('none', load: (_) async => null, now: () => now),
      ])));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('vpRenew_soon')), findsOneWidget);
      expect(find.byKey(const ValueKey('vpRenew_gone')), findsOneWidget);
      expect(find.byKey(const ValueKey('vpRenew_fine')), findsNothing);
      expect(find.text(en('vpBadge')), findsOneWidget);
    });
  });
}
