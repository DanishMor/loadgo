# Next tasks (paid or manual only)

Rewritten 2026-10-06 after the Task 40 classification. Every free item is built: `docs/ROADMAP_STATUS.md` has no Partial or Todo-free row left. What remains needs a paid service, a provider, or a manual Console step. The free part of each row is already in the app; the row text in ROADMAP_STATUS says which.

| Code | Item | What is left | Cost / reason |
|---|---|---|---|
| P0-03 | Server-authoritative Fare, booking status, payout, permissions aur ris | Free part done: rules check state, OTP, fields; fare/commission are records. Server-side authority needs Cloud Functions (Blaze) | Cloud Functions / Blaze plan |
| P0-05 | Auditability Critical changes ka event log - who, what, when, device/s | Free part done: append-only audit_events for status, evidence, document views, admin actions. Tamper-proof logging needs Functions | Cloud Functions / Blaze plan |
| P0-06 | Indian logistics first UPI, GST, e-way bill workflow, vehicle docs, In | Free part done: UPI pay link, GST, e-way number + validity warning, ports list, 12 languages. Real e-way/GST portal check needs a provider | paid or government verification provider |
| A2 | Google login Optional secondary auth; Firebase identity linking ke saa | Needs the app SHA-1 in Firebase Console and google-services.json (manual, docs/MANUAL_SETUP.md) | manual Firebase Console setup (no cost) |
| A8 | Account recovery Secure recovery workflow; identity checks required fo | No recovery flow; identity checks need KYC provider | paid or government verification provider |
| K1 | Aadhaar verification flow Authorised/approved Aadhaar authentication e | Aadhaar needs authorised provider | paid or government verification provider |
| K2 | PAN verification Authorised PAN verification service/path; name/DOB/st | PAN verification needs provider | paid or government verification provider |
| K3 | Driving Licence DigiLocker/transport-authorised source se available do | Licence number + expiry collected and format-checked. Source verification (DigiLocker/Parivahan) is a paid or government provider | paid or government verification provider |
| K4 | RC verification Vehicle registration record/document verification thro | RC number is text only (vehicle.rcNumber), no source check | paid service or partner |
| K5 | DigiLocker consent User consent ke baad supported documents fetch/shar | DigiLocker needs registration | paid service or partner |
| K7 | Face verification Identity match workflow; liveness/provider controls  | Needs face-match provider | paid or government verification provider |
| K8 | Driver KYC pack Aadhaar, PAN, DL, address, photo, payout profile, vehi | Driver KYC pack has licence, RC, Aadhaar last 4, PAN, address and a payout UPI id record (Edit profile); the photo needs Storage (paid) | Firebase Storage (Blaze plan) |
| K9 | Business KYC GSTIN, PAN, business name, trade name, addresses, company | GSTIN format and mod-36 check character are verified offline in all three forms; confirming that the number exists needs the GST portal / a KYC API (p | GST/transport portal access (provider) |
| K10 | MCA / EntityLocker path Eligible company/entity documents ke authorise | MCA/EntityLocker integration | paid service or partner |
| R1 | Scheduled re-KYC Configured policy interval par face/identity re-check | Needs face-KYC provider | paid or government verification provider |
| R4 | Payout/bank change Payout account change se pehle re-KYC/risk challeng | No payout/bank profile exists yet | paid service or partner |
| R10 | Face-KYC freshness Current verification timestamp aur next verificatio | Needs face-KYC | paid service or partner |
| R11 | Recovery protection Passwordless ecosystem mein identity-sensitive rec | Needs KYC | paid service or partner |
| C8 | Available vehicles Nearby/verified vehicle options with ETA, vehicle i | Matching vehicle count is shown while posting; a nearby-vehicle list with ETA needs vehicle positions that customers may not read (privacy) or a Maps  | Maps API (billing account) |
| C10 | Active trip Live vehicle map + ETA + status timeline. | Status timeline, trip ETA and last location as text are done; the live vehicle map needs Maps | Maps API (billing account) |
| C12 | Payments UPI/card/other supported methods, receipts and refunds. | Free part done: cash/UPI-link records, invoices as receipts. Gateway, cards and refunds need a payment gateway | payment gateway (per-transaction fees) |
| C14 | Profile/business Individual ya company account with KYC and saved sett | Free part done: profile, business profile, GSTIN checksum, settings. KYC against GST/PAN sources is a paid provider | paid or government verification provider |
| B10 | Photo capture Pickup/delivery proof for parcel. | Needs Storage (POD screen placeholder) | Firebase Storage (Blaze plan) |
| B11 | Bike route tracking Real-time rider location and ETA. | Free part done: shared position, distance and arrival estimate. Map line and road ETA need a Maps API | Maps API (billing account) |
| V9 | FASTag layer Future partner/API integration for supported FASTag flows | FASTag partner API | partner contract |
| V12 | Vehicle verification badge RC/transport-source verification + document | Free part done (document freshness badge, Unverified). Transport-source/Vahan verification needs a paid provider | paid or government verification provider |
| L8 | Load alerts Matching load par push notification. | Free part done: in-app new-load badge and saved-search matches. Push needs FCM sender (Functions) | Cloud Functions / Blaze plan |
| P11 | Cancellation policy Reason + charge/refund logic. | Free part done: charge computed, shown before cancel and recorded. Refund moves need a gateway | payment gateway (per-transaction fees) |
| P13 | Server-side pricing Client estimate is not authoritative; final quote  | TODO(functions); needs Blaze | Cloud Functions / Blaze plan |
| M2 | Pickup/drop Search, pin, geocoding and saved place. | City typeahead over the offline table, saved places and free text are done; pin on a map and real geocoding need a Maps API | Maps API (billing account) |
| M3 | Vehicle markers Nearby trucks, bikes and active vehicles. | Needs Maps | Maps API (billing account) |
| M4 | Load markers Available/public loads on map. | Needs Maps | Maps API (billing account) |
| M5 | Driver network layer Eligible connected/nearby drivers based on privac | Needs Maps | Maps API (billing account) |
| M6 | Active trip layer Running shipments and routes. | Needs Maps | Maps API (billing account) |
| M7 | Warehouse/factory Business logistics POIs. | Free part done: branches list. Map layer needs a Maps API | Maps API (billing account) |
| M8 | Ports/CFS Import/export logistics POIs. | Free part done: ports/CFS picker. Map layer needs a Maps API | Maps API (billing account) |
| M9 | Fuel/toll Relevant navigation overlays. | Needs Maps | Maps API (billing account) |
| M10 | Routing Route calculation + ETA. | Free part done: offline distance estimate and ETA. Road routing and traffic need a Maps/Directions API | Maps API (billing account) |
| M11 | Navigation Turn-by-turn driver navigation. | Needs Maps SDK | Maps API (billing account) |
| M12 | Rerouting Route change/off-route handling. | Needs Maps | Maps API (billing account) |
| M13 | Traffic-aware ETA Where provider data and plan permit. | Needs provider data | paid or government verification provider |
| M15 | Route deviation Planned vs actual route comparison. | Needs planned route from Maps | Maps API (billing account) |
| D9 | Documents KYC + vehicle docs + expiry. | Free part done (expiry + freshness badge). Document photos need Storage (Blaze) | Firebase Blaze plan (Storage / Functions) |
| CH4 | Voice message Short voice notes. | Needs Storage | Firebase Storage (Blaze plan) |
| CH5 | Photo sharing Cargo/route/proof communication. | Needs Storage | Firebase Storage (Blaze plan) |
| CH6 | Document sharing Load-related documents. | Needs Storage | Firebase Storage (Blaze plan) |
| CH9 | Masked call Possible where telephony provider supports it. | Needs telephony provider | paid or government verification provider |
| T9 | Route deviation Off-route alert. | Needs planned route | paid service or partner |
| T14 | Settlement Payment/payout workflow after conditions. | Free part done: payment record, ledger, wallet, payout profile record. Real payouts need a gateway/bank partner | payment gateway (per-transaction fees) |
| S4 | Cargo photos Condition and loading evidence. | Needs Storage | Firebase Storage (Blaze plan) |
| S5 | Vehicle photo Vehicle-at-pickup evidence. | Needs Storage | Firebase Storage (Blaze plan) |
| S12 | Delivery photo Delivered cargo evidence. | Needs Storage | Firebase Storage (Blaze plan) |
| S14 | POD Final proof-of-delivery packet. | Free part done: POD text, timeline, receiver signature, OTP and GPS. Photos need Storage (Blaze) | Firebase Blaze plan (Storage / Functions) |
| PAY2 | Cards/net banking Optional supported gateways. | Gateway needed | payment gateway (per-transaction fees) |
| PAY5 | Refund Cancellation/issue resolution. | Refund needs gateway | payment gateway (per-transaction fees) |
| PAY8 | Driver payout Completed trip settlement. | Payouts need provider | paid or government verification provider |
| PAY10 | Payout verification Bank/account ownership checks. | Bank verification provider | paid or government verification provider |
| PAY11 | Suspicious payout hold Risk high hone par temporary hold + review. | No payouts to hold | paid service or partner |
| PAY14 | Settlement ledger Server-side financial ledger + audit. | Free part done: append-only ledger with rules checks. Server-side ledger needs Functions | Cloud Functions / Blaze plan |
| DOC4 | E-way bill reference Official workflow/reference integration where per | Free part done: validity date, expiring/expired warning on both trip screens. Checking the bill against the GST portal needs a provider | paid or government verification provider |
| DOC5 | Driver documents KYC docs and expiry. | Free part done: driver licence/RC/ID numbers with expiry and freshness. Document photos need Storage (Blaze) | Firebase Blaze plan (Storage / Functions) |
| DOC8 | POD packet Delivery evidence bundle. | Free part done: POD packet text, timeline, signature, GPS. Photos need Storage (Blaze) | Firebase Blaze plan (Storage / Functions) |
| DOC12 | Verification source Document source and verification status. | Free part done: Unverified label, verification status, admin review. Source verification is a paid provider | paid or government verification provider |
| IE7 | Port/CFS POIs Map and booking references. | Free part done: ports/CFS picker and booking references. Map layer needs a Maps API | Maps API (billing account) |
| BIZ1 | Business KYC GST/PAN/company/entity verification. | GST/PAN/MCA verification needs API | paid service or partner |
| BIZ13 | API integration ERP/TMS/WMS integration layer. | Needs server/Functions | Cloud Functions / Blaze plan |
| BIZ14 | Webhooks Trip/status/POD events where integration supports. | Needs Functions | Cloud Functions / Blaze plan |
| F2 | Duplicate PAN patterns Authorised verification data ke basis par risk  | Needs PAN data | paid service or partner |
| F6 | Payout risk Bank/payout changes + high-value activity. | No payout yet | paid service or partner |
| F8 | Impossible travel Location sequence inconsistency. | Needs continuous GPS history | paid service or partner |
| F9 | Fake GPS risk Mock-location/device/GPS consistency checks where feasib | Needs platform mock-location checks | paid service or partner |
| F12 | Document tampering Uploaded docs suspicious -> verification queue. | Needs uploads + analysis | paid service or partner |
| F14 | Auto hold Risk condition par transaction/account hold. | Free part done: admin bulk hold of high-score accounts with audit. Automatic hold needs Cloud Functions | Cloud Functions / Blaze plan |
| F16 | Audit trail Critical events immutable-style logging architecture. | Free part done: audit events for evidence, documents, admin actions. Immutable store needs Functions | Cloud Functions / Blaze plan |
| SAFE9 | Goods insurance Optional authorised partner integration. | Insurance partner | partner contract |
| SAFE10 | Driver accident cover Optional partner product. | Insurance partner | partner contract |
| N4 | Route deviation Alert. | Needs route deviation | paid service or partner |
| N6 | KYC reminder Re-KYC due. | Needs re-KYC | paid service or partner |
| AI1 | AI fare assistant Route/cargo/vehicle based informational estimate. | Later, after core is stable | paid service or partner |
| AI2 | AI load recommendations Driver ke route/preferences par matching sugge | Later | paid service or partner |
| AI3 | AI route assistant Operational route suggestions. | Later | paid service or partner |
| AI4 | AI support First-level FAQ/support automation. | Later | paid service or partner |
| AI5 | AI document extraction Uploaded docs se fields identify karna. | Later | paid service or partner |
| AI6 | AI fraud signals Pattern detection; final decisions remain rule/human  | Later | paid service or partner |
| AI7 | Demand prediction City/route demand forecasting. | Later | paid service or partner |
| AI8 | Supply prediction Driver/vehicle supply forecasting. | Later | paid service or partner |
| AI9 | Dynamic pricing intelligence Market signals + configured business rule | Later | paid service or partner |
| AI10 | Fleet optimisation Vehicle allocation and utilisation suggestions. | Later | paid service or partner |
| AI11 | Empty-mile reduction Return-load optimisation. | Later | paid service or partner |
| AI12 | Route optimisation Multi-stop logistics planning. | Later | paid service or partner |
| AI13 | Conversation assistant Natural-language load creation/search. | Later | paid service or partner |
| AI14 | Enterprise assistant Business shipment queries and summaries. | Later | paid service or partner |
| BE3 | Cloud Functions/server Fare, matching, booking state, notifications, r | Needs Blaze (functions/index.js not deployed) | Cloud Functions / Blaze plan |
| BE4 | Storage Documents, cargo photos, POD, profile/vehicle media with stric | storage.rules written, Storage not deployed (needs Blaze) | Firebase Blaze plan (Storage / Functions) |
| BE5 | App Check Untrusted app requests ko reduce/deny karne ke liye. | Needs Play Integrity registered in Console before enforcing App Check (manual, docs/MANUAL_SETUP.md) | manual Firebase Console setup (no cost) |
| BE8 | Maps service layer Map/routing/geocoding provider wrapper so vendor ch | Needs Maps provider | Maps API (billing account) |
| BE9 | Payment service layer Gateway-agnostic interface for UPI/cards/refunds | Needs gateway | payment gateway (per-transaction fees) |
| BE10 | KYC service layer Aadhaar/PAN/DigiLocker/GST/MCA/vehicle-source integr | Needs KYC providers | paid or government verification provider |
| BE11 | Notification service FCM/push + transactional message layer. | Free part done: in-app notifications and token record. FCM sending needs Functions (Blaze) | Cloud Functions / Blaze plan |
| BE12 | Audit event store Critical security/booking/payment/KYC events. | Free part done: audit_events for security, booking, payment and verification events. Server-written store needs Functions | Cloud Functions / Blaze plan |
| BE14 | Analytics pipeline Operational and business analytics. | Free part done: admin counters, trends, CSV. A pipeline (BigQuery) needs a paid cloud project | paid cloud project |
| BE15 | Backup/recovery Firestore/storage backups, disaster recovery and opera | Backups need Blaze | Firebase Blaze plan (Storage / Functions) |
| BE16 | Secrets management API keys, service credentials and signing secrets n | Needs Functions/secret manager | Cloud Functions / Blaze plan |
| TEST6 | Payment tests Success/failure/refund/payout/duplicate transaction. | Free part done: duplicate mark/confirm/advance/handover tests in app and rules. Gateway success/failure/refund/payout tests need a gateway | payment gateway (per-transaction fees) |
| TEST7 | Load tests Many drivers, loads, tracking events. | Needs load tooling and environment | paid service or partner |
| TEST8 | Device coverage Android ranges + different screen sizes. | Manual device lab | paid service or partner |
| TEST10 | Pilot city 1-2 city controlled launch. | Business pilot | paid service or partner |
| TEST11 | Operational feedback Driver + shipper feedback, fraud cases, support p | After pilot | paid service or partner |
| TEST12 | Scale-up More cities after operational readiness. | After pilot | paid service or partner |
| TEST13 | Pan-India National coverage with route/city expansion. | After pilot | paid service or partner |
| TEST14 | Import/export scale Ports/CFS/industrial clusters expansion. | After pilot | paid service or partner |
