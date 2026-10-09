# Decisions (MASTER-5)

One line per assumption taken without asking.

- 2026-10-08 `.claude/` is git-ignored, so the project permissions in `.claude/settings.json` stay local to the Codespace and are not committed.
- 2026-10-08 Rules audit (Task 1) is a static Dart test plus the existing emulator tests; the full field-level review stays in docs/SECURITY_REVIEW.md.
- Privacy / Terms (Task 8): docs and public pages mention the automatic clean-up, the LR-link switch-off on deletion and the hourly limits; the in-app policy stays the five short clauses (generic, no new 12-language text).
- Tasks 45 and 46 (e2e): test/e2e/bilty_e2e_test.dart, inspection_e2e_test.dart and transporter_private_chat_e2e_test.dart (Tasks 66-71) already walk transporter + bilty + inspection and chat block + strike ladder + call block from the booking to the admin; I kept them as the e2e for these tasks and added test/e2e/deletion_roles_e2e_test.dart (Task 47) instead of writing duplicates.
- Task 31: the Post Load wizard is three numbered steps on one scrolling page, not three separate screens, so every field stays in the tree and existing flows and tests keep working.
- Task 20: the phone clock is corrected with a server time learned from a chat message the phone sent; the rules themselves always use the server time. A person who never chats keeps the phone clock for screens (documented in Task 20 progress).
- Task 38: admin lists page the 100 documents read, 50 at a time, on the client; real server paging would need a cursor per list and a composite index.
- Task 20 (update): the learning source for `ServerClock` is the device record (`users/{uid}/devices/{id}.lastSeenAt` is stamped by the server and read back) at sign-in and at most every six hours, plus chat acknowledgements. It is not saved between runs: an old offset would be wrong after the person fixes the phone clock.
- M6-36: trust badges are shown to the driver only; customer-facing needs server summary (TODO(functions)).
- M6-43: R8 minify/shrink turned on for release; unverified because the Android SDK is missing here (see BLOCKED.md).
