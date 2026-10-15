import 'package:firebase_auth/firebase_auth.dart';
import '../core/security/secure_screen.dart';
import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/l10n/language_widgets.dart';
import '../core/services/auth_helpers.dart';
import '../core/services/device_service.dart';
import '../core/security/otp_limits.dart';
import '../core/services/user_service.dart';
import 'start_resolvers.dart';
import '../core/theme/design_tokens.dart';
import '../core/widgets/ds/app_button.dart';
import '../core/widgets/ds/app_top_bar.dart';
import '../core/widgets/ds/haptics.dart';
import '../core/widgets/ds/otp_field.dart';
import 'login_widgets.dart';


// OTP (shared by Customer + Driver)
// ============================================================

class OtpVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final String verificationId;
  final int? resendToken;
  final bool isDriver;

  /// `customer`, `driver` or `fleet`. Defaults from [isDriver].
  final String? role;

  const OtpVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
    this.resendToken,
    this.isDriver = false,
    this.role,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  static const resendSeconds = OtpPolicy.resendSeconds;

  final _otpController = TextEditingController();
  bool _isLoading = false;
  late String _verificationId = widget.verificationId;
  late int? _resendToken = widget.resendToken;
  final _countdown = CountdownController();
  bool _resending = false;
  bool _codeWrong = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() => _countdown.start(resendSeconds);

  @override
  void dispose() {
    _countdown.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _snack(String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr(context, key)), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    await sendPhoneOtp(
      widget.phoneNumber,
      OtpCallbacks(
        onCodeSent: (verificationId, resendToken) {
          if (!mounted) return;
          _verificationId = verificationId;
          _resendToken = resendToken ?? _resendToken;
          setState(() => _resending = false);
          _startTimer();
          _snack('otpResent');
        },
        onError: (key) {
          if (!mounted) return;
          setState(() => _resending = false);
          _snack(key);
        },
        onAutoVerified: (credential) => _signIn(credential),
      ),
      resendToken: _resendToken,
    );
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();

    if (otp.length != 6) {
      setState(() => _codeWrong = true);
      Haptics.warning();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'invalidOtp')), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    final locked = await OtpLimiter.instance.lockedFor(widget.phoneNumber);
    if (locked != null) {
      if (!mounted) return;
      setState(() => _codeWrong = true);
      _snackText(trf(context, 'otpLockedMin', {'m': minutesLeft(locked)}));
      return;
    }
    await _signIn(PhoneAuthProvider.credential(verificationId: _verificationId, smsCode: otp));
  }

  void _snackText(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  /// A wrong code from Firebase: count it; the 5th locks this number for 15 minutes.
  Future<void> _countWrong() async {
    final f = await OtpLimiter.instance.recordWrong(widget.phoneNumber);
    if (!mounted) return;
    if (f.lockedFor != null) {
      _snackText(trf(context, 'otpLockedMin', {'m': minutesLeft(f.lockedFor!)}));
    } else {
      _snackText(trf(context, 'otpAttemptsLeft', {'n': f.attemptsLeft}));
    }
  }

  /// Records this device (new-device signals for admins). Never blocks login.
  Future<void> _registerDevice() async {
    try {
      await DeviceService.register();
    } catch (_) {}
  }

  Future<void> _signIn(PhoneAuthCredential credential) async {
    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.signInWithCredential(credential);
      await OtpLimiter.instance.recordSuccess(widget.phoneNumber);
      if (!mounted) return;
      await syncLanguageAfterLogin();

      Widget next;
      final role = widget.role ?? (widget.isDriver ? 'driver' : 'customer');
      if (role == 'fleet') {
        await UserService.markRoleSelected('fleet');
        await _registerDevice();
        next = await resolveFleetStart();
      } else if (role == 'driver') {
        await UserService.markRoleSelected('driver');
        await _registerDevice();
        next = await resolveDriverStart();
      } else {
        await UserService.markRoleSelected('customer');
        await _registerDevice();
        next = await resolveCustomerStart();
      }

      if (!mounted) return;
      setState(() => _isLoading = false);

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => next),
        (route) => false,
      );
    } on RoleMismatchException catch (e) {
      // Wrong door for this number: drop the session so nothing is half-open.
      await UserService.logout();
      if (!mounted) return;
      setState(() => _isLoading = false);
      final role = tr(context, e.existing == 'driver' ? 'roleNameDriver' : 'roleNameCustomer');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(trf(context, 'roleMismatch', {'role': role})), behavior: SnackBarBehavior.floating),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _codeWrong = e.code == 'invalid-verification-code' || e.code == 'invalid-credential';
      });
      if (_codeWrong) {
        Haptics.warning();
        await _countWrong();
      } else {
        _snack(authErrorKey(e.code));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'otpFailed')), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final role = widget.role ?? (widget.isDriver ? 'driver' : 'customer');
    final accentRole = role == 'fleet' ? 'transporter' : role;
    return SecureScope(child: Scaffold(
      appBar: AppTopBar(title: tr(context, 'verifyMobile'), role: accentRole, actions: const [LanguageButton()]),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LoginHeader(
                role: accentRole,
                icon: Icons.sms_rounded,
                title: tr(context, 'verifyTitle'),
                subtitle: '${tr(context, 'otpText')}\n${maskPhone('+91${widget.phoneNumber}')}',
              ),
              const SizedBox(height: DsSpace.s8),
              OtpField(
                fieldKey: const ValueKey('otpField'),
                controller: _otpController,
                error: _codeWrong,
                autofocus: true,
                enabled: !_isLoading,
                onChanged: (_) {
                  if (_codeWrong) setState(() => _codeWrong = false);
                },
              ),
              const SizedBox(height: DsSpace.s6),
              AppButton(key: const ValueKey('otpVerify'), label: tr(context, 'verifyOtp'), loading: _isLoading, onPressed: _verifyOtp),
              const SizedBox(height: DsSpace.s4),
              Center(child: OtpResendButton(buttonKey: const Key('resendOtp'), countdown: _countdown, busy: _resending, onPressed: _resend)),
              const SizedBox(height: DsSpace.s2),
              Text(tr(context, 'terms'), textAlign: TextAlign.center, style: DsType.caption.copyWith(height: 1.4, color: c.textMuted)),
            ],
          ),
        ),
      ),
    ));
  }
}
