import 'package:shared_preferences/shared_preferences.dart';

/// The last few searches, kept on the device only.
class RecentSearches {
  RecentSearches._();

  static const key = 'recent_searches';
  static const max = 8;

  /// Newest first. A missing or unreadable store gives an empty list.
  static Future<List<String>> load() async {
    try {
      return (await SharedPreferences.getInstance()).getStringList(key) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// Puts [query] first (a repeat moves up, matching without case), keeps [max].
  /// Ignores queries shorter than 2 characters.
  static Future<List<String>> add(String query) async {
    final q = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (q.length < 2) return load();
    final list = [q, for (final s in await load()) if (s.toLowerCase() != q.toLowerCase()) s].take(max).toList();
    try {
      await (await SharedPreferences.getInstance()).setStringList(key, list);
    } catch (_) {}
    return list;
  }

  static Future<void> clear() async {
    try {
      await (await SharedPreferences.getInstance()).remove(key);
    } catch (_) {}
  }
}
