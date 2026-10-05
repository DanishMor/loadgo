import 'package:flutter/material.dart';

import '../core/constants/logistics.dart';
import '../core/l10n/l10n.dart';
import '../core/widgets/rating_widgets.dart';
import '../core/widgets/tip_card.dart';
import '../core/widgets/detention_card.dart';
import '../core/widgets/evidence_cards.dart';
import 'cancel_scheduled_button.dart';
import 'driver_trust_row.dart';
import '../core/widgets/booking_widgets.dart';
import '../core/widgets/trip_eta_card.dart';
import '../core/widgets/location_widgets.dart';
import 'trip_otp_card.dart';
import '../core/documents/trip_document_buttons.dart';
import '../core/documents/payment_card.dart';
import '../core/claims/claim_screens.dart';

void openBookingTracking(BuildContext context, String bookingId) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookingTrackingScreen(bookingId: bookingId)));
}

/// Customer view of a booking; updates live as the driver changes status.
class BookingTrackingScreen extends StatelessWidget {
  final String bookingId;

  const BookingTrackingScreen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context) {
    return BookingDetailScaffold(
      bookingId: bookingId,
      title: tr(context, 'trackBooking'),
      builder: (context, booking) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        children: [
          BookingSummary(booking: booking, showDriver: true),
          if (booking.canCustomerCancelScheduled) CancelScheduledButton(booking: booking),
          if (booking.isActive) ...[
            const SizedBox(height: 8),
            TripOtpCard(key: ValueKey('otp_${booking.id}'), booking: booking),
          ],
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: RatingBadge(userId: booking.driverId)),
          const SizedBox(height: 4),
          DriverTrustRow(booking: booking),
          const SizedBox(height: 8),
          TripEtaCard(booking: booking),
          if (booking.isInTransit) ...[
            const SizedBox(height: 8),
            DriverLocationCard(booking: booking),
          ],
          const SizedBox(height: 8),
          DetentionCard(booking: booking, isDriver: false),
          const SizedBox(height: 8),
          CargoDocsCard(booking: booking),
          const SizedBox(height: 8),
          PaymentCard(booking: booking),
          const SizedBox(height: 8),
          ClaimCard(booking: booking),
          const SizedBox(height: 8),
          BookingTimeline(booking: booking),
          const SizedBox(height: 12),
          TripDocumentButtons(booking: booking),
          if (booking.status == BookingStatus.delivered) ...[
            const SizedBox(height: 14),
            RatingPrompt(booking: booking, titleKey: 'rateDriver'),
            const SizedBox(height: 8),
            TipCard(booking: booking),
          ],
        ],
      ),
    );
  }
}
