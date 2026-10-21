# Index check (Z4)

Command: `node tool/check_indexes.js` (add `--verbose` to list queries it could not follow, `--json` for machine output, `--add` to append missing composite indexes to `firestore.indexes.json`, additive only).
Test: `flutter test --concurrency=1 test/index_check_test.dart` fails when a query in `lib/` needs a composite index that is not in `firestore.indexes.json`.

## Result (this run)
- Queries scanned: 439 (where / orderBy chains on `collection`, `collectionGroup`, helper getters like `_lrs` and `_col('x')`).
- Composite indexes needed by the app: 4, all present. Missing: 0. Nothing was added to `firestore.indexes.json`.
- The app mostly sorts on the phone and keeps queries to one field, so it needs few composite indexes. The other indexes in the file are for Cloud Functions (see `test/function_indexes_test.dart`).
- LR register (Z2): `lrs where issuerId` and `lr_shares where ownerId` are single-field, so no composite index is involved. If the register still does not load on the phone, the likely cause is rules or network, not an index.

## What counts as "needs a composite index"
Equality on one or more fields plus an orderBy or range on a different field; a range plus an orderBy on another field; two or more orderBy fields. Equality-only queries and single-field orderBy do not (Firestore merges the automatic single-field indexes).

## Limits (what the checker cannot see)
- Queries built step by step (`q = q.where(...)` in several statements) are listed as "unresolved" (15 now, all checked by hand: each has one filter and no orderBy, so none needs an index).
- Field names that are variables, `FieldPath.documentId`, and queries in Cloud Functions (`functions/`) are not scanned.
- It does not know if the index is already built on Firebase, only that it is declared in the file. Publishing is an owner step (see `docs/RELEASE_CANDIDATE.md`).
