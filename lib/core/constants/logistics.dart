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

  static const all = [available, onTrip, maintenance, suspended];
}

/// Compliance papers tracked per vehicle (text only, never uploaded).
class VehicleDocKind {
  VehicleDocKind._();
  static const insurance = 'insurance';
  static const puc = 'puc';
  static const fitness = 'fitness';
  static const permit = 'permit';

  static const all = [insurance, puc, fitness, permit];
}

class LoadStatus {
  LoadStatus._();
  static const open = 'open';
  static const matched = 'matched';
  static const closed = 'closed';
}

class BookingStatus {
  BookingStatus._();
  static const accepted = 'accepted';
  static const pickedUp = 'picked_up';
  static const inTransit = 'in_transit';
  static const delivered = 'delivered';

  /// Driver backed out before pickup; the load reopens. Not part of [flow].
  static const cancelled = 'cancelled';

  /// Ordered lifecycle of a booking. Must stay in sync with firestore.rules.
  static const flow = [accepted, pickedUp, inTransit, delivered];

  /// Returns the status that follows [status], or null when the trip is done.
  static String? next(String status) {
    final i = flow.indexOf(status);
    if (i < 0 || i == flow.length - 1) return null;
    return flow[i + 1];
  }
}
