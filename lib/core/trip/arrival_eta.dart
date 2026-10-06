import '../constants/logistics.dart';
import '../models/booking.dart';
import '../pricing/cities.dart';
import 'trip_eta.dart';

/// How far the driver still is from the pickup (T2, N2): the last shared
/// position to the pickup city of the offline table, at [TripEta.speedKmph].
/// Null without a shared position or when the pickup is not in the table.
/// LATER(paid): routing / traffic API for a road ETA.
class ArrivalEta {
  final int km;
  final Duration time;
  final DateTime at;

  const ArrivalEta(this.km, this.time, this.at);

  static const arrivedKm = 2;

  bool get arrived => km <= arrivedKm;

  static ArrivalEta? of(Booking b, {DateTime? now}) {
    if (b.status != BookingStatus.driverArriving && b.status != BookingStatus.accepted) return null;
    final p = b.lastKnownLocation;
    final city = findCity(b.pickup);
    if (p == null || city == null) return null;
    final km = haversineKm(p.latitude, p.longitude, city.lat, city.lng).round();
    final road = (km * 1.25).ceil();
    final time = TripEta.travelTime(road);
    return ArrivalEta(road, time, (now ?? DateTime.now()).add(time));
  }
}
