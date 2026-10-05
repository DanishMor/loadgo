import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/documents/doc_expiry.dart';

import '../core/constants/logistics.dart';
import '../core/l10n/l10n.dart';
import '../core/models/booking.dart';
import '../core/models/risk.dart';
import '../core/models/support_ticket.dart';
import '../core/services/admin_console_service.dart';
import '../core/support/support_screens.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import '../core/widgets/logistics_labels.dart';
import '../core/services/fraud_case_service.dart';
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
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  late Future<List<Doc>> _users = AdminConsoleService.users();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'adminUsers'))),
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
              if (snap.hasError) return Center(child: Text(tr(context, 'somethingWrong')));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final list = [for (final d in snap.data!) if (AdminConsoleService.userMatches(d.data(), d.id, _query)) d];
              if (list.isEmpty) return _empty(context);
              return ListView(children: [
                for (final d in list)
                  ListTile(
                    key: ValueKey('user_${d.id}'),
                    title: Text((d.data()['name'] ?? d.data()['driverName'] ?? d.id).toString()),
                    subtitle: Text([
                      d.data()['phone'] ?? '',
                      riskTierLabel(context, d.data()['riskTier'] as String? ?? RiskTier.normal),
                      if ((d.data()['roles'] as List?)?.isNotEmpty ?? false) (d.data()['roles'] as List).join('/'),
                      if (DocExpiry.licenceBlocked(d.data(), DateTime.now())) tr(context, 'adminLicenceExpiredTag'),
                    ].where((e) => e.toString().isNotEmpty).join(' · ')),
                    trailing: DocExpiry.licenceBlocked(d.data(), DateTime.now())
                        ? TextButton(
                            key: ValueKey('licenceOverride_${d.id}'),
                            onPressed: () async {
                              await AdminConsoleService.overrideLicence(d.id);
                              if (context.mounted) showSnack(context, tr(context, 'docOverrideDone'));
                              setState(() => _users = AdminConsoleService.users());
                            },
                            child: Text(tr(context, 'adminDocOverride')),
                          )
                        : const Icon(Icons.edit_outlined),
                    onTap: () async {
                      final name = (d.data()['name'] ?? d.data()['driverName'] ?? d.id).toString();
                      final tier = d.data()['riskTier'] as String? ?? RiskTier.normal;
                      if (await editRiskTier(context, uid: d.id, name: name, tier: tier)) {
                        setState(() => _users = AdminConsoleService.users());
                      }
                    },
                  ),
              ]);
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
  const AdminBookingsScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'adminBookings'))),
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
