import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/backend.dart';
import '../widgets/common.dart';

/// Driver home: loads an admin suggested (MASTER-6 Task 4). It assigns
/// nothing; the driver finds the load in Loads and accepts as usual.
class DispatchSuggestionsCard extends StatefulWidget {
  const DispatchSuggestionsCard({super.key});

  @override
  State<DispatchSuggestionsCard> createState() => _DispatchSuggestionsCardState();
}

class _DispatchSuggestionsCardState extends State<DispatchSuggestionsCard> {
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = Backend.uid;
    if (uid == null) return;
    try {
      final snap = await Backend.db.collection('dispatch_suggestions').where('driverId', isEqualTo: uid).where('status', isEqualTo: 'suggested').limit(5).get();
      if (mounted) setState(() => _items = snap.docs);
    } catch (_) {}
  }

  Future<void> _dismiss(String id) async {
    try {
      await Backend.db.collection('dispatch_suggestions').doc(id).update({'status': 'declined'});
    } catch (_) {}
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        key: const ValueKey('dispatchCard'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(context, 'dispCardTitle'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          for (final d in _items)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${d.data()['pickup']} → ${d.data()['drop']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${d.data()['weight']} t · ${d.data()['vehicleType']}${'${d.data()['note']}'.isEmpty ? '' : '\n${d.data()['note']}'}', style: TextStyle(color: AppColors.muted)),
                  ]),
                ),
                TextButton(key: ValueKey('dispDismiss_${d.id}'), onPressed: () => _dismiss(d.id), child: Text(tr(context, 'dispDismiss'))),
              ]),
            ),
          const SizedBox(height: 6),
          Text(tr(context, 'dispCardHint'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
        ]),
      ),
    );
  }
}
