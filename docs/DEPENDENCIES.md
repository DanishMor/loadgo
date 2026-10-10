# Dependencies (P8), 2026-10-11

Command: `flutter pub outdated`. Rule: sirf patch / minor updates, major upgrade nahi.

## Jo update kiya
| Package | Pehle | Ab | Kyun safe |
|---|---|---|---|
| image_picker | 1.2.3 | 1.2.4 | patch |
| shared_preferences | 2.5.5 | 2.5.6 | patch |

Sirf `pubspec.lock` badla (`flutter pub upgrade image_picker shared_preferences`); koi aur package nahi chhua. Baad mein: `flutter analyze` 0 issues, 8 related test files (draft, low-end mode, smart defaults, trip queue, inspection, auth, announcement, role tour) pass; poora `flutter test` P14 mein.

## Jo jaan-bujhkar nahi badla
| Package | Abhi | Naya | Wajah |
|---|---|---|---|
| cupertino_icons | 1.0.9 | 2.0.0 (major) | major; sirf icons font, koi fayda nahi |
| connectivity_plus | 7.3.1 | 7.3.2 | pub.dev par naya hai par abhi resolve nahi hota; agle `pub upgrade` par aayega |
| qr, cross_file, nm, dbus, equatable, cli_util | transitive | major | direct dependents (printing/pdf, share_plus, flutter_launcher_icons...) ke constraint se bandhe; unke apne update ke saath aayenge |
| code_assets, hooks, record_use (transitive) | purane | major / minor | build-hook packages Flutter SDK ke saath aate hain; alag se mat chhedo |

## Unsafe ya abandoned
* `flutter pub outdated` mein koi package **discontinued** ya **retracted** nahi dikha. Dart ka `pub audit` is SDK mein nahi hai; advisories ke liye pub.dev par package ka "Security advisories" section dekho (VERIFY har bade update se pehle).
* Dhyan dene wali: **Kotlin Gradle Plugin (KGP) warning**. Build ke dauraan Flutter batata hai ki ye plugins KGP apply karte hain aur "future Flutter versions will fail to build" (Built-in Kotlin migration): `firebase_analytics`, `firebase_auth`, `firebase_core`, `firebase_crashlytics`, `firebase_remote_config`, `firebase_storage`, `flutter_webrtc`. Abhi build chalta hai (`android.builtInKotlin=false`, `android.newDsl=false` in `android/gradle.properties`). Flutter ya in plugins ko major upgrade karne se pehle ye dono flags aur changelog dekho. Plugin authors ki guide: docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin.
* Java warning "source value 8 is obsolete" kuch plugins (cloud_firestore, geolocator) se aati hai; sirf warning hai.
* `speech_to_text` (7.5.0) aur `flutter_webrtc` seedhe device hardware se jude hain: har update ke baad phone par test karo (voice input, call), sirf unit test kaafi nahi.
* Dev tools: `flutter_launcher_icons`, `flutter_native_splash`, `fake_cloud_firestore`, `firebase_auth_mocks` sirf dev_dependencies mein hain, APK mein nahi jaate.

## Aage ka niyam
Mahine mein ek baar `flutter pub outdated`, patch/minor lagao, analyze + poora test, phir `docs/PROGRESS.md` mein ek line. Major upgrade ek ek karke, alag commit mein, phone par test ke saath.
