# Bilty (LR) - Task 70

A numbered lorry receipt that a **transporter** (on a booking where `fleetOwnerId` is them) or a **customer** (on their own booking) issues. A driver and an admin never issue one. Flag: `config/features.bilty` (ON by default for testing). The customer's one is labelled "Consignor LR / booking slip", the transporter's "LR".

The old LR screen (`lib/core/documents/lr_screen.dart`) stays as the read-only sheet made from the booking; the Bilty card sits at its top and holds everything below.

## Data

| Path | Holds | Who reads |
|---|---|---|
| `lrs/{issuer}_{year}_{seq}_v{n}` | LR no, date, route, goods, packages, weight, vehicle, driver name, party names, status, version, `complianceMode` (Task 71) | issuer, the customer, the transporter (`fleetOwnerId`), the booking's driver and assigned driver, admins |
| `lrs/{id}/private/details` | freight, advance, balance, margin, GST, phones (integer paise) | issuer, customer, transporter, admins. **Never the driver** |
| `lrs/{id}/private/compliance` | goods value, invoice no, party GSTIN, e-way bill no and validity | issuer, customer, transporter, admins; the driver only in mode `show` or with a valid grant (Inspection mode below) |
| `lr_series/{issuer}_{year}` | `next` counter, bumped in the same transaction as the LR | the issuer |
| `lr_shares/{token}` | snapshot of one copy type, expiry, revoked, views | `get` by token while live; list only for the owner's own |

One document per **version**. An edit writes `..._v2`, marks `..._v1` as `superseded` (view only) in the same batch; a cancel needs a reason (3 to 200 letters). Nothing else of an issued version ever changes. Number: prefix (`TR` transporter, `CS` customer) + calendar year + 6 digits: `TR-2026-000012`; unique per issuer because the counter and the LR commit together (the rules check `next == seq + 1`).

Audit (`audit_events`): `lr_issue`, `lr_version`, `lr_cancel`, `lr_share` (in-app, pdf, link), `lr_revoke`, `lr_mode`.

## Copy types (who sees what)

`lib/core/bilty/lr_visibility.dart` is the one place; the screen, the preview, the PDF and the share snapshot all use it.

| Field group | Full | Consignee | Driver |
|---|---|---|---|
| Public (LR no, date, route, goods, packages, weight, vehicle, driver name, party names, issuer, status, version) | yes | yes | yes |
| Rate (freight, advance, balance, GST) | yes | only if the owner switches "show the rate" on | **never** |
| Margin, phones | yes | never | never |
| Compliance (goods value, invoice no, GSTIN, e-way bill no) | yes | mode `show` | mode `show` or a valid inspection grant |

The send screen shows a **preview** of exactly the chosen copy before anything leaves the phone. The driver copy says "Rate hidden by owner" and points to chat and call in the app.

## Sending

1. **In app**: "Send to the driver" notifies the assigned driver (notice `lr_sent`); the trip screen then shows **LR (driver copy)**.
2. **PDF** (`pdf` + `share_plus`, WhatsApp): A4, heading, copy type, rows, signature line (issuer), delivery-proof line, **verify QR**.
3. **Link** `https://<host>/lr/<token>`: token is 128 random bits (32 hex letters). The document is a snapshot of that copy's fields; default end is delivery + 2 days (before delivery: pickup + 3 days + 2 days); the owner can revoke; each open adds 1 to `views`. Rules: create only by the issuer, `get` by token only (not expired, not revoked), no list for others, a driver copy cannot carry rate/margin/phone/compliance keys, a consignee copy cannot carry margin or phones.
4. **Verify QR** (on the PDF): a `verify` link showing only LR number, route, status, issuer. Its status follows new versions and cancels.

`hosting/lr.html` (from `tool/templates/hosting/lr.html`) reads `lr_shares/{token}` over REST and counts the view. `firebase.json` rewrites `/lr/**`.

## PDF fonts

`assets/fonts/` holds Noto Sans (Latin) and one Noto font each for Devanagari, Kannada, Tamil, Telugu, Gujarati, Bengali, Gurmukhi and Naskh Arabic (SIL OFL, `LICENSE.txt`). `LrFonts` loads them and uses them as fallbacks, so no letter turns into a box. Limit: the `pdf` package does not shape every joined form; check a Tamil or Urdu PDF by eye before the Play Store release.

## E-way bill

Only a record: number (12 digits), validity date and the vehicle. `// LATER(paid)`: generate it through a GSP API.

## Tests

`test/bilty_test.dart` (visibility matrix, numbering, versions, cancel, shares, PDF in 12 languages, screens), `test/e2e/bilty_e2e_test.dart` (transporter issues, the driver gets the driver copy, no rate), rules tests `bilty (Task 70)` in `firestore_rules_test/rules.test.mjs`.

# Inspection mode - Task 71 (RTO / GST checks)

Two groups, two rules:

* **Rate group** (freight, advance, balance, GST, margin, phones): always hidden from the driver. No toggle, no grant, no mode changes it. The rules deny the driver any read of `private/details`; `LrVisibility` never puts these keys into a driver copy.
* **Compliance group** (goods value, invoice no, party GSTIN, e-way bill no): the owner's per-LR mode `complianceMode` on the public document: `hide` (default) | `show` | `inspection_on_request`. Set when the LR is made and changeable later on the LR card; a change is one `lr_mode` line in `audit_events` and does **not** make a new version.

The driver reads `private/compliance` only when the mode is `show` or a valid `lrs/{id}/inspection_grants/{driverId}` exists (`expiresAt > request.time`). The rule stops honouring a grant at `expiresAt`, whatever the phone's clock says. Another driver's grant never works: the grant id is the reader's own uid.

## Flow

1. Driver trip screen > LR (driver copy): labels "Rate hidden by owner" and "Owner approval needed for inspection", button **Show inspection**.
2. `inspection_requests/{driverId}` (pending) + notice `inspection_request` to the owner (never muted) + audit `inspection_request`. The owner answers from the notification bell or from the LR card.
3. **Approve**: grant `kind: approved`, `expiresAt` = now + 2 hours (rules: at most 2 h), notice to the driver, audit `inspection_approve`. **Deny**: audit `inspection_deny`, notice; the driver may ask again.
4. **Pre-approve** (owner, before the trip): "Show for this trip" sets mode `show`; "Allow inspection for the next N hours" (2, 6, 12, 24, 48 or 72) writes a `preapproved` grant (rules: at most 72 h). Audit `inspection_approve` with `advance: true`. The owner can also end a grant early.
5. **Expiry**: the driver's screen looks every 15 seconds; when the grant has run out it deletes the saved copy, marks the request `expired` and writes **one** `inspection_expire` event (a local flag stops repeats).

## Offline "Inspection copy"

When a grant is valid (or the mode is `show`) the driver can **Save inspection copy for offline**: a PDF with the compliance fields, no rate, the watermark "Inspection copy", LR no, the verify QR (the owner puts the verify token into the grant), date and time and the driver's name. It is kept in `shared_preferences` (`inspection_cache_<lrId>`) with its end time: the grant's `expiresAt`, or 12 hours in mode `show`. Reading it after that time deletes it; the app and the trip screen also purge expired copies. "Show saved inspection copy" opens it without a network.

## Tests

`test/inspection_test.dart` (mode x copy matrix, request / approve / deny / pre-approve / revoke, cache and expiry, screens), `test/e2e/inspection_e2e_test.dart` (request, approve, offline copy, expiry), rules tests `bilty inspection mode (Task 71)` (14: the driver never reads `details`; compliance only in `show` or on a valid grant; expired grant refused; another driver's grant refused; who creates grants and requests; audit and notices).
