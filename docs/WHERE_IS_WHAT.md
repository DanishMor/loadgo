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
| `dispatchV2` | Loads go to the nearest drivers first, then wider rings. Customers can pick Instant, Bid or Schedule. Turn on only after the new Firestore rules are published. Off: the old open load and offers work as before. | OFF | OFF | Customer > book a truck; Driver > incoming load card; Admin > dispatch monitor |
| `designV3` | Signature (Ivory) and Midnight (true black, Gold) looks with the Look picker in Settings; OFF shows Classic, the look from before the Elite plan, to everyone. | ON | ON | Settings > Look; Admin > Features > Signature look |
| `vehicleCatalog` | Vehicle pictures, approximate sizes, compare and "what fits" (lib/core/vehicles, catalog asset assets/vehicles/catalog.json, no reads). Shows "See all vehicles" and drawings in the booking truck step, a drawing on each offer in the bid room and on the truck board. | OFF | OFF | Admin > Features > Vehicle catalog; Book > truck step |
| `vehiclePhotos` | Drivers add photos of each truck (lib/core/photos/vehicle_photos_screen.dart from My vehicles), verifier and super admins review them (Admin > People > Vehicle photo review) and grant a six-month Photo-verified badge; customers see the badge on bid room offers (1 cached read per vehicle) and can tap it for the outside views. Needs photoUploads ON and the E18 rules published. | OFF | OFF | Admin > Features > Vehicle photos and badge; My vehicles > Vehicle photos |
| `cargoPhotos` | Customers add up to 3 goods photos to an open load on the bid room (lib/core/photos/cargo_photo_widgets.dart); drivers tap the photo icon on a load card to see them before bidding (1 read, only on tap); in the trip steps the driver adds a seal photo at pickup and damage photos at delivery (bookings/{id}/proofs, shown on the POD screen). Needs photoUploads ON and the E19 rules published. | OFF | OFF | Admin > Features > Goods and seal photos; bid room > Goods photos; driver load card > photo icon |
| `homeV3` | The customer Home tab is built from sections (lib/customer/v3/customer_home_v3.dart, lib/core/home): booking (always shown), trip now, vehicles (with vehicleCatalog), book again and templates, offers and invite (with the offers switch), the promise strip, Sahayak, recent bilty (starts hidden), more. The tune icon opens Arrange: drag or Move up / Move down, switch sections off, Reset. The order is kept on the phone. Needs designV3 ON. | OFF | OFF | Admin > Features > Arrangeable home; Home > tune icon |
| `driverHomeV3` | The driver Home tab is built from sections (lib/driver/v3, lib/core/home): online switch with the radar pulse (still with reduce-motion or LowEndMode) and a ring of today's earnings against the driver's own goal (kept on the phone), truck for today, alerts, trip now, return loads while goods are on board, papers health, level and streak (from delivered trips, nothing attached), quick actions, the 3 newest bids, more. Tune icon: Arrange. Needs designV3 ON. The demand strip waits for demandFeed. | OFF | OFF | Admin > Features > Arrangeable driver home; driver Home > tune icon |
| `fleetCommand` | On the transporter dashboard (lib/fleet/command_center_view.dart, lib/core/fleet/command_center.dart): counts of trucks on trip, booked, free, papers expired, not active; use over 30 days; what needs attention today (expired or soon papers, counter prices, trucks idle 7+ of 30 days, parties that owe); every truck with its state and route; open bids (newest 20); money to collect from the books. | OFF | OFF | Admin > Features > Transporter command center; Transporter > Dashboard |
| `adminOpsHome` | Admin Panel > Ops home (lib/admin/admin_ops_home_screen.dart): queue counts read once (count() aggregates; vehicle photos at most 50), dispatch picture, kill-switch shortcuts with one confirmation. | OFF | OFF | Admin > Features > Admin ops home; Admin Panel > Ops home |
| `navV3` | Global search (lib/core/search) also lists the bilty (LR) the person issued: by LR number, places, goods, vehicle, consignor, consignee or driver; a hit opens its booking. The v3 customer home gets a search button. Tabs already keep their state (IndexedStack); deep links and the notification bell were already there. | OFF | OFF | Admin > Features > Search in bilty; Search > Bilty |
| `onboardingV3` | First start on a new phone (lib/core/settings/onboarding_v3_screen.dart): three slides on the navy look: language pick and what the app is for; agreed price, one-time codes, tracking, SOS, hidden numbers; why location and notifications help (the system asks only when a feature needs them). Then the role pick. Drivers still give papers right after the profile (consent, KYC, pending), as before. Needs designV3 ON. | OFF | OFF | Admin > Features > First-run tour v3 |
| `priceCard` | Booking > price step > See the full price (lib/core/widgets/price_transparency_sheet.dart): every estimate line with why, platform fee and GST as their own lines, the no-hidden-fee promise, the customer's own price, and with `rateRange` where it sits (below, usual, above) against recent trips on the route. A guard test keeps every charge of the fare a shown line. The fair-price meter (FareMeter) was already in the price step. | OFF | OFF | Admin > Features > Full price card; Book > price step |
| `roundTrip` | Booking wizard > last step > Also book the way back: after the outbound load is posted, a second scheduled load from the drop to the pickup (same goods, truck and price) on the chosen date, through the same LoadService.post (rules, limits, rate limits unchanged). If the second post fails the first stays and the customer is told. | OFF | OFF | Admin > Features > Book the way back; Book > last step |
| `bulkUpload` | Business > Bulk post (lib/customer/bulk_post_screen.dart, lib/core/enterprise/bulk_loads.dart): rows copied from Excel or a CSV saved from it (byte-order mark, header row, quoted cells, semicolons), Copy template, Paste, a preview of every load and the reason for each bad row. Still at most 10 loads and the usual limits. No Excel file reader: no package was added (rule 7). | OFF | OFF | Admin > Features > Bulk loads from Excel; Business > Bulk post |
| `laneRfq` | Business hub > Lane tenders (lib/core/enterprise/lane_rfq_screens.dart): post a lane for 1 to 12 months with trips a month, see the rates (lowest first), award one or close. Transporter > shortcuts > Open lane tenders: send or change one rate per tender while it is open (drivers are allowed by the rules too). Records only (lane_rfqs, firestore.rules). | OFF | OFF | Admin > Features > Lane tenders; Business hub; Transporter dashboard |
| `quoteShare` | Booking wizard > last step > Share this quote (lib/core/share/quote_summary.dart, quote_share_sheet.dart): a card with route, goods, truck, date, every fare line (when the price is the estimate) and the total, sent as a picture, an A5 PDF in the person's language (Indian-script fonts of the LR) or text. No phone number, code or account id. | OFF | OFF | Admin > Features > Share a quote; Book > last step |
| `legalGateInsurance` | Legal gate. Trip screen (customer) > More > Ask for goods insurance (lib/core/insurance/insurance_request.dart): goods and value, a disclaimer and an "I understand this is a quote request, not insurance" tick, then one call to the InsuranceQuotes adapter through ConnectKit and its cost guard (3 a day per user and 100 a day in all, from the spec; kill switch = this gate; costs kill group). The app sells nothing and promises no cover. With no partner configured the customer is told nothing was sent. | OFF | OFF | Admin > Features > Legal > Insurance quote requests |
| `tollEstimate` | Price card (priceCard) also shows "Expected tolls on the way (approximate)", never added to the price, from the TollEstimator adapter through ConnectKit and its guard (lib/core/pricing/city_notes.dart TollLine). With no toll provider configured nothing is shown. | OFF | OFF | Admin > Features > Expected tolls |
| `cityNotes` | Admin Panel > City notes (super): notes per city; Book > route step shows the note for the pickup or drop city as written (config/city_notes, one read per session). | OFF | OFF | Admin > Features > City notes |
| `reliabilityBadges` | Offer cards (PublicTrustCard) show "Reliable" or "Highly reliable" from public_trust.reliability, which the trust function writes (functions/src/trust.js reliabilityTier; formula in docs/RELIABILITY.md; at least 10 finished trips). Only the word, never the numbers. The app mirror is lib/core/trust/reliability.dart. | OFF | OFF | Admin > Features > Reliability badges |
| `goingTo` | Recommended loads (lib/core/matching/load_ranker.dart): a load on a saved favourite route driven back gets +20 and the reason "Way back on your route". The "I am going to" planned route (onYourRoute, stopsOnRoute) and return loads near the trip's drop were already ranked (L5). | OFF | OFF | Admin > Features > Way back on your route; driver Loads > Recommended |
| `demandFeed` | Server job jobDemandCells (functions/src/demand.js, every 10 minutes) counts open loads by 4-character pickup geohash into demand_cells; the arrangeable driver home (driverHomeV3) shows the busiest cells near the driver (FirestoreDemandFeed, one query of up to 9 cells, counts older than 30 minutes ignored). Counts only. Dispatch also has a Black-tier head start (config dispatch.blackHeadStartSeconds, default 0; functions/src/dispatch.js headStartSeconds) for when the Black tier exists. | OFF | OFF | Admin > Features > Demand near drivers; driver Home > Busy areas near you |
| `uiV2` | The new home, 5-step booking, bid room, incoming-load card and trip screens. Turn it off to go back to the old screens. Works with or without the new dispatch switch. | ON | ON | Every role > home, booking, bids and trip screens |
| `bizCard` | Transporters and drivers can make a card (name, city, trucks, routes, verified mark) from their profile and send it as a picture on WhatsApp. The phone number is only on the card if the person turns it on each time. | OFF | OFF | Transporter and Driver > Profile > My business card |
| `khata` | A private notebook in Profile: add the people you do business with, write what they owe you or what you owe them, see the balance and send a statement on WhatsApp. Records only, no money moves. | OFF | OFF | Profile > Party khata |
| `safetyCheckin` | When the truck stands for 30 minutes on the road, the driver is asked "Are you OK?". One tap for fine, one tap for help (an SOS to support and, with SMS on, to saved contacts). No answer in 10 minutes tells support too. | OFF | OFF | Driver > trip screen (in transit) |
| `payHold` | With online payment on, the driver's earning and commission are written when the trip is delivered, not when the customer pays. A refund before delivery lowers what is released. Needs the functions deployed. Off: the driver is credited at once. | OFF | OFF | Admin > Features > Hold online payment until delivery |
| `rateRange` | Shows the usual price range of finished trips on the same route and truck type (at least 5 trips), when a load is posted. The server collects only amounts, never names or booking ids. Needs the functions deployed. | OFF | OFF | Customer > Post a load > price estimate card |
| `tripTrustCard` | The customer sees the driver's trips done, star rating, verified mark and member-since month on offers and on the trip. Numbers are written by the server only; needs the server trip counts switch and the functions deployed. No name, phone or papers. | OFF | OFF | Customer > offers on a load; Customer > trip screen |
| `appCheckEnforce` | The server refuses payment, maps, SMS and ID-check calls that do not carry the real app's proof (App Check). Turn on only after the app is registered and the logs show almost no missing proofs. Off: the calls are only counted. | OFF | OFF | Admin > Features > Refuse calls from unknown apps |
| `kycVerify` | After a driver saves papers, the server checks the numbers with the ID partner (or the sandbox) and shows the admin the answer. Without a partner the admin looks at the papers as before. Aadhaar: only the last four digits, never looked up. | OFF | OFF | Admin > Features > ID checks; Admin > Verification card |
| `smsGateway` | Short SMS for trip steps to a customer who cannot get push, and the SOS message to the person's own emergency contacts. Needs the functions deployed, an SMS partner key and approved templates. The login code is not affected. | OFF | OFF | Admin > Features > SMS messages |
| `liveLocation` | The driver shares the truck position during the trip (with their consent), with a visible notification, few database writes and a stop when the trip ends. Off: the older sharing while the trip screen is open. | OFF | OFF | Admin > Features > Live trip location; Driver trip screen |
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
| Ops home | (flag adminOpsHome) one page for the shift: open SOS, loads waiting 30+ minutes, drivers to verify, vehicle photos, claims and tickets (only the queues your role may open), open loads and running trips, kill-switch shortcuts (roles that may change Features) | all |
| City notes | (flag cityNotes) short notes per city that customers see in the booking route step (config/city_notes); write only what you have checked | super |
| Analytics | counters, trends | all |
| Users | search, risk tier, licence override, export | all |
| Driver verification | approve or reject drivers and transporters | super, verifier |
| Vehicles, Loads, Bookings (reassign, export) | lists and fixes | all (vehicles: super, verifier) |
| Vehicle photo review | (flag vehiclePhotos + photoUploads) drivers' truck photos grouped by vehicle; approve, or reject with a reason; grant the six-month Photo-verified badge once every required photo is approved | super, verifier |
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
| Dispatch monitor | live loads with ring and bids; time to first bid, time to fill, taken out of finished, price against estimate, loads that ended with no bid, no-show cancels (read once, Refresh) | super, ops |
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

## Part 3: paid-service code, new features, go-live (G1 to G45)

Every row sits behind a switch that is OFF (see the flag table above). Setup docs are named in the last column.

| What | Who | Where in the app | Code | Doc |
|---|---|---|---|---|
| Fingerprint / screen lock on earnings (real prompt) | driver, transporter | Settings; the earnings screens | `lib/core/security/local_auth_authenticator.dart` | KNOWN_ISSUES |
| Analytics funnel (7 steps, no personal data, only after consent) | all | none (invisible) | `lib/core/services/funnel.dart`, `analytics_events.dart` | ANALYTICS |
| Pay online (Razorpay checkout) | customer | Booking > payment card > Pay online | `lib/core/payments/online_pay.dart`, `functions/src/razorpay.js` | BLAZE_GO_LIVE, FUNCTIONS |
| Payment held until delivery | customer, driver | payment card ("Held safely...") | `payHold`, `functions/src/razorpay.js` (`releaseHeld`) | FUNCTIONS |
| Road distance on the post-load form | customer | Post a load > estimate card | `lib/core/maps/road_distance.dart`, `functions/src/maps.js` | MAPS_SETUP |
| Trip map | customer | Booking > Show on map | `lib/core/maps/trip_map.dart` | MAPS_SETUP |
| Usual price of a route | customer | Post a load > estimate card | `lib/core/pricing/route_rates.dart`, `functions/src/rates.js` | COST_WATCH |
| Live trip location (foreground service, consent) | driver, customer | Driver trip screen; customer "Last seen N min ago" | `lib/core/location/live_location_sharer.dart` | LIVE_LOCATION |
| SMS: trip step fallback and SOS text | customer, anyone with emergency contacts | none (invisible); SOS | `functions/src/sms.js`, `lib/core/services/safety_service.dart` | SMS_SETUP |
| ID checks and admin answer chips | admin (driver saves papers) | Admin > Verification card | `functions/src/kyc.js`, `lib/core/widgets/kyc_check_widgets.dart` | KYC_PARTNER_CHECKLIST |
| GST rules, IGST and place of supply on the invoice, e-way adapter | driver | Invoice PDF | `lib/core/gst/gst_rules.dart`, `lib/core/adapters/eway_adapter.dart` | GST_EWAY |
| App Check (Play Integrity) and the server guard | all | none | `lib/core/services/app_check_setup.dart`, `functions/src/appCheck.js` | APP_CHECK |
| Driver trust card | customer | offers on a load; booking screen | `lib/core/trust/public_trust_card.dart` | NEW_FEATURES_PLAN |
| Safety check-in | driver | Driver trip screen after a 30 minute stop | `lib/driver/safety_checkin_card.dart` | NEW_FEATURES_PLAN |
| Party khata | driver, transporter, customer | Profile > Party khata | `lib/core/khata/` | NEW_FEATURES_PLAN |
| Business card | driver, transporter | Profile > My business card | `lib/core/share/business_card.dart` | NEW_FEATURES_PLAN |
| Cost guards (switch, daily limits, App Check) | owner | Admin > Features; `config/*Limits` | `functions/src/quota.js` | COST_WATCH |
| Go-live | owner | none | `tool/golive_check.ps1`, `tool/status.ps1`, `tool/regression_batches.ps1` | GO_LIVE_RUNBOOK, PHONE_TEST_SHEET |
| Partner ideas not built | owner | none | none | PARTNER_OFFERS, COMPETITOR_MATRIX |

## Part 4 (UX v2 and the bid engine)

| What | Where |
|---|---|
| Switches `uiV2` (new screens, default ON) and `dispatchV2` (rings and bids, default OFF) | lib/core/features/features.dart, Admin > Features |
| Load mode, bid window, auto-accept, ring boost (data model) | lib/core/dispatch/dispatch_models.dart, lib/core/models/load.dart, firestore.rules (`validDispatchFields`) |
| Rings, delays, accept time, bid window by city (`config/dispatch`) | lib/core/dispatch/dispatch_config_service.dart |
| Bid extras (ETA, note chip, one edit) | firestore.rules (`validBidExtras`, `driverOfferUpdate`) |
| Component kit (RouteRibbon, FareMeter, CountdownRing, SlideToConfirm, BidCard, DriverMiniCard, StatusTimelineV2, sheets, chips, FeedbackKit) | lib/core/widgets/ds/ |
| Draw the kit to PNG | `flutter test tool/render_kit_test.dart` (writes build/ux_png) |
| Migrate old loads | tool/migrate_loads_mode.js (dry run first), docs/MIGRATIONS.md |

### Part 4 screens (all behind `uiV2`, the old screen returns when it is OFF)

| Screen | Who | Where in the app | Code |
|---|---|---|---|
| Customer home and shell (Home, Trips, Help, Profile) | customer | opens first | lib/customer/v2/customer_shell_v2.dart, customer_home_v2.dart |
| Trips tab (Active, Upcoming, Past, Book again) | customer | Trips | lib/customer/v2/trips_tab_v2.dart, trips_model.dart |
| Book wizard (5 steps, draft saved) | customer | Book a truck | lib/customer/v2/ (wizard files, U19) |
| Bid Room | customer | a bid-mode load | lib/customer/v2/ (U20) |
| Trip tracking v2, delivery section, Bilty card | customer | a booking | lib/customer/v2/tracking_v2_screen.dart, lib/core/bilty/bilty_entry_card.dart |
| Driver home v2 (online switch, Radar line, truck for today) | driver | opens first | lib/driver/v2/driver_home_v2.dart |
| Incoming Load Card | driver | rings over any screen while online | lib/driver/v2/incoming_load_screen.dart, incoming_load_host.dart |
| Driver bid sheet (also used by the transporter, for the company) | driver, transporter | feed card, My bids, Incoming card | lib/core/dispatch/driver_bid_sheet.dart |
| Loads feed (sort chips, saved routes, match reasons) | driver | Loads tab | lib/driver/v2/loads_feed_v2.dart, lib/driver/available_loads_view.dart |
| My bids (Waiting, Counter price, Selected, Lost) | driver | Home > My bids | lib/driver/v2/my_bids_v2.dart |
| Trip step card | driver | a trip | lib/driver/driver_trip_screen.dart (_StepCard) |
| Earnings and Where your money is | driver | Earnings tab | lib/driver/v2/earnings_v2.dart |
| Set-up card with state words and rejection box | driver | waiting-for-review screen | lib/auth/driver_onboarding_card.dart |
| Company bid through the bid sheet | transporter | Loads tab | lib/fleet/transporter_loads_screen.dart |
| Admin home in five groups | admin | Admin panel | lib/admin/admin_dashboard_screen.dart |
| Text of U30 to U36 (12 languages) | all | n/a | lib/core/l10n/ux2_feed_strings.dart |

## Part 5 (security, stability, performance)

| What | Where |
|---|---|
| Threat model, decisions, incident plan, alert thresholds | `docs/THREAT_MODEL.md`, `docs/SECURITY_DECISIONS.md`, `docs/INCIDENT_RESPONSE.md`, `docs/ALERT_THRESHOLDS.md` |
| Red-team attacks on the rules | `firestore_rules_test/redteam.test.mjs`, `firestore_rules_test/redteam_storage.test.mjs`, results in `docs/REDTEAM_RESULTS.md` |
| Rules against what the app really sends | `test/rules_contract_capture_test.dart` (records), `firestore_rules_test/contract.test.mjs` (replays), `firestore_rules_test/contract/captured.json`, `docs/RULES_CONTRACT.md` |
| Functions checklist, hostile-input tests | `docs/FUNCTIONS_SECURITY.md`, `functions/test/emulator/fuzz.test.js`, `functions/test/unit/hardening.test.js` |
| Emergency switches (one tap per group) | Admin > Features, top card; `lib/core/features/kill_switches.dart`, `lib/admin/admin_features_screen.dart` |
| Start-up fallback and guarded start-up steps | `lib/core/errors/startup_failed_app.dart`, `lib/main.dart` |
| One damaged document does not blank a list | `lib/core/services/safe_docs.dart`, `test/model_fuzz_test.dart`, `test/model_fuzz_known.txt` |
| Retry with backoff and jitter | `lib/core/network/with_retry.dart`, `test/chaos_test.dart` |
| Log cleaning (keys, phones, codes) | `lib/core/services/breadcrumbs.dart`, `test/redactor_part5_test.dart` |
| Link and input safety | `lib/core/share/share_links.dart`, `test/untrusted_input_test.dart` |
| Public pages: scripts, styles, headers, security.txt | `hosting/assets/`, `hosting/.well-known/security.txt`, `firebase.json`, templates in `tool/templates/hosting/`, `docs/VULNERABILITY_DISCLOSURE.md` |
| Android network and manifest rules | `android/app/src/main/res/xml/network_security_config.xml`, `android/app/src/main/AndroidManifest.xml`, `test/android_release_test.dart` |
| Speed budgets and cost guards | `test/perf_budget_test.dart`, `test/query_cost_guard_test.dart`, `test/lifecycle_guard_test.dart`, `docs/PERFORMANCE.md`, `docs/COST_WATCH.md` |
| Data map, secrets scan, dependencies | `docs/DATA_MAP.md`, `docs/SECRETS_SCAN_PART5.md`, `docs/DEPENDENCY_AUDIT_PART5.md` |
| Baseline, risks, scorecard, tester checklist | `docs/BASELINE.md`, `docs/KNOWN_RISKS.md`, `docs/SECURITY_SCORECARD.md`, `docs/PENTEST_CHECKLIST.md` |

## Load 20 FINAL2 additions
| What | Where |
|---|---|
| Diagnose problem (all roles) | Help > Diagnose problem; also the Diagnose button on every error screen (codes E-PERM, E-INDEX, E-NET, E-TIMEOUT) |
| Owner tools | `tool/phone.ps1`, `tool/run_regression.ps1`, `tool/status.ps1`, `tool/make_keystore.ps1`, `tool/change_package_id.ps1`, `node tool/check_indexes.js`, `node tool/rules_app_drift.js`, `node tool/screen_inventory.js`, `node tool/translation_merge.js`, `node tool/translation_apply.js` |
| Owner docs | docs/START_HERE.md, OWNER_TODO.md, RULES_PUBLISH.md, PHONE_SMOKE_SHEET.md, PHONE_TOOLS.md, TESTING.md, PILOT_DISTRIBUTION.md, SIZE.md, CI.md, NOT_FREE.md |
