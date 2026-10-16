import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_web_shell.dart';
import 'package:transport_app/core/app_mode.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/theme/app_theme.dart';

Widget host(Widget w) => LanguageScope(
      notifier: ValueNotifier(AppLanguage.english),
      child: MaterialApp(theme: AppTheme.build(Brightness.light), home: w),
    );

/// F32: the admin-only web shell.
void main() {
  testWidgets('signed out: the normal pages show', (t) async {
    await t.pumpWidget(host(AdminWebShell(signedIn: Stream.value(false), adminStream: Stream.value(false), child: const Text('login page'))));
    await t.pump();
    expect(find.text('login page'), findsOneWidget);
  });

  testWidgets('signed in but not an admin: a calm sentence, no other screen', (t) async {
    await t.pumpWidget(host(AdminWebShell(signedIn: Stream.value(true), adminStream: Stream.value(false), child: const Text('login page'))));
    await t.pump();
    await t.pump();
    expect(find.byKey(const ValueKey('adminWebNotAdmin')), findsOneWidget);
    expect(find.text('login page'), findsNothing);
    expect(find.byKey(const ValueKey('adminWebSignOut')), findsOneWidget);
  });

  testWidgets('signed in, answer not known yet: waiting, nothing loads', (t) async {
    final never = StreamController<bool>();
    addTearDown(never.close);
    await t.pumpWidget(host(AdminWebShell(signedIn: Stream.value(true), adminStream: never.stream, child: const Text('login page'))));
    await t.pump();
    expect(find.byKey(const ValueKey('adminWebWaiting')), findsOneWidget);
  });

  test('the normal build is not admin-only; the build option is documented', () {
    expect(AppMode.isAdminOnly, isFalse);
    final doc = File('docs/ADMIN_WEB.md').readAsStringSync();
    expect(doc, contains('APP_MODE=admin'));
    expect(doc, contains('firebase deploy --only hosting:admin'));
  });
}
