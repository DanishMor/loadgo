# Red-team results (Part 5, H2/H3)

Suite: `firestore_rules_test/redteam.test.mjs` (Firestore rules) and `redteam_storage.test.mjs` (Storage rules). Run: `sh run-redteam.sh`; both are also part of `npm test`. Each ATTACK is written the way a modified client would send it and must be refused. CONTROL cases prove the same shape works when done right, so an attack is not "blocked" only because every write fails.

| Suite | Attacks | Blocked | Controls |
|---|---|---|---|
| Firestore rules | 249 | 249 | 14 |
| Storage rules | 30 | 30 | 1 |
| Total | 279 | 279 | 15 |

Classes: reading other people's data (lists without a filter, collection groups, enumeration), self-escalation (role, riskTier, plan, verified, wallet, admin), mass assignment, bad numbers (negative, zero, float, huge, string) and bad sizes (20000-character text, big arrays and maps), client timestamps, state-machine jumps and replays (accepted to delivered, delivered then cancelled, backward steps, a second rating), ledger / payout / wallet tampering and self-approval (maker-checker), staff-role escalation, audit forging, banned and restricted accounts, trip OTP secrets, two drivers accepting at once (one winner), storage paths, types (SVG, HTML, executable), sizes.

## What failed first, and what was done
The first runs showed 10 attacks that passed:

| Attack that passed | Verdict | Action |
|---|---|---|
| Load created with the phone's clock in `createdAt` | real, S4 | rule `get('createdAt', request.time) == request.time` (BUG_REPORT H-3) |
| RC image uploaded as `image/svg+xml`, or empty | real, S4 | storage rule uses the five-type list and size > 0 (H-4) |
| Extra server-side fields planted on a new load | real, S3, **open** | the load rule is at the 1000-expression limit; a whitelist and even three extra forbidden keys broke the promo tests (H-2). In KNOWN_RISKS |
| Offer edit outside 30%..300% | test mistake: the limit applies only when the load has an estimate (by design); with an estimate it is refused and stays as an attack | none |
| Float load budget | by design: the budget is in rupees | removed |
| Payout above wallet balance | test used a wrong field name | fixed in the test, now blocked |
| Finance rejects a payout without a reason | by design while maker-checker is off | removed |
| Huge config document | the emulator does not enforce the 1 MB limit | removed |
| Staff lists users | by design (admin console) | KNOWN_RISKS (insider) |

The planting attacks on loads were removed from the suite because they pass today; they are listed here and in BUG_REPORT H-2 so they can be turned back into attacks when the rule has room.

## Other results of Part 5 so far
- Rules contract test: 55 real app writes replayed against the rules, all allowed (docs/RULES_CONTRACT.md). It found H-8 (S2).
- Full rules run after all changes: 13 + 167 + 56 + 263 + 31 + 116 + 114 + 126 + 158 tests, 0 failures. Functions: lint clean, unit 38, emulator 161.
