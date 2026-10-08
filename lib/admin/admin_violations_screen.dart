import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/services/comm_admin_service.dart';
import '../core/widgets/admin_phone.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Chat violations (a blocked phone number, UPI id or app mention) newest
/// first, with each person's strikes and the buttons to extend or lift a
/// suspension, reset the strikes, and see the phone number (logged).
class AdminViolationsScreen extends StatefulWidget {
  /// Injectable for tests.
  final Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? violations;

  const AdminViolationsScreen({super.key, this.violations});

  @override
  State<AdminViolationsScreen> createState() => _AdminViolationsScreenState();
}

class _AdminViolationsScreenState extends State<AdminViolationsScreen> {
  int _reload = 0;

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() => _reload++);
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  Widget _userCard(BuildContext context, String uid, List<QueryDocumentSnapshot<Map<String, dynamic>>> rows) {
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey('viol_${uid}_$_reload'),
      future: CommAdminService.user(uid),
      builder: (context, snap) {
        final u = snap.data ?? const <String, dynamic>{};
        final until = (u['chatBlockedUntil'] as Timestamp?)?.toDate();
        final suspended = until != null && until.isAfter(DateTime.now());
        final name = (u['companyName'] ?? u['driverName'] ?? u['name'] ?? uid).toString();
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            key: ValueKey('violUser_$uid'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text(trf(context, 'pcStrikes', {'n': (u['chatStrikes'] as num?)?.toInt() ?? 0}), key: ValueKey('strikes_$uid'), style: const TextStyle(fontWeight: FontWeight.w700)),
              AdminPhoneText(uid: uid, phone: (u['phone'] ?? '').toString(), style: TextStyle(color: AppColors.muted)),
              Wrap(spacing: 6, children: [
                if (suspended) StatusChip(label: trf(context, 'pcSuspendedUntil', {'until': formatDateTime(until)}), color: Colors.red),
                if (u['chatReview'] == true) StatusChip(label: tr(context, 'pcNeedsReview'), color: AppColors.warning),
              ]),
              const SizedBox(height: 6),
              for (final r in rows.take(5))
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${tr(context, 'pcKind${r.data()['kind']}')} · “${r.data()['excerpt'] ?? ''}” · ${r.data()['createdAt'] is Timestamp ? formatDateTime((r.data()['createdAt'] as Timestamp).toDate()) : ''}',
                    style: TextStyle(fontSize: 12, color: AppColors.body),
                  ),
                ),
              Wrap(spacing: 4, children: [
                TextButton(key: ValueKey('extend_$uid'), onPressed: () => _run(() => CommAdminService.extendSuspension(uid)), child: Text(tr(context, 'pcExtend'))),
                if (suspended || u['chatReview'] == true)
                  TextButton(key: ValueKey('lift_$uid'), onPressed: () => _run(() => CommAdminService.liftSuspension(uid)), child: Text(tr(context, 'pcLift'))),
                TextButton(key: ValueKey('reset_$uid'), onPressed: () => _run(() => CommAdminService.resetStrikes(uid)), child: Text(tr(context, 'pcResetStrikes'))),
              ]),
            ]),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'pcAdminViolations'))),
      body: LiveStream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        stream: () => widget.violations ?? CommAdminService.watchViolations(),
        builder: (context, docs) {
          if (docs.isEmpty) return EmptyState(icon: Icons.shield_outlined, title: tr(context, 'pcNoViolations'));
          final byUser = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
          for (final d in docs) {
            byUser.putIfAbsent('${d.data()['userId']}', () => []).add(d);
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            for (final e in byUser.entries.take(30)) _userCard(context, e.key, e.value),
          ]);
        },
      ),
    );
  }
}
