import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/services/auth_helpers.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/language_store.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/auth/otp_verification_screen.dart';
void main() {
  group('authErrorKey', () {
    test('maps Firebase codes to translated keys', () {
      expect(authErrorKey('invalid-phone-number'), 'authErrInvalidPhone');
      expect(authErrorKey('invalid-verification-code'), 'invalidOtp');
      expect(authErrorKey('session-expired'), 'otpExpired');
      expect(authErrorKey('too-many-requests'), 'authErrTooMany');
      expect(authErrorKey('quota-exceeded'), 'authErrQuota');
      expect(authErrorKey('network-request-failed'), 'authErrNetwork');
      expect(authErrorKey('captcha-check-failed'), 'authErrCaptcha');
      expect(authErrorKey('user-disabled'), 'authErrDisabled');
      expect(authErrorKey('something-new'), 'otpFailed');
    });

    test('every mapped key is translated', () {
      for (final code in ['invalid-phone-number', 'too-many-requests', 'quota-exceeded', 'network-request-failed',
          'captcha-check-failed', 'user-disabled', 'session-expired', 'invalid-verification-code', 'x']) {
        expect(T.data.containsKey(authErrorKey(code)), isTrue, reason: code);
      }
    });
  });

  test('maskPhone hides the middle digits', () {
    expect(maskPhone('+919876543210'), '+91 98•••••210');
    expect(maskPhone('9876543210'), '98•••••210');
    expect(maskPhone('+91 98765 43210'), '+91 98•••••210');
    expect(maskPhone('123'), '123');
    expect(maskPhone(null), '');
  });

  group('language persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      languageNotifier.value = AppLanguage.english;
    });

    test('saves on device and on the signed-in profile', () async {
      final db = FakeFirebaseFirestore();
      Backend.useFakes(db: db, uid: () => 'u1');
      await setAppLanguage(AppLanguage.tamil);
      expect(await LanguageStore.loadLocal(), 'tamil');
      expect((await db.collection('users').doc('u1').get()).data()!['language'], 'tamil');
    });

    test('after login the profile language wins', () async {
      final db = FakeFirebaseFirestore();
      Backend.useFakes(db: db, uid: () => 'u2');
      await db.collection('users').doc('u2').set({'language': 'marathi'});
      await syncLanguageAfterLogin();
      expect(languageNotifier.value, AppLanguage.marathi);
      expect(await LanguageStore.loadLocal(), 'marathi');
    });

    test('unknown names are ignored', () {
      applyLanguageName('klingon');
      expect(languageNotifier.value, AppLanguage.english);
    });
  });

  testWidgets('OTP screen: masked number, digits only, 60s resend timer', (tester) async {
    languageNotifier.value = AppLanguage.english;
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: const MaterialApp(home: OtpVerificationScreen(phoneNumber: '9876543210', verificationId: 'v1')),
    ));
    expect(find.textContaining('+91 98•••••210'), findsOneWidget);
    expect(find.text('Resend OTP in 60s'), findsOneWidget);
    expect(tester.widget<TextButton>(find.byKey(const Key('resendOtp'))).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '12ab34');
    expect(find.text('1234'), findsOneWidget);

    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Resend OTP in 30s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    expect(tester.widget<TextButton>(find.byKey(const Key('resendOtp'))).onPressed, isNotNull);
  });

}
