import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../pricing/cities.dart';
import '../services/backend.dart';
import '../services/ttl_cache.dart';
import '../widgets/common.dart';

/// Which cities the pilot serves (MASTER-6 Task 2): `config/pilot.openCities`
/// (city names). An empty or missing list means everywhere; a place that is
/// not a known city is never refused (we cannot judge it).
class PilotAreas {
  final List<String> openCities;
  const PilotAreas(this.openCities);

  static const maxCities = 50;

  static PilotAreas fromMap(Map<String, dynamic>? m) {
    final raw = m?['openCities'];
    final list = raw is List ? [for (final c in raw) if (c is String && c.trim().isNotEmpty) c.trim()] : <String>[];
    return PilotAreas(list.take(maxCities).toList());
  }

  bool isOpen(String place) {
    if (openCities.isEmpty) return true;
    final c = findCity(place);
    if (c == null) return true;
    return openCities.any((o) => o.toLowerCase() == c.name.toLowerCase());
  }

  /// The first of the places that is closed, as the city name; null when all are open.
  String? firstClosed(Iterable<String> places) {
    for (final p in places) {
      if (!isOpen(p)) return findCity(p)!.name;
    }
    return null;
  }

  static PilotAreas current = const PilotAreas([]);
  static final TtlCache _cache = TtlCache(const Duration(minutes: 15));

  /// Forget the cached list (after the admin saved a new one).
  static void invalidate() => _cache.invalidate();

  @visibleForTesting
  static void reset() {
    current = const PilotAreas([]);
    invalidate();
  }

  static Future<PilotAreas> refresh({bool force = false}) async {
    await _cache.run(() async {
      final d = await Backend.db.collection('config').doc('pilot').get();
      current = fromMap(d.data());
    }, force: force).catchError((_) => false);
    return current;
  }
}

/// `waitlist/{uid}_{from}_{to}`: a person asks to be told when a route opens.
class WaitlistService {
  WaitlistService._();

  static FirebaseFirestore get _db => Backend.db;

  static String _key(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

  /// Joins the waitlist for the route. [from] and [to] are city names.
  static Future<String> join({required String role, required String from, required String to}) async {
    final uid = Backend.requireUid();
    final id = '${uid}_${_key(from)}_${_key(to)}';
    await _db.collection('waitlist').doc(id).set({'uid': uid, 'role': role, 'from': from, 'to': to, 'createdAt': FieldValue.serverTimestamp()});
    return id;
  }

  static Future<List<({String id, String from, String to})>> mine() async {
    final snap = await _db.collection('waitlist').where('uid', isEqualTo: Backend.requireUid()).limit(20).get();
    return [for (final d in snap.docs) (id: d.id, from: '${d.data()['from']}', to: '${d.data()['to']}')];
  }

  static Future<void> leave(String id) => _db.collection('waitlist').doc(id).delete();

  /// The waitlisted routes whose cities are all open now.
  static Future<List<({String id, String from, String to})>> opened(PilotAreas areas) async {
    final all = await mine();
    return [for (final w in all) if (areas.isOpen(w.from) && areas.isOpen(w.to)) w];
  }
}

/// Dialog for a route outside the pilot: say so and offer the waitlist.
Future<void> showNotServed(BuildContext context, {required String role, required String closedCity, required String from, required String to}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr(ctx, 'wlTitle')),
      content: Text(trf(ctx, 'wlBody', {'city': closedCity}), key: const ValueKey('wlBody')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(ctx, 'cancel'))),
        FilledButton(
          key: const ValueKey('wlJoin'),
          onPressed: () async {
            final nav = Navigator.of(ctx);
            final messenger = ScaffoldMessenger.of(context);
            final done = tr(ctx, 'wlJoined');
            try {
              await WaitlistService.join(role: role, from: findCity(from)?.name ?? from, to: findCity(to)?.name ?? to);
              messenger.showSnackBar(SnackBar(content: Text(done)));
            } catch (_) {}
            nav.pop();
          },
          child: Text(tr(ctx, 'wlJoin')),
        ),
      ],
    ),
  );
}

/// Home card: "your route is now open" for a waitlisted route; closing it
/// removes the entry.
class WaitlistOpenCard extends StatefulWidget {
  const WaitlistOpenCard({super.key});

  @override
  State<WaitlistOpenCard> createState() => _WaitlistOpenCardState();
}

class _WaitlistOpenCardState extends State<WaitlistOpenCard> {
  List<({String id, String from, String to})> _open = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final areas = await PilotAreas.refresh();
      final open = await WaitlistService.opened(areas);
      if (mounted) setState(() => _open = open);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_open.isEmpty) return const SizedBox.shrink();
    final w = _open.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        key: const ValueKey('wlOpenCard'),
        child: Row(children: [
          Icon(Icons.celebration_outlined, color: AppColors.success),
          const SizedBox(width: 12),
          Expanded(child: Text(trf(context, 'wlOpened', {'from': w.from, 'to': w.to}), style: const TextStyle(fontWeight: FontWeight.w700))),
          IconButton(
            key: const ValueKey('wlOpenClose'),
            tooltip: tr(context, 'wlGotIt'),
            icon: const Icon(Icons.close_rounded),
            onPressed: () async {
              await WaitlistService.leave(w.id);
              _load();
            },
          ),
        ]),
      ),
    );
  }
}
