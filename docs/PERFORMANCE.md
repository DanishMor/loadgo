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
