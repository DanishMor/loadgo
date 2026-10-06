import 'package:flutter/material.dart';

import '../constants/logistics.dart';
import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../services/booking_service.dart';
import '../widgets/common.dart';
import '../widgets/live_stream.dart';
import 'invoice_screen.dart';
import 'lr_screen.dart';
import 'pod_screen.dart';

/// Invoices, LRs and PODs of the user's bookings in one place. Drivers pass
/// [header] with their vehicle papers (that screen lives in lib/driver).
class DocumentsCenterScreen extends StatelessWidget {
  final bool asDriver;
  final Widget? header;

  const DocumentsCenterScreen({super.key, required this.asDriver, this.header});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(tr(context, 'documentsCenter'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: LiveStream<List<Booking>>(
          stream: asDriver ? BookingService.watchForDriver : BookingService.watchForCustomer,
          builder: (context, bookings) {
            final withDocs = bookings.where((b) => b.status != BookingStatus.cancelled).toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              children: [
                if (header != null) ...[header!, const SizedBox(height: 16)],
                Text(tr(context, 'tripDocuments'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                if (withDocs.isEmpty) Text(tr(context, 'noDocuments'), style: TextStyle(color: AppColors.muted)),
                for (final b in withDocs) ...[_BookingDocs(booking: b), const SizedBox(height: 10)],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BookingDocs extends StatelessWidget {
  final Booking booking;
  const _BookingDocs({required this.booking});

  @override
  Widget build(BuildContext context) {
    final b = booking;
    void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RouteText(pickup: b.pickup, drop: b.drop),
          Text('${b.lrNumber} • ${formatDate(b.pickupDate)}', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              if (b.status == BookingStatus.delivered)
                TextButton.icon(
                  key: ValueKey('invoice_${b.id}'),
                  onPressed: () => push(InvoiceScreen(bookingId: b.id)),
                  icon: const Icon(Icons.receipt_rounded, size: 18),
                  label: Text(tr(context, 'invoice')),
                ),
              TextButton.icon(
                onPressed: () => push(LrScreen(bookingId: b.id)),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: Text(tr(context, 'viewLr')),
              ),
              if (b.pickupOtpVerified)
                TextButton.icon(
                  onPressed: () => push(PodScreen(booking: b)),
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: Text(tr(context, 'viewPod')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
