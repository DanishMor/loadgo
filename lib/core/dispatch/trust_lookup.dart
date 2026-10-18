import '../trust/public_trust.dart';

/// Reads a driver's public trust summary (rating, trips, verified) once and remembers it for the session. The summary
/// is written by the server (`public_trust/{uid}`, switch `serverTrust`); without it every answer is null and the bid
/// shows no rating, which is the honest thing to show.
class TrustLookup {
  TrustLookup._();

  static final Map<String, Future<PublicTrust?>> _cache = {};

  /// Tests replace how the summary is read.
  static Future<PublicTrust?> Function(String uid) reader = _read;

  static Future<PublicTrust?> _read(String uid) async {
    try {
      return await PublicTrust.watch(uid).first.timeout(const Duration(seconds: 4));
    } catch (_) {
      return null;
    }
  }

  static Future<PublicTrust?> of(String uid) => _cache.putIfAbsent(uid, () => reader(uid));

  static void reset() {
    _cache.clear();
    reader = _read;
  }
}
