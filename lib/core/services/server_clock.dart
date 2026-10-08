/// "Now" as the server sees it, for client-side checks (a scheduled pickup, a
/// document that expired, an inspection grant that ended) when the phone's own
/// clock may be wrong (MASTER-5 Task 20).
///
/// Nothing here is trusted by the rules: they compare against `request.time`
/// on the server. This only keeps what the screen shows and the pre-checks in
/// line with that, e.g. a grant is not shown as valid for days because the
/// phone is set in the past.
///
/// The offset is learned from a document the server stamped just after this
/// phone wrote it (a chat message the app sent: the server time arrives when
/// the write is acknowledged, so it is the server's "now" give or take the
/// network delay). Without a sample the phone's clock is used as it is.
class ServerClock {
  ServerClock._();

  static Duration _offset = Duration.zero;
  static bool _known = false;

  /// Overridable in tests.
  static DateTime Function() deviceNow = DateTime.now;

  /// Server time minus device time; zero until a sample was seen.
  static Duration get offset => _offset;
  static bool get known => _known;

  /// The server's "now".
  static DateTime now() => deviceNow().add(_offset);

  /// A server-stamped time [serverTime] that arrived when the device clock read
  /// [receivedAt] (default: now). A small difference (under 2 seconds) is just
  /// network delay and is ignored so the offset does not jitter.
  static void observe(DateTime serverTime, {DateTime? receivedAt}) {
    final local = receivedAt ?? deviceNow();
    final diff = serverTime.difference(local);
    _offset = diff.abs() < const Duration(seconds: 2) ? Duration.zero : diff;
    _known = true;
  }

  /// How far the phone's clock is from the server's; false when it is more
  /// than [tolerance] off, so a screen can ask the person to fix the date.
  static bool deviceClockOk({Duration tolerance = const Duration(minutes: 5)}) => _offset.abs() <= tolerance;

  static void reset() {
    _offset = Duration.zero;
    _known = false;
    deviceNow = DateTime.now;
  }
}
