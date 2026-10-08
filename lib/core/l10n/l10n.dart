import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/language_store.dart';
import 'core_strings.dart';
import 'strings.dart';

// ============================================================
// 12-LANGUAGE SYSTEM
// ============================================================

enum AppLanguage {
  english,
  hindi,
  hinglish,
  kannada,
  tamil,
  telugu,
  marathi,
  gujarati,
  bengali,
  punjabi,
  kashmiri,
  urdu,
}

final ValueNotifier<AppLanguage> languageNotifier = ValueNotifier<AppLanguage>(
  AppLanguage.english,
);

/// Switches the UI to the language with enum [name]; unknown names are ignored.
void applyLanguageName(String? name) {
  for (final l in AppLanguage.values) {
    if (l.name == name) languageNotifier.value = l;
  }
}

/// User picked a language: apply it and remember it on device + profile.
Future<void> setAppLanguage(AppLanguage lang) {
  languageNotifier.value = lang;
  return LanguageStore.save(lang.name);
}

/// After sign-in, prefer the language saved on the profile; otherwise store
/// the one chosen on this device.
Future<void> syncLanguageAfterLogin() async {
  applyLanguageName(await LanguageStore.loadRemote());
  await LanguageStore.save(languageNotifier.value.name);
}

class LanguageInfo {
  final String nativeName;
  final String englishName;
  const LanguageInfo(this.nativeName, this.englishName);
}

const Map<AppLanguage, LanguageInfo> languageInfo = {
  AppLanguage.english: LanguageInfo('English', 'English'),
  AppLanguage.hindi: LanguageInfo('हिंदी', 'Hindi'),
  AppLanguage.hinglish: LanguageInfo('Hinglish', 'Hinglish'),
  AppLanguage.kannada: LanguageInfo('ಕನ್ನಡ', 'Kannada'),
  AppLanguage.tamil: LanguageInfo('தமிழ்', 'Tamil'),
  AppLanguage.telugu: LanguageInfo('తెలుగు', 'Telugu'),
  AppLanguage.marathi: LanguageInfo('मराठी', 'Marathi'),
  AppLanguage.gujarati: LanguageInfo('ગુજરાતી', 'Gujarati'),
  AppLanguage.bengali: LanguageInfo('বাংলা', 'Bengali'),
  AppLanguage.punjabi: LanguageInfo('ਪੰਜਾਬੀ', 'Punjabi'),
  AppLanguage.kashmiri: LanguageInfo('کٲشُر', 'Kashmiri'),
  AppLanguage.urdu: LanguageInfo('اردو', 'Urdu'),
};

class LanguageScope extends InheritedNotifier<ValueNotifier<AppLanguage>> {
  const LanguageScope({
    super.key,
    required ValueNotifier<AppLanguage> super.notifier,
    required super.child,
  });

  static AppLanguage of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LanguageScope>();
    return scope?.notifier?.value ?? AppLanguage.english;
  }
}

class T {
  /// Every UI string: the original table plus the per-feature tables in
  /// *_strings.dart files (12-item lists in [AppLanguage] order).
  ///
  /// The app name is written `{app}` in the tables and filled in here from
  /// `AppInfo` (core/app_info.dart), per language; the tagline comes from
  /// there too. Renaming the app never touches a translation.
  static final Map<String, Map<AppLanguage, String>> data = {
    for (final e in coreStrings.entries)
      e.key: {for (final l in e.value.entries) l.key: AppInfo.fill(l.value, l.key.index)},
    for (final e in extraStrings.entries)
      e.key: {
        for (var i = 0; i < AppLanguage.values.length && i < e.value.length; i++)
          AppLanguage.values[i]: AppInfo.fill(e.value[i], i),
      },
    'tagline': {for (var i = 0; i < AppLanguage.values.length; i++) AppLanguage.values[i]: AppInfo.taglines[i]},
  };

  static String get(String key, AppLanguage language) {
    return data[key]?[language] ?? data[key]?[AppLanguage.english] ?? key;
  }
}

String tr(BuildContext context, String key) =>
    T.get(key, LanguageScope.of(context));

/// [tr] with `{name}` placeholders filled from [args].
String trf(BuildContext context, String key, Map<String, Object> args) {
  var s = tr(context, key);
  args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

String trLanguageName(AppLanguage language) =>
    languageInfo[language]?.nativeName ?? 'English';
