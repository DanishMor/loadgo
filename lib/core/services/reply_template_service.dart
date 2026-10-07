
import '../admin/reply_templates.dart';
import 'admin_console_service.dart';
import 'backend.dart';

class TemplateException implements Exception {
  /// 'empty', 'long' or 'limit'.
  final String reason;
  TemplateException(this.reason);
  @override
  String toString() => 'TemplateException($reason)';
}

/// Support reply templates in `config/reply_templates` ({items: [{id, title,
/// text}]}). Everyone signed in can read the config (rules); only super
/// admins write it, with an audit row from [AdminConsoleService.writeConfig].
class ReplyTemplateService {
  ReplyTemplateService._();

  static const docId = 'reply_templates';

  /// The saved templates, or the built-in ones while none were ever saved.
  static Future<List<ReplyTemplate>> load() async {
    try {
      final snap = await Backend.db.collection('config').doc(docId).get();
      if (!snap.exists) return ReplyTemplate.defaults;
      return ReplyTemplate.parse(snap.data());
    } catch (_) {
      return ReplyTemplate.defaults;
    }
  }

  static Future<void> _save(List<ReplyTemplate> list) =>
      AdminConsoleService.writeConfig(docId, {'items': [for (final t in list) t.toMap()]});

  /// Adds a template, or replaces the one with [id].
  static Future<List<ReplyTemplate>> upsert({String? id, required String title, required String text}) async {
    final problem = ReplyTemplate.check(title, text);
    if (problem != null) throw TemplateException(problem);
    final list = [...await load()];
    final i = id == null ? -1 : list.indexWhere((t) => t.id == id);
    final t = ReplyTemplate(id: id ?? '${DateTime.now().microsecondsSinceEpoch}', title: title.trim(), text: text.trim());
    if (i >= 0) {
      list[i] = t;
    } else {
      if (list.length >= ReplyTemplate.maxTemplates) throw TemplateException('limit');
      list.add(t);
    }
    await _save(list);
    return list;
  }

  static Future<List<ReplyTemplate>> remove(String id) async {
    final list = [for (final t in await load()) if (t.id != id) t];
    await _save(list);
    return list;
  }
}
