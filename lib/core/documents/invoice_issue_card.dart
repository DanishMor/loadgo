import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../models/invoice.dart';
import '../services/backend.dart';
import '../services/invoice_service.dart';
import '../widgets/common.dart';
import '../widgets/live_stream.dart';
import 'invoice_pdf.dart';

/// Under the invoice summary: the driver issues the numbered GST invoice and
/// records e-way bill details; both sides share the PDF.
class InvoiceIssueCard extends StatefulWidget {
  final Booking booking;

  /// Replaces the share sheet (tests).
  final Future<void> Function(TripInvoice, Booking)? onShare;

  const InvoiceIssueCard({super.key, required this.booking, this.onShare});

  @override
  State<InvoiceIssueCard> createState() => _InvoiceIssueCardState();
}

class _InvoiceIssueCardState extends State<InvoiceIssueCard> {
  // A list of zero or one: LiveStream treats a null value as "no data yet".
  late final Stream<List<TripInvoice>> _invoice =
      InvoiceService.watch(widget.booking.id).map((i) => [?i]).asBroadcastStream();
  late final _seller = TextEditingController(text: widget.booking.driverName);
  final _sellerGstin = TextEditingController();
  final _buyer = TextEditingController();
  final _buyerGstin = TextEditingController();
  final _eway = TextEditingController();
  final _distance = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_seller, _sellerGstin, _buyer, _buyerGstin, _eway, _distance]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _issue() async {
    setState(() => _busy = true);
    try {
      await InvoiceService.issue(
        booking: widget.booking,
        sellerName: _seller.text,
        sellerGstin: _sellerGstin.text,
        buyerName: _buyer.text,
        buyerGstin: _buyerGstin.text,
        ewayBillNo: _eway.text,
        ewayDistanceKm: int.tryParse(_distance.text.trim()),
      );
      if (mounted) showSnack(context, tr(context, 'invoiceIssued'));
    } on InvoiceException catch (e) {
      if (mounted) {
        showSnack(context, switch (e.reason) {
          'gstin' => tr(context, 'gstinInvalid'),
          'eway' => tr(context, 'invoiceBadEway'),
          'no_amount' => tr(context, 'invoiceNoAmount'),
          _ => tr(context, 'somethingWrong'),
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveEway(TripInvoice inv) async {
    try {
      await InvoiceService.saveEway(inv.bookingId, ewayBillNo: _eway.text, distanceKm: int.tryParse(_distance.text.trim()));
      if (mounted) showSnack(context, tr(context, 'ewaySaved'));
    } on InvoiceException {
      if (mounted) showSnack(context, tr(context, 'invoiceBadEway'));
    }
  }

  Widget _field(String key, TextEditingController c, String label, {int max = 80, bool digits = false, bool caps = false}) => TextField(
        key: ValueKey(key),
        controller: c,
        maxLength: max,
        keyboardType: digits ? TextInputType.number : null,
        textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.none,
        inputFormatters: [if (digits) FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, counterText: ''),
      );

  @override
  Widget build(BuildContext context) {
    final isIssuer = widget.booking.driverId == Backend.uid;
    return LiveStream<List<TripInvoice>>(
      stream: () => _invoice,
      compact: true,
      builder: (context, found) {
        final inv = found.isEmpty ? null : found.first;
        final title = Text(tr(context, 'invoiceIssueTitle'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.title));
        if (inv != null) {
          return AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              title,
              const SizedBox(height: 4),
              Text(trf(context, 'invoiceNumberLine', {'no': inv.number}), key: const ValueKey('invoiceSeriesNo'), style: const TextStyle(fontWeight: FontWeight.w700)),
              if (inv.ewayBillNo.isNotEmpty) Text('${tr(context, 'ewayBill')}: ${inv.ewayBillNo}'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('shareInvoicePdf'),
                onPressed: () => (widget.onShare ?? shareInvoicePdf)(inv, widget.booking),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(tr(context, 'invoiceSharePdf')),
              ),
              if (isIssuer) ...[
                const SizedBox(height: 8),
                _field('ewayNo', _eway, tr(context, 'ewayBill'), max: 12, digits: true),
                _field('ewayKm', _distance, tr(context, 'ewayDistance'), max: 4, digits: true),
                Text(tr(context, 'ewayRecordNote'), style: TextStyle(fontSize: 12, color: AppColors.faint)),
                TextButton(key: const ValueKey('ewayUpdate'), onPressed: () => _saveEway(inv), child: Text(tr(context, 'save'))),
              ],
            ]),
          );
        }
        if (!isIssuer) {
          return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, const SizedBox(height: 4), Text(tr(context, 'invoicePending'))]));
        }
        return AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            title,
            _field('sellerName', _seller, tr(context, 'sellerNameLabel')),
            _field('sellerGstin', _sellerGstin, tr(context, 'sellerGstinLabel'), max: 15, caps: true),
            _field('buyerName', _buyer, tr(context, 'buyerNameLabel')),
            _field('buyerGstin', _buyerGstin, tr(context, 'buyerGstinLabel'), max: 15, caps: true),
            _field('ewayNo', _eway, tr(context, 'ewayBill'), max: 12, digits: true),
            _field('ewayKm', _distance, tr(context, 'ewayDistance'), max: 4, digits: true),
            Text(tr(context, 'ewayRecordNote'), style: TextStyle(fontSize: 12, color: AppColors.faint)),
            const SizedBox(height: 8),
            PrimaryButton(label: tr(context, 'invoiceIssue'), loading: _busy, onPressed: _issue),
          ]),
        );
      },
    );
  }
}
