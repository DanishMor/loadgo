import 'dart:convert';

/// Checks, diff and history for the config JSON editor (MASTER-6 Task 13).
class ConfigIssue {
  /// Translation key of the problem and the path it is about.
  final String key;
  final String path;
  const ConfigIssue(this.key, this.path);

  /// The translation key of the message shown for this problem.
  String get messageKey => switch (key) {
        'cfgOutOfRange' => 'cfgIssueRange',
        'cfgNeedWhole' => 'cfgIssueWhole',
        'cfgTooDeep' || 'cfgTooBig' || 'cfgTextTooLong' => 'cfgIssueLong',
        _ => 'cfgIssueFormat',
      };
  @override
  String toString() => '$key @ $path';
}

class ConfigChange {
  final String path;
  final String? before; // null = added
  final String? after; // null = removed
  const ConfigChange(this.path, this.before, this.after);
}

class ConfigSchema {
  ConfigSchema._();

  static const maxDepth = 6;
  static const maxLeaves = 2000;
  static const maxString = 2000;

  static String _kind(Object? v) => v is Map ? 'map' : v is List ? 'list' : v is bool ? 'bool' : v is num ? 'number' : v is String ? 'string' : 'null';

  static Iterable<(String, Object?)> _leaves(Object? v, String path, [int depth = 0]) sync* {
    if (v is Map) {
      for (final e in v.entries) {
        yield* _leaves(e.value, path.isEmpty ? '${e.key}' : '$path.${e.key}', depth + 1);
      }
    } else if (v is List) {
      for (var i = 0; i < v.length; i++) {
        yield* _leaves(v[i], '$path[$i]', depth + 1);
      }
    } else {
      yield (path, v);
    }
  }

  static int _depth(Object? v) => v is Map ? 1 + (v.values.map(_depth).fold(0, (a, b) => a > b ? a : b)) : v is List ? 1 + (v.map(_depth).fold(0, (a, b) => a > b ? a : b)) : 0;

  /// Problems that must be fixed before saving [data] as `config/[docId]`.
  /// [before] is the saved version (null when new): a value may not change
  /// its kind (number to text and so on).
  static List<ConfigIssue> validate(String docId, Map<String, dynamic> data, {Map<String, dynamic>? before}) {
    final out = <ConfigIssue>[];
    if (_depth(data) > maxDepth) out.add(const ConfigIssue('cfgTooDeep', ''));
    var n = 0;
    for (final (path, v) in _leaves(data, '')) {
      if (++n > maxLeaves) {
        out.add(const ConfigIssue('cfgTooBig', ''));
        break;
      }
      if (v is num && (v.isNaN || v.isInfinite)) out.add(ConfigIssue('cfgBadNumber', path));
      if (v is String && v.length > maxString) out.add(ConfigIssue('cfgTextTooLong', path));
    }
    if (before != null) {
      final old = {for (final (p, v) in _leaves(before, '')) p: v};
      for (final (p, v) in _leaves(data, '')) {
        final o = old[p];
        if (o != null && v != null && _kind(o) != _kind(v)) out.add(ConfigIssue('cfgKindChanged', p));
      }
    }
    out.addAll(_perDoc(docId, data));
    return out;
  }

  static ConfigIssue? _num(Map d, String key, {double? min, double? max}) {
    final v = d[key];
    if (v == null) return null;
    if (v is! num) return ConfigIssue('cfgNeedNumber', key);
    if (min != null && v < min) return ConfigIssue('cfgOutOfRange', key);
    if (max != null && v > max) return ConfigIssue('cfgOutOfRange', key);
    return null;
  }

  static List<ConfigIssue> _perDoc(String docId, Map<String, dynamic> d) {
    final out = <ConfigIssue>[];
    switch (docId) {
      case 'pricing':
        for (final (p, v) in _leaves(d, '')) {
          if (v is num && v < 0) out.add(ConfigIssue('cfgOutOfRange', p));
          final last = p.split('.').last;
          if (v is num && last.endsWith('Percent') && v > 100) out.add(ConfigIssue('cfgOutOfRange', p));
          // Rate cards are whole paise.
          if (v is num && (p.startsWith('categories.') || p.startsWith('types.')) && v != v.roundToDouble()) out.add(ConfigIssue('cfgNeedWhole', p));
        }
      case 'vehicle_types':
        final t = d['types'];
        if (t is! List || t.isEmpty || t.length > 50) {
          out.add(const ConfigIssue('cfgNeedList', 'types'));
        } else {
          for (var i = 0; i < t.length; i++) {
            final e = t[i];
            if (e is! Map || e['id'] is! String || (e['id'] as String).isEmpty || e['name'] is! String) {
              out.add(ConfigIssue('cfgNeedText', 'types[$i]'));
              continue;
            }
            final lo = e['minTons'], hi = e['maxTons'];
            if (lo is! num || hi is! num || lo < 0 || hi <= lo) out.add(ConfigIssue('cfgOutOfRange', 'types[$i].maxTons'));
          }
        }
      case 'risk':
        for (final k in ['reviewScore', 'holdScore']) {
          final i = _num(d, k, min: 0, max: 1000);
          if (i != null) out.add(i);
        }
        final r = d['reviewScore'], h = d['holdScore'];
        if (r is num && h is num && r >= h) out.add(const ConfigIssue('cfgOutOfRange', 'holdScore'));
      case 'support':
        final phone = d['phone'];
        if (phone != null && (phone is! String || !RegExp(r'^[+0-9 \-]{0,16}$').hasMatch(phone))) out.add(const ConfigIssue('cfgNeedText', 'phone'));
        final hours = d['hours'];
        if (hours != null && (hours is! String || hours.length > 60)) out.add(const ConfigIssue('cfgTextTooLong', 'hours'));
      case 'announcement':
        final text = d['text'];
        if (text != null && (text is! String || text.length > 300)) out.add(const ConfigIssue('cfgTextTooLong', 'text'));
        if (d['level'] != null && !const ['info', 'warning', 'urgent'].contains(d['level'])) out.add(const ConfigIssue('cfgOutOfRange', 'level'));
        final until = d['until'];
        if (until != null && until != '' && (until is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(until))) out.add(const ConfigIssue('cfgNeedDate', 'until'));
        final roles = d['roles'];
        if (roles != null && (roles is! List || roles.any((x) => !const ['customer', 'driver', 'fleet'].contains(x)))) out.add(const ConfigIssue('cfgOutOfRange', 'roles'));
      case 'pilot':
        if (d['inviteOnly'] != null && d['inviteOnly'] is! bool) out.add(const ConfigIssue('cfgNeedBool', 'inviteOnly'));
        final c = d['openCities'];
        if (c != null && (c is! List || c.length > 50 || c.any((x) => x is! String || x.trim().isEmpty || x.length > 40))) out.add(const ConfigIssue('cfgNeedList', 'openCities'));
    }
    return out;
  }

  /// What changes between [before] and [after]: one entry per changed leaf
  /// (a list counts as one value). Order: by path.
  static List<ConfigChange> diff(Map<String, dynamic>? before, Map<String, dynamic> after) {
    String show(Object? v) {
      final s = v is String ? v : jsonEncode(v);
      return s.length > 80 ? '${s.substring(0, 77)}...' : s;
    }

    Map<String, Object?> flat(Map<String, dynamic>? m) {
      final out = <String, Object?>{};
      void walk(Object? v, String path) {
        if (path.isEmpty && v is Map && v.isEmpty) return;
        if (v is Map && v.isNotEmpty) {
          for (final e in v.entries) {
            walk(e.value, path.isEmpty ? '${e.key}' : '$path.${e.key}');
          }
        } else {
          out[path] = v;
        }
      }

      walk(m ?? const {}, '');
      out.remove('updatedAt');
      return out;
    }

    final a = flat(before), b = flat(after);
    final paths = {...a.keys, ...b.keys}.toList()..sort();
    return [
      for (final p in paths)
        if (!(a.containsKey(p) && b.containsKey(p) && jsonEncode(a[p]) == jsonEncode(b[p])))
          ConfigChange(p, a.containsKey(p) ? show(a[p]) : null, b.containsKey(p) ? show(b[p]) : null),
    ];
  }
}

/// Limits of the saved versions (`config_history`).
class ConfigHistory {
  ConfigHistory._();

  /// Longest saved version, in characters of JSON (the editor allows 20,000).
  static const maxJson = 30000;
}
