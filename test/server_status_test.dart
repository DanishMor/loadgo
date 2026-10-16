import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_health_screen.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/server_actions.dart';
import 'package:transport_app/core/theme/app_theme.dart';

class FakeGateway implements ServerGateway {
  Object? error;
  Map<String, dynamic> answer = {'ok': true, 'switches': {'a': true, 'b': false, 'c': true}};
  @override
  Future<Map<String, dynamic>> call(String name, Map<String, Object?> data) async {
    if (error != null) throw error!;
    return answer;
  }
}

Widget host(Widget w) => LanguageScope(
      notifier: ValueNotifier(AppLanguage.english),
      child: MaterialApp(theme: AppTheme.build(Brightness.light), home: Scaffold(body: SingleChildScrollView(child: w))),
    );

/// F33: "Is the server there?"
void main() {
  tearDown(() => ServerActions.gateway = const CloudServerGateway());

  test('status counts the switches that are on; no answer or an error is null, never a crash', () async {
    final g = FakeGateway();
    ServerActions.gateway = g;
    final s = await ServerActions.status();
    expect(s!.on, 2);
    expect(s.switches.length, 3);
    g.answer = {'ok': false};
    expect(await ServerActions.status(), isNull);
    g.error = Exception('not deployed');
    expect(await ServerActions.status(), isNull);
  });

  testWidgets('the card says nothing until asked, then shows up or down', (t) async {
    final g = FakeGateway();
    ServerActions.gateway = g;
    await t.pumpWidget(host(const ServerStatusCard()));
    expect(find.byKey(const ValueKey('serverUp')), findsNothing);
    expect(find.byKey(const ValueKey('serverDown')), findsNothing);
    await t.tap(find.byKey(const ValueKey('serverCheck')));
    await t.pump();
    await t.pump();
    expect(find.byKey(const ValueKey('serverUp')), findsOneWidget);
    expect(find.text('2 / 3 server switches on'), findsOneWidget);

    g.error = Exception('down');
    await t.tap(find.byKey(const ValueKey('serverCheck')));
    await t.pump();
    await t.pump();
    expect(find.byKey(const ValueKey('serverDown')), findsOneWidget);
    expect(find.byKey(const ValueKey('serverUp')), findsNothing);
  });

  testWidgets('fits 360x640 at 2.0x text in Urdu, dark', (t) async {
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    ServerActions.gateway = FakeGateway()..error = Exception('x');
    await t.pumpWidget(LanguageScope(
      notifier: ValueNotifier(AppLanguage.urdu),
      child: MaterialApp(
        theme: AppTheme.build(Brightness.dark),
        builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(2.0)), child: Directionality(textDirection: TextDirection.rtl, child: child!)),
        home: const Scaffold(body: SingleChildScrollView(child: ServerStatusCard())),
      ),
    ));
    await t.tap(find.byKey(const ValueKey('serverCheck')));
    await t.pump();
    await t.pump();
    expect(t.takeException(), isNull);
  });
}
