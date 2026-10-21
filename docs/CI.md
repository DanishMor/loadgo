# CI (Z20)

File: `.github/workflows/ci.yml` (runs on every push to `main` and on pull requests). Jobs:
1. **flutter**: `flutter analyze` (must be 0 issues), `node tool/check_indexes.js`, then the Flutter tests in **batches of 30 files, one batch at a time** (`--concurrency=1`), like on the laptop.
2. **functions**: `npm ci`, then `npm test` (eslint plus the unit tests) in `functions/`.
3. **rules**: `npm ci`, then `npm test` in `firestore_rules_test/` (Firestore and Storage emulators, Java 21).

Safety: the token has `contents: read` only; every action is pinned to a full commit id (a test checks this: `test/ci_workflow_test.dart`); a newer run of the same branch cancels the older one. No secrets are used, and CI never deploys.

Tests that need Windows PowerShell (`phone_tool_test`, `change_package_id_test`) are skipped on Linux by design; they run on the laptop.

## Free minutes: VERIFY
Whether this fits the free GitHub Actions minutes depends on the repository being public or private and on GitHub's current plan limits: **VERIFY** on GitHub's billing page before relying on it. The Flutter job (about 400 test files in 14 batches) is the long one (timeout 45 minutes). If minutes run out, the laptop runs the same checks: `tool/run_regression.ps1` (docs/TESTING.md).
