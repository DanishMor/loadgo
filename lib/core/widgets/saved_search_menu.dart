import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/saved_search.dart';
import '../services/saved_search_service.dart';
import 'common.dart';
import 'live_stream.dart';

/// "Save this search" and "Saved searches" buttons for a filter. [currentFilter]
/// returns the stored form of the filter in use; [onApply] gets a saved one.
class SavedSearchMenu extends StatelessWidget {
  final String kind;
  final bool canSave;
  final Map<String, Object?> Function() currentFilter;
  final void Function(Map<String, dynamic> filter) onApply;

  const SavedSearchMenu({super.key, required this.kind, required this.canSave, required this.currentFilter, required this.onApply});

  Future<void> _save(BuildContext context) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(c, 'saveSearch')),
        content: TextField(key: const ValueKey('searchName'), controller: ctrl, maxLength: 40, autofocus: true, decoration: InputDecoration(labelText: tr(c, 'searchName'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr(c, 'cancel'))),
          FilledButton(key: const ValueKey('searchNameOk'), onPressed: () => Navigator.pop(c, ctrl.text), child: Text(tr(c, 'save'))),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    try {
      await SavedSearchService.save(kind: kind, name: name, filter: currentFilter());
      if (context.mounted) showSnack(context, tr(context, 'searchSaved'));
    } on SearchLimitException {
      if (context.mounted) showSnack(context, tr(context, 'searchLimit'));
    }
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<SavedSearch>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: LiveStream<List<SavedSearch>>(
          stream: () => SavedSearchService.watch(kind),
          builder: (c, list) {
            if (list.isEmpty) return Padding(padding: const EdgeInsets.all(24), child: Text(tr(c, 'noSavedSearches')));
            return ListView(shrinkWrap: true, children: [
              for (final s in list)
                ListTile(
                  key: ValueKey('savedSearch_${s.id}'),
                  title: Text(s.name),
                  onTap: () => Navigator.pop(c, s),
                  trailing: IconButton(
                    key: ValueKey('deleteSearch_${s.id}'),
                    tooltip: tr(c, 'removeFromList'),
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => SavedSearchService.delete(s.id),
                  ),
                ),
            ]);
          },
        ),
      ),
    );
    if (picked != null) onApply(picked.filter);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 4, children: [
      TextButton.icon(
        key: const ValueKey('saveSearch'),
        onPressed: canSave ? () => _save(context) : null,
        icon: const Icon(Icons.bookmark_add_outlined, size: 18),
        label: Text(tr(context, 'saveSearch')),
      ),
      TextButton.icon(
        key: const ValueKey('openSavedSearches'),
        onPressed: () => _open(context),
        icon: const Icon(Icons.bookmarks_outlined, size: 18),
        label: Text(tr(context, 'savedSearches')),
      ),
    ]);
  }
}
