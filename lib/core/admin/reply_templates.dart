import '../app_info.dart';
/// A canned support reply an admin can drop into a ticket answer.
class ReplyTemplate {
  final String id;
  final String title;
  final String text;
  const ReplyTemplate({required this.id, required this.title, required this.text});

  static const maxTemplates = 20;
  static const maxTitle = 40;
  static const maxText = 500;

  Map<String, String> toMap() => {'id': id, 'title': title, 'text': text};

  /// Null for anything that is not a usable template.
  static ReplyTemplate? fromMap(Object? m) {
    if (m is! Map) return null;
    final id = m['id'], title = m['title'], text = m['text'];
    if (id is! String || title is! String || text is! String) return null;
    if (id.isEmpty || title.trim().isEmpty || text.trim().isEmpty) return null;
    return ReplyTemplate(id: id, title: title.trim(), text: text.trim());
  }

  /// The valid templates of a `config/reply_templates` document (at most [maxTemplates]).
  static List<ReplyTemplate> parse(Map<String, dynamic>? doc) {
    final raw = doc?['items'];
    if (raw is! List) return const [];
    return [for (final m in raw) ?fromMap(m)].take(maxTemplates).toList();
  }

  /// Used while the config document does not exist.
  static const defaults = [
    ReplyTemplate(id: 'looking', title: 'Looking into it', text: 'Thank you for contacting ${AppInfo.name}. We are looking into this and will update you soon.'),
    ReplyTemplate(id: 'booking_id', title: 'Need booking details', text: 'Please share the booking details (pickup, drop and date) so that we can check this quickly.'),
    ReplyTemplate(id: 'fixed', title: 'Issue fixed', text: 'This has been fixed from our side. Please check and let us know if you still face the problem.'),
    ReplyTemplate(id: 'closing', title: 'Closing the ticket', text: 'We are closing this ticket. You can open a new one any time if you need more help.'),
  ];

  /// Why [title] / [text] cannot be saved, or null when they can.
  static String? check(String title, String text) {
    final t = title.trim(), x = text.trim();
    if (t.isEmpty || x.isEmpty) return 'empty';
    if (t.length > maxTitle || x.length > maxText) return 'long';
    return null;
  }
}
