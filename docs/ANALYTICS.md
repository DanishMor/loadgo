# Analytics (G8)

Firebase Analytics through `lib/core/services/analytics_events.dart`. It is OFF in debug builds. Only event names and short coded parameters go out: **no name, phone number, address, load id, booking id, amount or user id**.

## Funnel (lib/core/services/funnel.dart)

Each step is logged once per person per phone as `funnel_<step>` with one parameter `role` (`customer`, `driver` or `fleet`). The "already logged" marker lives in the phone's own storage.

| Step | Event | Where it is raised |
|---|---|---|
| Sign-up (first role chosen on a new account) | `funnel_signup` | `UserService.markRoleSelected` |
| Profile done | `funnel_profile_done` | `saveCustomerProfile`, `saveFleetProfile`, `saveDriverProfile` |
| Documents added | `funnel_docs_added` | `saveDriverKyc`, `VehicleService.saveDocuments` |
| First load posted | `funnel_first_load` | `LoadService.post` |
| First bid sent | `funnel_first_bid` | `OfferService.send` |
| First delivery | `funnel_first_delivery` | `BookingService.advance` (status delivered) |
| Repeat (second load) | `funnel_repeat_load` | `LoadService.post` |

Older events: `screen_view`, `load_posted`, `offer_sent`, `booking_done`, `company_bid`, `trip_assigned`, `contact_blocked`, `call_started`, `call_connected`.

## Building the funnel in the Firebase Console

Analytics > Explore > Funnel exploration. Add the steps in the order above, open (not closed) funnel, break down by the custom dimension `role` (register `role` once under Custom definitions, event-scoped). Compare step to step to see where people stop.

## Rules for new events

1. Name: letter first, then letters, digits, `_`, at most 40 (`AnalyticsEvents.validName`).
2. Parameters: short codes only. `cleanParams` drops anything else.
3. Add the event to this table and a test (test/funnel_test.dart shows how: `AnalyticsEvents.testSink`).
4. Nothing is logged until the person turns on Settings > data use > analytics (`AnalyticsEvents.consent`, default off; applied after sign-in and when the switch is saved; switched off again on sign-out). A funnel step is not used up while consent is off.
