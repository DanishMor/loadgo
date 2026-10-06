import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../identity/profile_extras.dart';
import '../services/user_service.dart';
import '../widgets/common.dart';
import '../l10n/l10n.dart';
final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Edit name, email and company after the first-time setup. Pops `true`
/// once saved.
class EditProfileScreen extends StatefulWidget {
  final bool isDriver;
  final Map<String, dynamic> profile;

  const EditProfileScreen({super.key, required this.isDriver, required this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController(
      text: (widget.isDriver ? widget.profile['driverName'] : (widget.profile['name'] ?? widget.profile['fullName'])) as String? ?? '');
  late final _emailCtrl = TextEditingController(text: widget.profile['email'] as String? ?? '');
  late final _companyCtrl = TextEditingController(text: widget.profile['companyName'] as String? ?? '');
  late final _extras = ProfileExtras.fromProfile(widget.profile);
  late final _currentCtrl = TextEditingController(text: _extras.currentAddress);
  late final _permanentCtrl = TextEditingController(text: _extras.permanentAddress);
  late final _upiCtrl = TextEditingController(text: _extras.upiId);
  late final _holderCtrl = TextEditingController(text: _extras.holder);
  late String? _businessType = _extras.businessType;
  bool _saving = false;

  /// Payout details are for the people who get paid: drivers and fleet owners.
  bool get _getsPaid => widget.isDriver || widget.profile['role'] == 'fleet';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _companyCtrl.dispose();
    _currentCtrl.dispose();
    _permanentCtrl.dispose();
    _upiCtrl.dispose();
    _holderCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await UserService.updateProfile(
        isDriver: widget.isDriver,
        name: _nameCtrl.text,
        email: _emailCtrl.text,
        companyName: _companyCtrl.text,
        currentAddress: _currentCtrl.text,
        permanentAddress: _permanentCtrl.text,
        businessType: widget.isDriver ? null : (_businessType ?? ''),
        upiId: _getsPaid ? _upiCtrl.text : null,
        holder: _getsPaid ? _holderCtrl.text : null,
      );
      if (!mounted) return;
      showSnack(context, tr(context, 'profileUpdated'));
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(tr(context, 'editProfile'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FieldLabel(tr(context, 'fullName')),
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline_rounded)),
                  validator: (v) => (v == null || v.trim().length < 2) ? tr(context, 'nameRequired') : null, inputFormatters: [LengthLimitingTextInputFormatter(100)]),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'emailOptional')),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.email_outlined)),
                  validator: (v) {
                    final e = v?.trim() ?? '';
                    return e.isEmpty || _emailPattern.hasMatch(e) ? null : tr(context, 'invalidEmail');
                  }, inputFormatters: [LengthLimitingTextInputFormatter(100)]),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'companyNameOptional')),
                TextFormField(
                  controller: _companyCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.business_rounded)), inputFormatters: [LengthLimitingTextInputFormatter(100)]),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'addrCurrent')),
                TextFormField(
                  key: const ValueKey('addrCurrent'),
                  controller: _currentCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.home_outlined)), inputFormatters: [LengthLimitingTextInputFormatter(200)]),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'addrPermanent')),
                TextFormField(
                  key: const ValueKey('addrPermanent'),
                  controller: _permanentCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.location_city_outlined)), inputFormatters: [LengthLimitingTextInputFormatter(200)]),
                if (!widget.isDriver) ...[
                  const SizedBox(height: 18),
                  FieldLabel(tr(context, 'businessTypeLabel')),
                  DropdownButtonFormField<String?>(
                    key: const ValueKey('businessType'),
                    isExpanded: true,
                    initialValue: _businessType,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.category_outlined)),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('-')),
                      for (final t in BusinessType.all) DropdownMenuItem(value: t, child: Text(tr(context, 'bt${t[0].toUpperCase()}${t.substring(1)}'))),
                    ],
                    onChanged: (v) => setState(() => _businessType = v),
                  ),
                ],
                if (_getsPaid) ...[
                  const SizedBox(height: 18),
                  FieldLabel(tr(context, 'upiIdLabel')),
                  TextFormField(
                    key: const ValueKey('upiId'),
                    controller: _upiCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.account_balance_wallet_outlined)),
                    validator: (v) => (v ?? '').trim().isEmpty || isValidUpiId(v!) ? null : tr(context, 'upiInvalid'),
                    inputFormatters: [LengthLimitingTextInputFormatter(61)]),
                  const SizedBox(height: 10),
                  FieldLabel(tr(context, 'upiHolder')),
                  TextFormField(
                    key: const ValueKey('upiHolder'),
                    controller: _holderCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.badge_outlined)), inputFormatters: [LengthLimitingTextInputFormatter(80)]),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(tr(context, 'payoutNote'), style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ),
                ],
                const SizedBox(height: 30),
                PrimaryButton(label: tr(context, 'save'), loading: _saving, onPressed: _save),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
