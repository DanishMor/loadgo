import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_notification.dart';
import '../models/booking.dart';
import 'backend.dart';
import 'notification_service.dart';

/// Someone the user wants called in an emergency.
class EmergencyContact {
  final String name;
  final String phone;
  const EmergencyContact(this.name, this.phone);

  Map<String, String> toMap() => {'name': name, 'phone': phone};

  static EmergencyContact? fromMap(Object? m) {
    if (m is! Map) return null;
    return EmergencyContact(m['name']?.toString() ?? '', m['phone']?.toString() ?? '');
  }
}

/// SOS alerts, emergency contacts and breakdown reports.
///
/// LATER(paid): SMS to emergency contacts / masked calling; for now the app
/// offers tap-to-call and the alert is reviewed by admins in the app.
class SafetyService {
  SafetyService._();

  static const maxContacts = 3;

  static List<EmergencyContact> contactsFrom(Map<String, dynamic>? user) => [
        for (final m in (user?['emergencyContacts'] as List?) ?? const []) ?EmergencyContact.fromMap(m),
      ];

  static Future<void> saveContacts(List<EmergencyContact> contacts) {
    if (contacts.length > maxContacts) throw ArgumentError('At most $maxContacts contacts');
    return Backend.db.collection('users').doc(Backend.requireUid()).update({
      'emergencyContacts': [for (final c in contacts) c.toMap()],
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Raises an SOS for admins with the last known position (if any).
  static Future<String> sendSos({Booking? booking, GeoPoint? location}) async {
    final uid = Backend.requireUid();
    final ref = await Backend.db.collection('sos_alerts').add({
      'userId': uid,
      'bookingId': ?booking?.id,
      'location': location ?? booking?.lastKnownLocation,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Driver reports a breakdown on an active trip; the customer is notified
  /// and the booking is flagged for a replacement vehicle.
  static Future<void> reportBreakdown(Booking booking, {String note = '', bool needReplacement = true}) async {
    final ref = Backend.db.collection('bookings').doc(booking.id);
    await Backend.db.runTransaction((tx) async {
      tx.update(ref, {
        'breakdown': {
          'note': note.trim(),
          'replacementRequested': needReplacement,
          'reportedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });
      NotificationService.addInTransaction(
        tx,
        userId: booking.customerId,
        type: NotificationType.breakdownReported,
        message: '${booking.pickup} → ${booking.drop}',
        relatedId: booking.id,
      );
    });
  }
}
