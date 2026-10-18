import 'package:flutter/material.dart';

import 'lr_copy_screen.dart';
import 'lr_form_screen.dart';
import 'lr_model.dart';
import 'lr_service.dart';
import '../constants/logistics.dart';
import '../documents/lr_screen.dart';
import '../features/features.dart';
import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../services/backend.dart';
import '../services/features_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/common.dart';
import '../widgets/ds/app_button.dart';
import '../widgets/live_stream.dart';

/// U24: the Bilty button, in plain sight on the trip page (it used to sit under "View LR" in the papers row and the
/// owner could not find it). The customer or the transporter of the booking sees "Make bilty"; once one exists, "See
/// bilty" and the three copies (Full, Driver, Consignee). Hidden when the `bilty` switch is off, or for someone who
/// cannot make one and has nothing to see.
class BiltyEntryCard extends StatelessWidget {
  final Booking booking;
  const BiltyEntryCard({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    if (!FeaturesService.isOn(FeatureKey.bilty)) return const SizedBox.shrink();
    final uid = Backend.uid;
    final canIssue = uid != null && LrService.canIssue(booking, uid);
    final c = context.ds;
    return LiveStream<List<LrPublic>>(
      compact: true,
      stream: () => LrService.watchForBooking(booking.id),
      builder: (context, all) {
        final lr = LrService.current(all);
        if (lr == null && !canIssue) return const SizedBox.shrink();
        final open = lr != null && !lr.isCancelled;
        return Padding(
          padding: const EdgeInsets.only(bottom: DsSpace.s3),
          child: AppCard(
            key: const ValueKey('biltyEntry'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(Icons.receipt_long_rounded, color: c.primary),
                const SizedBox(width: DsSpace.s2),
                Expanded(child: Text(open ? '${tr(context, 'tkBilty')}: ${lr.lrNo}' : tr(context, 'tkBilty'), style: DsType.title.copyWith(color: c.textStrong))),
              ]),
              const SizedBox(height: DsSpace.s1),
              Text(tr(context, 'tkBiltyHint'), style: DsType.bodySmall.copyWith(color: c.textMuted)),
              const SizedBox(height: DsSpace.s3),
              if (!open)
                AppButton(
                  key: const ValueKey('biltyMake'),
                  label: tr(context, 'tkBiltyMake'),
                  icon: Icons.add_rounded,
                  onPressed: booking.status == BookingStatus.cancelled
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LrFormScreen(booking: booking, issuerRole: LrService.roleFor(booking, uid!)))),
                )
              else ...[
                AppButton(
                  key: const ValueKey('biltyOpen'),
                  label: tr(context, 'tkBiltyOpen'),
                  kind: AppButtonKind.secondary,
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LrScreen(bookingId: booking.id))),
                ),
                const SizedBox(height: DsSpace.s2),
                Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s2, children: [
                  for (final (copy, label) in const [(LrCopy.full, 'blCopyFull'), (LrCopy.driver, 'blCopyDriver'), (LrCopy.consignee, 'blCopyConsignee')])
                    ActionChip(
                      key: ValueKey('biltyCopy_$copy'),
                      label: Text(tr(context, label)),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LrCopyScreen(booking: booking, lr: lr, copy: copy))),
                    ),
                ]),
              ],
            ]),
          ),
        );
      },
    );
  }
}
