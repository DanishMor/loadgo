import 'package:flutter/material.dart';

import '../../core/constants/logistics.dart';
import '../../core/models/booking.dart';
import '../../core/models/earnings.dart';
import '../../core/widgets/common.dart';
import '../../main.dart';
import 'booking_tracking_screen.dart';
import 'booking_widgets.dart';

void openInvoice(BuildContext context, String bookingId) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceScreen(bookingId: bookingId)));
}

/// Short human-friendly reference derived from the booking id.
String invoiceNumber(Booking b) {
  final id = b.id.toUpperCase();
  return 'LG-${id.length > 8 ? id.substring(0, 8) : id}';
}

/// Simple trip summary for a delivered booking (not a tax invoice).
class InvoiceScreen extends StatelessWidget {
  final String bookingId;

  const InvoiceScreen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context) {
    return BookingDetailScaffold(
      bookingId: bookingId,
      title: tr(context, 'invoice'),
      builder: (context, b) {
        if (b.status != BookingStatus.delivered) {
          return EmptyState(icon: Icons.receipt_long_outlined, title: tr(context, 'invoiceAfterDelivery'));
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          children: [
            AppCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.local_shipping_rounded, color: AppColors.primary),
                      const SizedBox(width: 8),
                      const Text('LoadGo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary)),
                      const Spacer(),
                      Text(invoiceNumber(b), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.body)),
                    ],
                  ),
                  const Divider(height: 28),
                  _InvoiceRow(tr(context, 'date'), formatDate(EarningsSummary.deliveredAt(b))),
                  _InvoiceRow(tr(context, 'pickupLocation'), b.pickup),
                  _InvoiceRow(tr(context, 'dropLocation'), b.drop),
                  _InvoiceRow(tr(context, 'cargo'), b.cargoType),
                  _InvoiceRow(tr(context, 'weightTons'), formatNum(b.weight)),
                  _InvoiceRow(tr(context, 'vehicle'), '${b.vehicleNumber} (${b.vehicleType})'),
                  _InvoiceRow(tr(context, 'driver'), b.driverName.isEmpty ? '--' : b.driverName),
                  const Divider(height: 28),
                  Row(
                    children: [
                      Text(tr(context, 'fare'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      Text(
                        b.budget == null ? tr(context, 'budgetNegotiable') : formatRupees(b.budget!),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(tr(context, 'invoiceNote'), style: const TextStyle(fontSize: 12, color: AppColors.faint)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => openBookingTracking(context, b.id),
              icon: const Icon(Icons.timeline_rounded),
              label: Text(tr(context, 'viewTrip')),
            ),
          ],
        );
      },
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  final String label;
  final String value;
  const _InvoiceRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 120, child: Text(label, style: const TextStyle(color: AppColors.muted))),
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.title)),
            ),
          ],
        ),
      );
}
