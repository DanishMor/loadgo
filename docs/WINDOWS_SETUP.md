# Windows laptop setup (LoadGo)

Project folder: `C:\projects\loadgo`. Use PowerShell. Nothing secret is stored here.

## 1. Tools
- Flutter SDK (stable) on PATH, `flutter doctor` green for Android toolchain and Chrome.
- Android Studio with Android SDK, platform-tools and NDK. Accept licenses: `flutter doctor --android-licenses`.
- JDK: the one bundled with Android Studio (`jbr`) is enough. For the rules tests `java -version` must work (Firebase emulator).
- Node.js for `firestore_rules_test` (`npm install`, `npm test`).

## 2. Build
- `flutter build apk --debug` (first run downloads Gradle and dependencies; needs internet).
- A broken NDK shows as a missing `source.properties`. Delete only that NDK version folder under `%LOCALAPPDATA%\Android\sdk\ndk\` and build again; it is downloaded again.
- `android/app/build.gradle.kts` starts with `import java.util.Properties`. Without it Kotlin resolves `java` to Gradle's `java` extension and the build fails with "Unresolved reference 'util'".
- `android/gradle.properties` uses `-Xmx4g` (laptop has about 16 GB). The old `-Xmx1024m` ran out of Java heap space. With 8 GB RAM use `-Xmx2g` or `-Xmx3g`.

## 3. Why one build took 2.5+ hours
- The failing build log was `Could not GET https://dl.google.com/... No such host is known`: the laptop lost internet (DNS) in the middle, and Gradle retried every artifact. This was the real cause, not RAM, the NDK or antivirus.
- The first build also ran out of heap (1 GB) and was killed after about 22 minutes.
- With internet and 4 GB heap the debug build takes about 100 to 270 seconds.
- Before a long build check `Test-NetConnection google.com -Port 443` and that no old `java`/`dart` process is running (`Get-Process java,dart`).

## 4. Phone or emulator
- Phone: USB debugging on, USB mode File transfer, tap Allow on the phone, `adb devices` must say `device` (not `unauthorized`).
- The test emulator (Android 16, 2 GB RAM) crashed while installing the 216 MB debug APK. Give the AVD 4 GB RAM, cold boot it, or use a real phone.

## 5. Git
- Generated plugin files (linux, macos, windows `generated_plugin_registrant.*`, `generated_plugins.cmake`, `GeneratedPluginRegistrant.swift`) are kept LF by `.gitattributes`; they should not show as modified. Do not commit them if they do.
- `git push` uses the account saved in Windows Credential Manager. It must have write access to the repo (see BLOCKED.md).
- Firebase CLI: run `firebase login:use <account>` for the account that owns the project. Deploys are done by the owner only.

## 6. PowerShell
- Scripts may be blocked: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.
- Use PowerShell syntax, not bash (`Get-Content -Tail`, `Select-String`).
