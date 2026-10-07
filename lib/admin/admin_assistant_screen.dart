import 'package:flutter/material.dart';

import '../core/assistant/assistant_log_service.dart';
import '../core/l10n/l10n.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Admin > Sahayak questions: what the assistant did not understand.
class AdminAssistantScreen extends StatelessWidget {
  const AdminAssistantScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'adminAssistant'))),
      body: LiveStream<List<UnknownQuestion>>(
        stream: AssistantLogService.watch,
        builder: (context, list) {
          if (list.isEmpty) return EmptyState(icon: Icons.chat_bubble_outline_rounded, title: tr(context, 'asAdminEmpty'));
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final q = list[i];
              return AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(q.text, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(trf(context, 'asAdminMeta', {'role': q.role, 'language': q.language}), style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  if (q.resolved)
                    Text(tr(context, 'asAdminResolved'), key: ValueKey('asResolved_${q.id}'), style: TextStyle(color: AppColors.muted))
                  else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        key: ValueKey('asResolve_${q.id}'),
                        onPressed: () => AssistantLogService.resolve(q.id),
                        child: Text(tr(context, 'asAdminMarkResolved')),
                      ),
                    ),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
