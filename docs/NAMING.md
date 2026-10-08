# Renaming the app

The name and the tagline are written in **one place**: `lib/core/app_info.dart` (`AppInfo`). Nothing else spells the name.
The display name today is `LoadGo`. This file says what to change to use another name, and what a rename does not touch.

## How to rename (4 steps)

1. Edit `lib/core/app_info.dart`:
   * `AppInfo.name` - the display name in Latin letters.
   * `AppInfo.nameInLanguage` - how the name is written in each of the 12 languages (en, hi, hinglish, kn, ta, te, mr, gu,
     bn, pa, ks, ur). Languages that read Latin letters keep the Latin name; for the others write the name in that script.
   * `AppInfo.tagline` and `AppInfo.taglines` - the line under the name, English and the 12 translations.
   * `AppInfo.description` - one sentence for the web page and the store.
2. Run `dart run tool/apply_app_info.dart` (it prints the files it changed; `--check` only lists files that are out of date).
3. Run `flutter test test/naming_test.dart`. It fails when a file is stale or when someone typed the old name into a screen.
4. Do the things in "Not generated" below.

## What comes from `app_info.dart` by itself (no step needed)

| Where | How |
|---|---|
| Every translation (all 12 tables in `lib/core/l10n/*_strings.dart`), including the Terms and Privacy text in the app (`tosC*`, `privC*`), the welcome text, Sahayak, help, notifications | the tables write `{app}`; `T.data` in `lib/core/l10n/l10n.dart` fills it per language from `AppInfo.nameInLanguage` |
| Tagline on the splash screen (`tr('tagline')`) | `T.data` takes it from `AppInfo.taglines` |
| Splash screen, role-selection screen, `MaterialApp.title` (`lib/main.dart`) | `AppInfo.name` |
| Invoice screen and invoice PDF, share texts (`lib/core/share_text.dart`, trip share), share subject, UPI payee name, reply templates | `AppInfo.name` |

## What `dart run tool/apply_app_info.dart` writes

| File | What |
|---|---|
| `hosting/index.html`, `hosting/privacy.html`, `hosting/terms.html`, `hosting/delete-account.html`, `hosting/load.html`, `hosting/trip.html` | generated from `tool/templates/hosting/*.html` (the templates hold `{{APP_NAME}}`, `{{APP_TAGLINE}}`, `{{APP_DESCRIPTION}}`). **Edit the template, not the generated page** (to change the Terms or Privacy wording edit `tool/templates/hosting/terms.html` or `privacy.html`, then run the tool). |
| `android/app/src/main/AndroidManifest.xml` | `android:label` |
| `ios/Runner/Info.plist` | `CFBundleDisplayName`, `CFBundleName` and the location, photo, camera and microphone permission sentences |
| `web/index.html` | `<title>`, the description meta tag, `apple-mobile-web-app-title` |
| `web/manifest.json` | `name`, `short_name`, `description` |

Then deploy hosting yourself (`firebase deploy --only hosting`) when you want the pages online. A rename never deploys anything.

## Not generated (the name is not in these, or they need a person)

* **Package and bundle ids**: `pubspec.yaml` `name: transport_app`, Android `applicationId` / namespace, iOS bundle id. Changing
  an id makes a different app for the stores and for Firebase; do it only before the first release.
* **Firebase project and hosting domain**: `loadgo-defc2` (`lib/firebase_options.dart`, `firebase.json`, share links in
  `lib/core/share/share_links.dart`, the Android intent filter host in `AndroidManifest.xml`, `docs/assetlinks.template.json`).
  The links `https://loadgo-defc2.web.app/load/...` keep working after a rename. A new domain needs a new hosting site,
  a new `ShareLinks.host` and a new App Links file.
* **Icons and splash images** (`android/.../mipmap-*`, `ios/Runner/Assets.xcassets`, `web/icons`, `web/favicon.png`, `assets/`).
* **Store listings**: the Play Store title, short description, screenshots, the privacy-policy URL.
* **Documents in `docs/`** (`PRIVACY_POLICY.md`, `TERMS.md`, `PLAY_STORE_CHECKLIST.md`, the roadmap files): search and replace the old
  name by hand. They are drafts for a lawyer, not read by the app.
* **Desktop folders** (`linux/`, `macos/`, `windows/`): not shipped; they keep the project name.
* **Code names**: the class `LoadGoApp` in `lib/main.dart` and the word in code comments are names for developers, not shown.
* **Other languages**: if a new language is added, add its entry to `AppInfo.nameInLanguage` and `AppInfo.taglines` first (the
  test checks the lengths).

## The rule that keeps it this way

`test/naming_test.dart` fails when:

* a generated file is out of date (`dart run tool/apply_app_info.dart --check`);
* a translation table spells the name instead of `{app}`;
* a quoted string anywhere in `lib/` (outside `app_info.dart`) contains the name;
* a hosting page has a leftover `{{` token.

So a new screen, text or share message must use `AppInfo.name` (or `{app}` in a translation), never the name itself.
