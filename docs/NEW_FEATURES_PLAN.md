# New features plan (G2)

Chosen from docs/COMPETITOR_MATRIX.md. Priority rule: needed for the pilot, trust and safety, stops commission bypass, easy for a low-literacy driver, free or cheap, fits the design system. Free features come first (G18 onward), paid-dependent ones last.

Common to every feature: a flag in `config/features` (default OFF, shown in Admin > Features and WHERE_IS_WHAT), strings in 12 languages, money as integer paise, widgets from `core/widgets`, no cross-imports between customer/driver/fleet/admin, a rules test and one end-to-end test, old behaviour untouched when the flag is OFF.

| # | Feature (flag) | What | Who | How | Data | Rules | Risk |
|---|---|---|---|---|---|---|---|
| 1 | Trusted contacts (`trustedContacts`) | Up to 3 contacts get the trip link automatically when a trip starts | Customer, driver | Extends `tripShare`; contact name + number kept on the phone and in `users/{uid}/trusted` | name, number | owner only, max 3 | Number privacy; never shown to the other party |
| 2 | Safety check-in (`safetyCheckin`) | If the truck stops long or leaves the route, ask the driver "All OK?"; no answer tells support | Driver, support | Uses `trip_watcher`; one tap Yes / Need help | `trips/{id}/checkins` | parties write own | False alarms; threshold in config |
| 3 | Driver and truck trust card (`tripTrustCard`) | Customer sees driver photo, name, truck plate, rating, badges on the trip | Customer | Reads existing public trust summary and photos | none new | existing read rules | Photo missing: show initials |
| 4 | Wait-time charge (`waitCharges`) | After a free window at pickup or drop, a per-hour charge in paise is added with both sides seeing it | Customer, driver | Timer from arrival; capped; customer confirms | `bookings/{id}.waitPaise` | only driver adds, customer sees; cap in config | Disputes: show timestamps |
| 5 | Preferred routes (`preferredRoutes`) | Driver saves up to 3 routes or a home city; matching loads rank first | Driver | Profile list; sort in load feed | `users/{uid}/routes` | owner | Too narrow: always allow "show all" |
| 6 | Load match score (`matchScore`) | A 0-100 "fit" with the reasons (vehicle, route, weight, price) | Driver | Pure Dart function, shown as a chip with the reasons | none | none | Must be explainable, no hidden ranking |
| 7 | Freight rate range (`rateRange`) | "Usual price for this route and truck: low to high" before posting or bidding | Customer, driver | From pricing table + finished trips of the same route | `config/pricing` | read only | Thin data: show "not enough trips" |
| 8 | Document vault and expiry reminders (`docVault`) | One list of RC, insurance, permit, licence with expiry and local reminder 30/7/1 days | Driver, transporter | Existing papers + expiry date; local notifications | existing | owner | Reminder permission |
| 9 | Expense log and mileage (`expenseLog`) | Fuel, toll, repair per truck; km per litre; cost per trip | Transporter, driver | Simple form; uses `trip_cost` | `users/{uid}/expenses` | owner only | Wrong entries: edit within a day |
| 10 | Service reminders (`serviceReminders`) | Reminder by km or date (oil, tyres, permit) | Transporter, driver | Local schedule | `users/{uid}/service` | owner | Missed alarms on low-end phones |
| 11 | Party khata (`khata`) | Per party ledger: given, received, balance, share PDF | Transporter, customer business | Records only, not a payment | `users/{uid}/khata` | owner | Not legal accounts; note in app |
| 12 | Advance and balance split (`advanceSplit`) | Booking says "30% advance, rest on delivery"; both sides mark received | Customer, driver | Records on the booking; later pays through gateway | `bookings/{id}.advancePaise` | parties; integer paise | Cash disputes: both confirm |
| 13 | Payment protection (`payHold`) | Online payment is held until delivery proof, then released as a payout request | Customer, driver | Needs G9; ledger entries; manual maker-checker payout | ledger | server only | Needs Blaze and gateway |
| 14 | Shareable business card (`bizCard`) | A card (name, trucks, routes, badges) shared on WhatsApp as an image/link | Transporter | Renders widget to image; no phone number unless chosen | none | none | Contact leakage: opt-in only |
| 15 | Caller ID card (`callerCard`) | When a known user calls, show their name and verification in app | All | In-app only (no OS call hook) | none | existing | Skip OS-level; in-app call button only |
| 16 | Multi-stop (`multiStop`) | Up to 3 drop points with per-stop proof | Customer, driver | List on booking; each stop has a code | `bookings/{id}.stops` | parties | Pricing per stop; cap in config |
| 17 | Part load (`partLoad`) | Customer books a share of an empty truck | Customer, driver | Builds on empty trucks board; share in kg | `emptyTrucks` | existing | Matching complexity |
| 18 | Verified badge from KYC (`kycBadge`) | Show "ID checked" after KYC adapter result or admin review | All | Reads `kyc` status written by server/admin | `users/{uid}.kyc` | server/admin write | Needs partner for automatic |
| 19 | FASTag and fuel card (paid, `partnerOffers`) | Referral page only, no data sent | Transporter | Doc + link card after partner is chosen | none | none | Partner deal; later |
| 20 | Trip insurance quote (paid, `insuranceQuote`) | Ask for a quote from a partner on high value loads | Customer | Adapter skeleton | none | none | Partner and IRDAI rules; later |

Build order: 1, 3, 2, 4, 8, 5, 6, 7, 9, 10, 11, 12, 14, 16, 17, 18, 13 (needs G9), then 15, 19, 20 only as docs or skeletons.

Scope note: the plan allows G18 to G37 (20 slots). Features 15, 19 and 20 are documented skeletons because they depend on a partner or the OS.

## Audit before building (G18, 2026-10-17)

The plan above was written from the competitor matrix. Before building, each row was checked against the code. Most of it **already exists**; building it again would be a duplicate. Result:

| # | Feature | In the app today | Decision |
|---|---|---|---|
| 1 | Trusted contacts | Emergency contacts (3) + "Share trip with my contacts" (`ShareTripButton`, 24-hour link `tripShare`) | **Exists**, no new build |
| 2 | Safety check-in | Night prompt and rest prompt (`TripSafetyChecks`), halt detection (`trip_watcher`); **no** "Are you OK?" reply with an alert to support | **Build** (G22) |
| 3 | Driver trust card | `TrustBadgesCard` shows the driver their own numbers; the server writes `public_trust/{uid}` (F19) but **no screen shows it to customers** | **Build** (G19) |
| 4 | Wait-time charge | `DetentionCard` records waiting minutes and the charge it would cost; it is not added to the bill (needs the customer's consent and invoice rules) | **Exists as record**; adding to the bill deferred |
| 5 | Preferred routes | `FavouriteRoute` and `PlannedRoute` in the load ranker | **Exists** |
| 6 | Load match score | `LoadMatch.score` in `LoadRanker` | **Exists** |
| 7 | Freight rate range | `BidAssistant` suggests a range from the fare estimate; **nothing from real finished trips** | **Build** (G20) |
| 8 | Document vault | Vehicle papers with expiry + reminders (`DocExpiryService`, home banner, notification list) | **Exists** |
| 9 | Expense log, mileage | `VehicleExpensesScreen`, `ExpenseService`, mileage in `TripCost` | **Exists** |
| 10 | Service reminders | Service and tyre dates in the home banner and notification list | **Exists** |
| 11 | Party khata | Wallet ledger is the driver's earnings only; **no** per-party "who owes whom" | **Build** (G23) |
| 12 | Advance and balance split | PAY3: advance recorded and confirmed, balance shown | **Exists** |
| 13 | Payment hold until delivery | G9 credits the driver at payment time | **Build** (G21, server, flag `payHold`) |
| 14 | Shareable business card | none | **Build** (G24) |
| 15 | Caller ID card | none | **Skip** (needs OS call hook; in-app call screens already show names) |
| 16 | Multi-stop | `extraPickups`, `extraDrops`, `StopProgressCard` | **Exists** |
| 17 | Part load | Empty-trucks board only | **Later**: needs matching of weight shares; written in docs/PARTNER_OFFERS.md |
| 18 | KYC badge | `VerificationBadges`, admin chips (G13) | **Exists** |
| 19, 20 | FASTag / fuel card, trip insurance | none | **Doc only** (G25): partner deals |

So Phase 4 builds six features: G19 trip trust card, G20 route rate range, G21 payment hold, G22 safety check-in, G23 party khata, G24 business card, and G25 writes the partner offers note. Each has its flag (OFF), its rules test and an end-to-end test.

## Status after Phase 4 (2026-10-17)

| Task | Feature | Flag | Where | Tests |
|---|---|---|---|---|
| G19 | Driver trust card for customers | `tripTrustCard` | Customer offers and trip screen | `public_trust_card_test` |
| G20 | Usual price of a route | `rateRange` | Customer > Post a load > estimate | `route_rates_test`, emulator `rates` |
| G21 | Online payment held until delivery | `payHold` | Payment card (both sides) | emulator `razorpayHold`, `pay_hold_card_test` |
| G22 | Safety check-in on a long stop | `safetyCheckin` | Driver trip screen | `safety_checkin_test`, rules (SOS reason) |
| G23 | Party khata | `khata` | Profile > Party khata | `khata_test`, rules (private book) |
| G24 | Business card | `bizCard` | Driver and transporter Profile | `business_card_test` |
| G25 | Partner offers note (FASTag, insurance, caller ID, part load) | none | docs/PARTNER_OFFERS.md | doc only |

G26 to G37 were kept free in the plan for more features; the audit (G18) found nothing else worth building before the pilot shows real demand. They are not used.
