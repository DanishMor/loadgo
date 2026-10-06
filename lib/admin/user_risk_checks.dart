import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/vehicle.dart';
import '../core/risk/risk_rules.dart';
import '../core/services/risk_service.dart';
import '../core/widgets/common.dart';
import 'admin_user_screen.dart';

/// Admin > Users > one user: accounts that look like the same person (F1)
/// and vehicle / RC checks (F3). Hints for an admin, never automatic action.
class UserRiskChecks extends StatefulWidget {
  final String uid;
  final bool isDriver;
  const UserRiskChecks({super.key, required this.uid, required this.isDriver});

  @override
  State<UserRiskChecks> createState() => _UserRiskChecksState();
}

class _UserRiskChecksState extends State<UserRiskChecks> {
  late final Future<List<DuplicateCandidate>> _dups = RiskService.duplicatesOf(widget.uid);
  late final Future<List<({Vehicle vehicle, List<String> reasons})>> _veh = widget.isDriver ? RiskService.vehicleChecks(widget.uid) : Future.value(const []);
  late final Future<bool> _many = widget.isDriver ? RiskService.tooManyVehicles(widget.uid) : Future.value(false);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr(context, 'riskDupTitle'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      FutureBuilder<List<DuplicateCandidate>>(
        future: _dups,
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          if (snap.data!.isEmpty) return Text(tr(context, 'riskDupNone'), key: const ValueKey('dupNone'), style: TextStyle(color: AppColors.muted));
          return Column(children: [
            for (final c in snap.data!)
              ListTile(
                key: ValueKey('dup_${c.uid}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.people_outline_rounded),
                title: Text(c.uid),
                subtitle: Text([for (final r in c.reasons) tr(context, 'riskDup_$r')].join(' · ')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminUserScreen(uid: c.uid))),
              ),
          ]);
        },
      ),
      if (widget.isDriver) ...[
        const SizedBox(height: 12),
        Text(tr(context, 'riskVehTitle'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        FutureBuilder<List<({Vehicle vehicle, List<String> reasons})>>(
          future: _veh,
          builder: (context, snap) => Column(children: [
            for (final e in snap.data ?? const <({Vehicle vehicle, List<String> reasons})>[])
              ListTile(
                key: ValueKey('vehCheck_${e.vehicle.id}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                title: Text(e.vehicle.number),
                subtitle: Text([for (final r in e.reasons) tr(context, 'riskVeh_$r')].join(' · ')),
              ),
          ]),
        ),
        FutureBuilder<bool>(
          future: _many,
          builder: (context, snap) => snap.data == true
              ? Padding(padding: const EdgeInsets.only(top: 4), child: Text(tr(context, 'riskVehMany'), key: const ValueKey('vehMany'), style: TextStyle(color: AppColors.warning)))
              : const SizedBox.shrink(),
        ),
      ],
    ]);
  }
}
