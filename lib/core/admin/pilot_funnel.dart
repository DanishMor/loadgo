/// One step of a funnel: how many people got this far.
class FunnelStep {
  /// Translation key of the step name.
  final String key;
  final int count;
  const FunnelStep(this.key, this.count);
}

/// Where people stop on the way to their first delivery (MASTER-5 Task 39):
/// sign-up, profile, documents (drivers), first load or first trip, first
/// delivery. Counts people (not records) from the newest users, loads and
/// bookings an admin loaded; a step can never be higher than the one before it.
class PilotFunnel {
  final List<FunnelStep> customers;
  final List<FunnelStep> drivers;
  final List<FunnelStep> transporters;

  const PilotFunnel(this.customers, this.drivers, this.transporters);

  /// [users]: (uid, document data). [loadShippers]: shipper ids of loads.
  /// [bookings]: (customerId, driverId, fleetOwnerId, status).
  factory PilotFunnel.compute({
    required Iterable<(String, Map<String, dynamic>)> users,
    required Iterable<String> loadShippers,
    required Iterable<({String customerId, String driverId, String fleetOwnerId, String status})> bookings,
  }) {
    final shippers = loadShippers.toSet();
    final customerTrips = <String>{}, customerDelivered = <String>{};
    final driverTrips = <String>{}, driverDelivered = <String>{};
    final fleetTrips = <String>{}, fleetDelivered = <String>{};
    for (final b in bookings) {
      if (b.status == 'cancelled') continue;
      final done = b.status == 'delivered';
      customerTrips.add(b.customerId);
      driverTrips.add(b.driverId);
      if (b.fleetOwnerId.isNotEmpty) fleetTrips.add(b.fleetOwnerId);
      if (done) {
        customerDelivered.add(b.customerId);
        driverDelivered.add(b.driverId);
        if (b.fleetOwnerId.isNotEmpty) fleetDelivered.add(b.fleetOwnerId);
      }
    }

    String roleOf(Map<String, dynamic> d) => '${d['role'] ?? d['selectedRole'] ?? ''}';
    final cs = [for (final (id, d) in users) if (roleOf(d) == 'customer') (id, d)];
    final ds = [for (final (id, d) in users) if (roleOf(d) == 'driver') (id, d)];
    final fs = [for (final (id, d) in users) if (roleOf(d) == 'fleet') (id, d)];

    // Each step keeps only those who also passed the one before.
    List<FunnelStep> chain(List<(String, Map<String, dynamic>)> start, List<(String, bool Function(String, Map<String, dynamic>))> steps) {
      var cur = start;
      final out = <FunnelStep>[];
      for (final (key, test) in steps) {
        cur = [for (final u in cur) if (test(u.$1, u.$2)) u];
        out.add(FunnelStep(key, cur.length));
      }
      return out;
    }

    final customers = [FunnelStep('pfSignedUp', cs.length), ...chain(cs, [
      ('pfProfile', (id, d) => d['profileComplete'] == true),
      ('pfFirstLoad', (id, d) => shippers.contains(id)),
      ('pfFirstDelivery', (id, d) => customerDelivered.contains(id)),
    ])];
    final drivers = [FunnelStep('pfSignedUp', ds.length), ...chain(ds, [
      ('pfProfile', (id, d) => d['driverProfileComplete'] == true),
      ('pfDocuments', (id, d) => d['kycComplete'] == true),
      ('pfVerified', (id, d) => d['verified'] == true),
      ('pfFirstTrip', (id, d) => driverTrips.contains(id)),
      ('pfFirstDelivery', (id, d) => driverDelivered.contains(id)),
    ])];
    final transporters = [FunnelStep('pfSignedUp', fs.length), ...chain(fs, [
      ('pfProfile', (id, d) => d['fleetProfileComplete'] == true),
      ('pfFirstTrip', (id, d) => fleetTrips.contains(id)),
      ('pfFirstDelivery', (id, d) => fleetDelivered.contains(id)),
    ])];
    // The customers' "signed up" is the start; their chain begins from it.
    return PilotFunnel(customers, drivers, transporters);
  }

  /// The step with the biggest share lost from the one before it, as
  /// (from key, to key, lost count); null when nothing was lost.
  static (String, String, int)? biggestDrop(List<FunnelStep> steps) {
    (String, String, int)? best;
    for (var i = 1; i < steps.length; i++) {
      final lost = steps[i - 1].count - steps[i].count;
      if (lost > 0 && (best == null || lost > best.$3)) best = (steps[i - 1].key, steps[i].key, lost);
    }
    return best;
  }
}
