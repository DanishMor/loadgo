import 'package:flutter/material.dart';

import '../../core/constants/logistics.dart';
import '../../core/services/user_service.dart';
import '../../core/services/vehicle_service.dart';
import '../../core/widgets/common.dart';
import '../../main.dart';

/// Form for a driver to register a vehicle. Pops with `true` once saved.
class AddVehicleScreen extends StatefulWidget {
  /// Prefill number/type from the driver's profile (used for the first vehicle).
  final bool prefillFromProfile;

  const AddVehicleScreen({super.key, this.prefillFromProfile = false});

  @override
  State<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<AddVehicleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _numberCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController();
  final _rcCtrl = TextEditingController();
  String _type = 'Mini';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.prefillFromProfile) _prefill();
  }

  Future<void> _prefill() async {
    try {
      final data = await UserService.getUser();
      if (!mounted || data == null) return;
      final number = data['vehicleNumber'] as String?;
      final type = (data['vehicleType'] as String?)?.replaceAll(' ', '');
      setState(() {
        if (number != null && _numberCtrl.text.isEmpty) _numberCtrl.text = number;
        if (type != null && vehicleTypes.contains(type)) _type = type;
      });
    } catch (_) {
      // Prefill is best-effort; the form still works empty.
    }
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    _capacityCtrl.dispose();
    _rcCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await VehicleService.add(
        number: _numberCtrl.text,
        type: _type,
        capacity: num.parse(_capacityCtrl.text.trim()),
        rcNumber: _rcCtrl.text,
      );
      if (!mounted) return;
      showSnack(context, tr(context, 'vehicleAdded'));
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
        title: Text(tr(context, 'addVehicle'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FieldLabel(tr(context, 'vehicleNumber')),
                TextFormField(
                  controller: _numberCtrl,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.pin_outlined),
                    hintText: tr(context, 'vehicleNumberHint'),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return tr(context, 'fieldRequired');
                    return VehicleService.isValidNumber(v) ? null : tr(context, 'invalidVehicleNumber');
                  },
                ),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'vehicleType')),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.local_shipping_outlined)),
                  items: [for (final t in vehicleTypes) DropdownMenuItem(value: t, child: Text(t))],
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'capacityTons')),
                TextFormField(
                  controller: _capacityCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.scale_outlined), hintText: 'e.g. 9'),
                  validator: (v) {
                    final n = num.tryParse(v?.trim() ?? '');
                    return (n == null || n <= 0 || n > 100) ? tr(context, 'invalidNumber') : null;
                  },
                ),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'rcNumber')),
                TextFormField(
                  controller: _rcCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.description_outlined)),
                  validator: (v) => (v == null || v.trim().length < 4) ? tr(context, 'fieldRequired') : null,
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
