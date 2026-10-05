import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/l10n.dart';
import '../core/models/driver_extras.dart';
import '../core/services/driver_extras_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Admin: driver incentives (create, switch off), claims to pay by hand, and
/// Pro plan requests / manual plan changes.
class AdminDriverRewardsScreen extends StatelessWidget {
  const AdminDriverRewardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr(context, 'adminDriverRewards')),
          bottom: TabBar(tabs: [
            Tab(text: tr(context, 'incentivesTitle')),
            Tab(text: tr(context, 'adminClaims')),
            Tab(text: tr(context, 'adminPlans')),
          ]),
        ),
        body: const TabBarView(children: [_IncentivesTab(), _ClaimsTab(), _PlansTab()]),
      ),
    );
  }
}

class _IncentivesTab extends StatelessWidget {
  const _IncentivesTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('newIncentive'),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IncentiveEditScreen())),
        icon: const Icon(Icons.add_rounded),
        label: Text(tr(context, 'newIncentive')),
      ),
      body: LiveStream<List<Incentive>>(
        stream: () => DriverExtrasService.watchIncentives(onlyActive: false),
        builder: (context, list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
          children: [
            if (list.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(tr(context, 'noIncentives'))),
            for (final i in list)
              ListTile(
                key: ValueKey('adminIncentive_${i.id}'),
                title: Text(i.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${trf(context, 'incentiveRule', {'trips': i.targetTrips, 'days': i.windowDays, 'bonus': formatPaise(i.bonusPaise)})}\n${formatDate(i.startsAt)}'),
                isThreeLine: true,
                trailing: Switch(
                  value: i.active,
                  onChanged: (v) => DriverExtrasService.saveIncentive(
                    Incentive(id: i.id, title: i.title, targetTrips: i.targetTrips, windowDays: i.windowDays, bonusPaise: i.bonusPaise, startsAt: i.startsAt, active: v),
                    id: i.id,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// New incentive: X trips in Y days = Z rupees, starting now.
class IncentiveEditScreen extends StatefulWidget {
  const IncentiveEditScreen({super.key});

  @override
  State<IncentiveEditScreen> createState() => _IncentiveEditScreenState();
}

class _IncentiveEditScreenState extends State<IncentiveEditScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _trips = TextEditingController(text: '10');
  final _days = TextEditingController(text: '7');
  final _bonus = TextEditingController(text: '500');
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_title, _trips, _days, _bonus]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _int(String? v, int min, int max) {
    final n = int.tryParse(v?.trim() ?? '');
    return (n == null || n < min || n > max) ? tr(context, 'invalidNumber') : null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await DriverExtrasService.saveIncentive(Incentive(
        id: '',
        title: _title.text.trim(),
        targetTrips: int.parse(_trips.text.trim()),
        windowDays: int.parse(_days.text.trim()),
        bonusPaise: int.parse(_bonus.text.trim()) * 100,
        startsAt: DateTime.now(),
      ));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'newIncentive'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          TextFormField(
            key: const ValueKey('incTitle'),
            controller: _title,
            maxLength: 60,
            decoration: InputDecoration(labelText: tr(context, 'incentiveName')),
            validator: (v) => (v ?? '').trim().length < 2 ? tr(context, 'fieldRequired') : null,
          ),
          TextFormField(key: const ValueKey('incTrips'), controller: _trips, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr(context, 'incentiveTrips')), validator: (v) => _int(v, 1, 1000), inputFormatters: [LengthLimitingTextInputFormatter(10)]),
          TextFormField(key: const ValueKey('incDays'), controller: _days, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr(context, 'incentiveDays')), validator: (v) => _int(v, 1, 365), inputFormatters: [LengthLimitingTextInputFormatter(10)]),
          TextFormField(key: const ValueKey('incBonus'), controller: _bonus, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr(context, 'incentiveBonus')), validator: (v) => _int(v, 1, 100000), inputFormatters: [LengthLimitingTextInputFormatter(10)]),
          const SizedBox(height: 20),
          PrimaryButton(label: tr(context, 'save'), loading: _saving, onPressed: _save),
        ]),
      ),
    );
  }
}

class _ClaimsTab extends StatelessWidget {
  const _ClaimsTab();

  @override
  Widget build(BuildContext context) {
    return LiveStream<List<IncentiveClaim>>(
      stream: DriverExtrasService.watchAllClaims,
      builder: (context, claims) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (claims.isEmpty) Text(tr(context, 'noClaims')),
          for (final c in claims)
            ListTile(
              key: ValueKey('claim_${c.id}'),
              title: Text('${formatPaise(c.bonusPaise)} · ${c.driverId}'),
              subtitle: Text('${c.incentiveId} · ${c.createdAt == null ? '' : formatDateTime(c.createdAt!)}'),
              trailing: c.status == IncentiveClaim.paid
                  ? Text(tr(context, 'claimPaid'), style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700))
                  : FilledButton.tonal(
                      key: ValueKey('markPaid_${c.id}'),
                      onPressed: () => DriverExtrasService.markClaimPaid(c.id),
                      child: Text(tr(context, 'markClaimPaid')),
                    ),
            ),
        ],
      ),
    );
  }
}

class _PlansTab extends StatefulWidget {
  const _PlansTab();

  @override
  State<_PlansTab> createState() => _PlansTabState();
}

class _PlansTabState extends State<_PlansTab> {
  final _uid = TextEditingController();
  final _days = TextEditingController(text: '30');

  @override
  void dispose() {
    _uid.dispose();
    _days.dispose();
    super.dispose();
  }

  Future<void> _set(String driverId, String plan) async {
    try {
      await DriverExtrasService.setPlan(driverId, plan, days: int.tryParse(_days.text.trim()));
      if (mounted) showSnack(context, tr(context, 'settingsSaved'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      TextField(key: const ValueKey('planDays'), controller: _days, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr(context, 'planDays')), inputFormatters: [LengthLimitingTextInputFormatter(10)]),
      const SizedBox(height: 8),
      Text(tr(context, 'planRequests'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      LiveStream<List<dynamic>>(
        stream: DriverExtrasService.watchPlanRequests,
        compact: true,
        builder: (context, docs) {
          final pending = [for (final d in docs) if (d.data()['status'] == DriverPlan.requestPending) d];
          if (pending.isEmpty) return Padding(padding: const EdgeInsets.all(8), child: Text(tr(context, 'noPlanRequests')));
          return Column(children: [
            for (final d in pending)
              ListTile(
                key: ValueKey('planRequest_${d.id}'),
                title: Text(d.id),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  TextButton(key: ValueKey('rejectPlan_${d.id}'), onPressed: () => DriverExtrasService.rejectPlanRequest(d.id), child: Text(tr(context, 'reject'))),
                  FilledButton(key: ValueKey('approvePlan_${d.id}'), onPressed: () => _set(d.id, DriverPlan.pro), child: Text(tr(context, 'approve'))),
                ]),
              ),
          ]);
        },
      ),
      const Divider(height: 32),
      TextField(key: const ValueKey('planUid'), controller: _uid, decoration: InputDecoration(labelText: tr(context, 'userId')), inputFormatters: [LengthLimitingTextInputFormatter(128)]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: FilledButton(key: const ValueKey('setPro'), onPressed: () => _set(_uid.text.trim(), DriverPlan.pro), child: Text(tr(context, 'planSetPro')))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton(key: const ValueKey('setFree'), onPressed: () => _set(_uid.text.trim(), DriverPlan.free), child: Text(tr(context, 'planSetFree')))),
      ]),
    ]);
  }
}
