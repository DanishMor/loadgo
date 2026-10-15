# Earnings and accounts: security (F13)

Today Load 20 holds **records only**. No real money moves through the app. This file says what protects the records now, what will protect real money later, and what still needs a server (Cloud Functions, Phase C).

Default label in the app: "Kamai aur hisaab" (Earnings and accounts). The word "wallet" is a decision for the lawyer (`WALLET_LEGAL.md`, `DECISIONS.md`).

## What exists

| Part | Where | Flag (all default OFF) |
|---|---|---|
| Money in whole paise, clamped sums, basis-point rounding | `lib/core/money/money.dart` | none (pure code) |
| Balance only from lines (pending, available, held, paid out); duplicate keys count once; a box never goes below zero | `lib/core/money/wallet_book.dart` | none |
| Ledger lines append-only; corrections are signed `adj_` lines by finance or super | `firestore.rules` (`ledger`) | none |
| `wallets/{uid}` summary: client read-only | `firestore.rules` | none |
| Freeze (`wallet_freezes`) stops new payout requests | `firestore.rules` | none |
| Payout states requested, approved, paid, rejected, reversed; the approver cannot pay | `firestore.rules` (`payouts`) | `walletMakerChecker` |
| Fresh sign-in (5 minutes) for a payout request or a change of payout details | `firestore.rules` (`stepUpOk`), `lib/core/wallet/step_up.dart` | `walletStepUp` |
| Waiting time after changed payout details; per-day count and total | `firestore.rules` (`payoutLimitsOk`, `payout_counters`), `config/wallet` | `walletLimits` |
| Screen lock and screenshot block | `lib/core/security/app_lock.dart`, `secure_screen.dart` | `appLock`, `secureScreens` |
| Every money action in `audit_events` | `AuditService` | none |
| Admin Finance with daily check and anomaly flags | `lib/admin/admin_finance_screen.dart` | none (admin only) |

## Threat model

| Threat | What stops it today | What is still missing |
|---|---|---|
| **Double spend**: asking for the same money twice | The app refuses a second open request and checks the balance. The rules cap the amount by the server summary once it exists. The per-day counter (flag `walletLimits`) limits count and total. | The rules cannot add up the ledger. Until Functions write `wallets/{uid}`, a modified app could ask for more than it earned. Finance sees it in the daily check before paying. **Server: F23.** |
| **Replay**: sending an old request again | Payout ids are new each time; the counter must grow by exactly one request in the same batch; ledger line ids are fixed per booking and type, so a second write is refused. | None for the records. |
| **Race**: two phones, two admins, at the same moment | Firestore transactions for the counter and the request; approve and pay are separate updates guarded by the old status (`resource.data.status`). Two admins cannot both move the same payout from the same status. | Server-side recompute of the summary after parallel writes (F23). |
| **Tampering with the balance** | Nothing stores a balance a client can write. `wallets/{uid}` is server-only. Lines cannot be edited or deleted. | A modified app can show a wrong number to its own user; it cannot change what finance sees. |
| **Stolen phone or stolen session** | Fresh code before a payout or before payout details change (flag `walletStepUp`; the rules read `auth_time`). Waiting time after details change (flag `walletLimits`). Screens can be locked with the phone's lock (`appLock`, plugin pending) and hide screenshots (`secureScreens`). Amounts start hidden. | The SMS code is the only strong factor. App Check and device binding come with Phase G. |
| **Insider fraud**: one finance admin approves and pays their own friend | Maker-checker in the rules (`approvedBy != paidBy`); reasons for reject and reverse; every action in `audit_events`; the daily check lists any person with more paid than earned; anomaly flags for big, repeated and "new details then big" payouts. Nobody can edit or delete a ledger line or a payout. | Two colluding admins. A second layer is the owner reading the daily check. |
| **Account takeover to change payout details** | Fresh code; waiting time; audit line `payout_details_changed` (no UPI id or name in it). | Notify the old phone by push (Phase D, F25 payout status). |
| **Data leak** | UPI id shown masked (`maskUpiId`); bank numbers masked (`maskAccountNumber`); logs and crash reports are cleaned (`Redactor`, `RedactedError`); `wallets` and `ledger` are readable only by the owner and admins. | The admin Finance screen shows driver ids, not names or phones. |

## What runs on the phone and what needs the server

**Phone only (a modified app can skip it):** the 5-minute cache of a fresh code, hiding amounts, the app lock, the screenshot block, the "approver cannot pay" button hiding, the client balance check before a request.

**Enforced by the Firestore rules (cannot be skipped from the app):** append-only ledger; no client writes to `wallets`; payout statuses and who may move them; the approver cannot pay; reasons and reference are required; freeze blocks new requests; fresh sign-in, waiting time and daily counter when their flags are on.

**Needs the server (Phase C, F23):** adding up the ledger to know the real balance; checking a request against it; recomputing the summary after every write; scheduled reconciliation; alerts. Until then finance reads the daily check.

## How to verify

1. `firestore_rules_test`: `npm test` (groups "wallet data model (F8)" and "wallet security (F11)").
2. `flutter test --concurrency=1 test/money_core_test.dart test/wallet_security_test.dart test/finance_test.dart`.
3. Emulator: sign in two finance admins, approve with one, try to pay with the same one (must be refused), pay with the other.
