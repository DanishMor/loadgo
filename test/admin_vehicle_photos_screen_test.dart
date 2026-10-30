import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_vehicle_photos_screen.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/photos/photo_service.dart';
import 'package:transport_app/core/photos/photo_widgets.dart';
import 'package:transport_app/core/photos/vehicle_photos.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/widgets/ds/skeleton.dart';

class _Store implements StorageGateway {
  @override
  Future<void> put(String path, Uint8List bytes, String contentType, {void Function(double)? onProgress}) async {}
  @override
  Future<Uint8List?> get(String path, {int maxSize = 5 * 1024 * 1024}) async => null;
  @override
  Future<void> delete(String path) async {}
}

/// E18c: the admin photo review queue and the per-vehicle review.
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

  VehiclePhotoRecord rec(VehiclePhotoSlot s, [VehiclePhotoStatus st = VehiclePhotoStatus.pending, String? reason]) =>
      VehiclePhotoRecord(slot: s, path: 'users/d/vphotos/v1/${s.name}', status: st, reason: reason);

  final allApproved = [for (final s in VehiclePhotoSlot.required) rec(s, VehiclePhotoStatus.approved)];

  testWidgets('queue: loading, then each vehicle with its count; a tap opens that vehicle', (t) async {
    final ctl = StreamController<Map<String, List<VehiclePhotoRecord>>>();
    String? opened;
    await t.pumpWidget(host(AdminVehiclePhotosScreen(queue: () => ctl.stream, review: (id) {
      opened = id;
      return const Scaffold();
    })));
    expect(find.byType(SkeletonList), findsOneWidget);
    ctl.add({'v1': [rec(VehiclePhotoSlot.front), rec(VehiclePhotoSlot.rc)], 'v2': [rec(VehiclePhotoSlot.rear)]});
    await t.pumpAndSettle();
    expect(find.text(en('vpaWaiting').replaceAll('{n}', '2')), findsOneWidget);
    expect(find.text(en('vpaWaiting').replaceAll('{n}', '1')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('vpaVehicle_v2')));
    await t.pumpAndSettle();
    expect(opened, 'v2');
    await ctl.close();
  });

  testWidgets('queue: empty says nothing is waiting; an error offers retry that opens the stream again', (t) async {
    var opens = 0;
    await t.pumpWidget(host(AdminVehiclePhotosScreen(queue: () {
      opens++;
      return opens == 1 ? Stream.error('denied') : Stream.value(const {});
    })));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('vpaRetry')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('vpaRetry')));
    await t.pumpAndSettle();
    expect(opens, 2);
    expect(find.text(en('vpaEmpty')), findsOneWidget);
  });

  testWidgets('review: approve sends approve; reject asks why and sends the chosen reason', (t) async {
    final calls = <String>[];
    await t.pumpWidget(host(AdminVehiclePhotoReview(
      vehicleId: 'v1',
      records: () => Stream.value([rec(VehiclePhotoSlot.front), rec(VehiclePhotoSlot.plate)]),
      badge: () async => null,
      number: () async => 'MH12AB1234',
      review: (id, slot, {required bool approve, String? reason}) async => calls.add('$id ${slot.name} $approve $reason'),
    )));
    await t.pumpAndSettle();
    expect(find.text(en('vpaNumber').replaceAll('{number}', 'MH12AB1234')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('vpaApprove_front')));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const ValueKey('vpaReject_plate')), 200, scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(find.byKey(const ValueKey('vpaReject_plate')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('vpaReject_plate')));
    await t.pumpAndSettle();
    expect(find.text(en('vpaRejectWhy')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('vpaReason_plate_mismatch')));
    await t.pumpAndSettle();
    expect(calls, ['v1 front true null', 'v1 plate false plate_mismatch']);
  });

  testWidgets('review: dismissing the reason sheet sends nothing; a failed write says so', (t) async {
    var calls = 0;
    await t.pumpWidget(host(AdminVehiclePhotoReview(
      vehicleId: 'v1',
      records: () => Stream.value([rec(VehiclePhotoSlot.front)]),
      badge: () async => null,
      number: () async => null,
      review: (id, slot, {required bool approve, String? reason}) async {
        calls++;
        throw StateError('denied');
      },
    )));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('vpaReject_front')));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    expect(calls, 0);
    await t.tap(find.byKey(const ValueKey('vpaApprove_front')));
    await t.pumpAndSettle();
    expect(calls, 1);
    expect(find.text(en('vpFailed')), findsOneWidget);
  });

  testWidgets('the badge button waits for every required photo, then grants from now', (t) async {
    DateTime? grantedAt;
    final now = DateTime(2027, 1, 1);
    Future<void> pump(List<VehiclePhotoRecord> records) => t.pumpWidget(host(AdminVehiclePhotoReview(
          key: UniqueKey(),
          vehicleId: 'v1',
          records: () => Stream.value(records),
          badge: () async => null,
          number: () async => null,
          grant: (id, at) async => grantedAt = at,
          now: () => now,
        )));
    await pump([...allApproved.skip(1), rec(VehiclePhotoSlot.front)]);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const ValueKey('vpaGrant')), 300, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const ValueKey('vpaGrantNeed')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('vpaGrant')), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(grantedAt, isNull);

    await pump(allApproved);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const ValueKey('vpaGrant')), 300, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const ValueKey('vpaGrantNeed')), findsNothing);
    await t.tap(find.byKey(const ValueKey('vpaGrant')));
    await t.pumpAndSettle();
    expect(grantedAt, now);
    expect(find.textContaining(en('vpaGranted').split('{').first), findsOneWidget);
  });

  for (final (lang, b) in [(AppLanguage.hindi, Brightness.light), (AppLanguage.urdu, Brightness.dark), (AppLanguage.tamil, Brightness.dark)]) {
    testWidgets('no overflow at 320 dp and 2.0x: ${lang.name} ${b.name}, queue, review and reason sheet', (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(host(AdminVehiclePhotosScreen(queue: () => Stream.value({'a-very-long-vehicle-id-0123456789': [rec(VehiclePhotoSlot.front)]})), lang: lang, b: b, scale: 2.0));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.pumpWidget(host(AdminVehiclePhotoReview(
        vehicleId: 'v1',
        records: () => Stream.value([rec(VehiclePhotoSlot.plate, VehiclePhotoStatus.rejected, 'plate_mismatch'), rec(VehiclePhotoSlot.front)]),
        badge: () async => PhotoBadge(DateTime(2099)),
        number: () async => 'MH12AB1234',
      ), lang: lang, b: b, scale: 2.0));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.scrollUntilVisible(find.byKey(const ValueKey('vpaReject_front')), 200, scrollable: find.byType(Scrollable).first);
      await t.ensureVisible(find.byKey(const ValueKey('vpaReject_front')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('vpaReject_front')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('vpaReason_other')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  test('the queue query has its collection-group index (single field, firestore.indexes.json)', () {
    final j = jsonDecode(File('firestore.indexes.json').readAsStringSync()) as Map<String, dynamic>;
    final o = (j['fieldOverrides'] as List).cast<Map<String, dynamic>>().firstWhere((o) => o['collectionGroup'] == 'photos' && o['fieldPath'] == 'status');
    final scopes = (o['indexes'] as List).cast<Map<String, dynamic>>();
    expect(scopes.any((i) => i['queryScope'] == 'COLLECTION_GROUP' && i['order'] == 'ASCENDING'), isTrue);
    expect(scopes.where((i) => i['queryScope'] == 'COLLECTION').length, 3, reason: 'an override replaces the automatic indexes, so the collection ones are kept');
  });
}
