'use strict';
// Test helpers: a Firestore handle on the local emulator and a way to empty it.
// The emulator is started by run-emulator-tests.sh (firebase emulators:exec),
// which sets FIRESTORE_EMULATOR_HOST. Nothing here can reach a real project.

const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const PROJECT = 'loadgo-functions-test';
// Stops the Google client library from looking for cloud credentials (it waits for a network timeout otherwise).
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || PROJECT;

function emulatorHost() {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  if (!host) throw new Error('FIRESTORE_EMULATOR_HOST is not set: run these tests with npm run test:emulator');
  return host;
}

function getDb() {
  emulatorHost();
  if (getApps().length === 0) initializeApp({ projectId: PROJECT });
  return getFirestore();
}

async function clearDb() {
  const res = await fetch(`http://${emulatorHost()}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error('could not clear the emulator: ' + res.status);
}

module.exports = { getDb, clearDb, PROJECT };
