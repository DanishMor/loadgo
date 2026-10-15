# Earnings and accounts: when to let real money move, and how to go back (F13)

Today: **records only**. LoadGo staff pay drivers by hand outside the app and mark the payout paid. This file is the order of switches before any real money goes through the app itself (a payment gateway, escrow or a held balance). Do not start before the lawyer and the CA have answered `WALLET_LEGAL.md`.

## Ready when (all of these)

1. Lawyer and CA answers in writing (is it "earnings records" or "held money", RBI rules, TDS/GST, KYC for payouts, refund time limit).
2. Blaze plan is on, a budget alert is set, Cloud Functions are deployed (`docs/BLAZE_GO_LIVE.md`), including the wallet functions (F23): the server writes `wallets/{uid}` after every ledger line, runs the scheduled reconciliation, and checks each payout request.
3. The reconciliation shows "every person balances" for 14 days in a row on the pilot.
4. Two finance admins exist (not the same person) and both have tried approve and pay with test payouts.
5. A real phone test of: the fresh code (SMS to a real number), screenshot block, app lock (if used).
6. Test phone numbers are deleted in Firebase Authentication (`docs/OTP_SECURITY.md`).
7. `firestore.rules` is deployed by the owner together with the matching app version (older app versions cannot pick up or deliver after the trip-code rules).

## Switch order (one at a time, 24 hours apart, watch the daily check after each)

1. `walletHub` (the new hub screens, records only).
2. `walletMakerChecker` (two admins for payouts).
3. `walletStepUp` (fresh code before a payout or a change of payout details).
4. `walletLimits` and `config/wallet` (waiting hours, daily count, daily total). Start strict: 24 hours, 2 requests, Rs 25,000 a day.
5. `secureScreens`, then `appLock` once the plugin is in.
6. Only then: the gateway adapter (F34) in sandbox, then live with a tiny first payout of your own.

## Rollback

- Any flag can be turned OFF at once in Admin > Features. The app falls back to the previous behaviour (records only, one-step payout, no code, no limits).
- A wrong payout state: never edit. Use **Reverse** on a paid payout, **Reject** on an open one, and a signed **correction line** for the ledger. All are audited.
- A suspicious person: **Freeze payouts** (reason required). Unfreeze after review.
- Rules rollback: redeploy the previous `firestore.rules` from git (`git log firestore.rules`). The rules keep working with the flags off.
- Stop everything: turn off `walletHub`; drivers see the old Wallet screen; staff keep the admin Payouts and Finance screens.

## What to watch daily

- Admin > Finance > Daily check: "Every person balances". Any "Needs a look" row is looked at the same day.
- Anomaly chips in the payout queue.
- Admin > Audit log filtered to `payout_decision`, `wallet_freeze`, `wallet_adjust`.
