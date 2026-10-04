/// Per-feature translation tables, merged into `T.data` in main.dart.
///
/// Each value is a 12-item list in `AppLanguage` order:
/// en, hi, hinglish, kn, ta, te, mr, gu, bn, pa, ks, ur.
library;

import 'auth_strings.dart';

const List<Map<String, List<String>>> stringTables = [
  authStrings,
];

final Map<String, List<String>> extraStrings = {
  for (final table in stringTables) ...table,
};
