#!/bin/sh
# Red-team suite (H2): attacks on firestore.rules, then on storage.rules.
set -e
EXEC="./node_modules/.bin/firebase emulators:exec --config ../firebase.json --only firestore,storage --project loadgo-rules-test"
$EXEC "node --test redteam.test.mjs"
$EXEC "node --test redteam_storage.test.mjs"
