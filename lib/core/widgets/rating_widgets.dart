import '../errors/error_text.dart';
import 'package:flutter/material.dart';

import '../models/booking.dart';
import '../models/rating.dart';
import '../services/rating_service.dart';
import 'common.dart';
import 'live_stream.dart';
import '../l10n/l10n.dart';
const _starColor = Color(0xFFFDB022);

/// Row of 1-5 stars; tappable when [onChanged] is given.
class StarRow extends StatelessWidget {
  final int stars;
  final double size;
  final ValueChanged<int>? onChanged;
  final String keyPrefix;

  const StarRow({super.key, required this.stars, this.size = 28, this.onChanged, this.keyPrefix = 'star'});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          onChanged == null
              ? Icon(i <= stars ? Icons.star_rounded : Icons.star_outline_rounded, color: _starColor, size: size)
              : IconButton(
                  key: ValueKey('$keyPrefix$i'),
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
            Text(s.average.toStringAsFixed(1), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.title)),
            const SizedBox(width: 4),
            Text('(${s.count} ${tr(context, 'ratings')})', style: TextStyle(color: AppColors.muted, fontSize: 13)),
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
  final Map<String, int> _cats = {};
  bool _saving = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      await RatingService.rate(booking: widget.booking, stars: _stars, comment: _commentCtrl.text, cats: _cats);
      if (mounted) showSnack(context, tr(context, 'thanksForRating'));
    } on AlreadyRatedException {
      if (mounted) showSnack(context, tr(context, 'alreadyRated'));
    } catch (error) {
      if (mounted) showSnack(context, errorText(context, error));
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.title)),
              const SizedBox(height: 8),
              if (mine != null) ...[
                StarRow(stars: mine.stars, size: 24),
                if (mine.cats.isNotEmpty) RatingCategoryRows(scores: {for (final e in mine.cats.entries) e.key: e.value.toDouble()}),
                if (mine.comment.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(mine.comment, style: TextStyle(color: AppColors.muted)),
                ],
              ] else ...[
                StarRow(stars: _stars, onChanged: _saving ? null : (v) => setState(() => _stars = v)),
                const SizedBox(height: 4),
                Text(tr(context, 'rateInDetail'), style: TextStyle(fontSize: 13, color: AppColors.muted)),
                for (final c in RatingCategory.all)
                  Row(children: [
                    Expanded(child: Text(tr(context, 'rating${c[0].toUpperCase()}${c.substring(1)}'))),
                    StarRow(
                      keyPrefix: 'cat_${c}_',
                      stars: _cats[c] ?? 0,
                      size: 20,
                      onChanged: _saving ? null : (v) => setState(() => _cats[c] = v),
                    ),
                  ]),
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

/// One line per scored category: label and its (average) stars.
class RatingCategoryRows extends StatelessWidget {
  final Map<String, double> scores;

  const RatingCategoryRows({super.key, required this.scores});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      for (final c in RatingCategory.all)
        if (scores[c] != null)
          Row(children: [
            Expanded(child: Text(tr(context, 'rating${c[0].toUpperCase()}${c.substring(1)}'), style: TextStyle(color: AppColors.muted, fontSize: 13))),
            StarRow(stars: scores[c]!.round(), size: 16),
            const SizedBox(width: 6),
            Text(scores[c]!.toStringAsFixed(1), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
    ]);
  }
}

/// Reviews a user received: summary with category averages, then each review.
class ReviewsScreen extends StatelessWidget {
  final String userId;

  const ReviewsScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'reviewsTitle'))),
      body: LiveStream<List<Rating>>(
        stream: () => RatingService.watchReceived(userId),
        builder: (context, list) {
          if (list.isEmpty) return EmptyState(icon: Icons.star_outline_rounded, title: tr(context, 'noReviews'));
          final s = RatingSummary.of(list);
          return ListView(padding: const EdgeInsets.all(20), children: [
            AppCard(
              child: Column(children: [
                Row(children: [
                  Text(s.average.toStringAsFixed(1), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 10),
                  StarRow(stars: s.average.round(), size: 22),
                  const SizedBox(width: 8),
                  Text('(${s.count})'),
                ]),
                RatingCategoryRows(scores: s.categoryAverages),
              ]),
            ),
            for (final r in list)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    StarRow(stars: r.stars, size: 18),
                    RatingCategoryRows(scores: {for (final e in r.cats.entries) e.key: e.value.toDouble()}),
                    if (r.comment.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(r.comment)),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
