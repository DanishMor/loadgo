MASTER-4. Task 69 (admin panel visibility lock), Task 70 (Bilty / LR upgrade), Task 71 (Bilty inspection mode). Saved as given.

RULES: free stack only. After each task: flutter analyze 0 issues, new tests, flutter test pass, rules tests pass, commit, push. New text in 12 languages. Money is integer paise. Update PROGRESS.md. customer/, driver/, fleet/, admin/ must not import each other. Do not deploy rules/indexes/hosting. If blocked, write docs/BLOCKED.md.

TASK 69 - ADMIN PANEL VISIBILITY LOCK:
1. No admin tile, button, menu, route or text is visible to customer, driver, transporter anywhere (role screen, login, Settings, Help, Sahayak, search, deep links). The admin entry shows only when an admins/{uid} document exists (live check).
2. Route guard on admin screens: a non-admin arriving by direct route, saved state or deep link is sent out at once, no data loaded.
3. Rules: non-admin cannot read or write the admins collection. Every admin-only collection (violations, audit_events, config writes, riskTier, fraud_cases, error logs, features) gets rules tests: customer, driver, transporter all denied.
4. Admin session shows a differently coloured "Admin mode" banner. Tests that a non-admin sees no admin entry in the UI.

TASK 70 - BILTY (LR) UPGRADE (upgrade digital LR Task 7 and transporter LR Task 67):
1. Who can create: only transporter and customer (on own booking). Not driver, not admin. Flag config/features.bilty. Customer one is labelled "Consignor LR / booking slip", transporter one "LR".
2. Data split: lrs/{lrId} (LR no, date, route, goods, packages, weight, vehicle, driver name, party names, status, version) and lrs/{lrId}/private/details (freight, advance, balance, margin, GST, invoice value, phones). Private readable only by creator, both parties of the booking, and admin; not driver. Driver sees only the public part and only for own assigned booking.
3. 3 copy types: Full, Driver, Consignee. Driver copy never has rate, margin or phone (in-app chat/call). Consignee copy shows rate by owner toggle. Preview of what the receiver will see before sending.
4. Lock after issue: edit = new version (old view-only), cancel = with reason, everything in audit_events. LR number series unique per issuer (transaction counter), prefix+year+number.
5. Sending: (a) assigned driver in-app, trip screen "LR (driver copy)", (b) PDF via share_plus (WhatsApp), (c) lr_shares/{randomToken} (128-bit) link: snapshot of that copy type's fields, expiry (default delivery+2 days), revoke, view count, create-only, get-by-token only, list closed. hosting/lr.html and PDF carry a verify QR (only LR no, route, status, issuer, no rate or value).
6. PDF: pdf package, Noto fonts for Devanagari and the 12 languages bundled in assets so Hindi has no boxes. Add signature and POD link.
7. E-way bill is only a record of number/validity/vehicle. // LATER(paid): generate via GSP API.
8. Rules tests: driver cannot read private, other's LR hidden, customer cannot create on other's booking, expired/revoked token fails. Unit tests of the visibility matrix. e2e: transporter creates LR, driver gets driver copy, rate not visible. Update docs/BILTY.md, WHERE_IS_WHAT.md, TEST_PLAN.md. One line in Privacy/Terms about bilty and share link.

TASK 71 - BILTY INSPECTION MODE (for RTO/GST checking):
1. Visibility in 2 groups: (a) Rate group (freight, advance, balance, margin): always hidden from driver, no toggle. (b) Compliance group (goods value, invoice no, party GSTIN, e-way bill no): per-LR owner mode hide | show | inspection_on_request. Default hide. Mode settable at LR create and later (change goes to audit log, no new version).
2. Inspection on request: driver trip screen button "Show inspection". Owner gets in-app request (notification list). If owner approves, lrs/{id}/inspection_grants/{driverId} is created (expiresAt = 2 hours, owner-only create, driver read). Rules refuse compliance read after expiry. Every request, approve, deny, expiry in audit_events.
3. Pre-approve: owner can set "Show for this trip" or "Allow inspection for next N hours" before the trip so it works without network.
4. Offline: "Inspection copy" PDF (compliance fields, no rate, watermark "Inspection copy", LR no, verify QR, date/time, driver name) can be downloaded/cached on driver phone in advance when owner allowed. Cache auto-deletes on grant expiry.
5. Clear driver labels: "Rate hidden by owner" and "Owner approval needed for inspection".
6. Rules tests: driver never reads rate, compliance only in show mode or valid grant, expired grant refused, another driver's grant does not work. Unit tests mode x copy type matrix. e2e: request, approve, expiry. Update docs/BILTY.md, TEST_PLAN.md. One line in Privacy/Terms that inspection access is recorded.

END: summary, and say whether rules and hosting deploy is needed.
