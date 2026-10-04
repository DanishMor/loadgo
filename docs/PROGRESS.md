# LoadGo progress (Final Master Roadmap, free stack only)

Resume from the first task that is not `done`. Stack: Flutter + Firebase Auth + Firestore only.
Paid/manual items are marked `// LATER(paid): ...` in code and listed in docs/MANUAL_TODO.md.

| # | Task | Status | Notes |
|---|---|---|---|
| 1 | Auth fixes (resend OTP, error map, language persist, masked phone, digits only) | done | auth_helpers.dart, language_store.dart, lib/l10n/ split |
| 2 | Vehicle types config | done | config/vehicle_types + fallback, rules: signed-in read, admin write |
| 3 | Vehicle documents, availability, duplicates | done | vehicle_numbers registry, lib/driver/vehicle_documents_screen.dart |
| 4 | Pricing engine + fare estimate + cancellation policy | done | lib/core/pricing, config/pricing, TODO(functions) for server fare |
| 5 | Load posting upgrade (multi-stop, saved places, prohibited cargo, slot, repost) | done | lib/customer/saved_place_picker.dart, rules regex for prohibited goods |
| 6 | Offers & negotiation | done | offers/{loadId}_{driverId}, double confirmation in the booking transaction |
| 7 | Trip lifecycle + OTPs + POD + LR | done | bookings/{id}/secrets/otp (customer-only), rules compare driver input; lib/core/documents |
| 8 | Booking chat | done | bookings/{id}/messages, chat_reads, users/{uid}/blocked, reports |
| 9 | Support tickets & safety (SOS, contacts, breakdown) | done | tickets(+replies), sos_alerts, users.emergencyContacts, bookings.breakdown |
| 10 | Payment records & documents center | done | paymentStatus on bookings, ledger/{bookingId}_{type} append-only, lib/core/documents |
| 11 | Anti-fraud basics | done | users.riskTier (admin-only), canTransact() rules, audit_events append-only, cancelCount (+1 in same batch), lib/admin/flagged_users_screen.dart |
| 12 | Admin dashboard | done | admins/{uid} allowlist, lib/admin/*, AdminConsoleService |
| 13 | Matching & recommendations | todo | |
| 14 | Analytics & settings | todo | |
| 15 | Enterprise lite + import/export | todo | |
| 16 | Quality (CI, rules review, docs) | todo | |
| END | Deploy rules/indexes + final summary | todo | |

## Conventions
- New UI strings live in `lib/l10n/*_strings.dart` as 12-item lists in `AppLanguage` order
  (en, hi, hinglish, kn, ta, te, mr, gu, bn, pa, ks, ur); merged into `T.data`.
- Money is always integer paise.
- Server-only logic that would need Cloud Functions is marked `// TODO(functions)`.
- After each task: `flutter analyze` (0 issues), `flutter test`, rules tests when rules change, commit. Push every 3 tasks.

## Log
- 2026-10-04 Task 1 done: resend OTP (60s, forceResendingToken), Firebase error-code map, language saved to device + users.language, masked phone on OTP/profile/home, digits-only inputs.
- 2026-10-04 Task 2 done: VehicleTypeService (config/vehicle_types, 15 fallback types with tonne ranges), translated labels, used by add vehicle, post load (weight vs max check), filters, driver setup.
- 2026-10-04 Structure rules received (see docs/ARCHITECTURE.md). Prep for Task 17a done early: language system, tr()/trf(), translation tables and language selector moved to lib/core/l10n; main.dart re-exports them so old `import '../../main.dart'` keeps working. New code imports core/ directly and puts screens in lib/{auth,customer,driver,admin}.
- 2026-10-04 Task 3 done: insurance/PUC/fitness/permit (number + expiry, 'Unverified'), next service date, availability (available/on_trip/maintenance/suspended; on_trip set by accept, freed on deliver/cancel; admin-only suspend), duplicate numbers blocked via vehicle_numbers/{number} (rules), Home banner for papers expiring within 30 days. LiveStream widgets moved to core/widgets.
- 2026-10-04 Task 4 done: FareCalculator (paise, basis-point rounding, min fare, loading/unloading, waiting per started hour, extra stops, platform fee %, GST %), config/pricing with category + type rate cards, 64-city offline table (haversine x road factor 1.25) + manual km override, estimate card + breakdown sheet on Post Load, estimate stored on load and copied to booking, config-driven cancellation charge recorded on driver cancel (record only).
- 2026-10-04 Task 5 done: up to 3 pickups/3 drops (extraPickups/extraDrops, leg-by-leg distance, per-stop charge), saved places (users/{uid}/saved_places, max 20), prohibited goods list (client + rules regex), pickup time slot, Repost on closed loads. core/widgets/vehicle_type_widgets.dart renamed logistics_labels.dart.
- 2026-10-04 Task 6 done: drivers send a price (Make offer next to Accept); customer sees Offers (n) on open loads, counters once, selects/rejects; selected driver confirms and the booking is created with agreedFarePaise in the same transaction (rules check the offer is selected, price matches, offer becomes confirmed). My Offers screen for drivers.
- 2026-10-04 Task 7 done: statuses accepted→driver_arriving→loading→picked_up→in_transit→unloading→delivered; customer creates 6-digit pickup/delivery OTPs in bookings/{id}/secrets/otp (only they can read); driver's entered OTP must equal the secret (rules); pickup proof (packages, weight, seal, damage) and delivery proof (receiver name/phone, damage); POD packet screen (photos LATER(paid)); digital LR/bilty screen with 12-digit e-way bill field. Driver can cancel until loading. TODO(functions): OTP attempt rate-limit.
- 2026-10-04 Task 8 done: booking chat (lib/core/chat) with unread badge on the Chat button, off-platform detector (phone / UPI id / pay-outside phrases, warn before send + flag), 500-char limit, report (reports collection, admin review) and block (rules stop messages to someone who blocked you).
- 2026-10-04 Task 9 done: support tickets (category incl. dispute needing a booking, priority, status, escalation 0-3, replies; owner/admin rules), Help & support + Emergency contacts in Profile, Help button on bookings, driver SOS (sos_alerts with last location, then call 112 / contacts via tel:), breakdown report (booking flag + replacement request + customer notification). SMS/masked calling LATER(paid).
- 2026-10-04 Task 10 done: payment mode on loads (cash / UPI direct, copied to bookings), payment record pending -> customer_marked_paid (amount) -> driver_confirmed, which writes append-only ledger lines (earning + negative commission from config/pricing.commissionPercent), driver Wallet screen, invoice moved to core with GST-inclusive CGST/SGST split, Documents center (invoices, LR, POD; drivers also vehicle papers). All labelled records only; gateway LATER(paid).
- 2026-10-04 Task 11 done: riskTier normal/review/restricted/suspended (admin-only write); restricted/suspended blocked from post/offer/accept in services and rules; audit_events (verification, accept, status_change, cancel, risk_change) append-only, admin-read; cancelCount incremented with every cancel (rules enforce +1 in the same batch); user reports reuse Task 8 `reports`; admin Flagged users list with tier edit (to be linked from the Task 12 dashboard).
- 2026-10-04 Task 12 done: admin = a doc at admins/{uid} created by hand in the Firebase Console (rules `isAdmin()` = exists(admins/uid); the old `admin` custom claim no longer counts). Profile shows "Admin panel" only for those users (AdminEntryTile); the dashboard (lib/admin/) has analytics counters (users, loads/bookings by status, delivered fare sum), users search + risk tier edit, driver verification, vehicles (suspend/lift), loads, bookings (manual driver reassign by vehicle number, audited as `reassign`), tickets (status + reply), SOS alerts, reports queue, flagged users, JSON editors for config/pricing and config/vehicle_types. Admins can read all loads/bookings; they cannot edit them except the reassign batch.
- Note: check `flutter test` exit status directly (not through `| tail`) before committing.
