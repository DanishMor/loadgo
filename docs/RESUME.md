# RESUME (Part 4, U tasks: premium flow + bid engine)

Plan: docs/MASTER_PLAN_PART4.md. Read it, then continue from NEXT.

LAST_DONE: Phase 4 finished (U18 to U26) and tagged ux-v2-phase4: customer shell + home, wizard, Bid Room, trip page v2, delivery, trips tab, bilty button, profile logout confirm, loading/empty/error tests (a double-padding overflow in the Trips skeleton was found and fixed).
NEXT: Phase 5 driver UX v2: U27 driver home (online switch, earnings today, vehicle selector, Radar status, upcoming, document expiry, Simple Mode compatible) behind uiV2 with the old driver home kept when uiV2 is OFF, U28 Incoming Load Card (LoadRadar), U29 to U34, then Phase 6, 7, 8. Customer-side extras still open: none.

Unfinished / to remember:
- The old CustomerHomeScreen must stay reachable with uiV2 OFF.
- The driver side has to: show the Incoming Load Card from LoadRadar (U28), bid sheet with ETA/note/pickupKm (OfferService.send already accepts them), edit once (OfferService.edit), confirm after the customer accepts (OfferService.confirm).
- docs/WHERE_IS_WHAT.md, FLOW_SPEC.md, DESIGN_SYSTEM.md, TEST_PLAN.md, RELEASE_CANDIDATE.md need the new screens (U38).
- Rules: full suite passed at ux-v2-phase3 (13 + 167 + 116/110/126/158); functions unit 38 + emulator dispatch 4 pass.

Standing rules: no firebase deploy, no phone/emulator/apk, no real keys, every new server feature behind a config/features flag, flutter test only in small batches with --concurrency=1 (check free memory, under 3 GB wait 2 min), PowerShell only, commit "U<n>: ...", push every 3 tasks, tag ux-v2-phase<n> at the end of each phase. `flutter analyze <folders>` is fast; the whole project takes minutes.
Tips: use the Write tool for files (bash heredocs with quotes or `${` in node -e fail; never `cat > file` without a heredoc); patch scripts in the scratchpad (patch.js with JSON, add_strings.js for l10n tables, addflag.js for switches); new texts go in lib/core/l10n/ux2_*_strings.dart (en, hi, hinglish, kn, ta, te, mr, gu, bn, pa, ks, ur) and are registered in strings.dart. PNG check: `flutter test tool/render_screens_test.dart` then read build/ux_png/*.png.
Emulator tests (rules, functions) need JAVA_HOME of Android Studio jbr; run only one emulator job at a time (they share ports).
