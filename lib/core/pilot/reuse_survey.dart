import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../services/backend.dart';
import '../widgets/common.dart';

/// "Would you use it again?" after a delivered trip (MASTER-6 Task 7), asked
/// of both sides once: `trip_surveys/{bookingId}_{uid}`.
class SurveyService {
  SurveyService._();

  static const answers = ['yes', 'maybe', 'no'];

  static String idFor(String bookingId, String uid) => '${bookingId}_$uid';

  static DocumentReference<Map<String, dynamic>> _ref(String bookingId, String uid) => Backend.db.collection('trip_surveys').doc(idFor(bookingId, uid));

  /// My answer for the trip, or null.
  static Future<String?> mine(String bookingId) async {
    final uid = Backend.uid;
    if (uid == null) return null;
    try {
      return (await _ref(bookingId, uid).get()).data()?['answer'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// [role] is customer or driver (the side of the signed-in person).
  static Future<void> answer(Booking booking, String role, String value) {
    assert(answers.contains(value) && (role == 'customer' || role == 'driver'));
    final uid = Backend.requireUid();
    return _ref(booking.id, uid).set({
      'bookingId': booking.id,
      'uid': uid,
      'role': role,
      'answer': value,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

/// Numbers for the admin view.
class SurveyStats {
  final Map<String, Map<String, int>> byRole; // role -> answer -> count

  const SurveyStats(this.byRole);

  static SurveyStats compute(Iterable<Map<String, dynamic>> rows) {
    final out = <String, Map<String, int>>{
      for (final r in const ['customer', 'driver']) r: {for (final a in SurveyService.answers) a: 0},
    };
    for (final m in rows) {
      final role = m['role'], answer = m['answer'];
      if (out.containsKey(role) && SurveyService.answers.contains(answer)) out[role]![answer as String] = out[role]![answer]! + 1;
    }
    return SurveyStats(out);
  }

  int total(String role) => byRole[role]!.values.fold(0, (a, b) => a + b);

  /// Whole percent of "yes" for the role; null with no answers.
  int? yesPercent(String role) {
    final t = total(role);
    return t == 0 ? null : byRole[role]!['yes']! * 100 ~/ t;
  }
}

class ReuseSurveyCard extends StatefulWidget {
  final Booking booking;
  final String role;
  const ReuseSurveyCard({super.key, required this.booking, required this.role});

  @override
  State<ReuseSurveyCard> createState() => _ReuseSurveyCardState();
}

class _ReuseSurveyCardState extends State<ReuseSurveyCard> {
  String? _answer;
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    SurveyService.mine(widget.booking.id).then((a) {
      if (mounted) {
        setState(() {
          _answer = a;
          _loaded = true;
        });
      }
    });
  }

  Future<void> _send(String v) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await SurveyService.answer(widget.booking, widget.role, v);
      if (mounted) setState(() => _answer = v);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return AppCard(
      key: const ValueKey('reuseSurvey'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(context, _answer == null ? 'svTitle' : 'svThanks'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        if (_answer == null) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final a in SurveyService.answers) OutlinedButton(key: ValueKey('sv_$a'), onPressed: _busy ? null : () => _send(a), child: Text(tr(context, 'sv_$a'))),
          ]),
        ],
      ]),
    );
  }
}
