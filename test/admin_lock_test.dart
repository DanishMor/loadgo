import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_dashboard_screen.dart';
import 'package:transport_app/admin/admin_entry.dart';
import 'package:transport_app/admin/admin_guard.dart';
import 'package:transport_app/core/services/backend.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    db = FakeFirebaseFirestore();
    uid = 'u1';
    Backend.useFakes(db: db, uid: () => uid);
  });

  Widget app(Widget home) => MaterialApp(home: Scaffold(body: home));

  testWidgets('non-admin sees no admin entry, and it appears and goes away live', (tester) async {
    await tester.pumpWidget(app(const AdminEntryTile()));
    await settle(tester);
    expect(find.byKey(const ValueKey('profileAdmin')), findsNothing);
    expect(find.text('Admin panel'), findsNothing);

    await db.collection('admins').doc('u1').set({'by': 'console'});
    await tester.pump(const Duration(milliseconds: 50));
    await settle(tester);
    expect(find.byKey(const ValueKey('profileAdmin')), findsOneWidget);

    await db.collection('admins').doc('u1').delete();
    await tester.pump(const Duration(milliseconds: 50));
    await settle(tester);
    expect(find.byKey(const ValueKey('profileAdmin')), findsNothing);
  });

  testWidgets('signed out: no admin entry', (tester) async {
    uid = null;
    await tester.pumpWidget(app(const AdminEntryTile()));
    await settle(tester);
    expect(find.byKey(const ValueKey('profileAdmin')), findsNothing);
  });

  testWidgets('a non-admin who reaches the admin route is sent out and nothing loads', (tester) async {
    var built = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const ValueKey('go'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AdminGuard(child: Builder(builder: (_) {
                built = true;
                return const Text('SECRET ADMIN SCREEN');
              })),
            )),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('go')));
    await settle(tester);
    expect(built, isFalse);
    expect(find.text('SECRET ADMIN SCREEN'), findsNothing);
    expect(find.byKey(const ValueKey('adminGuardWaiting')), findsNothing, reason: 'route closed');
    expect(find.byKey(const ValueKey('go')), findsOneWidget);
  });

  testWidgets('an admin sees the Admin mode banner; losing the admin doc closes the panel', (tester) async {
    await db.collection('admins').doc('u1').set({'by': 'console'});
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const ValueKey('go'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminGuard(child: AdminDashboardScreen()))),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('go')));
    await settle(tester);
    expect(find.byKey(const ValueKey('adminModeBanner')), findsOneWidget);
    expect(find.text('Admin mode'), findsOneWidget);
    final banner = tester.widget<Container>(find.byKey(const ValueKey('adminModeBanner')));
    expect(banner.color, adminModeColor);

    await db.collection('admins').doc('u1').delete();
    await tester.pump(const Duration(milliseconds: 50));
    await settle(tester);
    expect(find.byKey(const ValueKey('adminModeBanner')), findsNothing);
    expect(find.byKey(const ValueKey('go')), findsOneWidget);
  });

  test('admin screens are referenced only from lib/admin and the one registered entry', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final p = f.path;
      if (!p.endsWith('.dart') || p.startsWith('lib/admin/') || p.contains('/l10n/')) continue;
      final s = f.readAsStringSync();
      if (s.contains("'adminPanel'") || s.contains('AdminDashboardScreen') || s.contains('adminModeBanner')) offenders.add(p);
    }
    expect(offenders, isEmpty, reason: 'admin text and screens stay inside lib/admin');
  });
}
