#!/bin/sh
# F44: runs the integration tests through the local emulators (Auth, Firestore, Functions, Storage).
# Needs Java (Android Studio's jbr, set JAVA_HOME only for this command). Nothing is deployed and
# nothing reaches a real Firebase project. The two Razorpay secrets are fake values for the emulator
# only and the file is removed at the end.
set -e
# The functions emulator reads the code to find the functions; on a slow laptop that can pass 10 seconds.
export FUNCTIONS_DISCOVERY_TIMEOUT=60
cd "$(dirname "$0")/.."
printf 'RAZORPAY_KEY_ID=test_key_id_for_emulator\nRAZORPAY_KEY_SECRET=test_secret_for_emulator\n' > .secret.local
trap 'rm -f .secret.local' EXIT
../firestore_rules_test/node_modules/.bin/firebase emulators:exec --config ../firebase.integration.json --only auth,functions,firestore,storage,pubsub --project loadgo-integration "node --test --test-concurrency=1 integration/*.test.js"
