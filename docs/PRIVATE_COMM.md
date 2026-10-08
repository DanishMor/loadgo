# Private chat and call (Task 68)

Customers, drivers and transporters never see each other's phone number. They talk inside the app, in a
chat and in a free voice call. Free stack only: Flutter, Firebase Auth, Firestore, `flutter_webrtc`, Google's public
STUN servers. Anything that needs money or a server is marked `// LATER(paid)` or `// TODO(functions)`.

## 1. Numbers are hidden

* Nothing in the customer, driver or transporter screens shows or dials the other party's number any more:
  the booking summary shows name, vehicle number and a **Call** button; the share texts carry the driver name
  only; the trip alert text has no number; `PhoneVisibility.visiblePhone` always returns "".
* New bookings store no phone number (`bookings.driverPhone` is ''; the rules require it).
  Older bookings may still hold one in the document, but no screen reads it.
* Transporter screens mask the phone of invited drivers (`maskPhone`).
* **Still opens the dialer:** SOS and 112 (`trip_safety_card.dart`), the user's own emergency contacts, and the
  support number in Help. These are not a counterpart's number.
* **Admins** see both numbers. In every admin screen a number is masked until it is tapped; the tap writes an
  `audit_events` line of type `contact_view` (who, which person, which booking) first, and if that line cannot be
  written the number stays hidden. In a chat review "Show both phone numbers (logged)" does the same for both people.
  `// TODO(functions)`: write the line from a server so a modified admin app cannot skip it.

## 2. What the chat blocks (before sending)

`lib/core/comm/contact_filter.dart` (pure, offline, tested by `test/contact_filter_test.dart`):

| Caught | Examples |
|---|---|
| Phone numbers | `9876543210`, `+91 98765 43210`, `98765-43210`, `9.8.7.6...`, `(98765) 43210`, `011 2345 6789`, 8-9 digit pieces that start like a mobile number |
| Other scripts and tricks | Devanagari, Bengali, Arabic-Indic and full-width digits, keycap emoji, zero-width characters |
| Spelled out | `nau aath saat chhe paanch char teen do ek zero`, English words, Hindi words, `double seven` |
| Split over messages | `98765` then `43210` (the sender's last three messages are joined) |
| UPI and e-mail | any `name@handle` |
| Apps and links | WhatsApp (also `w h a t s a p p`), Telegram, `t.me`, `wa.me`, `http://`, `www.` |
| Asking for contact | `call me`, `call karo`, `apna number do`, `mobile number`, `व्हाट्सएप पर आओ`, `मोबाइल नंबर दो` |
| Paying outside | `pay outside the app`, `app ke bahar payment` |

Ordinary numbers stay fine: weights, prices (`12,50,000`), times (`10:30`), dates, vehicle numbers
(`MH12AB1234`), pin codes, OTPs, 13-digit invoice numbers. A price range such as `25000-30000` is allowed because
Indian mobile numbers start with 6-9.

The message is **not sent**. The text stays in the box so it can be edited, and a warning explains why. Limits:
a determined person can invent a new trick (a picture of a number, a made-up code word). `// LATER(paid)`: a
server-side check. The Firestore rules repeat the plain cases for a modified app: a message with a 10-digit mobile number or an
`@` is refused (`chatTextClean`).

## 3. Strikes

A stopped message writes `violations/{uid}_{seq}` (kind, up to 120 characters of the text, time) and raises
`users.chatStrikes` by one **in the same batch**; the rules check the id, the count and the ladder, like
`cancelCount`.

| Strike | What happens |
|---|---|
| 1, 2 | Warning ("Warning 1 of 2") |
| 3 | Chat and calls off for 24 hours |
| 4 | 3 days |
| 5 and more | 7 days and `chatReview = true` (an admin reviews the account) |

* `users.chatBlockedUntil` is checked by the rules when a **message** or a **call** is created (`chatAllowed`).
  The person sees a plain message in 12 languages with the time ("Chat and calls are off until ... SOS still works").
* **30 clean days** take one strike off (`chatDecayStep`, tried when a chat opens). The clock restarts at each change.
* The block end may be at most one hour earlier than the ladder says (phone clocks differ); a wrong phone clock
  beyond that means the strike cannot be saved, the message is still not sent and the person is told.
* Fields: `chatStrikes`, `chatSeq` (never goes down, makes the violation id), `chatStrikeAt`, `chatBlockedUntil`,
  `chatReview`. Only the ladder steps above or an admin can change them. A new account cannot start with them.
* **Report buttons**: in the chat menu "Report" now has "Asked for my number" and "Sent me a number".

## 4. In-app voice call

* `CallProvider` (interface) with `WebRtcCallProvider` (flutter_webrtc, STUN `stun.l.google.com`). Signalling in
  Firestore: `calls/{id}` (offer, answer, status) and `calls/{id}/candidates`. The audio goes phone to phone and never
  through Firestore. Only STUN: if both phones are behind strict networks the call may not connect (the app says so).
* `CallController` runs the call from either side; `CallScreen` (mute, speaker, end) and `IncomingCallHost`
  (mounted around every signed-in home through `DeepLinkListener`) open the incoming-call screen.
* **Rings only while the app is open.** A ringing call older than about a minute is not shown. A closed app does not ring.
  `// LATER(paid)`: push (FCM sender).
* **Only for a confirmed, unfinished booking** (`accepted` ... `unloading`), only between its people (customer, driver, the
  transporter holding the booking, the assigned driver), never while the caller is suspended. Rules: `callBookingOk`,
  `chatAllowed`. No phone number is stored in a call document.
* **Microphone**: a plain-words dialog first (`RationaleKind.callMicrophone`), then the system prompt. Refused: a clear
  message, nothing starts.
* The call document keeps who called whom, when and how it ended (declined, cancelled, ended). Nothing is recorded.
* `// LATER(paid)`: a masked-number provider (the phone network rings both people without showing a number) behind the
  same `CallProvider` interface, plus a TURN server for strict networks.

## 5. Admin

* **Admin > Chat violations**: people with violations, their strikes, suspension and review flag, the last blocked messages,
  **Extend 7 days**, **Lift suspension**, **Reset strikes** (each audited as `user_action`), and the masked phone.
* **Admin > Reports > Open chat for review**: creates `chat_reviews/{bookingId}` (needs a report or a *dispute* ticket
  about that booking; the rules check it), logs a `chat_view` audit line and shows the chat. Without it admins cannot read messages.
* Call metadata (`calls`) is readable by admins.

## 6. Privacy Policy and Terms

Both now say that phone numbers are not shown between users, that chat and call details (not audio) can be reviewed by
admins for safety, that phone numbers are logged when an admin views them, that a chat is opened only for a report or
dispute, and the strike rules. Updated in `docs/PRIVACY_POLICY.md`, `docs/TERMS.md`, `hosting/privacy.html`,
`hosting/terms.html` and the in-app text (`privC3`, `tosC3`, 12 languages).

## Tests

`test/contact_filter_test.dart`, `test/task68_test.dart`, `test/chat_test.dart`, and the rules suite
"private chat and call (Task 68)" in `firestore_rules_test/rules.test.mjs` (20 cases).
