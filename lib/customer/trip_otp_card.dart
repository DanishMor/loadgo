import 'package:flutter/material.dart';

import '../core/constants/logistics.dart';
import '../core/l10n/l10n.dart';
import '../core/models/booking.dart';
import '../core/services/trip_otp_service.dart';
import '../core/widgets/common.dart';

/// Customer's pickup and delivery codes for an active booking. The code
/// still needed is shown large; codes already used are hidden.
class TripOtpCard extends StatefulWidget {
  final Booking booking;
  const TripOtpCard({super.key, required this.booking});

  @override
  State<TripOtpCard> createState() => _TripOtpCardState();
}

class _TripOtpCardState extends State<TripOtpCard> {
  late Future<TripOtps> _otps = TripOtpService.ensure(widget.booking.id);

  Widget _code(String label, String code, {required bool big}) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(color: AppColors.muted)),
        ),
        SelectableText(
          code,
          key: ValueKey('otp_$label'),
          style: TextStyle(
            fontSize: big ? 26 : 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 4,
            color: AppColors.title,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final status = widget.booking.status;
    final flow = BookingStatus.flow;
    final beforePickup = flow.indexOf(status) < flow.indexOf(BookingStatus.pickedUp);
    if (!widget.booking.isActive) return const SizedBox.shrink();
    return FutureBuilder<TripOtps>(
      future: _otps,
      builder: (context, snap) {
        if (snap.hasError) {
          return AppCard(
            child: TextButton.icon(
              onPressed: () => setState(() {
                _otps = TripOtpService.ensure(widget.booking.id);
              }),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(tr(context, 'retry')),
            ),
          );
        }
        if (!snap.hasData) return const SizedBox.shrink();
        final o = snap.data!;
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.password_rounded, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    tr(context, 'tripCodes'),
                    style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.title),
                  ),
                ],
              ),
              if (beforePickup) _code(tr(context, 'pickupOtp'), o.pickupOtp, big: true),
              _code(tr(context, 'deliveryOtp'), o.deliveryOtp, big: !beforePickup),
              const SizedBox(height: 8),
              Text(tr(context, 'otpShareNote'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
            ],
          ),
        );
      },
    );
  }
}
