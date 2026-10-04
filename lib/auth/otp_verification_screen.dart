import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/l10n.dart';
import '../core/l10n/language_widgets.dart';
import '../core/services/auth_helpers.dart';
import '../core/services/device_service.dart';
import '../core/services/user_service.dart';
import 'start_resolvers.dart';


// OTP (shared by Customer + Driver)
// ============================================================

class OtpVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final String verificationId;
  final int? resendToken;
  final bool isDriver;

  const OtpVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
    this.resendToken,
    this.isDriver = false,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  static const resendSeconds = 60;

  final _otpController = TextEditingController();
  bool _isLoading = false;
  late String _verificationId = widget.verificationId;
  late int? _resendToken = widget.resendToken;
  int _secondsLeft = resendSeconds;
  bool _resending = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'invalidOtp')), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    await _signIn(PhoneAuthProvider.credential(verificationId: _verificationId, smsCode: otp));
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
      if (!mounted) return;
      await syncLanguageAfterLogin();

      Widget next;
      if (widget.isDriver) {
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
      setState(() => _isLoading = false);

      _snack(authErrorKey(e.code));
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
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F8FC),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(tr(context, 'verifyMobile'), style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: const [LanguageButton()],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 35, 20, 30),
          child: Column(
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(color: const Color(0xFFE8F1FF), borderRadius: BorderRadius.circular(24)),
                child: const Icon(Icons.sms_rounded, size: 42, color: Color(0xFF1565C0)),
              ),
              const SizedBox(height: 28),
              Text(
                tr(context, 'verifyTitle'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
              ),
              const SizedBox(height: 10),
              Text(
                '${tr(context, 'otpText')}\n${maskPhone('+91${widget.phoneNumber}')}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, height: 1.5, color: Color(0xFF667085)),
              ),
              const SizedBox(height: 35),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 10),
                decoration: const InputDecoration(counterText: '', hintText: '••••••'),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 23,
                          height: 23,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          tr(context, 'verifyOtp'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                key: const Key('resendOtp'),
                onPressed: _secondsLeft > 0 || _resending ? null : _resend,
                child: Text(
                  _secondsLeft > 0 ? trf(context, 'resendIn', {'s': _secondsLeft}) : tr(context, 'resendOtp'),
                  style: TextStyle(
                    color: _secondsLeft > 0 ? const Color(0xFF98A2B3) : const Color(0xFF1565C0),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

