# LoadGo privacy policy (draft)

Public copy: `hosting/privacy.html` (kept in step by hand). Lawyer review needed before release.

## What LoadGo is
LoadGo connects customers who need goods moved with drivers and transporters who own trucks. It does not move money: payments are made directly between the parties and the app only records them.

## Data we collect
- **Account:** mobile number (for the one-time password login), name, role (customer, driver or transporter), language, optional e-mail, company name, GST number and addresses.
- **Drivers and transporters:** driving licence number and expiry, vehicle registration number, PAN, the last 4 digits of Aadhaar (the full number is never stored), vehicle details and document expiry dates, payout UPI id. These are formats checked in the app and are not verified against government records.
- **Loads and trips:** pickup and drop places, cargo details, prices and offers, trip status, delivery proofs, chat messages between the two parties of a booking, ratings and support tickets.
- **Location:** the driver's approximate position while location sharing is on, and during a trip. Customers may use location once to pick the nearest city. Location is never collected in the background when the sharing switch is off.
- **Microphone:** while you hold the mic button, to turn speech into text, and during an in-app call. Audio is not recorded or stored by LoadGo, and call audio does not pass through LoadGo servers (it goes directly between the two phones).
- **Chat and call records:** the messages of a booking, who called whom, when, and how the call ended (no audio). Messages that were stopped because they carried a phone number, a UPI id or another app are not sent; a short copy (up to 120 characters), the kind and the time are kept as a "violation", and a strike count is kept on your profile.
- **Device and app data:** device identifier used for fraud checks, app version, and anonymous crash and error reports.

## Why we use it
To run the service (matching, bookings, safety, support), to prevent fraud and duplicate accounts, to send in-app and push notifications you allow, and to improve the app.

## Who processes it
Google Firebase (Authentication, Firestore, Cloud Messaging, Crashlytics, Analytics, Remote Config) stores and processes the data on our behalf. We do not sell personal data. The other party of a booking sees the details needed for that trip (name, rating, vehicle number, verified badge and trip details). **Phone numbers are never shown between customers, drivers and transporters**; they chat and call inside the app.

**What LoadGo staff can see.** For safety, LoadGo admins can see a person's phone number (every view is written to an audit log), the call history details (who, when, how it ended; calls are not recorded) and the chat of one booking, but a chat is opened only when there is a report or a dispute about that booking (and that is logged too).

**Bilty (LR) and share links.** A transporter, or a customer on their own booking, can make a numbered LR. The rate, margin, phone numbers and value fields are kept apart from the public part and are readable only by the person who made it, the two parties of the booking and admins; the driver gets a driver copy without them. A share link shows only the copy type you choose, has an end date, can be revoked, and counts how many times it was opened. Making and sharing an LR, and every inspection request or approval, are recorded in an audit log.

## Your choices
- Consent switches for location, analytics and marketing are in Settings.
- You can download your data and delete your account from Settings. Deletion is blocked while a trip is active. Bookings, invoices, ledger lines, ratings and chats of finished trips are kept for the legal retention period (see the retention table in the app documentation) and are no longer linked to a usable account.
- Technical error samples, unanswered assistant questions and call records have an expiry date (about 3 months, 6 months and 1 year) and are then deleted automatically. On account deletion your bilty (LR) share links are switched off.
- Account deletion page: /delete-account.

## Children
LoadGo is not for people under 18.

## Changes and contact
We will update this page when the app changes. Questions: [add support email].
