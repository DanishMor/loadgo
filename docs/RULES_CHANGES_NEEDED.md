# Rules changes needed (for the owner to review)

Rules are never loosened by Claude. If a future task needs a rules change, it is listed here with the reason and the test that covers it, and the owner publishes it by `docs/RULES_PUBLISH.md`.

Until these are published, the features below stay OFF (their flags default OFF) and the app keeps working: a denied write shows the usual E-PERM reason in Diagnose.

## Waiting to be published

| Task | File | What is added | Why | Tests |
|---|---|---|---|---|
| E18 | `firestore.rules` | `vehicles/{vehicleId}/photos/{slot}`: owner writes a pending record (slot, path, status, at; path must be its own Storage path); verifier admins approve or reject with a reason; `badge` record written only by verifiers, at most 190 days ahead; plate and RC records readable only by the owner and admins | Photo-verified vehicles (flag `vehiclePhotos`) | `firestore_rules_test/vphotos.test.mjs` (8 cases) |
| E18 | `storage.rules` | `users/{uid}/vphotos/{vehicleId}/{slot}`: owner writes images under 3 MB to eight known slots; outside views readable by signed-in people, plate and RC only by the owner and admins | Same | `vphotos.test.mjs` (storage cases); `storage.test.mjs` 13/13 and `redteam_storage.test.mjs` 31/31 still pass |
| E18c | `firestore.rules` + `firestore.indexes.json` | `match /{p=**}/photos/{slot}`: super and verifier admins may list photo records across vehicles (at most 50 per query); a single-field collection-group index on `photos.status` (fieldOverrides keep the three automatic collection indexes) | Admin photo review queue (flag `vehiclePhotos`) | `vphotos.test.mjs` (queue case), `redteam.test.mjs` (driver cannot list the group), matrix 176/176 with vphotos |

Earlier: Z5 (`node tool/rules_app_drift.js`) found no field the app writes that `firestore.rules` never mentions.
