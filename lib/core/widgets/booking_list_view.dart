import 'package:flutter/material.dart';

import '../models/booking.dart';
import 'common.dart';
import 'live_stream.dart';
import 'paged_live_stream.dart';
import 'booking_widgets.dart';

/// Titled live list of bookings; used for the driver Trips tab and the
/// customer Bookings tab.
class BookingListView extends StatelessWidget {
  final String title;
  final PagedStreamFactory<Booking> bookings;
  final String emptyTitle;
  final String? emptySubtitle;
  final ValueChanged<String> onOpen;

  const BookingListView({
    super.key,
    required this.title,
    required this.bookings,
    required this.emptyTitle,
    this.emptySubtitle,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.title)),
          ),
          Expanded(
            child: PagedLiveStream<Booking>(
              stream: bookings,
              builder: (context, list, loadMore) {
                if (list.isEmpty) {
                  return EmptyState(icon: Icons.receipt_long_rounded, title: emptyTitle, subtitle: emptySubtitle);
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                  itemCount: list.length + (loadMore == null ? 0 : 1),
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) =>
                      i == list.length ? loadMore! : BookingCard(booking: list[i], onTap: () => onOpen(list[i].id)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Small card on Driver Home showing the current (undelivered) trip.
class ActiveTripCard extends StatelessWidget {
  final StreamFactory<List<Booking>> bookings;
  final ValueChanged<String> onOpen;
  final Widget empty;

  const ActiveTripCard({super.key, required this.bookings, required this.onOpen, required this.empty});

  @override
  Widget build(BuildContext context) {
    return LiveStream<List<Booking>>(
      stream: bookings,
      compact: true,
      builder: (context, all) {
        final active = all.where((b) => b.isActive).toList();
        if (active.isEmpty) return empty;
        return Column(
          children: [
            for (final b in active) ...[
              BookingCard(booking: b, onTap: () => onOpen(b.id)),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}
