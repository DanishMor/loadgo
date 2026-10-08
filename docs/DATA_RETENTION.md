# Data retention policy (BE17)

Written 2026-10-04 for the free stack (Auth + Firestore). It states what LoadGo keeps, for how long, and who can remove it. The in-app text comes with Task 28 (Help and legal); until then this file is the reference.

| Data | Where | Kept | Removed when |
|---|---|---|---|
| Phone number, name, language, consents | `users/{uid}` | While the account exists | Account deletion |
| Driver documents (licence, RC, PAN, Aadhaar last 4 only) | `users/{uid}.driverKyc` | While the account exists | Account deletion or the driver edits them |
| Identity index (hash of licence / PAN / RC / GST) | `identity_index` | While the account exists | Account deletion; admins can free an entry |
| Last location (with consent) | `users/{uid}.lastLocation` | Until the next update | Consent switched off (deleted at once) or account deletion |
| Devices | `users/{uid}/devices`, `device_links` | While the account exists | Revoke, account deletion |
| Loads, bookings, chat, ratings, tips, payments records | `loads`, `bookings/*`, `ratings`, `tips`, `ledger` | 8 years (tax and dispute period; GST records) | Not deleted on request; personal fields are cleared when the account is deleted |
| Audit events, risk signals, fraud cases | `audit_events`, `risk_signals`, `fraud_cases` | 3 years | Admin clean-up |
| Support tickets, SOS, reports | `tickets`, `sos_alerts`, `reports` | 3 years | Admin clean-up |
| Notifications | `notifications` | Until the user deletes them | Account deletion |
| Chat violations (`violations/{uid}_{seq}`: kind, up to 120 characters of the stopped text, time) and the strike fields on `users` (`chatStrikes`, `chatSeq`, `chatStrikeAt`, `chatBlockedUntil`, `chatReview`) | `violations`, `users` | 3 years (safety evidence; one strike comes off after 30 clean days, the record stays) | Admin clean-up; strike fields go with the profile on account deletion |
| In-app call records (who, when, how it ended; no audio, no phone number) | `calls`, `calls/*/candidates` | 1 year | Admin clean-up (`TODO(functions)`: scheduled delete) |
| Admin views of a phone number or a chat | `audit_events` (`contact_view`, `chat_view`), `chat_reviews` | 3 years | Admin clean-up |
| Transporter books (what a party pays, what a driver is owed; private to the transporter) | `transporter_accounts` | While the account exists | The owner, or account deletion (done in the app) |
| Fleet membership, attached vehicle | `fleet_members`, `vehicles.attachedTo` | While active | Either side ends it; the driver can detach a vehicle any time |
| Promo redemptions, credits ledger, referrals | `promos/*/slots`, `users/{uid}/credits`, `referrals` | 3 years | Account deletion (credits lines are cleared) |

Rules:
- Aadhaar is never stored in full: only the last 4 digits.
- A deletion request (`deletion_requests/{uid}`) is handled by an admin today. TODO(functions): perform it with the Admin SDK (delete Auth user, `users/{uid}` and its subcollections, `identity_index` entries, device links). Task 28 adds the in-app flow.
- Anything legally required (GST invoices, e-way bill references, payment records) is kept for the period above even after the account is gone, without the person's contact details.
- Admin checklist: review `deletion_requests` weekly; remove audit/risk/support records older than 3 years once a year; never export personal data outside the project.
