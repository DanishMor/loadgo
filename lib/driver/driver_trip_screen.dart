import '../core/pilot/reuse_survey.dart';
import '../core/services/backend.dart';
import 'package:flutter/material.dart';

import '../core/claims/claim_screens.dart';
import '../core/constants/logistics.dart';
import '../core/models/booking.dart';
import '../core/services/booking_service.dart';
import '../core/share/share_widgets.dart';
import '../core/widgets/cancel_reason_picker.dart';
import '../core/widgets/common.dart';
import '../core/widgets/trip_eta_card.dart';
import '../core/l10n/l10n.dart';
import '../core/widgets/rating_widgets.dart';
import '../core/widgets/booking_widgets.dart';
import '../core/widgets/location_widgets.dart';
import '../core/widgets/detention_card.dart';
import '../core/widgets/evidence_cards.dart';
import '../core/services/trip_evidence_service.dart';
import '../core/services/pricing_service.dart';
import 'trip_proof_dialogs.dart';
import '../core/documents/trip_document_buttons.dart';
import 'trip_safety_card.dart';
import 'trip_geofence_banner.dart';
import 'pickup_alerts.dart';
import '../core/enterprise/handover_card.dart';
import '../core/documents/eway_status_line.dart';
import 'return_loads_section.dart';
import '../core/documents/payment_card.dart';
import '../core/payments/payment_timeline_card.dart';
import '../core/services/server_clock.dart';

void openDriverTrip(BuildContext context, String bookingId) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => DriverTripScreen(bookingId: bookingId)));
}

/// Driver's active trip: details, timeline and the button for the next status.
class DriverTripScreen extends StatelessWidget {
  final String bookingId;

  const DriverTripScreen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context) {
    return BookingDetailScaffold(
      bookingId: bookingId,
      title: tr(context, 'tripDetails'),
      builder: (context, booking) => _tripBody(context, booking),
    );
  }

  /// A driver a transporter assigned (not the booking holder) moves the trip
  /// and talks to the customer; money, papers and cancelling stay with the
  /// transporter who holds the booking.
  Widget _tripBody(BuildContext context, Booking booking) {
    final holder = booking.driverId == Backend.uid;
    return ListView(
        // Extra bottom space keeps the action button clear of floating snackbars.
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
        children: [
          BookingSummary(booking: booking),
          if (booking.isActive) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (BookingStatus.flow.indexOf(booking.status) < BookingStatus.flow.indexOf(BookingStatus.pickedUp))
                  NavigateButton(label: tr(context, 'navPickup'), place: booking.pickup),
                NavigateButton(label: tr(context, 'navDrop'), place: booking.drop),
              ],
            ),
            const SizedBox(height: 14),
            TripSafetyCard(booking: booking),
          ],
          if (booking.status == BookingStatus.driverArriving) ...[
            const SizedBox(height: 14),
            PickupGeofenceBanner(booking: booking),
            const SizedBox(height: 14),
            LocationSharingCard(booking: booking),
          ],
          if (booking.isInTransit) ...[
            const SizedBox(height: 14),
            TripGeofenceBanner(dropPlace: booking.drop),
            if (booking.extraDrops.isNotEmpty) ...[
              const SizedBox(height: 8),
              StopProgressCard(booking: booking),
            ],
            LocationSharingCard(booking: booking),
          ],
          if (holder) ...[
            const SizedBox(height: 14),
            DetentionCard(booking: booking, isDriver: true),
            const SizedBox(height: 14),
            DriverEvidenceCard(booking: booking),
            const SizedBox(height: 14),
            HandoverCard(booking: booking),
            EwayStatusLine(booking: booking),
            const SizedBox(height: 14),
            CargoDocsCard(booking: booking),
            const SizedBox(height: 14),
            PaymentCard(booking: booking),
            if (booking.status == BookingStatus.delivered) ...[const SizedBox(height: 14), PaymentTimelineCard(booking: booking)],
          ],
          const SizedBox(height: 14),
          TripEtaCard(booking: booking),
          const SizedBox(height: 8),
          if (holder) ClaimCard(booking: booking),
          const SizedBox(height: 8),
          BookingTimeline(booking: booking),
          const SizedBox(height: 12),
          TripDocumentButtons(booking: booking),
          const SizedBox(height: 20),
          if (holder && (booking.status == BookingStatus.inTransit || booking.status == BookingStatus.unloading || booking.status == BookingStatus.delivered)) ...[
            ReturnLoadsSection(booking: booking, onAccepted: (id) => openDriverTrip(context, id)),
            const SizedBox(height: 14),
          ],
          _NextStatusButton(booking: booking),
          if (holder && booking.canDriverCancel) ...[
            const SizedBox(height: 10),
            _CancelBookingButton(booking: booking),
          ],
          if (holder && booking.status == BookingStatus.delivered) ...[
            const SizedBox(height: 14),
            RatingPrompt(booking: booking, titleKey: 'rateCustomer'),
            const SizedBox(height: 8),
            ReuseSurveyCard(booking: booking, role: 'driver'),
          ],
        ],
    );
  }
}

class _NextStatusButton extends StatefulWidget {
  final Booking booking;
  const _NextStatusButton({required this.booking});

  @override
  State<_NextStatusButton> createState() => _NextStatusButtonState();
}

class _NextStatusButtonState extends State<_NextStatusButton> {
  bool _busy = false;

  static String _labelKey(String next) => switch (next) {
        BookingStatus.driverArriving => 'markArriving',
        BookingStatus.loading => 'markLoading',
        BookingStatus.pickedUp => 'markPickedUp',
        BookingStatus.inTransit => 'markInTransit',
        BookingStatus.unloading => 'markUnloading',
        _ => 'markDelivered',
      };

  Future<bool> _confirmDelivered() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(dialogContext, 'markDelivered')),
        content: RouteText(pickup: widget.booking.pickup, drop: widget.booking.drop, fontSize: 15),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(tr(dialogContext, 'cancel'))),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(tr(dialogContext, 'markDelivered'))),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _advance(String next) async {
    String? otp;
    PickupProof? pickup;
    DeliveryProof? delivery;
    if (next == BookingStatus.pickedUp) {
      final r = await askPickupProof(context);
      if (r == null) return;
      (otp, pickup) = r;
    } else if (next == BookingStatus.delivered) {
      // Delivery closes the load and can't be undone, so ask first.
      if (!await _confirmDelivered() || !mounted) return;
      final r = await askDeliveryProof(context);
      if (r == null) return;
      (otp, delivery) = r;
    }
    if (!mounted) return;
    await _sendAdvance(next, otp, pickup, delivery);
  }

  /// The network part of [_advance]; a failed call can be retried with the
  /// same OTP and proof.
  Future<void> _sendAdvance(String next, String? otp, PickupProof? pickup, DeliveryProof? delivery) async {
    setState(() => _busy = true);
    try {
      await BookingService.advance(widget.booking.id, otp: otp, pickup: pickup, delivery: delivery);
      // GPS evidence with the event (best effort; needs the location permission).
      if (next == BookingStatus.pickedUp || next == BookingStatus.delivered) {
        TripEvidenceService.saveGps(widget.booking.id, pickup: next == BookingStatus.pickedUp, place: next == BookingStatus.pickedUp ? widget.booking.pickup : widget.booking.drop).then((_) {}, onError: (_) {});
      }
      if (mounted) showSnack(context, tr(context, 'statusUpdated'));
    } on WrongOtpException {
      if (mounted) showSnack(context, tr(context, 'wrongOtp'));
    } catch (_) {
      if (mounted) showRetrySnack(context, tr(context, 'somethingWrong'), () => _sendAdvance(next, otp, pickup, delivery));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.booking.status == BookingStatus.cancelled) {
      return Center(child: StatusChip(label: tr(context, 'bookingCancelledChip'), color: Colors.redAccent));
    }
    final next = widget.booking.nextStatus;
    if (next == null) {
      return Center(
        child: StatusChip(label: tr(context, 'tripCompleted'), color: AppColors.success),
      );
    }
    return PrimaryButton(
      label: tr(context, _labelKey(next)),
      icon: next == BookingStatus.delivered ? Icons.flag_rounded : Icons.arrow_forward_rounded,
      loading: _busy,
      onPressed: () => _advance(next),
    );
  }
}

class _CancelBookingButton extends StatefulWidget {
  final Booking booking;
  const _CancelBookingButton({required this.booking});

  @override
  State<_CancelBookingButton> createState() => _CancelBookingButtonState();
}

class _CancelBookingButtonState extends State<_CancelBookingButton> {
  bool _busy = false;

  Future<void> _cancel() async {
    String? reason;
    final charge = BookingService.cancellationCharge(widget.booking, ServerClock.now());
    final policy = PricingService.config.cancellation;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(dialogContext, 'cancelBooking')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(dialogContext, 'cancelBookingConfirm')),
            const SizedBox(height: 12),
            Text(
              charge == 0
                  ? trf(dialogContext, 'cancelFree', {'m': policy.freeMinutes})
                  : trf(dialogContext, 'cancelChargeNote', {'amount': formatPaise(charge)}),
              key: const ValueKey('cancelPolicyNote'),
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            CancelReasonPicker(by: 'driver', onChanged: (r) => reason = r),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(tr(dialogContext, 'keepBooking'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(tr(dialogContext, 'cancelBooking')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final done = tr(context, 'bookingCancelledByYou');
    final failed = tr(context, 'somethingWrong');
    setState(() => _busy = true);
    try {
      await BookingService.cancelByDriver(widget.booking.id, reason: reason);
      messenger.showSnackBar(SnackBar(content: Text(done), behavior: SnackBarBehavior.floating));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed), behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _busy ? null : _cancel,
        style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
        icon: const Icon(Icons.close_rounded),
        label: Text(tr(context, 'cancelBooking')),
      ),
    );
  }
}
