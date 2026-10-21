# Known risks (Part 5)

Things that are true today and are not fixed by code in this repo. Each says why and what closes it.

| # | Risk | Why it stays | Closes with |
|---|---|---|---|
| 1 | Extra / server-side fields can be planted on a new load by a modified client (BUG_REPORT H-2, S3). Nothing trusts them as input today. | The `loads` create rule is at the 1000-expression limit; a key whitelist does not fit. | A function that strips unknown fields on create (`TODO(functions)`), or splitting the rule. |
| 2 | Functions are written and tested on the emulator only; they are not deployed. Fares, commission and payout are checked by rules for shape and limits, not computed by the server. | No Blaze plan / no deploy by rule. | Deploy steps in `docs/BLOCKED.md`. |
| 3 | App Check is not enforced (monitor mode only). A script with a valid sign-in can call the API without the real app. | Needs the Play-Integrity registration and a monitoring period. | The six-step plan in `docs/SECURITY_DECISIONS.md`. |
| 4 | Audit lines for user events (accept, status change, cancel) are written by the client and can be skipped or forged by a modified client. | Server triggers need deploy. | Deploy of the audit triggers. |
| 5 | The chat contact filter catches spelled-out numbers only in the app; rules refuse plain 10-digit numbers. | Server scan needs deploy. | `serverChatScan` flag on. |
| 6 | The pickup / delivery code of a queued trip step sits in plain `SharedPreferences` until it is sent (BUG_REPORT H-6, S4). Needs a rooted phone; the code is single-use; backups are off. | No secure-storage package is installed; adding one is a dependency change. | `flutter_secure_storage` in a later round. |
| 7 | Every staff role can read all user profiles (admin console). Insider misuse is limited by `audit_events` for contact and chat views only. | By design for support work. | Per-role field-level views. |
| 8 | Admin screens copy CSV (payout queue, cohorts) to the clipboard. | Intentional convenience for the owner. | Optional export-to-file. |
| 9 | Vehicle papers (policy numbers) are readable by every signed-in user. | Needed for matching today. | A private subcollection. |
| 10 | (Closed in Z21) The admin app now opens nothing for an unknown staff role; a missing role is still super, like the rules. | - | - |
| 11 | Only tested on emulators and fakes. No real phone, no real network, no external penetration test. | Rules of this work. | `docs/PENTEST_CHECKLIST.md`, the phone sheet in `docs/RELEASE_CANDIDATE.md`. |
| 12 | Certificate pinning and root detection are not used. | Decisions with reasons in `docs/SECURITY_DECISIONS.md`. | Revisit when a first-party API exists. |
| 13 | `firestore_rules_test` dev tools have 16 audit findings (in `firebase`, `firebase-tools`). Not shipped. | Fixing needs major upgrades. | A planned tools upgrade, run through the full rules suite. |
