# Dependency audit (Part 5, H8 and H14)

Date: 2026-10-19. Nothing was upgraded: with no real phone to test on, an update of a native plugin is a risk with no way to prove it, and the rules of this work allow only compatible patch and minor updates.

## Flutter packages
- `flutter pub outdated`: 18 locked packages have a newer compatible version (patch and minor, for example `firebase_*_platform_interface` 3.0.7 to 3.0.8, `geolocator_android` 5.1.1 to 5.2.0, `shared_preferences_android` 2.4.28 to 2.5.0, `image` 4.10.1 to 4.12.0, `meta`, `petitparser`, `xml`). 30 more are held back by version limits in `pubspec.yaml` (majors: `qr` 4.0.0, `nm`, and similar).
- No package is discontinued or abandoned in the list. There is no WebView package (guard: `test/untrusted_input_test.dart`).
- Plan for the owner: after the phone test sheet is done on one phone, run `flutter pub upgrade` (compatible versions only), run the whole test suite in batches and the phone sheet again, and commit `pubspec.lock`. Never `--major-versions` without a separate plan.
- Biggest by size: the WebRTC plugin (`flutter_webrtc`) native libraries, see `docs/PERFORMANCE.md` (use the app bundle).
- Plugins that still apply the Kotlin Gradle Plugin (cloud_functions, firebase_*, flutter_webrtc) print a build warning about "built-in Kotlin". It is a warning about a future Flutter version, not a security issue; the fix is in the plugins' next releases.

## npm
- `functions/`: `npm audit` 0 vulnerabilities; runtime dependencies are only `firebase-admin` and `firebase-functions`; `engines.node` 22; lockfile committed.
- `firestore_rules_test/` (test tools, never deployed): 16 findings (4 moderate, 12 high) in `firebase`, `firebase-tools` and what they pull in (`braces`, `chokidar`, `basic-ftp`, `proxy-agent`, `uuid` ...). They affect a developer's machine when running the tools, not users. A fix needs major versions of `firebase-tools` and the web SDK; schedule it as its own task and run the whole rules suite after it.

## GitHub Actions (`.github/workflows/ci.yml`)
- Third-party actions are pinned to full commit hashes with the version in a comment (`actions/checkout` 4.3.1, `actions/setup-node` 4.4.0, `actions/setup-java` 4.9.1, `subosito/flutter-action` 2.9.1). A moved tag can no longer change what runs.
- `permissions: contents: read` for the whole workflow, a concurrency group that cancels older runs, and a 45-minute limit per job.
- No secret is used by the workflow; nothing is deployed from CI.
- To update a pinned action: look up the new tag's commit hash (`git ls-remote --tags https://github.com/<owner>/<repo>`), replace both the hash and the comment.
