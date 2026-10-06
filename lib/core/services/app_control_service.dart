import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app_control/app_control.dart';
import '../app_info.dart';
import 'backend.dart';

/// Loads [AppControl] from Remote Config with `config/app` as fallback and
/// keeps the latest value in [notifier]. Defaults never block the app.
class AppControlService {
  AppControlService._();

  static final ValueNotifier<AppControl> notifier = ValueNotifier(AppControl.open);
  static const fetchInterval = Duration(hours: 1);

  /// Remote Config defaults (also listed in docs/FIREBASE_SETUP_2.md).
  static const remoteDefaults = <String, Object>{
    'min_version_code': 0,
    'maintenance': false,
    'maintenance_message': '',
    'feature_flags': '{}',
  };

  static int _currentCode = VersionGate.codeOf(appVersion);
  static int get currentCode => _currentCode;

  static Future<void> refresh() async {
    var control = AppControl.open;
    try {
      final snap = await Backend.db.collection('config').doc('app').get();
      control = AppControl.fromMap(snap.data());
    } catch (_) {}
    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: fetchInterval,
      ));
      await rc.setDefaults(remoteDefaults);
      await rc.fetchAndActivate();
      control = fromRemote(
        {for (final k in remoteDefaults.keys) k: rc.getValue(k)},
        control,
      );
    } catch (_) {}
    try {
      final info = await PackageInfo.fromPlatform();
      _currentCode = int.tryParse(info.buildNumber) ?? _currentCode;
    } catch (_) {}
    apply(control);
  }

  /// Remote values that are still the default do not override the fallback.
  static AppControl fromRemote(Map<String, RemoteConfigValue> v, AppControl fallback) {
    bool remote(String k) => v[k]?.source == ValueSource.valueRemote;
    final r = AppControl(
      minVersionCode: v['min_version_code']?.asInt() ?? 0,
      maintenance: v['maintenance']?.asBool() ?? false,
      maintenanceMessage: v['maintenance_message']?.asString() ?? '',
      flags: AppControl.parseFlags(v['feature_flags']?.asString()),
    );
    return r.overlay(
      fallback,
      hasMin: remote('min_version_code'),
      hasMaintenance: remote('maintenance'),
      hasMessage: remote('maintenance_message'),
    );
  }

  static void apply(AppControl c) {
    FeatureFlags.set(c.flags);
    notifier.value = c;
  }

  @visibleForTesting
  static void reset({int code = 1}) {
    _currentCode = code;
    FeatureFlags.set(const {});
    notifier.value = AppControl.open;
  }
}
