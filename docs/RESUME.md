# RESUME (Part 4, U tasks: premium flow + bid engine)

Plan: docs/MASTER_PLAN_PART4.md. Read it, then continue from NEXT.

LAST_DONE: U18 (customer home + shell: Home, Trips, Help, Profile behind uiV2; old home kept with uiV2 off) and U23 (Trips tab: active, upcoming, past, book again). Earlier: U1 to U17, U19 wizard, U20 Bid Room; phases 1 to 3 tagged.
NEXT: U21 tracking v2, U22 delivery, U24 bilty button, U25, U26, then Phase 5 driver (U27 to U34), Phase 6, 7, 8. Tag ux-v2-phase4 after U26. Push is due (last push was before U17).

Unfinished / to remember:
- The old CustomerHomeScreen must stay reachable with uiV2 OFF.
- The driver side has to: show the Incoming Load Card from LoadRadar (U28), bid sheet with ETA/note/pickupKm (OfferService.send already accepts them), edit once (OfferService.edit), confirm after the customer accepts (OfferService.confirm).
- docs/WHERE_IS_WHAT.md, FLOW_SPEC.md, DESIGN_SYSTEM.md, TEST_PLAN.md, RELEASE_CANDIDATE.md need the new screens (U38).
- Rules: full suite passed at ux-v2-phase3 (13 + 167 + 116/110/126/158); functions unit 38 + emulator dispatch 4 pass.

Standing rules: no firebase deploy, no phone/emulator/apk, no real keys, every new server feature behind a config/features flag, flutter test only in small batches with --concurrency=1 (check free memory, under 3 GB wait 2 min), PowerShell only, commit "U<n>: ...", push every 3 tasks, tag ux-v2-phase<n> at the end of each phase. `flutter analyze <folders>` is fast; the whole project takes minutes.
Tips: use the Write tool for files (bash heredocs with quotes or `${` in node -e fail; never `cat > file` without a heredoc); patch scripts in the scratchpad (patch.js with JSON, add_strings.js for l10n tables, addflag.js for switches); new texts go in lib/core/l10n/ux2_*_strings.dart (en, hi, hinglish, kn, ta, te, mr, gu, bn, pa, ks, ur) and are registered in strings.dart. PNG check: `flutter test tool/render_screens_test.dart` then read build/ux_png/*.png.
Emulator tests (rules, functions) need JAVA_HOME of Android Studio jbr; run only one emulator job at a time (they share ports).
