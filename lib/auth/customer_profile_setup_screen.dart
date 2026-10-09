import '../core/errors/error_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/enterprise/validators.dart';
import '../core/identity/identity_index.dart';
import '../core/services/user_service.dart';
import '../core/l10n/l10n.dart';
import '../core/l10n/language_widgets.dart';
import '../customer/customer_home_screen.dart';
import 'role_selection_screen.dart';
import '../core/widgets/common.dart';

class CustomerProfileSetupScreen extends StatefulWidget {
  final String phoneNumber;
  final String existingName;

  const CustomerProfileSetupScreen({
    super.key,
    this.phoneNumber = '',
    this.existingName = '',
  });

  @override
  State<CustomerProfileSetupScreen> createState() => _CustomerProfileSetupScreenState();
}

class _CustomerProfileSetupScreenState extends State<CustomerProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  final _companyCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _gstCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existingName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _companyCtrl.dispose();
    _emailCtrl.dispose();
    _gstCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      await UserService.saveCustomerProfile(
        name: _nameCtrl.text.trim(),
        companyName: _companyCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        gstin: _gstCtrl.text,
        language: languageNotifier.value.name,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const CustomerHomeScreen()),
        (route) => false,
      );
    } on DuplicateIdentityException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showDuplicateIdentity(context, e);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorText(context, error)), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _logout() async {
    await UserService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      (route) => false,
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.body)),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          actions: [
            const LanguageButton(),
            TextButton(onPressed: _saving ? null : _logout, child: Text(tr(context, 'logout'))),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(context, 'profileSetupTitle'), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.title)),
                  const SizedBox(height: 8),
                  Text(tr(context, 'profileSetupSub'), style: TextStyle(fontSize: 15, color: AppColors.muted)),
                  const SizedBox(height: 30),
                  _label(tr(context, 'fullName')),
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline_rounded)),
                    validator: (v) => (v == null || v.trim().length < 2) ? tr(context, 'nameRequired') : null, inputFormatters: [LengthLimitingTextInputFormatter(100)]),
                  const SizedBox(height: 18),
                  _label(tr(context, 'companyNameOptional')),
                  TextFormField(
                    controller: _companyCtrl,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.business_rounded)), inputFormatters: [LengthLimitingTextInputFormatter(100)]),
                  const SizedBox(height: 18),
                  _label(tr(context, 'emailOptional')),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.email_outlined)),
                    validator: (v) {
                      final e = v?.trim() ?? '';
                      if (e.isEmpty) return null;
                      return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e) ? null : tr(context, 'invalidEmail');
                    }, inputFormatters: [LengthLimitingTextInputFormatter(100)]),
                  const SizedBox(height: 18),
                  _label(tr(context, 'gstOptional')),
                  TextFormField(
                    key: const ValueKey('gstField'),
                    controller: _gstCtrl,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 15,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.receipt_long_outlined), counterText: ''),
                    validator: (v) {
                      final g = v?.trim() ?? '';
                      if (g.isEmpty) return null;
                      return isValidGstin(g) ? null : tr(context, 'gstinInvalid');
                    },
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF9DBCE5),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 23,
                              height: 23,
                              child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                            )
                          : Text(tr(context, 'saveContinue'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}