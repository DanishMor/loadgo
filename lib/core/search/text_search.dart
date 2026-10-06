/// Lower-case words of [s] without punctuation.
List<String> _words(String s) => s.toLowerCase().split(RegExp(r'[^a-z0-9ऀ-෿]+')).where((w) => w.isNotEmpty).toList();

/// True when every word typed in [query] starts a word of some field (so
/// "del mum" finds "Delhi -> Mumbai"). An empty query matches nothing.
bool matchesQuery(String query, Iterable<String?> fields) {
  final q = _words(query);
  if (q.isEmpty) return false;
  final words = [for (final f in fields) ..._words(f ?? '')];
  return q.every((w) => words.any((x) => x.startsWith(w)));
}
