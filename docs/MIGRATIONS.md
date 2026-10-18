# Data migrations

## pickupGeohash on old loads (Task 3 of run 3)

New loads store `pickupGeohash` (7 characters, geohash of the pickup city from the offline city table). Loads posted before this have no such field, so the driver's "nearby" query cannot see them (the normal newest-first page still lists them).

**Run once after deploying the app, rules and indexes:**
1. Deploy `firestore.rules` (admins may add `pickupGeohash` to a load that lacks it, nothing else) and `firestore.indexes.json` (loads: status + pickupGeohash). The index takes a few minutes to build; until then the nearby query logs an error and the list falls back to the page.
2. Sign in as an admin, open Admin panel > Config > "Add location codes to old loads". It updates up to 400 loads per tap and shows how many changed. Repeat until it says 0. It skips places that are not in the city table and loads that already have the field, so repeating is safe.

Why not a Node/Admin SDK script: it needs a service-account key, and the in-app tool uses the same Firestore rules as everything else. `// LATER(paid)`: when Cloud Functions exist, set the field in an `onCreate` trigger and backfill with the Admin SDK.

## Load mode for old loads (U10, Part 4)

New loads can carry `mode` (`instant`, `bid`, `scheduled`), `bidWindowEnds`, `autoAccept` and `ringBoost` (switch `dispatchV2`). Old loads have none and the app and the rules treat them as `instant`, so this migration is optional: it only makes admin queries tidy.

1. Publish `firestore.rules` first (it accepts the new fields; a bid-mode load can be taken only through a selected bid).
2. `node tool/migrate_loads_mode.js --project <id>` is a dry run: it prints how many loads would change and writes nothing.
3. `node tool/migrate_loads_mode.js --project <id> --apply` writes `mode` (`scheduled` when the load has `scheduledAt`, else `instant`) in batches of 400. Loads that already have a valid mode are skipped, so it is safe to run twice.

It signs in with your own Google login (`gcloud auth application-default login`) or uses `FIRESTORE_EMULATOR_HOST`; no key file is read or written.
