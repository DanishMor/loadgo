# Where is what

Every feature, for every role: which screen, which menu. Flags are the switches in **Admin > Features and pilot
mode** (`config/features`). In pilot mode (the default for a new project) only the core freight flow, support and safety
are on; **Pilot** and **Normal** below are the defaults of each flag in pilot mode and with pilot mode off. An admin can
force any flag On or Off; a forced value always wins. A flag that is OFF hides its entry everywhere.

## Feature flags

| Flag | What it means | Pilot | Normal | Where it shows |
|---|---|---|---|---|
| `driverNetwork` | Drivers connect with each other, share location with trusted drivers, make groups | OFF | ON | Driver Home > Driver network tile; Profile > Driver network |
| `emptyTrucks` | Board of empty trucks (customers find, drivers post) | OFF | ON | Customer Home > Empty trucks card; Driver Home > Empty trucks tile |
| `businessTools` | Company tools: team, approvals, cost centres, monthly statement | OFF | ON | Customer Home > More for you > Business tools; Profile > Business tools |
| `rentalMovers` | Hourly rental and packers and movers on the Post Load screen | OFF | ON | Customer > Post Load > booking type |
| `driverRewards` | Tips, bonuses and paid plans for drivers | OFF | ON | Driver > Earnings tab > Rewards |
| `tripShare` | 24-hour trip link for family (no phone number, no live position) | ON | ON | Trip screens > Share trip |
| `problemReport` | Two-tap "Report a problem" on trip screens and in Help | ON | ON | Trip screens, Help |
| `transporter` | The Transporter role (company profile, bids, assigning, books) | ON | ON | First screen > Transporter card; Transporter app |
| `bilty` | Numbered LR (bilty) with driver, consignee and full copies, PDF and share link | ON | ON | Trip screen > LR; Transporter > Trips > LR |

Other switches that are not in the list above:

* Promo codes, credits, referral: **Admin > Offers** (three switches, OFF by default). Customer Home > More for you > Offers and credits.
* Surge pricing: `config/pricing.surge.enabled` (OFF). Admin > Config.
* Demo data in a release build: `config/app.allowDemo` (OFF). Admin > Demo data.
* Simple mode for drivers (big buttons): the driver's own switch, Profile > Settings.

## Customer

Bottom bar: **Home**, **Bookings**, **Loads**, **Profile**.

| Feature | Where |
|---|---|
| Book a truck / post a load | Home > hero button, Quick actions > Book a truck / Post a load; Loads tab > Post |
| Book a bike | Home > Quick actions > Book a bike |
| Make a booking slip (consignor LR) with copies, PDF and link; answer inspection requests | Bookings tab > the booking > LR > Bilty (LR); the notification bell |
| Track a shipment, status, ETA, chat, call, LR, POD, invoice | Bookings tab > the booking (chat, call, LR, help and report buttons are on the trip screen) |
| My loads, offers on a load (counter, pick one) | Loads tab > a load |
| Documents (invoices, LR, POD, e-way bills) | Home > Quick actions > Documents |
| Empty trucks board | Home > Quick actions > Empty trucks (flag `emptyTrucks`) |
| Trip history | Home > More for you > Trip history; Profile > Trip history |
| Saved loads (templates), repeat | Home > More for you > Load templates |
| Payments and credits | Home > More for you > Transactions, My spending |
| Favourite drivers | Home > More for you > Favourite drivers |
| My analytics | Home > More for you > My analytics |
| Offers and credits, referral | Home > More for you > Offers and credits (OFF until an Offers switch is on) |
| Business tools | Home > More for you > Business tools (flag `businessTools`) |
| Search | Home > search box |
| Sahayak (assistant) | Home > top right assistant button |
| Notifications | Home > top right bell |
| Language | Home > top right globe; Profile; Settings |
| Edit profile, verification card, logout | Profile tab |
| Settings (theme, notification choices, consents, devices, terms, privacy, refund policy, linked accounts, change mobile number, download my data, delete account) | Profile > Settings |
| Help and support, tickets | Profile > Help and support |
| Emergency contacts, SOS | Profile > Emergency contacts; trip screen > SOS |
| Chat and in-app call | Trip screen > Chat, Call (phone numbers are never shown) |
| Report a problem | Trip screen; Help (flag `problemReport`) |
| Trip share link | Trip screen > Share trip (flag `tripShare`) |

## Driver

Bottom bar: **Home**, **Loads**, **Trips**, **Earnings**, **Profile**.

| Feature | Where |
|---|---|
| Online / offline, nearby loads | Home > top; Loads tab |
| Accept a load, make an offer | Loads tab > a load |
| Active trip, next status, OTP steps, proofs, navigate | Home > Active trip; Trips tab |
| Trips from my transporter | Home > Trips from your transporter (only when a transporter assigned one) |
| Transporter invites, attach my vehicle | Home > the fleet card (accept, attach or detach a vehicle, leave) |
| My truck, vehicle papers, expiry | Home > My truck, Documents and KYC |
| LR (driver copy): route, goods, "Rate hidden by owner"; Show inspection, save the inspection copy | Trip screen > LR (driver copy) |
| Documents center (invoices, LR, POD) | Home > Documents center |
| My offers | Home > My offers |
| Wallet | Home > Wallet; Earnings tab |
| City demand | Home > City demand |
| Empty trucks | Home > Empty trucks (flag `emptyTrucks`) |
| My analytics | Home > My analytics; Profile |
| Favourite routes, pickup alerts | Home > Favourite routes; Loads tab |
| Driver network | Home > Driver network (flag `driverNetwork`) |
| Earnings, history, tips, bonuses, plans | Earnings tab (Rewards: flag `driverRewards`) |
| Edit documents (licence, RC, PAN) | Profile > Edit documents |
| Chat and in-app call | Trip screen > Chat, Call |
| SOS, emergency contacts, trip share | Trip screen; Profile |
| Simple mode, settings, help, delete account | Profile > Settings; Profile > Help and support |

## Transporter

Bottom bar: **Dashboard**, **Loads**, **Trips**, **Fleet**, **Profile**. Flag: `transporter`.

| Feature | Where |
|---|---|
| Company profile, Verified badge | Dashboard > Company profile |
| Papers expiring soon (own and attached vehicles) | Dashboard top card |
| Books (margin, owed to drivers, party-wise due) | Dashboard > Books; Trips > a company trip > Books |
| Analytics (utilisation, revenue, expenses) | Dashboard > Analytics |
| Open loads, bid for the company, post a load | Loads tab > Bid for company; "Post a load" button |
| My bids, confirm a selected bid | Trips tab > My bids |
| Assign or change the vehicle and driver | Trips tab > a company trip |
| Late trips, LR / bilty, trip details | Trips tab |
| Issue an LR, new version, cancel, copies, PDF, link; answer inspection requests, allow inspection in advance | Trips tab > LR > Bilty (LR); the notification bell |
| Vehicles (own and attached) | Fleet tab > Vehicles |
| Drivers, invite by phone | Fleet tab > Drivers |
| Chat and in-app call (customer, assigned driver) | Trip details > Chat, Call, Call driver |
| Sahayak, notifications | Top right |
| Settings, help, emergency contacts, logout | Profile tab |

## Admin

Admin Panel: **Profile > Admin** (only for accounts in `admins/{uid}`). The panel shows only what the staff role may use.

| Screen | What for | Staff roles |
|---|---|---|
| Analytics | counters, trends | all |
| Users | search, risk tier, licence override, export | all |
| Driver verification | approve or reject drivers and transporters | super, verifier |
| Vehicles, Loads, Bookings (reassign, export) | lists and fixes | all (vehicles: super, verifier) |
| Tickets, SOS | support work | super, support (SOS also ops) |
| Reports | user reports, open a case, **open the chat for review** | super, support, ops |
| Chat violations | strikes, suspensions, phone numbers (logged) | super, support, ops |
| Signals, Fraud cases, Flagged users | anti-fraud | super, ops (signals also verifier) |
| Disputes, Rating flags, Rating bursts | claims and ratings | super, support (ops for ratings) |
| Sahayak, Feedback, Templates | assistant and reply templates | super, support |
| Health | app health | super, ops |
| Supply and demand, Unit economics | numbers | super (supply and demand also ops) |
| Features | the flags above, with a line of meaning for each | super |
| Demo data | seed and remove demo data | super |
| Deletion requests | account deletions | super, support |
| Audit log | who did what (includes number views and chat opens) | super, ops |
| Driver rewards, Payouts, Offers, Config | money records and settings | super |
