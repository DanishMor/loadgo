import 'package:flutter/material.dart';

import '../core/security/secure_screen.dart';
import '../core/constants/logistics.dart';
import '../core/l10n/l10n.dart';
import '../core/models/booking.dart';
import '../core/services/trip_otp_attempts.dart';
import '../core/services/trip_otp_service.dart';
import '../core/widgets/common.dart';
import '../core/theme/design_tokens.dart';

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
          child: Text(label, style: DsStyle.inherit.copyWith(color: AppColors.muted)),
        ),
        SelectableText(
          code,
          key: ValueKey('otp_$label'),
          style: DsStyle.w700.copyWith(fontSize: big ? 26 : 16, letterSpacing: 4, color: AppColors.title),
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
        return SecureScope(child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.password_rounded, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    tr(context, 'tripCodes'),
                    style: DsStyle.w700.copyWith(color: AppColors.title),
                  ),
                ],
              ),
              if (beforePickup) _code(tr(context, 'pickupOtp'), o.pickupOtp, big: true),
              _code(tr(context, 'deliveryOtp'), o.deliveryOtp, big: !beforePickup),
              StreamBuilder<Duration?>(
                stream: TripOtpAttempts.watchLock(widget.booking.id, beforePickup ? TripOtpAttempts.pickup : TripOtpAttempts.delivery),
                builder: (context, lock) {
                  if (lock.data == null) return const SizedBox.shrink();
                  final c = context.ds;
                  return Container(
                    key: const ValueKey('otpLockNotice'),
                    margin: const EdgeInsets.only(top: DsSpace.s3),
                    padding: const EdgeInsets.all(DsSpace.s3),
                    decoration: BoxDecoration(color: c.errorBg, borderRadius: DsRadius.all(DsRadius.md)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.lock_clock_rounded, color: c.error),
                      const SizedBox(width: DsSpace.s2),
                      Expanded(child: Text(tr(context, 'tripOtpLockNotice'), style: DsStyle.inherit.copyWith(color: c.text))),
                    ]),
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(tr(context, 'otpShareNote'), style: DsStyle.t12w400.copyWith(color: AppColors.faint)),
            ],
          ),
        ));
      },
    );
  }
}
