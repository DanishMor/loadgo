#!/bin/sh
# Runs the function tests that need Firestore against the LOCAL emulator.
# Needs Java (Android Studio's jbr is fine: set JAVA_HOME only for this command).
# Nothing here talks to a real Firebase project and nothing is deployed.
set -e
EXEC="../firestore_rules_test/node_modules/.bin/firebase emulators:exec --config ../firebase.json --only firestore --project loadgo-functions-test"
$EXEC "node --test --test-concurrency=1 test/emulator/*.test.js"
