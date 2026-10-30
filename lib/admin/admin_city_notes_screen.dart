import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/errors/error_text.dart';
import '../core/l10n/l10n.dart';
import '../core/pricing/city_notes.dart';
import '../core/theme/design_tokens.dart';
import '../core/widgets/common.dart';
import '../core/widgets/ds/app_top_bar.dart';
import '../core/widgets/ds/skeleton.dart';

/// E33 (flag cityNotes): super admins write short notes per city (for example truck entry hours). Customers see the
/// words as written in the booking route step. Write only what is known and checked; the app adds nothing.
class AdminCityNotesScreen extends StatefulWidget {
  final Future<CityNotes> Function()? load;
  final Future<void> Function(CityNotes notes)? save;
  const AdminCityNotesScreen({super.key, this.load, this.save});

  @override
  State<AdminCityNotesScreen> createState() => _AdminCityNotesScreenState();
}

class _AdminCityNotesScreenState extends State<AdminCityNotesScreen> {
  Map<String, String>? _notes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    CityNotesService.reset();
    (widget.load ?? CityNotesService.load)().then((n) {
      if (mounted) setState(() => _notes = {...n.notes});
    }, onError: (_) {
      if (mounted) setState(() => _notes = {});
    });
  }

  Future<void> _persist(Map<String, String> next) async {
    final before = _notes;
    setState(() {
      _notes = next;
      _saving = true;
    });
    try {
      await (widget.save ?? CityNotesService.save)(CityNotes(next));
      if (mounted) showSnack(context, tr(context, 'featSaved'));
    } catch (e) {
      if (mounted) {
        setState(() => _notes = before);
        showSnack(context, errorText(context, e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit([String? city]) async {
    final got = await showDialog<(String, String)>(context: context, builder: (_) => _NoteDialog(city: city, note: city == null ? '' : _notes![city]!));
    if (got == null || !mounted) return;
    final (name, text) = got;
    if (name.trim().length < 2 || text.trim().isEmpty) return;
    if (city == null && _notes!.length >= CityNotes.maxCities) {
      showSnack(context, tr(context, 'cnTooMany'));
      return;
    }
    final next = {..._notes!}..remove(city);
    next[name.trim()] = text.trim();
    await _persist(next);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final notes = _notes;
    return Scaffold(
      appBar: AppTopBar(title: tr(context, 'cnTitle')),
      floatingActionButton: notes == null ? null : FloatingActionButton.extended(key: const ValueKey('cnAdd'), onPressed: _saving ? null : () => _edit(), icon: const Icon(Icons.add_rounded), label: Text(tr(context, 'cnAdd'))),
      body: notes == null
          ? const Padding(padding: EdgeInsets.all(DsSpace.gutter), child: SkeletonList(count: 3))
          : ListView(padding: const EdgeInsets.fromLTRB(DsSpace.gutter, DsSpace.gutter, DsSpace.gutter, 96), children: [
              Text(tr(context, 'cnHelp'), style: DsType.bodySmall.copyWith(color: c.textMuted)),
              const SizedBox(height: DsSpace.s3),
              if (notes.isEmpty) Text(tr(context, 'cnNone'), key: const ValueKey('cnNone'), style: DsType.body.copyWith(color: c.textMuted)),
              for (final e in (notes.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
                Padding(
                  padding: const EdgeInsets.only(bottom: DsSpace.s2),
                  child: AppCard(
                    key: ValueKey('cn_${e.key}'),
                    onTap: _saving ? null : () => _edit(e.key),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(e.key, style: DsType.subtitle.copyWith(color: c.textStrong)),
                          Text(e.value, style: DsType.bodySmall.copyWith(color: c.text)),
                        ]),
                      ),
                      IconButton(
                        key: ValueKey('cnDelete_${e.key}'),
                        tooltip: tr(context, 'cnDelete'),
                        onPressed: _saving ? null : () => _persist({...notes}..remove(e.key)),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ]),
                  ),
                ),
            ]),
    );
  }
}

class _NoteDialog extends StatefulWidget {
  final String? city;
  final String note;
  const _NoteDialog({this.city, this.note = ''});

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _city = TextEditingController(text: widget.city ?? '');
  late final _note = TextEditingController(text: widget.note);

  @override
  void dispose() {
    _city.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(key: const ValueKey('cnCity'), controller: _city, decoration: InputDecoration(labelText: tr(context, 'cnCity')), inputFormatters: [LengthLimitingTextInputFormatter(60)]),
            TextField(key: const ValueKey('cnNote'), controller: _note, maxLines: 4, decoration: InputDecoration(labelText: tr(context, 'cnNote')), inputFormatters: [LengthLimitingTextInputFormatter(CityNotes.maxChars)]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr(context, 'cancel'))),
          FilledButton(key: const ValueKey('cnSave'), onPressed: () => Navigator.pop(context, (_city.text, _note.text)), child: Text(tr(context, 'hlDone'))),
        ],
      );
}
