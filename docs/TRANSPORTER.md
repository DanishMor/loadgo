# Transporter (Task 67)

The old "Fleet owner" role is now **Transporter**. It is the same role (`users.role == 'fleet'`, the same
collections `fleet_invites` and `fleet_members`, the same `lib/fleet/` folder); only the name, the profile and
the company features are new. No new role was added, and the role lock is unchanged.

Free stack only: Flutter, Firebase Auth, Firestore, Hosting. Anything that needs a paid service is marked
`// LATER(paid)` in the code and listed at the end of this file.

## Switch

`config/features.flags.transporter` (Admin > Features > "Transporter accounts"). Default **ON**, also in pilot
mode, so it can be tested. When it is off the "Transporter" card disappears from the first screen. An account
that is already a transporter keeps working.

## 1. Profile

| Field | Where it is stored | Check |
|---|---|---|
| Company name | `users.companyName` | 2 to 100 characters |
| GST number (optional) | `users.business.gstin` | format and check character (`isValidGstin`) |
| PAN | `users.fleet.pan` | format; one PAN per account (identity index); locked after setup |
| Office city | `users.fleet.officeCity` | 2 to 60 characters |
| Operating routes | `users.fleet.routes` | up to 10, typed with commas |
| Vehicle types | `users.fleet.vehicleTypes` | up to 12 |
| Vehicle count | `users.fleet.vehicleCount` | whole number 0 to 100000 |

* Setup screen: `lib/auth/fleet_profile_setup_screen.dart`. Edit later: Home > "Company profile".
* Old accounts have no office city: the dashboard shows a "Finish your company profile" card.
* **Verified transporter** badge: shown when `users.verified == true`. Only an admin can set it (Admin >
  Driver verification lists transporters too, with the company, city and vehicle count). Nothing is checked
  against GST or PAN servers (`// LATER(paid)`: GST / PAN verification API).
* Rules: `validFleetProfile` limits the `fleet` map keys and sizes; `verified` and `verificationStatus` stay
  admin-only.

## 2. Vehicles

* **Own** vehicles: the normal vehicle form (Fleet tab > Vehicles).
* **Attached** vehicles: a driver first joins the fleet (phone invite, the driver accepts: that is the
  consent). In Driver Home > fleet card the driver switches "Attach to {company}" on a vehicle. The vehicle
  keeps its owner; `vehicles.attachedTo` names the transporter. The driver can detach at any time. If the
  driver leaves the fleet the attachment stops working (rules check `fleet_members.active`).
* The transporter may only flip an attached vehicle between available and on a trip; it cannot edit it.
* **Document reminders**: Home shows papers (insurance, PUC, fitness, permit) that are expired or end within
  30 days, for own and attached vehicles (`docReminders`). Day granularity: a paper that ends today still counts
  as valid today. No push message (`// LATER(paid)`: FCM sender), the reminder is in the app.

## 3. Loads, company bid, assign, reassign

1. **Loads tab**: open loads. "Bid for company" asks for a vehicle (own or attached, free, big enough) and
   a price. It is a normal offer (`offers/{loadId}_{transporterUid}`) with `fleetOwnerId` = the transporter and
   the company name as the name, so the customer sees "Transporter" on it. The same price limits apply.
2. The customer counters or selects as always. **Trips tab > My bids**: "Confirm job" on a selected bid creates the
   booking. The booking is **held by the company**: `driverId` = transporter, `fleetOwnerId` = transporter
   (`Booking.isCompanyBooking`).
3. **Assign**: Trips tab > "Assign vehicle and driver": pick an active fleet member and an own or attached
   vehicle. Written to the booking as `assignedDriverId`, `assignedDriverName`, `assignedVehicleId`,
   `assignedVehicleNumber`, `assignedAt`.
4. **Reassign**: the same button, until loading ends (`accepted`, `driver_arriving`, `loading`). The old vehicle
   becomes available again and the new one is marked on a trip. Every assignment and reassignment writes an
   `audit_events` line of type `assign` (who, which driver and vehicle, the previous ones).
5. The **assigned driver** sees the trip on Driver Home ("Trips from your transporter"), can read the
   booking, chat with the customer and move the trip through its steps (including the OTP steps) and share the
   position. They cannot change the assignment, the payment or cancel. Payments and the wallet stay with the
   booking holder (the transporter).
6. Refusals (`assignmentProblem`): `status`, `not_member`, `vehicle`, `busy`, `papers`, `capacity`, `same`; each
   has a message in 12 languages.

Rules summary: `validOfferCreate` (`fleetOwnerId` only for the transporter role, own or attached vehicle),
`bookingVehicleOk` (company booking), `transporterAssigns`, `transporterVehicle`, `attachOk`,
`transporterAvailability`.

## 4. Posting loads

The transporter can post a load with the normal Post Load screen (Loads tab > "Post a load"). The load gets
`postedByRole: 'fleet'` and every load card shows **Posted by transporter**. Rules: only a user with role
`fleet` may set that field. A transporter cannot bid on their own load.

## 5. Role lock and identity

Unchanged: `users.role` is set once and frozen, `selectedRole` must match, `role`, `riskTier`, `plan`, wallet
and `verified` cannot be changed by the owner. A transporter's PAN is in the identity index like every other
account. See `docs/SECURITY_REVIEW.md` and the rules tests "role lock" and "transporter (Task 67)".

## 6. Trips, status, delay alert, LR

Trips tab lists every booking with the transporter's vehicles (company bookings and trips run by member
drivers with fleet vehicles): status chip, assigned vehicle and driver, **LR / bilty** button (the same digital
LR the driver and customer have). **Late trips** card: a trip on the road past the estimated arrival plus one
hour of grace (`TripEta`, offline road distance at 40 km/h, not live traffic). `// LATER(paid)`: traffic API.

## 7. Books (record only)

Per company trip: what the party pays, what the driver is owed, other cost, what the party has paid.
`transporter_accounts/{bookingId}` (private to the transporter, not even admins read it, integer paise, each value
0 to ₹10 lakh). Shown: margin per trip, total margin, total owed to drivers, **party-wise balance** (largest due
first). Nothing is paid or collected by the app. `// TODO(functions)`: nothing needs a server for a private record,
but a real payout would.

## Not built (needs money or a server)

* GST and PAN verification (`// LATER(paid)`), vehicle RC verification.
* Push or SMS reminders for expiring papers and late trips (`// LATER(paid)`).
* Paying drivers through the app, collecting from parties (`// LATER(paid)` payment gateway).
* Live traffic ETA.

## Tests

`test/task67_test.dart` (logic, services, screens) and the rules suites "fleet owners" and "transporter (Task 67)"
in `firestore_rules_test/rules.test.mjs`.
