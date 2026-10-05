import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';
import '../models/vehicle.dart';

/// Expired-document rules (pure). Day granularity: a paper that expires today
/// is still valid today. Keep in sync with firestore.rules (`paperClear`,
/// `canTransact`).
class DocExpiry {
  DocExpiry._();

  static DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : null;

  /// The driver's licence expiry from `users.driverKyc.dlExpiry`.
  static DateTime? licenceExpiry(Map<String, dynamic>? profile) => _date((profile?['driverKyc'] as Map?)?['dlExpiry']);

  static bool licenceExpired(Map<String, dynamic>? profile, DateTime now) {
    final e = licenceExpiry(profile);
    return e != null && e.isBefore(DateTime(now.year, now.month, now.day));
  }

  /// `users.docOverrideUntil`, set by an admin only.
  static bool userOverrideActive(Map<String, dynamic>? profile, DateTime now) {
    final u = _date(profile?['docOverrideUntil']);
    return u != null && u.isAfter(now);
  }

  /// An expired licence stops the driver accepting loads, unless overridden.
  static bool licenceBlocked(Map<String, dynamic>? profile, DateTime now) =>
      licenceExpired(profile, now) && !userOverrideActive(profile, now);

  /// The availability a vehicle should have right now because of its papers,
  /// or null to leave it as it is. Only free vehicles are suspended (a vehicle
  /// on a trip finishes it first); only a vehicle the app suspended is lifted.
  static String? vehicleTarget(Vehicle v, DateTime now) {
    if (v.availability == VehicleAvailability.available && v.papersBlocked(now)) return VehicleAvailability.docExpired;
    if (v.availability == VehicleAvailability.docExpired && !v.papersBlocked(now)) return VehicleAvailability.available;
    return null;
  }
}
