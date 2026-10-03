import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Whether the device has any network connection. Optimistic (true) until
/// the platform says otherwise; tests set [online] directly.
class ConnectivityService {
  ConnectivityService._();

  static final ValueNotifier<bool> online = ValueNotifier(true);
  static StreamSubscription<List<ConnectivityResult>>? _sub;

  static bool _hasNetwork(List<ConnectivityResult> r) => r.any((e) => e != ConnectivityResult.none);

  /// Start tracking; call once at app start. Failures leave [online] true.
  static Future<void> start() async {
    try {
      final connectivity = Connectivity();
      online.value = _hasNetwork(await connectivity.checkConnectivity());
      _sub ??= connectivity.onConnectivityChanged.listen((r) => online.value = _hasNetwork(r));
    } catch (e) {
      debugPrint('Connectivity tracking unavailable: $e');
    }
  }
}
