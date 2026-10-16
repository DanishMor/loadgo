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
