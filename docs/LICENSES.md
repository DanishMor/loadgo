# Licences and dependency policy (E5)

Every package in `pubspec.yaml` must have a row here; `test/licenses_test.dart` fails on an unlisted package, a missing font or a licence outside the allowed list.
The licence was read from each package's LICENSE file in the local pub cache on 2026-10-29.

## Policy
- Add a package only when the feature cannot be built without it. Prefer none.
- One package per commit. After it: `flutter pub get`, `flutter analyze`, the related tests. If anything breaks, revert and write `docs/BLOCKED.md`.
- Each new row says: licence, size impact (measured or UNVERIFIED, also in `docs/SIZE.md`), maintenance (last release, publisher), and Kotlin Gradle Plugin (KGP) status.
- KGP: the release build already warns for the plugins marked below. Never add a plugin that applies KGP the old way (see `docs/DEPENDENCIES.md`).
- Allowed licences: MIT, BSD-2-Clause, BSD-3-Clause, Apache-2.0, and SIL OFL 1.1 for fonts. Anything else needs an owner decision first.
- Images and illustrations: our own work only (drawn in code or SVG), no third-party artwork.

## Packages
| Package | Version | Licence | KGP / APK | Why |
|---|---|---|---|---|
| `cupertino_icons` | 1.0.9 | MIT | ok | iOS-style icons |
| `firebase_core` | 4.15.0 | BSD-3-Clause | KGP warning today | Firebase base |
| `firebase_auth` | 6.7.0 | BSD-3-Clause | KGP warning today | phone OTP login |
| `cloud_firestore` | 6.10.0 | BSD-3-Clause | ok | database |
| `firebase_storage` | 13.6.0 | BSD-3-Clause | KGP warning today | photo uploads (behind photoUploads) |
| `image_picker` | 1.2.4 | Apache-2.0 | ok | camera and gallery for papers and photos |
| `geolocator` | 14.1.1 | MIT | ok | location for trips |
| `firebase_messaging` | 16.7.0 | BSD-3-Clause | ok | push tokens and messages |
| `connectivity_plus` | 7.3.1 | BSD-3-Clause | ok | offline detection |
| `shared_preferences` | 2.5.6 | BSD-3-Clause | ok | small local settings |
| `url_launcher` | 6.3.3 | BSD-3-Clause | ok | calls, maps and links out |
| `crypto` | 3.0.7 | BSD-3-Clause | ok | hashing (trip codes, idempotency) |
| `pdf` | 3.13.1 | Apache-2.0 | ok | LR, invoice and statement PDFs |
| `printing` | 5.15.1 | Apache-2.0 | ok | PDF share and print |
| `firebase_crashlytics` | 5.4.0 | BSD-3-Clause | KGP warning today | crash reports |
| `firebase_analytics` | 12.6.0 | BSD-3-Clause | KGP warning today | product analytics (consent-gated) |
| `firebase_remote_config` | 6.7.0 | BSD-3-Clause | KGP warning today | remote switches |
| `package_info_plus` | 10.2.2 | BSD-3-Clause | ok | app version for force-update and Diagnose |
| `share_plus` | 13.3.1 | BSD-3-Clause | ok | share sheet |
| `speech_to_text` | 7.5.0 | BSD-3-Clause | ok | voice input (Sahayak) |
| `flutter_webrtc` | 1.6.2+hotfix.4 | MIT | KGP warning today | in-app voice call |
| `cloud_functions` | 6.5.0 | BSD-3-Clause | ok | server calls |
| `local_auth` | 3.0.2 | BSD-3-Clause | ok | app lock on money screens |
| `razorpay_flutter` | 1.4.7 | MIT | ok | checkout window (behind paymentGateway) |
| `google_maps_flutter` | 2.19.0 | BSD-3-Clause | ok | trip map (behind maps) |
| `firebase_app_check` | 0.4.8 | BSD-3-Clause | ok | App Check |
| `flutter_lints` | 6.0.0 | BSD-3-Clause | dev only, not in the APK | lint rules |
| `fake_cloud_firestore` | 4.3.0 | BSD-2-Clause | dev only, not in the APK | Firestore fake for tests |
| `flutter_launcher_icons` | 0.14.4 | MIT | dev only, not in the APK | icon generation |
| `flutter_native_splash` | 2.4.8 | MIT | dev only, not in the APK | splash generation |
| `firebase_auth_mocks` | 0.15.2 | BSD-2-Clause | dev only, not in the APK | Auth fake for tests |

## Fonts
| File | Licence | Source |
|---|---|---|
| `assets/fonts/NotoSans-Regular.ttf` | SIL OFL 1.1 | The Noto Project Authors (`assets/fonts/LICENSE.txt`) |
| `assets/fonts/NotoSansDevanagari-Regular.ttf` | SIL OFL 1.1 | The Noto Project Authors (`assets/fonts/LICENSE.txt`) |
| `assets/fonts/NotoSansKannada-Regular.ttf` | SIL OFL 1.1 | The Noto Project Authors (`assets/fonts/LICENSE.txt`) |
| `assets/fonts/NotoSansTamil-Regular.ttf` | SIL OFL 1.1 | The Noto Project Authors (`assets/fonts/LICENSE.txt`) |
| `assets/fonts/NotoSansTelugu-Regular.ttf` | SIL OFL 1.1 | The Noto Project Authors (`assets/fonts/LICENSE.txt`) |
| `assets/fonts/NotoSansGujarati-Regular.ttf` | SIL OFL 1.1 | The Noto Project Authors (`assets/fonts/LICENSE.txt`) |
| `assets/fonts/NotoSansBengali-Regular.ttf` | SIL OFL 1.1 | The Noto Project Authors (`assets/fonts/LICENSE.txt`) |
| `assets/fonts/NotoSansGurmukhi-Regular.ttf` | SIL OFL 1.1 | The Noto Project Authors (`assets/fonts/LICENSE.txt`) |
| `assets/fonts/NotoNaskhArabic-Regular.ttf` | SIL OFL 1.1 | The Noto Project Authors (`assets/fonts/LICENSE.txt`) |
| `assets/fonts/mukta/Mukta-Regular.ttf` | SIL OFL 1.1 | Ek Type (`assets/fonts/mukta/OFL.txt`) |
| `assets/fonts/mukta/Mukta-Bold.ttf` | SIL OFL 1.1 | Ek Type (`assets/fonts/mukta/OFL.txt`) |

## Images
| Path | Licence | Source |
|---|---|---|
| `assets/branding/` | owned by the app owner | made for this app (docs/LOGO_BRIEF.md) |
