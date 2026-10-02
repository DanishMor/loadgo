# Firestore rules tests

Tests for `../firestore.rules` and `../storage.rules`, run against the local Firestore + Storage emulators (needs Java).

```bash
cd firestore_rules_test
npm install
npm test
```

## Deploying the rules

Either paste `firestore.rules` into Firebase Console → Firestore Database → Rules → Publish, or with the CLI from the repo root:

```bash
npx --prefix firestore_rules_test firebase login
npx --prefix firestore_rules_test firebase deploy --only firestore:rules,storage --project loadgo-defc2
```
