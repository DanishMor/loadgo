import 'package:flutter/material.dart';

import '../../core/constants/logistics.dart';
import '../../core/models/booking.dart';
import '../../core/widgets/common.dart';
import '../../main.dart';
import '../shared/live_stream.dart';
import 'booking_widgets.dart';

/// Customer "Bookings" tab split into active and past (delivered/cancelled).
/// Delivered bookings open their invoice; everything else opens tracking.
class CustomerBookingsView extends StatefulWidget {
  final StreamFactory<List<Booking>> bookings;
  final ValueChanged<String> onOpenTracking;
  final ValueChanged<String> onOpenInvoice;

  const CustomerBookingsView({
    super.key,
    required this.bookings,
    required this.onOpenTracking,
    required this.onOpenInvoice,
  });

  @override
  State<CustomerBookingsView> createState() => _CustomerBookingsViewState();
}

class _CustomerBookingsViewState extends State<CustomerBookingsView> {
  bool _showPast = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(tr(context, 'bookings'),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.title)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(tr(context, 'activeBookings'))),
                ButtonSegment(value: true, label: Text(tr(context, 'pastBookings'))),
              ],
              selected: {_showPast},
              onSelectionChanged: (v) => setState(() => _showPast = v.first),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LiveStream<List<Booking>>(
              stream: widget.bookings,
              builder: (context, all) {
                final list = all.where((b) => b.isActive != _showPast).toList();
                if (list.isEmpty) {
                  return EmptyState(
                    icon: _showPast ? Icons.history_rounded : Icons.receipt_long_rounded,
                    title: tr(context, _showPast ? 'noPastBookings' : 'noBookingsTitle'),
                    subtitle: _showPast ? null : tr(context, 'noBookingsSub'),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final b = list[i];
                    final delivered = b.status == BookingStatus.delivered;
                    return Column(
                      children: [
                        BookingCard(
                          booking: b,
                          onTap: () => delivered ? widget.onOpenInvoice(b.id) : widget.onOpenTracking(b.id),
                        ),
                        if (delivered)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => widget.onOpenInvoice(b.id),
                              icon: const Icon(Icons.receipt_long_rounded, size: 18),
                              label: Text(tr(context, 'viewInvoice')),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
