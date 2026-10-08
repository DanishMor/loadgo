import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

import '../models/booking.dart';
import '../models/earnings.dart';

/// CSV exports for admins. Phone numbers and e-mail addresses are masked,
/// KYC numbers and addresses are never included.
class AdminExport {
  AdminExport._();

  /// Keeps the last two digits: `+91 98765 43210` -> `********10`.
  static String maskPhone(Object? phone) {
    final d = '${phone ?? ''}'.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return '';
    if (d.length <= 2) return '*' * d.length;
    return '${'*' * (d.length - 2)}${d.substring(d.length - 2)}';
  }

  /// `ravi@example.com` -> `r***@example.com`.
  static String maskEmail(Object? email) {
    final e = '${email ?? ''}'.trim();
    final at = e.indexOf('@');
    if (e.isEmpty) return '';
    if (at <= 0) return '***';
    return '${e[0]}***${e.substring(at)}';
  }

  static String cell(Object? v) {
    final s = '${v ?? ''}';
    // A formula in a spreadsheet: keep it text.
    final plainNumber = RegExp(r'^-?\d+(\.\d+)?$').hasMatch(s);
    final safe = s.isNotEmpty && '=+-@'.contains(s[0]) && !plainNumber ? "'$s" : s;
    return (safe.contains(',') || safe.contains('"') || safe.contains('\n')) ? '"${safe.replaceAll('"', '""')}"' : safe;
  }

  static String _date(Object? v) {
    final d = v is DateTime ? v : (v is Timestamp ? v.toDate() : null);
    if (d == null) return '';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static const usersHeader = 'uid,role,name,phone,email,risk_tier,verification,plan,cancels,created';

  /// One row per user document: (uid, data).
  static String usersCsv(Iterable<(String, Map<String, dynamic>)> users) {
    final rows = [usersHeader];
    for (final (uid, d) in users) {
      rows.add([
        uid,
        d['role'] ?? d['selectedRole'] ?? '',
        d['name'] ?? d['driverName'] ?? '',
        maskPhone(d['phone']),
        maskEmail(d['email']),
        d['riskTier'] ?? 'normal',
        d['verificationStatus'] ?? '',
        d['plan'] ?? '',
        d['cancelCount'] ?? 0,
        _date(d['createdAt']),
      ].map(cell).join(','));
    }
    return rows.join('\n');
  }

  /// Fields that never leave an export (personal or secret), whatever a list shows.
  static final _private = RegExp(r'phone|email|aadhaar|(^|_)pan($|_)|licen|dlNumber|rcNumber|kyc|address|otp|upi|token|secret|text|description|note|message|comment', caseSensitive: false);

  /// A CSV of any admin list: `id` plus every plain field (text, number, yes/no,
  /// time) except personal or free-text ones, in a stable column order.
  static String genericCsv(Iterable<(String, Map<String, dynamic>)> docs) {
    final rows = docs.toList();
    final cols = <String>{};
    for (final (_, d) in rows) {
      for (final e in d.entries) {
        final v = e.value;
        if (_private.hasMatch(e.key)) continue;
        if (v is String || v is num || v is bool || v is Timestamp) cols.add(e.key);
      }
    }
    final keys = cols.toList()..sort();
    final out = [['id', ...keys].map(cell).join(',')];
    for (final (id, d) in rows) {
      out.add([id, for (final k in keys) d[k] is Timestamp ? _date(d[k]) : d[k]].map(cell).join(','));
    }
    return '${out.join('\n')}\n';
  }

  static const bookingsHeader = 'booking,date,status,pickup,drop,cargo,vehicle_type,vehicle,amount_rupees,payment,driver,customer,cancelled_by,cancel_reason';

  static String _rupees(int? paise) => paise == null ? '' : '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';

  /// One row per booking (ids only, no phone numbers or names).
  static String bookingsCsv(Iterable<Booking> bookings) {
    final rows = [bookingsHeader];
    for (final b in bookings) {
      final at = b.createdAt?.toDate() ?? EarningsSummary.deliveredAt(b);
      rows.add([
        b.id,
        at.millisecondsSinceEpoch == 0 ? '' : _date(at),
        b.status,
        b.pickup,
        b.drop,
        b.cargoType,
        b.vehicleType,
        b.vehicleNumber,
        _rupees(b.billAmountPaise),
        b.paymentStatus,
        b.driverId,
        b.customerId,
        b.cancellation?.by ?? '',
        b.cancellation?.reason ?? '',
      ].map(cell).join(','));
    }
    return rows.join('\n');
  }
}
