import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/services/auth_helpers.dart';
import '../core/services/user_service.dart';
import '../core/l10n/l10n.dart';
import '../core/l10n/language_widgets.dart';
import 'start_resolvers.dart';
import 'otp_verification_screen.dart';
class DriverLoginScreen extends StatefulWidget {
  const DriverLoginScreen({super.key});

  @override
  State<DriverLoginScreen> createState() => _DriverLoginScreenState();
}

class _DriverLoginScreenState extends State<DriverLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _continueWithPhone() async {
    if (!_formKey.currentState!.validate()) return;

    final phone = _phoneController.text.trim();
    setState(() => _isLoading = true);

    void fail(String key) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, key)), behavior: SnackBarBehavior.floating),
      );
    }

    await sendPhoneOtp(
      phone,
      OtpCallbacks(
        onAutoVerified: (credential) async {
          try {
            await FirebaseAuth.instance.signInWithCredential(credential);
            if (!mounted) return;
            await UserService.markRoleSelected('driver');
            await syncLanguageAfterLogin();
            final next = await resolveDriverStart();
            if (!mounted) return;
            setState(() => _isLoading = false);
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => next),
              (route) => false,
            );
          } on FirebaseAuthException catch (e) {
            fail(authErrorKey(e.code));
          } catch (_) {
            fail('otpFailed');
          }
        },
        onError: fail,
        onCodeSent: (verificationId, resendToken) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OtpVerificationScreen(
                phoneNumber: phone,
                verificationId: verificationId,
                resendToken: resendToken,
                isDriver: true,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F8FC),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).pop()),
        title: Text(tr(context, 'driverLoginTitle'), style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: const [LanguageButton()],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Center(
                  child: Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(color: const Color(0xFFE8F1FF), borderRadius: BorderRadius.circular(24)),
                    child: const Icon(Icons.local_shipping_rounded, size: 45, color: Color(0xFF1565C0)),
                  ),
                ),
                const SizedBox(height: 28),
                Center(
                  child: Text(tr(context, 'driverLoginTitle'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(tr(context, 'driverLoginSub'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: Color(0xFF667085))),
                ),
                const SizedBox(height: 40),
                Text(tr(context, 'mobile'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF344054))),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    counterText: '',
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: 16, right: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('🇮🇳', style: TextStyle(fontSize: 20)),
                          SizedBox(width: 8),
                          Text('+91', style: TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    hintText: tr(context, 'mobileHint'),
                  ),
                  validator: (value) {
                    final phone = value?.trim() ?? '';
                    if (phone.isEmpty) return tr(context, 'required');
                    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(phone)) return tr(context, 'invalidMobile');
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _continueWithPhone,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF9DBCE5),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 23,
                            height: 23,
                            child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                          )
                        : Text(tr(context, 'continueMobile'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}