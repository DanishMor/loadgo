# Renaming the app with the script (P1)

`tool/rename_app.ps1` does the steps of `docs/NAMING.md` in one go. It lists first and writes only when you say so.

```powershell
# 1. Look (default, writes nothing)
.\tool\rename_app.ps1 -Name "NewName" -Tagline "Truck & Cargo Booking" -PackageId "in.newname.app"
# 2. Apply
.\tool\rename_app.ps1 -Name "NewName" -Tagline "Truck & Cargo Booking" -PackageId "in.newname.app" -DryRun false
# 3. Check
flutter test test/naming_test.dart
```

What it edits: `lib/core/app_info.dart` (name and English tagline), `android/gradle.properties` (`loadgo.applicationId`, only with `-PackageId`), the plain-text name in `README.md` and `docs/PLAY_*.md`. Then it runs `dart run tool/apply_app_info.dart`, which writes the AndroidManifest label, `web/index.html`, `web/manifest.json`, `hosting/*.html` and the iOS Info.plist. Every `{app}` in the 12 languages follows `AppInfo` by itself. The script never deploys and never touches keys or `google-services.json`.

By hand after it: `AppInfo.nameInLanguage` and `AppInfo.taglines` for hi, kn, ta, te, mr, gu, bn, pa, ks, ur still hold the old name in their own script; write the new name there (a person who reads that script should check it).

## Changing the package id (important)

The package id is the Android identity of the app. Changing it means:

1. Register a **new Android app** in the Firebase project (Project settings > Your apps > Add app > Android) with the new package id. The old app keeps working, it is a separate entry.
2. Download the **new `google-services.json`** and put it in `android/app/`.
3. Add the **new SHA-1 and SHA-256** (debug now, and the release/upload key later; Play App Signing adds its own, see `docs/SIGNING.md`) to that new app.
4. Restrict the API key to the new package + SHA (`docs/FIREBASE_CONSOLE_CHECKLIST.md`).
5. Rebuild; phone login (OTP) and Google sign-in work only after steps 1 to 3.

Because Play Store ties an app to its package id forever, **fix the package id before the first Play Store upload**. The name can be changed later; the package id cannot. The Kotlin namespace in `android/app/build.gradle.kts` is the code package and does not change with it.
