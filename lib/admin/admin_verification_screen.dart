import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/services/admin_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import '../core/widgets/verification_badges.dart';

/// Driver verification queue for admins (opened from the admin panel; the
/// `admins/{uid}` rules are the real gate).
class AdminVerificationScreen extends StatefulWidget {
  const AdminVerificationScreen({super.key});

  @override
  State<AdminVerificationScreen> createState() =>
      _AdminVerificationScreenState();
}

class _AdminVerificationScreenState extends State<AdminVerificationScreen> {
  String _status = AdminService.pending;

  String _label(String status) => switch (status) {
    AdminService.approved => tr(context, 'adminApproved'),
    AdminService.rejected => tr(context, 'adminRejected'),
    _ => tr(context, 'adminPending'),
  };

  Future<void> _set(DriverVerification d, String status) async {
    try {
      await AdminService.setStatus(d.uid, status);
      if (mounted) showSnack(context, tr(context, 'statusUpdated'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(
          tr(context, 'driverVerification'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final s in const [
                    AdminService.pending,
                    AdminService.approved,
                    AdminService.rejected,
                  ])
                    ChoiceChip(
                      label: Text(_label(s)),
                      selected: _status == s,
                      onSelected: (_) => setState(() => _status = s),
                    ),
                ],
              ),
            ),
            Expanded(
              child: LiveStream<List<DriverVerification>>(
                key: ValueKey(_status),
                stream: () => AdminService.watchDrivers(_status),
                builder: (context, list) {
                  if (list.isEmpty) {
                    return EmptyState(
                      icon: Icons.verified_user_outlined,
                      title: tr(context, 'noDriversHere'),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) => _DriverCard(
                      driver: list[i],
                      onSet: (status) => _set(list[i], status),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriverCard extends StatefulWidget {
  final DriverVerification driver;
  final ValueChanged<String> onSet;

  const _DriverCard({required this.driver, required this.onSet});

  @override
  State<_DriverCard> createState() => _DriverCardState();
}

class _DriverCardState extends State<_DriverCard> {
  bool _reveal = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.driver;
    final onSet = widget.onSet;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            d.name.isEmpty ? d.uid : d.name,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: AppColors.title,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${d.phone} • ${d.vehicleNumber} • ${d.vehicleType}',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          VerificationBadges(user: d.data, isDriver: true, reveal: _reveal),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: ValueKey('reveal_${d.uid}'),
              onPressed: () => setState(() => _reveal = !_reveal),
              icon: Icon(_reveal ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
              label: Text(tr(context, _reveal ? 'hideNumbers' : 'showNumbers')),
            ),
          ),
          Row(
            children: [
              if (d.status != AdminService.approved)
                Expanded(
                  child: FilledButton(
                    onPressed: () => onSet(AdminService.approved),
                    child: Text(tr(context, 'approve')),
                  ),
                ),
              if (d.status == AdminService.pending) const SizedBox(width: 10),
              if (d.status != AdminService.rejected)
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                    ),
                    onPressed: () => onSet(AdminService.rejected),
                    child: Text(tr(context, 'reject')),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
