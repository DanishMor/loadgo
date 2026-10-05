import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/repeat.dart';
import '../core/services/repeat_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import 'post_load_screen.dart';

/// Saved loads the customer posts again and again. "Use" opens Post Load
/// filled in (no date); the pickup date is always chosen fresh.
class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key});

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  late final Stream<List<LoadTemplate>> _templates = RepeatService.watchTemplates().asBroadcastStream();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'templatesTitle'))),
      body: LiveStream<List<LoadTemplate>>(
        stream: () => _templates,
        builder: (context, list) {
          if (list.isEmpty) {
            return EmptyState(icon: Icons.bookmarks_outlined, title: tr(context, 'templatesNone'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final t = list[i];
              return Card(
                child: ListTile(
                  key: ValueKey('template_${t.id}'),
                  title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${t.pickup} → ${t.drop}\n${t.cargoType} · ${t.vehicleType}'),
                  isThreeLine: true,
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute<bool>(builder: (_) => PostLoadScreen(repostFrom: t.toLoadDraft()))),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    TextButton(
                      onPressed: () => Navigator.of(context)
                          .push(MaterialPageRoute<bool>(builder: (_) => PostLoadScreen(repostFrom: t.toLoadDraft()))),
                      child: Text(tr(context, 'useTemplate')),
                    ),
                    IconButton(
                      key: ValueKey('deleteTemplate_${t.id}'),
                      tooltip: tr(context, 'removeFromList'),
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => RepeatService.deleteTemplate(t.id),
                    ),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
