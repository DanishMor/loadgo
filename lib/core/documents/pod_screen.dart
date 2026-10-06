import 'package:flutter/material.dart';

import '../constants/logistics.dart';
import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../widgets/common.dart';
import '../widgets/logistics_labels.dart';
import '../models/trip_evidence.dart';
import '../services/trip_evidence_service.dart';
import '../widgets/signature_pad.dart';

/// Proof-of-delivery packet: timeline with times, OTP checks, cargo details
/// at pickup and receiver details at delivery. Same view for both parties.
class PodScreen extends StatelessWidget {
  final Booking booking;
  const PodScreen({super.key, required this.booking});

  static Widget row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(label, style: TextStyle(color: AppColors.muted)),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.title),
          ),
        ),
      ],
    ),
  );

  Widget _section(String title, List<Widget> children) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.title),
        ),
        const SizedBox(height: 6),
        ...children,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final p = b.pickupProof;
    final d = b.deliveryProof;
    String yes(bool v) => v ? tr(context, 'otpVerified') : tr(context, 'notYet');
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(tr(context, 'podTitle'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        // Not lazy: the packet is short and should read like one document.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _section(tr(context, 'route'), [
                Text(b.route.join('  →  '), style: const TextStyle(fontWeight: FontWeight.w700)),
                row(tr(context, 'lrNumber'), b.lrNumber),
                row(tr(context, 'vehicle'), '${b.vehicleNumber} (${vehicleTypeLabel(context, b.vehicleType)})'),
                if (b.driverName.isNotEmpty) row(tr(context, 'driver'), b.driverName),
              ]),
              const SizedBox(height: 12),
              _section(tr(context, 'tripDetails'), [
                for (final s in BookingStatus.flow)
                  row(bookingStatusLabel(context, s), b.timeline[s] == null ? '—' : formatDateTime(b.timeline[s]!)),
              ]),
              const SizedBox(height: 12),
              _section(tr(context, 'pickupOtp'), [
                row(tr(context, 'pickupOtp'), yes(b.pickupOtpVerified)),
                if (p != null) ...[
                  row(tr(context, 'packages'), '${p.packages}'),
                  row(tr(context, 'actualWeight'), '${formatNum(p.weightTons)} T'),
                  if (p.sealNumber.isNotEmpty) row(tr(context, 'sealNumber'), p.sealNumber),
                  if (p.damageNote.isNotEmpty) row(tr(context, 'damageNote'), p.damageNote),
                ],
              ]),
              const SizedBox(height: 12),
              _section(tr(context, 'deliveryOtp'), [
                row(tr(context, 'deliveryOtp'), yes(b.deliveryOtpVerified)),
                if (d != null) ...[
                  row(tr(context, 'receiverName'), d.receiverName),
                  if (d.receiverPhone.isNotEmpty) row(tr(context, 'receiverPhone'), d.receiverPhone),
                  if (d.damageNote.isNotEmpty) row(tr(context, 'damageNote'), d.damageNote),
                ],
              ]),
              const SizedBox(height: 12),
              _section(tr(context, 'tripEvidence'), [
                row(tr(context, 'pickupGpsLabel'), b.pickupGps == null ? '—' : '${b.pickupGps!.latitude.toStringAsFixed(5)}, ${b.pickupGps!.longitude.toStringAsFixed(5)}'),
                row(tr(context, 'deliveryGpsLabel'), b.deliveryGps == null ? '—' : '${b.deliveryGps!.latitude.toStringAsFixed(5)}, ${b.deliveryGps!.longitude.toStringAsFixed(5)}'),
                row(tr(context, 'odometerStartLabel'), b.odometerStart == null ? '—' : '${b.odometerStart} km'),
                row(tr(context, 'odometerEndLabel'), b.odometerEnd == null ? '—' : '${b.odometerEnd} km'),
                StreamBuilder<SignatureStrokes?>(
                  stream: TripEvidenceService.watchSignature(b.id),
                  builder: (context, snap) => snap.data == null
                      ? row(tr(context, 'receiverSignature'), '—')
                      : Padding(padding: const EdgeInsets.only(top: 6), child: SignatureView(signature: snap.data!)),
                ),
              ]),
              const SizedBox(height: 12),
              // LATER(paid): pickup/delivery photos need Firebase Storage (Blaze plan).
              AppCard(
                child: Row(
                  children: [
                    Icon(Icons.photo_library_outlined, color: AppColors.faint),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(tr(context, 'photosLater'), style: TextStyle(color: AppColors.muted)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
