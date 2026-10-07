import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/analytics/unit_economics.dart';
import '../core/l10n/l10n.dart';
import '../core/services/admin_console_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Admin > Unit economics (super admin): the last 30 days in plain numbers,
/// with the two costs typed in rupees. Revenue is the commission recorded in
/// the driver ledger (no money moves through LoadGo yet).
class AdminUnitEconomicsScreen extends StatefulWidget {
  /// Test hooks.
  final Future<UnitEconomics> Function()? load;
  final Future<void> Function(EconomicsCosts)? save;
  const AdminUnitEconomicsScreen({super.key, this.load, this.save});

  @override
  State<AdminUnitEconomicsScreen> createState() => _AdminUnitEconomicsScreenState();
}

class _AdminUnitEconomicsScreenState extends State<AdminUnitEconomicsScreen> {
  late Future<UnitEconomics> _data = _load();
  final _fixed = TextEditingController();
  final _perTrip = TextEditingController();
  bool _filled = false;
  bool _saving = false;

  Future<UnitEconomics> _load() => (widget.load ?? AdminConsoleService.unitEconomics)();

  void _refresh() => setState(() {
        _data = _load();
        _filled = false;
      });

  @override
  void dispose() {
    _fixed.dispose();
    _perTrip.dispose();
    super.dispose();
  }

  String _rupees(int paise) => (paise / 100).toStringAsFixed(paise % 100 == 0 ? 0 : 2);

  int? _toPaise(String s) {
    final n = double.tryParse(s.trim());
    return n == null || n < 0 || n > 1e9 ? null : (n * 100).round();
  }

  Future<void> _save() async {
    final fixed = _toPaise(_fixed.text), per = _toPaise(_perTrip.text);
    if (fixed == null || per == null) return showSnack(context, tr(context, 'ueBadCost'));
    setState(() => _saving = true);
    try {
      await (widget.save ?? AdminConsoleService.saveEconomicsCosts)(EconomicsCosts(monthlyFixedPaise: fixed, perTripCostPaise: per));
      if (!mounted) return;
      showSnack(context, tr(context, 'featSaved'));
      _refresh();
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _row(String key, String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text(value, key: ValueKey('ue_$key'), style: TextStyle(fontWeight: FontWeight.w800, color: color)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'adminUnitEconomics')),
        actions: [IconButton(key: const ValueKey('ueRefresh'), tooltip: tr(context, 'retry'), onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: FutureBuilder<UnitEconomics>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(error: snap.error, onRetry: _refresh);
          final u = snap.data;
          if (u == null) return const Center(child: CircularProgressIndicator());
          if (!_filled) {
            _fixed.text = _rupees(u.costs.monthlyFixedPaise);
            _perTrip.text = _rupees(u.costs.perTripCostPaise);
            _filled = true;
          }
          String money(int? p) => p == null ? '-' : formatPaise(p);
          final profit = u.profitPaise;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(trf(context, 'ueNote', {'days': u.days}), style: TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 8),
            AppCard(
              child: Column(children: [
                _row('trips', tr(context, 'ueTrips'), '${u.trips}'),
                _row('cancelRate', tr(context, 'ueCancelRate'), u.cancelRate == null ? '-' : '${(u.cancelRate! * 100).toStringAsFixed(1)}%'),
                _row('value', tr(context, 'ueValue'), money(u.deliveredValuePaise)),
                _row('avgFare', tr(context, 'ueAvgFare'), money(u.avgFarePaise)),
                _row('revenue', tr(context, 'ueRevenue'), money(u.revenuePaise)),
                _row('takeRate', tr(context, 'ueTakeRate'), u.takeRateBp == null ? '-' : '${(u.takeRateBp! / 100).toStringAsFixed(2)}%'),
                _row('revPerTrip', tr(context, 'ueRevPerTrip'), money(u.revenuePerTripPaise)),
                _row('contribution', tr(context, 'ueContribution'), money(u.contributionPerTripPaise)),
                const Divider(),
                _row('profit', tr(context, 'ueResult'), formatPaise(profit), color: profit >= 0 ? AppColors.success : Colors.redAccent),
                _row('breakEven', tr(context, 'ueBreakEven'), u.breakEvenTrips == null ? '-' : '${u.breakEvenTrips}'),
              ]),
            ),
            const SizedBox(height: 16),
            Text(tr(context, 'ueCosts'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('ueFixed'),
              controller: _fixed,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [LengthLimitingTextInputFormatter(12), FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: InputDecoration(labelText: tr(context, 'ueFixedCost'), prefixText: '₹ '),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('uePerTrip'),
              controller: _perTrip,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [LengthLimitingTextInputFormatter(12), FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: InputDecoration(labelText: tr(context, 'uePerTripCost'), prefixText: '₹ '),
            ),
            const SizedBox(height: 12),
            FilledButton(key: const ValueKey('ueSave'), onPressed: _saving ? null : _save, child: Text(tr(context, 'save'))),
          ]);
        },
      ),
    );
  }
}
