import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/matching/return_loads.dart';
import '../core/models/booking.dart';
import '../core/models/load.dart';
import '../core/services/backend.dart';
import '../core/services/load_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import '../core/widgets/load_card.dart';
import 'available_loads_view.dart';

/// "Loads for the way back" under a trip that is on its way or done: open
/// loads starting near the drop city, return runs first.
class ReturnLoadsSection extends StatelessWidget {
  final Booking booking;

  /// Injectable for tests.
  final Stream<List<Load>>? loads;
  final ValueChanged<String>? onAccepted;

  const ReturnLoadsSection({super.key, required this.booking, this.loads, this.onAccepted});

  @override
  Widget build(BuildContext context) {
    return LiveStream<List<Load>>(
      stream: () => loads ?? LoadService.watchOpen(),
      compact: true,
      builder: (context, open) {
        final back = returnLoadsFor(booking, open, excludeShipperId: Backend.uid).take(3).toList();
        if (back.isEmpty) return const SizedBox.shrink();
        return Column(
          key: const ValueKey('returnLoads'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(trf(context, 'returnLoadsTitle', {'city': booking.drop}), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.title)),
            const SizedBox(height: 8),
            for (final r in back) ...[
              if (r.towardsHome)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(tr(context, 'returnHome'), key: ValueKey('home_${r.load.id}'), style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700)),
                ),
              LoadCard(key: ValueKey('return_${r.load.id}'), load: r.load, networkShare: true, action: AcceptLoadButton(load: r.load, onAccepted: onAccepted)),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}
