# Incident response (Part 5, H31)

For the owner (and whoever is on call). First rule: **stop the damage, then understand it**. Switches first, investigation after.

## The emergency switches
Admin > Features (super admin) has a card at the top, "Emergency switches". One tap, one confirmation, one write to `config/features`; the app and the Cloud Functions read it within about 30 seconds. A group only turns features OFF; turning them back ON is done below the card, one feature at a time (Default / On / Off), so nothing comes back by accident. Every change is audited.

| Group (`killGroup_...`) | Switches turned off | Use it for |
|---|---|---|
| `money` | `paymentGateway`, `serverWallet`, `payHold` | payout fraud, wrong ledger lines, a payment bug |
| `costs` | `smsGateway`, `kycVerify`, `maps`, `adminBroadcast`, `photoUploads` | SMS pumping, a cost spike, an abused paid call |
| `dispatch` | `dispatchV2` | wrong prices in bids, a flood of bids, a dispatch bug |
| `push` | `pushNotifications` | notification spam or wrong text |
| `server` | `serverLimits`, `serverChatScan`, `serverCredits`, `serverTrust`, `serverJobs`, `serverAdminActions`, `serverDeletion`, `serverWallet`, `paymentGateway`, `pushNotifications`, `dispatchV2` | anything unknown on the server side: the app keeps running on the Firestore rules alone |

If the app itself cannot be opened by an admin (no phone at hand): Firebase console > Firestore > `config/features` > set `flags.<name>` to `false`. That is the same document.

Other brakes that need no code: Firebase Authentication > Sign-in method > disable phone sign-in (stops all new sign-ins and SMS cost at once); a user's `riskTier` to `banned` / `suspended` (Admin > users); `config/app_control` to show the update notice or a maintenance message.

## Playbooks

### Account takeover (someone uses another person's account)
1. Admin > the user > set risk tier `suspended` (they cannot transact; rules enforce it).
2. Devices screen of the user: revoke the unknown device. The refresh token revoke is a server step (`TODO(functions)`): until deployed, ask the person to sign out everywhere and change the SIM PIN.
3. If it is a pattern (many accounts, one device): `risk_signals` / `device_links` show the shared device; suspend the group; consider disabling phone sign-in for an hour.
4. Check `audit_events` for what the account did (payout requests, bank/UPI change). Payouts in `requested` or `approved`: reject with a reason.
5. Rollback tag: none needed (data only). Write what happened in the incident log (below).

### Data leak (someone saw data they should not)
1. Switch the `server` group off if a function is involved; otherwise find the rule or screen that exposed it (`docs/DATA_MAP.md` lists who may read what).
2. Fix the rule, run the whole rules suite (`sh run-tests.sh` in `firestore_rules_test`), publish the rules (owner step in `docs/BLOCKED.md`). A rule fix is live in about a minute.
3. If personal data left the system: the law may require telling the people and the authority within 72 hours; see `docs/LEGAL_QUESTIONS.md`. Rotate any key that was shown.
4. Rollback tag: `git tag` before each rules publish; to go back, publish the rules file of the previous tag.

### Wrong deploy (rules, functions or app)
1. Functions: switch the `server` group off, then redeploy the previous tag (`git checkout hardening-phase<n>` or the release tag, deploy that). Rules: publish the rules of the previous tag.
2. App: stop the staged rollout in Play Console (halt), and use `config/app_control` to ask people to wait for the fix. A bad build cannot be pulled from phones that already have it, only superseded.
3. Rollback tags in this repo: `pre-hardening` (before Part 5), `hardening-phase1..9` (each phase end), `ux-v2-phase5`, `ux-v2-phase6`.
4. Never deploy on a Friday evening; run `docs/GO_LIVE_RUNBOOK.md` smoke steps after every deploy (`serverStatus` call).

### Cost spike (the bill or the usage graph jumps)
1. Firebase console > Usage and billing: which product? Firestore reads (a runaway listener or a script), Functions (a loop), SMS, Maps.
2. Switch `costs` (paid calls) and/or `server` off. For a Firestore read storm: tighten the rules for the collection or switch off the feature behind it; the per-user hourly limits are already in the rules (`rate_limits`).
3. Budget alerts and thresholds: `docs/ALERT_THRESHOLDS.md`.
4. Afterwards: `docs/COST_WATCH.md` gets the new row and a guard test.

### Payout fraud (a driver or an insider drains the wallet)
1. `money` group off. Admin > Wallet freeze for the person (`wallet_freezes`), reject open payouts with a reason.
2. Maker-checker (`walletMakerChecker`) must be ON in production: nobody approves and pays their own request. Check `audit_events` type `payout_decision` for who approved what.
3. Reconcile: the `walletReconcile` job writes `reconciliation_reports`; compare ledger sums with payouts for the person.
4. Reverse a wrongly paid payout with the "reverse" action (reason required); it creates a signed adjustment line, nothing is deleted.

### SMS pumping (attackers trigger many SMS to premium numbers)
1. Disable phone sign-in in Firebase Authentication at once (that is where most SMS are sent) and switch `costs` off (our own SMS function).
2. Firebase Auth > Settings > SMS region policy: allow only India (+91).
3. Turn sign-in back on after the region policy and App Check are in place (`docs/APP_CHECK.md`).
4. The daily SMS quota (`config/sms`: per person and total) caps what our own function can send.

## Backup and restore
- Firestore export needs the Blaze plan (a scheduled export to a Cloud Storage bucket, `gcloud firestore export`). Until Blaze is on there is **no automatic backup**: this is a known risk (`docs/KNOWN_RISKS.md`).
- Plan once Blaze is on: a daily export to a bucket in the same region with a 30-day lifecycle rule; point-in-time recovery (7 days) enabled on the database; a restore drill once a quarter into a *new* database (never over production), then compare document counts.
- Auth users are not in the Firestore export: export them with `firebase auth:export` monthly (phone numbers are personal data: store the file encrypted, delete after 30 days).
- Storage (papers, proofs): enable object versioning on the bucket.

## After every incident
Write five lines in `docs/INCIDENT_LOG.md` (create it on the first incident): what happened, how it was found, the switch or fix, how long, what test now catches it. No names of customers; ids only.
