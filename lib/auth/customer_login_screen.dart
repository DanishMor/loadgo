import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/l10n.dart';
import '../core/l10n/language_widgets.dart';
import '../core/services/auth_helpers.dart';
import '../core/services/user_service.dart';
import 'start_resolvers.dart';
import 'otp_verification_screen.dart';
import '../core/widgets/common.dart';
import '../core/theme/design_tokens.dart';
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(tooltip: tr(context, 'a11yBack'), 
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(tr(context, 'login'), style: DsStyle.w700),
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
                    decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(24)),
                    child: const Icon(Icons.person_rounded, size: 45, color: AppColors.primary),
                  ),
                ),
                const SizedBox(height: 28),
                Center(
                  child: Text(
                    tr(context, 'welcome'),
                    textAlign: TextAlign.center,
                    style: DsStyle.t28w700.copyWith(color: AppColors.title),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    tr(context, 'loginSub'),
                    textAlign: TextAlign.center,
                    style: DsStyle.t16w400.copyWith(color: AppColors.muted),
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  tr(context, 'mobile'),
                  style: DsStyle.t14w700.copyWith(color: AppColors.body),
                ),
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
                          Text('🇮🇳', style: DsStyle.t20w400),
                          SizedBox(width: 8),
                          Text('+91', style: DsStyle.w600),
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
                AppButton(label: tr(context, 'continueMobile'), loading: _isLoading, onPressed: _continueWithPhone),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: Divider(color: AppColors.border)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        tr(context, 'or'),
                        style: DsStyle.t12w600.copyWith(color: AppColors.faint),
                      ),
                    ),
                    Expanded(child: Divider(color: AppColors.border)),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(tr(context, 'googleSoon')), behavior: SnackBarBehavior.floating),
                      );
                    },
                    icon: const Icon(Icons.g_mobiledata_rounded, size: 30),
                    label: Text(tr(context, 'google'), style: DsStyle.t16w700),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.body,
                      side: BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Center(
                  child: Text(
                    tr(context, 'terms'),
                    textAlign: TextAlign.center,
                    style: DsStyle.t12w400.copyWith(height: 1.4, color: AppColors.faint),
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

// ============================================================
