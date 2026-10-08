import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'admin_user_screen.dart';
import 'package:flutter/services.dart';
import '../core/documents/doc_expiry.dart';

import '../core/constants/logistics.dart';
import '../core/l10n/l10n.dart';
import '../core/models/booking.dart';
import '../core/models/risk.dart';
import '../core/models/support_ticket.dart';
import '../core/admin/staff_roles.dart';
import '../core/services/admin_console_service.dart';
import '../core/services/auth_helpers.dart';
import '../core/services/admin_user_service.dart';
import '../core/share/share_csv.dart';
import '../core/support/support_screens.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import '../core/widgets/logistics_labels.dart';
import '../core/services/fraud_case_service.dart';
import 'admin_chat_review_screen.dart';
import '../core/services/comm_admin_service.dart';
import 'admin_fraud_cases_screen.dart';
import 'flagged_users_screen.dart';

typedef Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

String _ts(Object? v) => v is Timestamp ? v.toDate().toString().split('.').first : '';

Widget _empty(BuildContext context) => EmptyState(icon: Icons.inbox_outlined, title: tr(context, 'adminNothingHere'));

/// Scaffold with a live list; newest first by [sortKey].
class _LiveList extends StatelessWidget {
  final String titleKey;
  final Stream<List<Doc>> Function() stream;
  final String sortKey;
  final Widget Function(BuildContext, Doc) tile;
  final List<Widget> header;

  const _LiveList({
    super.key,
    required this.titleKey,
    required this.stream,
    required this.tile,
    this.sortKey = 'createdAt',
    this.header = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, titleKey))),
      body: Column(children: [
        ...header,
        Expanded(
          child: LiveStream<List<Doc>>(
            stream: stream,
            builder: (context, docs) {
              if (docs.isEmpty) return _empty(context);
              final list = [...docs]..sort((a, b) {
                  final x = a.data()[sortKey], y = b.data()[sortKey];
                  if (x is Timestamp && y is Timestamp) return y.compareTo(x);
                  return 0;
                });
              return ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => tile(context, list[i]),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ---- users ----

class AdminUsersScreen extends StatefulWidget {
  /// Shares exported CSV text; defaults to the system share sheet. A test hook.
  final Future<bool> Function(String csv, String subject)? share;

  const AdminUsersScreen({super.key, this.share});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  late Future<List<Doc>> _users = AdminConsoleService.users();
  late final Future<String> _role = AdminConsoleService.staffRole();
  String _query = '';
  final _selected = <String>{};
  List<Doc> _loaded = const [];

  bool get _selecting => _selected.isNotEmpty;

  void _toggle(String uid) => setState(() => _selected.contains(uid) ? _selected.remove(uid) : _selected.add(uid));

  Future<void> _export() async {
    final subject = tr(context, 'adminUsers');
    final failed = tr(context, 'cannotOpenLink');
    final ok = await (widget.share ?? shareCsv)(await AdminConsoleService.usersCsv(), subject);
    if (!ok && mounted) showSnack(context, failed);
  }

  /// Asks for a reason (and a status for "set status"); null when cancelled.
  Future<({String reason, String? tier})?> _ask({required String titleKey, bool pickTier = false, bool needReason = true}) async {
    final reason = TextEditingController();
    String tier = RiskTier.review;
    return showDialog<({String reason, String? tier})>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(trf(c, titleKey, {'n': _selected.length})),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (pickTier)
              Wrap(spacing: 6, children: [
                for (final t in AdminUserService.bulkTiers)
                  ChoiceChip(key: ValueKey('bulkTier_$t'), label: Text(riskTierLabel(c, t)), selected: tier == t, onSelected: (_) => set(() => tier = t)),
              ]),
            TextField(
              key: const ValueKey('bulkReason'),
              controller: reason,
              inputFormatters: [LengthLimitingTextInputFormatter(200)],
              decoration: InputDecoration(labelText: tr(c, needReason ? 'bulkReason' : 'bulkReasonOptional')),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text(tr(c, 'cancel'))),
            FilledButton(key: const ValueKey('bulkConfirm'), onPressed: () => Navigator.pop(c, (reason: reason.text, tier: pickTier ? tier : null)), child: Text(tr(c, 'save'))),
          ],
        ),
      ),
    );
  }

  Future<void> _bulk(String action) async {
    final ask = await _ask(
      titleKey: switch (action) { UserAction.bulkHold => 'bulkHoldTitle', UserAction.bulkUnhold => 'bulkUnholdTitle', _ => 'bulkStatusTitle' },
      pickTier: action == UserAction.bulkStatus,
      needReason: action != UserAction.bulkUnhold,
    );
    if (ask == null || !mounted) return;
    final tier = switch (action) { UserAction.bulkHold => RiskTier.restricted, UserAction.bulkUnhold => RiskTier.normal, _ => ask.tier! };
    final current = {
      for (final d in _loaded)
        if (_selected.contains(d.id)) d.id: d.data()['riskTier'] as String? ?? RiskTier.normal,
    };
    try {
      final r = await AdminUserService.bulkSetTier(current, tier, action: action, reason: ask.reason);
      if (!mounted) return;
      showSnack(context, trf(context, 'bulkDone', {'n': r.changed, 'm': r.skipped}));
      setState(() {
        _selected.clear();
        _users = AdminConsoleService.users();
      });
    } on UserActionException {
      if (mounted) showSnack(context, tr(context, 'auReasonNeeded'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  Widget _bulkBar() => FutureBuilder<String>(
        future: _role,
        builder: (context, snap) {
          if (!staffCan(snap.data, 'flaggedUsers')) return const SizedBox.shrink();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.center, children: [
                FilledButton(key: const ValueKey('bulkHold'), onPressed: () => _bulk(UserAction.bulkHold), child: Text(tr(context, 'bulkHold'))),
                OutlinedButton(key: const ValueKey('bulkUnhold'), onPressed: () => _bulk(UserAction.bulkUnhold), child: Text(tr(context, 'bulkUnhold'))),
                OutlinedButton(key: const ValueKey('bulkStatus'), onPressed: () => _bulk(UserAction.bulkStatus), child: Text(tr(context, 'bulkStatus'))),
              ]),
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selecting ? trf(context, 'bulkSelected', {'n': _selected.length}) : tr(context, 'adminUsers')),
        leading: _selecting ? IconButton(key: const ValueKey('bulkClear'), tooltip: tr(context, 'clear'), onPressed: () => setState(_selected.clear), icon: const Icon(Icons.close_rounded)) : null,
        actions: [
          if (!_selecting) IconButton(key: const ValueKey('exportUsers'), tooltip: tr(context, 'exportCsv'), onPressed: _export, icon: const Icon(Icons.ios_share_rounded)),
        ],
      ),
      bottomNavigationBar: _selecting ? _bulkBar() : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            key: const ValueKey('userSearch'),
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr(context, 'adminSearchHint')),
            onChanged: (v) => setState(() => _query = v), inputFormatters: [LengthLimitingTextInputFormatter(30)]),
        ),
        Expanded(
          child: FutureBuilder<List<Doc>>(
            future: _users,
            builder: (context, snap) {
              if (snap.hasError) return ErrorState(error: snap.error);
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              _loaded = snap.data!;
              final list = [for (final d in snap.data!) if (AdminConsoleService.userMatches(d.data(), d.id, _query)) d];
              if (list.isEmpty) return _empty(context);
              return ListView.builder(itemCount: list.length, itemBuilder: (context, i) {
                final d = list[i];
                return ListTile(
                    key: ValueKey('user_${d.id}'),
                    selected: _selected.contains(d.id),
                    leading: _selecting ? Checkbox(key: ValueKey('pick_${d.id}'), value: _selected.contains(d.id), onChanged: (_) => _toggle(d.id)) : null,
                    title: Text((d.data()['name'] ?? d.data()['driverName'] ?? d.id).toString()),
                    subtitle: Text([
                      maskPhone(d.data()['phone'] as String?),
                      riskTierLabel(context, d.data()['riskTier'] as String? ?? RiskTier.normal),
                      if ((d.data()['roles'] as List?)?.isNotEmpty ?? false) (d.data()['roles'] as List).join('/'),
                      if (DocExpiry.licenceBlocked(d.data(), DateTime.now())) tr(context, 'adminLicenceExpiredTag'),
                    ].where((e) => e.toString().isNotEmpty).join(' · ')),
                    trailing: _selecting
                        ? null
                        : DocExpiry.licenceBlocked(d.data(), DateTime.now())
                            ? TextButton(
                                key: ValueKey('licenceOverride_${d.id}'),
                                onPressed: () async {
                                  await AdminConsoleService.overrideLicence(d.id);
                                  if (context.mounted) showSnack(context, tr(context, 'docOverrideDone'));
                                  setState(() {
                                    _users = AdminConsoleService.users();
                                  });
                                },
                                child: Text(tr(context, 'adminDocOverride')),
                              )
                            : const Icon(Icons.edit_outlined),
                    onLongPress: () => _toggle(d.id),
                    onTap: _selecting
                        ? () => _toggle(d.id)
                        : () async {
                            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminUserScreen(uid: d.id)));
                            if (mounted) {
                              setState(() {
                                _users = AdminConsoleService.users();
                              });
                            }
                          },
                  );
              });
            },
          ),
        ),
      ]),
    );
  }
}

// ---- vehicles ----

class AdminVehiclesScreen extends StatelessWidget {
  const AdminVehiclesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LiveList(
      titleKey: 'adminVehicles',
      stream: AdminConsoleService.watchVehicles,
      tile: (context, d) {
        final v = d.data();
        final availability = v['availability'] as String? ?? VehicleAvailability.available;
        final suspended = availability == VehicleAvailability.suspended;
        return ListTile(
          key: ValueKey('vehicle_${d.id}'),
          title: Text('${v['number'] ?? ''} · ${vehicleTypeLabel(context, v['type'] as String? ?? '')}'),
          subtitle: Text(availabilityLabel(context, availability)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (availability == VehicleAvailability.docExpired)
              TextButton(
                key: ValueKey('docOverride_${d.id}'),
                onPressed: () => _run(context, () async {
                  await AdminConsoleService.overrideVehicleDocs(d.id);
                  if (context.mounted) showSnack(context, tr(context, 'docOverrideDone'));
                }),
                child: Text(tr(context, 'adminDocOverride')),
              ),
            TextButton(
              key: ValueKey('suspend_${d.id}'),
              onPressed: () => _run(
                context,
                () => AdminConsoleService.setVehicleAvailability(
                    d.id, suspended ? VehicleAvailability.available : VehicleAvailability.suspended),
              ),
              child: Text(tr(context, suspended ? 'adminLiftSuspension' : 'adminSuspend')),
            ),
          ]),
        );
      },
    );
  }
}

Future<void> _run(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (_) {
    if (context.mounted) showSnack(context, tr(context, 'somethingWrong'));
  }
}

// ---- loads ----

class AdminLoadsScreen extends StatefulWidget {
  const AdminLoadsScreen({super.key});

  @override
  State<AdminLoadsScreen> createState() => _AdminLoadsScreenState();
}

class _AdminLoadsScreenState extends State<AdminLoadsScreen> {
  String? _status;

  @override
  Widget build(BuildContext context) {
    final labels = {
      LoadStatus.open: 'statusOpen',
      LoadStatus.matched: 'statusMatched',
      LoadStatus.closed: 'statusClosed',
    };
    return _LiveList(
      key: ValueKey(_status),
      titleKey: 'adminLoads',
      stream: () => AdminConsoleService.watchLoads(status: _status),
      header: [
        _Filter(
          selected: _status,
          values: {for (final e in labels.entries) e.key: tr(context, e.value)},
          onChanged: (s) => setState(() => _status = s),
        ),
      ],
      tile: (context, d) {
        final l = d.data();
        return ListTile(
          key: ValueKey('load_${d.id}'),
          title: Text('${l['pickup'] ?? ''} → ${l['drop'] ?? ''}'),
          subtitle: Text('${tr(context, labels[l['status']] ?? 'statusOpen')} · ${l['cargoType'] ?? ''} · ${l['weight'] ?? ''} t · ${_ts(l['createdAt'])}'),
        );
      },
    );
  }
}

class _Filter extends StatelessWidget {
  final String? selected;
  final Map<String, String> values;
  final ValueChanged<String?> onChanged;
  const _Filter({required this.selected, required this.values, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(spacing: 8, children: [
          ChoiceChip(label: Text(tr(context, 'adminAll')), selected: selected == null, onSelected: (_) => onChanged(null)),
          for (final e in values.entries)
            ChoiceChip(
              key: ValueKey('filter_${e.key}'),
              label: Text(e.value),
              selected: selected == e.key,
              onSelected: (_) => onChanged(e.key),
            ),
        ]),
      );
}

// ---- bookings (with manual reassign) ----

class AdminBookingsScreen extends StatefulWidget {
  /// Shares exported CSV text; defaults to the system share sheet. A test hook.
  final Future<bool> Function(String csv, String subject)? share;

  const AdminBookingsScreen({super.key, this.share});

  @override
  State<AdminBookingsScreen> createState() => _AdminBookingsScreenState();
}

class _AdminBookingsScreenState extends State<AdminBookingsScreen> {
  String? _status;

  Future<void> _reassign(Booking b) async {
    final number = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'adminReassign')),
        content: TextField(
          key: const ValueKey('reassignNumber'),
          controller: number,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: tr(ctx, 'adminNewVehicleHint')), inputFormatters: [LengthLimitingTextInputFormatter(30)]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ctx, 'cancel'))),
          FilledButton(key: const ValueKey('reassignGo'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr(ctx, 'save'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await AdminConsoleService.reassignDriver(b, number.text);
      if (mounted) showSnack(context, tr(context, 'adminReassigned'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'adminReassignFailed'));
    }
  }

  Future<void> _export() async {
    final subject = tr(context, 'adminBookings');
    final failed = tr(context, 'cannotOpenLink');
    final ok = await (widget.share ?? shareCsv)(await AdminConsoleService.bookingsCsv(status: _status), subject);
    if (!ok && mounted) showSnack(context, failed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'adminBookings')),
        actions: [IconButton(key: const ValueKey('exportBookings'), tooltip: tr(context, 'exportCsv'), onPressed: _export, icon: const Icon(Icons.ios_share_rounded))],
      ),
      body: Column(children: [
        _Filter(
          selected: _status,
          values: {for (final s in [...BookingStatus.flow, BookingStatus.cancelled]) s: bookingStatusLabel(context, s)},
          onChanged: (s) => setState(() => _status = s),
        ),
        Expanded(
          child: LiveStream<List<Booking>>(
            key: ValueKey(_status),
            stream: () => AdminConsoleService.watchBookings(status: _status),
            builder: (context, list) {
              if (list.isEmpty) return _empty(context);
              return ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final b = list[i];
                  final movable = const [BookingStatus.accepted, BookingStatus.driverArriving, BookingStatus.loading].contains(b.status);
                  return ListTile(
                    key: ValueKey('booking_${b.id}'),
                    title: Text('${b.pickup} → ${b.drop}'),
                    subtitle: Text('${bookingStatusLabel(context, b.status)} · ${b.driverName} · ${b.vehicleNumber}'),
                    trailing: movable
                        ? IconButton(
                            key: ValueKey('reassign_${b.id}'),
                            tooltip: tr(context, 'adminReassign'),
                            icon: const Icon(Icons.swap_horiz_rounded),
                            onPressed: () => _reassign(b),
                          )
                        : null,
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ---- tickets ----

class AdminTicketsScreen extends StatelessWidget {
  const AdminTicketsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LiveList(
      titleKey: 'adminTickets',
      sortKey: 'updatedAt',
      stream: AdminConsoleService.watchTickets,
      tile: (context, d) {
        final t = SupportTicket.fromDoc(d);
        return TicketTile(
          key: ValueKey('ticket_${d.id}'),
          ticket: t,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TicketDetailScreen(ticketId: t.id, asAdmin: true, adminControls: _TicketControls(ticket: t)),
          )),
        );
      },
    );
  }
}

class _TicketControls extends StatelessWidget {
  final SupportTicket ticket;
  const _TicketControls({required this.ticket});

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, children: [
        for (final s in TicketStatus.all)
          ChoiceChip(
            key: ValueKey('ticketStatus_$s'),
            label: Text(ticketStatusLabel(context, s)),
            selected: ticket.status == s,
            onSelected: (_) => _run(context, () => AdminConsoleService.updateTicket(ticket.id, status: s)),
          ),
      ]);
}

// ---- SOS ----

class AdminSosScreen extends StatelessWidget {
  const AdminSosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LiveList(
      titleKey: 'adminSos',
      stream: AdminConsoleService.watchSos,
      tile: (context, d) {
        final a = d.data();
        final status = a['status'] as String? ?? 'open';
        final loc = a['location'];
        return ListTile(
          key: ValueKey('sos_${d.id}'),
          leading: Icon(Icons.sos_rounded, color: status == 'resolved' ? Colors.green : Colors.redAccent),
          title: Text('${a['userId'] ?? ''}'),
          subtitle: Text([
            status,
            if (a['bookingId'] != null) '${a['bookingId']}',
            if (loc is GeoPoint) '${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}',
            _ts(a['createdAt']),
          ].where((e) => e.isNotEmpty).join(' · ')),
          trailing: Wrap(children: [
            if (status == 'open')
              TextButton(
                key: ValueKey('ack_${d.id}'),
                onPressed: () => _run(context, () => AdminConsoleService.setSosStatus(d.id, 'acknowledged')),
                child: Text(tr(context, 'adminAcknowledge')),
              ),
            if (status != 'resolved')
              TextButton(
                key: ValueKey('resolveSos_${d.id}'),
                onPressed: () => _run(context, () => AdminConsoleService.setSosStatus(d.id, 'resolved')),
                child: Text(tr(context, 'adminResolve')),
              ),
          ]),
        );
      },
    );
  }
}

// ---- reports ----

class AdminReportsScreen extends StatelessWidget {
  const AdminReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LiveList(
      titleKey: 'adminReports',
      stream: AdminConsoleService.watchReports,
      tile: (context, d) {
        final r = d.data();
        final open = (r['status'] ?? 'open') == 'open';
        return ListTile(
          key: ValueKey('report_${d.id}'),
          title: Text('${r['reason'] ?? ''}: ${r['reportedId'] ?? ''}'),
          subtitle: Text([r['details'] ?? '', r['status'] ?? '', _ts(r['createdAt'])].where((e) => e.toString().isNotEmpty).join(' · ')),
          trailing: open
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  TextButton(
                    key: ValueKey('openCase_${d.id}'),
                    onPressed: () => _run(context, () async {
                      final id = await FraudCaseService.open(
                        userId: '${r['reportedId'] ?? ''}',
                        summary: '${r['reason'] ?? 'report'}: ${r['details'] ?? ''}'.trim(),
                        reportId: d.id,
                      );
                      if (context.mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => FraudCaseScreen(caseId: id)));
                    }),
                    child: Text(tr(context, 'openCase')),
                  ),
                  if ('${r['bookingId'] ?? ''}'.isNotEmpty)
                    TextButton(
                      key: ValueKey('openChat_${d.id}'),
                      onPressed: () => _run(context, () async {
                        await CommAdminService.openChatForReview('${r['bookingId']}', reportId: d.id);
                        if (context.mounted) {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => AdminChatReviewScreen(bookingId: '${r['bookingId']}', parties: ['${r['reporterId'] ?? ''}', '${r['reportedId'] ?? ''}']),
                          ));
                        }
                      }),
                      child: Text(tr(context, 'pcOpenChat')),
                    ),
                  TextButton(
                    key: ValueKey('resolveReport_${d.id}'),
                    onPressed: () => _run(context, () => AdminConsoleService.resolveReport(d.id)),
                    child: Text(tr(context, 'adminResolve')),
                  ),
                ])
              : null,
        );
      },
    );
  }
}

// ---- audit log ----

/// Latest audit events: who did what to which record (read only).
class AdminAuditScreen extends StatelessWidget {
  const AdminAuditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LiveList(
      titleKey: 'adminAudit',
      stream: AdminConsoleService.watchAudit,
      tile: (context, d) {
        final e = d.data();
        final data = (e['data'] as Map?) ?? const {};
        final detail = [
          if (e['targetId'] != null) '${e['targetId']}',
          for (final x in data.entries) '${x.key}: ${x.value is List ? (x.value as List).join(', ') : x.value}',
        ].join(' · ');
        return ListTile(
          key: ValueKey('audit_${d.id}'),
          title: Text('${e['type']} · ${e['actorId']}'),
          subtitle: Text([detail, _ts(e['createdAt'])].where((x) => x.isNotEmpty).join('\n')),
          isThreeLine: detail.isNotEmpty,
        );
      },
    );
  }
}

// ---- deletion requests ----

class AdminDeletionRequestsScreen extends StatelessWidget {
  const AdminDeletionRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LiveList(
      titleKey: 'adminDeletionRequests',
      stream: AdminConsoleService.watchDeletionRequests,
      tile: (context, d) {
        final r = d.data();
        final pending = (r['status'] ?? 'pending') == 'pending';
        return ListTile(
          key: ValueKey('deletion_${d.id}'),
          title: Text('${r['userId'] ?? d.id}'),
          subtitle: Text([r['status'] ?? '', r['reason'] ?? '', _ts(r['createdAt'])].where((e) => e.toString().isNotEmpty).join(' · ')),
          trailing: pending
              ? TextButton(
                  key: ValueKey('deletionDone_${d.id}'),
                  onPressed: () => _run(context, () => AdminConsoleService.setDeletionStatus(d.id, 'done')),
                  child: Text(tr(context, 'adminMarkDone')),
                )
              : null,
        );
      },
    );
  }
}
