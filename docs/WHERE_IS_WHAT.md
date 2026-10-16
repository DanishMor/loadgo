# Where is what

Every feature, for every role: which screen, which menu. Flags are the switches in **Admin > Features and pilot
mode** (`config/features`). In pilot mode (the default for a new project) only the core freight flow, support and safety
are on; **Pilot** and **Normal** below are the defaults of each flag in pilot mode and with pilot mode off. An admin can
force any flag On or Off; a forced value always wins. A flag that is OFF hides its entry everywhere.

## Feature flags

| Flag | What it means | Pilot | Normal | Where it shows |
|---|---|---|---|---|
| `driverNetwork` | Drivers connect with each other, share location with trusted drivers, make groups | OFF | ON | Driver Home > Driver network tile; Profile > Driver network |
| `emptyTrucks` | Board of empty trucks (customers find, drivers post) | OFF | ON | Customer Home > Empty trucks card; Driver Home > Empty trucks tile |
| `businessTools` | Company tools: team, approvals, cost centres, monthly statement | OFF | ON | Customer Home > More for you > Business tools; Profile > Business tools |
| `rentalMovers` | Hourly rental and packers and movers on the Post Load screen | OFF | ON | Customer > Post Load > booking type |
| `driverRewards` | Tips, bonuses and paid plans for drivers | OFF | ON | Driver > Earnings tab > Rewards |
| `tripShare` | 24-hour trip link for family (no phone number, no live position) | ON | ON | Trip screens > Share trip |
| `problemReport` | Two-tap "Report a problem" on trip screens and in Help | ON | ON | Trip screens, Help |
| `transporter` | The Transporter role (company profile, bids, assigning, books) | ON | ON | First screen > Transporter card; Transporter app |
| `bilty` | Numbered LR (bilty) with driver, consignee and full copies, PDF and share link | ON | ON | Trip screen > LR; Transporter > Trips > LR |
| `walletHub` | New earnings and accounts hub for every role (records only) | OFF | OFF | Admin > Features > Earnings and accounts hub |
| `walletMakerChecker` | A payout is approved by one finance admin and paid by another (rules enforce it) | OFF | OFF | Admin > Features > Two admins for payouts |
| `walletStepUp` | A fresh SMS code before a payout request or a change of payout details | OFF | OFF | Admin > Features > Fresh code before payouts |
| `walletLimits` | Waiting time after payout details change and a daily payout count and total limit (config/wallet) | OFF | OFF | Admin > Features > Payout limits and waiting time |
| `appLock` | Optional fingerprint / screen lock on the earnings screens | OFF | OFF | Admin > Features > Fingerprint lock for earnings; Settings |
| `serverLimits` | The server counts bids, chat messages and code requests per hour and refuses extra ones, even from a modified app. | OFF | OFF | Admin > Features > Server hourly limits |
| `serverChatScan` | The server scans every chat message again for phone numbers and links and applies the strike steps. | OFF | OFF | Admin > Features > Server chat check |
| `serverCredits` | The server settles promo, credits and referral bonuses so a modified app cannot change the balance. | OFF | OFF | Admin > Features > Server credits and referral |
| `serverTrust` | The server counts finished trips and writes a safe public trust summary for each driver. | OFF | OFF | Admin > Features > Server trip counts |
| `serverJobs` | The server expires old open loads, starts scheduled bookings and suspends drivers with expired documents. | OFF | OFF | Admin > Features > Server timed jobs |
| `serverAdminActions` | Risk tier and driver approval are done by the server and logged, not by the admin phone itself. | OFF | OFF | Admin > Features > Server admin actions |
| `serverDeletion` | The server removes a person's data, sign-in and files when an account deletion is approved. | OFF | OFF | Admin > Features > Server account deletion |
| `serverWallet` | The server adds up the ledger, writes the summary, checks payouts and runs the daily check. | OFF | OFF | Admin > Features > Server earnings checks |
| `paymentGateway` | Customers can pay a booking online through the payment partner (test mode until the owner adds keys). | OFF | OFF | Admin > Features > Online payment (test mode) |
| `pushNotifications` | Phones get push messages for new loads, offers, trip steps and chat. Needs the functions deployed. | OFF | OFF | Admin > Features > Push notifications |
| `adminBroadcast` | Admins can send an announcement push to a role or to everyone. | OFF | OFF | Admin > Features > Admin announcements by push |
| `photoUploads` | Documents and trip photos can be added from the phone camera or gallery. Needs Storage switched on. | OFF | OFF | Admin > Features > Photo uploads |
| `maps` | Real road distance and time for fares and trips, and the trip map. Needs the functions deployed and a Maps key set as a secret. Off: the built-in city table. | OFF | OFF | Admin > Features > Maps and road distance |
| `secureScreens` | No screenshots or screen recording on the login code, documents, private LR copy, earnings and trip code screens (Android release builds) | OFF | OFF | Admin > Features > Block screenshots on private screens |

Other switches that are not in the list above:

* Promo codes, credits, referral: **Admin > Offers** (three switches, OFF by default). Customer Home > More for you > Offers and credits.
* Surge pricing: `config/pricing.surge.enabled` (OFF). Admin > Config.
* Demo data in a release build: `config/app.allowDemo` (OFF). Admin > Demo data.
* Simple mode for drivers (big buttons): the driver's own switch, Profile > Settings.

## Customer

Bottom bar: **Home**, **Bookings**, **Loads**, **Profile**.

| Feature | Where |
|---|---|
| Book a truck / post a load | Home > hero button, Quick actions > Book a truck / Post a load; Loads tab > Post |
| Book a bike | Home > Quick actions > Book a bike |
| Make a booking slip (consignor LR) with copies, PDF and link; answer inspection requests | Bookings tab > the booking > LR > Bilty (LR); the notification bell |
| Track a shipment, status, ETA, chat, call, LR, POD, invoice | Bookings tab > the booking (chat, call, LR, help and report buttons are on the trip screen) |
| My loads, offers on a load (counter, pick one) | Loads tab > a load |
| Documents (invoices, LR, POD, e-way bills) | Home > Quick actions > Documents |
| Empty trucks board | Home > Quick actions > Empty trucks (flag `emptyTrucks`) |
| Trip history | Home > More for you > Trip history; Profile > Trip history |
| Saved loads (templates), repeat | Home > More for you > Load templates |
| Payments and credits | Home > More for you > Transactions, My spending |
| Favourite drivers | Home > More for you > Favourite drivers |
| My analytics | Home > More for you > My analytics |
| Offers and credits, referral | Home > More for you > Offers and credits (OFF until an Offers switch is on) |
| Business tools | Home > More for you > Business tools (flag `businessTools`) |
| Search | Home > search box |
| Sahayak (assistant) | Home > top right assistant button |
| Notifications | Home > top right bell |
| Language | Home > top right globe; Profile; Settings |
| Edit profile, verification card, logout | Profile tab |
| Settings (theme, notification choices, consents, devices, terms, privacy, refund policy, linked accounts, change mobile number, download my data, delete account) | Profile > Settings |
| Help and support, tickets | Profile > Help and support |
| The three first steps of a role (shown once, "Got it" hides them) | Home > top card |
| A notice from LoadGo (announcement banner) | Home > top, above the first steps |
| Dispute: what the trip records show (status times, pickup / delivery proof, notes, cancellation charge) | Bookings tab > a booking > Report a problem > the dispute |
| Emergency contacts, SOS | Profile > Emergency contacts; trip screen > SOS |
| Chat and in-app call | Trip screen > Chat, Call (phone numbers are never shown) |
| Report a problem | Trip screen; Help (flag `problemReport`) |
| Trip share link | Trip screen > Share trip (flag `tripShare`) |

## Driver

Bottom bar: **Home**, **Loads**, **Trips**, **Earnings**, **Profile**.

| Feature | Where |
|---|---|
| Online / offline, nearby loads | Home > top; Loads tab |
| Accept a load, make an offer | Loads tab > a load |
| Active trip, next status, OTP steps, proofs, navigate | Home > Active trip; Trips tab |
| Trips from my transporter | Home > Trips from your transporter (only when a transporter assigned one) |
| Transporter invites, attach my vehicle | Home > the fleet card (accept, attach or detach a vehicle, leave) |
| My truck, vehicle papers, expiry | Home > My truck, Documents and KYC |
| LR (driver copy): route, goods, "Rate hidden by owner"; Show inspection, save the inspection copy | Trip screen > LR (driver copy) |
| Documents center (invoices, LR, POD) | Home > Documents center |
| My offers | Home > My offers |
| Wallet | Home > Wallet; Earnings tab |
| Earnings statement (this month, last month, this financial year, all time) as CSV or PDF | Home > Wallet > Earnings statement |
| City demand | Home > City demand |
| Empty trucks | Home > Empty trucks (flag `emptyTrucks`) |
| My analytics | Home > My analytics; Profile |
| Favourite routes, pickup alerts | Home > Favourite routes; Loads tab |
| Driver network | Home > Driver network (flag `driverNetwork`) |
| Earnings, history, tips, bonuses, plans | Earnings tab (Rewards: flag `driverRewards`) |
| Edit documents (licence, RC, PAN) | Profile > Edit documents |
| Chat and in-app call | Trip screen > Chat, Call |
| SOS, emergency contacts, trip share | Trip screen; Profile |
| Simple mode, settings, help, delete account | Profile > Settings; Profile > Help and support |

## Transporter

Bottom bar: **Dashboard**, **Loads**, **Trips**, **Fleet**, **Profile**. Flag: `transporter`.

| Feature | Where |
|---|---|
| Company profile, Verified badge | Dashboard > Company profile |
| Papers expiring soon (own and attached vehicles) | Dashboard top card |
| Books (margin, owed to drivers, party-wise due) | Dashboard > Books; Trips > a company trip > Books |
| Party statement and the all-parties export (CSV, PDF) | Dashboard > Books > the share icon on a party; "Export all parties" |
| Analytics (utilisation, revenue, expenses) | Dashboard > Analytics |
| Open loads, bid for the company, post a load | Loads tab > Bid for company; "Post a load" button |
| My bids, confirm a selected bid | Trips tab > My bids |
| Assign or change the vehicle and driver | Trips tab > a company trip |
| Late trips, LR / bilty, trip details | Trips tab |
| Issue an LR, new version, cancel, copies, PDF, link; answer inspection requests, allow inspection in advance | Trips tab > LR > Bilty (LR); the notification bell |
| Vehicles (own and attached) | Fleet tab > Vehicles |
| Drivers, invite by phone | Fleet tab > Drivers |
| Chat and in-app call (customer, assigned driver) | Trip details > Chat, Call, Call driver |
| Sahayak, notifications | Top right |
| Settings, help, emergency contacts, logout | Profile tab |

## Admin

Admin Panel: **Profile > Admin** (only for accounts in `admins/{uid}`). The panel shows only what the staff role may use.

| Screen | What for | Staff roles |
|---|---|---|
| Analytics | counters, trends | all |
| Users | search, risk tier, licence override, export | all |
| Driver verification | approve or reject drivers and transporters | super, verifier |
| Vehicles, Loads, Bookings (reassign, export) | lists and fixes | all (vehicles: super, verifier) |
| Tickets, SOS | support work | super, support (SOS also ops) |
| Reports | user reports, open a case, **open the chat for review** | super, support, ops |
| Chat violations | strikes, suspensions, phone numbers (logged) | super, support, ops |
| Signals, Fraud cases, Flagged users | anti-fraud | super, ops (signals also verifier) |
| Disputes, Rating flags, Rating bursts | claims and ratings; **Hide comment** blanks an abusive rating comment (the stars stay) | super, support (ops for ratings; hiding: super, support) |
| Sahayak, Feedback, Templates | assistant and reply templates | super, support |
| Health | app health | super, ops |
| Supply and demand, Unit economics | numbers | super (supply and demand also ops) |
| Pilot control room | today's sign-ups, drivers sharing location, open / unfilled loads, running trips, open SOS and tickets | super, ops, support |
| Strike appeals | a person's reason for asking us to look at a chat strike again; take one strike off (and lift the suspension if the lower count no longer needs it) or keep it, with a note | super, support, ops |
| Alerts | what needs a person now, most urgent first, only what your role can work on: open SOS, fraud cases, unreviewed risk signals, people with 3+ chat strikes, papers running out together, holds, deletion requests | all staff |
| Search everything | one box for a name, phone, vehicle number (verifiers, ops, support, super), booking id or LR number; phones are matched but never shown | all staff |
| Payment aging | delivered trips whose payment record is not done, by age (who is slow: customer or driver) with a Remind button, one per 6 hours | super, ops, support |
| Use-again survey | share of customers and drivers who would use the app again after a delivered trip | super, ops |
| Pilot cohorts | per week of posting: time to first bid and to a driver, customers who came back, cancel reasons; copy as CSV | super, ops |
| Pilot report | today's or last 7 days' numbers as plain text to copy into WhatsApp | super, ops |
| Manual dispatch | loads waiting 30+ minutes: suggest a nearby fitting driver (the driver sees it on Home and accepts as usual), add a call-back note about the customer | super, ops |
| Waitlist | people who asked to hear when a closed route opens (search, CSV) | super, ops |
| Invite codes | pilot codes per role / route with uses and last day; let a phone number in without a code | super, ops |
| Pilot funnel | where customers, drivers and transporters stop before a first delivery | super, ops |
| Features | the flags above, with a line of meaning for each | super |
| Demo data | seed and remove demo data | super |
| Deletion requests | account deletions | super, support |
| Audit log | who did what (includes number views and chat opens) | super, ops |
| Driver rewards, Payouts, Offers, Config | money records and settings; Config also has the **Announcement banner** (text per language, level, last day, roles) | super |
| Announcement push | an announcement push to drivers, customers, transporters or everyone (switch Admin > Features > Admin announcements by push; the server sends it, honours each person's notification switches and quiet hours, and writes the audit line) | super, support, ops |
| Finance | payout queue with two admins (one approves, a different one marks paid with the bank or UPI reference), reversal, daily check of ledger against payouts and summaries, warnings for big or repeated payouts, freeze and correction tools, CSV copy | super, finance |

Every admin list (tickets, SOS, reports, audit log, vehicles, deletion requests ...) has a search box, saved filters (kept on the device), "Show 50 more" and **Export CSV** of what is on screen (no phone numbers, e-mail, KYC or free text). Every admin change also writes an audit event.

## Design system (Load 20, Phase 2 to 4)
| What | Where |
|---|---|
| Colours, type scale (DsType, DsStyle consts), spacing, radius, elevation, motion; legacy colours (DsLegacy), hero gradient (DsHero), `context.ds` | `lib/core/theme/design_tokens.dart` |
| Material 3 light and dark theme, RoleAccents (customer, driver, transporter), Low-end switch | `lib/core/theme/app_theme.dart` |
| Contrast maths (`contrastRatio`, `ensureContrast`) | `lib/core/theme/contrast.dart` |
| Brand font Mukta (OFL) + Noto fallbacks | `assets/fonts/mukta/`, `pubspec.yaml`, `test/typography_test.dart` |
| Buttons, status badges (one colour per status), OTP field, text fields, top bar, bottom nav, dialogs, sheets, snackbars | `lib/core/widgets/ds/` (`app_button`, `status_badge`, `otp_field`, `app_text_field`, `app_top_bar`, `app_bottom_nav`, `app_dialogs`) |
| Money display, balance hide switch | `lib/core/widgets/ds/money_text.dart` |
| Skeleton loading, drawn pictures for empty and error states | `lib/core/widgets/ds/skeleton.dart`, `illustrations.dart` |
| Logo mark, wordmark, lockup | `lib/core/widgets/ds/brand_logo.dart`; icons from `tool/make_brand_assets_test.dart` (`docs/ICON_AND_SPLASH.md`) |
| Entrance animations (reduce-motion aware), haptics (Settings > Touch feedback) | `lib/core/widgets/ds/motion.dart`, `haptics.dart` |
| Login pieces (header, phone field) | `lib/auth/login_widgets.dart` |
| Guard: no hard-coded colour or text style outside the theme (table is empty) | `tool/theme_guard.dart`, `test/theme_guard_test.dart`, `docs/THEME_EXCEPTIONS.md` |
| Brand rules, name checks | `docs/BRAND.md`, `docs/NAME_CHECKLIST.md`, `docs/RENAME.md` |

## Part 2: server, photos, payments, admin web (F1 to F46)

| Thing | Where |
|---|---|
| Login code limits (resend wait, hourly cap, lock) | `lib/core/security/otp_limits.dart`, `docs/OTP_SECURITY.md` |
| Trip code lock (enforced by rules) | `firestore.rules` (`otp_attempts`), `lib/core/services/trip_otp_attempts.dart` |
| Screenshot block | `lib/core/security/secure_screen.dart`, `MainActivity.kt` (flag `secureScreens`) |
| Money in whole paise, wallet book | `lib/core/money/`, `lib/core/wallet/` |
| Earnings hubs (driver, customer, transporter) | `lib/core/wallet/hub/`, entry `lib/driver/wallet_entry.dart` (flag `walletHub`) |
| Fresh code before payouts, limits, app lock | `lib/core/wallet/step_up.dart`, `app_lock.dart` (flags `walletStepUp`, `walletLimits`, `appLock`) |
| Admin Finance and payouts with two people | `lib/admin/admin_finance_screen.dart` (flag `walletMakerChecker`), `docs/WALLET_SECURITY.md` |
| Cloud Functions (38) | `functions/index.js`, `functions/src/`, `docs/FUNCTIONS.md` |
| Server actions with phone fallback | `lib/core/services/server_actions.dart` |
| Check the server | Admin > System health > Check server (`lib/admin/admin_health_screen.dart`) |
| Push: token, channels, tap routing | `lib/core/services/push_service.dart`, `lib/core/notifications/`, `MainActivity.kt` |
| Announcement push | Admin > Announcement push (`lib/admin/admin_broadcast_screen.dart`, flag `adminBroadcast`) |
| Photos and papers (add) | `lib/core/photos/` (`PhotoAttach`): Vehicle documents, trip pickup/delivery dialog, damage claim, driver profile (flag `photoUploads`) |
| Papers seen by admin | Admin > Driver verification > Show papers (`lib/admin/admin_uploads.dart`) |
| Trip photos | POD screen (`lib/core/documents/pod_screen.dart`); proof photo in the LR PDF (`lib/core/bilty/lr_pdf.dart`) |
| Storage rules | `storage.rules`, `firestore_rules_test/storage.test.mjs` |
| Online payment (test mode) | `lib/core/adapters/razorpay_gateway.dart`, `functions/src/razorpay.js` (flag `paymentGateway`) |
| KYC and SMS partner skeletons | `lib/core/adapters/partner_adapters.dart` |
| Admin-only web build | `lib/admin/admin_web_shell.dart`, `lib/core/app_mode.dart`, `docs/ADMIN_WEB.md` |
| Go-live order, release list, known issues | `docs/BLAZE_GO_LIVE.md`, `docs/RELEASE_CANDIDATE.md`, `docs/KNOWN_ISSUES.md` |
| Texts for the native reader, logo brief | `docs/TRANSLATION_REVIEW.csv`, `docs/LOGO_BRIEF.md` |
| Integration tests (all emulators) | `functions/integration/`, `firebase.integration.json` |
