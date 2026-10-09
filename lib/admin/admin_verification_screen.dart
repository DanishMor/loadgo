import '../core/errors/error_text.dart';
import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/onboarding/driver_onboarding.dart';
import '../core/services/admin_service.dart';
import '../core/widgets/admin_phone.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import '../core/widgets/kyc_check_widgets.dart';
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
    String? reason;
    var note = '';
    if (status == AdminService.rejected) {
      final r = await showDialog<({String reason, String note})>(context: context, builder: (_) => const _RejectDialog());
      if (r == null || !mounted) return;
      reason = r.reason;
      note = r.note;
    }
    try {
      await AdminService.setStatus(d.uid, status, reason: reason, note: note);
      if (mounted) showSnack(context, tr(context, 'statusUpdated'));
    } catch (error) {
      if (mounted) showSnack(context, errorText(context, error));
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
          AdminPhoneText(uid: d.uid, phone: d.phone, style: TextStyle(color: AppColors.muted)),
          Text(
            d.isTransporter
                ? '${tr(context, 'fleetOwner')} • ${((d.data['fleet'] as Map?)?['officeCity'] ?? '')} • ${((d.data['fleet'] as Map?)?['vehicleCount'] ?? 0)} ${tr(context, 'fleetVehicles')}'
                : '${d.vehicleNumber} • ${d.vehicleType}',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          VerificationBadges(user: d.data, isDriver: true, reveal: _reveal),
          const SizedBox(height: 6),
          AutoCheckChips(user: d.data),
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

/// Asks why a driver is not approved: a reason and an optional short note the
/// driver will see (MASTER-6 Task 21).
class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  String _reason = RejectReason.docsUnclear;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'rejectWhy')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final r in RejectReason.all)
            InkWell(
              key: ValueKey('reject_$r'),
              onTap: () => setState(() => _reason = r),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Icon(_reason == r ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(child: Text(tr(context, RejectReason.labelKey(r)))),
                ]),
              ),
            ),
          TextField(key: const ValueKey('rejectNote'), controller: _note, maxLength: RejectReason.maxNote, decoration: InputDecoration(labelText: tr(context, 'rejectNoteHint'))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr(context, 'cancel'))),
        FilledButton(key: const ValueKey('rejectConfirm'), onPressed: () => Navigator.pop(context, (reason: _reason, note: _note.text)), child: Text(tr(context, 'reject'))),
      ],
    );
  }
}
