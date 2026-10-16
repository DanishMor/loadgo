import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/services/app_check_setup.dart';

void main() {
  tearDown(() => AppCheckSetup.activator = AppCheckSetup.activator);

  test('provider: debug builds use the debug provider, release Android uses Play Integrity, the web and others none', () {
    String p({required bool debug, bool web = false, TargetPlatform t = TargetPlatform.android}) =>
        AppCheckSetup.providerFor(debug: debug, web: web, platform: t);
    expect(p(debug: true), 'debug');
    expect(p(debug: false), 'playIntegrity');
    expect(p(debug: false, web: true), 'none');
    expect(p(debug: true, web: true), 'none');
    expect(p(debug: false, t: TargetPlatform.iOS), 'none');
    expect(p(debug: false, t: TargetPlatform.windows), 'none');
  });

  test('asleep unless the build asks: nothing is started by default', () async {
    var started = 0;
    AppCheckSetup.activator = (_) async => started++;
    expect(AppCheckSetup.mode, 'off');
    expect(await AppCheckSetup.start(platform: TargetPlatform.android, debug: false, web: false), isNull);
    expect(await AppCheckSetup.start(buildMode: 'off', platform: TargetPlatform.android, debug: false, web: false), isNull);
    expect(started, 0);
  });

  test('when asked it starts with the right provider; a failure never throws', () async {
    final used = <String>[];
    AppCheckSetup.activator = (p) async => used.add(p);
    expect(await AppCheckSetup.start(buildMode: 'on', platform: TargetPlatform.android, debug: true, web: false), 'debug');
    expect(await AppCheckSetup.start(buildMode: 'on', platform: TargetPlatform.android, debug: false, web: false), 'playIntegrity');
    expect(used, ['debug', 'playIntegrity']);
    expect(await AppCheckSetup.start(buildMode: 'on', platform: TargetPlatform.android, debug: false, web: true), isNull);
    AppCheckSetup.activator = (_) async => throw StateError('no play services');
    expect(await AppCheckSetup.start(buildMode: 'on', platform: TargetPlatform.android, debug: false, web: false), isNull);
  });

  test('the secret-free rule: no debug token or key is written in the repository files', () {
    for (final f in ['lib/core/services/app_check_setup.dart', 'docs/APP_CHECK.md']) {
      final text = File(f).readAsStringSync();
      expect(RegExp(r'[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}').hasMatch(text), isFalse, reason: f);
    }
  });
}
