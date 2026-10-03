import 'package:flutter/material.dart';

import '../../core/constants/logistics.dart';
import '../../core/models/booking.dart';
import '../../core/services/booking_service.dart';
import '../../core/share_text.dart';
import '../../core/widgets/common.dart';
import '../../main.dart';
import '../shared/live_stream.dart';

String bookingStatusLabel(BuildContext context, String status) => switch (status) {
      BookingStatus.accepted => tr(context, 'statusAccepted'),
      BookingStatus.pickedUp => tr(context, 'statusPickedUp'),
      BookingStatus.inTransit => tr(context, 'statusInTransit'),
      BookingStatus.delivered => tr(context, 'statusDelivered'),
      BookingStatus.cancelled => tr(context, 'statusCancelled'),
      _ => status,
    };

Color bookingStatusColor(String status) => switch (status) {
      BookingStatus.accepted => AppColors.primary,
      BookingStatus.pickedUp || BookingStatus.inTransit => AppColors.warning,
      BookingStatus.cancelled => Colors.redAccent,
      _ => AppColors.success,
    };

/// Compact list card used by the driver Trips tab and customer Bookings tab.
class BookingCard extends StatelessWidget {
  final Booking booking;
  final VoidCallback onTap;

  const BookingCard({super.key, required this.booking, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final b = booking;
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: RouteText(pickup: b.pickup, drop: b.drop)),
              const SizedBox(width: 8),
              StatusChip(label: bookingStatusLabel(context, b.status), color: bookingStatusColor(b.status)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${formatNum(b.weight)} T • ${b.cargoType} • ${b.vehicleNumber} • ${formatDate(b.pickupDate)}',
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Route, cargo, vehicle and driver details for a booking.
class BookingSummary extends StatelessWidget {
  final Booking booking;
  final bool showDriver;

  const BookingSummary({super.key, required this.booking, this.showDriver = false});

  Widget _row(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.muted),
            const SizedBox(width: 10),
            SizedBox(width: 90, child: Text(label, style: const TextStyle(color: AppColors.muted))),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.body))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final b = booking;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: RouteText(pickup: b.pickup, drop: b.drop, fontSize: 19)),
              const SizedBox(width: 8),
              StatusChip(label: bookingStatusLabel(context, b.status), color: bookingStatusColor(b.status)),
              CopyShareButton(
                text: bookingShareText(b),
                tooltip: tr(context, 'share'),
                copiedMessage: tr(context, 'copiedToClipboard'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _row(Icons.calendar_today_outlined, tr(context, 'pickupDate'), formatDate(b.pickupDate)),
          _row(Icons.inventory_2_outlined, tr(context, 'cargo'), '${b.cargoType} • ${formatNum(b.weight)} T'),
          _row(Icons.local_shipping_outlined, tr(context, 'vehicle'), '${b.vehicleNumber} (${b.vehicleType})'),
          _row(Icons.currency_rupee_rounded, tr(context, 'budget'),
              b.budget == null ? tr(context, 'budgetNegotiable') : formatRupees(b.budget!)),
          if (showDriver)
            _row(Icons.person_outline_rounded, tr(context, 'driver'),
                [b.driverName, b.driverPhone].where((s) => s.isNotEmpty).join(' • ')),
          if (b.notes.isNotEmpty) _row(Icons.notes_rounded, tr(context, 'notes'), b.notes),
        ],
      ),
    );
  }
}

/// Vertical stepper of the booking lifecycle with the time each step happened.
class BookingTimeline extends StatelessWidget {
  final Booking booking;

  const BookingTimeline({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    // A cancelled booking only ever got as far as "accepted".
    final steps = booking.status == BookingStatus.cancelled
        ? const [BookingStatus.accepted, BookingStatus.cancelled]
        : BookingStatus.flow;
    final currentIndex = steps.indexOf(booking.status);
    return AppCard(
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            _step(
              context,
              status: steps[i],
              done: i <= currentIndex,
              isLast: i == steps.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _step(BuildContext context, {required String status, required bool done, required bool isLast}) {
    final time = booking.timeline[status];
    final isCancel = status == BookingStatus.cancelled;
    final color = !done ? AppColors.border : (isCancel ? Colors.redAccent : AppColors.success);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Icon(
                !done ? Icons.radio_button_unchecked_rounded : (isCancel ? Icons.cancel_rounded : Icons.check_circle_rounded),
                color: color,
                size: 24,
              ),
              if (!isLast) Expanded(child: Container(width: 2, color: color)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bookingStatusLabel(context, status),
                    style: TextStyle(fontWeight: FontWeight.w800, color: done ? AppColors.title : AppColors.faint),
                  ),
                  if (time != null)
                    Text(formatDateTime(time), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared body for driver/customer booking detail screens.
class BookingDetailScaffold extends StatelessWidget {
  final String bookingId;
  final String title;
  final Widget Function(BuildContext context, Booking booking) builder;

  const BookingDetailScaffold({super.key, required this.bookingId, required this.title, required this.builder});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: _BookingStreamBody(bookingId: bookingId, builder: builder),
      ),
    );
  }
}

class _BookingStreamBody extends StatelessWidget {
  final String bookingId;
  final Widget Function(BuildContext context, Booking booking) builder;

  const _BookingStreamBody({required this.bookingId, required this.builder});

  @override
  Widget build(BuildContext context) {
    // Wrapped in a record so "booking doesn't exist" (null) counts as data.
    return LiveStream<(Booking?,)>(
      stream: () => BookingService.watch(bookingId).map((b) => (b,)),
      builder: (context, data) {
        final booking = data.$1;
        if (booking == null) return EmptyState(icon: Icons.search_off_rounded, title: tr(context, 'bookingNotFound'));
        return builder(context, booking);
      },
    );
  }
}
