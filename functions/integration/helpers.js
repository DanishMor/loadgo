'use strict';
// F44: helpers for the integration tests. They talk to the LOCAL emulators only:
// the host variables are set by `firebase emulators:exec`, and the project id is a made-up one.

const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const { getStorage } = require('firebase-admin/storage');

const PROJECT = 'loadgo-integration';
const FUNCTIONS = 'http://127.0.0.1:5002';
const AUTH = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9098';

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('run these tests with integration/run.sh (emulators only)');

if (getApps().length === 0) initializeApp({ projectId: PROJECT, storageBucket: `${PROJECT}.appspot.com` });

const db = getFirestore();
const auth = getAuth();
const bucket = () => getStorage().bucket();

async function waitFor(check, what, ms = 20000) {
  const end = Date.now() + ms;
  let last;
  while (Date.now() < end) {
    try {
      last = await check();
      if (last) return last;
    } catch (e) {
      last = e;
    }
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error(`timed out waiting for: ${what} (${last && last.message ? last.message : last})`);
}

// A quiet period: used to show that something did NOT happen.
const pause = (ms) => new Promise((r) => setTimeout(r, ms));

async function setFlags(flags) {
  await db.collection('config').doc('features').set({ flags });
  // The functions cache the switches for 30 s; wait it out only when a switch was turned off.
}

// A signed-in person in the Auth emulator; returns the id token for callable requests.
async function signUp(email) {
  const res = await fetch(`http://${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: 'pass-for-emulator-1', returnSecureToken: true }),
  });
  const j = await res.json();
  if (!j.idToken) throw new Error('signUp failed: ' + JSON.stringify(j));
  return { uid: j.localId, token: j.idToken };
}

// Calls a callable function the way the app's SDK does.
async function callFn(name, data, token) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(`${FUNCTIONS}/${PROJECT}/asia-south1/${name}`, { method: 'POST', headers, body: JSON.stringify({ data }) });
  const j = await res.json();
  return { status: res.status, result: j.result, error: j.error };
}

async function clearAll() {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  const list = await auth.listUsers(1000);
  if (list.users.length) await auth.deleteUsers(list.users.map((u) => u.uid));
}

module.exports = { PROJECT, db, auth, bucket, waitFor, pause, setFlags, signUp, callFn, clearAll };
