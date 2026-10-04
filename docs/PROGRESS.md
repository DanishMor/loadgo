# LoadGo progress (Final Master Roadmap, free stack only)

Resume from the first task that is not `done`. Stack: Flutter + Firebase Auth + Firestore only.
Paid/manual items are marked `// LATER(paid): ...` in code and listed in docs/MANUAL_TODO.md.

| # | Task | Status | Notes |
|---|---|---|---|
| 1 | Auth fixes (resend OTP, error map, language persist, masked phone, digits only) | done | auth_helpers.dart, language_store.dart, lib/l10n/ split |
| 2 | Vehicle types config | done | config/vehicle_types + fallback, rules: signed-in read, admin write |
| 3 | Vehicle documents, availability, duplicates | done | vehicle_numbers registry, lib/driver/vehicle_documents_screen.dart |
| 4 | Pricing engine + fare estimate + cancellation policy | in-progress | |
| 5 | Load posting upgrade (multi-stop, saved places, prohibited cargo, slot, repost) | todo | |
| 6 | Offers & negotiation | todo | |
| 7 | Trip lifecycle + OTPs + POD + LR | todo | |
| 8 | Booking chat | todo | |
| 9 | Support tickets & safety (SOS, contacts, breakdown) | todo | |
| 10 | Payment records & documents center | todo | |
| 11 | Anti-fraud basics | todo | |
| 12 | Admin dashboard | todo | |
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
