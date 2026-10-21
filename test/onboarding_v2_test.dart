import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/auth/driver_onboarding_card.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';

import 'test_utils.dart';

/// U34: onboarding with each step and document in words, and a rejection with its reason.
void main() {
  setUp(() {
    FeaturesService.reset();
    languageNotifier.value = AppLanguage.english;
  });
  tearDown(FeaturesService.reset);

  Map<String, dynamic> user({String status = 'pending', bool consent = true, Map<String, dynamic>? meta, bool allDocs = true}) => {
        'driverProfileComplete': true,
        'locationConsentAsked': consent,
        'kycComplete': allDocs,
        'verificationStatus': status,
        'verified': status == 'approved',
        'driverKyc': {'dlNumber': 'MH1220190001234', if (allDocs) ...{'dlExpiry': Timestamp.fromDate(DateTime(2031)), 'rcNumber': 'MH12AB1234', 'aadhaarLast4': '1234', 'pan': 'ABCDE1234F'}},
        'verificationMeta': ?meta,
      };

  Future<void> show(WidgetTester t, Map<String, dynamic> u, {Brightness b = Brightness.light, double scale = 1}) async {
    t.view.physicalSize = const Size(360 * 2, 900 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(
        theme: AppTheme.build(b),
        builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
        home: Scaffold(body: SingleChildScrollView(child: DriverOnboardingCard(user: u))),
      ),
    ));
    await settle(t);
  }

  testWidgets('every step says Done, Do this next or Later; documents say Added or Missing', (t) async {
    await show(t, user(consent: false, allDocs: false));
    expect(find.text('Your set-up: 1 of 4 steps done'), findsOneWidget);
    String label(String step) => (t.widget(find.descendant(of: find.byKey(ValueKey('obState_$step')), matching: find.byType(Text))) as Text).data!;
    expect(label('profile'), 'Done');
    expect(label('consent'), 'Do this next');
    expect(label('documents'), 'Later');
    expect(find.text('Added'), findsWidgets);
    expect(find.text('Missing'), findsWidgets);
  });

  testWidgets('when only the team check is left the chip says Waiting for our team, not Do this next (Z7)', (t) async {
    await show(t, user());
    final review = (t.widget(find.descendant(of: find.byKey(const ValueKey('obState_review')), matching: find.byType(Text))) as Text).data!;
    expect(review, 'Waiting for our team');
  });

  testWidgets('a rejection shows why, the note, and a big send-again button', (t) async {
    await show(t, user(status: 'rejected', meta: {'reason': 'licence_expired', 'note': 'Valid till 2023'}));
    expect(find.byKey(const ValueKey('obRejected')), findsOneWidget);
    expect(find.text('Why it was not approved'), findsOneWidget);
    expect(find.byKey(const ValueKey('obReason')), findsOneWidget);
    expect(find.text('Valid till 2023'), findsOneWidget);
    expect(find.byKey(const ValueKey('obResubmit')), findsOneWidget);
  });

  testWidgets('dark, 2.0x text and Hindi: no overflow', (t) async {
    languageNotifier.value = AppLanguage.hindi;
    await show(t, user(status: 'rejected', meta: {'reason': 'rc_mismatch', 'note': 'x'}), b: Brightness.dark, scale: 2);
    expect(t.takeException(), isNull);
  });

  testWidgets('uiV2 off: the old card, without state words', (t) async {
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.uiV2: false});
    await show(t, user());
    expect(find.byKey(const ValueKey('obState_profile')), findsNothing);
    expect(find.byKey(const ValueKey('obBar')), findsOneWidget);
  });
}
