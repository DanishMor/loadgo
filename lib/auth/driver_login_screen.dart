import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/services/auth_helpers.dart';
import '../core/services/user_service.dart';
import '../core/l10n/l10n.dart';
import '../core/l10n/language_widgets.dart';
import 'start_resolvers.dart';
import 'otp_verification_screen.dart';
import '../core/theme/design_tokens.dart';
import '../core/widgets/ds/app_top_bar.dart';
import 'login_widgets.dart';
import '../core/widgets/ds/app_button.dart';
class DriverLoginScreen extends StatefulWidget {
  /// `driver` (default) or `fleet`: the same phone login with another door.
  final String role;

  const DriverLoginScreen({super.key, this.role = 'driver'});

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
            await UserService.markRoleSelected(widget.role);
            await syncLanguageAfterLogin();
            final next = widget.role == 'fleet' ? await resolveFleetStart() : await resolveDriverStart();
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
                isDriver: widget.role == 'driver',
                role: widget.role,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fleet = widget.role == 'fleet';
    final role = fleet ? 'transporter' : 'driver';
    final title = tr(context, fleet ? 'fleetLoginTitle' : 'driverLoginTitle');
    return Scaffold(
      appBar: AppTopBar(title: title, role: role, actions: const [LanguageButton()]),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LoginHeader(role: role, icon: fleet ? Icons.warehouse_rounded : Icons.local_shipping_rounded, title: title, subtitle: tr(context, fleet ? 'fleetLoginSub' : 'driverLoginSub')),
                const SizedBox(height: DsSpace.s8),
                PhoneFormField(controller: _phoneController),
                const SizedBox(height: DsSpace.s6),
                AppButton(key: const ValueKey('loginContinue'), label: tr(context, 'continueMobile'), loading: _isLoading, onPressed: _continueWithPhone),
              ],
            ),
          ),
        ),
      ),
    );
  }
}