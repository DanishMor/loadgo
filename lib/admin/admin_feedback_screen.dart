import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/services/feedback_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Admin > Feedback: what people sent from Help, newest first.
class AdminFeedbackScreen extends StatelessWidget {
  const AdminFeedbackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'adminFeedback'))),
      body: LiveStream<List<FeedbackEntry>>(
        stream: FeedbackService.watch,
        builder: (context, list) {
          if (list.isEmpty) return EmptyState(icon: Icons.rate_review_outlined, title: tr(context, 'fbNone'));
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final f = list[i];
              return AppCard(
                key: ValueKey('fb_${f.id}'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    for (var s = 1; s <= 5; s++) Icon(s <= f.rating ? Icons.star_rounded : Icons.star_border_rounded, size: 18, color: const Color(0xFFF59E0B)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(tr(context, 'fbCat_${f.category}'), style: const TextStyle(fontWeight: FontWeight.w700))),
                  ]),
                  if (f.text.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(f.text)),
                  const SizedBox(height: 4),
                  Text('${f.role} · ${f.appVersion} · ${formatDate(f.createdAt)}', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
