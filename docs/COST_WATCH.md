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
