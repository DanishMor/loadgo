/// Goods LoadGo refuses to carry. Matching is word-based and case-insensitive
/// on what the customer types (notes / description). Keep in sync with the
/// regex in firestore.rules (`prohibitedText`).
library;

const List<String> prohibitedCargo = [
  'explosive',
  'explosives',
  'dynamite',
  'detonator',
  'gunpowder',
  'firearm',
  'firearms',
  'gun',
  'guns',
  'pistol',
  'rifle',
  'ammunition',
  'bullets',
  'grenade',
  'narcotics',
  'drugs',
  'ganja',
  'charas',
  'heroin',
  'cocaine',
  'opium',
  'radioactive',
  'ivory',
  'counterfeit',
  'fake currency',
  'wildlife',
  'animal skin',
  'fireworks',
  'crackers',
  'patakhe',
  'human remains',
];

/// The first prohibited item mentioned in [text], or null.
String? prohibitedCargoMatch(String text) {
  final t = ' ${text.toLowerCase().replaceAll(RegExp(r'[^a-z ]'), ' ').replaceAll(RegExp(r'\s+'), ' ')} ';
  for (final item in prohibitedCargo) {
    if (t.contains(' $item ')) return item;
  }
  return null;
}
