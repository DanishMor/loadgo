import 'package:flutter/material.dart';

import '../core/admin/ops_queues.dart';
import '../core/admin/staff_roles.dart';
import '../core/errors/error_text.dart';
import '../core/features/features.dart';
import '../core/features/kill_switches.dart';
import '../core/l10n/l10n.dart';
import '../core/services/admin_console_service.dart';
import '../core/services/features_service.dart';
import '../core/theme/design_tokens.dart';
import '../core/widgets/common.dart';
import '../core/widgets/ds/app_top_bar.dart';
import '../core/widgets/ds/skeleton.dart';
import '../core/widgets/ds/status_badge.dart';
import '../core/widgets/live_stream.dart' show ErrorState;

/// E24 (flag adminOpsHome): one page for the shift: what is waiting in each staff queue (only the queues this role
/// may open), the dispatch picture, and kill-switch shortcuts for roles that may change features. Counted once per
/// open; Refresh counts again.
class AdminOpsHomeScreen extends StatefulWidget {
  /// The admin areas this page can open, by staff-area key (the dashboard's own screen list).
  final Map<String, Widget> screens;

  /// Test hooks; by default the signed-in staff role, the live counts and the features document.
  final Future<String> Function()? role;
  final Future<OpsQueues> Function()? load;
  final Future<void> Function(Features next)? save;

  const AdminOpsHomeScreen({super.key, required this.screens, this.role, this.load, this.save});

  @override
  State<AdminOpsHomeScreen> createState() => _AdminOpsHomeScreenState();
}

class _AdminOpsHomeScreenState extends State<AdminOpsHomeScreen> {
  late Future<OpsQueues> _data = _count();
  String? _role;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    (widget.role ?? AdminConsoleService.staffRole)().then((r) {
      if (mounted) setState(() => _role = r);
    }, onError: (_) {});
  }

  Future<OpsQueues> _count() => (widget.load ?? AdminConsoleService.opsQueues)();

  /// Until the role is known nothing role-bound is shown; an unknown area is never offered.
  bool _can(String area) => _role != null && widget.screens.containsKey(area) && staffCan(_role!, area);

  void _open(String area) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => widget.screens[area]!));

  void _refresh() {
    final next = _count();
    setState(() {
      _data = next;
    });
  }

  static const _icons = {
    'sos': Icons.sos_rounded,
    'unfilled': Icons.hourglass_empty_rounded,
    'kyc': Icons.verified_user_outlined,
    'photos': Icons.photo_library_outlined,
    'claims': Icons.gavel_rounded,
    'tickets': Icons.support_agent_rounded,
  };

  Future<void> _kill(KillGroup g) async {
    final name = tr(context, 'killGroup_${g.id}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(trf(c, 'killConfirm', {'group': name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr(c, 'cancel'))),
          FilledButton(key: const ValueKey('opsKillYes'), onPressed: () => Navigator.pop(c, true), child: Text(tr(c, 'killOff'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await (widget.save ?? FeaturesService.save)(FeaturesService.notifier.value.withGroupOff(g));
      if (mounted) showSnack(context, tr(context, 'featSaved'));
    } catch (e) {
      if (mounted) showSnack(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Scaffold(
      appBar: AppTopBar(
        title: tr(context, 'opsTitle'),
        actions: [IconButton(key: const ValueKey('opsRefresh'), tooltip: tr(context, 'retry'), onPressed: () => _refresh(), icon: const Icon(Icons.refresh_rounded))],
      ),
      body: FutureBuilder<OpsQueues>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(error: snap.error, onRetry: () => _refresh());
          final q = snap.data;
          if (q == null) return const Padding(padding: EdgeInsets.all(DsSpace.gutter), child: SkeletonList(key: ValueKey('opsSkeleton'), count: 5));
          final queues = [for (final (id, area) in OpsQueues.order) if (_can(area)) (id, area)];
          return ListView(padding: const EdgeInsets.all(DsSpace.gutter), children: [
            AppCard(
              key: const ValueKey('opsBanner'),
              child: Row(children: [
                Icon(q.urgent ? Icons.priority_high_rounded : Icons.check_circle_outline_rounded, color: q.urgent ? c.error : c.success),
                const SizedBox(width: DsSpace.s3),
                Expanded(child: Text(tr(context, q.urgent ? 'opsUrgent' : (q.anyWaiting ? 'opsWaiting' : 'opsQuiet')), style: DsType.subtitle.copyWith(color: c.textStrong))),
              ]),
            ),
            const SizedBox(height: DsSpace.s4),
            Semantics(header: true, child: Text(tr(context, 'opsQueues'), style: DsType.title.copyWith(color: c.textStrong))),
            const SizedBox(height: DsSpace.s2),
            for (final (id, area) in queues)
              Padding(
                padding: const EdgeInsets.only(bottom: DsSpace.s2),
                child: AppCard(
                  key: ValueKey('opsQ_$id'),
                  onTap: () => _open(area),
                  child: Row(children: [
                    Icon(_icons[id], color: q.count(id) > 0 && (id == 'sos' || id == 'unfilled') ? c.error : c.primary),
                    const SizedBox(width: DsSpace.s3),
                    Expanded(child: Text(tr(context, 'opsQ_$id'), style: DsType.body.copyWith(color: c.text))),
                    Text(q.label(id), key: ValueKey('opsN_$id'), style: DsType.title.copyWith(color: q.count(id) > 0 ? c.textStrong : c.textMuted)),
                    const Icon(Icons.chevron_right_rounded),
                  ]),
                ),
              ),
            const SizedBox(height: DsSpace.s4),
            Semantics(header: true, child: Text(tr(context, 'opsDispatch'), style: DsType.title.copyWith(color: c.textStrong))),
            const SizedBox(height: DsSpace.s2),
            Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s2, children: [
              StatusBadge(key: const ValueKey('opsOpenLoads'), label: '${tr(context, 'pcOpenLoads')}: ${q.openLoads < 0 ? '–' : q.openLoads}', tone: StatusTone.neutral),
              StatusBadge(key: const ValueKey('opsRunning'), label: '${tr(context, 'pcRunningTrips')}: ${q.runningTrips < 0 ? '–' : q.runningTrips}', tone: StatusTone.progress),
            ]),
            if (_can('adminDispatchMonitor'))
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(key: const ValueKey('opsMonitor'), onPressed: () => _open('adminDispatchMonitor'), icon: const Icon(Icons.monitor_heart_outlined), label: Text(tr(context, 'adminDispatchMonitor'))),
              ),
            if (_can('adminFeatures')) ...[
              const SizedBox(height: DsSpace.s4),
              Semantics(header: true, child: Text(tr(context, 'opsKill'), style: DsType.title.copyWith(color: c.textStrong))),
              const SizedBox(height: DsSpace.s1),
              Text(tr(context, 'opsKillHint'), style: DsType.bodySmall.copyWith(color: c.textMuted)),
              const SizedBox(height: DsSpace.s2),
              Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s2, children: [
                for (final g in KillSwitches.groups)
                  OutlinedButton.icon(
                    key: ValueKey('opsKill_${g.id}'),
                    onPressed: _saving ? null : () => _kill(g),
                    icon: Icon(Icons.power_settings_new_rounded, color: c.error),
                    label: Text(tr(context, 'killGroup_${g.id}')),
                  ),
              ]),
            ],
          ]);
        },
      ),
    );
  }
}
