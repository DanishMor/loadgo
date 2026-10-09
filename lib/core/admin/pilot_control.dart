/// Numbers for the pilot control room (MASTER-6 Task 3).
class PilotControl {
  final int signupsToday;
  final int driversSharing;
  final int openLoads;
  final int unfilledLoads;
  final int runningTrips;
  final int openSos;
  final int openTickets;

  const PilotControl({
    this.signupsToday = 0,
    this.driversSharing = 0,
    this.openLoads = 0,
    this.unfilledLoads = 0,
    this.runningTrips = 0,
    this.openSos = 0,
    this.openTickets = 0,
  });

  /// A load nobody has taken after this many minutes counts as unfilled.
  static const unfilledAfterMinutes = 30;

  /// How many open loads are read to find the unfilled ones.
  static const sampleLimit = 300;

  /// Start of "today" for the sign-up count: midnight of [now] on the
  /// server-corrected clock.
  static DateTime dayStart(DateTime now) => DateTime(now.year, now.month, now.day);

  /// Loads in [createdAt] older than [unfilledAfterMinutes] at [now]; a load
  /// with no time yet (just written) is not counted.
  static int unfilled(Iterable<DateTime?> createdAt, DateTime now) =>
      createdAt.where((t) => t != null && now.difference(t).inMinutes >= unfilledAfterMinutes).length;

  /// Anything that needs a person right now.
  bool get needsAttention => openSos > 0 || unfilledLoads > 0;
}
