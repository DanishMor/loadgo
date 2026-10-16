import 'package:cloud_firestore/cloud_firestore.dart';

import '../adapters/partner_adapters.dart';
import '../adapters/sms_adapter.dart';
import '../features/features.dart';
import '../models/app_notification.dart';
import '../models/booking.dart';
import 'backend.dart';
import 'features_service.dart';
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

  /// G12: the SMS partner behind the `smsGateway` switch (the server checks the number is one of the caller's contacts).
  static SmsGateway sms = Msg91SmsGateway();

  /// +91 form of a number a person typed: ten digits, or with 91 / +91 in front; null otherwise.
  static String? e164India(String raw) {
    final d = raw.replaceAll(RegExp(r'[\s-]'), '');
    final m = RegExp(r'^(?:\+?91)?([6-9]\d{9})$').firstMatch(d);
    return m == null ? null : '+91${m.group(1)}';
  }

  /// Best effort: one SMS to each saved contact. Never throws and never blocks the SOS.
  static Future<int> smsContacts(Map<String, dynamic>? user, String text) async {
    if (!FeaturesService.isOn(FeatureKey.smsGateway)) return 0;
    var sent = 0;
    for (final c in contactsFrom(user)) {
      final to = e164India(c.phone);
      if (to == null) continue;
      try {
        if ((await sms.send(to, text)).ok) sent++;
      } catch (_) {}
    }
    return sent;
  }

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
    if (FeaturesService.isOn(FeatureKey.smsGateway)) {
      try {
        final user = (await Backend.db.collection('users').doc(uid).get()).data();
        final loc = location ?? booking?.lastKnownLocation;
        final where = loc == null ? '' : ' https://maps.google.com/?q=${loc.latitude.toStringAsFixed(4)},${loc.longitude.toStringAsFixed(4)}';
        smsContacts(user, 'SOS from a Load 20 user. Please call them.$where').ignore();
      } catch (_) {}
    }
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
