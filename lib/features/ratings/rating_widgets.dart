import 'package:flutter/material.dart';

import '../../core/models/booking.dart';
import '../../core/models/rating.dart';
import '../../core/services/rating_service.dart';
import '../../core/widgets/common.dart';
import '../../main.dart';

const _starColor = Color(0xFFFDB022);

/// Row of 1-5 stars; tappable when [onChanged] is given.
class StarRow extends StatelessWidget {
  final int stars;
  final double size;
  final ValueChanged<int>? onChanged;

  const StarRow({super.key, required this.stars, this.size = 28, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          onChanged == null
              ? Icon(i <= stars ? Icons.star_rounded : Icons.star_outline_rounded, color: _starColor, size: size)
              : IconButton(
                  key: ValueKey('star$i'),
                  visualDensity: VisualDensity.compact,
                  tooltip: '$i',
                  onPressed: () => onChanged!(i),
                  icon: Icon(i <= stars ? Icons.star_rounded : Icons.star_outline_rounded, color: _starColor, size: size),
                ),
      ],
    );
  }
}

/// "★ 4.5 (12)" for [userId]; renders nothing until they have ratings.
class RatingBadge extends StatefulWidget {
  final String userId;
  const RatingBadge({super.key, required this.userId});

  @override
  State<RatingBadge> createState() => _RatingBadgeState();
}

class _RatingBadgeState extends State<RatingBadge> {
  late final Stream<RatingSummary> _summary = RatingService.watchSummary(widget.userId);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<RatingSummary>(
      stream: _summary,
      builder: (context, snap) {
        final s = snap.data;
        if (s == null || s.count == 0) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, color: _starColor, size: 20),
            const SizedBox(width: 4),
            Text(s.average.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.title)),
            const SizedBox(width: 4),
            Text('(${s.count} ${tr(context, 'ratings')})', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          ],
        );
      },
    );
  }
}

/// After delivery: lets the signed-in party rate the other one once, then
/// shows the rating they gave.
class RatingPrompt extends StatefulWidget {
  final Booking booking;

  /// Translation key for the heading, e.g. 'rateDriver' / 'rateCustomer'.
  final String titleKey;

  const RatingPrompt({super.key, required this.booking, required this.titleKey});

  @override
  State<RatingPrompt> createState() => _RatingPromptState();
}

class _RatingPromptState extends State<RatingPrompt> {
  late final Stream<Rating?> _mine = RatingService.watchMine(widget.booking.id);
  final _commentCtrl = TextEditingController();
  int _stars = 0;
  bool _saving = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      await RatingService.rate(booking: widget.booking, stars: _stars, comment: _commentCtrl.text);
      if (mounted) showSnack(context, tr(context, 'thanksForRating'));
    } on AlreadyRatedException {
      if (mounted) showSnack(context, tr(context, 'alreadyRated'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Rating?>(
      stream: _mine,
      builder: (context, snap) {
        if (!snap.hasData && snap.connectionState == ConnectionState.waiting) return const SizedBox.shrink();
        final mine = snap.data;
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(context, mine == null ? widget.titleKey : 'yourRating'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.title)),
              const SizedBox(height: 8),
              if (mine != null) ...[
                StarRow(stars: mine.stars, size: 24),
                if (mine.comment.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(mine.comment, style: const TextStyle(color: AppColors.muted)),
                ],
              ] else ...[
                StarRow(stars: _stars, onChanged: _saving ? null : (v) => setState(() => _stars = v)),
                const SizedBox(height: 8),
                TextField(
                  controller: _commentCtrl,
                  maxLength: 500,
                  maxLines: 2,
                  decoration: InputDecoration(hintText: tr(context, 'commentOptional')),
                ),
                PrimaryButton(
                  label: tr(context, 'submitRating'),
                  loading: _saving,
                  onPressed: _stars == 0 ? null : _submit,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
