# Baseline before the Elite plan (E0)

Tag: `pre-elite` (commit 18bde09, on top of tag final-free-complete).

| Item | Value | Source |
|---|---|---|
| Test files (test/) | 325 | counted 2026-10-29 |
| Test cases in test/ (grep of test/testWidgets) | about 2,471 | counted, approximate |
| flutter analyze | No issues found | run 2026-10-29 |
| firestore.rules | 248,806 bytes before E2, 205,322 after (see RULES_BUDGET.md) | measured |
| storage.rules | 3,899 bytes | measured |
| Rules emulator tests | storage 13, matrix 167, slices 116 + 114 + 126 + 158 | docs/BASELINE.md |
| Release APK arm64 | 66.6 MB; universal obfuscated 114.5 MB | docs/SIZE.md |
| Web build size | not measured (web builds skipped for low memory); UNVERIFIED | RESUME.md |
| Listeners per screen | no per-screen table yet; the listener audit test guards cancellation (PERFORMANCE.md). A table is part of E81. | PERFORMANCE.md |
