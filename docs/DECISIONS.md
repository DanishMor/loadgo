# Decisions (MASTER-5)

One line per assumption taken without asking.

- 2026-10-08 `.claude/` is git-ignored, so the project permissions in `.claude/settings.json` stay local to the Codespace and are not committed.
- 2026-10-08 Rules audit (Task 1) is a static Dart test plus the existing emulator tests; the full field-level review stays in docs/SECURITY_REVIEW.md.
- Privacy / Terms (Task 8): docs and public pages mention the automatic clean-up, the LR-link switch-off on deletion and the hourly limits; the in-app policy stays the five short clauses (generic, no new 12-language text).
