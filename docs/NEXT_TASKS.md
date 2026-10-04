# Next tasks (Todo-free items)

The 62 items marked **Todo-free** in `docs/ROADMAP_STATUS.md`, grouped into 8 tasks. All of them fit the free stack (Flutter + Auth + Firestore, no Blaze, no paid API). Not started. Same rules as before: `flutter analyze` 0 issues, `flutter test`, rules tests when rules change, 12-language strings, money in paise, `// TODO(functions)` / `// LATER(paid)` for server or paid parts.

| # | Task | Items |
|---|---|---|
| 1 | Sign-in methods and device security | A2, A6, A7, R2, R3, R9, F4, F5 |
| 2 | Business roles and approvals | A4, BIZ4, BIZ5, BIZ6, BIZ9, BIZ12 |
| 3 | Fleet and vehicle management | B14, V4, V5, V6, V10, BIZ8, BIZ10, SM9 |
| 4 | Risk rules and manual review | K13, R5, R6, R7, R8, F1, BE5, BE17 |
| 5 | Driver network and chat | D11, D12, D13, CH2, CH3, CH7, CH13, CH14 |
| 6 | Trip events and evidence | T8, T10, T11, M14, S2, S6, S13, SAFE4, IE10 |
| 7 | Marketplace, recurring and scheduled matching | B4, L5, L13, P3, SM10, SM11, PAY3 |
| 8 | Documents, notifications, fleet analytics, integration tests | DOC7, DOC9, IE13, N2, N8, N9, N13, TEST3 |

## 1. Sign-in methods and device security
- A2 Google login with `google_sign_in` and account linking (needs the SHA-1 added in the Firebase Console).
- A6, R2, F4 Device id stored per user (`users/{uid}/devices`), new-device challenge, same-device cluster flag for admins.
- A7, R9 Trusted device list, revoke a device, "log out everywhere" (marks devices revoked; the app checks on start).
- R3 Extra confirmation when the phone number or sensitive profile fields change.
- F5 Unusual login signal (new device + recent change) written to the risk queue.

## 2. Business roles and approvals
- A4, BIZ4, BIZ5 Company users (owner, manager, dispatch, accounts, viewer) under one business, with a permission map used by screens and rules.
- BIZ6 Approval workflow: bookings or bulk posts above a configured amount wait for a manager.
- BIZ9 Approved driver pool for a business.
- BIZ12 Transporter dashboard: many vehicles, drivers and customers in one view.

## 3. Fleet and vehicle management
- B14, V4, V5 Fleet owner with several vehicles, owner/operator relationship and vehicle-to-driver assignment.
- V6 Fleet dashboard: vehicles, drivers, online/offline, active trips, idle vehicles.
- V10, BIZ10 Fuel and toll expense entries and an expense dashboard (station map stays paid).
- BIZ8 Company-owned and contracted vehicles.
- SM9 Auto-allocate a load to an available fleet vehicle.

## 4. Risk rules and manual review
- K13 Name/vehicle mismatch sends the driver to a manual review state instead of approval.
- R5, R6, R7, R8 Rule-based triggers: high-value booking, behavioural score from cancellations and changes, expired papers, random selection; each creates a review item.
- F1 Duplicate identity patterns on phone, name and vehicle number.
- BE5 App Check with Play Integrity (free).
- BE17 Written data retention policy plus an in-app note and admin checklist.

## 5. Driver network and chat
- D11, D12, D13 Nearby/connected drivers list with privacy setting, connection requests, groups.
- CH2, CH3 Driver-to-driver and group chat.
- CH7 Share a load card inside a chat.
- CH13, CH14 Location privacy modes and automatic expiry of temporary location shares.

## 6. Trip events and evidence
- T8, T10, T11, M14 Geofence logic with Geolocator: near destination, drop reached, long halt alert.
- S2 Save GPS with the pickup and delivery events.
- S6 Optional odometer at trip start.
- S13 Signature capture stored as strokes in Firestore (image upload stays Storage/paid).
- SAFE4 Accident report and escalation to support.
- IE10 Controlled leg 1 to leg 2 handover step.

## 7. Marketplace, recurring and scheduled matching
- B4 Add Cycle to vehicle types.
- L5 Driver enters a planned route; loads along it are ranked.
- L13 Load visibility: public, selected network, direct invite.
- P3 Recurring shipments (repeat a route on a schedule, creating loads in the app).
- SM10, SM11 Matching by pickup slot and compatible multi-stop capacity.
- PAY3 Advance payment record at booking.

## 8. Documents, notifications, fleet analytics, integration tests
- DOC7, IE13 Cargo documents per shipment and per leg (text and reference records).
- DOC9 Version history for changed documents.
- N2, N8, N9 In-app ETA, return-load and payment notifications (push still needs Blaze).
- N13 Fleet analytics: utilisation, idle time, revenue, maintenance.
- TEST3 `integration_test/` flows with the Firebase emulator.
