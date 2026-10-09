import '../core/errors/error_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/enterprise/bulk_loads.dart';
import '../core/l10n/l10n.dart';
import '../core/models/risk.dart';
import '../core/services/enterprise_service.dart';
import '../core/services/vehicle_type_service.dart';
import '../core/widgets/common.dart';

/// Paste up to 10 lines (pickup, drop, cargo, weight, vehicle type[, budget])
/// and post them all with one pickup date.
class BulkPostScreen extends StatefulWidget {
  const BulkPostScreen({super.key});

  @override
  State<BulkPostScreen> createState() => _BulkPostScreenState();
}

class _BulkPostScreenState extends State<BulkPostScreen> {
  final _text = TextEditingController();
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  BulkParseResult get _parsed =>
      parseBulkLoads(_text.text, vehicleTypeIds: VehicleTypeService.ids, maxTonsFor: maxTonsOf);

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _post(BulkParseResult r) async {
    setState(() => _busy = true);
    try {
      final ids = await EnterpriseService.postBulk(r.rows, pickupDate: _date);
      if (!mounted) return;
      showSnack(context, trf(context, 'bulkPosted', {'n': ids.length}));
      Navigator.of(context).pop(true);
    } on BulkPostException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(
          context,
          e.cause is AccountRestrictedException
              ? tr(context, 'accountRestricted')
              : trf(context, 'bulkPartial', {'n': e.postedIds.length}));
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(context, errorText(context, error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _parsed;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'bulkPost'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(tr(context, 'bulkHelp'), style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 4),
        const Text('Delhi, Mumbai, FMCG, 8, 20ft, 25000', style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('bulkText'),
          controller: _text,
          minLines: 6,
          maxLines: 12,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}), inputFormatters: [LengthLimitingTextInputFormatter(5000)]),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_rounded),
          title: Text(formatDate(_date)),
          trailing: const Icon(Icons.edit_calendar_outlined),
          onTap: _pickDate,
        ),
        if (r.tooMany)
          Text(tr(context, 'bulkTooMany'), key: const ValueKey('bulkTooMany'), style: const TextStyle(color: Colors.redAccent)),
        for (final e in r.errors)
          Text(trf(context, 'bulkLineError', {'n': e.line}), key: ValueKey('bulkError_${e.line}'), style: const TextStyle(color: Colors.redAccent)),
        if (r.rows.isNotEmpty && r.errors.isEmpty && !r.tooMany)
          Text(trf(context, 'bulkReady', {'n': r.rows.length}), style: const TextStyle(color: AppColors.success)),
        const SizedBox(height: 12),
        FilledButton(
          key: const ValueKey('bulkSubmit'),
          onPressed: r.ok && !_busy ? () => _post(r) : null,
          child: Text(trf(context, 'bulkPostAll', {'n': r.rows.length})),
        ),
      ]),
    );
  }
}
