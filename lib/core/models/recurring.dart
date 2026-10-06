import 'package:cloud_firestore/cloud_firestore.dart';

import 'load.dart';
import 'repeat.dart';

/// How often a repeating shipment comes due.
class Frequency {
  Frequency._();
  static const weekly = 'weekly';
  static const monthly = 'monthly';
  static const all = [weekly, monthly];

  /// The date after [d] (same time of day): 7 days, or the same day next
  /// month (clamped to the month's last day).
  static DateTime next(DateTime d, String frequency) {
    if (frequency == weekly) return d.add(const Duration(days: 7));
    final y = d.month == 12 ? d.year + 1 : d.year;
    final m = d.month == 12 ? 1 : d.month + 1;
    final last = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, d.day > last ? last : d.day, d.hour, d.minute);
  }
}

/// `users/{uid}/recurring_loads/{id}`: a shipment that repeats. Nothing is
/// posted by itself (no server): when one comes due the customer sees it on
/// Home and posts it with one tap. TODO(functions): post due loads unattended.
class RecurringLoad {
  static const maxPerUser = 10;

  final String id;
  final LoadTemplate template;
  final String frequency;
  final DateTime nextDueAt;
  final bool active;

  const RecurringLoad({required this.id, required this.template, required this.frequency, required this.nextDueAt, this.active = true});

  factory RecurringLoad.fromDoc(String id, Map<String, dynamic> d) => RecurringLoad(
        id: id,
        template: LoadTemplate.fromDoc(id, d),
        frequency: d['frequency'] as String? ?? Frequency.weekly,
        nextDueAt: (d['nextDueAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        active: d['active'] != false,
      );

  Map<String, Object?> toMap() => {
        ...template.toMap(),
        'frequency': frequency,
        'nextDueAt': Timestamp.fromDate(nextDueAt),
        'active': active,
      };

  /// Due when its date is today or earlier.
  bool isDue(DateTime now) => active && !nextDueAt.isAfter(DateTime(now.year, now.month, now.day, 23, 59, 59));

  /// The Post Load draft for this occurrence (pickup date set to the due date).
  Load toDraft() => template.toLoadDraft();
}
