import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/constants/logistics.dart';
import '../core/l10n/l10n.dart';
import '../core/models/vehicle.dart';
import '../core/services/vehicle_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/logistics_labels.dart';

/// Insurance / PUC / fitness / permit details, next service date and the
/// maintenance switch for one vehicle. Text only: nothing is uploaded or
/// verified yet. LATER(paid): document photos (Storage) + RC/insurance KYC APIs.
class VehicleDocumentsScreen extends StatefulWidget {
  final Vehicle vehicle;
  const VehicleDocumentsScreen({super.key, required this.vehicle});

  @override
  State<VehicleDocumentsScreen> createState() => _VehicleDocumentsScreenState();
}

class _VehicleDocumentsScreenState extends State<VehicleDocumentsScreen> {
  late final Map<String, TextEditingController> _numbers = {
    for (final k in VehicleDocKind.all) k: TextEditingController(text: widget.vehicle.docs[k]?.number ?? ''),
  };
  late final Map<String, DateTime?> _expiry = {for (final k in VehicleDocKind.all) k: widget.vehicle.docs[k]?.expiry};
  late DateTime? _nextService = widget.vehicle.nextServiceDate;
  late DateTime? _nextTyre = widget.vehicle.nextTyreCheckDate;
  late bool _maintenance = widget.vehicle.availability == VehicleAvailability.maintenance;
  bool _saving = false;

  /// on_trip and suspended are not the driver's to change.
  bool get _canToggleMaintenance =>
      widget.vehicle.availability == VehicleAvailability.available ||
      widget.vehicle.availability == VehicleAvailability.maintenance;

  @override
  void dispose() {
    for (final c in _numbers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime? current) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 20),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await VehicleService.saveDocuments(widget.vehicle.id, {
        for (final k in VehicleDocKind.all) k: VehicleDocInfo(number: _numbers[k]!.text.trim(), expiry: _expiry[k]),
      }, nextServiceDate: _nextService, nextTyreCheckDate: _nextTyre);
      final wanted = _maintenance ? VehicleAvailability.maintenance : VehicleAvailability.available;
      if (_canToggleMaintenance && wanted != widget.vehicle.availability) {
        await VehicleService.setAvailability(widget.vehicle.id, wanted);
      }
      if (!mounted) return;
      showSnack(context, tr(context, 'docsSaved'));
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  Widget _dateRow({
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime?> onChanged,
    Key? key,
  }) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: key,
            onPressed: _saving
                ? null
                : () async {
                    final d = await _pick(value);
                    if (d != null) onChanged(d);
                  },
            icon: const Icon(Icons.event_rounded),
            label: Text(value == null ? label : '$label: ${formatDate(value)}'),
          ),
        ),
        if (value != null)
          IconButton(
            tooltip: tr(context, 'clearDate'),
            onPressed: _saving ? null : () => onChanged(null),
            icon: const Icon(Icons.close_rounded),
          ),
      ],
    );
  }

  Widget _docCard(String kind) {
    final now = DateTime.now();
    final info = VehicleDocInfo(number: _numbers[kind]!.text, expiry: _expiry[kind]);
    final expiring = _expiry[kind] != null && !_expiry[kind]!.isAfter(now.add(const Duration(days: 30)));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  vehicleDocLabel(context, kind),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.title),
                ),
              ),
              if (info.isExpired(now))
                StatusChip(label: tr(context, 'docExpired'), color: Colors.redAccent)
              else if (expiring)
                StatusChip(
                  label: trf(context, 'docExpiresOn', {'date': formatDate(_expiry[kind])}),
                  color: AppColors.warning,
                ),
              const SizedBox(width: 6),
              StatusChip(label: tr(context, 'unverified'), color: AppColors.faint),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            key: ValueKey('docNumber_$kind'),
            controller: _numbers[kind],
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(labelText: tr(context, 'docNumber')), inputFormatters: [LengthLimitingTextInputFormatter(30)]),
          const SizedBox(height: 8),
          _dateRow(
            key: ValueKey('docExpiry_$kind'),
            label: tr(context, 'docExpiry'),
            value: _expiry[kind],
            onChanged: (d) => setState(() => _expiry[kind] = d),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(tr(context, 'vehicleDocs'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      v.number,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.title),
                    ),
                  ),
                  StatusChip(
                    label: availabilityLabel(context, v.availability),
                    color: availabilityColor(v.availability),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(tr(context, 'docsTextOnly'), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              const SizedBox(height: 14),
              for (final k in VehicleDocKind.all) ...[_docCard(k), const SizedBox(height: 12)],
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _dateRow(
                      key: const ValueKey('nextService'),
                      label: tr(context, 'nextService'),
                      value: _nextService,
                      onChanged: (d) => setState(() => _nextService = d),
                    ),
                    const SizedBox(height: 8),
                    _dateRow(
                      key: const ValueKey('nextTyre'),
                      label: tr(context, 'tyreCheckDate'),
                      value: _nextTyre,
                      onChanged: (d) => setState(() => _nextTyre = d),
                    ),
                    SwitchListTile(
                      key: const ValueKey('maintenanceSwitch'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr(context, 'underMaintenance')),
                      value: _maintenance,
                      onChanged: _canToggleMaintenance && !_saving ? (x) => setState(() => _maintenance = x) : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              PrimaryButton(label: tr(context, 'save'), loading: _saving, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}
