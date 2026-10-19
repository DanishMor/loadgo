import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'breadcrumbs.dart';

/// Part 5 (H17): one damaged document must not blank a whole list.
///
/// Most models read a field with `as String?`, which throws when an old or hand-edited document holds another type.
/// Reading a list with [parse] skips such a document and keeps the rest. The count of skipped documents is printed
/// (no data) so it shows up in the debug log and the tests.
extension SafeDocs on Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> {
  List<T> parse<T>(T Function(QueryDocumentSnapshot<Map<String, dynamic>> doc) make) {
    final out = <T>[];
    var skipped = 0;
    for (final d in this) {
      try {
        out.add(make(d));
      } catch (_) {
        skipped++;
      }
    }
    if (skipped > 0) {
      SafeDocsStats.skipped += skipped;
      debugPrint(Redactor.safe('Skipped $skipped damaged document(s) while reading a list'));
    }
    return out;
  }
}

class SafeDocsStats {
  SafeDocsStats._();

  /// Documents skipped since the app started (tests read it).
  static int skipped = 0;
}
