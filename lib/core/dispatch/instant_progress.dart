import 'dispatch_models.dart';

/// Where an instant load is in its search (U12): which wave is open, how far it reaches, how long
/// until the next wave, or that the last wave ran out with nobody taking the load ("stalled").
/// Time comes from the load's server `createdAt`, so a rebuilt screen shows the true state.
class InstantProgress {
  /// The wave that is open now (0-based).
  final int wave;

  /// How far this wave reaches, in km.
  final int reachKm;

  /// Seconds until the next wave opens, or until the search gives up in the last wave. 0 when stalled.
  final int secondsLeft;

  /// Length of the current stage in seconds (for the ring).
  final int stageSeconds;

  /// The last wave has run its accept time and nobody took the load.
  final bool stalled;

  /// How many waves exist.
  final int waves;

  const InstantProgress({required this.wave, required this.reachKm, required this.secondsLeft, required this.stageSeconds, required this.stalled, required this.waves});

  bool get inLastWave => wave == waves - 1;

  static InstantProgress at(DispatchConfig c, {required DateTime createdAt, required DateTime now, int boost = 0}) {
    final elapsed = now.difference(createdAt).inSeconds.clamp(0, 1 << 30);
    final n = c.ringsKm.length;
    int reach(int i) => c.ringsKm[(i + boost).clamp(0, n - 1)];
    final giveUp = c.ringDelaySeconds.last + c.acceptSeconds;
    var wave = 0;
    for (var i = 0; i < n; i++) {
      if (elapsed >= c.ringDelaySeconds[i]) wave = i;
    }
    final stalled = elapsed >= giveUp;
    final stageEnd = wave == n - 1 ? giveUp : c.ringDelaySeconds[wave + 1];
    final stageStart = c.ringDelaySeconds[wave];
    return InstantProgress(
      wave: wave,
      reachKm: reach(wave),
      secondsLeft: stalled ? 0 : stageEnd - elapsed,
      stageSeconds: stageEnd - stageStart,
      stalled: stalled,
      waves: n,
    );
  }
}

/// "Raise the price" for an instant load (U12): +5% or +10% on the customer's price in whole rupees,
/// rounded up, never above 300% of the fare estimate and never above the rules' ceiling.
class PriceBump {
  PriceBump._();

  static const options = [5, 10];
  static const ceilingRupees = 1000000000;

  /// The new price in rupees, or null when the bump is not allowed (no price, over the limit).
  /// [estimatePaise] is the fare estimate when the load has one.
  static int? bumped(num? budgetRupees, int percent, {int? estimatePaise}) {
    if (budgetRupees == null || budgetRupees <= 0 || !options.contains(percent)) return null;
    final base = budgetRupees.ceil();
    final next = (base * (100 + percent) + 99) ~/ 100;
    if (next <= base) return null;
    if (next > ceilingRupees) return null;
    if (estimatePaise != null && estimatePaise > 0 && next * 100 > estimatePaise * 3) return null;
    return next;
  }
}
