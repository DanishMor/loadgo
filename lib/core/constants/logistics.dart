/// Shared domain constants for vehicles, loads and bookings.
library;

const List<String> cargoTypes = [
  'General',
  'FMCG',
  'Agriculture',
  'Construction',
  'Electronics',
  'Furniture',
  'Machinery',
  'Chemicals',
  'Other',
];

class VehicleStatus {
  VehicleStatus._();
  static const active = 'active';
  static const inactive = 'inactive';
}

/// Day-to-day state of a vehicle (separate from the active/inactive switch).
/// Must stay in sync with firestore.rules.
class VehicleAvailability {
  VehicleAvailability._();
  static const available = 'available';

  /// Set automatically while the vehicle is on an accepted booking.
  static const onTrip = 'on_trip';
  static const maintenance = 'maintenance';

  /// Admin only.
  static const suspended = 'suspended';

  /// Set by the app while an insurance, permit or fitness paper is expired;
  /// lifted by renewing it or by an admin override.
  static const docExpired = 'doc_expired';

  static const all = [available, onTrip, maintenance, suspended, docExpired];
}

/// Compliance papers tracked per vehicle (text only, never uploaded).
class VehicleDocKind {
  VehicleDocKind._();
  static const insurance = 'insurance';
  static const puc = 'puc';
  static const fitness = 'fitness';
  static const permit = 'permit';

  static const all = [insurance, puc, fitness, permit];

  /// Papers that stop a vehicle taking bookings when expired (PUC only warns).
  static const blocking = [insurance, permit, fitness];
}

/// Fuel and body type of a vehicle (optional profile fields). Keep in sync
/// with firestore.rules.
class FuelType {
  FuelType._();
  static const all = ['diesel', 'petrol', 'cng', 'electric', 'lpg'];
}

class BodyType {
  BodyType._();
  static const all = ['open', 'closed', 'container', 'flatbed', 'tanker', 'tipper', 'refrigerated', 'other'];
}

/// Preferred pickup window. Must stay in sync with firestore.rules.
class PickupSlot {
  PickupSlot._();
  static const any = 'any';
  static const morning = 'morning';
  static const midday = 'midday';
  static const afternoon = 'afternoon';
  static const evening = 'evening';

  static const all = [any, morning, midday, afternoon, evening];

  /// Hour (24 h) at which a slot starts. Reminders count from here; `any`
  /// is treated as 9 in the morning.
  static int startHour(String slot) => switch (slot) {
        morning => 8,
        midday => 12,
        afternoon => 15,
        evening => 18,
        _ => 9,
      };
}

/// What the customer is booking. Must stay in sync with firestore.rules.
class BookingType {
  BookingType._();
  static const freight = 'freight';
  static const rental = 'rental';
  static const movers = 'movers';

  static const all = [freight, rental, movers];
}

/// Most pickup and drop points a load can have (each side).
const int maxStopsPerSide = 3;

class LoadStatus {
  LoadStatus._();
  static const open = 'open';
  static const matched = 'matched';
  static const closed = 'closed';
}

class BookingStatus {
  BookingStatus._();
  static const accepted = 'accepted';
  static const driverArriving = 'driver_arriving';
  static const loading = 'loading';

  /// Reached only with the customer's pickup OTP.
  static const pickedUp = 'picked_up';
  static const inTransit = 'in_transit';
  static const unloading = 'unloading';

  /// Reached only with the customer's delivery OTP.
  static const delivered = 'delivered';

  /// Driver backed out before pickup; the load reopens. Not part of [flow].
  static const cancelled = 'cancelled';

  /// Ordered lifecycle of a booking. Must stay in sync with firestore.rules.
  static const flow = [accepted, driverArriving, loading, pickedUp, inTransit, unloading, delivered];

  /// Steps that need an OTP from the customer.
  static bool needsOtp(String next) => next == pickedUp || next == delivered;

  /// The driver may back out until loading starts.
  static const driverCancellable = [accepted, driverArriving];

  /// Returns the status that follows [status], or null when the trip is done.
  static String? next(String status) {
    final i = flow.indexOf(status);
    if (i < 0 || i == flow.length - 1) return null;
    return flow[i + 1];
  }
}
