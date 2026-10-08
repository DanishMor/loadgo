import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import '../services/backend.dart';
import '../services/server_clock.dart';
import '../services/ttl_cache.dart';
import '../widgets/common.dart';

/// `config/announcement`, written by an admin in Admin > Config (MASTER-5 Task 40):
///
///     {"id": "diwali-2026", "text": "Support is closed on 12 Nov.",
///      "text_hindi": "...", "level": "info", "until": "2026-11-13",
///      "roles": ["customer", "driver", "fleet"]}
///
/// `text` is the default; `text_<language>` (the language name, e.g.
/// `text_tamil`) wins for that language. `level` is info, warning or urgent
/// (urgent cannot be closed). `until` is the last day it shows; `roles` limits
/// who sees it (empty or missing = everyone). A new `id` shows it again to
/// people who closed the old one.
class Announcement {
  static const levels = ['info', 'warning', 'urgent'];

  final String id;
  final Map<String, String> texts;
  final String level;
  final DateTime? until;
  final List<String> roles;

  const Announcement({required this.id, required this.texts, this.level = 'info', this.until, this.roles = const []});

  /// Null when the document is missing or has no text.
  static Announcement? fromMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    final texts = <String, String>{
      for (final e in m.entries)
        if ((e.key == 'text' || e.key.startsWith('text_')) && e.value is String && (e.value as String).trim().isNotEmpty) e.key: (e.value as String).trim(),
    };
    if (texts.isEmpty) return null;
    final until = m['until'] is String ? DateTime.tryParse(m['until'] as String) : null;
    final id = (m['id'] is String && (m['id'] as String).trim().isNotEmpty) ? (m['id'] as String).trim() : (texts['text'] ?? texts.values.first).hashCode.toRadixString(36);
    return Announcement(
      id: id.length > 60 ? id.substring(0, 60) : id,
      texts: texts,
      level: levels.contains(m['level']) ? m['level'] as String : 'info',
      until: until == null ? null : DateTime(until.year, until.month, until.day),
      roles: [for (final r in (m['roles'] is List ? m['roles'] as List : const [])) if (r is String) r],
    );
  }

  String textFor(AppLanguage language) => texts['text_${language.name}'] ?? texts['text'] ?? texts.values.first;

  bool get dismissible => level != 'urgent';

  /// Shown through the end of the [until] day, to [role] only when roles are listed.
  bool isActive(DateTime now, String role) {
    if (until != null && !DateTime(now.year, now.month, now.day).isBefore(until!.add(const Duration(days: 1)))) return false;
    return roles.isEmpty || roles.contains(role);
  }
}

class AnnouncementService {
  AnnouncementService._();

  static final ValueNotifier<Announcement?> current = ValueNotifier(null);
  static final TtlCache _cache = TtlCache(const Duration(minutes: 15));
  static Object? _forDb;

  /// Reads the document at most every 15 minutes (with the other config).
  static Future<void> refresh({bool force = false}) async {
    if (!force && _cache.fresh && identical(_forDb, Backend.db)) return;
    try {
      final snap = await Backend.db.collection('config').doc('announcement').get();
      current.value = Announcement.fromMap(snap.data());
      _cache.markFetched();
      _forDb = Backend.db;
    } catch (_) {
      // Offline or signed out: keep what is shown.
    }
  }

  static String _key(String id) => 'announcement_closed_$id';

  static Future<bool> closed(String id) async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_key(id)) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> close(String id) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_key(id), true);
    } catch (_) {}
  }

  @visibleForTesting
  static void reset() {
    current.value = null;
    _cache.invalidate();
    _forDb = null;
  }
}

/// The admin's notice at the top of a home screen.
class AnnouncementBanner extends StatefulWidget {
  final String role;
  const AnnouncementBanner({super.key, required this.role});

  @override
  State<AnnouncementBanner> createState() => _AnnouncementBannerState();
}

class _AnnouncementBannerState extends State<AnnouncementBanner> {
  String? _closedId;
  String? _checkedId;

  Future<void> _check(String id) async {
    _checkedId = id;
    if (await AnnouncementService.closed(id) && mounted) setState(() => _closedId = id);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Announcement?>(
      valueListenable: AnnouncementService.current,
      builder: (context, a, _) {
        if (a == null || !a.isActive(ServerClock.now(), widget.role)) return const SizedBox.shrink();
        if (_checkedId != a.id) _check(a.id);
        if (a.dismissible && _closedId == a.id) return const SizedBox.shrink();
        final color = switch (a.level) {
          'urgent' => Colors.redAccent,
          'warning' => AppColors.warning,
          _ => AppColors.primary,
        };
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Container(
            key: ValueKey('announcement_${a.level}'),
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.5))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(a.level == 'info' ? Icons.campaign_outlined : Icons.warning_amber_rounded, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(a.textFor(LanguageScope.of(context)), key: const ValueKey('announcementText'), style: TextStyle(color: AppColors.title, height: 1.35))),
              if (a.dismissible)
                IconButton(
                  key: const ValueKey('announcementClose'),
                  tooltip: tr(context, 'close'),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () {
                    setState(() => _closedId = a.id);
                    AnnouncementService.close(a.id);
                  },
                ),
            ]),
          ),
        );
      },
    );
  }
}
