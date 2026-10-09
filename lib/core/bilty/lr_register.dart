import 'lr_model.dart';
import 'lr_service.dart';

/// One LR in the register: the version to work with and what its links look like.
class LrRow {
  final LrPublic lr;
  final int versions;
  final List<LrShare> shares;
  const LrRow(this.lr, this.versions, this.shares);

  int active(DateTime now) => shares.where((s) => s.isLive(now)).length;
  int revoked() => shares.where((s) => s.revoked).length;
  int expired(DateTime now) => shares.where((s) => !s.revoked && s.expiresAt != null && !s.expiresAt!.isAfter(now)).length;
}

enum LinkState { active, expired, revoked }

/// The LR register of an issuer (MASTER-6 Task 31): every LR once (its newest
/// version), searchable, filtered by status, with the state of its share links.
class LrRegister {
  LrRegister._();

  static LinkState stateOf(LrShare s, DateTime now) => s.revoked ? LinkState.revoked : (s.isLive(now) ? LinkState.active : LinkState.expired);

  /// One row per LR number (issuer, year, seq): the issued version, else the newest.
  /// Newest LR first.
  static List<LrRow> rows(Iterable<LrPublic> all, Iterable<LrShare> shares) {
    final byNumber = <String, List<LrPublic>>{};
    for (final l in all) {
      (byNumber['${l.issuerId}|${l.year}|${l.seq}'] ??= []).add(l);
    }
    final sharesByLr = <String, List<LrShare>>{};
    for (final s in shares) {
      (sharesByLr[s.lrId] ??= []).add(s);
    }
    final rows = <LrRow>[];
    for (final versions in byNumber.values) {
      versions.sort((a, b) => b.version.compareTo(a.version));
      final shown = versions.firstWhere((v) => v.isCurrent, orElse: () => versions.first);
      final links = <LrShare>[for (final v in versions) ...?sharesByLr[v.id]];
      rows.add(LrRow(shown, versions.length, links));
    }
    rows.sort((a, b) => a.lr.year != b.lr.year ? b.lr.year.compareTo(a.lr.year) : b.lr.seq.compareTo(a.lr.seq));
    return rows;
  }

  static String _n(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9ऀ-෿؀-ۿ]+'), ' ').trim();

  /// Rows whose number, route, goods, consignor, consignee, vehicle or driver
  /// contain every word of [query]; [status] limits to one status (null = all).
  static List<LrRow> filter(Iterable<LrRow> rows, {String query = '', String? status}) {
    final words = _n(query).split(' ').where((w) => w.isNotEmpty).toList();
    return [
      for (final r in rows)
        if ((status == null || r.lr.status == status) && _matches(r.lr, words)) r,
    ];
  }

  static bool _matches(LrPublic l, List<String> words) {
    if (words.isEmpty) return true;
    final hay = _n([l.lrNo, l.route, l.pickup, l.drop, l.goods, l.consignorName, l.consigneeName, l.vehicleNumber, l.driverName].join(' '));
    return words.every(hay.contains);
  }

  /// Counts for the filter chips: all, and per status.
  static Map<String?, int> counts(Iterable<LrRow> rows) {
    final out = <String?, int>{null: 0, LrStatus.issued: 0, LrStatus.cancelled: 0, LrStatus.superseded: 0};
    for (final r in rows) {
      out[null] = out[null]! + 1;
      out[r.lr.status] = (out[r.lr.status] ?? 0) + 1;
    }
    return out;
  }
}
