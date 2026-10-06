import 'package:flutter/material.dart';

import '../constants/logistics.dart';
import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../models/earnings.dart';
import '../pricing/gst.dart';
import '../services/booking_service.dart';
import '../services/pricing_service.dart';
import '../widgets/common.dart';
import '../widgets/live_stream.dart';
import '../widgets/logistics_labels.dart';
import 'invoice_issue_card.dart';
import 'payment_card.dart';

void openInvoice(BuildContext context, String bookingId) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceScreen(bookingId: bookingId)));
}

/// Short human-friendly reference derived from the booking id.
String invoiceNumber(Booking b) {
  final id = b.id.toUpperCase();
  return 'LG-${id.length > 8 ? id.substring(0, 8) : id}';
}

/// Trip invoice for a delivered booking with the GST split of the billed
/// amount (treated as GST-inclusive). Not a statutory tax invoice yet.
class InvoiceScreen extends StatelessWidget {
  final String bookingId;

  const InvoiceScreen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(tr(context, 'invoice'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: LiveDoc<Booking>(
          stream: () => BookingService.watch(bookingId),
          builder: (context, b) {
            if (b == null) return EmptyState(icon: Icons.search_off_rounded, title: tr(context, 'bookingNotFound'));
            if (b.status != BookingStatus.delivered) {
              return EmptyState(icon: Icons.receipt_long_outlined, title: tr(context, 'invoiceAfterDelivery'));
            }
            final amount = b.billAmountPaise;
            final gst = amount == null ? null : GstSplit.inclusive(amount, PricingService.config.gstPercent);
            final half = formatNum(PricingService.config.gstPercent / 2);
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                            const Text('LoadGo',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary)),
                            const Spacer(),
                            Text(invoiceNumber(b), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.body)),
                          ],
                        ),
                        const Divider(height: 28),
                        _InvoiceRow(tr(context, 'date'), formatDate(EarningsSummary.deliveredAt(b))),
                        _InvoiceRow(tr(context, 'pickupLocation'), b.pickup),
                        _InvoiceRow(tr(context, 'dropLocation'), b.drop),
                        _InvoiceRow(tr(context, 'cargo'), b.cargoType),
                        _InvoiceRow(tr(context, 'weightTons'), formatNum(b.weight)),
                        _InvoiceRow(tr(context, 'vehicle'), '${b.vehicleNumber} (${vehicleTypeLabel(context, b.vehicleType)})'),
                        _InvoiceRow(tr(context, 'driver'), b.driverName.isEmpty ? '--' : b.driverName),
                        _InvoiceRow(tr(context, 'lrNumber'), b.lrNumber),
                        if (b.ewayBillNo.isNotEmpty) _InvoiceRow(tr(context, 'ewayBill'), b.ewayBillNo),
                        const Divider(height: 28),
                        if (gst == null)
                          _InvoiceRow(tr(context, 'fare'), tr(context, 'budgetNegotiable'))
                        else ...[
                          Text(tr(context, 'taxBreakdown'), style: const TextStyle(fontWeight: FontWeight.w800)),
                          _InvoiceRow(tr(context, 'taxableValue'), formatPaise(gst.taxable)),
                          _InvoiceRow(trf(context, 'cgst', {'p': half}), formatPaise(gst.cgst)),
                          _InvoiceRow(trf(context, 'sgst', {'p': half}), formatPaise(gst.sgst)),
                          const Divider(height: 20),
                          Row(
                            children: [
                              Text(tr(context, 'invoiceTotal'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                              const Spacer(),
                              Text(
                                formatPaise(gst.total),
                                key: const ValueKey('invoiceTotal'),
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(tr(context, 'invoiceNote'), style: TextStyle(fontSize: 12, color: AppColors.faint)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  InvoiceIssueCard(booking: b),
                  const SizedBox(height: 12),
                  PaymentCard(booking: b),
                ],
              ),
            );
          },
        ),
      ),
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
            SizedBox(width: 130, child: Text(label, style: TextStyle(color: AppColors.muted))),
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.title)),
            ),
          ],
        ),
      );
}
