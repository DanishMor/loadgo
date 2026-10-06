import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_notification.dart';
import '../models/booking.dart';
import '../models/support_ticket.dart';
import '../models/trip_evidence.dart';
import '../trip/trip_alerts.dart';
import 'audit_service.dart';
import 'backend.dart';
import 'location_service.dart';
import 'notification_service.dart';
import 'support_service.dart';

class EvidenceException implements Exception {
  final String reason;
  const EvidenceException(this.reason);

  @override
  String toString() => 'EvidenceException($reason)';
}

/// Evidence on a trip: GPS at pickup and delivery, odometer, receiver
/// signature, cargo document records, and accident reports. All records;
/// photos need Storage (LATER(paid)).
class TripEvidenceService {
  TripEvidenceService._();

  static DocumentReference<Map<String, dynamic>> _booking(String id) => Backend.db.collection('bookings').doc(id);

  /// Driver: saves where the phone is now with the pickup or delivery event.
  /// Best effort: returns false when no position is available. When [place]
  /// (the booking's pickup or drop) is a known city and the point is far from
  /// it, a `gps_mismatch` risk signal is written for admins (F10, F11).
  static Future<bool> saveGps(String bookingId, {required bool pickup, String? place}) async {
    final pos = await LocationService.current();
    if (pos == null) return false;
    final key = pickup ? 'pickupGps' : 'deliveryGps';
    final batch = Backend.db.batch();
    batch.update(_booking(bookingId), {
      key: GeoPoint(pos.lat, pos.lng),
      '${key}At': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    AuditService.inBatch(batch, AuditType.evidence, bookingId: bookingId, data: {
      'kind': pickup ? 'pickup_gps' : 'delivery_gps',
      'lat': double.parse(pos.lat.toStringAsFixed(4)),
      'lng': double.parse(pos.lng.toStringAsFixed(4)),
    });
    final km = place == null ? null : gpsMismatchKm(pos.lat, pos.lng, place);
    if (km != null) {
      batch.set(Backend.db.collection('risk_signals').doc(), {
        'uid': Backend.requireUid(),
        'type': 'gps_mismatch',
        'bookingId': bookingId,
        'note': '${pickup ? 'pickup' : 'delivery'} GPS ${km.round()} km from $place',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    return true;
  }

  /// Driver: odometer reading (km) at the start or the end of the trip, once each.
  static Future<void> setOdometer(Booking b, {required bool start, required int km}) async {
    if (km < 0 || km > 9999999) throw const EvidenceException('km');
    if (!start && b.odometerStart != null && km < b.odometerStart!) throw const EvidenceException('end_before_start');
    final batch = Backend.db.batch();
    batch.update(_booking(b.id), {
      start ? 'odometerStart' : 'odometerEnd': km,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    AuditService.inBatch(batch, AuditType.evidence, bookingId: b.id, data: {'kind': start ? 'odometer_start' : 'odometer_end', 'km': km});
    await batch.commit();
  }

  // ---- signature ----

  static DocumentReference<Map<String, dynamic>> _signature(String bookingId) =>
      _booking(bookingId).collection('signatures').doc('receiver');

  /// Driver: the receiver signs on the phone at delivery (once).
  static Future<void> saveSignature(Booking b, SignatureStrokes sig) async {
    if (sig.isEmpty) throw const EvidenceException('empty');
    if ((await _signature(b.id).get()).exists) throw const EvidenceException('already');
    final batch = Backend.db.batch();
    batch.set(_signature(b.id), {
      'strokes': sig.toFirestore(),
      'driverId': Backend.requireUid(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    AuditService.inBatch(batch, AuditType.evidence, bookingId: b.id, data: {'kind': 'signature'});
    await batch.commit();
  }

  static Stream<SignatureStrokes?> watchSignature(String bookingId) =>
      _signature(bookingId).snapshots().map((s) => s.exists ? SignatureStrokes.fromFirestore(s.data()!['strokes']) : null);

  // ---- cargo documents (versioned) ----

  static CollectionReference<Map<String, dynamic>> _docs(String bookingId) => _booking(bookingId).collection('cargo_docs');

  /// Either party records a document reference. A new record of the same
  /// type is a new version; nothing is overwritten.
  static Future<void> addCargoDoc(Booking b, {required String type, required String number, String note = '', int? leg}) async {
    final n = number.trim();
    if (!CargoDocType.all.contains(type)) throw ArgumentError.value(type, 'type');
    if (n.isEmpty || n.length > 40 || note.trim().length > 200) throw const EvidenceException('invalid');
    if (leg != null && leg != 1 && leg != 2) throw ArgumentError.value(leg, 'leg');
    final batch = Backend.db.batch();
    batch.set(_docs(b.id).doc(), {
      'type': type,
      'number': n,
      if (note.trim().isNotEmpty) 'note': note.trim(),
      'leg': ?leg,
      'addedBy': Backend.requireUid(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    AuditService.inBatch(batch, AuditType.evidence, bookingId: b.id, data: {'kind': 'cargo_doc', 'docType': type, 'leg': ?leg});
    await batch.commit();
  }

  /// Every record, oldest first (the history of each document).
  static Stream<List<CargoDoc>> watchCargoDocs(String bookingId) => _docs(bookingId).snapshots().map((s) {
        final list = [for (final d in s.docs) CargoDoc.fromDoc(d.id, d.data())];
        list.sort((a, b) => (a.createdAt ?? DateTime(3000)).compareTo(b.createdAt ?? DateTime(3000)));
        return list;
      });

  /// A party opened the cargo documents of the booking (DOC14).
  static Future<void> logDocView(String bookingId) =>
      AuditService.record(AuditType.docView, bookingId: bookingId, data: {'doc': 'cargo_docs'});

  // ---- accident ----

  /// Driver: reports an accident. Opens an urgent safety ticket for LoadGo
  /// and tells the customer. Returns the ticket id.
  static Future<String> reportAccident(Booking b, String description) async {
    final text = description.trim();
    if (text.length < 5 || text.length > 500) throw const EvidenceException('description');
    final ticketId = await SupportService.create(
      category: TicketCategory.safety,
      subject: 'Accident: ${b.pickup} → ${b.drop}',
      description: text,
      bookingId: b.id,
    );
    final batch = Backend.db.batch();
    NotificationService.addInBatch(
      batch,
      userId: b.customerId,
      type: NotificationType.accidentReported,
      message: '${b.pickup} → ${b.drop}',
      relatedId: b.id,
    );
    AuditService.inBatch(batch, AuditType.evidence, bookingId: b.id, data: {'kind': 'accident', 'ticketId': ticketId});
    await batch.commit();
    return ticketId;
  }
}
