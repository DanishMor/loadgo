# APK size (Z19)

No new build was made. Data: `docs/PERFORMANCE.md` (H28, `--analyze-size`, arm64, 2026-10-19), `docs/BASELINE.md` and `docs/SECURITY_SCORECARD.md` (obfuscated release build H33). All numbers below come from those; anything else is marked **UNVERIFIED**.

## Where the size is
| Build | Size | Source |
|---|---|---|
| Universal release APK (obfuscated, all ABIs) | 114.5 MB | SECURITY_SCORECARD (H33) |
| arm64-only release APK | 66.6 MB | PERFORMANCE (H28) |

Parts of the arm64 build (H28): Dart code `libapp.so` 15.4 MB, WebRTC (voice call) 11.7 MB, Flutter engine 11.2 MB, `classes.dex` 3.2 MB, assets 1.5 MB. The universal APK is bigger because the WebRTC plugin ships **all ABIs**: x86_64 15.4 MB and armeabi-v7a 6.5 MB are extra, and the engine and Dart code are repeated for each ABI (the exact repeat sizes of the universal build were not measured: **UNVERIFIED**).

In short: about half of the 114 MB universal APK is code for ABIs that one phone never uses.

## What can be smaller, and what each costs
| Idea | Saves (from the data) | Status |
|---|---|---|
| **App bundle** (`flutter build appbundle --release`) for Google Play | Each phone downloads only its own ABI: roughly the 66 MB arm64 figure, less after Play's own compression (**UNVERIFIED**) | Owner step, needs Play Console. No code change. Best option. |
| **`--split-per-abi`** for direct APK files | One APK per ABI; arm64 about 67 MB. Give each phone the matching file (almost every phone since 2018 is arm64). | Owner step when building the APK. No code change. |
| Drop **x86_64** from the release APK (`ndk { abiFilters }` in the release build type) | About 15 MB of WebRTC plus engine and Dart code for x86_64 | **Not applied**: it needs a release build and a phone to verify, and a release APK would stop installing on x86 emulators and some Chromebooks. Owner decision. |
| Unused assets | Assets are 1.5 MB in total (fonts only; `assets/branding/` is not in `pubspec.yaml` assets). Nothing to remove. | Done already, guarded by `test/performance_guard_test.dart` (3 MB budget). |
| Font subset | The Noto fonts are about 1.4 MB of the 2.9 MB in `assets/` (Mukta 2 weights, 8 scripts). Subsetting them would need a font tool and a check of every language by a reader. Saving is under 1.5 MB (1 to 2% of the arm64 APK). | Not worth the risk. Not applied. |
| Material icons | Already tree-shaken by Flutter (1.6 MB to 50 KB). | Done by the build. |
| R8 minify and resource shrinking | Already ON in the release type (`isMinifyEnabled`, `isShrinkResources`). | Done. |
| Drop voice call (WebRTC, about 12 MB per ABI in arm64) | Large, but removes a feature. | Not a size task; product decision. |

## Checks
- `test/performance_guard_test.dart` keeps the bundled assets under 3 MB.
- To measure again (owner, needs a build): `flutter build apk --release --analyze-size --target-platform android-arm64` (it cannot be combined with `--obfuscate`, see BASELINE).

## What was applied in this task
Nothing in code or Gradle. The safe things are already on; the big ones are build-time choices (bundle, split per ABI) that the owner makes when building. Listed in `docs/OWNER_TODO.md` section D.
