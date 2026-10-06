/// Remembers when something was last fetched, so repeat sign-ins and screen
/// opens inside [ttl] do not read the same Firestore document again.
class TtlCache {
  final Duration ttl;
  final DateTime Function() _now;
  DateTime? _at;

  TtlCache(this.ttl, {DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  bool get fresh => _at != null && _now().difference(_at!) < ttl;

  void markFetched() => _at = _now();

  void invalidate() => _at = null;

  /// Runs [fetch] unless the last run is still fresh (or [force]).
  /// A failed fetch does not mark the cache fresh, so the next call retries.
  Future<bool> run(Future<void> Function() fetch, {bool force = false}) async {
    if (!force && fresh) return false;
    await fetch();
    markFetched();
    return true;
  }
}
