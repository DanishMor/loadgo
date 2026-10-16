import 'package:flutter/material.dart';

import '../constants/logistics.dart';
import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../widgets/common.dart';
import '../widgets/logistics_labels.dart';
import '../models/trip_evidence.dart';
import '../services/trip_evidence_service.dart';
import '../widgets/signature_pad.dart';
import '../theme/design_tokens.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../features/features.dart';
import '../photos/photo_widgets.dart';
import '../services/backend.dart';
import '../widgets/feature_gate.dart';

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
          child: Text(label, style: DsStyle.inherit.copyWith(color: AppColors.muted)),
        ),
        Expanded(
          child: Text(
            value,
            style: DsStyle.w600.copyWith(color: AppColors.title),
          ),
        ),
      ],
    ),
  );

  Widget _photosLater(BuildContext context) => AppCard(
    child: Row(
      children: [
        Icon(Icons.photo_library_outlined, color: AppColors.faint),
        const SizedBox(width: 10),
        Expanded(
          child: Text(tr(context, 'photosLater'), style: DsStyle.inherit.copyWith(color: AppColors.muted)),
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
          style: DsStyle.t16w700.copyWith(color: AppColors.title),
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
        title: Text(tr(context, 'podTitle'), style: DsStyle.w700),
      ),
      body: SafeArea(
        // Not lazy: the packet is short and should read like one document.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _section(tr(context, 'route'), [
                Text(b.route.join('  →  '), style: DsStyle.w700),
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
              // With the photoUploads switch on, the photos taken on this trip; else the old note.
              FeatureGate(
                featureKey: FeatureKey.photoUploads,
                otherwise: _photosLater(context),
                child: _TripPhotos(bookingId: b.id),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The photos taken on this trip (pickup, delivery, proof, damage), read with the sign-in.
class _TripPhotos extends StatefulWidget {
  final String bookingId;
  const _TripPhotos({required this.bookingId});

  @override
  State<_TripPhotos> createState() => _TripPhotosState();
}

class _TripPhotosState extends State<_TripPhotos> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream = Backend.db.collection('bookings').doc(widget.bookingId).collection('proofs').limit(30).snapshots();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(context, 'photosTitle'), style: DsStyle.t16w700.copyWith(color: AppColors.title)),
          const SizedBox(height: 6),
          StreamBuilder(
            stream: _stream,
            builder: (context, snap) {
              final docs = [for (final d in snap.data?.docs ?? const []) if (d.data()['path'] is String) d];
              if (docs.isEmpty) return Text(tr(context, 'photosNone'), key: const ValueKey('noTripPhotos'), style: DsStyle.inherit.copyWith(color: AppColors.muted));
              return Wrap(spacing: 10, runSpacing: 10, children: [
                for (final d in docs)
                  Column(key: ValueKey('tripPhoto_${d.id}'), mainAxisSize: MainAxisSize.min, children: [
                    PhotoImage(d.data()['path'] as String, size: 96),
                    SizedBox(width: 96, child: Text(tr(context, 'photoKind_${d.data()['kind']}'), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: DsStyle.t12w400.copyWith(color: AppColors.muted))),
                  ]),
              ]);
            },
          ),
        ],
      ),
    );
  }
}
