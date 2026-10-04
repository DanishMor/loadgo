import 'package:flutter/material.dart';

import '../../core/services/user_service.dart';
import '../../main.dart';
import '../../core/services/vehicle_type_service.dart';
import '../shared/vehicle_type_widgets.dart';

class DriverProfileSetupScreen extends StatefulWidget {
  const DriverProfileSetupScreen({super.key});

  @override
  State<DriverProfileSetupScreen> createState() => _DriverProfileSetupScreenState();
}

class _DriverProfileSetupScreenState extends State<DriverProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _vehicleNumCtrl = TextEditingController();
  String _vehicleType = 'Mini';
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _vehicleNumCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      await UserService.saveDriverProfile(
        name: _nameCtrl.text.trim(),
        vehicleNumber: _vehicleNumCtrl.text.trim().toUpperCase(),
        vehicleType: _vehicleType,
        language: languageNotifier.value.name,
      );
      if (!mounted) return;
      final next = await resolveDriverStart();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => next),
        (route) => false,
      );
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F8FC),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF6F8FC),
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
                  Text(tr(context, 'driverProfileTitle'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
                  const SizedBox(height: 8),
                  Text(tr(context, 'driverProfileSub'), style: const TextStyle(fontSize: 15, color: Color(0xFF667085))),
                  const SizedBox(height: 30),
                  _label(tr(context, 'fullName')),
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline_rounded)),
                    validator: (v) => (v == null || v.trim().length < 2) ? tr(context, 'nameRequired') : null,
                  ),
                  const SizedBox(height: 18),
                  _label(tr(context, 'vehicleNumber')),
                  TextFormField(
                    controller: _vehicleNumCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(prefixIcon: const Icon(Icons.numbers_rounded), hintText: tr(context, 'vehicleNumberHint')),
                    validator: (v) => (v == null || v.trim().length < 4) ? tr(context, 'vehicleNumberRequired') : null,
                  ),
                  const SizedBox(height: 18),
                  _label(tr(context, 'vehicleType')),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: VehicleTypeService.ids.map((t) {
                      final selected = t == _vehicleType;
                      return ChoiceChip(
                        label: Text(vehicleTypeLabel(context, t)),
                        selected: selected,
                        onSelected: (_) => setState(() => _vehicleType = t),
                        selectedColor: const Color(0xFFE8F1FF),
                      );
                    }).toList(),
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