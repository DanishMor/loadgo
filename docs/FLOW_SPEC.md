# Flow spec (U2)

Two switches: `uiV2` (new screens, default ON) and `dispatchV2` (new data model and bid engine, default OFF until the new rules are published). With `dispatchV2` OFF the new screens use the old model: an open load plus offers.

## Load modes
| mode | meaning | needs dispatchV2 |
|---|---|---|
| `instant` | customer sets a price; nearby drivers are asked in rings; first valid accept wins | wave visibility and ring timing only |
| `bid` | a bid window opens; drivers send prices; customer counters once and accepts | bid fields only |
| `scheduled` | pickup later; goes out as `instant` at (pickup time minus lead) | no |

Old documents have no `mode`: treated as `instant`.

## Load states
`open` -> `matched` (accepted) -> `pickedUp` -> `inTransit` -> `delivered`; or `open` -> `expired` (nobody) / `cancelled`. Existing booking statuses are not renamed. `bidWindowEnds` closes bidding; `expired` loads can be re-posted with a higher price or a wider range.

## Customer flow
1. Home: Book a truck, three modes in one line, recent routes, active trip card, trust strip.
2. Wizard (5 steps, draft autosaved, back never loses data): Route, Goods, Vehicle, Price and Mode, Review (slide to confirm).
3. Instant: waiting screen with countdown ring and the current ring (3 / 7 / 15 km). No taker: "raise price +5% / +10%" or "wider range".
4. Bid: Bid Room. Bids arrive live. Sort chips: best price, nearest, top rated, fastest. One counter per bid. Accept closes the other bids. Auto-accept rule sheet. No bid: suggestions (raise price, more time, go instant, schedule).
5. Tracking: timeline, pickup OTP, delivery OTP, share, SOS, check-in, ETA, map if `maps` ON else route ribbon.
6. Delivery: proof of delivery, payment record, tip, rating, one-tap reorder. Bilty button on the booking detail.

## Driver flow
1. Home: online / offline switch, today's earnings, vehicle selector, Radar status, upcoming trips, document alerts.
2. Incoming Load Card (one at a time, queue for more): route ribbon, distance to pickup, trip km, goods, fare, countdown ring, slide to accept at the fare, send own price (chips -5, +5, +10, custom), skip (optional reason). Sound and vibration respect quiet hours and Low-end mode. Expired: "someone else took this load".
3. Bid sheet: range hint, ETA chips, note chips, edit once, withdraw. My bids: pending, countered, selected, lost.
4. Trip: arrived, loading proof, in transit, delivered OTP; offline queue.

## Dispatch (instant mode)
Ring r unlocks for a driver when `distanceKm(driver.lastLocation, pickup) <= ringsKm[r]` and `now - load.createdAt >= ringDelaySeconds[r]`. `DispatchWindow` (pure Dart) computes this. It is a client-side visibility layer; enforcement by a server wave is the `dispatchWave` function (flag `dispatchV2`, OFF) after deploy.

## Bid rules
- One active bid per driver per load; one edit; withdraw allowed.
- Price between 30% and 300% of the estimate (integer paise); a floor and ceiling check also lives in the rules.
- A driver never reads another driver's bid (rules: bid readable by its driver and the load owner only).
- Customer counters each bid at most once. Accept closes the rest in the same transaction.
- Limits per load and per hour are the existing offer limits.

## Auto-accept
`autoAccept {maxPaise, minRating, verifiedOnly}` on the load. While the customer app is open, the client evaluates every new bid and accepts the first one that fits, in the same accept transaction. The server skeleton `autoAcceptBids` (OFF) would do the same with the app closed; until deployed, the limit is: **nothing is accepted while the customer app is closed.**

## Incoming-load contract (LoadRadar)
One stream of loads that are open, unlocked for this driver (ring), match the driver's vehicle type, are not expired and not dismissed. Deduped by id, ordered by unlock time, shown one after another.

## State of the build (end of Part 4)
Customer flow 1 to 6 and driver flow 1 to 4 above are built behind `uiV2` (default ON). `dispatchV2` (rings, the bid window, the driver feed by ring) stays OFF until the rules are published. Differences from the sketch above: skip reasons on the Incoming Load Card are asked but not stored (no field on the server); a bid that was not chosen counts as Lost only when it is rejected or withdrawn (the data does not say another driver was picked); the card rings only while the app is open (push to a closed app waits for the Cloud Functions).
