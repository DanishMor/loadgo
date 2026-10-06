import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../constants/logistics.dart';
import '../models/booking.dart';
import '../payments/payment_logic.dart';
import '../widgets/common.dart';

/// E-way bill validity warning (DOC4): nothing without a bill number, a hint
/// without a date, a warning when the bill expires soon or has expired. The
/// date is what the user recorded; nothing is checked with the GST portal
/// (LATER(paid)).
class EwayStatusLine extends StatelessWidget {
  final Booking booking;
  final DateTime Function() now;
  const EwayStatusLine({super.key, required this.booking, this.now = DateTime.now});

  @override
  Widget build(BuildContext context) {
    if (booking.status == BookingStatus.delivered || booking.status == BookingStatus.cancelled) return const SizedBox.shrink();
    final st = ewayStatus(number: booking.ewayBillNo, validUntil: booking.ewayValidUntil, now: now());
    final (IconData icon, Color color, String text)? view = switch (st.state) {
      EwayState.missing => null,
      EwayState.noDate => (Icons.info_outline_rounded, AppColors.muted, tr(context, 'ewayNoDateWarn')),
      EwayState.expired => (Icons.error_outline_rounded, Colors.redAccent, tr(context, 'ewayExpiredWarn')),
      EwayState.expiring => (Icons.warning_amber_rounded, AppColors.warning, trf(context, 'ewayExpiringWarn', {'h': (st.left!.inMinutes / 60).ceil()})),
      EwayState.valid => (Icons.verified_outlined, AppColors.success, trf(context, 'ewayValidLine', {'date': formatDate(booking.ewayValidUntil!)})),
    };
    if (view == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        Icon(view.$1, size: 18, color: view.$2),
        const SizedBox(width: 8),
        Expanded(child: Text(view.$3, key: ValueKey('eway_${st.state.name}'), style: TextStyle(fontSize: 12, color: view.$2, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}
