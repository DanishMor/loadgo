# Roadmap status

Source: `roadmap.txt` (LoadGo Final Master Roadmap, 25 modules, Hinglish edition). Rebuilt on 2026-10-04 using the roadmap's own codes. Each status was set by reading the code, rules and tests (not guessed). The older 16-task brief numbering (T1.1 ...) is replaced by these codes.

Legend: **Done** built and tested on the free stack (Flutter + Auth + Firestore). **Partial** works with a stated gap. **Todo-free** not built, but possible on the free stack. **Paid-or-Later** needs Blaze/Functions/Storage, a paid or government provider, partner or Maps, or is a later phase by design. **Unsure** could not be confirmed from the code.

## Summary

| Module | Items | Done | Partial | Todo-free | Paid-or-Later | Unsure |
|---|---|---|---|---|---|---|
| P0 Principles | 6 | 3 | 3 | 0 | 0 | 0 |
| A Authentication | 10 | 7 | 0 | 2 | 1 | 0 |
| K Identity, KYC | 14 | 5 | 1 | 0 | 8 | 0 |
| R Re-KYC | 12 | 8 | 0 | 0 | 4 | 0 |
| C Customer app | 14 | 8 | 6 | 0 | 0 | 0 |
| B Bike | 14 | 11 | 2 | 0 | 1 | 0 |
| V Truck + fleet | 12 | 8 | 2 | 1 | 1 | 0 |
| L Load marketplace | 14 | 12 | 1 | 1 | 0 | 0 |
| P Booking + pricing | 14 | 10 | 2 | 1 | 1 | 0 |
| M Map | 16 | 2 | 5 | 0 | 9 | 0 |
| SM Smart matching | 14 | 11 | 1 | 2 | 0 | 0 |
| D Driver app | 16 | 11 | 2 | 3 | 0 | 0 |
| CH Chat | 14 | 4 | 1 | 5 | 4 | 0 |
| T Trip lifecycle | 14 | 9 | 4 | 0 | 1 | 0 |
| S Pickup, cargo, POD | 15 | 10 | 2 | 0 | 3 | 0 |
| PAY Payments | 14 | 5 | 3 | 1 | 5 | 0 |
| DOC Documents | 14 | 8 | 6 | 0 | 0 | 0 |
| IE Import/export | 14 | 12 | 1 | 1 | 0 | 0 |
| BIZ Business | 15 | 4 | 4 | 4 | 3 | 0 |
| F Anti-fraud | 18 | 4 | 9 | 0 | 5 | 0 |
| SAFE Safety | 12 | 9 | 1 | 0 | 2 | 0 |
| N Notifications | 15 | 10 | 1 | 2 | 2 | 0 |
| AI AI | 14 | 0 | 0 | 0 | 14 | 0 |
| BE Backend | 18 | 5 | 5 | 1 | 7 | 0 |
| TEST Testing | 14 | 4 | 3 | 0 | 7 | 0 |
| **Total** | **347** | **180** | **65** | **24** | **78** | **0** |

## P0 Principles

| Code | Item | Status | Where / why |
|---|---|---|---|
| P0-01 | Modular architecture Ek hi main.dart mein sab kuch bharne ke bajay auth, customer, driver, | Done | main.dart is only main()+LoadGoApp; lib/{core,auth,customer,driver,admin}; test/structure_test.dart enforces it |
| P0-02 | Verification-first Sensitive role ko verification ke bina high-trust actions nahi milne chahiye. | Done | Admin approves drivers; drivers cannot reach Home/Loads without licence, RC, Aadhaar last 4 and PAN (router guard); restricted, suspended and banned accounts blocked in rules; customers need no verification for their own loads |
| P0-03 | Server-authoritative Fare, booking status, payout, permissions aur risk decisions client app par | Partial | Rules check OTP, fields, state; fare is client-side (TODO(functions)) |
| P0-04 | Privacy by design Aadhaar/PAN/face/address/location ko minimum required scope mein | Done | Masked phone, consent center, OTPs in a customer-only secrets doc, Aadhaar stored as last 4 digits only (rules), identity index keeps hashes, account deletion (Task 28) |
| P0-05 | Auditability Critical changes ka event log - who, what, when, device/session context | Partial | audit_events append-only (rules) but client-written |
| P0-06 | Indian logistics first UPI, GST, e-way bill workflow, vehicle docs, Indian mobile numbers, | Partial | INR paise, GST, e-way text field, ports/ICD list, 12 languages; no real UPI/e-way integration |

## A Authentication

| Code | Item | Status | Where / why |
|---|---|---|---|
| A1 | Customer mobile OTP Indian mobile validation + Firebase OTP; register/login same account | Done | lib/auth/customer_login_screen.dart + otp_verification_screen.dart, Firebase phone OTP, digits-only |
| A2 | Google login Optional secondary auth; Firebase identity linking ke saath. | Todo-free | Google button only shows "coming soon" (customer_login_screen.dart); google_sign_in is free |
| A3 | Driver mobile OTP Driver signup/login with dedicated role. | Done | lib/auth/driver_login_screen.dart |
| A4 | Business accounts Company owner, manager, dispatch, accounts, viewer roles. | Todo-free | No manager/dispatch/accounts/viewer roles |
| A5 | Role-based access Customer, driver, transporter, fleet, shipper, importer, exporter, trader, | Done | Customer, driver and fleet roles are locked once set; users.businessType (shipper, importer, exporter, trader, transporter) in Edit profile, rules-validated; transporters also have the fleet role |
| A6 | New-device verification Naye device par extra verification / risk challenge. | Done | Device id kept per installation; a new device on an account with other devices raises a risk signal and shows as New in Settings > My devices |
| A7 | Session management Trusted devices, logout all, session revoke. | Done | My devices: trust, sign out a device, log out everywhere (checked when the app starts; token revoke is TODO(functions)) |
| A8 | Account recovery Secure recovery workflow; identity checks required for sensitive changes. | Paid-or-Later | No recovery flow; identity checks need KYC provider |
| A9 | Account linking Individual se business role / fleet / company profiles link karna. | Done | Settings > Linked accounts lists the own company profile, company teams (booker) and fleets the login belongs to |
| A10 | Consent center Privacy, location, document, face-verification aur communication | Done | Settings > consent center (users.consents), core/settings/settings_screen.dart |

## K Identity, KYC

| Code | Item | Status | Where / why |
|---|---|---|---|
| K1 | Aadhaar verification flow Authorised/approved Aadhaar authentication ecosystem ke through | Paid-or-Later | Aadhaar needs authorised provider |
| K2 | PAN verification Authorised PAN verification service/path; name/DOB/status checks | Paid-or-Later | PAN verification needs provider |
| K3 | Driving Licence DigiLocker/transport-authorised source se available document | Partial | Licence number + expiry are collected and format-checked in driver onboarding, never verified against a source (DigiLocker/Parivahan is the paid part) |
| K4 | RC verification Vehicle registration record/document verification through permitted | Paid-or-Later | RC number is text only (vehicle.rcNumber), no source check |
| K5 | DigiLocker consent User consent ke baad supported documents fetch/share/verify. | Paid-or-Later | DigiLocker needs registration |
| K6 | Current + permanent address User/business profile mein structured address records; sensitive display | Done | Edit profile keeps users.addresses {current, permanent} (rules: 200 chars each); admins see them masked |
| K7 | Face verification Identity match workflow; liveness/provider controls as appropriate. | Paid-or-Later | Needs face-match provider |
| K8 | Driver KYC pack Aadhaar, PAN, DL, address, photo, payout profile, vehicle relationship. | Paid-or-Later | Driver KYC pack has licence, RC, Aadhaar last 4, PAN, address and a payout UPI id record (Edit profile); the photo needs Storage (paid) |
| K9 | Business KYC GSTIN, PAN, business name, trade name, addresses, company | Paid-or-Later | GSTIN format and mod-36 check character are verified offline in all three forms; confirming that the number exists needs the GST portal / a KYC API (paid) |
| K10 | MCA / EntityLocker path Eligible company/entity documents ke authorised verification workflow ke | Paid-or-Later | MCA/EntityLocker integration |
| K11 | Verification badge Mobile/identity/PAN/DL/RC/GST/business/face status alag-alag visible. | Done | Per-document badges (OTP, provided/unverified, reviewed, missing) on the profile and in the admin queue; no source verification yet |
| K12 | Expiry tracking DL, RC, insurance, PUC, fitness, permits and other relevant document | Done | Vehicle papers, tyre/service and the driving licence expiry feed in-app reminders; push is the paid part |
| K13 | Mismatch workflow Name/entity/vehicle relationship mismatch -> pending/manual review, | Done | Admin > Users: Mark for review (name, RC owner, vehicle, document, other) with a note, audited; driver sees a banner on Home; clear when settled |
| K14 | Source + timestamp Har verification result ke saath source/type/status/timestamp/expiry | Done | Admin review writes verificationMeta {source: manual_review, by, status, at}; shown on the profile; external sources are LATER(paid) |

## R Re-KYC

| Code | Item | Status | Where / why |
|---|---|---|---|
| R1 | Scheduled re-KYC Configured policy interval par face/identity re-check. | Paid-or-Later | Needs face-KYC provider |
| R2 | New device trigger Naya phone/device detect ho to re-verification. | Done | New-device detection writes a `new_device` risk signal for admins (re-verification is manual) |
| R3 | SIM/mobile change Sensitive mobile change par stronger authentication. | Done | Settings > Change mobile number: SMS code to the new number (Firebase), profile phone updated, phone_change risk signal for admins |
| R4 | Payout/bank change Payout account change se pehle re-KYC/risk challenge. | Paid-or-Later | No payout/bank profile exists yet |
| R5 | High-value transaction High-value shipment/payout par additional verification. | Done | Loads of Rs 50,000 or more write a high_value risk signal for admins |
| R6 | Suspicious activity trigger Behavioural risk score high ho to re-KYC/manual review. | Done | RiskRules.score (cancels, reports, new devices, expired papers, tier) shown in the flagged list with a review suggestion |
| R7 | Document expiry trigger Expired/changed document ke baad verification refresh. | Done | Automatic check flags an expired licence and any KYC edit made after the last admin review; shown as chips in the verification queue and on the user screen; vehicle papers already move to doc_expired (Task 20) |
| R8 | Random verification Selected accounts par periodic random checks. | Done | Admin > Risk signals > Random check draws 5 approved drivers and can send them to re-verification |
| R9 | Trusted device list Device history + revoke access. | Done | Device list with revoke in Settings > My devices |
| R10 | Face-KYC freshness Current verification timestamp aur next verification due date track karna. | Paid-or-Later | Needs face-KYC |
| R11 | Recovery protection Passwordless ecosystem mein identity-sensitive recovery ko KYC se | Paid-or-Later | Needs KYC |
| R12 | Manual review Auto check fail hone par human verification queue. | Done | Verification queue and Admin > Users show the automatic check result (formats, expiry, edits after review, admin flag); admins decide |

## C Customer app

| Code | Item | Status | Where / why |
|---|---|---|---|
| C1 | Home dashboard Search, Book Bike, Book Truck, Post Load, Live Map, recent trips, alerts. | Partial | customer_home_screen.dart: Book Truck, recent; search box not wired, no Live Map |
| C2 | Book Bike Small parcel/local goods ke liye two-wheeler flow. | Partial | Bike/Scooter/EV 2W are vehicle types in post load; no dedicated bike flow |
| C3 | Book Truck Truck category + cargo + route + schedule. | Done | lib/customer/post_load_screen.dart |
| C4 | Post Load Customer budget ke saath marketplace par load publish kar sake. | Done | Post load with fare/budget, offers (load_offers_screen.dart) |
| C5 | Pickup/drop Single, multi-pickup, multi-drop location selection. | Done | Up to 3 pickups/3 drops (post_load_screen.dart) |
| C6 | Saved places Home, office, factory, warehouse, port, CFS, mandi etc. | Done | saved_place_picker.dart, users/{uid}/saved_places |
| C7 | Fare estimate Route, vehicle, weight and options ke basis par estimate. | Done | core/pricing/fare_calculator.dart, 64-city table (offline distance) |
| C8 | Available vehicles Nearby/verified vehicle options with ETA, vehicle info and verification | Partial | Matching vehicle count (matching_vehicles_line.dart); no ETA, no nearby vehicle list |
| C9 | Booking history Upcoming, active, completed, cancelled. | Done | customer_bookings_view.dart, my_loads_view.dart |
| C10 | Active trip Live vehicle map + ETA + status timeline. | Partial | booking_tracking_screen.dart: status timeline + last location as text; no map/ETA |
| C11 | Documents Invoice, LR/Bilty, e-way reference, POD, proofs. | Done | core/documents (invoice, LR, POD, documents center) |
| C12 | Payments UPI/card/other supported methods, receipts and refunds. | Partial | Cash/UPI-direct records only, receipts via invoice; no gateway, no refunds |
| C13 | Support Issue categories, ticket/chat/call. | Done | core/support/support_screens.dart tickets with category/priority |
| C14 | Profile/business Individual ya company account with KYC and saved settings. | Partial | Profile + business profile + settings; no KYC |

## B Bike

| Code | Item | Status | Where / why |
|---|---|---|---|
| B1 | Bike Local parcel and small goods transport. | Done | Vehicle type "Bike" (config/vehicle_types) |
| B2 | Scooter City delivery where suitable. | Done | Vehicle type "Scooter" |
| B3 | EV two-wheeler Eligible electric fleet category. | Done | Vehicle type "EV 2W" |
| B4 | Cycle Optional low-cost local delivery. | Done | Cycle is a vehicle type (two-wheeler category, 15 kg) |
| B5 | Goods auto 3-wheeler category. | Done | Vehicle type "3-Wheeler" |
| B6 | Mini truck Tata Ace / similar category. | Done | Vehicle type "Mini" |
| B7 | Instant local booking Pickup now -> nearby rider/vehicle -> ETA -> delivery. | Partial | Post load + driver accept; no nearby-rider ETA |
| B8 | Schedule local delivery Future date/time slot. | Done | Pickup date + time slot on loads |
| B9 | Package details Weight, size, quantity, fragile/high-value flag. | Done | Weight, packages, seal, damage plus fragile and high-value flags |
| B10 | Photo capture Pickup/delivery proof for parcel. | Paid-or-Later | Needs Storage (POD screen placeholder) |
| B11 | Bike route tracking Real-time rider location and ETA. | Partial | Driver position shared to booking as text; no map/ETA |
| B12 | Bike KYC Rider identity + DL + RC + insurance/PUC where applicable. | Done | Bike drivers pass the same driver KYC (licence, RC, Aadhaar last 4, PAN) and vehicle papers as truck drivers; PUC/insurance where applicable |
| B13 | Business delivery Shops/businesses ke repeated local orders. | Done | Bulk post (max 10), saved places, branches, load templates, Book again, favourite drivers (Task 15) |
| B14 | Fleet mode Multiple bikes/scooters under one fleet owner. | Done | Fleet owner role: several vehicles and invited drivers under one owner |

## V Truck + fleet

| Code | Item | Status | Where / why |
|---|---|---|---|
| V1 | Truck catalogue Open body, container, trailer, mini, 10-32 ft, multi-axle etc. | Done | config/vehicle_types, 15 types |
| V2 | Vehicle profile Number, class, capacity, dimensions, fuel, body type. | Done | Number, type, capacity, RC, optional cargo dimensions, fuel and body type (vehicle profile, rules validated) |
| V3 | Vehicle documents RC, insurance, PUC, fitness, permit and expiry. | Done | vehicle_documents_screen.dart insurance/PUC/fitness/permit + expiry |
| V4 | Owner relationship Owner, authorised operator or fleet relationship record. | Done | Vehicle ownerId plus assignedDriverId (owner and authorised driver relationship) |
| V5 | Driver assignment Vehicle-to-driver mapping with active assignment. | Done | Fleet owner assigns a vehicle to an active member (`assignedDriverId`); the driver sees and uses it |
| V6 | Fleet dashboard Vehicles, drivers, online/offline, active trips, idle vehicles. | Done | Fleet dashboard: vehicles, drivers, trips on the road, idle vehicles, earnings |
| V7 | Vehicle availability Available, busy, on-trip, maintenance, suspended. | Done | available/on_trip/maintenance/suspended, auto on_trip |
| V8 | Maintenance reminders Service, tyre, insurance, PUC, fitness, permit. | Done | Next service and next tyre-check dates + in-app reminders (Home banner and notification list); push is the paid part |
| V9 | FASTag layer Future partner/API integration for supported FASTag flows. | Paid-or-Later | FASTag partner API |
| V10 | Fuel layer Fuel station map, expense tracking, future partner integration. | Todo-free | Expense tracking buildable; fuel station map is paid |
| V11 | Replacement vehicle Breakdown/availability issue par replacement workflow. | Partial | Breakdown report sets replacement flag; no replacement vehicle assignment |
| V12 | Vehicle verification badge RC/transport-source verification + document freshness. | Partial | Doc freshness + "Unverified"; no transport-source verification |

## L Load marketplace

| Code | Item | Status | Where / why |
|---|---|---|---|
| L1 | Post Load Pickup, drop, cargo, weight, vehicle, date, budget, notes. | Done | post_load_screen.dart |
| L2 | Browse Loads Driver/transporter ko searchable marketplace. | Done | driver/available_loads_view.dart |
| L3 | Load filters Route, distance, vehicle, weight, freight, pickup time. | Done | core/models/load_filter.dart |
| L4 | Nearby loads Current location ke aas-paas. | Done | Driver position saved with a geohash; up to 9 live prefix range queries (own cell + neighbours) feed the Loads tab, sorted by distance with "X km away" (city-table distance, not road distance) |
| L5 | Route loads Driver ke planned route ke aas-paas. | Done | Driver sets a planned route (Loads tab); loads along it rank higher with an On your route chip |
| L6 | Return loads Destination par pahunchne ke baad reverse-direction opportunities. | Done | Return loads section on the trip screen (return runs first, nearest pickup next) and a reminder |
| L7 | Favourite routes Regular route alerts. | Done | favourite_routes_screen.dart |
| L8 | Load alerts Matching load par push notification. | Partial | In-app new-load badge (device-local); push needs Blaze |
| L9 | Load detail card Cargo, route, budget/fare, pickup time, verification requirements. | Done | core/widgets/load_card.dart |
| L10 | Offers Driver/transporter controlled quote/accept flow. | Done | make_offer.dart, offer_service.dart |
| L11 | Negotiation Optional controlled negotiation with platform rules. | Done | One counter by customer, driver confirms |
| L12 | Double confirmation Customer + driver confirmation ke baad booking lock. | Done | Booking transaction creates booking only after selected offer is confirmed |
| L13 | Load visibility controls Public marketplace, selected network, direct invite etc. | Todo-free | Loads are public only |
| L14 | Prohibited cargo rules Restricted goods ke liye policy and booking filters. | Done | core/constants/prohibited_cargo.dart + rules regex |

## P Booking + pricing

| Code | Item | Status | Where / why |
|---|---|---|---|
| P1 | Book Now Immediate vehicle search and booking. | Done | Post load + accept |
| P2 | Schedule Future pickup date/time. | Done | Exact pickup date and time, upcoming list, activation lead time and cancel window from config/pricing |
| P3 | Recurring Repeat route/shipments. | Todo-free | No recurring shipments |
| P4 | Multi-stop Multiple pickup/drop points. | Done | 3 pickups/3 drops with per-stop charge |
| P5 | Fare estimate Distance + vehicle + cargo + weight + demand factors. | Done | FareCalculator + estimate card |
| P6 | Fare breakdown Base, distance, toll, loading, unloading, waiting, platform fee, GST etc. | Done | fare_breakdown.dart: base, distance, loading, waiting, stops, fee, GST |
| P7 | Minimum fare Vehicle/category based minimum pricing. | Done | Minimum fare in config/pricing |
| P8 | Driver offer Marketplace quote option. | Done | Driver offers |
| P9 | Hybrid pricing System estimate + offers. | Done | Estimate + offers |
| P10 | Detention Loading/unloading waiting record and configured charge. | Done | Driver starts/stops a waiting clock at loading/unloading; minutes and the charge from config shown to both; record only |
| P11 | Cancellation policy Reason + charge/refund logic. | Partial | Config charge recorded on driver cancel; no refund moves |
| P12 | Booking state machine Created -> matched -> accepted -> confirmed -> active -> delivered -> | Partial | accepted..delivered (+cancelled); no created/matched/settled |
| P13 | Server-side pricing Client estimate is not authoritative; final quote from secure backend. | Paid-or-Later | TODO(functions); needs Blaze |
| P14 | Pricing admin Admin-configurable rates/rules with audit trail. | Done | Config edits write config_change audit events; Admin > Audit log lists them |

## M Map

| Code | Item | Status | Where / why |
|---|---|---|---|
| M1 | My location User current location with permission. | Partial | LocationService permission used for trip location sharing; not a user-facing "my location" |
| M2 | Pickup/drop Search, pin, geocoding and saved place. | Partial | City table + free-text addresses; no search/pin/geocoding |
| M3 | Vehicle markers Nearby trucks, bikes and active vehicles. | Paid-or-Later | Needs Maps |
| M4 | Load markers Available/public loads on map. | Paid-or-Later | Needs Maps |
| M5 | Driver network layer Eligible connected/nearby drivers based on privacy settings. | Paid-or-Later | Needs Maps |
| M6 | Active trip layer Running shipments and routes. | Paid-or-Later | Needs Maps |
| M7 | Warehouse/factory Business logistics POIs. | Partial | Branches list (warehouse/factory); no map layer |
| M8 | Ports/CFS Import/export logistics POIs. | Partial | core/constants/ports.dart picker; no map layer |
| M9 | Fuel/toll Relevant navigation overlays. | Paid-or-Later | Needs Maps |
| M10 | Routing Route calculation + ETA. | Partial | Offline haversine x 1.25 distance; no route/ETA |
| M11 | Navigation Turn-by-turn driver navigation. | Paid-or-Later | Needs Maps SDK |
| M12 | Rerouting Route change/off-route handling. | Paid-or-Later | Needs Maps |
| M13 | Traffic-aware ETA Where provider data and plan permit. | Paid-or-Later | Needs provider data |
| M14 | Geofencing Pickup/drop/warehouse/port boundaries. | Done | Geofence circles (pure logic) used for the drop; boundaries for warehouses and ports can reuse it |
| M15 | Route deviation Planned vs actual route comparison. | Paid-or-Later | Needs planned route from Maps |
| M16 | Offline/poor-network support Essential route/trip information cached where technically feasible. | Done | Firestore offline persistence (100 MB), connectivity banner, retry on failed actions, LiveStream/LiveDoc states (Task 27) |

## SM Smart matching

| Code | Item | Status | Where / why |
|---|---|---|---|
| SM1 | Nearest vehicle Pickup ke nearest eligible vehicle. | Done | Ranker measures from the driver's saved position when no trip is active; falls back to the last drop |
| SM2 | Correct capacity Weight/dimensions ke according capacity filter. | Done | LoadRanker capacity >= weight |
| SM3 | Correct vehicle type Bike/mini/container/trailer etc. | Done | LoadRanker vehicle type |
| SM4 | Availability Online + eligible + free vehicle. | Done | Active vehicle + available state |
| SM5 | Route match Driver route aur shipment route alignment. | Done | Planned route (users.plannedRoute) adds a ranker bonus and an On your route chip (load_ranker.dart); favourite routes too |
| SM6 | Return-load match Empty return reduce karne ke liye. | Done | Return-load bonus |
| SM7 | Verification filter Required KYC/document status valid. | Done | Verified driver + no expired papers |
| SM8 | Risk filter High-risk/suspended accounts exclude/hold. | Done | LoadRanker returns nothing for restricted or suspended drivers |
| SM9 | Fleet matching Fleet ke available vehicles se auto allocation. | Todo-free | No fleet auto allocation |
| SM10 | Scheduled matching Pickup slot ke according. | Done | A vehicle that is busy now can match a load scheduled more than 24 h ahead; advance bookings do not block the vehicle until started |
| SM11 | Multi-stop matching Compatible route and capacity. | Todo-free | No multi-stop matching |
| SM12 | Emergency replacement Breakdown/cancellation ke baad replacement. | Partial | Breakdown flag; manual replacement |
| SM13 | Load ranking Distance, ETA, route fit and operational factors. | Done | LoadRanker score + reason chips |
| SM14 | Human override Operations team exceptional cases manually reassign kar sake. | Done | Admin manual reassign by vehicle number (audited) |

## D Driver app

| Code | Item | Status | Where / why |
|---|---|---|---|
| D1 | Driver Home Online/offline, map, loads, trips, earnings. | Done | Driver Home: online switch saved on the profile and restored, loads, trips, earnings, reminders |
| D2 | Online/offline Availability control. | Done | Online switch saved on the profile (users.online) and restored on start |
| D3 | Nearby loads Location based marketplace. | Done | Loads tab merges geohash range queries with the newest page, sorted nearest first from users.lastLocation (consent-gated) |
| D4 | Route loads Planned route related opportunities. | Done | Planned route and favourite routes rank loads; On your route chip |
| D5 | Return loads Destination based reverse load suggestions. | Done | Recommended for you with return load reason |
| D6 | Trip dashboard Current assignment and steps. | Done | driver_trip_screen.dart |
| D7 | Earnings Day/week/month and trip level. | Done | earnings_view.dart + driver_analytics_screen.dart |
| D8 | Wallet Pending/available/payout records. | Done | Wallet shows pending, available and paid-out figures, payout requests and history (records only) |
| D9 | Documents KYC + vehicle docs + expiry. | Partial | Vehicle docs + expiry; driver licence, RC, Aadhaar last 4 and PAN at onboarding; no document photos |
| D10 | Driver profile Verified badges, vehicles, service info, languages. | Done | Profile shows verified badge, per-document badges, vehicle count, language and plan |
| D11 | Nearby drivers Privacy-controlled network map/list. | Todo-free | No driver network |
| D12 | Connect Driver-to-driver connection request. | Todo-free | No driver connections |
| D13 | Groups Trip/route/convoy/fleet groups. | Todo-free | No groups |
| D14 | Load share Load card share inside driver network. | Partial | Text share of load card (core/share_text.dart); not inside a network |
| D15 | Breakdown Emergency/replacement workflow. | Done | Breakdown report (trip_safety_card.dart) |
| D16 | SOS Safety escalation and trip-share flow. | Done | SOS with last location, calls 112 |

## CH Chat

| Code | Item | Status | Where / why |
|---|---|---|---|
| CH1 | Customer-driver chat Booking context attached chat. | Done | core/chat, bookings/{id}/messages |
| CH2 | Driver-driver chat 1-to-1 conversation. | Todo-free | Chat only per booking |
| CH3 | Group chat Trip/route/fleet group. | Todo-free | No group chat |
| CH4 | Voice message Short voice notes. | Paid-or-Later | Needs Storage |
| CH5 | Photo sharing Cargo/route/proof communication. | Paid-or-Later | Needs Storage |
| CH6 | Document sharing Load-related documents. | Paid-or-Later | Needs Storage |
| CH7 | Load card share Chat mein load detail card. | Todo-free | Load card not sendable in chat |
| CH8 | Location share Temporary/current location sharing. | Done | LocationSharingCard shares driver position to the booking during trip |
| CH9 | Masked call Possible where telephony provider supports it. | Paid-or-Later | Needs telephony provider |
| CH10 | Support chat Customer/driver -> LoadGo support. | Done | Support tickets with replies, categories, priority and escalation; SOS and call-support button |
| CH11 | Report/block Abuse/spam/scam reporting. | Done | reports + users/{uid}/blocked |
| CH12 | Off-platform warning Direct payment/contact risk warnings. | Partial | off_platform.dart client-side warning only |
| CH13 | Location privacy modes Nearby only / connections / trip members / hidden. | Todo-free | No privacy modes |
| CH14 | Location expiry Temporary share automatically expire. | Todo-free | No expiry on location share |

## T Trip lifecycle

| Code | Item | Status | Where / why |
|---|---|---|---|
| T1 | Driver assigned Customer gets driver + vehicle details. | Done | Booking has driver + vehicle, shown to customer |
| T2 | Driver arriving ETA and route. | Partial | driver_arriving status; no ETA/route |
| T3 | Pickup reached Geofence + optional OTP. | Partial | Pickup OTP; no geofence |
| T4 | Loading Loading state. | Done | loading status |
| T5 | Loading complete Cargo confirmation. | Done | Pickup proof (packages, weight, seal, damage) |
| T6 | Trip started Live location begins. | Done | picked_up / in_transit, location sharing starts |
| T7 | In transit Route, ETA, stops, alerts. | Partial | in_transit status; no route/ETA/stops alerts |
| T8 | Long halt Operational alert if configured. | Done | Long halt alert after 30 minutes without moving while in transit (in-app) |
| T9 | Route deviation Off-route alert. | Paid-or-Later | Needs planned route |
| T10 | Near destination Receiver preparation. | Done | Near-destination alert within 25 km of the drop city |
| T11 | Destination reached Drop geofence. | Done | Drop-reached alert within 5 km of the drop city; unloading stays manual |
| T12 | Unloading Unloading state. | Done | unloading status |
| T13 | Delivered POD requirements completed. | Done | Delivery OTP + proof + POD screen (photos missing) |
| T14 | Settlement Payment/payout workflow after conditions. | Partial | Payment record and ledger; no payout workflow |

## S Pickup, cargo, POD

| Code | Item | Status | Where / why |
|---|---|---|---|
| S1 | Pickup OTP Shipper + driver pickup confirmation. | Done | trip_otp_service.dart, secrets/otp compared in rules |
| S2 | Pickup GPS Location evidence. | Done | GPS saved with the pickup and delivery events (best effort, needs location permission) |
| S3 | Pickup timestamp Time evidence. | Done | Booking timeline timestamps |
| S4 | Cargo photos Condition and loading evidence. | Paid-or-Later | Needs Storage |
| S5 | Vehicle photo Vehicle-at-pickup evidence. | Paid-or-Later | Needs Storage |
| S6 | Odometer Optional trip start reading. | Done | Odometer start and end readings per trip with distance driven |
| S7 | Cargo count/weight Recorded shipment details. | Done | Packages/weight in pickup proof |
| S8 | Seal number Container/sealed cargo. | Done | Seal number (loads, bookings, LR) |
| S9 | Damage report Condition exception flow. | Done | Damage flag in pickup/delivery proof |
| S10 | Delivery OTP Receiver confirmation. | Done | Delivery OTP |
| S11 | Receiver details Name/contact where appropriate. | Done | Receiver name/phone |
| S12 | Delivery photo Delivered cargo evidence. | Paid-or-Later | Needs Storage |
| S13 | Signature Optional digital signature. | Done | Receiver signature captured as strokes and shown in the POD packet |
| S14 | POD Final proof-of-delivery packet. | Partial | pod_screen.dart text + timeline; no photos/signature |
| S15 | Evidence audit Who/when/where for evidence events. | Partial | audit_events for status changes; not every evidence event |

## PAY Payments

| Code | Item | Status | Where / why |
|---|---|---|---|
| PAY1 | UPI Primary Indian digital payment option where provider supports. | Partial | UPI direct payment mode as a record; no UPI intent/gateway |
| PAY2 | Cards/net banking Optional supported gateways. | Paid-or-Later | Gateway needed |
| PAY3 | Advance payment Booking time advance. | Todo-free | No advance payment record |
| PAY4 | Balance settlement Trip completion ke baad remaining amount. | Done | Payment record pending -> customer_marked_paid -> driver_confirmed, ledger line with commission, tips and advance fields follow in Task 37; money itself moves outside the app by design (gateway is paid, tracked in PAY rows) |
| PAY5 | Refund Cancellation/issue resolution. | Paid-or-Later | Refund needs gateway |
| PAY6 | Cancellation charges Rules-based calculation. | Partial | Charge computed and recorded; no money moves |
| PAY7 | Payment receipt Transaction proof. | Done | invoice_screen.dart + payment_card.dart |
| PAY8 | Driver payout Completed trip settlement. | Paid-or-Later | Payouts need provider |
| PAY9 | Wallet Pending/available balances. | Done | Driver wallet pending/available/paid-out with payout requests; customer credits ledger exists (offers) |
| PAY10 | Payout verification Bank/account ownership checks. | Paid-or-Later | Bank verification provider |
| PAY11 | Suspicious payout hold Risk high hone par temporary hold + review. | Paid-or-Later | No payouts to hold |
| PAY12 | Commission LoadGo platform fee with transparent record. | Done | Commission % in config/pricing, negative ledger line |
| PAY13 | GST/invoice Business transaction documentation. | Done | Invoice with CGST/SGST split |
| PAY14 | Settlement ledger Server-side financial ledger + audit. | Partial | Append-only ledger (rules) but client-written |

## DOC Documents

| Code | Item | Status | Where / why |
|---|---|---|---|
| DOC1 | Document center All shipment/vehicle/business documents. | Done | documents_center_screen.dart |
| DOC2 | LR/Bilty Digital transport document record. | Done | lr_screen.dart |
| DOC3 | Invoice Booking/business invoice. | Done | invoice_screen.dart |
| DOC4 | E-way bill reference Official workflow/reference integration where permitted. | Partial | 12-digit e-way bill text field; not validated against portal |
| DOC5 | Driver documents KYC docs and expiry. | Partial | Vehicle papers only; no driver KYC docs |
| DOC6 | Vehicle documents RC/insurance/PUC/fitness/permit. | Done | vehicle_documents_screen.dart |
| DOC7 | Cargo documents Shipment specific docs. | Done | Cargo document records per booking (type, number, note), either party can add |
| DOC8 | POD packet Delivery evidence bundle. | Partial | POD packet is text + timeline |
| DOC9 | Versioning Changed document history. | Done | Cargo documents are append-only: every change is a new version and the history stays |
| DOC10 | Access control Customer/driver/admin/enterprise role based. | Partial | Rules: owner/party/admin; no enterprise roles |
| DOC11 | Masking Sensitive identifiers partially masked on UI. | Done | Phone, PAN, licence, RC, GST masked on the profile; admins can reveal in the verification queue |
| DOC12 | Verification source Document source and verification status. | Partial | "Unverified" label only |
| DOC13 | Expiry reminders Upcoming expiry notifications. | Done | Expiry reminders for vehicle papers and the licence in-app (no push) |
| DOC14 | Audit Document upload/update/view verification logs where required. | Partial | Audit covers verification and status changes, not document views |

## IE Import/export

| Code | Item | Status | Where / why |
|---|---|---|---|
| IE1 | Domestic movement Factory/warehouse/shop -> destination. | Done | Normal load flow |
| IE2 | Import movement Port/CFS -> warehouse/factory. | Done | trade_details_section.dart import movement, ports picker |
| IE3 | Export movement Factory/warehouse -> CFS/port. | Done | trade_details_section.dart export movement |
| IE4 | Container booking Container vehicle category. | Done | Container vehicle type |
| IE5 | Container number Shipment linked container ID. | Done | Container number with ISO 6346 check digit |
| IE6 | Seal number Seal management. | Done | Seal number |
| IE7 | Port/CFS POIs Map and booking references. | Partial | ports.dart list in pickers; no map |
| IE8 | Multi-leg shipment Same shipment ke multiple transport legs. | Done | shipments/{id} two-leg shipment (shipments_screen.dart) |
| IE9 | Leg tracking Har leg ka driver/vehicle/status. | Done | Each leg is its own load/booking with status |
| IE10 | Handover Leg1 -> Leg2 controlled handover. | Todo-free | No controlled handover step |
| IE11 | Warehouse/factory stops Structured logistics locations. | Done | Branches (warehouse, factory, port, CFS) as structured stops; saved places; ports list |
| IE12 | Shipment timeline End-to-end milestone timeline. | Done | shipment_timeline.dart 8-step timeline |
| IE13 | Documents Relevant cargo/compliance docs per leg. | Done | Cargo document records can be tagged leg 1 or leg 2 |
| IE14 | Enterprise shipment view Business ko complete chain ka single view. | Done | shipments_screen.dart single view of both legs |

## BIZ Business

| Code | Item | Status | Where / why |
|---|---|---|---|
| BIZ1 | Business KYC GST/PAN/company/entity verification. | Paid-or-Later | GST/PAN/MCA verification needs API |
| BIZ2 | Company profile Legal + trade name, addresses, contacts. | Done | business_screen.dart |
| BIZ3 | Branches Multiple warehouses/factories/cities. | Done | users/{uid}/branches (max 20) |
| BIZ4 | Users Owner, admin, manager, dispatch, accounts, viewer. | Partial | Owner plus booker team members by phone invite; no manager/dispatch/accounts/viewer roles |
| BIZ5 | Permissions Role-based access. | Partial | Bookers can post for the company; owner reads the company bookings; no finer permissions |
| BIZ6 | Approval workflow Large bookings ke liye manager approval. | Todo-free | No approval workflow |
| BIZ7 | Bulk booking Multiple shipments ek saath. | Done | bulk_post_screen.dart (max 10) |
| BIZ8 | Fleet management Company-owned/contracted vehicles. | Partial | Fleet owners manage owned vehicles; no company contract-vehicle records |
| BIZ9 | Driver pool Assigned/approved drivers. | Todo-free | No driver pool |
| BIZ10 | Expense dashboard Transport spend, fuel, toll etc. | Todo-free | No expense dashboard |
| BIZ11 | Reports Routes, trips, payments, POD. | Done | route_report_screen.dart with CSV copy |
| BIZ12 | Transporter dashboard Multiple vehicles/drivers/customers. | Todo-free | No transporter dashboard |
| BIZ13 | API integration ERP/TMS/WMS integration layer. | Paid-or-Later | Needs server/Functions |
| BIZ14 | Webhooks Trip/status/POD events where integration supports. | Paid-or-Later | Needs Functions |
| BIZ15 | Business support Dedicated ticket/operations workflow. | Partial | Same tickets; no business queue |

## F Anti-fraud

| Code | Item | Status | Where / why |
|---|---|---|---|
| F1 | Duplicate identity patterns Same identity-related signals se duplicate accounts detect. | Partial | identity_index/{sha256(type+number)}: one licence, PAN, RC or GST per account, create-only rules, translated error; phone/name/device patterns not compared |
| F2 | Duplicate PAN patterns Authorised verification data ke basis par risk check. | Paid-or-Later | Needs PAN data |
| F3 | Duplicate DL/RC Vehicle/driver relationship anomalies. | Partial | Duplicate vehicle number blocked (vehicle_numbers) and duplicate DL/RC/PAN blocked at onboarding (identity_index); no DL/RC relationship anomaly checks |
| F4 | Same-device clusters Multiple suspicious accounts from same device. | Done | device_links groups accounts per device; admins see devices with 3+ accounts |
| F5 | Account takeover New device, SIM/mobile change, unusual login. | Partial | New-device signal only; SIM/mobile change and unusual-login timing are not detected |
| F6 | Payout risk Bank/payout changes + high-value activity. | Paid-or-Later | No payout yet |
| F7 | Behavioural risk Abnormal cancellations, bookings, profile changes. | Partial | cancelCount only |
| F8 | Impossible travel Location sequence inconsistency. | Paid-or-Later | Needs continuous GPS history |
| F9 | Fake GPS risk Mock-location/device/GPS consistency checks where feasible. | Paid-or-Later | Needs platform mock-location checks |
| F10 | Pickup fraud OTP + GPS + photo + timestamp. | Partial | OTP (+photos/GPS missing) |
| F11 | Delivery fraud OTP + receiver + POD + GPS. | Partial | OTP + receiver; no GPS/photo |
| F12 | Document tampering Uploaded docs suspicious -> verification queue. | Paid-or-Later | Needs uploads + analysis |
| F13 | Off-platform scam risk Chat/payment warnings + report flow. | Partial | Warning + report flow (chat) |
| F14 | Auto hold Risk condition par transaction/account hold. | Partial | Admin sets restricted/suspended; blocks in rules; not automatic |
| F15 | Human review High-risk cases manual operations queue. | Done | Admin flagged users + reports queue |
| F16 | Audit trail Critical events immutable-style logging architecture. | Partial | audit_events append-only but client-written |
| F17 | Risk tiers Normal / review / restricted / suspended states. | Done | riskTier normal/review/restricted/suspended |
| F18 | Fraud case management Alert -> evidence -> analyst action -> resolution. | Done | fraud_cases with notes, status, decision (risk tier) and audit; open from a report |

## SAFE Safety

| Code | Item | Status | Where / why |
|---|---|---|---|
| SAFE1 | SOS Driver safety escalation. | Done | sos_alerts + trip_safety_card.dart |
| SAFE2 | Emergency contacts Trip share and emergency contact flow. | Partial | Up to 3 emergency contacts; no trip share, SMS needs provider |
| SAFE3 | Breakdown Roadside/replacement process. | Done | Breakdown report |
| SAFE4 | Accident workflow Incident report + support escalation. | Done | Driver accident report opens an urgent safety ticket and notifies the customer |
| SAFE5 | Customer support Booking/payment/delivery issues. | Done | Tickets from bookings |
| SAFE6 | Driver support Load/payment/vehicle issues. | Done | Tickets for drivers |
| SAFE7 | Ticketing Case ID, priority, status. | Done | Case id, priority, status |
| SAFE8 | Call support Provider-based call option. | Done | config/support phone shows a Call support button on Help and support (provider-managed line is paid) |
| SAFE9 | Goods insurance Optional authorised partner integration. | Paid-or-Later | Insurance partner |
| SAFE10 | Driver accident cover Optional partner product. | Paid-or-Later | Insurance partner |
| SAFE11 | Dispute management Pickup/delivery/payment evidence based review. | Done | Claims/disputes on a booking with evidence text, timeline, admin resolution and status for both sides (Task 17) |
| SAFE12 | Escalation rules Customer -> support -> operations -> specialist. | Done | Escalation level 0-3 on tickets |

## N Notifications

| Code | Item | Status | Where / why |
|---|---|---|---|
| N1 | Booking notification Booking created/accepted/confirmed. | Done | In-app notifications |
| N2 | Driver arriving ETA alert. | Todo-free | No ETA alerts |
| N3 | Trip started Live trip started. | Done | status_changed notification |
| N4 | Route deviation Alert. | Paid-or-Later | Needs route deviation |
| N5 | Delivery complete POD/settlement notification. | Done | Delivered notification |
| N6 | KYC reminder Re-KYC due. | Paid-or-Later | Needs re-KYC |
| N7 | Document expiry DL/RC/insurance/etc. | Done | Vehicle paper, licence, service and tyre reminders in the Home banner and the notification list (no push) |
| N8 | Return load alert Driver route related opportunity. | Done | Driver reminder when open loads start near the drop city of a trip in transit or unloading |
| N9 | Payment notification Payment/payout/refund. | Done | In-app notifications when the customer marks payment and when the driver confirms it |
| N10 | Chat notification Message/group alerts. | Partial | Unread badge on Chat; no notification |
| N11 | Customer analytics Shipments, spend, routes, delivery success. | Done | customer_analytics_screen.dart |
| N12 | Driver analytics Trips, earnings, acceptance, empty km. | Done | driver_analytics_screen.dart (no empty km) |
| N13 | Fleet analytics Utilisation, idle time, revenue, maintenance. | Todo-free | No fleet analytics |
| N14 | Admin analytics Users, loads, bookings, GMV-like metrics, fraud alerts. | Done | admin dashboard counters (no fraud alert metric) |
| N15 | Enterprise reports Branch-wise, route-wise, driver-wise reports. | Done | Route, branch and driver-wise report with CSV |

## AI AI

| Code | Item | Status | Where / why |
|---|---|---|---|
| AI1 | AI fare assistant Route/cargo/vehicle based informational estimate. | Paid-or-Later | Later, after core is stable |
| AI2 | AI load recommendations Driver ke route/preferences par matching suggestions. | Paid-or-Later | Later |
| AI3 | AI route assistant Operational route suggestions. | Paid-or-Later | Later |
| AI4 | AI support First-level FAQ/support automation. | Paid-or-Later | Later |
| AI5 | AI document extraction Uploaded docs se fields identify karna. | Paid-or-Later | Later |
| AI6 | AI fraud signals Pattern detection; final decisions remain rule/human controlled. | Paid-or-Later | Later |
| AI7 | Demand prediction City/route demand forecasting. | Paid-or-Later | Later |
| AI8 | Supply prediction Driver/vehicle supply forecasting. | Paid-or-Later | Later |
| AI9 | Dynamic pricing intelligence Market signals + configured business rules. | Paid-or-Later | Later |
| AI10 | Fleet optimisation Vehicle allocation and utilisation suggestions. | Paid-or-Later | Later |
| AI11 | Empty-mile reduction Return-load optimisation. | Paid-or-Later | Later |
| AI12 | Route optimisation Multi-stop logistics planning. | Paid-or-Later | Later |
| AI13 | Conversation assistant Natural-language load creation/search. | Paid-or-Later | Later |
| AI14 | Enterprise assistant Business shipment queries and summaries. | Paid-or-Later | Later |

## BE Backend

| Code | Item | Status | Where / why |
|---|---|---|---|
| BE1 | Firebase Auth Phone OTP, identity/session management. | Done | Firebase Auth phone OTP |
| BE2 | Firestore Users, bookings, loads, vehicles, trips, chats, settings. | Done | Firestore collections |
| BE3 | Cloud Functions/server Fare, matching, booking state, notifications, risk actions, integrations. | Paid-or-Later | Needs Blaze (functions/index.js not deployed) |
| BE4 | Storage Documents, cargo photos, POD, profile/vehicle media with strict rules. | Paid-or-Later | storage.rules written, Storage not deployed (needs Blaze) |
| BE5 | App Check Untrusted app requests ko reduce/deny karne ke liye. | Todo-free | App Check not set up; free |
| BE6 | Security Rules Role and document-level access control. | Done | firestore.rules (951 lines) + 105 emulator tests |
| BE7 | Role model Customer/driver/business/admin/verification/support permissions. | Partial | Customer/driver/admin only |
| BE8 | Maps service layer Map/routing/geocoding provider wrapper so vendor change is easier. | Paid-or-Later | Needs Maps provider |
| BE9 | Payment service layer Gateway-agnostic interface for UPI/cards/refunds/payouts. | Paid-or-Later | Needs gateway |
| BE10 | KYC service layer Aadhaar/PAN/DigiLocker/GST/MCA/vehicle-source integrations via | Paid-or-Later | Needs KYC providers |
| BE11 | Notification service FCM/push + transactional message layer. | Partial | In-app + push_service.dart token; sender needs Blaze |
| BE12 | Audit event store Critical security/booking/payment/KYC events. | Partial | audit_events; client-written |
| BE13 | Risk engine Rules + signals + manual review queues. | Partial | riskTier + admin queue; no rules/signals engine |
| BE14 | Analytics pipeline Operational and business analytics. | Partial | Admin counters + stats classes; no pipeline |
| BE15 | Backup/recovery Firestore/storage backups, disaster recovery and operational restore plan. | Paid-or-Later | Backups need Blaze |
| BE16 | Secrets management API keys, service credentials and signing secrets not embedded in app. | Paid-or-Later | Needs Functions/secret manager |
| BE17 | Data retention Sensitive data ke liye explicit retention/deletion policy. | Done | docs/DATA_RETENTION.md (what is kept, how long, who removes it); in-app text comes with the legal screens |
| BE18 | Privacy controls Consent, purpose limitation, access minimisation, masking. | Done | Consent center, phone masking, account deletion (Task 28) and Settings > Download my data (JSON copy of own records) |

## TEST Testing

| Code | Item | Status | Where / why |
|---|---|---|---|
| TEST1 | Unit tests Fare, matching, booking state, permissions, validation. | Done | test/ 39 files: fare, matching, ranker, state, validators |
| TEST2 | Widget tests Login, booking, map, forms, chat, dashboards. | Done | widget tests for login, forms, chat, dashboards |
| TEST3 | Integration tests Firebase/KYC/payment/map/provider flows. | Done | test/e2e_flow_test.dart runs the whole customer to driver flow on fake Firestore + firebase_auth_mocks (rules are covered by firestore_rules_test); provider and map flows stay paid |
| TEST4 | Security tests Rules, role escalation, document access, auth takeover scenarios. | Done | firestore_rules_test (105 cases) |
| TEST5 | Location tests Background location, GPS loss, route deviation, low network. | Partial | live_location_test.dart; no background/GPS-loss tests |
| TEST6 | Payment tests Success/failure/refund/payout/duplicate transaction. | Partial | payments_test.dart for records; no gateway |
| TEST7 | Load tests Many drivers, loads, tracking events. | Paid-or-Later | Needs load tooling and environment |
| TEST8 | Device coverage Android ranges + different screen sizes. | Paid-or-Later | Manual device lab |
| TEST9 | Language QA All 12 languages across customer/driver flows. | Partial | translations_test.dart checks keys; no human QA |
| TEST10 | Pilot city 1-2 city controlled launch. | Paid-or-Later | Business pilot |
| TEST11 | Operational feedback Driver + shipper feedback, fraud cases, support patterns. | Paid-or-Later | After pilot |
| TEST12 | Scale-up More cities after operational readiness. | Paid-or-Later | After pilot |
| TEST13 | Pan-India National coverage with route/city expansion. | Paid-or-Later | After pilot |
| TEST14 | Import/export scale Ports/CFS/industrial clusters expansion. | Paid-or-Later | After pilot |


## Competitor feature audit (Porter, Uber, Rapido, Vahak, BlackBuck)

Written 2026-10-04. "Seen in" comes from general knowledge of how these apps are commonly described; it was not re-checked against the live apps, so treat it as a checklist to confirm, not as fact. "Roadmap" names the code in the 347 items above; **Not in roadmap** means no item covers it. Features that are not in the roadmap were added to `docs/NEXT_TASKS.md` (tasks 9 and 10).

| Feature | Commonly seen in | Roadmap | LoadGo today | Next |
|---|---|---|---|---|
| Return load / backhaul | Vahak, BlackBuck, Porter | L6, D5, SM6 (done), N8 (todo-free alert) | Return-load bonus in recommendations | N8 alert is in task 8 |
| Scheduled booking | Porter, Uber, Rapido | P2, B8, C3 | Pickup date + time slot on every load; no reminder before pickup | Reminder: task 9 |
| Recurring booking | Porter business, BlackBuck | P3 | None | Task 7 |
| Wallet (driver) | Porter, Rapido, BlackBuck | D8, PAY9 (partial) | Earnings/commission/net records | Pending/available/payout is in the partial row |
| Wallet / credits (customer) | Porter, Uber, Rapido | **Not in roadmap** (PAY9 reads as the driver side) | None | Task 9 (records only; top-up is paid) |
| Referral | Porter, Uber, Rapido, Vahak | **Not in roadmap** | None | Task 9 |
| Promo / coupon codes | Porter, Uber, Rapido | **Not in roadmap** (P14 pricing admin only) | None | Task 9 |
| Driver incentives (trip targets, streak, peak bonus) | Porter, Uber, Rapido | **Not in roadmap** | None | Task 9 |
| Helper / labour add-on | Porter | **Not in roadmap** (P6 has loading/unloading charge only) | Loading/unloading charge in fare, no helper count or driver acceptance | Task 9 |
| Tip to driver | Uber, Rapido | **Not in roadmap** | None | Task 9 |
| Fleet owner with several drivers | Porter, BlackBuck | V4, V5, V6, B14, BIZ8, BIZ12, SM9 (all todo-free) | Driver owns the vehicle; no assignment | Task 3 |
| Demand heat map / hot zones for drivers | Uber, Rapido, Porter | **Not in roadmap** (M-module has maps, no demand layer) | None | Task 10 (count of open loads per city; map is paid) |
| Driver subscription / membership plan | Vahak, BlackBuck, Rapido | **Not in roadmap** | None | Task 10 (plan record; payment is paid) |
| Hourly / rental packages | Uber, Porter | **Not in roadmap** | None | Task 10 |
| Packers and movers / house shifting | Porter | **Not in roadmap** | None | Task 10 (checklist form only) |
| Credit / pay-later for businesses | BlackBuck, Vahak | **Not in roadmap** (PAY14 is a ledger) | None | Left out on purpose: needs a lender (paid, regulated) |
| Live trip share link | Uber, Rapido, Porter | SAFE2, D16 (partial) | Emergency contacts + SOS call; no public tracking link | Link page needs hosting (paid/Functions): LATER(paid) |
| Masked calling | Uber, Rapido, Porter | SAFE8 (paid) | In-app chat only | LATER(paid) |
| FASTag / toll, fuel | BlackBuck | V9 (paid), V10 (expense part todo-free) | Toll is not in the fare | Task 3 |
| GPS vehicle tracking | BlackBuck, Porter | M-module, T-module | Phone GPS during trips (live_location) | Map is paid |
| Dynamic / surge pricing | Uber, Rapido, Porter | AI9, P5 (demand factors) | Config rate cards, no demand factor | AI9 is paid-or-later |
| Instant payout | BlackBuck, Rapido | PAY8 (paid) | Payment records only | LATER(paid) |
| Goods insurance | Porter, BlackBuck | SAFE9, SAFE10 (paid) | None | Partner needed |
| Ratings both ways | all | Trust profile (flow chart) | Done (rating_test) | none |
| Fare estimate before booking | all | C7, P5, P6 | Done (FareCalculator) | none |
| Pickup/delivery OTP | Porter, Rapido | S-module, F10, F11 | Done (trip OTPs) | none |
| Driver KYC and document expiry | all | K8, K12 | Onboarding gate + vehicle paper alerts | Licence expiry reminder: task 9 |
| Multilingual UI | Porter, Rapido, Vahak | P0-06 | 12 languages | none |
