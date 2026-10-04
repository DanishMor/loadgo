import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Enforces docs/ARCHITECTURE.md:
/// - nothing imports lib/main.dart
/// - customer/, driver/ and admin/ never import each other
/// - core/ never imports auth/, customer/, driver/ or admin/
/// - the legacy lib/features/ folder is gone
///
/// [findViolations] works on a map of path -> source, so the rules themselves
/// are tested below with deliberately broken input.

final _import = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true);

const _roles = ['customer', 'driver', 'admin', 'fleet'];

/// The lib/ sub-folder of [path] ("lib/customer/x.dart" -> "customer"), or
/// null for files directly in lib/ and for files outside lib/.
String? _area(String path) {
  final parts = path.split('/');
  if (parts.length < 3 || parts.first != 'lib') return null;
  return parts[1];
}

String? _resolve(String from, String target) {
  if (target.startsWith('package:transport_app/')) return 'lib/${target.substring('package:transport_app/'.length)}';
  if (target.startsWith('package:') || target.startsWith('dart:')) return null;
  return Uri.parse(from).resolve(target).toString();
}

List<String> findViolations(Map<String, String> sources) {
  final out = <String>[];
  sources.forEach((path, source) {
    final area = _area(path);
    for (final m in _import.allMatches(source)) {
      final to = _resolve(path, m.group(1)!);
      if (to == null) continue;
      final toArea = _area(to);
      if (to == 'lib/main.dart') out.add('$path imports main.dart');
      if (area != null && _roles.contains(area) && toArea != area && _roles.contains(toArea)) {
        out.add('$path ($area) imports $to ($toArea)');
      }
      if (area == 'core' && toArea != null && toArea != 'core') out.add('$path (core) imports $to ($toArea)');
    }
  });
  return out;
}

Map<String, String> _readAll(String dir) => {
      for (final f in Directory(dir).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')))
        f.path.replaceAll('\\', '/').replaceFirst(RegExp(r'^.*?/(?=(lib|test)/)'), ''): f.readAsStringSync(),
    };

void main() {
  test('the real code base follows the structure rules', () {
    final sources = {..._readAll('lib'), ..._readAll('test')}..remove('test/structure_test.dart');
    expect(sources.keys.where((k) => k.startsWith('lib/')).length, greaterThan(100), reason: 'the scan must really see lib/');
    expect(sources.keys, contains('lib/main.dart'));
    expect(findViolations(sources), isEmpty);
  });

  test('lib/features is gone', () {
    expect(Directory('lib/features').existsSync(), isFalse);
  });

  group('the checker catches violations', () {
    test('main.dart imports, relative and package form', () {
      expect(findViolations({'lib/core/a.dart': "import '../main.dart';"}), isNotEmpty);
      expect(findViolations({'lib/auth/a.dart': "import 'package:transport_app/main.dart';"}), isNotEmpty);
      expect(findViolations({'test/a_test.dart': "import 'package:transport_app/main.dart';"}), isNotEmpty);
      expect(findViolations({'lib/auth/a.dart': "import '../main.dart' show x;"}), isNotEmpty);
      expect(findViolations({'lib/auth/a.dart': "export '../main.dart';"}), isNotEmpty);
    });

    test('customer, driver and admin importing each other', () {
      expect(findViolations({'lib/customer/a.dart': "import '../driver/b.dart';"}), isNotEmpty);
      expect(findViolations({'lib/driver/a.dart': "import 'package:transport_app/customer/b.dart';"}), isNotEmpty);
      expect(findViolations({'lib/admin/a.dart': "import '../customer/sub/b.dart';"}), isNotEmpty);
      expect(findViolations({'lib/customer/sub/a.dart': "import '../../admin/b.dart';"}), isNotEmpty);
      expect(findViolations({'lib/driver/a.dart': "import '../admin/b.dart';"}), isNotEmpty);
    });

    test('core importing a role or auth folder', () {
      expect(findViolations({'lib/core/a.dart': "import '../customer/b.dart';"}), isNotEmpty);
      expect(findViolations({'lib/core/sub/a.dart': "import '../../auth/b.dart';"}), isNotEmpty);
    });

    test('allowed imports pass', () {
      expect(
        findViolations({
          'lib/customer/a.dart': "import '../core/x.dart';\nimport 'b.dart';\nimport '../auth/c.dart';\nimport 'package:flutter/material.dart';",
          'lib/auth/a.dart': "import '../customer/home.dart';\nimport '../driver/home.dart';",
          'lib/main.dart': "import 'auth/a.dart';",
          'lib/core/a.dart': "import 'sub/b.dart';\nimport '../firebase_options.dart';",
        }),
        isEmpty,
      );
    });
  });
}
