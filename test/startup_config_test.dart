import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/services/app_config.dart';
import 'package:transport_app/core/services/app_control_service.dart';

/// MASTER-6 Task 38: startup never depends on the network.
void main() {
  test('one config document failing does not stop the others or throw, and the next call retries', () async {
    var ok = 0, tries = 0;
    Future<void> good() async => ok++;
    Future<void> bad() async {
      tries++;
      throw StateError('offline');
    }

    await refreshAppConfig(force: true, loaders: [good, bad, good]);
    expect((ok, tries, configRefreshFailures), (2, 1, 1));
    await refreshAppConfig(loaders: [good, bad, good]); // not fresh after a failure: tries again
    expect((ok, tries), (4, 2));
    await refreshAppConfig(force: true, loaders: [good, good]);
    expect(configRefreshFailures, 0);
    await refreshAppConfig(loaders: [good, good]); // fresh now: nothing runs
    expect(ok, 6);
  });

  test('an app-control refresh that cannot reach Firebase leaves the app open (no maintenance, no forced update)', () async {
    AppControlService.reset();
    await AppControlService.refresh(); // no Firebase in tests: every read fails
    final c = AppControlService.notifier.value;
    expect((c.maintenance, c.minVersionCode), (false, 0));
  });

  test('Remote Config defaults are open', () {
    expect(AppControlService.remoteDefaults['maintenance'], false);
    expect(AppControlService.remoteDefaults['min_version_code'], 0);
  });
}
