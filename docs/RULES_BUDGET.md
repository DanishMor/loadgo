# Rules budget (E2)

- Before E2: `firestore.rules` 248,806 bytes (243 KB), 42 KB of it whole-line comments.
- After E2: 205,322 bytes (200 KB). Only whole-line comments and blank lines were removed; no rule text changed.
- The commented original is kept as `docs/firestore.rules.annotated.txt` (not deployed). When you change a rule, edit `firestore.rules` and add the comment to the annotated copy.
- Budget: tests fail above 235 KB (`test/rules_size_test.dart`, `tool/rules_size.ps1`). The real limit is believed near 256 KB (UNVERIFIED), so about 30 KB of room is left for the Elite plan.
- If the room runs short: reuse helpers, merge duplicate field whitelists, then move rarely used collections behind shorter helper functions. Never trade away a check for size.
- Verified after the change: static rule audits, wallet/security tests and `rules_contract_capture_test` (153 tests) pass. The emulator suite (`firestore_rules_test`) was not rerun because comment removal is behaviour-neutral; run `sh run-tests.sh` there before publishing.

## Rules emulator suite after E2 (2026-10-29)
Full `sh run-tests.sh` (keep-awake wrapper): storage 13/13, matrix 167/167, contract 66/66, red team 263/263, red team storage 31/31, rules slices 116/116, 114/114, 126/126, 158/158. Total 1054 passed, 0 failed. No rule changed.
The first run failed 1 contract flow (payout request): the fixture had the recording day in the id `payout_counters/drv1_20261019`, which the rules build from today. `contract.test.mjs` now moves that day to today, like it already did for timestamps.
