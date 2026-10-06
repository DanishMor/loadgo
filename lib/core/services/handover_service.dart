import 'package:cloud_firestore/cloud_firestore.dart';

import '../enterprise/validators.dart';
import '../constants/logistics.dart';
import '../models/booking.dart';
import '../models/handover.dart';
import 'backend.dart';

/// Which leg of which shipment a booking is, from its load.
typedef LegRef = ({String shipmentId, int leg});

class HandoverException implements Exception {
  final String reason;
  const HandoverException(this.reason);
  @override
  String toString() => 'HandoverException($reason)';
}

/// Controlled handover between the two drivers of a two-leg shipment (IE10).
/// A record: the leg-1 driver confirms what they hand over (container, seal),
/// the leg-2 driver confirms what they received; a different seal is flagged.
class HandoverService {
  HandoverService._();

  static DocumentReference<Map<String, dynamic>> _doc(String shipmentId) => Backend.db.collection('handovers').doc(shipmentId);

  /// The shipment leg this booking carries, or null for an ordinary booking.
  static Future<LegRef?> legOf(Booking b) async {
    if (b.loadId.isEmpty) return null;
    final load = (await Backend.db.collection('loads').doc(b.loadId).get()).data();
    final id = load?['shipmentId'] as String?;
    final leg = (load?['shipmentLeg'] as num?)?.toInt();
    if (id == null || id.isEmpty || (leg != 1 && leg != 2)) return null;
    return (shipmentId: id, leg: leg!);
  }

  static Stream<Handover?> watch(String shipmentId) => _doc(shipmentId).snapshots().map((s) => s.exists ? Handover.fromDoc(s) : null);

  static String _cleanSeal(String seal) {
    final s = seal.trim();
    if (s.isNotEmpty && !isValidSealNumber(s)) throw const HandoverException('seal');
    return s;
  }

  /// Leg-1 driver: hands the container over (once, from unloading).
  static Future<void> handOver(Booking b, LegRef ref, {String container = '', String seal = '', String note = ''}) async {
    if (ref.leg != 1) throw const HandoverException('leg');
    final c = normaliseContainer(container);
    if (c.isNotEmpty && !isValidContainerNumber(c)) throw const HandoverException('container');
    if (note.trim().length > 200) throw const HandoverException('note');
    if (b.status != BookingStatus.unloading && b.status != BookingStatus.delivered) throw const HandoverException('status');
    if ((await _doc(ref.shipmentId).get()).exists) throw const HandoverException('already');
    await _doc(ref.shipmentId).set({
      'shipmentId': ref.shipmentId,
      'leg1': {
        'driverId': Backend.requireUid(),
        'bookingId': b.id,
        'sealNumber': _cleanSeal(seal),
        'containerNumber': c,
        'note': note.trim(),
        'at': FieldValue.serverTimestamp(),
      },
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Leg-2 driver: confirms what they received. Needs the leg-1 side first.
  static Future<bool> receive(Booking b, LegRef ref, {String seal = '', String note = ''}) async {
    if (ref.leg != 2) throw const HandoverException('leg');
    if (note.trim().length > 200) throw const HandoverException('note');
    final snap = await _doc(ref.shipmentId).get();
    final h = snap.exists ? Handover.fromDoc(snap) : null;
    if (h?.leg1 == null) throw const HandoverException('waiting');
    if (h!.leg2 != null) throw const HandoverException('already');
    final s = _cleanSeal(seal);
    final matches = s == h.leg1!.sealNumber;
    await _doc(ref.shipmentId).update({
      'leg2': {
        'driverId': Backend.requireUid(),
        'bookingId': b.id,
        'sealNumber': s,
        'sealMatches': matches,
        'note': note.trim(),
        'at': FieldValue.serverTimestamp(),
      },
    });
    return matches;
  }
}
