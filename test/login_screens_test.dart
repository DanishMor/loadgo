import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/auth/customer_login_screen.dart';
import 'package:transport_app/auth/driver_login_screen.dart';
import 'package:transport_app/auth/login_widgets.dart';
import 'package:transport_app/auth/otp_verification_screen.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/theme/design_tokens.dart';
import 'package:transport_app/core/widgets/ds/app_button.dart';
import 'package:transport_app/core/widgets/ds/haptics.dart';
import 'package:transport_app/core/widgets/ds/otp_field.dart';

/// L17: login and OTP screens on the design system.
Widget host(Widget screen, {AppLanguage lang = AppLanguage.english, Brightness b = Brightness.light, double scale = 1.0}) {
  final language = ValueNotifier(lang);
  final dir = (lang == AppLanguage.urdu || lang == AppLanguage.kashmiri) ? TextDirection.rtl : TextDirection.ltr;
  return LanguageScope(
    notifier: language,
    child: MaterialApp(
      theme: AppTheme.build(b),
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
        child: Directionality(textDirection: dir, child: w!),
      ),
      home: screen,
    ),
  );
}

/// A screen opened from another one, so it has a back button.
Widget pushed(Widget screen, {AppLanguage lang = AppLanguage.english}) => host(
      Builder(builder: (c) => Scaffold(body: Center(child: ElevatedButton(onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => screen)), child: const Text('open'))))),
      lang: lang,
    );

void main() {
  setUp(() => Haptics.enabled.value = true);

  group('PhoneFormField.validate', () {
    testWidgets('empty, short, wrong first digit, too long, spaces', (t) async {
      late BuildContext ctx;
      await t.pumpWidget(host(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      String? v(String? s) => PhoneFormField.validate(ctx, s);
      expect(v(null), T.get('required', AppLanguage.english));
      expect(v(''), isNotNull);
      expect(v('  '), isNotNull);
      expect(v('12345'), isNotNull);
      expect(v('5876543210'), isNotNull, reason: 'Indian mobiles start with 6 to 9');
      expect(v('98765432101'), isNotNull);
      expect(v('9876543210'), isNull);
      expect(v(' 6000000000 '), isNull);
      expect(v('9999999999'), isNull);
    });
  });

  group('customer login', () {
    testWidgets('header, +91 field, continue button, or-divider, Google button and terms', (t) async {
      await t.pumpWidget(host(const CustomerLoginScreen()));
      expect(find.byKey(const ValueKey('loginIcon_customer')), findsOneWidget);
      expect(find.text(T.get('welcome', AppLanguage.english)), findsOneWidget);
      expect(find.text('+91'), findsOneWidget);
      expect(find.byKey(const ValueKey('phoneField')), findsOneWidget);
      expect(find.byKey(const ValueKey('loginContinue')), findsOneWidget);
      expect(find.byType(OrDivider), findsOneWidget);
      expect(find.text(T.get('google', AppLanguage.english)), findsOneWidget);
      expect(find.text(T.get('terms', AppLanguage.english)), findsOneWidget);
    });

    testWidgets('only 10 digits go in; letters and extra digits are dropped', (t) async {
      await t.pumpWidget(host(const CustomerLoginScreen()));
      await t.enterText(find.byKey(const ValueKey('phoneField')), '98ab765432101234');
      expect(t.widget<TextField>(find.byKey(const ValueKey('phoneField'))).controller!.text, '9876543210');
    });

    testWidgets('a wrong number shows the message with the error icon and does not start loading', (t) async {
      await t.pumpWidget(host(const CustomerLoginScreen()));
      await t.tap(find.byKey(const ValueKey('loginContinue')));
      await t.pump();
      expect(find.text(T.get('required', AppLanguage.english)), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await t.enterText(find.byKey(const ValueKey('phoneField')), '5876543210');
      await t.tap(find.byKey(const ValueKey('loginContinue')));
      await t.pump();
      expect(find.text(T.get('invalidMobile', AppLanguage.english)), findsOneWidget);
      final border = (t.widget<TextField>(find.byKey(const ValueKey('phoneField'))).decoration!.enabledBorder as OutlineInputBorder).borderSide;
      expect(border.color, DsColors.light.error);
    });

    testWidgets('Google says "coming soon" and the screen has the spoken back button when opened from another', (t) async {
      await t.pumpWidget(pushed(const CustomerLoginScreen()));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.byTooltip('Back'), findsOneWidget);
      await t.tap(find.text(T.get('google', AppLanguage.english)));
      await t.pump();
      expect(find.text(T.get('googleSoon', AppLanguage.english)), findsOneWidget);
      await t.tap(find.byTooltip('Back'));
      await t.pumpAndSettle();
      expect(find.byType(CustomerLoginScreen), findsNothing);
    });
  });

  group('driver and transporter login', () {
    testWidgets('driver: truck icon in the driver colour', (t) async {
      await t.pumpWidget(host(const DriverLoginScreen()));
      expect(find.byKey(const ValueKey('loginIcon_driver')), findsOneWidget);
      expect(find.byIcon(Icons.local_shipping_rounded), findsOneWidget);
      expect(find.text(T.get('driverLoginTitle', AppLanguage.english)), findsWidgets);
    });

    testWidgets('fleet: warehouse icon in the transporter colour and its own title', (t) async {
      await t.pumpWidget(host(const DriverLoginScreen(role: 'fleet')));
      expect(find.byKey(const ValueKey('loginIcon_transporter')), findsOneWidget);
      expect(find.byIcon(Icons.warehouse_rounded), findsOneWidget);
      expect(find.text(T.get('fleetLoginTitle', AppLanguage.english)), findsWidgets);
      expect(find.text(T.get('fleetLoginSub', AppLanguage.english)), findsOneWidget);
    });

    testWidgets('the same validation as the customer', (t) async {
      await t.pumpWidget(host(const DriverLoginScreen()));
      await t.enterText(find.byKey(const ValueKey('phoneField')), '12345');
      await t.tap(find.byKey(const ValueKey('loginContinue')));
      await t.pump();
      expect(find.text(T.get('invalidMobile', AppLanguage.english)), findsOneWidget);
    });
  });

  group('OTP screen', () {
    Widget otp({String role = 'customer'}) => host(OtpVerificationScreen(phoneNumber: '9876543210', verificationId: 'v1', role: role));

    testWidgets('masked number, six boxes, countdown, verify button', (t) async {
      await t.pumpWidget(otp());
      expect(find.textContaining('+91 98•••••210'), findsOneWidget);
      expect(find.byType(OtpField), findsOneWidget);
      expect(find.text('Resend OTP in 60s'), findsOneWidget);
      expect(find.byKey(const ValueKey('otpVerify')), findsOneWidget);
    });

    testWidgets('an incomplete code turns the boxes red, buzzes, and typing clears the red', (t) async {
      final calls = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add(call.arguments as String);
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await t.pumpWidget(otp());
      await t.enterText(find.byKey(const ValueKey('otpField')), '123');
      await t.tap(find.byKey(const ValueKey('otpVerify')));
      await t.pump();
      expect(find.text(T.get('invalidOtp', AppLanguage.english)), findsOneWidget);
      expect(t.widget<OtpField>(find.byType(OtpField)).error, isTrue);
      expect(calls, contains('HapticFeedbackType.heavyImpact'));
      await t.enterText(find.byKey(const ValueKey('otpField')), '1234');
      await t.pump();
      expect(t.widget<OtpField>(find.byType(OtpField)).error, isFalse);
    });

    testWidgets('digits only, resend waits 60 seconds then turns on', (t) async {
      await t.pumpWidget(otp());
      await t.enterText(find.byKey(const ValueKey('otpField')), '12ab34');
      await t.pump();
      expect(t.widget<TextField>(find.byKey(const ValueKey('otpField'))).controller!.text, '1234');
      expect(t.widget<TextButton>(find.byKey(const Key('resendOtp'))).onPressed, isNull);
      await t.pump(const Duration(seconds: 60));
      expect(t.widget<TextButton>(find.byKey(const Key('resendOtp'))).onPressed, isNotNull);
    });

    testWidgets('the role colour follows the door: driver and fleet', (t) async {
      await t.pumpWidget(otp(role: 'driver'));
      expect(find.byKey(const ValueKey('loginIcon_driver')), findsOneWidget);
      await t.pumpWidget(otp(role: 'fleet'));
      expect(find.byKey(const ValueKey('loginIcon_transporter')), findsOneWidget);
    });
  });

  for (final lang in [AppLanguage.english, AppLanguage.hindi, AppLanguage.tamil, AppLanguage.urdu]) {
    for (final b in Brightness.values) {
      for (final entry in {
        'customer login': () => const CustomerLoginScreen(),
        'driver login': () => const DriverLoginScreen(),
        'fleet login': () => const DriverLoginScreen(role: 'fleet'),
        'otp': () => const OtpVerificationScreen(phoneNumber: '9876543210', verificationId: 'v1'),
      }.entries) {
        testWidgets('${entry.key} fits 360x640 at 2.0x text and scrolls: ${lang.name} ${b.name}', (t) async {
          t.view.physicalSize = const Size(360, 640);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          await t.pumpWidget(host(entry.value(), lang: lang, b: b, scale: 2.0));
          expect(t.takeException(), isNull);
          await t.drag(find.byType(SingleChildScrollView).first, const Offset(0, -3000));
          await t.pump();
          expect(t.takeException(), isNull);
        });
      }
    }
  }
}
