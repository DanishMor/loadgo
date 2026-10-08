# Code structure rules

One app for now; Admin is a role-gated part of it (not a separate app). Code is laid out so the
Customer and Driver apps can be published separately later (see docs/SPLIT_PLAN.md).
`test/structure_test.dart` enforces the import rules below and fails the build when they are broken.

- `lib/core/`     shared: models, services, l10n, pricing, matching, analytics, enterprise helpers, theme, widgets, chat, documents, notifications, profile; also `core/transporter/` (pure transporter rules), `core/comm/` (contact filter, strike ladder) and `core/call/` (in-app voice call: `CallProvider` interface, WebRTC, signalling, screens)
- `lib/core/app_info.dart` the one place that names the app (see docs/NAMING.md)
- `lib/auth/`     splash, role selection, login, OTP, profile setup, driver pending, start resolvers
- `lib/customer/` customer-only screens
- `lib/driver/`   driver-only screens
- `lib/admin/`    admin-only screens
- `lib/fleet/`    transporter-only screens (dashboard, loads and bids, trips and assigning, fleet, books, company profile)
- `lib/main.dart` app shell only (`main()` and `LoadGoApp`); no feature code, and nothing imports it

Import rules
- `customer/`, `driver/`, `admin/` and `fleet/` never import each other. They import `core/` (and `auth/` if they must).
- `core/` imports nothing from `auth/`, `customer/`, `driver/` or `admin/`. When core needs a screen from
  those folders it takes a builder or a widget list instead (`AppRoutes` in `core/navigation`, `ProfileView.extraTiles`).
- `auth/` may import the role folders (it routes people into the right home screen).
- Admin views are built from `core/` models and widgets, not customer/driver screens.
- A feature both roles use goes in `core/`; a one-role feature goes in that role's folder.
- Nothing imports `main.dart`. Shared things that used to live there are in `core/`.
- Firestore field names (`customerId`, `shipperId`, `driverId`, ...) do not change.
- Admin screens appear only when `admins/{uid}` exists; Firestore rules are the real gate.
