import '../core/errors/error_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/l10n.dart';
import '../core/services/backend.dart';
import '../core/services/transporter_service.dart';
import '../core/transporter/transporter_logic.dart';
import '../core/widgets/common.dart';

/// Company profile of a transporter: company, GST, office city, routes,
/// vehicle types and count. The PAN is shown but locked (it is tied to the
/// identity index). The "Verified transporter" badge appears once an admin
/// has approved the account; nothing here is checked against a government
/// source (LATER(paid): GST / PAN API).
class TransporterProfileScreen extends StatefulWidget {
  const TransporterProfileScreen({super.key});

  @override
  State<TransporterProfileScreen> createState() => _TransporterProfileScreenState();
}

class _TransporterProfileScreenState extends State<TransporterProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _company = TextEditingController();
  final _gst = TextEditingController();
  final _city = TextEditingController();
  final _routes = TextEditingController();
  final _types = TextEditingController();
  final _count = TextEditingController();
  String _pan = '';
  bool _verified = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_company, _gst, _city, _routes, _types, _count]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final user = (await Backend.db.collection('users').doc(Backend.requireUid()).get()).data();
      final p = TransporterProfile.fromUser(user);
      _company.text = p.company;
      _gst.text = p.gstin;
      _city.text = p.officeCity;
      _routes.text = p.routes.join(', ');
      _types.text = p.vehicleTypes.join(', ');
      _count.text = p.vehicleCount == 0 ? '' : '${p.vehicleCount}';
      _pan = p.pan;
      _verified = isVerifiedTransporter(user);
    } catch (_) {
      // Offline: the form stays empty and saving shows the usual error.
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await TransporterService.updateProfile(TransporterProfile(
        company: _company.text,
        gstin: _gst.text,
        pan: _pan,
        officeCity: _city.text,
        routes: TransporterProfile.parseList(_routes.text),
        vehicleTypes: TransporterProfile.parseList(_types.text, max: TransporterProfile.maxVehicleTypes),
        vehicleCount: int.tryParse(_count.text.trim()) ?? 0,
      ));
      if (mounted) {
        showSnack(context, tr(context, 'trpSaved'));
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) showSnack(context, errorText(context, error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(tr(context, 'trpTitle'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _form,
                child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 30), children: [
                  Row(children: [
                    StatusChip(
                      key: const ValueKey('trpBadge'),
                      label: _verified ? tr(context, 'trpVerified') : tr(context, 'trpNotVerifiedChip'),
                      color: _verified ? AppColors.success : AppColors.muted,
                    ),
                  ]),
                  if (!_verified)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(tr(context, 'trpNotVerified'), style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('trpCompany'),
                    controller: _company,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(labelText: tr(context, 'company')),
                    inputFormatters: [LengthLimitingTextInputFormatter(100)],
                    validator: (v) => (v ?? '').trim().length < 2 ? tr(context, 'fieldRequired') : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('trpPan'),
                    initialValue: _pan,
                    enabled: false,
                    decoration: InputDecoration(labelText: tr(context, 'panNumber')),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('trpGst'),
                    controller: _gst,
                    maxLength: 15,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(labelText: tr(context, 'gstOptional'), counterText: ''),
                    validator: (v) => TransporterProfile(gstin: v ?? '').errors().contains('gstin') ? tr(context, 'gstinInvalid') : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('trpCityField'),
                    controller: _city,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(labelText: tr(context, 'trpCity')),
                    inputFormatters: [LengthLimitingTextInputFormatter(60)],
                    validator: (v) => (v ?? '').trim().length < 2 ? tr(context, 'fieldRequired') : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('trpRoutesField'),
                    controller: _routes,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(labelText: tr(context, 'trpRoutes')),
                    inputFormatters: [LengthLimitingTextInputFormatter(400)],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('trpTypesField'),
                    controller: _types,
                    decoration: InputDecoration(labelText: tr(context, 'trpVehicleTypes')),
                    inputFormatters: [LengthLimitingTextInputFormatter(300)],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('trpCountField'),
                    controller: _count,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: tr(context, 'trpVehicleCount')),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      key: const ValueKey('trpSave'),
                      onPressed: _saving ? null : _save,
                      child: _saving ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(tr(context, 'save')),
                    ),
                  ),
                ]),
              ),
      ),
    );
  }
}
