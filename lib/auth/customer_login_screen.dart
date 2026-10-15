import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/l10n/language_widgets.dart';
import '../core/services/auth_helpers.dart';
import '../core/services/user_service.dart';
import 'start_resolvers.dart';
import 'otp_verification_screen.dart';
import '../core/theme/design_tokens.dart';
import '../core/widgets/ds/app_top_bar.dart';
import 'login_widgets.dart';
import '../core/widgets/ds/app_button.dart';


// CUSTOMER LOGIN
// ============================================================

class CustomerLoginScreen extends StatefulWidget {
  const CustomerLoginScreen({super.key});

  @override
  State<CustomerLoginScreen> createState() => _CustomerLoginScreenState();
}

class _CustomerLoginScreenState extends State<CustomerLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _phoneController = TextEditingController();
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

            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(tr(context, 'phoneVerified')), behavior: SnackBarBehavior.floating),
            );

            await UserService.markRoleSelected('customer');
            await syncLanguageAfterLogin();
            final next = await resolveCustomerStart();

            if (!mounted) return;
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
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Scaffold(
      appBar: AppTopBar(title: tr(context, 'login'), role: 'customer', actions: const [LanguageButton()]),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LoginHeader(role: 'customer', icon: Icons.person_rounded, title: tr(context, 'welcome'), subtitle: tr(context, 'loginSub')),
                const SizedBox(height: DsSpace.s8),
                PhoneFormField(controller: _phoneController),
                const SizedBox(height: DsSpace.s6),
                AppButton(key: const ValueKey('loginContinue'), label: tr(context, 'continueMobile'), loading: _isLoading, onPressed: _continueWithPhone),
                const SizedBox(height: DsSpace.s6),
                const OrDivider(),
                const SizedBox(height: DsSpace.s6),
                AppButton(
                  label: tr(context, 'google'),
                  kind: AppButtonKind.secondary,
                  icon: Icons.g_mobiledata_rounded,
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'googleSoon')), behavior: SnackBarBehavior.floating)),
                ),
                const SizedBox(height: DsSpace.s6),
                Center(child: Text(tr(context, 'terms'), textAlign: TextAlign.center, style: DsType.caption.copyWith(height: 1.4, color: c.textMuted))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
// ============================================================
