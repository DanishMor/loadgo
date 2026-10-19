# Baseline before hardening (Part 5, H0)

Taken on 2026-10-19 at tag `pre-hardening`.

| Item | Number |
|---|---|
| Flutter test files / test cases | 305 / about 2326 (`test` and `testWidgets` calls) |
| Rules tests (emulator) | storage 13, generated matrix 167, rules slices 116 + 114 + 126 + 158 |
| Functions | 46 exports (`functions/index.js`), unit tests 38, emulator tests 161, 22 source files, about 3100 lines |
| `firestore.rules` / `storage.rules` | 4008 lines / 89 lines; 98 collection `match` blocks |
| Release APK (arm64 only, `flutter build apk --release --analyze-size --target-platform android-arm64`) | 66.6 MB (an earlier universal APK on 10 Oct: 119.8 MB) |
| Live listeners | 137 `.snapshots()` call sites; 68 `StreamBuilder`s; busiest files: `admin_console_service` 10, `driver_extras_service` 8, `chat_screen` 6 |
| Collections used by the app | 98 (top level) |
| npm audit | functions: 0 vulnerabilities; `firestore_rules_test` (dev tools only): 16 (4 moderate, 12 high), all in `firebase`, `firebase-tools` and their dependencies, not shipped |
| `flutter analyze` | 0 issues (last full run at U44) |

Notes
- The APK `--analyze-size` flag cannot be combined with `--obfuscate --split-debug-info` (Flutter refuses). Size is measured with the first; the obfuscated release build is checked in H33.
- Listener numbers are call sites, not live counts: a service stream is opened by the screens that use it.
