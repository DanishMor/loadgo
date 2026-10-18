# RESUME (Part 4, U tasks: premium flow + bid engine)

Plan: docs/MASTER_PLAN_PART4.md. Read it, then continue from NEXT.

LAST_DONE: U28 Incoming Load Card (driver/v2/incoming_load_screen.dart + incoming_load_host.dart: full-screen card from LoadRadar, ring, slide to accept, send price, skip with optional reason, taken/time-up message, queue; host wired in DriverHomeScreen when uiV2 and online; push to a closed app waits for the server wave) and U29 bid sheet (driver_bid_sheet.dart: percent chips, FareMeter, ETA and note chips, edit once, withdraw). Skip reasons are asked but not stored (no server field).
NEXT: U30 loads feed (filters, saved routes, match reasons; use the bid sheet), U31 My bids statuses (pending, countered, selected, lost; edit/withdraw through DriverBidSheet), U32 trip flow big buttons, U33 earnings, U34 onboarding; then Phase 6, 7, 8. Push is due.

Unfinished / to remember:
- The old CustomerHomeScreen must stay reachable with uiV2 OFF.
- The driver side has to: show the Incoming Load Card from LoadRadar (U28), bid sheet with ETA/note/pickupKm (OfferService.send already accepts them), edit once (OfferService.edit), confirm after the customer accepts (OfferService.confirm).
- docs/WHERE_IS_WHAT.md, FLOW_SPEC.md, DESIGN_SYSTEM.md, TEST_PLAN.md, RELEASE_CANDIDATE.md need the new screens (U38).
- Rules: full suite passed at ux-v2-phase3 (13 + 167 + 116/110/126/158); functions unit 38 + emulator dispatch 4 pass.

Standing rules: no firebase deploy, no phone/emulator/apk, no real keys, every new server feature behind a config/features flag, flutter test only in small batches with --concurrency=1 (check free memory, under 3 GB wait 2 min), PowerShell only, commit "U<n>: ...", push every 3 tasks, tag ux-v2-phase<n> at the end of each phase. `flutter analyze <folders>` is fast; the whole project takes minutes.
Tips: use the Write tool for files (bash heredocs with quotes or `${` in node -e fail; never `cat > file` without a heredoc); patch scripts in the scratchpad (patch.js with JSON, add_strings.js for l10n tables, addflag.js for switches); new texts go in lib/core/l10n/ux2_*_strings.dart (en, hi, hinglish, kn, ta, te, mr, gu, bn, pa, ks, ur) and are registered in strings.dart. PNG check: `flutter test tool/render_screens_test.dart` then read build/ux_png/*.png.
Emulator tests (rules, functions) need JAVA_HOME of Android Studio jbr; run only one emulator job at a time (they share ports).
