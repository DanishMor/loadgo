import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_health_screen.dart';
import 'package:transport_app/admin/admin_uploads.dart';
import 'package:transport_app/admin/admin_web_shell.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/photos/photo_service.dart';
import 'package:transport_app/core/photos/photo_widgets.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/ledger_entry.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/wallet/hub/hub_screens.dart';

class FakeStorage implements StorageGateway {
  final files = <String, Uint8List>{};
  @override
  Future<void> put(String path, Uint8List bytes, String contentType, {void Function(double)? onProgress}) async => files[path] = bytes;
  @override
  Future<Uint8List?> get(String path, {int maxSize = 5 * 1024 * 1024}) async => files[path];
  @override
  Future<void> delete(String path) async => files.remove(path);
}

class Picker implements PhotoPickerSource {
  @override
  Future<PickedPhoto?> pick(bool camera) async => null;
}

Widget host(Widget w, Brightness b, {AppLanguage lang = AppLanguage.english}) => LanguageScope(
      notifier: ValueNotifier(lang),
      child: MaterialApp(theme: AppTheme.build(b), home: Scaffold(body: SingleChildScrollView(child: w))),
    );

/// F41: spoken labels, 48 dp targets and contrast on the screens added in Part 2.
void main() {
  setUp(() {
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'u1');
    PhotoService.gateway = FakeStorage();
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.photoUploads: true});
  });
  tearDown(() {
    PhotoService.gateway = const FirebaseStorageGateway();
    FeaturesService.reset();
  });

  for (final b in Brightness.values) {
    Future<void> checks(WidgetTester t) async {
      await expectLater(t, meetsGuideline(androidTapTargetGuideline));
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(t, meetsGuideline(textContrastGuideline));
    }

    testWidgets('photo card: ${b.name}', (t) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(host(
        Column(children: [
          PhotoAttach(target: const PhotoTarget(PhotoKind.licence), picker: Picker()),
          const PhotoAttach(target: PhotoTarget(PhotoKind.truck, vehicleId: 'v1', view: 'front'), titleKey: 'photoView_front'),
        ]),
        b,
      ));
      await t.pumpAndSettle();
      await checks(t);
      h.dispose();
    });

    testWidgets('admin papers button: ${b.name}', (t) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(host(const AdminUploads(uid: 'd1'), b));
      await t.pumpAndSettle();
      await checks(t);
      h.dispose();
    });

    testWidgets('server status card: ${b.name}', (t) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(host(const ServerStatusCard(), b));
      await t.pumpAndSettle();
      await checks(t);
      h.dispose();
    });

    testWidgets('not-an-admin page: ${b.name}', (t) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(LanguageScope(
        notifier: ValueNotifier(AppLanguage.english),
        child: MaterialApp(theme: AppTheme.build(b), home: AdminWebShell(signedIn: Stream.value(true), adminStream: Stream.value(false), child: const SizedBox())),
      ));
      await t.pump();
      await t.pump();
      await checks(t);
      h.dispose();
    });
  }

  for (final b in Brightness.values) {
    testWidgets('driver earnings hub: ${b.name}', (t) async {
      final h = t.ensureSemantics();
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(LanguageScope(
        notifier: ValueNotifier(AppLanguage.english),
        child: MaterialApp(
          theme: AppTheme.build(b),
          home: DriverHubScreen(
            ledger: () => Stream.value([LedgerEntry(id: 'B1_trip_earning', driverId: 'd1', bookingId: 'B1', type: LedgerType.tripEarning, amountPaise: 100000, createdAt: DateTime(2026, 10, 14, 9))]),
            bookings: () => Stream.value(const <Booking>[]),
            payouts: () => Stream.value(const []),
            now: () => DateTime(2026, 10, 14, 15),
          ),
        ),
      ));
      await t.pumpAndSettle();
      await expectLater(t, meetsGuideline(androidTapTargetGuideline));
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(t, meetsGuideline(textContrastGuideline));
      h.dispose();
    });
  }

  testWidgets('a stored photo is announced to a screen reader', (t) async {
    final h = t.ensureSemantics();
    final s = FakeStorage()..files['users/u1/docs/rc/a.jpg'] = Uint8List.fromList(_png);
    PhotoService.gateway = s;
    PhotoImage.clearCache();
    await t.pumpWidget(host(const PhotoImage('users/u1/docs/rc/a.jpg'), Brightness.light));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.bySemanticsLabel(RegExp('photo', caseSensitive: false)), findsWidgets);
    h.dispose();
  });
}

const _png = [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xff, 0xff, 0x3f, 0x00, 0x05, 0xfe, 0x02, 0xfe, 0xa7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
];
