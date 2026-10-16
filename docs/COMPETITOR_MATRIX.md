# Competitor matrix (G1)

Researched 2026-10-16 from public pages only (search results, official sites, app store listings). Nothing was read behind a login. Only the feature idea is taken; no text, design, logo or name is copied. Anything not confirmed on a public page is marked **UNVERIFIED**.

## Sources read

| App | Public source | What it confirmed |
|---|---|---|
| Porter | https://porter.in/android_app, https://apps.apple.com/us/app/-/id1109398410 (2026-10-16) | Intra-city trucks, tempos, bikes, packers and movers; booking, tracking, pay by cash, wallet credit or UPI wallet, coupons. Driver subscription or commission terms: not on these pages, **UNVERIFIED** |
| Vahak | https://www.vahak.in/why-choose-us, /full-truck-load, /part-load-booking, /grow-network (2026-10-16) | Free marketplace, "no commission or brokerage" claim, Aadhaar and GST verified users, full and part load, truck status tracking, business profile and shareable enquiry card |
| BlackBuck | https://blackbuck.com/company-products.html, https://apps.apple.com/in/app/blackbuck/id6499570896 (2026-10-16) | Load marketplace, caller ID with name, verification and rating, FASTag, fuel card with cashback, GPS tracker with drive reports and driver alerts, driver insurance and roadside help |
| WheelsEye | https://www.cbinsights.com/company/wheelseye-technology and a business-model article (2026-10-16) | Full truck load booking, GPS tracking, cost estimate, FASTag; third-party only, feature list **UNVERIFIED** |
| Uber | https://www.uber.com/en-FR/ride/safety and press coverage (2026-10-16) | Trusted contacts, share trip, start-ride PIN, RideCheck (long stop or crash check), driver photo and plate match |
| Rapido, Ola | search returned nothing (2026-10-16) | All claims **UNVERIFIED** |
| Two more (lorry booking and fleet apps, for example Trucksuvidha, Fleetx) | not opened this round | **UNVERIFIED**, listed by name only |

## Matrix

Score = how much it matters for India trucking (1 to 5). Ours: **Yes** (checked in code), **Part**, **No**. Decision: build, later, skip.

| # | Feature | Seen in (confirmed unless marked) | Ours | Score | Cost | Decision |
|---|---|---|---|---|---|---|
| 1 | Start-trip PIN / OTP verify | Uber (confirmed) | Yes (trip code, rules lock) | 5 | free | done |
| 2 | Trusted contacts + share trip | Uber (confirmed) | Part (`tripShare` link, no live position, no contacts list) | 5 | free | build: trusted contacts |
| 3 | Live GPS position of the truck | BlackBuck, WheelsEye (confirmed GPS) | No (G11) | 5 | free to cheap | build (G11) |
| 4 | Verified profiles (Aadhaar/GST) | Vahak, BlackBuck (confirmed) | Part (documents + admin review, KYC adapter G13) | 5 | paid partner later | build adapter, partner later |
| 5 | Caller ID with name, rating, verification | BlackBuck (confirmed) | No | 3 | free | later |
| 6 | Zero commission / no brokerage | Vahak (claim confirmed); Porter and Rapido driver subscription **UNVERIFIED** | Part (wallet, driver plans flag) | 5 | free | keep; commission-bypass guard stays |
| 7 | Upfront fixed price and bidding together | Porter fixed price **UNVERIFIED**; bidding ours | Yes (fare + offers) | 4 | free | done |
| 8 | Wait-time (detention) charges | **UNVERIFIED** (Porter, Uber wait fee) | No | 4 | free | build |
| 9 | Part load / shared truck | Vahak (confirmed) | Part (empty trucks board) | 3 | free | later |
| 10 | Truck availability board | Vahak (part-load spare space) | Yes (`emptyTrucks`) | 4 | free | done |
| 11 | Driver destination mode and preferred routes | **UNVERIFIED** (not found in any page) | No | 4 | free | build: preferred routes |
| 12 | Load match score | **UNVERIFIED** | No | 3 | free | build (simple, explainable) |
| 13 | Freight rate benchmark | WheelsEye cost estimate (third-party) | Part (pricing table) | 4 | free | build: show typical range |
| 14 | Document vault (RC, insurance, permit expiry) | **UNVERIFIED** | Part (papers + expiry suspend job) | 5 | free | build: expiry reminders |
| 15 | Fleet expense and mileage | BlackBuck drive reports; Fleetx **UNVERIFIED** | Part (`trip_cost`) | 4 | free | build: expense log |
| 16 | Service reminders | **UNVERIFIED** | No | 3 | free | build (local reminder) |
| 17 | Khata / party ledger | **UNVERIFIED** | No | 5 | free | build |
| 18 | Instant payment, advance and balance split | **UNVERIFIED** | Part (wallet records) | 5 | paid (gateway) | build: advance/balance record |
| 19 | FASTag and fuel card partner | BlackBuck (confirmed) | No | 3 | partner paid | later (partner deal) |
| 20 | Geofence alerts | BlackBuck driver alerts (confirmed); ours `trip_watcher` | Yes (basic) | 3 | free | done |
| 21 | Long-stop / off-route check (RideCheck idea) | Uber (confirmed) | Part (`trip_watcher`) | 4 | free | build: safety check-in |
| 22 | Trip insurance | BlackBuck driver insurance (confirmed) | Part (cargo insurance field) | 3 | partner paid | later |
| 23 | Lost item | Uber/Ola **UNVERIFIED** | No | 2 | free | skip (problem report covers) |
| 24 | Multi-stop | **UNVERIFIED** | No | 3 | free | later |
| 25 | Scheduled booking | Porter/Uber **UNVERIFIED** | Yes (`serverJobs`) | 4 | free | done |
| 26 | Corporate invoicing | **UNVERIFIED** | Yes (`businessTools`) | 3 | free | done |
| 27 | Referral | **UNVERIFIED** | Yes | 3 | free | done |
| 28 | Driver rewards | **UNVERIFIED** | Yes (`driverRewards`) | 3 | free | done |
| 29 | Driver loans | not researched | No | 1 | partner | skip (licence issue) |
| 30 | Shareable business card / enquiry card | Vahak (confirmed) | No | 3 | free | build: share profile card |
| 31 | Driver photo + plate match shown to customer | Uber (confirmed) | Part | 4 | free | build: trust card on trip |
| 32 | Payment protection (hold until delivery) | **UNVERIFIED** | Part (payments G9) | 4 | gateway | build with G9 |

Notes: "Yes/Part/No" came from file searches in `lib/` and `functions/` on 2026-10-16 (for example no code for `waitingCharge`, `fastag`, `khata`, `multiStop`; `trip_watcher.dart` and `emptyTrucks` exist).
