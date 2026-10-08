import 'package:flutter/material.dart';

import '../constants/logistics.dart';
import '../features/features.dart';
import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../services/backend.dart';
import '../services/features_service.dart';
import '../widgets/common.dart';
import '../widgets/live_stream.dart';
import 'lr_copy_screen.dart';
import 'lr_copy_view.dart';
import 'lr_form_screen.dart';
import 'lr_model.dart';
import 'lr_send_screen.dart';
import 'lr_service.dart';

/// Whether [uid] is the person on the road for [b]: the driver a transporter
/// assigned, or the driver of a booking without a transporter.
bool isTripDriver(Booking b, String? uid) => uid != null && (uid == b.assignedDriverId || (uid == b.driverId && b.fleetOwnerId == null));

/// The Bilty section of the LR screen (Task 70): numbered LR, new version,
/// cancel, copy types and sending. Only the transporter and the customer of the
/// booking can make one; others just see it.
class BiltyCard extends StatelessWidget {
  final Booking booking;
  const BiltyCard({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    if (!FeaturesService.isOn(FeatureKey.bilty)) return const SizedBox.shrink();
    final uid = Backend.uid;
    final canIssue = uid != null && LrService.canIssue(booking, uid);
    return LiveStream<List<LrPublic>>(
      compact: true,
      stream: () => LrService.watchForBooking(booking.id),
      builder: (context, all) {
        final lr = LrService.current(all);
        final isDriver = isTripDriver(booking, uid);
        final party = uid != null && (canIssue || isDriver || uid == booking.driverId);
        if (!party || (lr == null && !canIssue)) return const SizedBox.shrink();
        final role = canIssue ? LrService.roleFor(booking, uid) : (lr?.issuerRole ?? LrIssuerRole.transporter);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, 'blCardTitle'), style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (lr == null) ...[
                Text(tr(context, 'blNone'), style: TextStyle(color: AppColors.muted)),
                const SizedBox(height: 8),
                FilledButton(
                  key: const ValueKey('biltyCreate'),
                  onPressed: booking.status == BookingStatus.cancelled
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LrFormScreen(booking: booking, issuerRole: role))),
                  child: Text(tr(context, 'blCreate')),
                ),
              ] else ...[
                Text('${tr(context, lrHeadingKey(lr.issuerRole))}: ${lr.lrNo}', key: const ValueKey('biltyNo'), style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${trf(context, 'blVersion', {'n': lr.version})} · ${tr(context, lrStatusKey(lr.status))}', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                if (lr.isCancelled) Text(trf(context, 'blCancelledNote', {'reason': lr.cancelReason}), style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (isDriver)
                    OutlinedButton(key: const ValueKey('biltyDriverCopy'), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DriverLrScreen(booking: booking))), child: Text(tr(context, 'blDriverCopyBtn')))
                  else
                    OutlinedButton(
                      key: const ValueKey('biltyView'),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LrCopyScreen(booking: booking, lr: lr, copy: LrCopy.full))),
                      child: Text(tr(context, 'blCopyFull')),
                    ),
                  if (canIssue && lr.issuerId == uid && lr.isCurrent) ...[
                    FilledButton(
                      key: const ValueKey('biltySend'),
                      onPressed: () async {
                        final nav = Navigator.of(context);
                        final b = await LrService.bundle(lr);
                        nav.push(MaterialPageRoute(builder: (_) => LrSendScreen(booking: booking, bundle: b)));
                      },
                      child: Text(tr(context, 'blSend')),
                    ),
                    OutlinedButton(
                      key: const ValueKey('biltyEdit'),
                      onPressed: () async {
                        final nav = Navigator.of(context);
                        final b = await LrService.bundle(lr);
                        nav.push(MaterialPageRoute(builder: (_) => LrFormScreen(booking: booking, issuerRole: role, editing: b)));
                      },
                      child: Text(tr(context, 'blEdit')),
                    ),
                    OutlinedButton(key: const ValueKey('biltyCancel'), onPressed: () => _askCancel(context, lr), child: Text(tr(context, 'blCancel'))),
                  ],
                ]),
                if (canIssue && lr.issuerId == uid && lr.isCurrent) _ModePicker(lr: lr),
                if (all.where((l) => l.id != lr.id && l.seq == lr.seq).isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(tr(context, 'blHistory'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  for (final old in all.where((l) => l.id != lr.id && l.seq == lr.seq))
                    ListTile(
                      key: ValueKey('biltyOld_${old.version}'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(trf(context, 'blVersion', {'n': old.version})),
                      subtitle: Text(tr(context, lrStatusKey(old.status))),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LrCopyScreen(booking: booking, lr: old, copy: LrCopy.full))),
                    ),
                ],
              ],
            ]),
          ),
        );
      },
    );
  }

  Future<void> _askCancel(BuildContext context, LrPublic lr) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(c, 'blCancel')),
        content: TextField(key: const ValueKey('biltyCancelReason'), controller: ctrl, maxLength: 200, decoration: InputDecoration(labelText: tr(c, 'blCancelReason'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr(c, 'cancel'))),
          FilledButton(key: const ValueKey('biltyCancelOk'), onPressed: () => Navigator.pop(c, ctrl.text), child: Text(tr(c, 'blCancel'))),
        ],
      ),
    );
    if (reason == null || !context.mounted) return;
    try {
      await LrService.cancel(lr, reason);
      if (context.mounted) showSnack(context, tr(context, 'blCancelled'));
    } on LrException {
      if (context.mounted) showSnack(context, tr(context, 'blCancelReason'));
    }
  }
}

/// Owner's choice for the compliance group; a change is written to the audit
/// log and does not make a new version.
class _ModePicker extends StatelessWidget {
  final LrPublic lr;
  const _ModePicker({required this.lr});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(context, 'blComplianceMode'), style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 4),
        SegmentedButton<String>(
          key: const ValueKey('biltyModePicker'),
          showSelectedIcon: false,
          segments: [
            for (final (m, k) in const [(ComplianceMode.hide, 'blModeHide'), (ComplianceMode.show, 'blModeShow'), (ComplianceMode.inspectionOnRequest, 'blModeInspection')])
              ButtonSegment(value: m, label: Text(tr(context, k), key: ValueKey('biltyMode_$m'), maxLines: 3, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
          ],
          selected: {lr.complianceMode},
          onSelectionChanged: (s) => LrService.setComplianceMode(lr, s.first),
        ),
      ]),
    );
  }
}

/// "LR (driver copy)" on the trip screen of the driver, shown once an LR exists.
class DriverLrButton extends StatelessWidget {
  final Booking booking;
  const DriverLrButton({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    if (!FeaturesService.isOn(FeatureKey.bilty) || !isTripDriver(booking, Backend.uid)) return const SizedBox.shrink();
    return StreamBuilder<List<LrPublic>>(
      stream: LrService.watchForBooking(booking.id),
      builder: (context, snap) {
        final lr = LrService.current(snap.data ?? const []);
        if (lr == null || lr.isCancelled) return const SizedBox.shrink();
        return OutlinedButton.icon(
          key: const ValueKey('driverLrCopy'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DriverLrScreen(booking: booking))),
          icon: const Icon(Icons.assignment_outlined),
          label: Text(tr(context, 'blDriverCopyBtn')),
        );
      },
    );
  }
}
