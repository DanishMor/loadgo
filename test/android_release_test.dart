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
      'ACCESS_FINE_LOCATION', 'ACCESS_COARSE_LOCATION', 'POST_NOTIFICATIONS', 'RECORD_AUDIO',
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
}
