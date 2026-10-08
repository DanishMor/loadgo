import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/rating.dart';
import '../core/services/rating_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Admin > Low ratings: every rating under 3 stars, open ones first.
class AdminRatingFlagsScreen extends StatelessWidget {
  const AdminRatingFlagsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'adminRatingFlags'))),
      body: LiveStream<List<RatingFlag>>(
        stream: RatingService.watchFlags,
        builder: (context, list) {
          if (list.isEmpty) return EmptyState(icon: Icons.star_half_rounded, title: tr(context, 'flagNone'));
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final f = list[i];
              return AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(trf(context, 'ratingFlagLine', {'stars': f.stars, 'rater': f.raterId, 'rated': f.ratedId}),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(f.bookingId, style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  _CommentRow(flag: f),
                  if (f.status == RatingFlag.open)
                    Wrap(spacing: 8, children: [
                      FilledButton(
                        key: ValueKey('flagReviewed_${f.id}'),
                        onPressed: () => RatingService.resolveFlag(f.id, RatingFlag.reviewed),
                        child: Text(tr(context, 'flagMarkReviewed')),
                      ),
                      TextButton(
                        key: ValueKey('flagDismiss_${f.id}'),
                        onPressed: () => RatingService.resolveFlag(f.id, RatingFlag.dismissed),
                        child: Text(tr(context, 'flagDismiss')),
                      ),
                    ])
                  else
                    Text(f.status, style: TextStyle(color: AppColors.muted)),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}

/// The rating's comment under the flag, with Hide comment (MASTER-5 Task 33).
class _CommentRow extends StatefulWidget {
  final RatingFlag flag;
  const _CommentRow({required this.flag});

  @override
  State<_CommentRow> createState() => _CommentRowState();
}

class _CommentRowState extends State<_CommentRow> {
  late final Future<DocumentSnapshot<Map<String, dynamic>>> _doc = RatingService.ratingDoc(widget.flag.id);
  bool _hidden = false;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _doc,
      builder: (context, snap) {
        final d = snap.data?.data();
        if (d == null) return const SizedBox.shrink();
        final comment = d['comment'] as String? ?? '';
        if (d['moderated'] == true || _hidden) {
          return Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr(context, 'ratingCommentHidden'), style: TextStyle(color: AppColors.muted, fontStyle: FontStyle.italic)));
        }
        if (comment.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('\u201c$comment\u201d', key: ValueKey('flagComment_${widget.flag.id}')),
            TextButton(
              key: ValueKey('flagHide_${widget.flag.id}'),
              onPressed: () async {
                await RatingService.hideComment(widget.flag.id);
                if (mounted) setState(() => _hidden = true);
              },
              child: Text(tr(context, 'ratingHideComment')),
            ),
          ]),
        );
      },
    );
  }
}
