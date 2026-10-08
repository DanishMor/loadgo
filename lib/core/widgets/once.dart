/// Lets an action run again only after the last run has finished, so a
/// double tap on Save cannot write twice (MASTER-5 Task 16).
///
///     final _once = Once();
///     onPressed: () => _once.run(_save)
class Once {
  bool _running = false;

  bool get running => _running;

  /// Runs [action] unless a run is still going; returns false when it skipped.
  Future<bool> run(Future<void> Function() action) async {
    if (_running) return false;
    _running = true;
    try {
      await action();
      return true;
    } finally {
      _running = false;
    }
  }
}
