/// Shared domain constants for vehicles, loads and bookings.
library;

const List<String> vehicleTypes = [
  'Bike',
  '3-Wheeler',
  'Mini',
  '14ft',
  '20ft',
  '32ft',
  'Container',
  'Trailer',
];

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

  /// Ordered lifecycle of a booking. Must stay in sync with firestore.rules.
  static const flow = [accepted, pickedUp, inTransit, delivered];

  /// Returns the status that follows [status], or null when the trip is done.
  static String? next(String status) {
    final i = flow.indexOf(status);
    if (i < 0 || i == flow.length - 1) return null;
    return flow[i + 1];
  }
}
