import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/identity/profile_extras.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/ledger_entry.dart';
import 'package:transport_app/core/models/payout.dart';
import 'package:transport_app/core/security/app_lock.dart';
import 'package:transport_app/core/security/otp_limits.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/services/payout_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/wallet/step_up.dart';

class FakeBackend implements StepUpBackend {
  final String? _phone;
  int sends = 0;
  final List<String> confirmed = [];
  String goodCode = '123456';
  FakeBackend([this._phone = '+919876543210']);

  @override
  String? get phone => _phone;

  @override
  Future<String> send() async {
    sends++;
    return 'vid$sends';
  }

  @override
  Future<void> confirm(String verificationId, String code) async {
    confirmed.add(code);
    if (code != goodCode) throw const StepUpError('invalidOtp');
  }
}

class FakeLock implements AppLockAuthenticator {
  bool available;
  bool pass;
  int asked = 0;
  FakeLock({this.available = true, this.pass = true});

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    asked++;
    return pass;
  }
}

Widget host(Widget home, {AppLanguage lang = AppLanguage.english, double scale = 1.0}) {
  final language = ValueNotifier(lang);
  return LanguageScope(
    notifier: language,
    child: MaterialApp(
      theme: AppTheme.build(Brightness.light),
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true), child: w!),
      home: home,
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FeaturesService.reset();
    StepUp.forget();
    StepUp.now = DateTime.now;
    AppLock.reset();
  });

  void flag(String key, bool on) => FeaturesService.notifier.value = Features(flags: {...FeaturesService.current.flags, key: on});

  group('step-up (a fresh code)', () {
    Future<bool?> run(WidgetTester t, StepUpBackend b) async {
      bool? result;
      await t.pumpWidget(host(Builder(builder: (c) => Scaffold(body: ElevatedButton(onPressed: () async => result = await StepUp.ensure(c, backend: b), child: const Text('go'))))));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      return result;
    }

    testWidgets('flag off: nothing is asked', (t) async {
      final b = FakeBackend();
      bool? r;
      await t.pumpWidget(host(Builder(builder: (c) => Scaffold(body: ElevatedButton(onPressed: () async => r = await StepUp.ensure(c, backend: b), child: const Text('go'))))));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(r, isTrue);
      expect(b.sends, 0);
    });

    testWidgets('flag on: a code is sent, the right code passes, the next 5 minutes are free', (t) async {
      flag(FeatureKey.walletStepUp, true);
      final b = FakeBackend();
      final clock = DateTime(2026, 1, 1, 10);
      StepUp.now = () => clock;
      bool? r;
      await t.pumpWidget(host(Builder(builder: (c) => Scaffold(body: ElevatedButton(onPressed: () async => r = await StepUp.ensure(c, backend: b), child: const Text('go'))))));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(b.sends, 1);
      expect(find.textContaining('98•••••210'), findsOneWidget, reason: 'the number is masked');
      await t.enterText(find.byKey(const ValueKey('stepUpCode')), '123456');
      await t.tap(find.byKey(const ValueKey('stepUpConfirm')));
      await t.pumpAndSettle();
      expect(r, isTrue);
      expect(StepUp.isFresh, isTrue);
      // Inside 5 minutes: no dialog.
      r = null;
      StepUp.now = () => clock.add(const Duration(minutes: 4, seconds: 59));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(r, isTrue);
      expect(b.sends, 1);
      // After 5 minutes: asks again.
      StepUp.now = () => clock.add(const Duration(minutes: 5, seconds: 1));
      expect(StepUp.isFresh, isFalse);
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(b.sends, 2);
      await t.tap(find.byKey(const ValueKey('stepUpCancel')));
      await t.pumpAndSettle();
      expect(r, isFalse, reason: 'cancel means no');
    });

    testWidgets('wrong codes count down and the 5th locks it', (t) async {
      flag(FeatureKey.walletStepUp, true);
      final store = _Mem();
      final limiter = OtpLimiter(store: store);
      final b = FakeBackend('+919000000011');
      await OtpLimiter.instance.recordSuccess('+919000000011'); // start clean
      var r = await run(t, b); // opens the dialog; r is set later
      expect(r, isNull);
      for (var i = 1; i <= 4; i++) {
        await t.enterText(find.byKey(const ValueKey('stepUpCode')), '00000$i');
        await t.tap(find.byKey(const ValueKey('stepUpConfirm')));
        await t.pumpAndSettle();
        expect(find.text(T.get('otpAttemptsLeft', AppLanguage.english).replaceAll('{n}', '${5 - i}')), findsOneWidget, reason: 'try $i');
      }
      await t.enterText(find.byKey(const ValueKey('stepUpCode')), '000009');
      await t.tap(find.byKey(const ValueKey('stepUpConfirm')));
      await t.pumpAndSettle();
      expect(find.text(T.get('otpLockedMin', AppLanguage.english).replaceAll('{m}', '15')), findsOneWidget);
      // Even the right code is refused while locked.
      await t.enterText(find.byKey(const ValueKey('stepUpCode')), '123456');
      await t.tap(find.byKey(const ValueKey('stepUpConfirm')));
      await t.pumpAndSettle();
      expect(b.confirmed.contains('123456'), isFalse);
      expect(StepUp.isFresh, isFalse);
      await OtpLimiter.instance.recordSuccess('+919000000011');
      expect(limiter, isNotNull);
    });

    testWidgets('the dialog fits 360x640 at 2.0x text in Hindi', (t) async {
      flag(FeatureKey.walletStepUp, true);
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(host(Builder(builder: (c) => Scaffold(body: ElevatedButton(onPressed: () => StepUp.ensure(c, backend: FakeBackend()), child: const Text('go')))), lang: AppLanguage.hindi, scale: 2.0));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('app lock', () {
    test('off by default; the flag and the setting are both needed; the phone must be able to check', () async {
      expect(AppLock.locked, isFalse);
      AppLock.authenticator = FakeLock(available: false);
      expect(await AppLock.set(true), isFalse, reason: 'no fingerprint on this phone');
      expect(AppLock.enabled.value, isFalse);
      AppLock.authenticator = FakeLock();
      expect(await AppLock.set(true), isTrue);
      expect(AppLock.locked, isFalse, reason: 'the flag is still off');
      flag(FeatureKey.appLock, true);
      expect(AppLock.locked, isTrue);
      expect(await AppLock.set(false), isTrue);
      expect(AppLock.locked, isFalse);
    });

    test('unlock keeps it open for a minute, then it locks again; a failed prompt stays locked', () async {
      flag(FeatureKey.appLock, true);
      final fake = FakeLock();
      AppLock.authenticator = fake;
      await AppLock.set(true);
      var clock = DateTime(2026, 1, 1, 9);
      AppLock.now = () => clock;
      expect(AppLock.locked, isTrue);
      expect(await AppLock.unlock('x'), isTrue);
      expect(AppLock.locked, isFalse);
      clock = clock.add(const Duration(seconds: 59));
      expect(AppLock.locked, isFalse);
      clock = clock.add(const Duration(seconds: 2));
      expect(AppLock.locked, isTrue);
      fake.pass = false;
      expect(await AppLock.unlock('x'), isFalse);
      expect(AppLock.locked, isTrue);
    });

    testWidgets('the gate shows the child when unlocked and asks for the finger when locked', (t) async {
      flag(FeatureKey.appLock, true);
      final fake = FakeLock();
      AppLock.authenticator = fake;
      await AppLock.set(true);
      await t.pumpWidget(host(const AppLockGate(child: Text('earnings'))));
      await t.pumpAndSettle();
      expect(fake.asked, 1, reason: 'asks as soon as it opens');
      expect(find.text('earnings'), findsOneWidget);
    });

    testWidgets('a failed unlock keeps the screen hidden and offers another try', (t) async {
      flag(FeatureKey.appLock, true);
      final fake = FakeLock(pass: false);
      AppLock.authenticator = fake;
      await AppLock.set(true);
      await t.pumpWidget(host(const AppLockGate(child: Text('earnings'))));
      await t.pumpAndSettle();
      expect(find.text('earnings'), findsNothing);
      expect(find.byKey(const ValueKey('appLockUnlockButton')), findsOneWidget);
      fake.pass = true;
      await t.tap(find.byKey(const ValueKey('appLockUnlockButton')));
      await t.pumpAndSettle();
      expect(find.text('earnings'), findsOneWidget);
    });
  });

  group('payout request writes its counter and an audit line', () {
    test('the counter goes up by one with the amount, the audit line carries no personal data', () async {
      final db = FakeFirebaseFirestore();
      Backend.useFakes(db: db, uid: () => 'd1');
      await db.collection('ledger').doc('B1_trip_earning').set({'driverId': 'd1', 'bookingId': 'B1', 'type': LedgerType.tripEarning, 'amountPaise': 900000});
      final id1 = await PayoutService.request(100000);
      await db.collection('payouts').doc(id1).update({'status': Payout.rejected});
      final id2 = await PayoutService.request(50000);
      final now = DateTime.now().toUtc();
      final c = (await db.collection('payout_counters').doc('d1_${now.year * 10000 + now.month * 100 + now.day}').get()).data()!;
      expect(c['count'], 2);
      expect(c['totalPaise'], 150000);
      expect(c['lastPayoutId'], id2);
      final audits = (await db.collection('audit_events').get()).docs.map((d) => d.data()).toList();
      expect(audits.length, 2);
      expect(audits.every((a) => a['type'] == 'wallet_action' && (a['data'] as Map).keys.toSet().difference({'action', 'amountPaise'}).isEmpty), isTrue);
    });
  });

  group('masking', () {
    test('UPI ids and account numbers show only a little', () {
      expect(maskUpiId('ravi.kumar@okaxis'), isNot(contains('kumar')));
      expect(maskUpiId('ravi.kumar@okaxis'), endsWith('@okaxis'));
      expect(maskUpiId(''), '');
      expect(maskAccountNumber('123456789012'), '••••••••9012');
      expect(maskAccountNumber('12'), '••');
      expect(maskAccountNumber(null), '');
    });
  });

  group('guards: the rules and the screens keep the checks', () {
    final rules = File('firestore.rules').readAsStringSync();
    test('the rules ask for a fresh sign-in and the day counter', () {
      expect(rules.contains('function stepUpOk()'), isTrue);
      expect(rules.contains("auth_time"), isTrue);
      expect(rules.contains('function payoutLimitsOk('), isTrue);
      expect(rules.contains('match /payout_counters/'), isTrue);
      expect(rules.contains('payoutChangeOk()'), isTrue);
    });
    test('the payout flow asks for the fresh code and the profile screen does too', () {
      expect(File('lib/core/wallet/payout_flow.dart').readAsStringSync(), contains('StepUp.ensure'));
      expect(File('lib/core/profile/edit_profile_screen.dart').readAsStringSync(), contains('StepUp.ensure'));
    });
    test('the earnings screens sit behind the app lock', () {
      expect(File('lib/core/wallet/hub/hub_widgets.dart').readAsStringSync(), contains('AppLockGate'));
      expect(File('lib/driver/wallet_screen.dart').readAsStringSync(), contains('AppLockGate'));
    });
    test('profile update writes the audit line for changed payout details', () {
      expect(File('lib/core/services/user_service.dart').readAsStringSync(), contains('payout_details_changed'));
    });
  });
}

class _Mem implements OtpLimitStore {
  final m = <String, String>{};
  @override
  Future<String?> read(String key) async => m[key];
  @override
  Future<void> write(String key, String value) async => m[key] = value;
}
