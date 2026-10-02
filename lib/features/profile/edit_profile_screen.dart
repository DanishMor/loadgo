import 'package:flutter/material.dart';

import '../../core/services/user_service.dart';
import '../../core/widgets/common.dart';
import '../../main.dart';

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
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _companyCtrl.dispose();
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
                  validator: (v) => (v == null || v.trim().length < 2) ? tr(context, 'nameRequired') : null,
                ),
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
                  },
                ),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'companyNameOptional')),
                TextFormField(
                  controller: _companyCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.business_rounded)),
                ),
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
