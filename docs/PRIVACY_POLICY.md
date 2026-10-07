# LoadGo privacy policy (draft)

Public copy: `hosting/privacy.html` (kept in step by hand). Lawyer review needed before release.

## What LoadGo is
LoadGo connects customers who need goods moved with drivers and fleet owners who own trucks. It does not move money: payments are made directly between the parties and the app only records them.

## Data we collect
- **Account:** mobile number (for the one-time password login), name, role (customer, driver or fleet owner), language, optional e-mail, company name, GST number and addresses.
- **Drivers and fleet owners:** driving licence number and expiry, vehicle registration number, PAN, the last 4 digits of Aadhaar (the full number is never stored), vehicle details and document expiry dates, payout UPI id. These are formats checked in the app and are not verified against government records.
- **Loads and trips:** pickup and drop places, cargo details, prices and offers, trip status, delivery proofs, chat messages between the two parties of a booking, ratings and support tickets.
- **Location:** the driver's approximate position while location sharing is on, and during a trip. Customers may use location once to pick the nearest city. Location is never collected in the background when the sharing switch is off.
- **Microphone:** only while you hold the mic button, to turn speech into text. Audio is not recorded or stored by LoadGo.
- **Device and app data:** device identifier used for fraud checks, app version, and anonymous crash and error reports.

## Why we use it
To run the service (matching, bookings, safety, support), to prevent fraud and duplicate accounts, to send in-app and push notifications you allow, and to improve the app.

## Who processes it
Google Firebase (Authentication, Firestore, Cloud Messaging, Crashlytics, Analytics, Remote Config) stores and processes the data on our behalf. We do not sell personal data. The other party of a booking sees the details needed for that trip (name, vehicle, trip details and, after acceptance, the phone number).

## Your choices
- Consent switches for location, analytics and marketing are in Settings.
- You can download your data and delete your account from Settings. Deletion is blocked while a trip is active. Bookings, invoices, ledger lines, ratings and chats of finished trips are kept for the legal retention period (see the retention table in the app documentation) and are no longer linked to a usable account.
- Account deletion page: /delete-account.

## Children
LoadGo is not for people under 18.

## Changes and contact
We will update this page when the app changes. Questions: [add support email].
