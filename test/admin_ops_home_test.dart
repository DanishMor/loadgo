import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_ops_home_screen.dart';
import 'package:transport_app/core/admin/ops_queues.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';

/// E24: the admin ops home.
void main() {
  setUp(FeaturesService.reset);
  tearDown(FeaturesService.reset);

  const busy = OpsQueues(kyc: 3, photos: 50, claims: 0, tickets: 2, sos: 1, unfilledLoads: 0, openLoads: 7, runningTrips: 4, capped: {'photos'});
  const quiet = OpsQueues(kyc: 0, photos: -1, claims: 0, tickets: 0, sos: 0, unfilledLoads: 0, openLoads: 2, runningTrips: 1);

  test('labels: counts, capped with a plus, unreadable as a dash; urgent and waiting', () {
    expect(busy.label('photos'), '50+');
    expect(busy.label('kyc'), '3');
    expect(quiet.label('photos'), '–');
    expect(busy.urgent, isTrue);
    expect(quiet.urgent, isFalse);
    expect(quiet.anyWaiting, isFalse);
    expect(const OpsQueues(kyc: 1, photos: 0, claims: 0, tickets: 0, sos: 0, unfilledLoads: 0, openLoads: 0, runningTrips: 0).anyWaiting, isTrue);
  });

  const screens = {
    'adminSos': Text('sos screen'),
    'adminDispatch': Text('dispatch screen'),
    'driverVerification': Text('kyc screen'),
    'adminVehiclePhotos': Text('photos screen'),
    'adminDisputes': Text('claims screen'),
    'adminTickets': Text('tickets screen'),
    'adminDispatchMonitor': Text('monitor screen'),
    'adminFeatures': Text('features screen'),
  };

  Widget host(Widget child, {AppLanguage lang = AppLanguage.english, Brightness b = Brightness.light, double scale = 1}) => LanguageScope(
        notifier: ValueNotifier(lang),
        child: MaterialApp(
          theme: AppTheme.build(b, style: ThemeStyle.signature),
          builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: Directionality(textDirection: lang.textDirection, child: w!)),
          home: child,
        ),
      );

  testWidgets('super: every queue with its count, a tap opens it; kill shortcuts confirm then save the group off', (t) async {
    t.view.physicalSize = const Size(400, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final saved = <Features>[];
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.dispatchV2: true});
    await t.pumpWidget(host(AdminOpsHomeScreen(screens: screens, role: () async => 'super', load: () async => busy, save: (f) async => saved.add(f))));
    expect(find.byKey(const ValueKey('opsSkeleton')), findsOneWidget);
    await t.pumpAndSettle();
    expect(find.text(T.get('opsUrgent', AppLanguage.english)), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const ValueKey('opsN_photos'))).data, '50+');
    expect(t.widget<Text>(find.byKey(const ValueKey('opsN_sos'))).data, '1');
    await t.tap(find.byKey(const ValueKey('opsKill_dispatch')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('opsKillYes')));
    await t.pumpAndSettle();
    expect(saved.single.isOn(FeatureKey.dispatchV2), isFalse);
    await t.tap(find.byKey(const ValueKey('opsQ_kyc')));
    await t.pumpAndSettle();
    expect(find.text('kyc screen'), findsOneWidget);
  });

  testWidgets('support: only its own queues, no kill switches; quiet when nothing waits', (t) async {
    await t.pumpWidget(host(AdminOpsHomeScreen(screens: screens, role: () async => 'support', load: () async => quiet)));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('opsQ_sos')), findsOneWidget);
    expect(find.byKey(const ValueKey('opsQ_tickets')), findsOneWidget);
    expect(find.byKey(const ValueKey('opsQ_kyc')), findsNothing);
    expect(find.byKey(const ValueKey('opsQ_unfilled')), findsNothing);
    expect(find.byKey(const ValueKey('opsKill_money')), findsNothing);
    expect(find.text(T.get('opsQuiet', AppLanguage.english)), findsOneWidget);
  });

  testWidgets('a failed count offers retry; Refresh counts again', (t) async {
    var calls = 0;
    await t.pumpWidget(host(AdminOpsHomeScreen(
      screens: screens,
      role: () async => 'super',
      load: () async {
        calls++;
        if (calls == 1) throw StateError('x');
        return quiet;
      },
    )));
    await t.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, T.get('retry', AppLanguage.english)), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('opsRefresh')));
    await t.pumpAndSettle();
    expect(calls, 2);
    expect(find.byKey(const ValueKey('opsBanner')), findsOneWidget);
  });

  for (final (lang, b) in [(AppLanguage.hindi, Brightness.light), (AppLanguage.urdu, Brightness.dark), (AppLanguage.tamil, Brightness.dark)]) {
    testWidgets('no overflow at 320 dp and 2.0x: ${lang.name} ${b.name}', (t) async {
      t.view.physicalSize = const Size(320, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(host(AdminOpsHomeScreen(screens: screens, role: () async => 'super', load: () async => busy), lang: lang, b: b, scale: 2));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('opsBanner')), findsOneWidget);
    });
  }
}
