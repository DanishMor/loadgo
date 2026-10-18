import 'package:flutter/material.dart';

import '../../core/claims/claim_screens.dart';
import '../../core/constants/logistics.dart';
import '../../core/documents/eway_status_line.dart';
import '../../core/documents/payment_card.dart';
import '../../core/documents/trip_document_buttons.dart';
import '../../core/errors/error_text.dart';
import '../../core/l10n/l10n.dart';
import '../../core/maps/trip_map.dart';
import '../../core/models/booking.dart';
import '../../core/pilot/reuse_survey.dart';
import '../../core/safety/call.dart';
import '../../core/safety/share_trip.dart';
import '../../core/services/safety_service.dart';
import '../../core/services/user_service.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/trust/public_trust_card.dart';
import '../../core/widgets/booking_widgets.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/detention_card.dart';
import '../../core/widgets/ds/app_button.dart';
import '../../core/widgets/ds/app_dialogs.dart';
import '../../core/widgets/ds/driver_mini_card.dart';
import '../../core/widgets/ds/route_ribbon.dart';
import '../../core/widgets/ds/status_badge.dart';
import '../../core/widgets/ds/status_timeline_v2.dart';
import '../../core/widgets/evidence_cards.dart';
import '../../core/widgets/location_widgets.dart';
import '../../core/widgets/logistics_labels.dart';
import '../../core/widgets/rating_widgets.dart';
import '../../core/widgets/tip_card.dart';
import '../../core/widgets/trip_eta_card.dart';
import '../cancel_scheduled_button.dart';
import '../delivered_actions.dart';
import '../trip_otp_card.dart';

/// The steps of a trip as the timeline shows them: all of [BookingStatus.flow], or only "accepted" and "cancelled".
List<String> trackingSteps(Booking b) => b.status == BookingStatus.cancelled ? const [BookingStatus.accepted, BookingStatus.cancelled] : BookingStatus.flow;

/// How far along the route the truck is, 0..1, from the step the trip is at. Null for a cancelled trip.
double? trackingProgress(Booking b) {
  if (b.status == BookingStatus.cancelled) return null;
  final i = BookingStatus.flow.indexOf(b.status);
  if (i < 0) return 0;
  final from = BookingStatus.flow.indexOf(BookingStatus.pickedUp);
  if (i < from) return 0.05;
  return ((i - from + 1) / (BookingStatus.flow.length - from)).clamp(0.05, 1.0).toDouble();
}

/// U21: the customer's trip page in the new app (switch `uiV2`). On top: route ribbon and status. Then the codes
/// (big), the timeline, the driver, and four quick actions (share, map, SOS, call 112). The older cards (payment,
/// papers, claim, detention, rating) stay, below "More".
class TrackingV2Screen extends StatelessWidget {
  final String bookingId;
  const TrackingV2Screen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context) {
    return BookingDetailScaffold(
      bookingId: bookingId,
      title: tr(context, 'trackBooking'),
      builder: (context, booking) => TrackingV2Body(booking: booking),
    );
  }
}

class TrackingV2Body extends StatefulWidget {
  final Booking booking;
  const TrackingV2Body({super.key, required this.booking});

  @override
  State<TrackingV2Body> createState() => _TrackingV2BodyState();
}

class _TrackingV2BodyState extends State<TrackingV2Body> {
  bool _sosBusy = false;

  Booking get b => widget.booking;

  Future<void> _sos() async {
    final ok = await showConfirmDialog(context, title: tr(context, 'sos'), message: tr(context, 'sosConfirm'), confirmLabel: tr(context, 'sos'), danger: true);
    if (!ok || !mounted) return;
    setState(() => _sosBusy = true);
    List<EmergencyContact> contacts = const [];
    try {
      await SafetyService.sendSos(booking: b);
      contacts = SafetyService.contactsFrom(await UserService.getUser());
    } catch (error) {
      if (mounted) showSnack(context, errorText(context, error));
    } finally {
      if (mounted) setState(() => _sosBusy = false);
    }
    if (!mounted) return;
    await showAppSheet<void>(
      context,
      title: tr(context, 'sos'),
      builder: (c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr(c, 'sosSent'), style: DsType.body.copyWith(color: c.ds.text)),
        const SizedBox(height: DsSpace.s4),
        for (final ct in contacts)
          Padding(padding: const EdgeInsets.only(bottom: DsSpace.s2), child: AppButton(label: ct.name, kind: AppButtonKind.secondary, icon: Icons.call_rounded, onPressed: () => callNumber(c, ct.phone))),
        AppButton(key: const ValueKey('trkCall112'), label: tr(c, 'call112'), kind: AppButtonKind.danger, icon: Icons.call_rounded, onPressed: () => callNumber(c, '112')),
      ]),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback? onTap, {Key? key}) {
    final c = context.ds;
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          key: key,
          borderRadius: DsRadius.all(DsRadius.md),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: DsSpace.s2, horizontal: DsSpace.s1),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, color: onTap == null ? c.textMuted : c.primary),
                const SizedBox(height: DsSpace.s1),
                Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: DsType.caption.copyWith(color: c.text)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _timeline() {
    final steps = trackingSteps(b);
    final at = steps.indexOf(b.status);
    final cancelled = b.status == BookingStatus.cancelled;
    return AppCard(
      key: const ValueKey('trkTimeline'),
      child: StatusTimelineV2(
        steps: [
          for (final s in steps) TimelineStepV2(bookingStatusLabel(context, s), time: b.timeline[s] == null ? null : formatDateTime(b.timeline[s]!)),
        ],
        // a cancelled trip has nothing left to wait for: every step counts as done
        current: cancelled ? steps.length : at,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final cancelled = b.status == BookingStatus.cancelled;
    final delivered = b.status == BookingStatus.delivered;
    final driver = b.assignedDriverName.isNotEmpty ? b.assignedDriverName : b.driverName;
    return ListView(
      key: const ValueKey('trkList'),
      padding: const EdgeInsets.all(DsSpace.gutter),
      children: [
        DeliveredWatcher(booking: b, child: const SizedBox.shrink()),
        AppCard(
          key: const ValueKey('trkHeader'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(tr(context, 'hvTrip'), style: DsType.title.copyWith(color: c.textStrong))),
              StatusBadge(label: bookingStatusLabel(context, b.status), tone: cancelled ? StatusTone.danger : (delivered ? StatusTone.success : StatusTone.progress)),
            ]),
            const SizedBox(height: DsSpace.s3),
            RouteRibbon(from: b.pickup, to: b.drop, progress: trackingProgress(b)),
            const SizedBox(height: DsSpace.s2),
            Text('${b.cargoType} • ${formatNum(b.weight)} T • ${b.vehicleNumber} (${vehicleTypeLabel(context, b.vehicleType)})', style: DsType.bodySmall.copyWith(color: c.textMuted)),
            if (b.agreedFarePaise != null || b.fareEstimate != null)
              Padding(
                padding: const EdgeInsets.only(top: DsSpace.s1),
                child: Text(formatPaise(b.agreedFarePaise ?? b.fareEstimate!), key: const ValueKey('trkFare'), style: DsType.subtitle.copyWith(color: c.textStrong)),
              ),
          ]),
        ),
        const SizedBox(height: DsSpace.s3),
        if (b.canCustomerCancelScheduled) CancelScheduledButton(booking: b),
        if (b.isActive) ...[
          TripOtpCard(key: ValueKey('otp_${b.id}'), booking: b),
          const SizedBox(height: DsSpace.s3),
        ],
        ArrivalEtaCard(booking: b),
        TripEtaCard(booking: b),
        if (b.isInTransit) ...[
          const SizedBox(height: DsSpace.s2),
          DriverLocationCard(booking: b),
        ],
        const SizedBox(height: DsSpace.s3),
        _timeline(),
        const SizedBox(height: DsSpace.s3),
        if (driver.isNotEmpty)
          AppCard(
            key: const ValueKey('trkDriver'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DriverMiniCard(name: driver, vehicle: b.vehicleNumber),
              PublicTrustCard(driverId: b.driverId),
              Align(alignment: AlignmentDirectional.centerStart, child: RatingBadge(userId: b.driverId)),
            ]),
          ),
        if (b.isActive) ...[
          const SizedBox(height: DsSpace.s3),
          AppCard(
            key: const ValueKey('trkActions'),
            padding: const EdgeInsets.all(DsSpace.s2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (TripMapScreen.available && b.isInTransit)
                _action(Icons.map_outlined, tr(context, 'tripMapOpen'), () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TripMapScreen(bookingId: b.id))), key: const ValueKey('openTripMap')),
              _action(Icons.sos_rounded, tr(context, 'sos'), _sosBusy ? null : _sos, key: const ValueKey('trkSos')),
              _action(Icons.call_rounded, tr(context, 'call112'), () => callNumber(context, '112'), key: const ValueKey('trkCall')),
            ]),
          ),
          ShareTripButton(booking: b),
          ShareTrackingLinkButton(booking: b),
        ],
        if (delivered) ...[
          const SizedBox(height: DsSpace.s4),
          RatingPrompt(booking: b, titleKey: 'rateDriver'),
          const SizedBox(height: DsSpace.s2),
          DeliveredActionsCard(booking: b),
          const SizedBox(height: DsSpace.s2),
          ReuseSurveyCard(booking: b, role: 'customer'),
          const SizedBox(height: DsSpace.s2),
          TipCard(booking: b),
        ],
        const SizedBox(height: DsSpace.s4),
        Semantics(header: true, child: Text(tr(context, 'tkMore'), style: DsType.title.copyWith(color: c.textStrong))),
        const SizedBox(height: DsSpace.s2),
        PaymentCard(booking: b),
        const SizedBox(height: DsSpace.s2),
        DetentionCard(booking: b, isDriver: false),
        EwayStatusLine(booking: b),
        CargoDocsCard(booking: b),
        const SizedBox(height: DsSpace.s2),
        ClaimCard(booking: b),
        const SizedBox(height: DsSpace.s3),
        TripDocumentButtons(booking: b),
      ],
    );
  }
}
