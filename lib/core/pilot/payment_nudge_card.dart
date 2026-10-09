import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/backend.dart';
import '../widgets/common.dart';

/// Home card: a reminder an admin left about a payment record (MASTER-6
/// Task 8). [target] is `customer` or `driver`. "Got it" removes it.
class PaymentNudgeCard extends StatefulWidget {
  final String target;
  const PaymentNudgeCard({super.key, required this.target});

  @override
  State<PaymentNudgeCard> createState() => _PaymentNudgeCardState();
}

class _PaymentNudgeCardState extends State<PaymentNudgeCard> {
  List<String> _ids = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = Backend.uid;
    if (uid == null) return;
    try {
      final snap = await Backend.db.collection('payment_nudges').where('userId', isEqualTo: uid).limit(10).get();
      final ids = [for (final d in snap.docs) if (d.data()['target'] == widget.target) d.id];
      if (mounted) setState(() => _ids = ids);
    } catch (_) {}
  }

  Future<void> _clear() async {
    final ids = _ids;
    setState(() => _ids = const []);
    for (final id in ids) {
      try {
        await Backend.db.collection('payment_nudges').doc(id).delete();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ids.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        key: const ValueKey('paymentNudgeCard'),
        child: Row(children: [
          Icon(Icons.payments_outlined, color: AppColors.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, 'pagCardTitle'), style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(tr(context, widget.target == 'driver' ? 'pagCardDriver' : 'pagCardCustomer')),
            ]),
          ),
          TextButton(key: const ValueKey('paymentNudgeClear'), onPressed: _clear, child: Text(tr(context, 'wlGotIt'))),
        ]),
      ),
    );
  }
}
