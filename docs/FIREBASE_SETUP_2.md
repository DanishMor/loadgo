# Firebase setup 2: Crashlytics, Analytics, Remote Config, app control

All four are free on the Spark plan. The code is already wired (Task 42); these are the console steps.

## 1. google-services
1. Firebase Console > Project settings > Your apps > Android. Package name must match `applicationId` in `android/app/build.gradle.kts` (now `com.example.transport_app`; change both together before Play Store).
2. Download `google-services.json` into `android/app/` (already there for `loadgo-defc2`).
3. Add your release and debug SHA-1/SHA-256 (needed for phone auth).
4. Gradle plugins are in `android/settings.gradle.kts` (`google-services`, `firebase.crashlytics`) and applied in `android/app/build.gradle.kts`.

## 2. Crashlytics
1. Console > Release & Monitor > Crashlytics > Enable.
2. `CrashService.init` hooks `FlutterError.onError` and `PlatformDispatcher.onError`; reporting is on in release builds only (debug builds only print).
3. Test: in a release build throw a test exception once, wait a few minutes, check the dashboard.

## 3. Analytics
1. Console > Analytics is on by default with the project.
2. `AnalyticsEvents` sends only screen and event names with short coded values. Never put names, phones, addresses or amounts in a parameter.
3. In Play Console data safety, declare "App activity" and "Diagnostics" as collected, not linked to identity.

## 4. Remote Config (force update, maintenance, feature flags)
Create these parameters in Console > Remote Config and publish. Defaults are in `AppControlService.remoteDefaults`; the fetch interval is 1 hour.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `min_version_code` | Number | 0 | builds below this see the update screen (0 = off) |
| `maintenance` | Boolean | false | true shows the maintenance screen |
| `maintenance_message` | String | empty | shown on the maintenance screen (empty = default text, 300 chars max) |
| `feature_flags` | JSON string | `{}` | e.g. `{"surge": true}`; read with `FeatureFlags.isOn('surge')` |

A parameter left at its default does not override the Firestore fallback.

## 5. Firestore fallback `config/app`
Same fields in camelCase: `minVersionCode` (number), `maintenance` (bool), `maintenanceMessage` (string), `flags` (map of bool). Signed-in users read it; only a super admin writes it (rules `config/{docId}`; test in `rules.test.mjs`). Rules are not deployed by the run.

## Notes
- The current build number comes from `package_info_plus` (the `+N` in `pubspec.yaml`, also `appVersion`). Raise `version:` for every Play upload.
- Everything is a safe no-op when Firebase is unavailable, so tests and the web run unchanged.
- To block old builds: publish the new build, then set `min_version_code` to its number.
