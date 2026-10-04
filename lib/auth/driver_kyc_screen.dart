import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/identity/identity_index.dart';
import '../core/identity/kyc_validators.dart';
import '../core/l10n/l10n.dart';
import '../core/l10n/language_widgets.dart';
import '../core/services/user_service.dart';
import 'role_selection_screen.dart';
import 'start_resolvers.dart';

/// Compulsory step after the driver's profile: licence, RC, Aadhaar (last 4
/// digits only) and PAN. Home and Loads stay closed until this is saved
/// (see [resolveDriverStart]). LATER(paid): verify with Parivahan / NSDL.
class DriverKycScreen extends StatefulWidget {
  /// Edit mode (from Profile): fields start filled, the screen can be left,
  /// and saving goes back instead of through the start router.
  final bool edit;

  const DriverKycScreen({super.key, this.edit = false});

  @override
  State<DriverKycScreen> createState() => _DriverKycScreenState();
}

class _DriverKycScreenState extends State<DriverKycScreen> {
  final _formKey = GlobalKey<FormState>();
  final _dlCtrl = TextEditingController();
  final _rcCtrl = TextEditingController();
  final _aadhaarCtrl = TextEditingController();
  final _panCtrl = TextEditingController();
  DateTime? _dlExpiry;
  bool _expiryError = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    UserService.getUser().then((u) {
      if (!mounted) return;
      final k = u?['driverKyc'];
      if (widget.edit && k is Map) {
        final exp = k['dlExpiry'];
        setState(() {
          _dlCtrl.text = k['dlNumber']?.toString() ?? '';
          _rcCtrl.text = k['rcNumber']?.toString() ?? '';
          _aadhaarCtrl.text = k['aadhaarLast4']?.toString() ?? '';
          _panCtrl.text = k['pan']?.toString() ?? '';
          if (exp is Timestamp) _dlExpiry = exp.toDate();
        });
        return;
      }
      final v = u?['vehicleNumber']?.toString() ?? '';
      if (_rcCtrl.text.isEmpty) _rcCtrl.text = v;
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _dlCtrl.dispose();
    _rcCtrl.dispose();
    _aadhaarCtrl.dispose();
    _panCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dlExpiry ?? now.add(const Duration(days: 365)),
      firstDate: now,
      lastDate: DateTime(now.year + 30),
    );
    if (picked != null && mounted) setState(() => _dlExpiry = picked);
  }

  Future<void> _submit() async {
    final formOk = _formKey.currentState!.validate();
    final expiryOk = isDlExpiryValid(_dlExpiry, DateTime.now());
    setState(() => _expiryError = !expiryOk);
    if (!formOk || !expiryOk) return;
    setState(() => _saving = true);

    try {
      await UserService.saveDriverKyc(DriverKyc(
        dlNumber: _dlCtrl.text,
        dlExpiry: _dlExpiry!,
        rcNumber: _rcCtrl.text,
        aadhaarLast4: _aadhaarCtrl.text,
        pan: _panCtrl.text,
      ));
      if (!mounted) return;
      if (widget.edit) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'kycUpdated')), behavior: SnackBarBehavior.floating),
        );
        return;
      }
      final next = await resolveDriverStart();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => next), (route) => false);
    } on DuplicateIdentityException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showDuplicateIdentity(context, e);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'somethingWrong')), behavior: SnackBarBehavior.floating),
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
        child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF344054))),
      );

  String _dateText(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final upper = [UpperCaseTextFormatter(), FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 -]'))];
    return PopScope(
      canPop: widget.edit,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F8FC),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF6F8FC),
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: widget.edit,
          actions: [
            const LanguageButton(),
            if (!widget.edit) TextButton(onPressed: _saving ? null : _logout, child: Text(tr(context, 'logout'))),
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
                  Text(tr(context, 'kycTitle'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
                  const SizedBox(height: 8),
                  Text(tr(context, 'kycSub'), style: const TextStyle(fontSize: 15, color: Color(0xFF667085))),
                  const SizedBox(height: 24),
                  _label(tr(context, 'dlNumber')),
                  TextFormField(
                    key: const ValueKey('kycDl'),
                    controller: _dlCtrl,
                    inputFormatters: upper,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.badge_outlined)),
                    validator: (v) => isValidDlNumber(v ?? '') ? null : tr(context, 'kycInvalidDl'),
                  ),
                  const SizedBox(height: 18),
                  _label(tr(context, 'dlExpiry')),
                  InkWell(
                    key: const ValueKey('kycDlExpiry'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: _pickExpiry,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.event_outlined),
                        errorText: _expiryError ? tr(context, 'kycDlExpired') : null,
                      ),
                      child: Text(_dlExpiry == null ? '—' : _dateText(_dlExpiry!)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _label(tr(context, 'rcVehicleNumber')),
                  TextFormField(
                    key: const ValueKey('kycRc'),
                    controller: _rcCtrl,
                    inputFormatters: upper,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(prefixIcon: const Icon(Icons.local_shipping_outlined), hintText: tr(context, 'vehicleNumberHint')),
                    validator: (v) => isValidVehicleNumber(v ?? '') ? null : tr(context, 'kycInvalidRc'),
                  ),
                  const SizedBox(height: 18),
                  _label(tr(context, 'aadhaarLast4')),
                  TextFormField(
                    key: const ValueKey('kycAadhaar'),
                    controller: _aadhaarCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.fingerprint_rounded),
                      counterText: '',
                      helperText: tr(context, 'aadhaarNote'),
                      helperMaxLines: 2,
                    ),
                    validator: (v) => isValidAadhaarLast4(v ?? '') ? null : tr(context, 'kycInvalidAadhaar'),
                  ),
                  const SizedBox(height: 18),
                  _label(tr(context, 'panNumber')),
                  TextFormField(
                    key: const ValueKey('kycPan'),
                    controller: _panCtrl,
                    maxLength: 10,
                    inputFormatters: upper,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.credit_card_outlined), counterText: ''),
                    validator: (v) => isValidPan(v ?? '') ? null : tr(context, 'kycInvalidPan'),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      key: const ValueKey('kycSubmit'),
                      onPressed: _saving ? null : _submit,
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
                          : Text(tr(context, 'kycSubmit'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
