# Android release (MASTER-6 Task 43)

The app name stays LoadGo. The store id is still the placeholder `com.example.transport_app`; Play Store will not accept `com.example.*`, so change it before the first upload.

## Change the package id (one place)
1. Edit `android/gradle.properties`: `loadgo.applicationId=com.yourcompany.loadgo`.
2. In the Firebase console add an Android app with that id, download the new `google-services.json` to `android/app/` (replace the old one).
3. Add the new release (and debug) SHA-1 and SHA-256 to that Firebase app (needed for phone sign-in checks).
4. Update `hosting/.well-known/assetlinks.json` (template: `docs/assetlinks.template.json`) with the new id and the release SHA-256, then ask for a hosting deploy.
5. Deep links in `AndroidManifest.xml` use the web host, not the id, so they need no change.
The Kotlin `namespace` (`com.example.transport_app`) is only the code package; leave it unless you also move `MainActivity.kt`.

## Sign the release build
1. `keytool -genkey -v -keystore ~/loadgo-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias loadgo` (keep the file and passwords safe; losing them means you cannot update the app. Play App Signing lets Google keep the real key).
2. Create `android/key.properties` (it is git-ignored, never commit it):
   ```
   storeFile=/home/you/loadgo-release.jks
   storePassword=...
   keyAlias=loadgo
   keyPassword=...
   ```
3. `flutter build appbundle --release` (upload the `.aab`) or `flutter build apk --release`.
Without `key.properties` a release build is signed with the debug key and Play will reject it.

## Shrinking
Release builds use R8 (`isMinifyEnabled`, `isShrinkResources`). Rules are in `android/app/proguard-rules.pro`. This could not be built here (no Android SDK), so install a release APK on a real phone and open: login, a call, a map link, and Crashlytics before uploading. If something crashes with a missing class, add a keep rule and note why.

## Permissions (all used; a test keeps the list honest)
| Permission | Why |
|---|---|
| INTERNET, ACCESS_NETWORK_STATE | Firebase, online/offline strip |
| ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION | trip tracking, nearest loads (asked with an explanation first) |
| POST_NOTIFICATIONS | phone alerts (Android 13+; asked with an explanation first) |
| RECORD_AUDIO | in-app voice call, voice input, Test my microphone |
| MODIFY_AUDIO_SETTINGS, CHANGE_NETWORK_STATE | speaker / call audio routing (flutter_webrtc) |
No camera, contacts, SMS, storage or phone-state permission is declared. Photos use the system picker.

## Icons
The launcher icons in `android/app/src/main/res/mipmap-*` are placeholders. To replace: make a 1024x1024 PNG, then either use Android Studio > Image Asset (Launcher Icons, adaptive) or add `flutter_launcher_icons` and run it (not added here to keep dependencies small). Check the icon on a dark and a light launcher.
