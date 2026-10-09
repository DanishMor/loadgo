import '../core/errors/error_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/admin/reply_templates.dart';
import '../core/l10n/l10n.dart';
import '../core/services/reply_template_service.dart';
import '../core/widgets/common.dart';

/// Admin > Reply templates (super admin): the canned answers offered in the
/// ticket reply box.
class AdminTemplatesScreen extends StatefulWidget {
  const AdminTemplatesScreen({super.key});

  @override
  State<AdminTemplatesScreen> createState() => _AdminTemplatesScreenState();
}

class _AdminTemplatesScreenState extends State<AdminTemplatesScreen> {
  late Future<List<ReplyTemplate>> _list = ReplyTemplateService.load();

  void _reload() => setState(() {
        _list = ReplyTemplateService.load();
      });

  Future<void> _edit([ReplyTemplate? t]) async {
    final title = TextEditingController(text: t?.title ?? '');
    final text = TextEditingController(text: t?.text ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(c, t == null ? 'tplAdd' : 'tplEdit')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              key: const ValueKey('tplTitle'),
              controller: title,
              inputFormatters: [LengthLimitingTextInputFormatter(ReplyTemplate.maxTitle)],
              decoration: InputDecoration(labelText: tr(c, 'tplTitle')),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('tplText'),
              controller: text,
              maxLines: 5,
              inputFormatters: [LengthLimitingTextInputFormatter(ReplyTemplate.maxText)],
              decoration: InputDecoration(labelText: tr(c, 'tplText')),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr(c, 'cancel'))),
          FilledButton(key: const ValueKey('tplSave'), onPressed: () => Navigator.pop(c, true), child: Text(tr(c, 'save'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ReplyTemplateService.upsert(id: t?.id, title: title.text, text: text.text);
      if (mounted) _reload();
    } on TemplateException catch (e) {
      if (mounted) showSnack(context, tr(context, e.reason == 'limit' ? 'tplLimit' : 'tplInvalid'));
    } catch (error) {
      if (mounted) showSnack(context, errorText(context, error));
    }
  }

  Future<void> _delete(ReplyTemplate t) async {
    try {
      await ReplyTemplateService.remove(t.id);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) showSnack(context, errorText(context, error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'adminTemplates'))),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('tplAdd'),
        onPressed: () => _edit(),
        icon: const Icon(Icons.add_rounded),
        label: Text(tr(context, 'tplAdd')),
      ),
      body: FutureBuilder<List<ReplyTemplate>>(
        future: _list,
        builder: (context, snap) {
          final list = snap.data;
          if (list == null) return const Center(child: CircularProgressIndicator());
          if (list.isEmpty) return EmptyState(icon: Icons.quickreply_outlined, title: tr(context, 'tplNone'));
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final t = list[i];
              return AppCard(
                key: ValueKey('tpl_${t.id}'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(t.text, maxLines: 3, overflow: TextOverflow.ellipsis),
                  Wrap(alignment: WrapAlignment.end, children: [
                    TextButton(key: ValueKey('tplEdit_${t.id}'), onPressed: () => _edit(t), child: Text(tr(context, 'tplEdit'))),
                    TextButton(key: ValueKey('tplDelete_${t.id}'), onPressed: () => _delete(t), child: Text(tr(context, 'tplDelete'))),
                  ]),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
