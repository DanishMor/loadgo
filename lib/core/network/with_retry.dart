import 'dart:async';

import '../errors/friendly_error.dart';

/// Runs a one-shot read with a timeout per try and a growing pause between
/// tries (400 ms, 800 ms, ...). Only transient failures (no network, timeout,
/// busy server) are retried; a permission or not-found error is thrown at once.
/// After the last try the last error is thrown.
Future<T> withRetry<T>(
  Future<T> Function() operation, {
  int attempts = 3,
  Duration timeout = const Duration(seconds: 10),
  Duration baseDelay = const Duration(milliseconds: 400),
  bool Function(Object error)? retryIf,
  Future<void> Function(Duration)? sleep,
}) async {
  assert(attempts >= 1);
  final wait = sleep ?? (d) => Future<void>.delayed(d);
  final shouldRetry = retryIf ?? FriendlyError.isTransient;
  for (var i = 1;; i++) {
    try {
      return await operation().timeout(timeout);
    } catch (e) {
      if (i >= attempts || !shouldRetry(e)) rethrow;
      await wait(baseDelay * (1 << (i - 1)));
    }
  }
}
