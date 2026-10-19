# Alert thresholds (Part 5, H32)

When to be told, and what to do. Numbers are for the pilot (a few hundred people); scale them with the user count. Where it says "switch", it is a group of the emergency card (`docs/INCIDENT_RESPONSE.md`).

## Set these up (owner, in the consoles, free)
| Where | Alert | Threshold | Action |
|---|---|---|---|
| Google Cloud > Billing > Budgets | budget with e-mail alerts | 50%, 90% and 100% of the monthly budget you accept (start with a small number) | at 90%: look at Usage; at 100%: switch `costs` and `server` off |
| Firebase > Authentication > Usage | phone sign-in SMS | more than 3 times the normal day, or any SMS outside India | disable phone sign-in, region policy to +91 only |
| Firebase > Firestore > Usage | reads per day | above 2 times the 7-day average; or above 50 000 on the free plan | find the screen or script; `docs/COST_WATCH.md` |
| Firebase > Firestore > Usage | writes per day | above 3 times the 7-day average | look for a loop or an abusing account (`rate_limits`) |
| Firebase > Functions > Dashboard | errors | error rate above 5% for 10 minutes, or any function above 1 000 calls an hour that is normally quiet | switch `server` off, read the log |
| Firebase > Functions | invocations | more than 3 times the 7-day average | check `maxInstances`, a trigger loop |
| Crashlytics | crash-free users | below 99% on a version, or a new fatal issue affecting more than 1% | halt the rollout in Play Console |
| Cloud Logging log-based metric | `app_check_missing` count | after App Check is on: more than 5% of callable calls | do not turn enforcement on yet; before it: it is only a count |
| Admin > Health / dispatch monitor (in the app) | loads that expire with no bid | above 30% in a day, in a city | add supply, widen the rings, or switch `dispatch` off if prices look wrong |
| Admin > wallet | payout requests | more than 3 times the 7-day average, or one person above the daily limit | `money` group, freeze the wallet, check maker-checker |
| Admin > users | risk signals | more than 10 new `risk_signals` in an hour | look for a shared device; suspend the group |

## Daily and weekly looks (5 minutes)
- Daily: Usage and billing, Functions errors, Crashlytics (new issues), `deletion_requests`.
- Weekly: reconciliation report (`walletReconcile`), `audit_events` for `wallet_adjust` and `risk_change` made by staff, the translation sheet questions, `npm audit` for `functions/`.

## Rule of thumb
Switch first, ask later. A feature that is off for an hour costs less than a bill that is open for a day. Everything above can be undone from the same screen.
