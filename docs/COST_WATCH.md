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

### Payment and push

- Razorpay charges per payment (the partner's fee, not Google's). Functions for payment run only when a person pays, when Razorpay sends the webhook (about 2 to 3 events per payment) or an admin refunds: tiny. Each payment writes about 6 documents (order, booking, 2 ledger lines, event, wallet recompute).
- FCM sending is free; the cost is the function runs above.

### Other triggers and schedules (small)

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
