# Roadmap status

Source: the LoadGo Final Master Roadmap, worked through as 16 tasks. The roadmap PDF itself is not in the repository or the Codespace, so the rows below use the task and item numbers from the brief (T3.2 = Task 3, second item). If the PDF has its own codes, map them by title.

Legend: **Done** built and tested on the free stack. **Partial** works, with a stated gap. **Needs-paid** blocked on Blaze/Functions or a paid service. **Later** not started on purpose.

| Code | Item | Status | Notes |
|---|---|---|---|
| T1.1 | Resend OTP, 60 s timer | Done | `forceResendingToken` |
| T1.2 | Firebase error codes -> translated messages | Done | `auth_helpers.dart` |
| T1.3 | Language saved (device + users doc) | Done | `LanguageStore` |
| T1.4 | Masked phone, digits-only input | Done | |
| T2.1 | Vehicle types config with fallback list | Done | `config/vehicle_types`, 15 types, capacity ranges |
| T2.2 | Add vehicle, post load, filters use the config | Done | |
| T2.3 | Rules: signed-in read, admin write | Done | |
| T3.1 | Insurance/PUC/fitness/permit number + expiry, "Unverified" | Done | text only |
| T3.2 | Expiry within 30 days -> Home alert | Done | banner on Home; no push |
| T3.3 | Availability states, auto `on_trip` | Done | admin-only suspend |
| T3.4 | Duplicate vehicle number blocked across accounts | Done | `vehicle_numbers` |
| T3.5 | Next service date | Done | |
| T4.1 | `config/pricing` per vehicle type, fee/GST configurable | Done | |
| T4.2 | 60+ city table, haversine x road factor, manual km | Done | 64 cities |
| T4.3 | Pure `FareCalculator` + tests | Done | basis-point rounding |
| T4.4 | Fare estimate and breakdown on Post Load | Done | |
| T4.5 | Cancellation policy recorded and shown | Done | no money moves |
| T4.6 | Authoritative server-side fare | Needs-paid | Functions (`TODO(functions)`) |
| T5.1 | Multi-stop (3 pickups / 3 drops) | Done | |
| T5.2 | Saved places (home/office/warehouse/factory/port/CFS) | Done | |
| T5.3 | Prohibited cargo block (client + rules) | Done | |
| T5.4 | Pickup slot, Repost | Done | |
| T6.1 | Driver offers a price next to Accept | Done | |
| T6.2 | Customer selects, one counter, driver confirms | Done | double confirmation in the booking transaction |
| T7.1 | Extra statuses (arriving, loading, unloading) | Done | |
| T7.2 | Pickup/delivery OTP in `secrets`, rules compare | Done | |
| T7.3 | Cargo count/weight, seal, damage, receiver | Done | |
| T7.4 | POD packet screen | Partial | text and timeline; photos need Storage |
| T7.5 | Digital LR/bilty + e-way bill text field | Done | e-way bill not validated against the portal |
| T7.6 | OTP attempt rate limit | Needs-paid | Functions |
| T8.1 | Booking chat, unread badge | Done | |
| T8.2 | Report and block | Done | |
| T8.3 | Off-platform warning (phone / UPI / "pay outside") | Partial | client-side only |
| T8.4 | Length limit, rules + tests | Done | 500 chars |
| T9.1 | Tickets: category, priority, status, booking link, replies, escalation | Done | |
| T9.2 | Driver SOS with last location | Done | calls 112 / contacts by `tel:` |
| T9.3 | Emergency contacts (max 3) | Done | |
| T9.4 | Breakdown report -> replacement flag + customer notification | Done | |
| T9.5 | SMS to contacts, masked calling | Needs-paid | |
| T10.1 | Payment mode, payment status flow | Done | cash / UPI direct, records only |
| T10.2 | Append-only ledger with commission, wallet screen | Done | |
| T10.3 | Invoice with GST breakdown | Done | |
| T10.4 | Documents center | Done | |
| T10.5 | Payment gateway, escrow, payouts | Later | after a gateway is chosen |
| T11.1 | `riskTier` admin-only; restricted/suspended blocked in rules | Done | |
| T11.2 | `audit_events` append-only | Partial | client-written, can be skipped or forged for user events |
| T11.3 | `cancelCount`, user reports, flagged users list | Done | |
| T12.1 | `admins/{uid}` allowlist in rules | Done | claim no longer used |
| T12.2 | Users search, verification, vehicles, loads, bookings | Done | |
| T12.3 | Tickets, SOS, reports queue, risk edit | Done | |
| T12.4 | Pricing and vehicle types editors | Done | JSON editors |
| T12.5 | Analytics counters, manual driver reassign | Done | |
| T13.1 | Pure ranker (type, capacity, verified, papers, distance, return load) | Done | `LoadRanker` |
| T13.2 | Recommended for you, favourite routes, new-loads badge | Done | badge is device-local |
| T13.3 | Matching vehicle count on Post Load | Partial | cannot see owner verification (private) |
| T13.4 | Real road distance / live GPS for matching | Needs-paid | Maps |
| T14.1 | Customer and driver analytics | Done | |
| T14.2 | Notification preferences | Partial | filters the in-app list; push needs FCM |
| T14.3 | Consent center | Done | |
| T14.4 | Settings: language, logout, deletion request, terms/privacy, version | Partial | legal text is a placeholder; deletion is manual |
| T15.1 | Business profile, GSTIN format, "Not verified" | Done | |
| T15.2 | Branches (warehouse/factory/port/CFS) | Done | |
| T15.3 | Bulk post (max 10) | Done | |
| T15.4 | Route/branch summary report | Done | CSV copy |
| T15.5 | Container number, seal number, ports/ICD list | Done | ISO 6346 check digit |
| T15.6 | Two-leg shipment + timeline | Done | |
| T15.7 | GST/KYC verification | Needs-paid | |
| T16.1 | GitHub Actions: analyze, test, rules tests | Done | `.github/workflows/ci.yml` |
| T16.2 | Rules security review | Done | `docs/SECURITY_REVIEW.md` |
| T16.3 | README, ROADMAP_STATUS, MANUAL_TODO | Done | |
| P1 | Google Maps picker and tracking map | Needs-paid | key + billing |
| P2 | FCM push | Needs-paid | app side done, sender function needs Blaze |
| P3 | RC and vehicle photos | Needs-paid | Storage |
| P4 | Split into Customer and Driver apps | Later | `docs/SPLIT_PLAN.md` |
