import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../models/load_filter.dart';
import '../services/vehicle_type_service.dart';
import 'common.dart';
import 'logistics_labels.dart';

/// Bottom sheet for drop city, vehicle type, budget, weight and pickup dates.
/// Pops the new filter.
class LoadFilterSheet extends StatefulWidget {
  final LoadFilter initial;
  const LoadFilterSheet({super.key, required this.initial});

  @override
  State<LoadFilterSheet> createState() => _LoadFilterSheetState();
}

class _LoadFilterSheetState extends State<LoadFilterSheet> {
  late String? _type = widget.initial.vehicleType;
  late DateTime? _from = widget.initial.fromDate;
  late DateTime? _to = widget.initial.toDate;
  late final _dropCtrl = TextEditingController(text: widget.initial.dropQuery);
  late final _minBudget = TextEditingController(text: widget.initial.minBudget == null ? '' : formatNum(widget.initial.minBudget!));
  late final _maxBudget = TextEditingController(text: widget.initial.maxBudget == null ? '' : formatNum(widget.initial.maxBudget!));
  late final _minWeight = TextEditingController(text: widget.initial.minWeight == null ? '' : formatNum(widget.initial.minWeight!));
  late final _maxWeight = TextEditingController(text: widget.initial.maxWeight == null ? '' : formatNum(widget.initial.maxWeight!));

  @override
  void dispose() {
    for (final c in [_dropCtrl, _minBudget, _maxBudget, _minWeight, _maxWeight]) {
      c.dispose();
    }
    super.dispose();
  }

  num? _num(TextEditingController c) {
    final n = num.tryParse(c.text.trim());
    return (n == null || n <= 0) ? null : n;
  }

  void _apply() {
    Navigator.of(context).pop(widget.initial.copyWith(
      dropQuery: _dropCtrl.text.trim(),
      vehicleType: () => _type,
      minBudget: () => _num(_minBudget),
      maxBudget: () => _num(_maxBudget),
      minWeight: () => _num(_minWeight),
      maxWeight: () => _num(_maxWeight),
      fromDate: () => _from,
      toDate: () => _to,
    ));
  }

  Future<void> _pick(bool from) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (d != null) setState(() => from ? _from = d : _to = d);
  }

  Widget _numField(String key, TextEditingController c, String label, {IconData? icon}) => Expanded(
        child: TextField(
          key: ValueKey(key),
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, prefixIcon: icon == null ? null : Icon(icon)), inputFormatters: [LengthLimitingTextInputFormatter(100)]),
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(context, 'filters'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(key: const ValueKey('dropFilter'), controller: _dropCtrl, decoration: InputDecoration(labelText: tr(context, 'filterDrop')), inputFormatters: [LengthLimitingTextInputFormatter(100)]),
            const SizedBox(height: 16),
            FieldLabel(tr(context, 'vehicleType')),
            DropdownButtonFormField<String?>(
              isExpanded: true,
              key: const ValueKey('vehicleTypeFilter'),
              initialValue: _type,
              items: [
                DropdownMenuItem(value: null, child: Text(tr(context, 'allTypes'))),
                for (final t in VehicleTypeService.ids) DropdownMenuItem(value: t, child: Text(vehicleTypeLabel(context, t))),
              ],
              onChanged: (v) => setState(() => _type = v),
            ),
            const SizedBox(height: 16),
            Row(children: [
              _numField('minBudgetFilter', _minBudget, tr(context, 'minBudget'), icon: Icons.currency_rupee_rounded),
              const SizedBox(width: 8),
              _numField('maxBudgetFilter', _maxBudget, tr(context, 'maxBudgetLabel'), icon: Icons.currency_rupee_rounded),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              _numField('minWeightFilter', _minWeight, tr(context, 'weightMin')),
              const SizedBox(width: 8),
              _numField('maxWeightFilter', _maxWeight, tr(context, 'weightMax')),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('fromDateFilter'),
                  onPressed: () => _pick(true),
                  child: Text(_from == null ? tr(context, 'filterDateFrom') : formatDate(_from!)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('toDateFilter'),
                  onPressed: () => _pick(false),
                  child: Text(_to == null ? tr(context, 'filterDateTo') : formatDate(_to!)),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(LoadFilter(pickupQuery: widget.initial.pickupQuery)),
                    child: Text(tr(context, 'clearFilters')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: FilledButton(key: const ValueKey('applyFilters'), onPressed: _apply, child: Text(tr(context, 'applyFilters')))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens [LoadFilterSheet] and returns the new filter (null when closed without applying).
Future<LoadFilter?> showLoadFilterSheet(BuildContext context, LoadFilter initial) => showModalBottomSheet<LoadFilter>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (_) => LoadFilterSheet(initial: initial),
    );
