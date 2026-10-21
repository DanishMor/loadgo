import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Z16: tool/change_package_id.ps1 on a COPY of the repo (never on the real one).
/// These need Windows PowerShell 5.1 (the owner's laptop); on Linux CI they are skipped.
final _skipNoPowerShell = Platform.isWindows ? null : 'needs Windows PowerShell';

void main() {
  const oldId = 'com.example.transport_app';
  const newId = 'in.load20.app';
  late Directory copy;

  Directory makeCopy() {
    final dir = Directory.systemTemp.createTempSync('pkgid');
    final listed = Process.runSync('git', ['ls-files', 'android', 'lib', 'linux', 'test', 'docs', 'tool']).stdout.toString().split('\n').where((l) => l.trim().isNotEmpty);
    for (final rel in listed) {
      final src = File(rel);
      if (!src.existsSync()) continue;
      final dst = File('${dir.path}/$rel')..createSync(recursive: true);
      dst.writeAsBytesSync(src.readAsBytesSync());
    }
    return dir;
  }

  ProcessResult run(List<String> extra) =>
      Process.runSync('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tool/change_package_id.ps1', '-NewId', newId, '-Root', copy.path, ...extra]);
  String read(String rel) => File('${copy.path}/$rel').readAsStringSync();

  setUpAll(() {
    if (Platform.isWindows) copy = makeCopy();
  });
  tearDownAll(() {
    if (Platform.isWindows) copy.deleteSync(recursive: true);
  });

  test('dry run lists the files and writes nothing; bad ids are refused', skip: _skipNoPowerShell, () {
    final r = run([]);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect('${r.stdout}', contains('DRY RUN'));
    expect('${r.stdout}', contains(r'android\gradle.properties'));
    expect(read('android/gradle.properties'), contains('loadgo.applicationId=$oldId'));
    final bad = Process.runSync('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tool/change_package_id.ps1', '-NewId', 'com.example.x', '-Root', copy.path]);
    expect(bad.exitCode, isNot(0));
  });

  test('-Apply changes the id, keeps the Kotlin namespace, prints the Firebase steps and the uninstall warning', skip: _skipNoPowerShell, () {
    final r = run(['-Apply']);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(read('android/gradle.properties'), contains('loadgo.applicationId=$newId'));
    expect(read('lib/core/widgets/app_control_gate.dart'), contains('id=$newId'));
    expect(read('linux/CMakeLists.txt'), contains('"$newId"'));
    expect(read('android/app/build.gradle.kts'), contains('namespace = "$oldId"'));
    expect(File('${copy.path}/android/app/src/main/kotlin/com/example/transport_app/MainActivity.kt').existsSync(), isTrue);
    expect(read('test/android_release_test.dart'), contains('loadgo.applicationId=$newId'));
    final out = '${r.stdout}';
    expect(out, contains('google-services.json'));
    expect(out, contains('SHA-256'));
    expect(out, contains('uninstall'));
  });

  test('-MoveNamespace also moves the Kotlin package folder and the package line', skip: _skipNoPowerShell, () {
    copy.deleteSync(recursive: true);
    copy = makeCopy();
    final r = run(['-Apply', '-MoveNamespace']);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(read('android/app/build.gradle.kts'), contains('namespace = "$newId"'));
    expect(File('${copy.path}/android/app/src/main/kotlin/in/load20/app/MainActivity.kt').existsSync(), isTrue);
    expect(read('android/app/src/main/kotlin/in/load20/app/MainActivity.kt'), startsWith('package $newId'));
    expect(Directory('${copy.path}/android/app/src/main/kotlin/com').existsSync(), isFalse);
  });

  test('the real repo is untouched by these tests', () {
    expect(File('android/gradle.properties').readAsStringSync(), contains('loadgo.applicationId=$oldId'));
  });
}
