import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/adapters/adapters.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/features/kill_switches.dart';
import 'package:transport_app/core/insurance/insurance_request.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/widgets/ds/app_button.dart';

class _Counting implements InsuranceQuotes {
  int calls = 0;
  @override
  Future<ConnectResult> requestQuote({required int cargoValuePaise, required String goods, required String bookingId}) async {
    calls++;
    return const ConnectResult.ok('q1');
  }
}

/// E32: cargo insurance quote request behind the legal gate.
void main() {
  setUp(() {
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'c1');
    FeaturesService.reset();
    languageNotifier.value = AppLanguage.english;
  });
  tearDown(FeaturesService.reset);

  CostGuard guard() => CostGuard(const CostCaps(daily: 100, perUser: 3), killed: () => false);

  test('outcomes: not connected by default, sent through a partner, invalid input, the per-user cap', () async {
    expect(await requestCargoQuote(bookingId: 'B1', goods: 'Cotton', valuePaise: 5000000, guard: guard()), InsuranceOutcome.notConnected);
    final g = guard();
    final p = _Counting();
    for (var i = 0; i < 3; i++) {
      expect(await requestCargoQuote(bookingId: 'B1', goods: 'Cotton', valuePaise: 5000000, via: p, guard: g), InsuranceOutcome.sent);
    }
    expect(await requestCargoQuote(bookingId: 'B1', goods: 'Cotton', valuePaise: 5000000, via: p, guard: g), InsuranceOutcome.capped);
    expect(p.calls, 3);
    expect(await requestCargoQuote(bookingId: 'B1', goods: ' ', valuePaise: 5000000, via: p, guard: guard()), InsuranceOutcome.invalid);
    expect(await requestCargoQuote(bookingId: 'B1', goods: 'X', valuePaise: InsuranceRequests.maxValuePaise + 1, via: p, guard: guard()), InsuranceOutcome.invalid);
  });

  test('the gate is a legal flag, OFF in every mode, and in the costs kill group', () {
    final spec = Features.registry.firstWhere((s) => s.key == FeatureKey.legalGateInsurance);
    expect((spec.group, spec.pilotOn, spec.normalOn), (FeatureGroup.legal, false, false));
    expect(KillSwitches.byId('costs')!.flags, contains(FeatureKey.legalGateInsurance));
  });

  test('the words promise no cover and never call it a sale (copy guard)', () {
    final src = File('lib/core/l10n/pricing_v3_strings.dart').readAsStringSync();
    final en = RegExp(r"'(ins\w+)': \['([^']*)'").allMatches(src).map((m) => m.group(2)!.toLowerCase()).join(' ');
    for (final banned in ['you are covered', 'guaranteed', 'buy insurance', 'policy issued', 'insured now']) {
      expect(en.contains(banned), isFalse, reason: banned);
    }
    expect(en, contains('does not sell insurance'));
  });

  final booking = Booking.fromMap('B1', {'status': 'in_transit', 'cargoType': 'Cotton bales', 'pickup': 'Pune', 'drop': 'Surat', 'customerId': 'c1'});
  Widget host(Widget child, {AppLanguage lang = AppLanguage.english, Brightness b = Brightness.light, double scale = 1}) => LanguageScope(
        notifier: ValueNotifier(lang),
        child: MaterialApp(
          theme: AppTheme.build(b, style: ThemeStyle.signature),
          builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: Directionality(textDirection: lang.textDirection, child: w!)),
          home: Scaffold(body: child),
        ),
      );

  testWidgets('card only behind the gate; Send waits for the tick; the outcome is told', (t) async {
    await t.pumpWidget(host(InsuranceRequestCard(booking: booking)));
    expect(find.byKey(const ValueKey('insCard')), findsNothing);
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.legalGateInsurance: true});
    await t.pumpWidget(host(InsuranceRequestCard(key: const ValueKey(2), booking: booking)));
    await t.tap(find.byKey(const ValueKey('insCard')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('insDisclaimer')), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('insValue')), '50000');
    expect(t.widget<AppButton>(find.byKey(const ValueKey('insSend'))).onPressed, isNull);
    await t.tap(find.byKey(const ValueKey('insUnderstood')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('insSend')));
    await t.pumpAndSettle();
    expect(find.text(T.get('insOut_notConnected', AppLanguage.english)), findsOneWidget);
  });

  for (final (lang, b) in [(AppLanguage.hindi, Brightness.light), (AppLanguage.urdu, Brightness.dark), (AppLanguage.tamil, Brightness.dark)]) {
    testWidgets('no overflow at 320 dp and 2.0x: ${lang.name} ${b.name}', (t) async {
      t.view.physicalSize = const Size(320, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      FeaturesService.notifier.value = const Features(flags: {FeatureKey.legalGateInsurance: true});
      await t.pumpWidget(host(InsuranceRequestCard(booking: booking), lang: lang, b: b, scale: 2));
      await t.tap(find.byKey(const ValueKey('insCard')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}
