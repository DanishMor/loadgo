import '../errors/error_text.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../services/backend.dart';
import '../services/booking_service.dart';
import '../services/user_service.dart';
import '../widgets/logistics_labels.dart';
import '../widgets/common.dart';
import 'inspection_service.dart';
import 'lr_model.dart';
import 'lr_service.dart';

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Pending inspection requests of an LR with Approve (2 hours) and Deny.
class InspectionRequestsList extends StatelessWidget {
  final Booking booking;
  final LrPublic lr;
  const InspectionRequestsList({super.key, required this.booking, required this.lr});

  Future<void> _answer(BuildContext context, InspectionRequest r, bool approve) async {
    try {
      await InspectionService.respond(booking, lr, r.driverId, approve: approve);
      if (context.mounted) showSnack(context, tr(context, approve ? 'inOwnerApproved' : 'inDecided'));
    } catch (error) {
      if (context.mounted) showSnack(context, errorText(context, error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<InspectionRequest>>(
      stream: InspectionService.watchPending(lr.id),
      builder: (context, snap) {
        final list = snap.data ?? const [];
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final r in list)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(trf(context, 'inRequestBody', {'name': r.driverName.isEmpty ? booking.assignedDriverName : r.driverName}), key: ValueKey('inReq_${r.driverId}')),
                // What the owner is deciding about: the trip, and what the driver would see.
                Text(
                  trf(context, 'inCtxLine', {'lr': lr.lrNo, 'route': booking.route.join(' → '), 'vehicle': booking.vehicleNumber.isEmpty ? '-' : booking.vehicleNumber, 'status': bookingStatusLabel(context, booking.status)}),
                  key: ValueKey('inCtx_${r.driverId}'),
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                if (r.requestedAt != null) Text(trf(context, 'inCtxAsked', {'t': _hm(r.requestedAt!)}), style: TextStyle(color: AppColors.muted, fontSize: 13)),
                Text(tr(context, 'inCtxSees'), key: ValueKey('inSees_${r.driverId}'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  FilledButton(key: ValueKey('inApprove_${r.driverId}'), onPressed: () => _answer(context, r, true), child: Text(tr(context, 'inApprove'))),
                  OutlinedButton(key: ValueKey('inDeny_${r.driverId}'), onPressed: () => _answer(context, r, false), child: Text(tr(context, 'inDeny'))),
                ]),
              ]),
            ),
        ]);
      },
    );
  }
}

/// The last events of inspection mode on this LR: asked, approved, refused,
/// allowed in advance, ended (MASTER-6 Task 32).
class InspectionHistory extends StatelessWidget {
  final LrPublic lr;
  final Stream<List<InspectionLogEntry>>? log;
  const InspectionHistory({super.key, required this.lr, this.log});

  String _day(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${_hm(d)}';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<InspectionLogEntry>>(
      stream: log ?? InspectionService.watchLog(lr.id),
      builder: (context, snap) {
        final list = snap.data ?? const [];
        if (list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(key: const ValueKey('inHistory'), crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(context, 'inHistory'), style: const TextStyle(fontWeight: FontWeight.w700)),
            for (final e in list)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('${e.at == null ? '' : '${_day(e.at!)} · '}${trf(context, 'inLog_${e.kind}', {'h': e.hours ?? 0})}', key: ValueKey('inLog_${e.id}'), style: TextStyle(color: AppColors.muted, fontSize: 13)),
              ),
          ]),
        );
      },
    );
  }
}

/// What the owner does about inspection on the LR card: answer requests,
/// "Show for this trip", "Allow inspection for the next N hours".
class InspectionOwnerPanel extends StatelessWidget {
  final Booking booking;
  final LrPublic lr;
  const InspectionOwnerPanel({super.key, required this.booking, required this.lr});

  static const hourChoices = [2, 6, 12, 24, 48, 72];

  @override
  Widget build(BuildContext context) {
    final driver = InspectionService.tripDriver(booking);
    final canGrant = driver != null && driver != Backend.uid;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(context, 'inRequestsTitle'), style: const TextStyle(fontWeight: FontWeight.w700)),
        InspectionRequestsList(booking: booking, lr: lr),
        InspectionHistory(lr: lr),
        if (canGrant) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton(
              key: const ValueKey('inPreTrip'),
              onPressed: lr.complianceMode == ComplianceMode.show ? null : () => LrService.setComplianceMode(lr, ComplianceMode.show),
              child: Text(tr(context, 'inPreTrip')),
            ),
            PopupMenuButton<int>(
              key: const ValueKey('inPreHours'),
              onSelected: (h) async {
                try {
                  await InspectionService.allowFor(booking, lr, h);
                  if (context.mounted) showSnack(context, tr(context, 'inPreSaved'));
                } catch (error) {
                  if (context.mounted) showSnack(context, errorText(context, error));
                }
              },
              itemBuilder: (_) => [for (final h in hourChoices) PopupMenuItem(key: ValueKey('inPreHours_$h'), value: h, child: Text(trf(context, 'inHoursN', {'n': h})))],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text(tr(context, 'inPreHours'), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600))),
                  const Icon(Icons.arrow_drop_down, color: AppColors.primary),
                ]),
              ),
            ),
          ]),
          StreamBuilder<InspectionGrant?>(
            stream: InspectionService.watchGrant(lr.id, driver),
            builder: (context, snap) {
              final g = snap.data;
              if (g == null || !g.isValid(InspectionService.now())) return const SizedBox.shrink();
              return Row(children: [
                Expanded(child: Text(trf(context, 'inAllowedUntil', {'t': _hm(g.expiresAt)}), key: const ValueKey('inGrantInfo'), style: TextStyle(color: AppColors.muted, fontSize: 13))),
                TextButton(key: const ValueKey('inRevoke'), onPressed: () => InspectionService.revoke(lr, driver), child: Text(tr(context, 'blRevoke'))),
              ]);
            },
          ),
        ],
      ]),
    );
  }
}

/// Opened from the notification list: answer the driver's request.
Future<void> showInspectionDecision(BuildContext context, String bookingId) async {
  final booking = await BookingService.watch(bookingId).first;
  final all = await LrService.watchForBooking(bookingId).first;
  final lr = LrService.current(all);
  if (!context.mounted || booking == null || lr == null || lr.issuerId != Backend.uid) return;
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr(c, 'inRequestsTitle')),
      content: SingleChildScrollView(child: InspectionRequestsList(booking: booking, lr: lr)),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(tr(c, 'pcDone')))],
    ),
  );
}

/// The driver's part of the LR screen: the plain labels, the request button, the
/// grant time and the offline copy.
class InspectionDriverPanel extends StatefulWidget {
  final Booking booking;
  final LrPublic lr;
  final InspectionGrant? grant;
  final InspectionRequest? request;

  /// Whether the compliance group is already part of the driver copy.
  final bool complianceShown;
  final Future<LrBundle> Function() loadBundle;
  const InspectionDriverPanel({super.key, required this.booking, required this.lr, required this.grant, required this.request, required this.complianceShown, required this.loadBundle});

  @override
  State<InspectionDriverPanel> createState() => _InspectionDriverPanelState();
}

class _InspectionDriverPanelState extends State<InspectionDriverPanel> {
  final _cache = InspectionCache();
  bool _busy = false;
  late Future<({List<int> bytes, DateTime expiresAt})?> _saved = _readSaved();

  Future<({List<int> bytes, DateTime expiresAt})?> _readSaved() async {
    final c = await _cache.get(widget.lr.id, InspectionService.now());
    return c == null ? null : (bytes: c.bytes, expiresAt: c.expiresAt);
  }

  @override
  void didUpdateWidget(InspectionDriverPanel old) {
    super.didUpdateWidget(old);
    // The parent looks again every few seconds; an ended grant must take the
    // saved copy away from the screen (reading it deletes it).
    _saved = _readSaved();
  }

  Future<String> _driverName() async {
    final u = await UserService.getUser();
    return (u?['driverName'] as String?) ?? (u?['name'] as String?) ?? widget.booking.assignedDriverName;
  }

  Future<void> _ask() async {
    setState(() => _busy = true);
    try {
      await InspectionService.request(widget.booking, widget.lr, driverName: await _driverName());
      if (mounted) showSnack(context, tr(context, 'inRequested'));
    } catch (error) {
      if (mounted) showSnack(context, errorText(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final language = LanguageScope.of(context);
    setState(() => _busy = true);
    try {
      final bundle = await widget.loadBundle();
      final end = await InspectionService.saveCopy(bundle, grant: widget.grant, driverName: await _driverName(), language: language);
      if (!mounted) return;
      if (end == null) {
        showSnack(context, tr(context, 'inNothingToSave'));
      } else {
        showSnack(context, trf(context, 'inSaved', {'t': _hm(end)}));
        _saved = _readSaved();
      }
    } catch (error) {
      if (mounted) showSnack(context, errorText(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = InspectionService.now();
    final g = widget.grant;
    final valid = g != null && g.isValid(now);
    final r = widget.request;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (valid) Text(trf(context, 'inAllowedUntil', {'t': _hm(g.expiresAt)}), key: const ValueKey('inAllowedLabel'), style: const TextStyle(fontWeight: FontWeight.w700)),
        if (!widget.complianceShown) ...[
          Row(children: [
            const Icon(Icons.lock_outline_rounded, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(tr(context, 'inNeedApproval'), key: const ValueKey('inNeedApprovalLabel'), style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
          if (g != null && !valid) Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr(context, 'inExpired'), key: const ValueKey('inExpiredLabel'), style: TextStyle(color: AppColors.muted))),
          if (r != null && r.pending) Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr(context, 'inPending'), key: const ValueKey('inPendingLabel'), style: TextStyle(color: AppColors.muted))),
          if (r != null && r.status == 'denied') Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr(context, 'inDenied'), key: const ValueKey('inDeniedLabel'), style: TextStyle(color: AppColors.muted))),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const ValueKey('inRequest'),
            onPressed: _busy || (r != null && r.pending) ? null : _ask,
            icon: const Icon(Icons.policy_outlined),
            label: Text(tr(context, 'inShow')),
          ),
        ] else ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(key: const ValueKey('inSave'), onPressed: _busy ? null : _save, icon: const Icon(Icons.download_for_offline_outlined), label: Text(tr(context, 'inSaveCopy'))),
          ]),
        ],
        FutureBuilder<({List<int> bytes, DateTime expiresAt})?>(
          future: _saved,
          builder: (context, snap) {
            final c = snap.data;
            if (c == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                key: const ValueKey('inShowCopy'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InspectionCopyScreen(lrId: widget.lr.id))),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(tr(context, 'inShowCopy')),
              ),
            );
          },
        ),
      ]),
    );
  }
}

/// The saved copy, shown from the phone's own storage (works without a network).
/// Shows nothing once its time is over: the copy is deleted when it is read late.
class InspectionCopyScreen extends StatelessWidget {
  final String lrId;
  const InspectionCopyScreen({super.key, required this.lrId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'inWatermark'))),
      body: FutureBuilder(
        future: InspectionCache().get(lrId, InspectionService.now()),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          final c = snap.data;
          if (c == null) return EmptyState(icon: Icons.timer_off_outlined, title: tr(context, 'inExpired'));
          return Column(children: [
            Padding(padding: const EdgeInsets.all(12), child: Text(trf(context, 'inAllowedUntil', {'t': _hm(c.expiresAt)}))),
            Expanded(child: PdfPreview(build: (_) async => c.bytes, canChangePageFormat: false, canChangeOrientation: false, canDebug: false, allowPrinting: false, allowSharing: false)),
          ]);
        },
      ),
    );
  }
}
