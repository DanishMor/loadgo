# Performance notes (MASTER-6 Task 37)

## What the tests guard (test/performance_guard_test.dart)
- Assets: only fonts, under 3 MB in total, no file over 700 KB (the base Noto Sans is 607 KB).
- Long lists: `ListView(children: [for ...])` builds every row at once. The count of such lists is capped; a list that can grow (chat, trips, notifications, ledger) must use `ListView.builder` or a query `limit`.
- `shrinkWrap: true` is capped for the same reason.
- `Image.network` must carry a width or `cacheWidth` so full photos are not decoded for a thumbnail.

## Habits
- `const` constructors wherever the analyzer allows (the `prefer_const_constructors` lint is on).
- A stream is created once (`initState` or a `late final`), never inside `build`; the listener audit test checks that screens cancel subscriptions.
- Firestore lists use `limit(...)`; see COST_WATCH.md for the unbounded ones that remain.
- Heavy pure work (CSV, statements, search) runs on small, already-loaded lists; nothing blocks the UI for more than a frame on a 500-row list (test/input_fuzz_test.dart has a time ceiling).

## Profile-mode checks (needs a real phone; owner or tester does this)
1. `flutter run --profile` on a low-end Android phone (2 GB RAM).
2. Open DevTools > Performance. Scroll: Driver loads list, Customer My Loads, Chat with 200 messages, Admin users list. Frames should stay under 16 ms (UI) and 16 ms (raster); janky frames under 5%.
3. DevTools > Memory: open and close the trip screen 10 times; memory must return near the start (no leak from listeners).
4. Cold start: time from tap to first screen under 4 s on the low-end phone (see the startup notes in ARCHITECTURE.md).
5. Turn on Settings > Low-end device mode (Task 40) and repeat steps 2 and 4.
6. Write any result worse than these numbers in BUG_REPORT.md.

## Part 2 pass (F42)
New screens and what keeps them cheap:
- **Photos:** the picker shrinks to 1600 px / quality 75 before upload; files over 5 MB are refused by the app and the rules. `PhotoImage` decodes at `cacheWidth: 400`, keeps at most 20 pictures in memory and reads with `getData` (limit 5 MB). Lists of pictures are `limit(20)` (admin papers) and `limit(30)` (trip photos).
- **Streams:** the admin papers card and the trip photos card create their stream once in `State` (found and fixed in this pass: they were built inside `build`).
- **Queue:** the offline photo queue holds at most 10 entries and stores paths, not bytes.
- **Hubs and finance:** show the newest ledger lines only (true paging needs the composite index in `firestore.indexes.json`, an owner deploy item).
- **Admin web:** the admin shell builds nothing for customers, drivers or fleets; a non-admin sees one small page.
- **Push:** the app registers once per sign-in; the tap router does no work until a push is tapped.
- Guard tests: `test/performance_guard_test.dart` (lists, shrinkWrap, images), `test/setstate_future_guard_test.dart`, `test/new_screens_a11y_test.dart` (targets and contrast).
- Real-phone numbers (frame times, memory with 50 photos in a list, cold start) are still to be filled in by the tester (steps above).

## Part 3 (G41, 2026-10-17): what the new code costs

Every new feature is behind a switch that is OFF, so a phone that does not use one pays nothing at run time. What each costs when it is ON, and the guard that keeps it small:

| Feature | Cost when ON | Guard |
|---|---|---|
| Live trip location (G11) | GPS with a 50 m filter inside a foreground service; Firestore writes at most one per 30 s and only after 100 m (or every 5 min parked): about 12 to 120 writes an hour of driving. Battery: the GPS is the cost; the notification is required by Android. | `LiveLocationPolicy` (bounded config), stops with the trip and at sign-out, server job removes the last position after a day |
| Trip map (G10) | one native map view while the screen is open; no polling (follows the booking document) | opened by a button, not drawn on other screens |
| Road distance (G10) | one function call per new city pair per run, waits 0.9 s after typing stops; the server keeps the answer 30 days | per person and total daily caps, city-table fallback |
| Usual price (G20) | one document read per route and truck type per run (cached in memory) | `RouteRates` cache; nothing without a known city pair |
| Driver trust card (G19) | one document read per driver shown (a stream on one small document) | hidden with the switch off; failure draws nothing |
| Party khata (G23) | a stream of the person's parties (at most 100); lines load only inside one party | list screen reads parties only (the balance sits on the party) |
| Business card (G24) | one picture drawn at 3x when shared (about 340 x 300 px), nothing kept | made only on the Share tap |
| Check-in (G22) | no extra GPS (it uses the banner's samples); one timer of 10 minutes while asking | one card per halt |
| Analytics funnel (G8) | seven events per person in their whole life | once per step, nothing while consent is off |
| App Check (G15) | token fetch is automatic and cached by the SDK | asleep unless the build asks |
| Server work | see docs/COST_WATCH.md (one table of every paid call, its switch and its daily limit) | `test/cost_guards_test.dart` |

### App size and start-up

New plugins: `local_auth`, `razorpay_flutter`, `google_maps_flutter`, `firebase_app_check`. The release build removes unused code (`isMinifyEnabled`), but the Maps and Razorpay plugins add native libraries; measure the release APK / bundle size before and after on the owner's laptop (`flutter build appbundle --release` then look at the size) and write the numbers here. Start-up: nothing new runs before the first screen except reading the saved analytics choice after sign-in and (only if the build asks) App Check activation; both are fire-and-forget.

### Low-end phones

`test/part3_layout_test.dart` draws every new screen with Low-end mode on. The map is the one heavy view: on a Low-end phone prefer the "Last seen N min ago" line (switch `maps` off, or do not open the map). Nothing new loops without a stop.

## Part 5 (H24 to H30): start-up, size, speed budgets, how to profile

### Start-up (H24)
What runs before the first frame, in order, and what may fail without stopping the app:

| Step | Before first frame? | If it fails |
|---|---|---|
| Binding, picture cache cap (48 MB), error hooks | yes (instant) | n/a |
| `Firebase.initializeApp` (30 s limit) | yes, needed by everything | calm "app could not start" screen with Try again (`StartupFailedApp`) |
| Crash reporting, App Check, offline cache, app lock | yes (short, each in `StartupGuard.step`) | logged by step name, app goes on |
| Language, theme, simple mode, low-end mode, haptics, connectivity (read together) | yes (one parallel wait, each guarded) | defaults |
| `AppControlService.refresh`, `refreshAppConfig`, analytics consent, push registration | no, started after sign-in state is known, never awaited | defaults (config has a 15 s limit per document, Remote Config style defaults in code) |
| Push router (asks the platform for the message that opened the app) | **no**, after the first frame since Part 5 | push taps still work (the router keeps an early tap) |

Budget (to be checked on a real phone, see below): first frame under 2.5 s on a 2 GB phone, cold start to the home list under 5 s on 4G. Nothing in `main()` may be added before `runApp` without a line in this table.

### Widgets (H26)
- Existing guards: `test/performance_guard_test.dart` (no `shrinkWrap` lists of unbounded data, `Image.network` always with a width or `cacheWidth`), `test/setstate_future_guard_test.dart`, `test/lifecycle_guard_test.dart` (no `setState` after an `await` without `mounted`).
- Text at 2.0x is covered by the layout matrices (`*_layout_test.dart`, 360x640).
- The long lists page or are capped (`watchForDriverPage`, `newestPage`, `BookingService.watchAllCap`); `performance_guard_test.dart` refuses `shrinkWrap` on unbounded lists.
- A hot path found and fixed in Part 5: `findCity` (the city table lookup used by the driver feed ranking) normalised every name on every call. Ranking 1 500 loads took **3.1 s**, now **0.09 s** (35 times faster). The names are prepared once and answers are cached.

### Heavy work off the screen thread (H27)
- CSV text (statements, cohorts, trends) is built from lists already in memory on a button tap (not measured separately; add it to `perf_budget_test.dart` if a statement ever grows large).
- PDF files (LR, invoice, statements) need the fonts from the asset bundle, which an isolate cannot read; they are built only on a button tap, one document at a time. Not moved; measure on a real phone (steps below). If a PDF takes over 300 ms there, build the font bytes first on the main isolate and run the drawing in `compute`.
- Parsing: reading 1 500 documents takes 0.06 s.

### App size (H28)
Measured on 2026-10-19 with `flutter build apk --release --analyze-size --target-platform android-arm64`: **66.6 MB** (the earlier universal APK was 119.8 MB). Largest parts:

| Part | Size |
|---|---|
| Your Dart code (`libapp.so`, arm64) | 15.4 MB |
| WebRTC (voice call), arm64 | 11.7 MB |
| Flutter engine, arm64 | 11.2 MB |
| WebRTC for **x86_64** and **armeabi-v7a** (plugin ships all ABIs) | 15.4 + 6.5 MB |
| `classes.dex` (Java/Kotlin) | 3.2 MB |
| Assets (fonts and images) | 1.5 MB (fonts only, under the 3 MB budget) |

What to do (owner, no code change): ship the **app bundle** to Google Play (`flutter build appbundle --release`): Play sends each phone only its own ABI, which removes the 22 MB of unused WebRTC code for a typical arm64 phone. For a direct APK file use `flutter build apk --release --split-per-abi` and give each phone the matching file. Fonts are already subset by Flutter's icon tree-shaking (Material icons 1.6 MB to 50 KB). Only the fonts are bundled (`pubspec.yaml` lists `assets/fonts/` only; the brand pictures in `assets/branding/` are inputs for the launcher-icon tool, not shipped), and every font is declared and used.

### Speed budgets as tests (H29)
`test/perf_budget_test.dart` runs on every test run and fails on a real slowdown (limits are about 10 times what a laptop needs):

| Path | Work | Measured | Budget |
|---|---|---|---|
| Fare calculator | 20 000 quotes | 0.06 s | 1.5 s |
| Log cleaning (`Redactor`) | 3 000 lines of 200 characters | 1.2 s | 4 s |
| Reading documents (`Load.fromDoc`) | 1 500 | 0.06 s | 1 s |
| Driver feed ranking (`LoadRanker.rank`) | 1 500 loads, 3 vehicles | 0.09 s | 2 s |

### Profile on a real phone (owner steps, H30)
1. Build a profile build: `flutter run --profile` on a USB-connected phone (never a debug build for numbers).
2. Open DevTools (the link printed in the terminal) > **Performance**. Record while you scroll the driver feed and the customer "My loads" list. Frames above 16 ms (red) are slow. Write the worst frame time and the screen in `docs/PHONE_TEST_SHEET.md`.
3. DevTools > **Memory**: open 50 photos in a list, then press "Snapshot". Memory should stay under 250 MB on a 2 GB phone and fall after you leave the screen.
4. Cold start: kill the app, start it, note the time to the home list (stopwatch). Compare with the budget above.
5. Network: switch on flight mode, open the app: the offline banner shows and the last lists appear (offline cache is capped, `Backend.offlineCacheBytes`).
6. Low-end mode: Settings > Low-end mode on, repeat step 2; animations are off and frames should be smoother.
