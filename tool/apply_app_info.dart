// Writes the app name and tagline from lib/core/app_info.dart into every file
// that cannot read a Dart constant: the hosting pages, the Android and iOS
// label, the web title and the web manifest.
//
//   dart run tool/apply_app_info.dart           write the files
//   dart run tool/apply_app_info.dart --check   list files that are out of date
//
// docs/NAMING.md explains the whole rename. A test (test/naming_test.dart)
// runs [render] and fails when a file is out of date.
import 'dart:convert';
import 'dart:io';

import 'package:transport_app/core/app_info.dart';

String _tokens(String text) => text
    .replaceAll('{{APP_NAME}}', AppInfo.name)
    .replaceAll('{{APP_TAGLINE}}', AppInfo.tagline)
    .replaceAll('{{APP_DESCRIPTION}}', AppInfo.description);

String _xml(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

String _must(String text, RegExp pattern, String Function(Match) replace, String file) {
  if (!pattern.hasMatch(text)) throw StateError('$file: the pattern $pattern was not found');
  return text.replaceFirstMapped(pattern, replace);
}

/// path (relative to [root]) -> the text that file must have.
Map<String, String> render(String root) {
  String read(String p) => File('$root/$p').readAsStringSync();
  final out = <String, String>{};

  // Hosting pages: tool/templates/hosting/x.html -> hosting/x.html
  for (final f in Directory('$root/tool/templates/hosting').listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    out['hosting/$name'] = _tokens(f.readAsStringSync());
  }

  // Android label.
  out['android/app/src/main/AndroidManifest.xml'] = _must(
    read('android/app/src/main/AndroidManifest.xml'),
    RegExp(r'android:label="[^"]*"'),
    (_) => 'android:label="${_xml(AppInfo.name)}"',
    'AndroidManifest.xml',
  );

  // iOS: display name, bundle name and the permission sentences that carry the name.
  var plist = read('ios/Runner/Info.plist');
  String key(String k, String value) => '<key>$k</key>\n\t\t<string>${_xml(value)}</string>';
  for (final e in {
    'CFBundleDisplayName': AppInfo.name,
    'CFBundleName': AppInfo.name,
    'NSLocationWhenInUseUsageDescription': '${AppInfo.name} shares your live location with the customer while a trip is in transit.',
    'NSPhotoLibraryUsageDescription': '${AppInfo.name} needs photo access to upload your vehicle RC document.',
    'NSCameraUsageDescription': '${AppInfo.name} needs camera access to photograph your vehicle RC document.',
    'NSMicrophoneUsageDescription': '${AppInfo.name} uses the microphone only during a call with your customer, driver or transporter. Nothing is recorded.',
  }.entries) {
    final pattern = RegExp('<key>${e.key}</key>\\s*<string>[^<]*</string>');
    if (pattern.hasMatch(plist)) {
      plist = plist.replaceFirst(pattern, key(e.key, e.value));
    } else {
      plist = plist.replaceFirst('<dict>\n', '<dict>\n\t\t${key(e.key, e.value)}\n');
    }
  }
  out['ios/Runner/Info.plist'] = plist;

  // Web: title, description, iOS web-app title.
  var html = read('web/index.html');
  html = _must(html, RegExp(r'<title>[^<]*</title>'), (_) => '<title>${_xml(AppInfo.name)}</title>', 'web/index.html');
  html = _must(html, RegExp(r'<meta name="description" content="[^"]*">'), (_) => '<meta name="description" content="${_xml(AppInfo.description)}">', 'web/index.html');
  html = _must(html, RegExp(r'<meta name="apple-mobile-web-app-title" content="[^"]*">'), (_) => '<meta name="apple-mobile-web-app-title" content="${_xml(AppInfo.name)}">', 'web/index.html');
  out['web/index.html'] = html;

  // Web manifest.
  var manifest = read('web/manifest.json');
  manifest = _must(manifest, RegExp(r'"name": "[^"]*"'), (_) => '"name": ${jsonEncode('${AppInfo.name} - ${AppInfo.tagline}')}', 'web/manifest.json');
  manifest = _must(manifest, RegExp(r'"short_name": "[^"]*"'), (_) => '"short_name": ${jsonEncode(AppInfo.name)}', 'web/manifest.json');
  manifest = _must(manifest, RegExp(r'"description": "[^"]*"'), (_) => '"description": ${jsonEncode(AppInfo.description)}', 'web/manifest.json');
  out['web/manifest.json'] = manifest;

  return out;
}

/// Paths whose current content differs from what [render] produces.
List<String> outOfDate(String root) => [
      for (final e in render(root).entries)
        if (!File('$root/${e.key}').existsSync() || File('$root/${e.key}').readAsStringSync().replaceAll('\r\n', '\n') != e.value.replaceAll('\r\n', '\n')) e.key,
    ];

void main(List<String> args) {
  final root = Directory.current.path;
  if (args.contains('--check')) {
    final stale = outOfDate(root);
    if (stale.isEmpty) {
      stdout.writeln('All files match lib/core/app_info.dart.');
    } else {
      stdout.writeln('Out of date:\n${stale.map((p) => '  $p').join('\n')}\nRun: dart run tool/apply_app_info.dart');
      exitCode = 1;
    }
    return;
  }
  var written = 0;
  for (final e in render(root).entries) {
    final f = File('$root/${e.key}');
    if (!f.existsSync() || f.readAsStringSync() != e.value) {
      f.writeAsStringSync(e.value);
      stdout.writeln('updated ${e.key}');
      written++;
    }
  }
  stdout.writeln(written == 0 ? 'Nothing to change.' : '$written file(s) updated.');
}
