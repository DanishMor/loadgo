import 'package:flutter/material.dart';

import '../core/analytics/rating_burst.dart';
import '../core/l10n/l10n.dart';
import '../core/services/rating_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import 'admin_user_screen.dart';

/// Admin > Rating bursts: users who gave 5 or more 1-star ratings in the last 24 hours.
class AdminRatingBurstScreen extends StatefulWidget {
  final DateTime Function()? now;
  const AdminRatingBurstScreen({super.key, this.now});

  @override
  State<AdminRatingBurstScreen> createState() => _AdminRatingBurstScreenState();
}

class _AdminRatingBurstScreenState extends State<AdminRatingBurstScreen> {
  late Future<List<RatingBurstEntry>> _list = _load();

  Future<List<RatingBurstEntry>> _load() async {
    final now = (widget.now ?? DateTime.now)();
    final ratings = await RatingService.recentRatings(since: now.subtract(RatingBurst.defaultWindow));
    return RatingBurst.find(ratings, now);
  }

  void _refresh() => setState(() {
        _list = _load();
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'adminRatingBurst')),
        actions: [IconButton(key: const ValueKey('burstRefresh'), tooltip: tr(context, 'retry'), onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: FutureBuilder<List<RatingBurstEntry>>(
        future: _list,
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(error: snap.error, onRetry: _refresh);
          final list = snap.data;
          if (list == null) return const Center(child: CircularProgressIndicator());
          if (list.isEmpty) return EmptyState(icon: Icons.star_outline_rounded, title: tr(context, 'burstNone'));
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final e = list[i];
              return AppCard(
                key: ValueKey('burst_${e.raterId}'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminUserScreen(uid: e.raterId))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(trf(context, 'burstLine', {'n': e.oneStarCount, 'm': e.distinctRated}), style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(e.raterId, style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
