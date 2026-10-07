import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/backend.dart';
import '../widgets/common.dart';

/// "Declared goods value: ₹ 50,000" for a claim, read once from the load
/// (give [loadId], or a [bookingId] to find the load through). Shows
/// "not declared" when the customer left it empty and nothing when the load
/// cannot be read.
class DeclaredValueLine extends StatelessWidget {
  final String? loadId;
  final String? bookingId;

  const DeclaredValueLine({super.key, this.loadId, this.bookingId});

  static const _unreadable = -1;

  /// Declared value in paise, 0 when none, [_unreadable] when it could not be read.
  Future<int> _value() async {
    try {
      var id = loadId;
      if (id == null && bookingId != null) {
        id = (await Backend.db.collection('bookings').doc(bookingId).get()).data()?['loadId'] as String?;
      }
      if (id == null) return _unreadable;
      final snap = await Backend.db.collection('loads').doc(id).get();
      if (!snap.exists) return _unreadable;
      return (snap.data()?['declaredValuePaise'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return _unreadable;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _value(),
      builder: (context, snap) {
        final v = snap.data;
        if (v == null || v == _unreadable) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            v > 0 ? trf(context, 'declaredValueLine', {'amount': formatPaise(v)}) : tr(context, 'declaredValueNone'),
            key: const ValueKey('declaredValueLine'),
            style: TextStyle(color: AppColors.muted),
          ),
        );
      },
    );
  }
}
