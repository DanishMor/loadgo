import 'package:flutter/material.dart';

import '../../core/constants/logistics.dart';
import '../../core/services/load_service.dart';
import '../../core/widgets/common.dart';
import '../../main.dart';

/// Customer form to post a load. Pops with `true` once posted.
class PostLoadScreen extends StatefulWidget {
  const PostLoadScreen({super.key});

  @override
  State<PostLoadScreen> createState() => _PostLoadScreenState();
}

class _PostLoadScreenState extends State<PostLoadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pickupCtrl = TextEditingController();
  final _dropCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _cargoType = cargoTypes.first;
  String _vehicleType = '14ft';
  DateTime? _pickupDate;
  bool _saving = false;

  @override
  void dispose() {
    _pickupCtrl.dispose();
    _dropCtrl.dispose();
    _weightCtrl.dispose();
    _budgetCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(FormFieldState<DateTime> field) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _pickupDate ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 90)),
    );
    if (picked == null) return;
    setState(() => _pickupDate = picked);
    field.didChange(picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final budgetText = _budgetCtrl.text.trim();
      await LoadService.post(
        pickup: _pickupCtrl.text,
        drop: _dropCtrl.text,
        cargoType: _cargoType,
        weight: num.parse(_weightCtrl.text.trim()),
        vehicleType: _vehicleType,
        budget: budgetText.isEmpty ? null : num.parse(budgetText),
        pickupDate: _pickupDate!,
        notes: _notesCtrl.text,
      );
      if (!mounted) return;
      showSnack(context, tr(context, 'loadPosted'));
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  String? _requiredText(String? v) => (v == null || v.trim().length < 2) ? tr(context, 'fieldRequired') : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(tr(context, 'postLoad'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FieldLabel(tr(context, 'pickupLocation')),
                TextFormField(
                  controller: _pickupCtrl,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.trip_origin_rounded, color: AppColors.success)),
                  validator: _requiredText,
                ),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'dropLocation')),
                TextFormField(
                  controller: _dropCtrl,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.location_on_rounded, color: Colors.redAccent)),
                  validator: _requiredText,
                ),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'cargoType')),
                DropdownButtonFormField<String>(
                  initialValue: _cargoType,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.inventory_2_outlined)),
                  items: [for (final c in cargoTypes) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: (v) => setState(() => _cargoType = v ?? _cargoType),
                ),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'weightTons')),
                TextFormField(
                  controller: _weightCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.scale_outlined), hintText: 'e.g. 8'),
                  validator: (v) {
                    final n = num.tryParse(v?.trim() ?? '');
                    return (n == null || n <= 0 || n > 100) ? tr(context, 'invalidNumber') : null;
                  },
                ),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'vehicleTypeNeeded')),
                DropdownButtonFormField<String>(
                  initialValue: _vehicleType,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.local_shipping_outlined)),
                  items: [for (final t in vehicleTypes) DropdownMenuItem(value: t, child: Text(t))],
                  onChanged: (v) => setState(() => _vehicleType = v ?? _vehicleType),
                ),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'budgetOptional')),
                TextFormField(
                  controller: _budgetCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.currency_rupee_rounded)),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return null;
                    final n = num.tryParse(t);
                    return (n == null || n <= 0) ? tr(context, 'invalidNumber') : null;
                  },
                ),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'pickupDate')),
                FormField<DateTime>(
                  validator: (_) => _pickupDate == null ? tr(context, 'fieldRequired') : null,
                  builder: (field) => InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _pickDate(field),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.calendar_today_rounded),
                        errorText: field.errorText,
                      ),
                      child: Text(
                        _pickupDate == null ? '--' : formatDate(_pickupDate),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'notesOptional')),
                TextFormField(
                  controller: _notesCtrl,
                  maxLines: 3,
                  maxLength: 300,
                  decoration: const InputDecoration(),
                ),
                const SizedBox(height: 20),
                PrimaryButton(label: tr(context, 'postLoad'), icon: Icons.send_rounded, loading: _saving, onPressed: _submit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
