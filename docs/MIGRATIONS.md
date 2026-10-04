# Data migrations

## pickupGeohash on old loads (Task 3 of run 3)

New loads store `pickupGeohash` (7 characters, geohash of the pickup city from the offline city table). Loads posted before this have no such field, so the driver's "nearby" query cannot see them (the normal newest-first page still lists them).

**Run once after deploying the app, rules and indexes:**
1. Deploy `firestore.rules` (admins may add `pickupGeohash` to a load that lacks it, nothing else) and `firestore.indexes.json` (loads: status + pickupGeohash). The index takes a few minutes to build; until then the nearby query logs an error and the list falls back to the page.
2. Sign in as an admin, open Admin panel > Config > "Add location codes to old loads". It updates up to 400 loads per tap and shows how many changed. Repeat until it says 0. It skips places that are not in the city table and loads that already have the field, so repeating is safe.

Why not a Node/Admin SDK script: it needs a service-account key, and the in-app tool uses the same Firestore rules as everything else. `// LATER(paid)`: when Cloud Functions exist, set the field in an `onCreate` trigger and backfill with the Admin SDK.
