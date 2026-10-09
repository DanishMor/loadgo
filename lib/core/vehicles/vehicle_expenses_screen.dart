import '../errors/error_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../models/vehicle_expense.dart';
import '../services/expense_service.dart';
import '../widgets/common.dart';
import '../widgets/live_stream.dart';

String expenseKindLabel(BuildContext context, String kind) => tr(context, switch (kind) {
      ExpenseKind.fuel => 'exFuel',
      ExpenseKind.toll => 'exToll',
      ExpenseKind.repair => 'exRepair',
      ExpenseKind.service => 'exService',
      _ => 'exOther',
    });

/// Fuel, toll, repair and service lines of one vehicle with totals by month
/// (V10). Private to the owner; a wrong line is deleted and entered again.
class VehicleExpensesScreen extends StatefulWidget {
  final String vehicleId;
  final String vehicleNumber;
  final Stream<List<VehicleExpense>>? source;

  const VehicleExpensesScreen({super.key, required this.vehicleId, required this.vehicleNumber, this.source});

  @override
  State<VehicleExpensesScreen> createState() => _VehicleExpensesScreenState();
}

class _VehicleExpensesScreenState extends State<VehicleExpensesScreen> {
  late final Stream<List<VehicleExpense>> _stream = (widget.source ?? ExpenseService.watchMine()).asBroadcastStream();

  Future<void> _add() async {
    var kind = ExpenseKind.fuel;
    final amount = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: Text(tr(c, 'exAdd')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                key: const ValueKey('exKind'),
                isExpanded: true,
                initialValue: kind,
                items: [for (final k in ExpenseKind.all) DropdownMenuItem(value: k, child: Text(expenseKindLabel(c, k)))],
                onChanged: (v) => setS(() => kind = v ?? kind),
              ),
              TextField(
                key: const ValueKey('exAmount'),
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: tr(c, 'exAmount')),
                inputFormatters: [LengthLimitingTextInputFormatter(10)],
              ),
              TextField(key: const ValueKey('exNote'), controller: note, maxLength: 100, decoration: InputDecoration(labelText: tr(c, 'exNote'))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr(c, 'cancel'))),
            FilledButton(key: const ValueKey('exSave'), onPressed: () => Navigator.pop(c, true), child: Text(tr(c, 'save'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final rupees = num.tryParse(amount.text.trim());
    final paise = rupees == null ? null : (rupees * 100).round();
    if (paise == null || paise < 1 || paise > VehicleExpense.maxPaise) return showSnack(context, tr(context, 'exInvalid'));
    try {
      await ExpenseService.add(vehicleId: widget.vehicleId, kind: kind, amountPaise: paise, note: note.text, date: DateTime.now());
    } catch (error) {
      if (mounted) showSnack(context, errorText(context, error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${tr(context, 'exTitle')} · ${widget.vehicleNumber}')),
      floatingActionButton: FloatingActionButton.extended(key: const ValueKey('exAddButton'), onPressed: _add, icon: const Icon(Icons.add_rounded), label: Text(tr(context, 'exAdd'))),
      body: LiveStream<List<VehicleExpense>>(
        stream: () => _stream,
        builder: (context, all) {
          final list = [for (final e in all) if (e.vehicleId == widget.vehicleId) e];
          if (list.isEmpty) return EmptyState(icon: Icons.receipt_long_outlined, title: tr(context, 'exNone'));
          final months = ExpenseSummary.byMonth(list);
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 90), children: [
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${tr(context, 'exTotal')}: ${formatPaise(ExpenseSummary.total(list))}', key: const ValueKey('exTotalText'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 6),
                Text(tr(context, 'exByMonth'), style: TextStyle(color: AppColors.muted)),
                for (final m in months.entries) Text('${m.key}: ${formatPaise(m.value)}', key: ValueKey('exMonth_${m.key}')),
              ]),
            ),
            const SizedBox(height: 8),
            for (final e in list)
              ListTile(
                key: ValueKey('exRow_${e.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text('${expenseKindLabel(context, e.kind)} · ${formatPaise(e.amountPaise)}'),
                subtitle: Text('${formatDate(e.date)}${e.note.isEmpty ? '' : ' · ${e.note}'}'),
                trailing: IconButton(tooltip: tr(context, 'a11yDelete'), icon: const Icon(Icons.delete_outline_rounded), onPressed: () => ExpenseService.delete(e.id)),
              ),
          ]);
        },
      ),
    );
  }
}
