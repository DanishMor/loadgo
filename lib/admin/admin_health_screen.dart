import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/services/admin_console_service.dart';
import '../core/services/error_log_service.dart';
import '../core/services/server_actions.dart';
import '../core/widgets/ds/app_button.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import '../core/theme/design_tokens.dart';

/// Admin > System health: totals and the latest sampled client errors.
class AdminHealthScreen extends StatefulWidget {
  const AdminHealthScreen({super.key});

  @override
  State<AdminHealthScreen> createState() => _AdminHealthScreenState();
}

class _AdminHealthScreenState extends State<AdminHealthScreen> {
  late Future<HealthCounts> _counts = AdminConsoleService.health();

  void _refresh() => setState(() {
        _counts = AdminConsoleService.health();
      });

  Widget _tile(String key, String label, int value) => Expanded(
        child: AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: DsStyle.t12w400.copyWith(color: AppColors.muted)),
            const SizedBox(height: 4),
            Text('$value', key: ValueKey('health_$key'), style: DsStyle.t24w700),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'adminHealth')),
        actions: [
          IconButton(
            key: const ValueKey('healthRefresh'),
            tooltip: tr(context, 'retry'),
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        FutureBuilder<HealthCounts>(
          future: _counts,
          builder: (context, snap) {
            if (snap.hasError) return ErrorRetry(messageKey: 'somethingWrong', onRetry: _refresh, compact: true);
            final c = snap.data;
            if (c == null) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
            return Column(children: [
              Row(children: [_tile('users', tr(context, 'healthUsers'), c.users), const SizedBox(width: 10), _tile('loads', tr(context, 'healthLoads'), c.loads)]),
              const SizedBox(height: 10),
              Row(children: [_tile('bookings', tr(context, 'healthBookings'), c.bookings), const SizedBox(width: 10), _tile('tickets', tr(context, 'healthOpenTickets'), c.openTickets)]),
              const SizedBox(height: 10),
              Row(children: [_tile('deletions', tr(context, 'healthPendingDeletions'), c.pendingDeletions), const Spacer()]),
            ]);
          },
        ),
        const SizedBox(height: 20),
        const ServerStatusCard(),
        const SizedBox(height: 20),
        Text(tr(context, 'healthErrors'), style: DsStyle.t16w700),
        const SizedBox(height: 4),
        Text(tr(context, 'healthErrorsNote'), style: DsStyle.t12w400.copyWith(color: AppColors.muted)),
        const SizedBox(height: 8),
        LiveStream<List<AppError>>(
          stream: ErrorLogService.watchRecent,
          compact: true,
          builder: (context, list) {
            if (list.isEmpty) return EmptyState(icon: Icons.verified_outlined, title: tr(context, 'healthNoErrors'));
            return Column(children: [
              for (final e in list)
                AppCard(
                  key: ValueKey('err_${e.id}'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.message, maxLines: 4, overflow: TextOverflow.ellipsis, style: DsStyle.w600),
                    const SizedBox(height: 4),
                    Text('${e.screen} · ${e.appVersion} · ${e.createdAt == null ? '' : formatDateTime(e.createdAt!)}', style: DsStyle.t12w400.copyWith(color: AppColors.muted)),
                  ]),
                ),
            ]);
          },
        ),
      ]),
    );
  }
}

/// F33: "Is the server there?" Pressing the button asks the cloud functions. No answer
/// is not an error: the app then uses its own direct writes, as before the deploy.
class ServerStatusCard extends StatefulWidget {
  final Future<ServerStatus?> Function()? check;
  const ServerStatusCard({super.key, this.check});

  @override
  State<ServerStatusCard> createState() => _ServerStatusCardState();
}

class _ServerStatusCardState extends State<ServerStatusCard> {
  bool _busy = false;
  bool _asked = false;
  ServerStatus? _status;

  Future<void> _ask() async {
    setState(() => _busy = true);
    final s = await (widget.check ?? ServerActions.status)();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _asked = true;
      _status = s;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(context, 'serverStatusTitle'), style: DsType.title.copyWith(color: c.text)),
        const SizedBox(height: DsSpace.s2),
        if (_asked && _status != null) ...[
          Text(tr(context, 'serverStatusUp'), key: const ValueKey('serverUp'), style: DsType.body.copyWith(color: c.success)),
          Text('${_status!.on} / ${_status!.switches.length} ${tr(context, 'serverStatusSwitches')}', key: const ValueKey('serverSwitches'), style: DsType.caption.copyWith(color: c.textMuted)),
        ],
        if (_asked && _status == null) Text(tr(context, 'serverStatusDown'), key: const ValueKey('serverDown'), style: DsType.body.copyWith(color: c.textMuted)),
        const SizedBox(height: DsSpace.s2),
        AppButton(key: const ValueKey('serverCheck'), label: tr(context, 'serverStatusCheck'), kind: AppButtonKind.secondary, expand: false, loading: _busy, onPressed: _busy ? null : _ask),
      ]),
    );
  }
}
