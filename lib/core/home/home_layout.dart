import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// E21: which sections a home shows and in what order. Kept on the phone per role (no reads, no writes to the
/// server). [locked] sections (the booking hero) can be moved but never hidden.
class HomeLayout {
  final List<String> order;
  final Set<String> hidden;
  final Set<String> locked;
  const HomeLayout(this.order, {this.hidden = const {}, this.locked = const {}});

  /// Defensive: unknown and repeated ids are dropped, sections the app added since are appended in their default
  /// place order, and a locked section is never hidden. Anything that does not parse gives the defaults.
  static HomeLayout parse(Object? json, List<String> known, {Set<String> locked = const {}, Set<String> hiddenByDefault = const {}}) {
    final order = <String>[];
    final hidden = <String>{};
    var parsed = false;
    if (json is Map) {
      final o = json['order'], h = json['hidden'];
      if (o is List) {
        parsed = true;
        for (final id in o) {
          if (id is String && known.contains(id) && !order.contains(id)) order.add(id);
        }
      }
      if (h is List) {
        for (final id in h) {
          if (id is String && known.contains(id) && !locked.contains(id)) hidden.add(id);
        }
      }
    }
    for (final id in known) {
      if (!order.contains(id)) {
        order.add(id);
        if (hiddenByDefault.contains(id) && !locked.contains(id)) hidden.add(id);
      }
    }
    if (!parsed) hidden.addAll(hiddenByDefault.difference(locked));
    return HomeLayout(order, hidden: hidden, locked: locked);
  }

  List<String> get visible => [for (final id in order) if (!hidden.contains(id)) id];

  bool isHidden(String id) => hidden.contains(id);

  /// Moves the section at [from] so that it ends up at index [to].
  HomeLayout move(int from, int to) {
    if (from < 0 || from >= order.length || to < 0 || to >= order.length) return this;
    final next = [...order];
    next.insert(to, next.removeAt(from));
    return HomeLayout(next, hidden: hidden, locked: locked);
  }

  HomeLayout toggle(String id) {
    if (locked.contains(id) || !order.contains(id)) return this;
    final next = {...hidden};
    if (!next.remove(id)) next.add(id);
    return HomeLayout(order, hidden: next, locked: locked);
  }

  Map<String, Object> toJson() => {'order': order, 'hidden': hidden.toList()};
}

/// Saves a [HomeLayout] per role in SharedPreferences; any storage trouble falls back to the defaults.
class HomeLayoutStore {
  HomeLayoutStore._();

  static String key(String role) => 'home_layout_$role';

  static Future<HomeLayout> load(String role, List<String> known, {Set<String> locked = const {}, Set<String> hiddenByDefault = const {}}) async {
    Object? json;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key(role));
      if (raw != null && raw.length < 4096) json = jsonDecode(raw);
    } catch (_) {
      json = null;
    }
    return HomeLayout.parse(json, known, locked: locked, hiddenByDefault: hiddenByDefault);
  }

  static Future<void> save(String role, HomeLayout layout) async {
    try {
      await (await SharedPreferences.getInstance()).setString(key(role), jsonEncode(layout.toJson()));
    } catch (_) {
      // Not saved: the home keeps the layout until the app closes.
    }
  }

  static Future<void> reset(String role) async {
    try {
      await (await SharedPreferences.getInstance()).remove(key(role));
    } catch (_) {}
  }
}
