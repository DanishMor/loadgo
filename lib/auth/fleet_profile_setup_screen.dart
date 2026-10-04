import 'package:flutter/material.dart';

import '../core/enterprise/validators.dart';
import '../core/identity/identity_index.dart';
import '../core/identity/kyc_validators.dart';
import '../core/l10n/l10n.dart';
import '../core/l10n/language_widgets.dart';
import '../core/services/user_service.dart';
import 'role_selection_screen.dart';
import 'start_resolvers.dart';

/// Fleet owner onboarding: name, company, PAN (unique across accounts) and an
/// optional GSTIN. Format checks only; nothing is verified (LATER(paid)).
class FleetProfileSetupScreen extends StatefulWidget {
  const FleetProfileSetupScreen({super.key});

  @override
  State<FleetProfileSetupScreen> createState() => _FleetProfileSetupScreenState();
}

class _FleetProfileSetupScreenState extends State<FleetProfileSetupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _company = TextEditingController();
  final _pan = TextEditingController();
  final _gst = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _company, _pan, _gst]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await UserService.saveFleetProfile(
        name: _name.text.trim(),
        companyName: _company.text.trim(),
        pan: _pan.text,
        gstin: _gst.text,
        language: languageNotifier.value.name,
      );
      if (!mounted) return;
      final next = await resolveFleetStart();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => next), (route) => false);
    } on DuplicateIdentityException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showDuplicateIdentity(context, e);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'somethingWrong')), behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _logout() async {
    await UserService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const RoleSelectionScreen()), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F8FC),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF6F8FC),
          elevation: 0,
          automaticallyImplyLeading: false,
          actions: [const LanguageButton(), TextButton(onPressed: _saving ? null : _logout, child: Text(tr(context, 'logout')))],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(context, 'fleetProfileTitle'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
                const SizedBox(height: 8),
                Text(tr(context, 'fleetProfileSub'), style: const TextStyle(fontSize: 15, color: Color(0xFF667085))),
                const SizedBox(height: 24),
                TextFormField(
                  key: const ValueKey('fleetName'),
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: tr(context, 'fullName')),
                  validator: (v) => (v ?? '').trim().length < 2 ? tr(context, 'nameRequired') : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const ValueKey('fleetCompany'),
                  controller: _company,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: tr(context, 'company')),
                  validator: (v) => (v ?? '').trim().length < 2 ? tr(context, 'fieldRequired') : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const ValueKey('fleetPan'),
                  controller: _pan,
                  maxLength: 10,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(labelText: tr(context, 'panNumber'), counterText: ''),
                  validator: (v) => isValidPan(v ?? '') ? null : tr(context, 'kycInvalidPan'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const ValueKey('fleetGst'),
                  controller: _gst,
                  maxLength: 15,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(labelText: tr(context, 'gstOptional'), counterText: ''),
                  validator: (v) {
                    final g = (v ?? '').trim();
                    return g.isEmpty || isValidGstinFormat(g) ? null : tr(context, 'gstinInvalid');
                  },
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    key: const ValueKey('fleetSave'),
                    onPressed: _saving ? null : _save,
                    child: _saving ? const SizedBox(width: 23, height: 23, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(tr(context, 'saveContinue')),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
