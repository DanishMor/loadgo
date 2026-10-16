import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/adapters/kyc_adapter.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/identity/kyc_check_service.dart';
import 'package:transport_app/core/identity/kyc_validators.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/widgets/kyc_check_widgets.dart';

class _Spy implements KycVerifier {
  final asked = <(KycKind, String)>[];
  KycStatus answer = KycStatus.verified;
  bool boom = false;
  @override
  Future<KycResult> verify(KycKind kind, String number) async {
    asked.add((kind, number));
    if (boom) throw StateError('x');
    return KycResult(answer);
  }
}

void main() {
  group('contract: every verifier answers one of four statuses and never throws', () {
    final makers = <String, KycVerifier Function()>{
      'fake': FakeKycVerifier.new,
      'sandbox': SandboxKycVerifier.new,
      'default': NoKycVerifier.new,
    };
    makers.forEach((name, make) {
      test(name, () async {
        final v = make();
        for (final k in KycKind.values) {
          for (final n in ['', '  ', 'x', 'MH1220200000001', 'ABCDE1234F', '1234', '123456789012']) {
            final r = await v.verify(k, n);
            expect(KycStatus.values, contains(r.status), reason: '$name ${k.name} "$n"');
          }
        }
      });
    });
  });

  group('sandbox rules (the same as the server)', () {
    const s = SandboxKycVerifier();
    test('the last character decides', () async {
      expect((await s.verify(KycKind.licence, 'mh12 2020 0000001')).status, KycStatus.verified);
      expect((await s.verify(KycKind.licence, 'MH1220200000001')).holderName, 'Sandbox Holder');
      expect((await s.verify(KycKind.pan, 'ABCDE1230Z')).status, KycStatus.mismatch);
      expect((await s.verify(KycKind.rc, 'MH12AB1230')).status, KycStatus.notFound);
      expect((await s.verify(KycKind.gstin, '27ABCDE1234F1Z5')).status, KycStatus.verified);
    });
    test('a bad format is not found; Aadhaar is four digits and never looked up', () async {
      expect((await s.verify(KycKind.pan, 'short')).status, KycStatus.notFound);
      expect((await s.verify(KycKind.aadhaar, '123456789012')).status, KycStatus.notFound, reason: 'a full number is never accepted');
      expect((await s.verify(KycKind.aadhaar, '9012')).status, KycStatus.unavailable);
    });
  });

  group('asking after the papers are saved', () {
    late _Spy spy;
    final kyc = DriverKyc(dlNumber: 'MH12 2020 0000001', dlExpiry: DateTime(2030), rcNumber: 'MH12AB1234', aadhaarLast4: '9012', pan: 'ABCDE1234F');
    setUp(() {
      spy = _Spy();
      KycCheckService.verifier = spy;
    });
    tearDown(FeaturesService.reset);

    test('switch off: nothing is asked', () async {
      expect(await KycCheckService.checkDriver(kyc), 0);
      expect(spy.asked, isEmpty);
    });

    test('switch on: each number once, Aadhaar as its last four digits only', () async {
      FeaturesService.notifier.value = const Features(flags: {FeatureKey.kycVerify: true});
      expect(await KycCheckService.checkDriver(kyc), 4);
      expect(spy.asked.map((e) => e.$1), [KycKind.licence, KycKind.rc, KycKind.pan, KycKind.aadhaar]);
      expect(spy.asked.last.$2, '9012');
      expect(spy.asked.any((e) => e.$2.length > 10 && e.$1 == KycKind.aadhaar), isFalse);
    });

    test('no partner (unavailable) or a crash is calm', () async {
      FeaturesService.notifier.value = const Features(flags: {FeatureKey.kycVerify: true});
      spy.answer = KycStatus.unavailable;
      expect(await KycCheckService.checkDriver(kyc), 0);
      spy.boom = true;
      expect(await KycCheckService.checkDriver(kyc), 0);
    });
  });

  group('admin chips', () {
    setUp(() {
      Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'admin');
      languageNotifier.value = AppLanguage.english;
      FeaturesService.notifier.value = const Features(flags: {FeatureKey.kycVerify: true});
    });
    tearDown(FeaturesService.reset);

    Widget app(Stream<Map<String, dynamic>?> s) => MaterialApp(theme: AppTheme.build(Brightness.light), home: Scaffold(body: PartnerKycChips(uid: 'u1', answers: s)));

    testWidgets('answers become chips; mismatch and not found ask for a look', (tester) async {
      await tester.pumpWidget(app(Stream.value({
        'licence': {'status': 'verified'},
        'pan': {'status': 'mismatch'},
        'rc': {'status': 'not_found'},
        'gstin': {'status': 'unavailable'},
      })));
      await tester.pump();
      expect(find.text('Licence: ID check passed'), findsOneWidget);
      expect(find.text('PAN: name on the record differs. Please look.'), findsOneWidget);
      expect(find.text('RC: not found in the records. Please look.'), findsOneWidget);
      expect(find.textContaining('GSTIN'), findsNothing);
    });

    testWidgets('no answer, a failed read or the switch off: the manual note or nothing', (tester) async {
      await tester.pumpWidget(app(Stream.value(null)));
      await tester.pump();
      expect(find.text('No automatic ID check yet. Please look at the papers yourself.'), findsOneWidget);
      await tester.pumpWidget(app(Stream.error(StateError('denied'))));
      await tester.pump();
      expect(find.text('No automatic ID check yet. Please look at the papers yourself.'), findsOneWidget);
      FeaturesService.notifier.value = const Features(flags: {FeatureKey.kycVerify: false});
      await tester.pumpWidget(app(Stream.value(null)));
      await tester.pump();
      expect(find.textContaining('ID check'), findsNothing);
    });
  });
}
