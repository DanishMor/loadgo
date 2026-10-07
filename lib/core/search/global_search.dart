import '../models/booking.dart';
import '../models/load.dart';
import '../models/saved_place.dart';
import '../models/support_ticket.dart';
import '../pricing/cities.dart';

/// What a search result is. The order is the order of the sections.
enum SearchKind { booking, load, ticket, place, city, help }

/// One thing that can be found: what to show and which words to match.
class SearchEntry {
  final SearchKind kind;

  /// Booking, load, ticket or place id; city name; help topic number.
  final String id;
  final String title;
  final String subtitle;

  /// Extra words the entry is found by (title and subtitle always count).
  final List<String> keywords;

  const SearchEntry({required this.kind, required this.id, required this.title, this.subtitle = '', this.keywords = const []});
}

class SearchHit {
  final SearchEntry entry;
  final int score;
  const SearchHit(this.entry, this.score);
}

/// Hits of one kind, best first; [total] counts all of them, [hits] only the
/// ones kept.
class SearchSection {
  final SearchKind kind;
  final List<SearchHit> hits;
  final int total;
  const SearchSection(this.kind, this.hits, this.total);
}

/// Pure index over everything a user can look for in the app: bookings,
/// loads, tickets, saved places, cities and help topics. No I/O.
///
/// Ranking per entry (the best field wins): an exact field 100, a field that
/// starts with the query 80, every typed word starting a word of the entry
/// 60, the query inside a field 40. A title match adds 5. Ties: kind order,
/// then title.
class GlobalSearch {
  final List<SearchEntry> entries;
  const GlobalSearch(this.entries);

  static const exact = 100;
  static const prefix = 80;
  static const wordPrefix = 60;
  static const contains = 40;
  static const titleBonus = 5;

  /// Lower case, punctuation to spaces, one space between words.
  static String normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true), ' ').trim();

  static List<String> _words(String s) => normalize(s).split(' ').where((w) => w.isNotEmpty).toList();

  /// 0 when [e] does not match [query].
  static int score(String query, SearchEntry e) {
    final q = normalize(query);
    if (q.isEmpty) return 0;
    final qWords = _words(q);
    final fields = [e.title, e.subtitle, ...e.keywords];
    var best = 0;
    for (var i = 0; i < fields.length; i++) {
      final f = normalize(fields[i]);
      if (f.isEmpty) continue;
      var s = 0;
      if (f == q) {
        s = exact;
      } else if (f.startsWith(q)) {
        s = prefix;
      } else if (f.contains(q)) {
        s = contains;
      }
      if (s > 0 && i == 0) s += titleBonus;
      if (s > best) best = s;
    }
    // Words typed in any order, each starting some word of the whole entry.
    final allWords = [for (final f in fields) ..._words(f)];
    if (qWords.every((w) => allWords.any((x) => x.startsWith(w))) && wordPrefix > best) best = wordPrefix;
    return best;
  }

  /// Sections with at least one hit, in [SearchKind] order, each capped at
  /// [perKind] hits.
  List<SearchSection> search(String query, {int perKind = 5}) {
    if (normalize(query).isEmpty) return const [];
    final byKind = <SearchKind, List<SearchHit>>{};
    for (final e in entries) {
      final s = score(query, e);
      if (s > 0) byKind.putIfAbsent(e.kind, () => []).add(SearchHit(e, s));
    }
    final out = <SearchSection>[];
    for (final k in SearchKind.values) {
      final list = byKind[k];
      if (list == null) continue;
      list.sort((a, b) {
        final c = b.score.compareTo(a.score);
        return c != 0 ? c : a.entry.title.compareTo(b.entry.title);
      });
      out.add(SearchSection(k, list.take(perKind).toList(), list.length));
    }
    return out;
  }

  /// All hits of [kind] (for "show all").
  List<SearchHit> all(String query, SearchKind kind) {
    final list = [
      for (final e in entries)
        if (e.kind == kind) SearchHit(e, score(query, e)),
    ].where((h) => h.score > 0).toList()
      ..sort((a, b) {
        final c = b.score.compareTo(a.score);
        return c != 0 ? c : a.entry.title.compareTo(b.entry.title);
      });
    return list;
  }

  // ----------------------------------------------------------- entry makers

  static SearchEntry fromBooking(Booking b) => SearchEntry(
        kind: SearchKind.booking,
        id: b.id,
        title: '${b.pickup} → ${b.drop}',
        subtitle: [b.cargoType, b.driverName].where((s) => s.trim().isNotEmpty).join(' · '),
        keywords: [b.pickup, b.drop, ...b.extraPickups, ...b.extraDrops, b.vehicleType, b.vehicleNumber, b.status],
      );

  static SearchEntry fromLoad(Load l) => SearchEntry(
        kind: SearchKind.load,
        id: l.id,
        title: '${l.pickup} → ${l.drop}',
        subtitle: [l.cargoType, l.vehicleType].where((s) => s.trim().isNotEmpty).join(' · '),
        keywords: [l.pickup, l.drop, ...l.extraPickups, ...l.extraDrops, l.notes, l.status],
      );

  static SearchEntry fromTicket(SupportTicket t) => SearchEntry(
        kind: SearchKind.ticket,
        id: t.id,
        title: t.subject,
        subtitle: '${t.category} · ${t.status}',
        keywords: [t.description],
      );

  static SearchEntry fromPlace(SavedPlace p) => SearchEntry(
        kind: SearchKind.place,
        id: p.id,
        title: p.name,
        subtitle: p.address,
        keywords: [p.label],
      );

  /// The offline city table (names, aliases and states).
  static List<SearchEntry> cities() => [
        for (final c in indianCities) SearchEntry(kind: SearchKind.city, id: c.name, title: c.name, subtitle: c.state, keywords: c.aliases),
      ];

  /// Help topics from translated question/answer pairs: (number, question, answer).
  static List<SearchEntry> helpTopics(Iterable<(int, String, String)> topics) => [
        for (final t in topics) SearchEntry(kind: SearchKind.help, id: '${t.$1}', title: t.$2, keywords: [t.$3]),
      ];
}
