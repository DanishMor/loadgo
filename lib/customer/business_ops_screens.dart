import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/enterprise/business_roles.dart';
import '../core/l10n/l10n.dart';
import '../core/models/business_ops.dart';
import '../core/models/load.dart';
import '../core/models/repeat.dart';
import '../core/models/support_ticket.dart';
import '../core/services/business_ops_service.dart';
import '../core/services/repeat_service.dart';
import '../core/services/support_service.dart';
import '../core/support/support_screens.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import '../core/widgets/load_card.dart';

/// Rupees typed as text to paise (null when not a positive amount).
int? _paise(String text) {
  final v = double.tryParse(text.trim());
  if (v == null || v < 0) return null;
  return (v * 100).round();
}

/// BIZ6: the approval limit (owner) and the loads waiting for the owner or a manager.
class ApprovalsScreen extends StatefulWidget {
  final BizContext context;
  const ApprovalsScreen({super.key, required this.context});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  final _limit = TextEditingController();
  late final Stream<List<Load>> _waiting = BusinessOpsService.watchAwaitingApproval(widget.context.ownerId).asBroadcastStream();

  @override
  void initState() {
    super.initState();
    BusinessOpsService.approvalLimit(widget.context.ownerId).then((p) {
      if (mounted && p > 0) _limit.text = '${p ~/ 100}';
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  Future<void> _saveLimit() async {
    final p = _paise(_limit.text.isEmpty ? '0' : _limit.text);
    if (p == null) return;
    try {
      await BusinessOpsService.setApprovalLimit(p);
      if (mounted) showSnack(context, tr(context, 'bizApprovalSaved'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  Future<void> _decide(Load l, bool approve) async {
    try {
      await BusinessOpsService.decide(l, approve: approve);
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'bizApprovals'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (widget.context.isOwner)
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('approvalLimit'),
                    controller: _limit,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
                    decoration: InputDecoration(labelText: tr(context, 'bizApprovalLimit')),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(key: const ValueKey('approvalLimitSave'), onPressed: _saveLimit, child: Text(tr(context, 'save'))),
              ]),
              Text(tr(context, 'bizApprovalHelp'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
            ]),
          ),
        const SizedBox(height: 12),
        LiveStream<List<Load>>(
          stream: () => _waiting,
          compact: true,
          builder: (context, loads) {
            if (loads.isEmpty) return Padding(padding: const EdgeInsets.all(16), child: Text(tr(context, 'bizNoApprovals'), style: TextStyle(color: AppColors.muted)));
            return Column(children: [
              for (final l in loads)
                Column(key: ValueKey('approval_${l.id}'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  LoadCard(load: l, showStatus: false),
                  Row(children: [
                    Expanded(child: OutlinedButton(key: ValueKey('reject_${l.id}'), onPressed: () => _decide(l, false), child: Text(tr(context, 'bizReject')))),
                    const SizedBox(width: 8),
                    Expanded(child: FilledButton(key: ValueKey('approve_${l.id}'), onPressed: () => _decide(l, true), child: Text(tr(context, 'bizApprove')))),
                  ]),
                  const SizedBox(height: 12),
                ]),
            ]);
          },
        ),
      ]),
    );
  }
}

/// BIZ8: vehicles the company hires on contract.
class ContractsScreen extends StatelessWidget {
  final BizContext context;
  const ContractsScreen({super.key, required this.context});

  Future<void> _add(BuildContext c) async {
    final number = TextEditingController(), type = TextEditingController(), vendor = TextEditingController(), rate = TextEditingController();
    DateTime? until;
    final ok = await showDialog<bool>(
      context: c,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(tr(d, 'bizContractAdd')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(key: const ValueKey('cvNumber'), controller: number, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: tr(d, 'vehicleNumber'))),
              TextField(key: const ValueKey('cvType'), controller: type, decoration: InputDecoration(labelText: tr(d, 'vehicleType'))),
              TextField(key: const ValueKey('cvVendor'), controller: vendor, decoration: InputDecoration(labelText: tr(d, 'bizVendor'))),
              TextField(key: const ValueKey('cvRate'), controller: rate, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr(d, 'bizRate'))),
              TextButton.icon(
                key: const ValueKey('cvUntil'),
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(until == null ? tr(d, 'ewayPickDate') : '${tr(d, 'ewayValidUntil')}: ${formatDate(until)}'),
                onPressed: () async {
                  final now = DateTime.now();
                  final p = await showDatePicker(context: d, initialDate: now.add(const Duration(days: 30)), firstDate: now, lastDate: now.add(const Duration(days: 1500)));
                  if (p != null) set(() => until = DateTime(p.year, p.month, p.day, 23, 59));
                },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(d).pop(false), child: Text(tr(d, 'cancel'))),
            FilledButton(key: const ValueKey('cvSave'), onPressed: () => Navigator.of(d).pop(true), child: Text(tr(d, 'save'))),
          ],
        ),
      ),
    );
    if (ok != true || !c.mounted) return;
    try {
      await BusinessOpsService.addContract(context.ownerId,
          vehicleNumber: number.text, vehicleType: type.text.trim(), vendorName: vendor.text, ratePerTripPaise: rate.text.trim().isEmpty ? null : _paise(rate.text), validUntil: until);
    } catch (_) {
      if (c.mounted) showSnack(c, tr(c, 'somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = this.context.can(BizPerm.manageContracts);
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'bizContracts'))),
      floatingActionButton: canEdit ? FloatingActionButton.extended(key: const ValueKey('cvAdd'), onPressed: () => _add(context), icon: const Icon(Icons.add_rounded), label: Text(tr(context, 'bizContractAdd'))) : null,
      body: LiveStream<List<ContractVehicle>>(
        stream: () => BusinessOpsService.watchContracts(this.context.ownerId),
        builder: (context, list) {
          if (list.isEmpty) return EmptyState(icon: Icons.local_shipping_outlined, title: tr(context, 'bizNoContracts'));
          return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 88), children: [
            for (final v in list)
              ListTile(
                key: ValueKey('contract_${v.id}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.local_shipping_outlined),
                title: Text('${v.vehicleNumber}${v.vehicleType.isEmpty ? '' : ' · ${v.vehicleType}'}'),
                subtitle: Text([
                  v.vendorName,
                  if (v.ratePerTripPaise != null) formatPaise(v.ratePerTripPaise!),
                  if (v.validUntil != null) (v.expired(DateTime.now()) ? tr(context, 'bizExpired') : '${tr(context, 'ewayValidUntil')} ${formatDate(v.validUntil)}'),
                ].join(' · ')),
                trailing: canEdit ? IconButton(key: ValueKey('cvDelete_${v.id}'), tooltip: tr(context, 'remove'), icon: const Icon(Icons.delete_outline_rounded), onPressed: () => BusinessOpsService.deleteContract(v.id)) : null,
              ),
          ]);
        },
      ),
    );
  }
}

/// BIZ9: the drivers the company approved; loads can be limited to them.
class PoolScreen extends StatelessWidget {
  final BizContext context;
  const PoolScreen({super.key, required this.context});

  Future<void> _add(BuildContext c) async {
    final favs = await RepeatService.watchFavourites().first;
    if (!c.mounted) return;
    final pool = {for (final p in await BusinessOpsService.watchPool(context.ownerId).first) p.driverId};
    final free = [for (final f in favs) if (!pool.contains(f.driverId)) f];
    if (!c.mounted) return;
    if (free.isEmpty) {
      showSnack(c, tr(c, 'favouritesNone'));
      return;
    }
    final pick = await showModalBottomSheet<FavouriteDriver>(
      context: c,
      showDragHandle: true,
      builder: (s) => SafeArea(child: ListView(shrinkWrap: true, children: [
        for (final f in free) ListTile(key: ValueKey('poolPick_${f.driverId}'), title: Text(f.name.isEmpty ? f.driverId : f.name), subtitle: Text(f.vehicleNumber), onTap: () => Navigator.of(s).pop(f)),
      ])),
    );
    if (pick == null) return;
    try {
      await BusinessOpsService.addToPool(context.ownerId, driverId: pick.driverId, name: pick.name, vehicleNumber: pick.vehicleNumber);
    } catch (_) {
      if (c.mounted) showSnack(c, tr(c, 'somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = this.context.can(BizPerm.managePool);
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'bizPool'))),
      floatingActionButton: canEdit ? FloatingActionButton.extended(key: const ValueKey('poolAdd'), onPressed: () => _add(context), icon: const Icon(Icons.person_add_alt_1_rounded), label: Text(tr(context, 'bizPoolAdd'))) : null,
      body: LiveStream<List<PoolDriver>>(
        stream: () => BusinessOpsService.watchPool(this.context.ownerId),
        builder: (context, list) {
          if (list.isEmpty) return EmptyState(icon: Icons.verified_user_outlined, title: tr(context, 'bizPoolNone'));
          return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 88), children: [
            for (final p in list)
              ListTile(
                key: ValueKey('pool_${p.driverId}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.verified_user_outlined),
                title: Text(p.name.isEmpty ? p.driverId : p.name),
                subtitle: Text(p.vehicleNumber),
                trailing: canEdit ? IconButton(key: ValueKey('poolRemove_${p.driverId}'), tooltip: tr(context, 'remove'), icon: const Icon(Icons.close_rounded), onPressed: () => BusinessOpsService.removeFromPool(this.context.ownerId, p.driverId)) : null,
              ),
          ]);
        },
      ),
    );
  }
}

String bizExpenseKindLabel(BuildContext context, String kind) => tr(context, switch (kind) {
      BizExpenseKind.fuel => 'exFuel',
      BizExpenseKind.toll => 'exToll',
      BizExpenseKind.loading => 'bizLoading',
      BizExpenseKind.detention => 'bizDetention',
      _ => 'exOther',
    });

/// BIZ10: transport spend by month (freight from delivered bookings plus
/// recorded fuel, toll, loading and other costs).
class SpendDashboardScreen extends StatefulWidget {
  final BizContext context;
  final DateTime Function() now;
  const SpendDashboardScreen({super.key, required this.context, this.now = DateTime.now});

  @override
  State<SpendDashboardScreen> createState() => _SpendDashboardScreenState();
}

class _SpendDashboardScreenState extends State<SpendDashboardScreen> {
  late final _expenses = BusinessOpsService.watchExpenses(widget.context.ownerId).asBroadcastStream();
  late final _bookings = BusinessOpsService.watchCompanyBookings(widget.context.ownerId).asBroadcastStream();

  Future<void> _add() async {
    final amount = TextEditingController(), note = TextEditingController();
    var kind = BizExpenseKind.fuel;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(tr(d, 'bizAddExpense')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(spacing: 8, children: [
              for (final k in BizExpenseKind.all) ChoiceChip(key: ValueKey('bizKind_$k'), label: Text(bizExpenseKindLabel(d, k)), selected: kind == k, onSelected: (_) => set(() => kind = k)),
            ]),
            TextField(key: const ValueKey('bizAmount'), controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr(d, 'exAmount'))),
            TextField(key: const ValueKey('bizNote'), controller: note, maxLength: 100, decoration: InputDecoration(labelText: tr(d, 'exNote'))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(d).pop(false), child: Text(tr(d, 'cancel'))),
            FilledButton(key: const ValueKey('bizExpenseSave'), onPressed: () => Navigator.of(d).pop(true), child: Text(tr(d, 'save'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final p = _paise(amount.text);
    try {
      if (p == null || p < 1) throw ArgumentError('amount');
      await BusinessOpsService.addExpense(widget.context.ownerId, kind: kind, amountPaise: p, date: widget.now(), note: note.text);
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'exInvalid'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = widget.context.can(BizPerm.manageExpenses);
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'bizExpenses'))),
      floatingActionButton: canEdit ? FloatingActionButton.extended(key: const ValueKey('bizAddExpense'), onPressed: _add, icon: const Icon(Icons.add_rounded), label: Text(tr(context, 'bizAddExpense'))) : null,
      body: LiveStream<List<BizExpense>>(
        stream: () => _expenses,
        builder: (context, expenses) => LiveStream(
          stream: () => _bookings,
          builder: (context, bookings) {
            final months = spendDashboard(bookings, expenses, widget.now());
            final maxTotal = months.map((m) => m.totalPaise).fold(0, (a, b) => a > b ? a : b);
            return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 88), children: [
              for (final m in months.reversed)
                AppCard(
                  key: ValueKey('spend_${m.month}'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(m.month, style: const TextStyle(fontWeight: FontWeight.w800)),
                      const Spacer(),
                      Text(formatPaise(m.totalPaise), key: ValueKey('spendTotal_${m.month}'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: maxTotal == 0 ? 0 : m.totalPaise / maxTotal, minHeight: 8)),
                    const SizedBox(height: 6),
                    Text('${tr(context, 'bizFreight')}: ${formatPaise(m.freightPaise)}', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    for (final k in BizExpenseKind.all)
                      if ((m.byKind[k] ?? 0) > 0) Text('${bizExpenseKindLabel(context, k)}: ${formatPaise(m.byKind[k]!)}', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  ]),
                ),
              const SizedBox(height: 8),
              if (expenses.isEmpty) Text(tr(context, 'bizNoExpenses'), style: TextStyle(color: AppColors.muted)),
              for (final e in expenses.take(30))
                ListTile(
                  key: ValueKey('expense_${e.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${bizExpenseKindLabel(context, e.kind)} · ${formatPaise(e.amountPaise)}'),
                  subtitle: Text('${formatDate(e.date)}${e.note.isEmpty ? '' : ' · ${e.note}'}'),
                  trailing: canEdit ? IconButton(tooltip: tr(context, 'remove'), icon: const Icon(Icons.delete_outline_rounded), onPressed: () => BusinessOpsService.deleteExpense(e.id)) : null,
                ),
            ]);
          },
        ),
      ),
    );
  }
}

/// BIZ15: the company's own ticket queue; tickets carry the company id and
/// start at high priority for LoadGo support.
class BusinessSupportScreen extends StatelessWidget {
  final BizContext context;
  const BusinessSupportScreen({super.key, required this.context});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'bizSupport'))),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('bizTicketNew'),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NewTicketScreen(businessId: this.context.ownerId))),
        icon: const Icon(Icons.add_rounded),
        label: Text(tr(context, 'bizSupportNew')),
      ),
      body: LiveStream<List<SupportTicket>>(
        stream: () => SupportService.watchForBusiness(this.context.ownerId),
        builder: (context, list) {
          if (list.isEmpty) return EmptyState(icon: Icons.support_agent_rounded, title: tr(context, 'bizSupportNone'));
          return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 88), children: [
            for (final t in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TicketTile(
                  key: ValueKey('bizTicket_${t.id}'),
                  ticket: t,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TicketDetailScreen(ticketId: t.id))),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
