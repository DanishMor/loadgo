import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// MASTER-6 Task 43: the Android release set-up stays safe.
void main() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('the store id is read from one property, with the placeholder as default', () {
    expect(gradle.contains('findProperty("loadgo.applicationId")'), isTrue);
    expect(gradle.contains('applicationId = loadgoApplicationId'), isTrue);
    expect(File('android/gradle.properties').readAsStringSync().contains('loadgo.applicationId=com.example.transport_app'), isTrue);
    // No second place that spells the id out as the applicationId.
    expect(RegExp(r'applicationId\s*=\s*"').hasMatch(gradle), isFalse);
  });

  test('release signing comes from a git-ignored key.properties; no secret is committed', () {
    expect(gradle.contains('key.properties'), isTrue);
    final ignore = File('.gitignore').readAsStringSync();
    expect(ignore.contains('android/key.properties'), isTrue);
    expect(ignore.contains('*.jks'), isTrue);
    expect(gradle.contains('storePassword = "'), isFalse);
    expect(File('android/key.properties').existsSync(), isFalse);
  });

  test('only the documented permissions are declared', () {
    const allowed = {
      'ACCESS_FINE_LOCATION', 'ACCESS_COARSE_LOCATION', 'POST_NOTIFICATIONS', 'RECORD_AUDIO', 'USE_BIOMETRIC', 'FOREGROUND_SERVICE', 'FOREGROUND_SERVICE_LOCATION',
      'INTERNET', 'MODIFY_AUDIO_SETTINGS', 'ACCESS_NETWORK_STATE', 'CHANGE_NETWORK_STATE',
    };
    final found = RegExp(r'uses-permission android:name="android\.permission\.(\w+)"').allMatches(manifest).map((m) => m.group(1)!).toSet();
    expect(found.difference(allowed), isEmpty, reason: 'a new permission needs a reason in docs/ANDROID_RELEASE.md and Play data safety');
    final doc = File('docs/ANDROID_RELEASE.md').readAsStringSync();
    for (final p in found) {
      expect(doc.contains(p), isTrue, reason: '$p is not in docs/ANDROID_RELEASE.md');
    }
  });

  test('app stays private: no backup, no cleartext traffic', () {
    expect(manifest.contains('android:allowBackup="false"'), isTrue);
    expect(manifest.contains('android:usesCleartextTraffic="false"'), isTrue);
  });

  // H9: the network security config says the same in a second place, trusts system CAs only in release, and nothing is debuggable or free to export by accident.
  test('network security config: no cleartext, system CAs only (user CAs only in debug)', () {
    expect(manifest.contains('android:networkSecurityConfig="@xml/network_security_config"'), isTrue);
    final nsc = File('android/app/src/main/res/xml/network_security_config.xml').readAsStringSync();
    expect(nsc.contains('<base-config cleartextTrafficPermitted="false">'), isTrue);
    final base = nsc.substring(nsc.indexOf('<base-config'), nsc.indexOf('</base-config>'));
    expect(base.contains('src="user"'), isFalse);
    expect(nsc.contains('cleartextTrafficPermitted="true"'), isFalse);
    expect(nsc.contains('<pin-set'), isFalse, reason: 'pinning is a decision in docs/SECURITY_DECISIONS.md');
  });

  test('only the launcher activity is exported and the app is not debuggable', () {
    expect(manifest.contains('android:debuggable'), isFalse);
    final exported = RegExp(r'android:exported="true"').allMatches(manifest).length;
    expect(exported, 1, reason: 'a new exported component needs a line in docs/THREAT_MODEL.md');
    expect(manifest.contains('android:name=".MainActivity"'), isTrue);
  });

  test('the share-link filter is HTTPS, our host, the /load/ prefix only', () {
    final filters = RegExp(r'<data android:scheme="([^"]+)" android:host="([^"]+)" android:pathPrefix="([^"]+)"').allMatches(manifest).toList();
    expect(filters, hasLength(1));
    expect(filters.single.group(1), 'https');
    expect(filters.single.group(3), '/load/');
  });
}
