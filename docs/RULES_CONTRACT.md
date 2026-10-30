# Rules contract: what the app really sends vs what the rules allow

**Why:** a field whitelist or a new check in `firestore.rules` is only safe if the real app still passes it. This test takes the writes from the app's own services, not from hand-made documents, so a rule that is stricter than the app fails here, before a driver finds it on a phone. If a rule rejects a field the app really sends, **the rule is fixed, not the app** (the old app is already installed).

## How it works
1. `test/rules_contract_capture_test.dart` runs the real services (`LoadService.post`, `OfferService.*`, `BookingService.*`, `ChatService.send`, `SupportService.*`, `RatingService.rate`, `PayoutService.request`, `PaymentService.*`, `DriverExtrasService.addTip`, `ClaimService.open`, `SafetyService.*`, `TripShareService`, `TruckBoardService.post`, `LrService.issue`, `VehicleService.add`, `TripOtpAttempts.recordGuess`) against fake Firestore. For each scenario it records the database before, runs the service, records it after, and keeps the difference (every document created, changed or deleted). Timestamps close to "now" are stored as server timestamps.
2. The result is `firestore_rules_test/contract/captured.json` (committed).
3. `firestore_rules_test/contract.test.mjs` seeds the "before" state with the rules off, then replays the recorded writes as **one batch per commit, signed in as the same person**, against `firestore.rules` on the emulator. Every scenario must be allowed.
4. It runs inside `npm test` (`run-tests.sh`, step "rules vs real app writes").

Regenerate after changing a service: `flutter test test/rules_contract_capture_test.dart`, then `sh run-tests.sh` (or only `node --test contract.test.mjs` inside an emulator).

## Covered (65 scenarios)

| Collection | Variants |
|---|---|
| `loads` (+ `rate_limits`) | plain without budget, plain with budget, freight with a real fare estimate (`PricingService.quote`), extra pickup and drop with slot and UPI payment, container and seal, branch + shipment + leg, helpers, rental (8 hours), movers, fragile + high value + declared value, cost centre + own business, invited driver, favourites visibility, `instant` flag, mode instant, mode bid, mode bid with auto-accept, mode scheduled, posted by a transporter, promo only, credits only, promo + credits |
| `promos/*/slots`, `promos/*/uses`, `users/*/credits` | written together with the promo and credits loads (same batch) |
| `vehicles`, `vehicle_numbers` | add a vehicle (vehicle + number reservation) |
| `offers` (bids) | send, send with ETA + note chip + pickup km, send on a bid-mode load, send as a company, edit once, withdraw, customer counter, driver accepts the counter, customer rejects, customer selects, driver confirms a selected bid (booking + load match + vehicle), customer `acceptBid` |
| `bookings` (+ `loads`, `vehicles`) | driver accepts an instant load, driver accepts a scheduled load, trip steps `driver_arriving`, `loading`, `picked_up`, `in_transit`, `unloading`, `delivered` |
| `bookings/*/otp_attempts` | the guess is stored in one commit and the step in the next (two commits, as the app does), for pickup and delivery |
| `bookings/*/messages` | chat message by the driver and by the customer |
| `tickets` | create about a booking, create plain, escalate, close |
| `ratings`, `rating_flags` | rating by the customer, by the driver, low stars (flag for review) |
| `payouts`, `payout_counters`, `audit_events` | payout request with the day counter and the audit line |
| `truck_posts` | post an empty truck |
| `lrs`, `lr_series`, `lrs/*/private` | issue an LR (bilty) as the customer |
| `bookings`, `ledger` | the customer marks the trip paid; the driver confirms the money (the booking and the two ledger lines in one batch) |
| `tips` | the customer adds a tip after delivery |
| `claims` (+ events) | opened by the customer, opened by the driver |
| `sos_alerts`, `bookings` | SOS by the driver; breakdown reported by the driver |
| `trip_shares` | the customer shares the trip link |
| `bookings`, `loads`, `vehicles`, `users`, `audit_events`, `notifications` | the driver cancels before pickup (the load reopens and loses driver, booking and match time; cancel count +1) |
| `loads`, `users`, `audit_events` | the customer cancels an open load (with a real fare estimate) |
| `loads/*/cargo`, `bookings/*/proofs` | E19: the shipper adds a goods photo record (`CargoPhotoService.upload`); the driver adds a seal photo record (`PhotoService.upload`, kind `seal`) |
| `lane_rfqs`, `lane_rfqs/*/bids` | E30: a business posts a lane tender, a transporter sends a rate, the business awards it |

## Not covered yet (planned, in this order)
- `lrs`: new version, cancel, share links.
- `truck_requests` (request, answer, withdraw), `calls`, `reports`, `deletion_requests`, scheduled-booking cancel by the customer, recurring loads.
- `wallets` and `payouts` decisions by staff (written by admin screens and the functions, not by the customer/driver services).
- User profile writes (`users/{uid}` on sign-up, KYC, preferences): they are spread over many screens, not one service.
- Business and fleet collections (`fleet_members`, `business_*`).

## Limits of the method
- It replays the **final difference** of a service call, not its internal reads. A service that reads a document the rules also read is covered only if that document is in the recorded "before" state.
- Fake Firestore does not overlap transactions and drops the other fields of a user document on `set(..., merge: true)` with an increment; the harness works around the second (see the comment in the capture test).
- Dates (a bid window, a pickup date) are moved to today when the fixture is replayed, so it never goes stale.

## What this test found
- **A real bug (S2, BUG_REPORT H-8):** a load posted with a real fare estimate and a promo code (and credits) was refused by the rules, because the `loads` create rule hit the 1000-expression limit. The older rules tests used a tiny estimate, so they never saw it. Fixed by cheaper but equal checks (absent stops are skipped, one list test for helpers, the credits checks that belong to the credit line moved into its own rule).
- Two false alarms taught the harness: the test once reserved the promo against the wrong total (the rules were right to refuse), and fake Firestore losing user fields made a cancellation look refused. Neither was a rules bug.
- The money, claim, SOS, share and cancellation flows needed no rule change.
- The `loads` create rule is still close to the limit (a key whitelist did not fit: H-2). Any new check there must pass this test and rules slice 3 (promo).

## Rule for the future
A change to a `validX` function or a `hasOnly([...])` list in `firestore.rules` is not done until `sh run-tests.sh` is green, including this step.
