/// E24: what is waiting for staff right now, counted once per open (Refresh counts again). A count capped by a
/// query limit is shown as "50+" ([capped]); -1 means this staff role may not read that queue (shown as a dash).
class OpsQueues {
  final int kyc;
  final int photos;
  final int claims;
  final int tickets;
  final int sos;
  final int unfilledLoads;
  final int openLoads;
  final int runningTrips;

  /// Queues whose count hit its read limit (shown with a "+").
  final Set<String> capped;

  const OpsQueues({
    required this.kyc,
    required this.photos,
    required this.claims,
    required this.tickets,
    required this.sos,
    required this.unfilledLoads,
    required this.openLoads,
    required this.runningTrips,
    this.capped = const {},
  });

  /// The photo queue reads at most this many records (the rules allow list queries of 50).
  static const photoLimit = 50;

  /// Queue ids, most urgent first, with the staff area that may open each one (lib/core/admin/staff_roles.dart).
  static const order = [
    ('sos', 'adminSos'),
    ('unfilled', 'adminDispatch'),
    ('kyc', 'driverVerification'),
    ('photos', 'adminVehiclePhotos'),
    ('claims', 'adminDisputes'),
    ('tickets', 'adminTickets'),
  ];

  int count(String id) => switch (id) {
        'sos' => sos,
        'unfilled' => unfilledLoads,
        'kyc' => kyc,
        'photos' => photos,
        'claims' => claims,
        'tickets' => tickets,
        _ => 0,
      };

  String label(String id) => count(id) < 0 ? '–' : capped.contains(id) ? '${count(id)}+' : '${count(id)}';

  /// SOS or a load waiting too long needs someone at once.
  bool get urgent => sos > 0 || unfilledLoads > 0;

  /// Anything at all waiting in a queue this role can read.
  bool get anyWaiting => [for (final (id, _) in order) count(id)].any((n) => n > 0);
}
