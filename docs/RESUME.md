# RESUME (Part 4, U tasks: premium flow + bid engine)

Plan: docs/MASTER_PLAN_PART4.md. Read it, then continue from NEXT.

LAST_DONE: U9 (component kit: RouteRibbon, FareMeter, CountdownRing, SlideToConfirm, BidCard, DriverMiniCard, StatusTimelineV2, sheet kit, QuickChipRow, SkeletonList, FeedbackKit with QuietHours and heads-up banner; tests ux2_kit_test, ux2_kit2_test; PNG tool tool/render_kit_test.dart)
NEXT: U10 (flags uiV2 default ON, dispatchV2 default OFF; data model, rules, indexes, rules tests, migration tool)

Unfinished: none.

Standing rules: no firebase deploy, no phone/emulator/apk, no real keys, every new server feature behind a config/features flag, flutter test only in small batches with --concurrency=1 (check free memory, under 3 GB wait 2 min), PowerShell only, commit "U<n>: ...", push every 3 tasks, tag ux-v2-phase<n> at the end of each phase. `flutter analyze lib/core test/x.dart` on the touched folders is fast; the whole project takes minutes.
Tips: use the Write tool for files (bash heredocs with quotes fail); `node` patch scripts for edits; new texts go in lib/core/l10n/ux2_strings.dart (en, hi, hinglish, kn, ta, te, mr, gu, bn, pa, ks, ur).
