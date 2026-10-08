import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../widgets/common.dart';
import '../widgets/live_stream.dart';
import 'lr_copy_view.dart';
import 'lr_model.dart';
import 'lr_service.dart';
import 'lr_visibility.dart';

/// The rows of one copy as a card. Used by the preview, by the copy screen and
/// by the driver's trip screen.
class LrCopyCard extends StatelessWidget {
  final Map<String, Object> fields;
  final String copy;
  final String issuerRole;
  const LrCopyCard({super.key, required this.fields, required this.copy, required this.issuerRole});

  @override
  Widget build(BuildContext context) {
    final rows = lrRows(fields);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(context, lrHeadingKey(issuerRole)), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        Text(tr(context, lrCopyKey(copy)), style: TextStyle(color: AppColors.muted)),
        const Divider(),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 120, child: Text(tr(context, r.labelKey), style: TextStyle(color: AppColors.muted, fontSize: 13))),
              Expanded(child: Text(r.value, key: ValueKey('lrRow_${r.labelKey}'))),
            ]),
          ),
      ]),
    );
  }
}

/// One LR version, as one copy type. Everything is built by [LrVisibility], so
/// a driver never gets a rate or a phone here, whatever the data holds.
class LrCopyScreen extends StatelessWidget {
  final Booking booking;
  final LrPublic lr;
  final String copy;
  final Widget? extra;
  const LrCopyScreen({super.key, required this.booking, required this.lr, required this.copy, this.extra});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(tr(context, copy == LrCopy.driver ? 'blDriverCopyBtn' : lrHeadingKey(lr.issuerRole)), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: FutureBuilder<LrBundle>(
          future: LrService.bundle(lr),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final fields = LrVisibility.snapshot(snap.data!, copy);
            return ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 30), children: [
              if (lr.isCancelled)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(trf(context, 'blCancelledNote', {'reason': lr.cancelReason}), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
                ),
              if (lr.status == LrStatus.superseded) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(tr(context, 'blStatusSuperseded'))),
              LrCopyCard(fields: fields, copy: copy, issuerRole: lr.issuerRole),
              if (extra != null) ...[const SizedBox(height: 12), extra!],
            ]);
          },
        ),
      ),
    );
  }
}

/// The driver's own view: driver copy plus the plain labels about what is hidden.
class DriverLrScreen extends StatelessWidget {
  final Booking booking;
  const DriverLrScreen({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    return LiveStream<List<LrPublic>>(
      stream: () => LrService.watchForBooking(booking.id),
      builder: (context, all) {
        final lr = LrService.current(all);
        if (lr == null) {
          return Scaffold(appBar: AppBar(title: Text(tr(context, 'blDriverCopyBtn'))), body: EmptyState(icon: Icons.receipt_long_outlined, title: tr(context, 'blNone')));
        }
        return LrCopyScreen(
          booking: booking,
          lr: lr,
          copy: LrCopy.driver,
          extra: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.visibility_off_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(tr(context, 'blRateHidden'), key: const ValueKey('rateHiddenLabel'), style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 6),
              Text(tr(context, 'blChatInApp'), style: TextStyle(color: AppColors.muted, fontSize: 13)),
            ]),
          ),
        );
      },
    );
  }
}
