// Gives old loads a `mode` (U10, Part 4). Dry run by default: nothing is written.
//
//   node tool/migrate_loads_mode.js                 -> counts what would change
//   node tool/migrate_loads_mode.js --apply         -> writes it (400 loads per batch)
//   node tool/migrate_loads_mode.js --project <id>  -> project (else GCLOUD_PROJECT / GOOGLE_CLOUD_PROJECT)
//
// A load with no `mode` becomes `scheduled` when it has `scheduledAt`, else `instant`. Loads that already
// have a valid mode are not touched, so running it twice is safe. The app and the rules already treat a
// load without `mode` as `instant`, so this migration is optional: it only makes admin queries tidy.
//
// It uses the Admin SDK with your own Google sign-in (gcloud auth application-default login) or with
// FIRESTORE_EMULATOR_HOST set. No key file is read or written by this script.
const path = require('path');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));

const MODES = ['instant', 'bid', 'scheduled'];

/** What to write for one load document's data, or null when it needs nothing. */
function plan(data) {
  if (!data || MODES.includes(data.mode)) return null;
  return { mode: data.scheduledAt ? 'scheduled' : 'instant' };
}

async function run(argv) {
  const apply = argv.includes('--apply');
  const pi = argv.indexOf('--project');
  const projectId = pi >= 0 ? argv[pi + 1] : process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;
  if (!projectId) {
    console.log('Give the project: --project <id> (or set GCLOUD_PROJECT).');
    return 1;
  }
  admin.initializeApp({ projectId });
  const db = admin.firestore();
  let seen = 0;
  const counts = { instant: 0, scheduled: 0, skipped: 0 };
  let batch = db.batch();
  let inBatch = 0;
  let last = null;
  for (;;) {
    let q = db.collection('loads').orderBy(admin.firestore.FieldPath.documentId()).limit(400);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      seen++;
      const p = plan(doc.data());
      if (!p) {
        counts.skipped++;
        continue;
      }
      counts[p.mode]++;
      if (apply) {
        batch.update(doc.ref, p);
        if (++inBatch >= 400) {
          await batch.commit();
          batch = db.batch();
          inBatch = 0;
        }
      }
    }
    last = snap.docs[snap.docs.length - 1];
  }
  if (apply && inBatch > 0) await batch.commit();
  console.log(`${apply ? 'WRITTEN' : 'DRY RUN (nothing written)'}: ${seen} loads read, ${counts.instant} to instant, ${counts.scheduled} to scheduled, ${counts.skipped} already fine.`);
  if (!apply) console.log('Run again with --apply to write.');
  return 0;
}

if (require.main === module) {
  run(process.argv.slice(2)).then((c) => process.exit(c), (e) => {
    console.error(e.message);
    process.exit(1);
  });
}

module.exports = { plan };
