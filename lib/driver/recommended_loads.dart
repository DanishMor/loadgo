import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/matching/load_ranker.dart';
import '../core/models/load.dart';
import '../core/services/match_service.dart';
import '../core/widgets/common.dart';

String matchReasonLabel(BuildContext context, MatchReason r) => tr(context, switch (r) {
      MatchReason.nearPickup => 'matchNearPickup',
      MatchReason.returnLoad => 'matchReturnLoad',
      MatchReason.favouriteRoute => 'matchFavouriteRoute',
      MatchReason.bestFit => 'matchBestFit',
      MatchReason.onYourRoute => 'matchOnYourRoute',
      MatchReason.stopsOnRoute => 'matchStopsOnRoute',
    });

/// Small chips telling the driver why a load was recommended.
class MatchReasonChips extends StatelessWidget {
  final List<MatchReason> reasons;
  const MatchReasonChips({super.key, required this.reasons});

  @override
  Widget build(BuildContext context) {
    if (reasons.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(spacing: 6, runSpacing: 4, children: [
        for (final r in reasons) StatusChip(label: matchReasonLabel(context, r), color: AppColors.success),
      ]),
    );
  }
}

/// "Recommended for you": the top open loads for this driver's vehicles,
/// ranked by [LoadRanker]. Shows nothing for unverified drivers, drivers
/// without a fitting vehicle, or when no load matches. [cardBuilder] draws
/// the load card so this folder does not depend on the legacy feature code.
class RecommendedLoads extends StatefulWidget {
  final List<Load> loads;
  final Widget Function(LoadMatch match) cardBuilder;
  final int max;

  const RecommendedLoads({super.key, required this.loads, required this.cardBuilder, this.max = 3});

  @override
  State<RecommendedLoads> createState() => _RecommendedLoadsState();
}

class _RecommendedLoadsState extends State<RecommendedLoads> {
  late final Future<DriverContext?> _ctx = MatchService.driverContext().then<DriverContext?>((c) => c).catchError((_) => null);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DriverContext?>(
      future: _ctx,
      builder: (context, snap) {
        final ctx = snap.data;
        if (ctx == null) return const SizedBox.shrink();
        final top = LoadRanker.rank(widget.loads, ctx).take(widget.max).toList();
        if (top.isEmpty) return const SizedBox.shrink();
        return Column(
          key: const ValueKey('recommended'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                const Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(tr(context, 'recommendedLoads'),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.title)),
              ]),
            ),
            for (final m in top) ...[widget.cardBuilder(m), const SizedBox(height: 12)],
            const Divider(),
          ],
        );
      },
    );
  }
}
