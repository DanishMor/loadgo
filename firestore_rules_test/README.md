# Firestore rules tests

Tests for `../firestore.rules`, run against the local Firestore emulator (needs Java).

```bash
cd firestore_rules_test
npm install
npm test
```

## Deploying the rules

Either paste `firestore.rules` into Firebase Console → Firestore Database → Rules → Publish, or with the CLI from the repo root:

```bash
npx --prefix firestore_rules_test firebase login
npx --prefix firestore_rules_test firebase deploy --only firestore:rules --project loadgo-defc2
```
