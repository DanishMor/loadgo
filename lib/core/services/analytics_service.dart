import '../analytics/trip_stats.dart';
import '../models/booking.dart';
import '../models/load.dart';
import '../models/offer.dart';
import 'backend.dart';

/// Reads the signed-in user's history for the analytics screens.
class AnalyticsService {
  AnalyticsService._();

  static const readLimit = 500;

  static Future<CustomerStats> customer() async {
    final uid = Backend.requireUid();
    final db = Backend.db;
    final results = await Future.wait([
      db.collection('loads').where('shipperId', isEqualTo: uid).limit(readLimit).get(),
      db.collection('bookings').where('customerId', isEqualTo: uid).limit(readLimit).get(),
    ]);
    return CustomerStats.from(results[0].docs.map(Load.fromDoc), results[1].docs.map(Booking.fromDoc));
  }

  static Future<DriverStats> driver() async {
    final uid = Backend.requireUid();
    final db = Backend.db;
    final results = await Future.wait([
      db.collection('bookings').where('driverId', isEqualTo: uid).limit(readLimit).get(),
      db.collection('offers').where('driverId', isEqualTo: uid).limit(readLimit).get(),
    ]);
    return DriverStats.from(results[0].docs.map(Booking.fromDoc), results[1].docs.map(Offer.fromDoc));
  }
}
