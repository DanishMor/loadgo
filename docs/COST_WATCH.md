# Cost watch

LoadGo runs on Firebase (Auth, Firestore, Hosting, Crashlytics, Analytics, Remote Config). Today the only metered parts that can grow are **Firestore reads and writes** and **phone sign-in SMS**. Prices and free quotas change: the numbers below are what the author remembers and must be checked on the Firebase pricing page and in the console Usage tab before launch.

## Set this up first (10 minutes)
1. Firebase console > Usage and billing: check the plan (Spark = free with fixed daily limits, Blaze = pay as you go). Some things in docs/PAID_UPGRADE_PLAN.md need Blaze.
2. If you move to Blaze: set a **budget alert** in Google Cloud Billing (for example at 500, 1000 and 2000 rupees) so a surprise reaches your e-mail.
3. Bookmark Firestore > Usage (reads, writes, deletes per day) and look at it every morning of the pilot.
4. Auth > Usage: check how many SMS verifications you used. Use Firebase test phone numbers for your own testing.

## What the app already does to keep reads low
| Where | Rule | Code |
|---|---|---|
| Config documents (pricing, vehicle types, settings, offers, features, risk) | loaded once after sign-in, cached 15 minutes, forced only after an admin saves | `refreshAppConfig`, `TtlCache` |
| Reminders | recomputed every 5 minutes and only when the list changed; open loads page of 50 | `ReminderService` |
| Nearby loads | 4 geohash cells at most, newest page only | `LoadService.watchNearby` |
| My loads, open loads | live lists capped at 200 | `watchMine`, `watchOpen` |
| Lists in the apps | paged (`PagedLiveStream`), builders for long lists | `LiveStream`, `ListView.builder` |
| Admin analytics and trends | newest 1000 bookings per open, no live listener | `AdminConsoleService.recentBookings` |
| Admin supply and demand | one read of up to 500 loads + 500 vehicles + 500 drivers per button press | `AdminConsoleService.supplyDemand` |
| Admin unit economics | up to 1000 bookings + 1000 ledger lines per press | `AdminConsoleService.unitEconomics` |
| System health | five count queries per open (counts are cheap) | `AdminConsoleService.health` |
| Error log | 25% sample, one per 30 s, 10 per run | `ErrorLogService` |
| Offline cache | on (100 MB): repeated opens read from the phone | `Backend.enableOfflinePersistence` |

## Rough read budget (to adapt)
A busy customer or driver session is roughly 100 to 400 document reads (home, one list page, a booking, chat). If the free quota is 50,000 reads a day (check), that is on the order of 150 busy sessions a day before the quota ends. Admin screens add up to a few thousand reads per press: avoid refresh-spamming them. These are estimates, not measurements: measure in the pilot (Usage tab at the end of each day divided by active users) and write the real number here.

| Date | Active users | Reads | Writes | Reads per user |
|---|---|---|---|---|
| (fill in) | | | | |

## Things that make the bill jump (watch for them)
1. A new live listener without a `limit`.
2. A screen that reads a whole collection to count it (use count queries or a stored counter).
3. A timer that re-reads on every tick.
4. A list that shows many cards each reading its own extra document (N+1 reads).
5. A loop that writes on every GPS update. Driver location writes are throttled (about every 5 minutes for the profile, 15 seconds for a trip).
6. Admin tools left open on auto-refresh.
7. Demo data created in the live project (extra documents that everyone's lists read): remove it.

## When a limit is near
1. Admin > Features: switch off the heaviest optional feature (driver network, empty trucks board).
2. Raise the cache time or lower a `limit` in code (one number, one place).
3. Move to Blaze with a budget alert; move counting and reminders to Cloud Functions (docs/PAID_UPGRADE_PLAN.md step 1).

## Hosting
Policy pages and the trip page are tiny static files. The trip page makes one Firestore REST read per visit (the public `trip_shares/{token}` document), so every opened share link costs one read.

## MASTER-5 review (Tasks 9-14)
- **Listeners (Task 9).** test/listener_audit_test.dart counts listeners that read a whole query with no `limit` (68 today) and fails if the number grows; a second check makes sure a State class that listens also cancels. The admin "all" lists (fraud cases, claims, payouts, plan requests, incentive claims, rating flags) now carry `limit(300)`. The remaining unbounded ones are per-user lists that grow with history (a customer's or driver's bookings, offers, tickets, notifications, tips, ledger lines, a transporter's trips). Paging them needs a composite index per list (`createdAt` next to the owner field); bookings and loads already page through `newestPage`. Do the others when a real account passes about 300 documents.
- **One-time reads (Task 10).** A listener costs its first read like a `get()`, and after that only the documents that change. So a live stream on a list that rarely changes (saved places, templates, favourites, branches, vehicles) is as cheap as a fetch; the expensive ones are long-open listeners on busy collections, and those are all limited or paged (chat 200, network messages 200, admin lists 100-300). No stream was converted.
- **Indexes (Task 11).** test/index_audit_test.dart pins the composite indexes against the paged queries; no index was added or removed.
- **Config cache (Task 12).** All admin-managed config documents are read together at most every 15 minutes (`refreshAppConfig`). `config/support` and the referral bonus (`config/offers`) were read on every use; they now use the same 15-minute cache (and a new Firestore instance, such as another account, reads fresh).
- **Build size (Task 13).** `assets/` is 2 MB: nine Noto fonts used only when a PDF is made (loaded on demand, not at start) and two launcher images used by the icon tools. Nothing unused was found.
- **Start (Task 14).** The four independent local reads at start (language, connectivity, theme, simple mode) now run together instead of one after another. Everything else (config, push, deep links) was already after the first frame or in the background.

- **Server clock (MASTER-5 Task 20).** `DeviceService.syncClock` costs one write (the device's `lastSeenAt`) and one read at sign-in and at most every six hours of app use, so that the app knows when the phone's clock is wrong. At 1,000 daily users that is about 1,000-3,000 writes a day.
- M6 (2026-10-09): budgets raised by 3 raw StreamBuilders (pilot cards) and 1 listener (admin pilot lists).

## Part 2: functions and storage (F45)

Prices and free allowances change. The numbers below are planning guesses from general knowledge and were **not** checked against today's price pages: open the Firebase pricing page before you rely on them.

### How many function runs one action causes

| Action | Functions that run (switch must be ON) | Runs |
|---|---|---|
| A load is posted | `limitLoad`, `pushNewLoad` | 2 |
| A driver sends a rate | `limitOffer`, `pushOnOffer` | 2 |
| An offer is changed (select, withdraw) | `pushOnOfferSelected` | 1 per change |
| A chat message | `limitBookingMessage`, `scanBookingMessage`, `pushOnChat` | 3 |
| An in-app notification | `pushOnNotification` | 1 |
| A booking document is updated (every step) | `tripDelivered` (returns at once unless it is the delivered step) | 1 per update |
| A trip is delivered | the above, plus counting and the public summary | +0 |
| A ledger line or payout changes | `walletOnLedger` or `walletOnPayout` | 1 |
| A rating | `ratingAdded` | 1 |
| A credit line | `creditsBalance` | 1 |
| An admin action | callable | 1 |
| A photo | none (Storage rules only) | 0 |

Scheduled: `pushWaves` every 2 minutes is about 21,600 runs a month by itself. `jobHoldScheduled` about 2,900. Four daily jobs about 120. These run even with nobody using the app (they return at once when their switch is OFF, but a run is still a run). If cost matters, make `pushWaves` less frequent in `functions/index.js` before deploy.

### Worked example (one day, a small pilot)

100 loads, 300 offers, 4,000 chat messages, 600 notifications, 1,000 booking updates, 300 ledger/payout writes, 600 offer changes.

| Item | Runs/day |
|---|---|
| loads 100 x 2 | 200 |
| offers 300 x 2 | 600 |
| chat 4,000 x 3 | 12,000 |
| notifications | 600 |
| booking updates | 1,000 |
| ledger and payouts | 300 |
| offer changes | 600 |
| **Total** | **about 15,300** |

About 460,000 runs a month plus 25,000 scheduled: well under the free allowance Google lists for second-generation functions at the time of writing (check: about 2 million runs a month). **Chat is the biggest part**: three functions per message. If the bill rises, turn off `serverChatScan` first (the phone already scans), then `serverLimits` for messages.

Firestore reads from the functions: the chat scan reads the sender's last messages (up to about 10) and the limit check reads counts (aggregate counts, cheap). About 40,000 reads a day in the example; compare with the free daily reads on your plan.

### Storage

- A photo is shrunk to 1600 px and quality 75 before upload: expect about 200 to 500 KB.
- Example: 100 trips a day x 3 photos x 400 KB is about 120 MB a day, about 3.6 GB added each month. Papers add a little per new driver.
- Cost grows with the stored size and with downloads (admins viewing papers, both parties opening trip photos). Photos are read with `getData` and kept in memory for 20 pictures, so one open is one download.
- Set a lifecycle rule in the Cloud Console to delete trip photos after the retention period in `docs/DATA_RETENTION.md` (owner step). Account deletion removes `users/{uid}/` files.
- Watch: Console > Storage > Usage after the first week with `photoUploads` ON.

### Guards on every paid call (G17)

Each server call that costs money has three controls, all in Firestore so the owner can change them without a new deploy:

| Call | Switch (kill switch) | Daily limit per person / in total (default) | Limits document |
|---|---|---|---|
| `paymentCreateOrder` | `paymentGateway` | 30 / 1000 new orders | `config/paymentLimits` |
| `mapsRoute` | `maps` | 20 / 2000 route requests | `config/mapsLimits` |
| `smsSend`, `smsOnNotification` | `smsGateway` | 10 / 500 messages | `config/sms` |
| `kycVerify` | `kycVerify` | 6 / 300 checks | `config/kyc` |

Fields in every limits document: `perUserPerDay` and `totalPerDay`, whole numbers only (a text or negative value falls back to the default). The counters live in `quota_usage` (and `maps_usage`); both carry `expireAt`, so set a **TTL policy** on `expireAt` for them in the Console (Firestore > TTL). Switch off a call at once: Admin > Features. `test/cost_guards_test.dart` fails if a new paid call is added without a switch, a quota and a line here. Calls without a valid App Check proof are counted in the logs (docs/APP_CHECK.md).

### Route rates and held payments (G20, G21)

- Each delivered trip adds one small write to `route_rates` (plus a bookkeeping document `route_rates_seen`, which expires in 90 days: set a TTL policy on `expireAt`). The app reads one document per route and run. Held payments add one release transaction per delivered trip that had an online payment.

### Maps (G10)

- `mapsRoute` runs only on a new city pair (the answer is kept 30 days in `route_cache`), so a pilot day is a few dozen Routes requests. Hard caps: `config/mapsLimits.perUserPerDay` (20) and `totalPerDay` (2000). Key setup: docs/MAPS_SETUP.md.

### SMS (G12)

- `smsOnNotification` runs on every new in-app notification but exits at once unless the switch is on and the type is a trip step; one SMS (a few paise) only for people with no push token. `smsSend` only on SOS. Caps: `config/sms.perUserPerDay` (10) and `totalPerDay` (500). Setup: docs/SMS_SETUP.md.

### ID checks (G13)

- `kycVerify` runs about 3 times per new driver and only when a provider is set (no partner: it answers at once and costs nothing). The partner's price per check is the real cost (docs/KYC_PARTNER_CHECKLIST.md). Caps: `config/kyc.perUserPerDay` (6) and `totalPerDay` (300).

### Payment and push

- Razorpay charges per payment (the partner's fee, not Google's). Functions for payment run only when a person pays, when Razorpay sends the webhook (about 2 to 3 events per payment) or an admin refunds: tiny. Each payment writes about 6 documents (order, booking, 2 ledger lines, event, wallet recompute).
- FCM sending is free; the cost is the function runs above.

### Other triggers and schedules (small)

- `jobClearLocations` (every day 04:30): one indexed query on `locationUpdatedAt`, writes only for old finished trips; tiny. Live location itself costs about 12 to 120 writes per driving hour (docs/LIVE_LOCATION.md).

| Function | When it runs | Size |
|---|---|---|
| `referralCheck` | a new referral | a few a day |
| `deleteApprovedAccount` | an admin approves a deletion | rare, but each run touches many documents and files |
| `pushOnSos` | an SOS alert | rare |
| `pushOnPayout` | a payout changes state | a few a day |
| `jobExpireLoads` | daily 03:00 | 1 a day, reads open loads past their date |
| `jobSuspendExpiredDocs` | daily 03:30 | 1 a day, reads users with expired papers |
| `walletReconcile` | daily 04:00 | 1 a day, reads every wallet and its ledger: **grows with users**, watch the reads |
| `pushDocExpiry` | daily 09:00 | 1 a day, reads papers close to expiry |
| `autoAcceptBids` | a new bid (switch `dispatchV2`, OFF) | 1 per bid; returns at once when the switch is OFF; reads the load and its bids when ON |
| `dispatchWave` | every minute (switch `dispatchV2`, OFF) | 1440 a day but returns at once when the switch is OFF; when ON it reads open instant loads: watch the reads |

## Part 5 (H25): writes per flow, measured

From the 65 flows recorded for the rules contract test (`firestore_rules_test/contract/captured.json`, regenerated by `flutter test test/rules_contract_capture_test.dart`): the number of documents each real service call writes. Reads are not counted by the fake; the notes under the table say what each flow reads.

| Flow | Commits | Documents written | Collections |
|---|---|---|---|
| vehicle add | 1 | 2 | vehicles, vehicle_numbers |
| load plain without budget | 1 | 2 | loads, rate_limits |
| load plain with budget | 1 | 2 | loads, rate_limits |
| load freight estimate | 1 | 2 | loads, rate_limits |
| load extra stops slot upi | 1 | 2 | loads, rate_limits |
| load container seal | 1 | 2 | loads, rate_limits |
| load branch shipment leg | 1 | 2 | loads, rate_limits |
| load helpers | 1 | 2 | loads, rate_limits |
| load rental | 1 | 2 | loads, rate_limits |
| load movers | 1 | 2 | loads, rate_limits |
| load fragile high value | 1 | 2 | loads, rate_limits |
| load cost centre business | 1 | 2 | loads, rate_limits |
| load invited driver | 1 | 2 | loads, rate_limits |
| load favourites visibility | 1 | 2 | loads, rate_limits |
| load instant flag | 1 | 2 | loads, rate_limits |
| load mode instant | 1 | 2 | loads, rate_limits |
| load mode bid | 1 | 2 | loads, rate_limits |
| load mode bid auto accept | 1 | 2 | loads, rate_limits |
| load mode scheduled | 1 | 2 | loads, rate_limits |
| load posted by fleet | 1 | 2 | loads, rate_limits |
| load promo only | 1 | 4 | promos/uses, promos/slots, loads, rate_limits |
| load credits only | 1 | 3 | users/credits, loads, rate_limits |
| load promo and credits | 1 | 5 | users/credits, promos/uses, promos/slots, loads, rate_limits |
| offer send | 1 | 2 | rate_limits, offers |
| offer send eta note km | 1 | 2 | rate_limits, offers |
| offer send bid mode | 1 | 2 | rate_limits, offers |
| offer send as company | 1 | 2 | rate_limits, offers |
| offer edit once | 1 | 1 | offers |
| offer withdraw | 1 | 1 | offers |
| offer counter | 1 | 1 | offers |
| offer accept counter | 1 | 1 | offers |
| offer reject | 1 | 1 | offers |
| offer select | 1 | 1 | offers |
| offer confirm to booking | 1 | 6 | loads, vehicles, offers, bookings, audit_events, notifications |
| offer acceptBid | 1 | 2 | offers, offers |
| chat message by drv1 | 1 | 4 | rate_limits, bookings/messages, bookings/chat_reads, notifications |
| chat message by cust1 | 1 | 4 | rate_limits, bookings/messages, bookings/chat_reads, notifications |
| ticket create about a booking | 1 | 2 | rate_limits, tickets |
| ticket create plain | 1 | 2 | rate_limits, tickets |
| ticket escalate | 1 | 1 | tickets |
| ticket close | 1 | 1 | tickets |
| rating by cust1 | 1 | 2 | notifications, ratings |
| rating by drv1 | 1 | 2 | notifications, ratings |
| rating low stars (flag for review) | 1 | 3 | notifications, ratings, rating_flags |
| payout request | 1 | 3 | payouts, payout_counters, audit_events |
| truck post | 1 | 1 | truck_posts |
| lr issue by the customer | 1 | 5 | audit_events, lr_series, lrs, lrs/private, lrs/private |
| booking accept instant | 1 | 5 | loads, vehicles, bookings, audit_events, notifications |
| booking accept scheduled | 1 | 4 | loads, bookings, audit_events, notifications |
| trip step driver_arriving | 1 | 3 | bookings, audit_events, notifications |
| trip step loading | 1 | 3 | bookings, audit_events, notifications |
| trip step picked_up | 2 | 5 | bookings/otp_attempts, bookings, bookings/otp_attempts, audit_events, notifications |
| trip step in_transit | 1 | 3 | bookings, audit_events, notifications |
| trip step unloading | 1 | 3 | bookings, audit_events, notifications |
| trip step delivered | 2 | 7 | bookings/otp_attempts, loads, vehicles, bookings, bookings/otp_attempts, audit_events, notifications |

Reads per flow (from the code): posting a load reads the profile (role), the blocked-driver list and the rate-limit counter (3 reads); a bid reads the load, the profile and the counter (3); accepting reads the load, the profile, the vehicle and the offer (4); a trip step reads the booking, the vehicle (delivery) and the guess document (2 to 3); the chat send reads the last messages (up to 10) and the counter.

Changes in this round that cut reads:
- "All my bookings" (`BookingService.watchFor...`) and "my notifications" stream only the newest 500 / 200 documents (`newestPage`). Before, an account with thousands of rows read all of them at the start and again for every change. New index: notifications by `userId` + `createdAt` (deploy `firestore.indexes.json`; until then the query falls back to an unordered limited read).
- A damaged document is skipped instead of failing the whole list (`SafeDocs.parse`), so a bad row no longer causes endless refresh retries.
- The push router starts after the first frame; the picture cache is capped at 48 MB.
- Guard: `test/query_cost_guard_test.dart` counts listeners with no limit (57 left, almost all per-owner lists of a few rows); the number may only go down.

## Elite features
- E17 `vehicleCatalog`: 0 Firestore reads and 0 writes. The catalog is an app asset (`assets/vehicles/catalog.json`, about 9 KB) read once per app start and kept in memory; drawings are painted in code (no images downloaded). Turning the flag on changes no read count in booking, bid room or truck board.
- E18 `vehiclePhotos`: driver screen 1 listener per vehicle (at most 9 docs) + 1 badge read; each photo is 1 Storage upload (under 3 MB, usually a few hundred KB after the picker resize) + 1 write. Admin queue: 1 listener of at most 50 records + 1 vehicle read and 1 listener (9 docs) per vehicle opened; review 1 write, badge 1 write. A bid card badge (E18d) costs 1 read per vehicle shown.
- E19 `cargoPhotos`: a goods photo is 1 Storage upload (under 3 MB) + 1 write, at most 3 per load; the shipper's load screen keeps 1 listener of at most 3 docs; a driver opening a load reads at most 3 docs once, and each picture is 1 download kept in the 20-picture memory cache. Storage rules for these files make 1 Firestore get per upload or download. A seal photo is 1 upload + 1 write like other trip photos.
- E21 `homeV3` (customer): the same 2 listeners the v2 home has (own bookings, own loads) + 1 read of at most 3 LRs, only when the person turns "Recent bilty" on (it starts hidden). The section order and hidden list live in SharedPreferences (0 reads, 0 writes). The vehicle row reads the catalog asset (0 reads).
- E22 `driverHomeV3`: the vehicles and bookings listeners the v2 home already has; + 1 listener of at most 3 newest bids (index offers driverId + createdAt); while goods are on board, the open-loads listener the return-load suggestions already use on the trip screen. Level, streak, papers health and the daily goal are worked out on the phone (0 reads). The demand strip calls DemandFeed only while online and only when demandFeed is live (default: no call).
- E23 `fleetCommand`: reuses the dashboard listeners (vehicles, fleet bookings, members, books) + 1 listener of the newest 20 bids (index offers driverId + createdAt). Everything else is worked out on the phone.
- E24 `adminOpsHome`: per open (and per Refresh) the pilot control counts it already had + 3 count() aggregates (pending drivers, pending vehicle photos at most 50, open claims). No listener.
- E25 `navV3`: while the search screen is open, the bilty register listener (issuer, newest 200) the LR register already uses. Nothing when closed.
