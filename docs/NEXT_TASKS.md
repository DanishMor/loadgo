# Next tasks

Written 2026-10-04 after run 3, Task 9. The items still marked **Todo-free** in `docs/ROADMAP_STATUS.md`, with where they will be done. Queue: `docs/TASK_QUEUE.md` (Tasks 10 to 30); blocked items: `docs/BLOCKED.md`.

| Code | Item | Gap | Planned in |
|---|---|---|---|
| A2 | Google login Optional secondary auth; Firebase identity link | Google button only shows "coming soon" (customer_login_screen.dart); google_sign_in is fre | BLOCKED (Console SHA-1) |
| A4 | Business accounts Company owner, manager, dispatch, accounts | No manager/dispatch/accounts/viewer roles | Task 14 |
| K13 | Mismatch workflow Name/entity/vehicle relationship mismatch  | Admin approves manually; no mismatch workflow | later (see below) |
| R3 | SIM/mobile change Sensitive mobile change par stronger authe | No mobile-change flow or extra challenge | later (see below) |
| R7 | Document expiry trigger Expired/changed document ke baad ver | Expired papers only filter recommendations; no re-verify trigger | later (see below) |
| B14 | Fleet mode Multiple bikes/scooters under one fleet owner. | No fleet owner with multiple vehicles/drivers | Task 13 |
| V4 | Owner relationship Owner, authorised operator or fleet relat | Only ownerId on vehicle | Task 13 |
| V5 | Driver assignment Vehicle-to-driver mapping with active assi | Driver owns vehicle; no assignment | Task 13 |
| V6 | Fleet dashboard Vehicles, drivers, online/offline, active tr | No fleet dashboard | Task 13 |
| V10 | Fuel layer Fuel station map, expense tracking, future partne | Expense tracking buildable; fuel station map is paid | later (see below) |
| L13 | Load visibility controls Public marketplace, selected networ | Loads are public only | Task 15 |
| P3 | Recurring Repeat route/shipments. | No recurring shipments | Task 15 |
| SM9 | Fleet matching Fleet ke available vehicles se auto allocatio | No fleet auto allocation | Task 13 |
| SM10 | Scheduled matching Pickup slot ke according. | Slot is stored, not used in matching | Task 11 |
| SM11 | Multi-stop matching Compatible route and capacity. | No multi-stop matching | later (see below) |
| D11 | Nearby drivers Privacy-controlled network map/list. | No driver network | later (see below) |
| D12 | Connect Driver-to-driver connection request. | No driver connections | later (see below) |
| D13 | Groups Trip/route/convoy/fleet groups. | No groups | later (see below) |
| CH2 | Driver-driver chat 1-to-1 conversation. | Chat only per booking | later (see below) |
| CH3 | Group chat Trip/route/fleet group. | No group chat | later (see below) |
| CH7 | Load card share Chat mein load detail card. | Load card not sendable in chat | later (see below) |
| CH13 | Location privacy modes Nearby only / connections / trip memb | No privacy modes | later (see below) |
| CH14 | Location expiry Temporary share automatically expire. | No expiry on location share | later (see below) |
| PAY3 | Advance payment Booking time advance. | No advance payment record | later (see below) |
| IE10 | Handover Leg1 -> Leg2 controlled handover. | No controlled handover step | later (see below) |
| BIZ4 | Users Owner, admin, manager, dispatch, accounts, viewer. | No multi-user company | Task 14 |
| BIZ5 | Permissions Role-based access. | No business roles | Task 14 |
| BIZ6 | Approval workflow Large bookings ke liye manager approval. | No approval workflow | Task 14 |
| BIZ8 | Fleet management Company-owned/contracted vehicles. | No company fleet | Task 13 |
| BIZ9 | Driver pool Assigned/approved drivers. | No driver pool | Task 13 |
| BIZ10 | Expense dashboard Transport spend, fuel, toll etc. | No expense dashboard | Task 14 |
| BIZ12 | Transporter dashboard Multiple vehicles/drivers/customers. | No transporter dashboard | Task 13 |
| N2 | Driver arriving ETA alert. | No ETA alerts | Task 22 |
| N8 | Return load alert Driver route related opportunity. | No return load alert | Task 12 |
| N13 | Fleet analytics Utilisation, idle time, revenue, maintenance | No fleet analytics | Task 13 |
| BE5 | App Check Untrusted app requests ko reduce/deny karne ke liy | App Check not set up; free | BLOCKED (Play Integrity setup) |
| TEST3 | Integration tests Firebase/KYC/payment/map/provider flows. | No integration_test folder | Task 10 |

## Left for later (too big for one step, split)

- **K13** Mismatch workflow: compare driver name, RC owner name and vehicle relationship; needs a free-text review form for admins first, then an automatic "needs review" state.
- **R3** Extra confirmation when the phone number changes: needs a Firebase re-authentication flow (`updatePhoneNumber`) and a signal; build as: (1) re-auth screen, (2) `phone_change` risk signal, (3) admin review.
- **R7** Expired or changed document sends the account back to verification: do with Task 20 (document expiry auto-actions).
- **V10** Fuel and toll expense entries per vehicle with a monthly total (the station map is paid).
- **SM11** Multi-stop matching: rank a load by how many of its stops lie along the driver planned route.
- **D11** Driver network, in three steps: (1) nearby drivers list with a privacy mode, (2) connection requests, (3) groups.
- **D12** See D11 step 2.
- **D13** See D11 step 3.
- **CH2** Driver-to-driver chat: reuse the booking chat code with a `chats/{pairId}` collection; needs D12 first.
- **CH3** Group chat: after CH2.
- **CH7** Load card inside a chat message: after CH2 (message type `load_ref`).
- **CH13** Location privacy modes (nearby only / connections / trip members / hidden): after D11.
- **CH14** Automatic expiry of temporary location shares: after CH13 (expiry field + a check when reading).
- **PAY3** Advance payment record at booking: add `advancePaise` to the payment card and ledger; settle the balance on delivery (PAY4).
- **IE10** Controlled leg 1 to leg 2 handover step with both drivers confirming.

## Still needs a paid service or a server (not on this list)

See `docs/BLOCKED.md` and the Paid-or-Later rows in `docs/ROADMAP_STATUS.md`.
