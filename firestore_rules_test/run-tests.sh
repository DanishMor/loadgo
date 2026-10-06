#!/bin/sh
# Runs the rules tests in slices (see RULES_PARTS in rules.test.mjs), one
# emulator session per slice, then the storage tests. Stops at the first failure.
set -e
EXEC="./node_modules/.bin/firebase emulators:exec --config ../firebase.json --only firestore,storage --project loadgo-rules-test"
PARTS=${RULES_PARTS:-4}
$EXEC "node --test storage.test.mjs"
i=1
while [ $i -le $PARTS ]; do
  echo "== rules slice $i of $PARTS =="
  $EXEC "RULES_PARTS=$PARTS RULES_PART=$i node rules.test.mjs"
  i=$((i+1))
done
