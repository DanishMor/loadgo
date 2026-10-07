import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Turns any error into the translation key of a short, honest explanation.
/// Raw exception text is never shown to people.
class FriendlyError {
  FriendlyError._();

  static const network = 'errorNetwork';
  static const noAccess = 'errorNoAccess';
  static const session = 'errorSession';
  static const notFound = 'errorNotFound';
  static const busy = 'errorBusy';
  static const conflict = 'errorConflict';
  static const generic = 'errorGeneric';

  static String of(Object? error) {
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' => noAccess,
        'unauthenticated' || 'user-token-expired' || 'requires-recent-login' || 'user-disabled' => session,
        'unavailable' || 'deadline-exceeded' || 'network-request-failed' => network,
        'not-found' => notFound,
        'resource-exhausted' || 'aborted' || 'too-many-requests' => busy,
        'already-exists' || 'failed-precondition' => conflict,
        _ => generic,
      };
    }
    if (error is TimeoutException) return network;
    // SocketException lives in dart:io, which the web build cannot import.
    if (error != null && error.runtimeType.toString() == 'SocketException') return network;
    return generic;
  }

  /// True for failures that may go away when tried again.
  static bool isTransient(Object? error) {
    final k = of(error);
    return k == network || k == busy;
  }
}
