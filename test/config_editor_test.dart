import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_config_screen.dart';
import 'package:transport_app/core/admin/config_schema.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/admin_console_service.dart';
import 'package:transport_app/core/services/backend.dart';

import 'test_utils.dart';

/// MASTER-6 Task 13: config editor checks, diff preview and rollback.
void main() {
  List<String> bad(String doc, Map<String, dynamic> d, {Map<String, dynamic>? before}) => [for (final i in ConfigSchema.validate(doc, d, before: before)) '${i.key}:${i.path}'];

  test('pricing: no negatives, percents up to 100, whole paise in rate cards, kinds may not change', () {
    expect(bad('pricing', {'platformFeePercent': 7, 'categories': {'lcv': {'baseFare': 50000}}}), isEmpty);
    expect(bad('pricing', {'platformFeePercent': -1}), ['cfgOutOfRange:platformFeePercent']);
    expect(bad('pricing', {'gstPercent': 120}), ['cfgOutOfRange:gstPercent']);
    expect(bad('pricing', {'categories': {'lcv': {'baseFare': 500.5}}}), ['cfgNeedWhole:categories.lcv.baseFare']);
    expect(bad('pricing', {'roadFactor': 1.3}), isEmpty); // not a rate card
    expect(bad('pricing', {'platformFeePercent': '7'}, before: {'platformFeePercent': 5}), ['cfgKindChanged:platformFeePercent']);
    expect(bad('pricing', {'platformFeePercent': 8}, before: {'platformFeePercent': 5}), isEmpty);
  });

  test('vehicle types, risk, support, announcement and pilot', () {
    expect(bad('vehicle_types', {'types': []}), ['cfgNeedList:types']);
    expect(bad('vehicle_types', {'types': [{'id': 'Mini', 'name': 'Mini', 'minTons': 1, 'maxTons': 2}]}), isEmpty);
    expect(bad('vehicle_types', {'types': [{'id': 'Mini', 'name': 'Mini', 'minTons': 3, 'maxTons': 2}]}), ['cfgOutOfRange:types[0].maxTons']);
    expect(bad('risk', {'reviewScore': 60, 'holdScore': 40}), ['cfgOutOfRange:holdScore']);
    expect(bad('risk', {'reviewScore': 30, 'holdScore': 60}), isEmpty);
    expect(bad('support', {'phone': '+91 98765 43210', 'hours': '9-6'}), isEmpty);
    expect(bad('support', {'phone': 'call me', 'hours': ''}), ['cfgNeedText:phone']);
    expect(bad('announcement', {'text': 'x', 'level': 'loud', 'until': '12/11/2026', 'roles': ['admin']}), ['cfgOutOfRange:level', 'cfgNeedDate:until', 'cfgOutOfRange:roles']);
    expect(bad('announcement', {'text': 'x', 'level': 'info', 'until': '2026-11-12', 'roles': ['driver']}), isEmpty);
    expect(bad('pilot', {'inviteOnly': 'yes', 'openCities': ['Delhi']}), ['cfgNeedBool:inviteOnly']);
    expect(bad('pilot', {'inviteOnly': true, 'openCities': [for (var i = 0; i < 51; i++) 'C$i']}), ['cfgNeedList:openCities']);
  });

  test('generic limits: depth, size, NaN, long text', () {
    Map<String, dynamic> deep = {'a': 1};
    for (var i = 0; i < 8; i++) {
      deep = {'n': deep};
    }
    expect(bad('other', deep), ['cfgTooDeep:']);
    expect(bad('other', {'x': double.nan}), ['cfgBadNumber:x']);
    expect(bad('other', {'x': 'a' * 2001}), ['cfgTextTooLong:x']);
    expect(bad('other', {'list': List.generate(2001, (i) => i)}), contains('cfgTooBig:'));
  });

  test('diff: changed, added, removed leaves by path; same value is not a change; updatedAt ignored', () {
    final d = ConfigSchema.diff({'a': 1, 'b': {'c': 'x', 'd': [1, 2]}, 'gone': true, 'updatedAt': 5}, {'a': 2, 'b': {'c': 'x', 'd': [1, 3]}, 'new': 'y'});
    expect([for (final c in d) '${c.path}|${c.before}|${c.after}'], ['a|1|2', 'b.d|[1,2]|[1,3]', 'gone|true|null', 'new|null|y']);
    expect(ConfigSchema.diff({'a': 1}, {'a': 1}), isEmpty);
    expect(ConfigSchema.diff(null, {'a': 1}).single.before, isNull);
  });

  test('saving keeps the replaced version; history lists newest first; first save has none', () async {
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'admin1');
    await AdminConsoleService.writeConfig('support', {'phone': '1', 'hours': 'a'});
    expect(await AdminConsoleService.configHistory('support'), isEmpty);
    await AdminConsoleService.writeConfig('support', {'phone': '2', 'hours': 'a'});
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await AdminConsoleService.writeConfig('support', {'phone': '3', 'hours': 'a'});
    final h = await AdminConsoleService.configHistory('support');
    expect(h.map((v) => v.data['phone']), ['2', '1']);
    expect(h.first.by, 'admin1');
    await AdminConsoleService.writeConfig('pricing', {'x': 1});
    expect((await AdminConsoleService.configHistory('support')).length, 2);
  });

  Future<FakeFirebaseFirestore> open(WidgetTester tester, String doc, Map<String, dynamic>? existing) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'admin1');
    if (existing != null) await db.collection('config').doc(doc).set(existing);
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: ConfigEditorScreen(docId: doc, titleKey: 'adminSupportConfig'))));
    await settle(tester);
    return db;
  }

  testWidgets('a bad value shows what to fix and saves nothing', (tester) async {
    final db = await open(tester, 'support', {'phone': '100', 'hours': '9-6'});
    await tester.enterText(find.byKey(const ValueKey('configJson')), jsonEncode({'phone': 'call me', 'hours': '9-6'}));
    await tester.tap(find.byKey(const ValueKey('saveConfig')));
    await settle(tester);
    expect(find.text('Fix these first'), findsOneWidget);
    expect(find.textContaining('phone: Wrong kind of value'), findsOneWidget);
    expect((await db.collection('config').doc('support').get())['phone'], '100');
  });

  testWidgets('a good change shows the diff, saves on confirm, and the old version can be loaded back', (tester) async {
    final db = await open(tester, 'support', {'phone': '100', 'hours': '9-6'});
    await tester.enterText(find.byKey(const ValueKey('configJson')), jsonEncode({'phone': '200', 'hours': '9-6'}));
    await tester.tap(find.byKey(const ValueKey('saveConfig')));
    await settle(tester);
    expect(find.text('Review 1 changes'), findsOneWidget);
    expect(find.textContaining('100  →  200'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cfgConfirm')));
    await settle(tester);
    expect((await db.collection('config').doc('support').get())['phone'], '200');
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    // rollback: open the history, pick the version, it is only loaded into the editor
    await tester.tap(find.byKey(const ValueKey('cfgHistoryButton')));
    await settle(tester);
    final tile = find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('cfgVersion_'));
    expect(tile, findsOneWidget);
    await tester.tap(tile);
    await settle(tester);
    expect(find.textContaining('Version loaded'), findsOneWidget);
    expect((await db.collection('config').doc('support').get())['phone'], '200'); // not saved yet
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('saveConfig')));
    await settle(tester);
    expect(find.text('Review 1 changes'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cfgConfirm')));
    await settle(tester);
    expect((await db.collection('config').doc('support').get())['phone'], '100');
  });

  testWidgets('no change says so; an empty history says so', (tester) async {
    await open(tester, 'support', {'phone': '100', 'hours': '9-6'});
    await tester.tap(find.byKey(const ValueKey('saveConfig')));
    await settle(tester);
    expect(find.text('Nothing changed.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cfgHistoryButton')));
    await settle(tester);
    expect(find.byKey(const ValueKey('cfgHistoryEmpty')), findsOneWidget);
  });
}
