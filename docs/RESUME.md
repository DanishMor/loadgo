# RESUME (Part 4, U tasks: premium flow + bid engine)

Plan: docs/MASTER_PLAN_PART4.md. Read it, then continue from NEXT.

LAST_DONE: U30 to U44 (see docs/PART4_PROGRESS.md, one line per unit): driver loads feed, My bids, trip step card, earnings, set-up card, transporter company bid through the bid sheet, admin home in groups, docs, layout matrix (48), e2e flows (8), rules and concurrency tests (4), PNG check, bug hunt (12 fixes, docs/BUG_REPORT.md), full regression. Tags ux-v2-phase5 and ux-v2-phase6 are pushed.
NEXT: nothing is left in docs/MASTER_PLAN_PART4.md. Owner steps are in docs/RELEASE_CANDIDATE.md section G (13 phone rows) and docs/BLOCKED.md (Part 4): publish the rules, deploy the functions, then turn dispatchV2 ON. Native reader: docs/TRANSLATION_REVIEW_PART4.csv and docs/TRANSLATION_REVIEW_PART5.csv.

Unfinished / to remember:
- The old CustomerHomeScreen must stay reachable with uiV2 OFF.
- The driver side has to: show the Incoming Load Card from LoadRadar (U28), bid sheet with ETA/note/pickupKm (OfferService.send already accepts them), edit once (OfferService.edit), confirm after the customer accepts (OfferService.confirm).
- docs/WHERE_IS_WHAT.md, FLOW_SPEC.md, DESIGN_SYSTEM.md, TEST_PLAN.md, RELEASE_CANDIDATE.md need the new screens (U38).
- Rules: full suite passed at ux-v2-phase3 (13 + 167 + 116/110/126/158); functions unit 38 + emulator dispatch 4 pass.

Standing rules: no firebase deploy, no phone/emulator/apk, no real keys, every new server feature behind a config/features flag, flutter test only in small batches with --concurrency=1 (check free memory, under 3 GB wait 2 min), PowerShell only, commit "U<n>: ...", push every 3 tasks, tag ux-v2-phase<n> at the end of each phase. `flutter analyze <folders>` is fast; the whole project takes minutes.
Tips: use the Write tool for files (bash heredocs with quotes or `${` in node -e fail; never `cat > file` without a heredoc); patch scripts in the scratchpad (patch.js with JSON, add_strings.js for l10n tables, addflag.js for switches); new texts go in lib/core/l10n/ux2_*_strings.dart (en, hi, hinglish, kn, ta, te, mr, gu, bn, pa, ks, ur) and are registered in strings.dart. PNG check: `flutter test tool/render_screens_test.dart` then read build/ux_png/*.png.
Emulator tests (rules, functions) need JAVA_HOME of Android Studio jbr; run only one emulator job at a time (they share ports).
