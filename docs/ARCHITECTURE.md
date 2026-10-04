# Code structure rules

One app for now; Admin is a role-gated part of it (not a separate app). Code is laid out so the
Customer and Driver apps can be published separately later (see docs/SPLIT_PLAN.md, Task 17).

- `lib/core/`   shared: models, services, l10n, theme, widgets, chat, notifications
- `lib/auth/`   login, OTP, profile setup
- `lib/customer/` customer-only screens
- `lib/driver/`   driver-only screens
- `lib/admin/`    admin-only screens

Import rules
- `customer/`, `driver/` and `admin/` never import each other. They import only `core/` (and `auth/`).
- Admin views are built from `core/` models and widgets, not customer/driver screens.
- A feature both roles use goes in `core/`; a one-role feature goes in that role's folder.
- New code does not go into `main.dart`, and new files never import `main.dart`
  (older files still do; Task 17 removes that). `lib/features/` is legacy and is moved in Task 17.
- Firestore field names (`customerId`, `shipperId`, `driverId`, ...) do not change.
- Admin screens appear only when `admins/{uid}` exists; Firestore rules are the real gate.
