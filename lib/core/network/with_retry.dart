import 'dart:async';
import 'dart:math' as math;

import '../errors/friendly_error.dart';

/// Runs a one-shot read with a timeout per try and a growing pause between
/// tries (400 ms, 800 ms, ...). Only transient failures (no network, timeout,
/// busy server) are retried; a permission or not-found error is thrown at once.
/// After the last try the last error is thrown.
///
/// Part 5 (H19): every pause is spread by +-[jitter] (a quarter by default), so many phones that lost the network at
/// the same moment do not all ask again at the same moment. Pass jitter: 0 for exact pauses.
Future<T> withRetry<T>(
  Future<T> Function() operation, {
  int attempts = 3,
  Duration timeout = const Duration(seconds: 10),
  Duration baseDelay = const Duration(milliseconds: 400),
  bool Function(Object error)? retryIf,
  Future<void> Function(Duration)? sleep,
  double jitter = 0.25,
  math.Random? random,
}) async {
  assert(attempts >= 1);
  final wait = sleep ?? (d) => Future<void>.delayed(d);
  final shouldRetry = retryIf ?? FriendlyError.isTransient;
  final rnd = random ?? math.Random();
  for (var i = 1;; i++) {
    try {
      return await operation().timeout(timeout);
    } catch (e) {
      if (i >= attempts || !shouldRetry(e)) rethrow;
      final pause = baseDelay * (1 << (i - 1));
      await wait(jitter <= 0 ? pause : pause * (1 - jitter + 2 * jitter * rnd.nextDouble()));
    }
  }
}
