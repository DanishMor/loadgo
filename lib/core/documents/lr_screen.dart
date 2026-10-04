import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../services/booking_service.dart';
import '../widgets/common.dart';
import '../widgets/logistics_labels.dart';
import 'pod_screen.dart';

/// Digital lorry receipt (LR / bilty) generated from the booking, with the
/// e-way bill number either party can record.
class LrScreen extends StatelessWidget {
  final String bookingId;
  const LrScreen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(tr(context, 'lrTitle'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: StreamBuilder<Booking?>(
          stream: BookingService.watch(bookingId),
          builder: (context, snap) {
            final b = snap.data;
            if (b == null) return const Center(child: CircularProgressIndicator());
            final row = PodScreen.row;
            final weight = b.pickupProof?.weightTons ?? b.weight;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      row(tr(context, 'lrNumber'), b.lrNumber),
                      row(tr(context, 'date'), formatDate(b.timeline['accepted'] ?? b.createdAt?.toDate())),
                      row(tr(context, 'consignor'), b.pickup),
                      row(
                        tr(context, 'consignee'),
                        [
                          b.deliveryProof?.receiverName,
                          b.drop,
                        ].whereType<String>().where((s) => s.isNotEmpty).join(', '),
                      ),
                      row(tr(context, 'route'), b.route.join(' → ')),
                      row(
                        tr(context, 'goods'),
                        '${b.cargoType}${b.pickupProof == null ? '' : ' • ${b.pickupProof!.packages} pkgs'}',
                      ),
                      row(tr(context, 'weightTons'), formatNum(weight)),
                      row(tr(context, 'vehicle'), '${b.vehicleNumber} (${vehicleTypeLabel(context, b.vehicleType)})'),
                      if (b.driverName.isNotEmpty) row(tr(context, 'driver'), b.driverName),
                      if (b.pickupProof?.sealNumber.isNotEmpty == true)
                        row(tr(context, 'sealNumber'), b.pickupProof!.sealNumber),
                      if (b.agreedFarePaise != null) row(tr(context, 'agreedFare'), formatPaise(b.agreedFarePaise!)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _EwayBillField(booking: b),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EwayBillField extends StatefulWidget {
  final Booking booking;
  const _EwayBillField({required this.booking});

  @override
  State<_EwayBillField> createState() => _EwayBillFieldState();
}

class _EwayBillFieldState extends State<_EwayBillField> {
  late final _ctrl = TextEditingController(text: widget.booking.ewayBillNo);
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _ctrl.text.trim();
    if (text.isNotEmpty && !RegExp(r'^\d{12}$').hasMatch(text)) {
      showSnack(context, tr(context, 'invalidEwayBill'));
      return;
    }
    setState(() => _saving = true);
    try {
      await BookingService.setEwayBill(widget.booking.id, text);
      if (mounted) showSnack(context, tr(context, 'ewaySaved'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('ewayField'),
              controller: _ctrl,
              keyboardType: TextInputType.number,
              maxLength: 12,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: tr(context, 'ewayBill'), counterText: ''),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const ValueKey('ewaySave'),
            onPressed: _saving || widget.booking.status == 'cancelled' ? null : _save,
            child: Text(tr(context, 'save')),
          ),
        ],
      ),
    );
  }
}
