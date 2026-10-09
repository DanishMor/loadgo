import 'package:flutter/material.dart';

import '../core/admin/user_overview.dart';
import '../core/l10n/l10n.dart';
import '../core/services/admin_user_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// The 360 summary at the top of Admin > Users > person (MASTER-6 Task 11).
class UserOverviewCard extends StatefulWidget {
  final String uid;

  /// Test hook; defaults to the live reads.
  final Future<UserOverview> Function(String uid)? load;
  const UserOverviewCard({super.key, required this.uid, this.load});

  @override
  State<UserOverviewCard> createState() => _UserOverviewCardState();
}

class _UserOverviewCardState extends State<UserOverviewCard> {
  late Future<UserOverview> _data = (widget.load ?? AdminUserService.overview)(widget.uid);

  void _refresh() {
    final next = (widget.load ?? AdminUserService.overview)(widget.uid);
    setState(() {
      _data = next;
    });
  }

  String _yn(bool b) => tr(context, b ? 'uoYes' : 'uoNo');

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const ValueKey('userOverview'),
      child: FutureBuilder<UserOverview>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(error: snap.error, onRetry: _refresh, compact: true);
          final o = snap.data;
          if (o == null) return const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator()));
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(tr(context, 'uoTitle'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
              IconButton(key: const ValueKey('uoRefresh'), tooltip: tr(context, 'retry'), onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
            ]),
            Text(trf(context, 'uoTrips', {'c': o.tripsAsCustomer, 'd': o.tripsAsDriver, 'del': o.delivered, 'can': o.cancelled}), key: const ValueKey('uoTrips')),
            Text(o.ratingTenths == null ? tr(context, 'uoNoRating') : trf(context, 'uoRating', {'r': (o.ratingTenths! / 10).toStringAsFixed(1), 'n': o.ratingCount}), key: const ValueKey('uoRating')),
            Text(trf(context, 'uoStrikes', {'s': o.strikes, 'v': o.violations}), key: const ValueKey('uoStrikes')),
            Text(trf(context, 'uoTickets', {'n': o.openTickets}), key: const ValueKey('uoTickets')),
            if (o.vehicles > 0) Text(trf(context, 'uoVehicles', {'n': o.vehicles, 'e': o.vehiclesWithExpiredPapers}), key: const ValueKey('uoVehicles')),
            Text(trf(context, 'uoVerified', {'v': _yn(o.verified), 'k': _yn(o.kycComplete)}), key: const ValueKey('uoVerified')),
            const SizedBox(height: 8),
            Text(tr(context, 'uoTrail'), style: const TextStyle(fontWeight: FontWeight.w700)),
            if (o.trail.isEmpty) Text(tr(context, 'uoNoTrail'), style: TextStyle(color: AppColors.muted)),
            for (final e in o.trail)
              Text('${e.at == null ? '' : '${formatDateTime(e.at!)} · '}${e.type}${e.action.isEmpty ? '' : ' · ${e.action}'}', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ]);
        },
      ),
    );
  }
}
