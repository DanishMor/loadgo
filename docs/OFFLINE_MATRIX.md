# Offline matrix (MASTER-6 Task 39)

How each area behaves with no internet. Firestore offline persistence is on, so anything the person opened before is still readable; a thin "offline" strip shows under the app. Three kinds of behaviour:

- **read**: shows what was cached; may be stale (it says nothing new arrived). Writes wait in Firestore's own queue and are sent when the phone is back online.
- **queue**: the app keeps the action itself and retries (trip status steps, OTP retry), with a sync indicator on the driver home.
- **network**: cannot work offline; the screen says so plainly (never a blank page).

| Area | File | Kind | What happens offline |
|---|---|---|---|
| Sign in / OTP | lib/auth/otp_verification_screen.dart | network | OTP needs the network; says "no internet" |
| Driver home, Today strip | lib/driver/driver_today.dart | read | numbers from cache, may be stale |
| Driver trip steps | lib/core/services/trip_action_queue.dart | queue | step saved on the phone, sent later; sync indicator shows waiting count |
| Pickup / delivery OTP | lib/driver/driver_trip_screen.dart | queue | retried when online; the customer must still be asked for the code |
| Load list (driver) | lib/driver/available_loads_view.dart | read | cached loads, new ones appear when online |
| Make an offer / bid | lib/driver/make_offer.dart | network | offline shows "try again when online" (a bid can go stale) |
| Post a load (customer) | lib/customer/post_load_screen.dart | read | draft autosaves on the phone; posting waits for the network |
| My loads / bookings | lib/customer/my_loads_view.dart | read | cached list |
| Tracking | lib/core/trip/trip_eta.dart | read | last known position with its age |
| Chat | lib/core/chat/chat_screen.dart | read | old messages readable; sending waits and sends later |
| Call | lib/core/call/call_screens.dart | network | needs internet; failure screen offers chat |
| Wallet / ledger | lib/core/payments/wallet_widgets.dart | read | cached balance, marked as of last sync |
| Documents / LR / POD | lib/core/documents/lr_screen.dart | read | cached; PDF share works from cache |
| SOS | lib/core/services/safety_service.dart | read | the alert is written to Firestore and waits in its own queue until the phone is online; no SMS fallback yet (LATER(paid): SMS to emergency contacts), so the person should also call 112 |
| Admin screens | lib/admin/admin_dashboard_screen.dart | network | counts and lists need the network; shows retry |
| Settings, language, theme | lib/core/settings/settings_screen.dart | read | stored on the phone, always works |

Rules the matrix relies on (tests): test/trip_queue_test.dart (queue), test/state_audit_test.dart (lists show an offline or error state, never blank), test/offline_matrix_test.dart (this table is real).
