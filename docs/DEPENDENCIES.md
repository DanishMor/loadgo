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

## Part 2 (2026-10-16): ek naya package
| Package | Version | Kyun | Dhyan |
|---|---|---|---|
| cloud_functions | 6.x (`flutter pub add`) | admin actions, payout decisions aur announcement push ko server function se chalane ke liye (F21, F23, F27). Switch band ho ya function deploy na ho to app purane direct write par chalta hai. | Sirf Firebase ka apna package. Android par koi extra permission nahi. Asli phone par pehli baar test karna hai (jab owner functions deploy kare). `functions/` ke Node packages (firebase-admin, firebase-functions, eslint) alag hain: `functions/package.json`. |

## Part 3 (2026-10-17): nayi packages
| Package | Version | Kyun | Dhyan |
|---|---|---|---|
| local_auth | 3.0.2 | earnings par fingerprint / screen lock (G7, `appLock` OFF) | `USE_BIOMETRIC` permission; MainActivity ab `FlutterFragmentActivity`. Asli phone par test baaki. |
| razorpay_flutter | 1.4.x | online payment ki checkout window (G9, `paymentGateway` OFF) | Sirf public key id use hoti hai (server order ke saath bhejta hai). Release build mein agar class missing dikhe to plugin ke keep rules lagte hain. Asli phone par test baaki. |
| google_maps_flutter | 2.19.x | trip map (G10, `maps` OFF) | Android key `android/local.properties` se; bina key ke map khaali dikhta hai, app nahi girti. Web build mein ye plugin compile hota hai, map web par nahi dikhaya jata. |
| firebase_app_check | 0.4.x | app ka praman (G15) | Soya hua hai jab tak build `--dart-define=APP_CHECK=on` se na bane. Play Integrity Console mein register karna hota hai (docs/APP_CHECK.md). |

`geolocator` ka foreground service use hua (G11), koi naya package nahi; `FOREGROUND_SERVICE` permissions manifest mein.

### Functions ka `npm audit` (2026-10-17, G39)
`npm audit --omit=dev` ne 9 baat batayi (2 high, 7 moderate), sab `firebase-admin` 12 ke andar ke packages se (`node-forge`, `uuid`, `google-gax`, `teeny-request`, `retry-request`, `@google-cloud/*`). Fix sirf `firebase-admin` ka major upgrade hai. Dekhiye "Functions upgrade" neeche.
