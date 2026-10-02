import 'package:flutter/material.dart';

import '../../main.dart';
import 'booking_widgets.dart';

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
          const SizedBox(height: 14),
          BookingTimeline(booking: booking),
        ],
      ),
    );
  }
}
