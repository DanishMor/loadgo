import 'package:cloud_firestore/cloud_firestore.dart';

/// Why a promo code cannot be used right now.
enum PromoProblem { unknown, inactive, expired, belowMinimum, exhausted, usedUp }

class PromoException implements Exception {
  final PromoProblem problem;

  /// For [PromoProblem.belowMinimum]: the minimum order in paise.
  final int? minOrderPaise;
  const PromoException(this.problem, {this.minOrderPaise});

  @override
  String toString() => 'PromoException($problem)';
}

/// `promos/{CODE}`, created by an admin. Money is integer paise; `value` is a
/// percent (1-100) for [percent] codes and paise for [flat] codes.
class Promo {
  static const percent = 'percent';
  static const flat = 'flat';

  final String code;
  final String type;
  final int value;

  /// Cap on the discount (paise); 0 = no cap.
  final int maxDiscountPaise;
  final int minOrderPaise;
  final DateTime expiresAt;

  /// Total redemptions across all users / per user.
  final int usageLimit;
  final int perUserLimit;
  final bool active;

  const Promo({
    required this.code,
    required this.type,
    required this.value,
    this.maxDiscountPaise = 0,
    this.minOrderPaise = 0,
    required this.expiresAt,
    this.usageLimit = 100,
    this.perUserLimit = 1,
    this.active = true,
  });

  static String normaliseCode(String s) => s.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static bool validCode(String s) => RegExp(r'^[A-Z0-9]{3,20}$').hasMatch(s);

  factory Promo.fromMap(String id, Map<String, dynamic> d) => Promo(
        code: id,
        type: d['type'] as String? ?? percent,
        value: (d['value'] as num?)?.toInt() ?? 0,
        maxDiscountPaise: (d['maxDiscountPaise'] as num?)?.toInt() ?? 0,
        minOrderPaise: (d['minOrderPaise'] as num?)?.toInt() ?? 0,
        expiresAt: (d['expiresAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
        usageLimit: (d['usageLimit'] as num?)?.toInt() ?? 1,
        perUserLimit: (d['perUserLimit'] as num?)?.toInt() ?? 1,
        active: d['active'] == true,
      );

  Map<String, Object> toMap() => {
        'code': code,
        'type': type,
        'value': value,
        'maxDiscountPaise': maxDiscountPaise,
        'minOrderPaise': minOrderPaise,
        'expiresAt': Timestamp.fromDate(expiresAt),
        'usageLimit': usageLimit,
        'perUserLimit': perUserLimit,
        'active': active,
      };

  /// Same arithmetic as the Firestore rules: percent rounds down, the cap
  /// applies, and the discount never exceeds the order.
  int discountFor(int totalPaise) {
    final raw = type == percent ? (totalPaise * value) ~/ 100 : value;
    final capped = maxDiscountPaise > 0 && raw > maxDiscountPaise ? maxDiscountPaise : raw;
    return capped > totalPaise ? totalPaise : capped;
  }

  /// Null when the code can be used for an order of [totalPaise] at [now].
  PromoProblem? problemFor(int totalPaise, DateTime now) {
    if (!active) return PromoProblem.inactive;
    if (!expiresAt.isAfter(now)) return PromoProblem.expired;
    if (totalPaise < minOrderPaise) return PromoProblem.belowMinimum;
    return null;
  }
}

/// A code that passed [Promo.problemFor], with the discount and the numbered
/// documents it will use (chosen by `RewardsService.reserve`).
class PromoApplication {
  final Promo promo;
  final int discountPaise;
  final int slot;
  final int use;

  const PromoApplication({required this.promo, required this.discountPaise, required this.slot, required this.use});

  Map<String, Object> toLoadMap() => {'code': promo.code, 'discountPaise': discountPaise, 'slot': slot, 'use': use};
}

/// One line of the credits ledger (signed paise).
class CreditLine {
  final String id;
  final int amountPaise;
  final String kind;
  final String? loadId;
  final String note;
  final DateTime? createdAt;

  const CreditLine({required this.id, required this.amountPaise, required this.kind, this.loadId, this.note = '', this.createdAt});

  factory CreditLine.fromDoc(String id, Map<String, dynamic> d) => CreditLine(
        id: id,
        amountPaise: (d['amountPaise'] as num?)?.toInt() ?? 0,
        kind: d['kind'] as String? ?? '',
        loadId: d['loadId'] as String?,
        note: d['note'] as String? ?? '',
        createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      );

  static int balance(Iterable<CreditLine> lines) => lines.fold(0, (a, l) => a + l.amountPaise);
}
