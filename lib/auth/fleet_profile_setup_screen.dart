import '../core/errors/error_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/enterprise/validators.dart';
import '../core/identity/identity_index.dart';
import '../core/identity/kyc_validators.dart';
import '../core/l10n/l10n.dart';
import '../core/l10n/language_widgets.dart';
import '../core/services/user_service.dart';
import '../core/transporter/transporter_logic.dart';
import 'role_selection_screen.dart';
import 'start_resolvers.dart';
import '../core/widgets/common.dart';

/// Transporter onboarding: name, company, PAN (unique across accounts) and an
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
  final _city = TextEditingController();
  final _routes = TextEditingController();
  final _types = TextEditingController();
  final _count = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _company, _pan, _gst, _city, _routes, _types, _count]) {
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
        officeCity: _city.text.trim(),
        routes: TransporterProfile.parseList(_routes.text),
        vehicleTypes: TransporterProfile.parseList(_types.text, max: TransporterProfile.maxVehicleTypes),
        vehicleCount: int.tryParse(_count.text.trim()) ?? 0,
      );
      if (!mounted) return;
      final next = await resolveFleetStart();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => next), (route) => false);
    } on DuplicateIdentityException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showDuplicateIdentity(context, e);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(context, error)), behavior: SnackBarBehavior.floating));
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
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
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
                Text(tr(context, 'fleetProfileTitle'), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.title)),
                const SizedBox(height: 8),
                Text(tr(context, 'fleetProfileSub'), style: TextStyle(fontSize: 15, color: AppColors.muted)),
                const SizedBox(height: 24),
                TextFormField(
                  key: const ValueKey('fleetName'),
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: tr(context, 'fullName')),
                  validator: (v) => (v ?? '').trim().length < 2 ? tr(context, 'nameRequired') : null, inputFormatters: [LengthLimitingTextInputFormatter(100)]),
                const SizedBox(height: 14),
                TextFormField(
                  key: const ValueKey('fleetCompany'),
                  controller: _company,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: tr(context, 'company')),
                  validator: (v) => (v ?? '').trim().length < 2 ? tr(context, 'fieldRequired') : null, inputFormatters: [LengthLimitingTextInputFormatter(100)]),
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
                    return g.isEmpty || isValidGstin(g) ? null : tr(context, 'gstinInvalid');
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const ValueKey('fleetCity'),
                  controller: _city,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: tr(context, 'trpCity')),
                  validator: (v) => (v ?? '').trim().length < 2 ? tr(context, 'fieldRequired') : null,
                  inputFormatters: [LengthLimitingTextInputFormatter(60)],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const ValueKey('fleetRoutes'),
                  controller: _routes,
                  decoration: InputDecoration(labelText: tr(context, 'trpRoutes')),
                  inputFormatters: [LengthLimitingTextInputFormatter(400)],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const ValueKey('fleetTypes'),
                  controller: _types,
                  decoration: InputDecoration(labelText: tr(context, 'trpVehicleTypes')),
                  inputFormatters: [LengthLimitingTextInputFormatter(300)],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const ValueKey('fleetCount'),
                  controller: _count,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: tr(context, 'trpVehicleCount')),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
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
