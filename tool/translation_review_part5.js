// Makes docs/TRANSLATION_REVIEW_PART5.csv: every text added or changed in U30 to U44 (every key of lib/core/l10n/*_strings.dart that is new or different since BASE),
// 12 languages each, with an empty reviewer column and the status 'pending'. Run: node tool/translation_review_part5.js
// BASE is the last commit before U30. Read-only for the app; writes only the CSV.
const { execSync } = require('node:child_process');
const fs = require('node:fs');

const BASE = 'b2aae7f'; // last commit before U30
const LANGS = ['en', 'hi', 'hinglish', 'kn', 'ta', 'te', 'mr', 'gu', 'bn', 'pa', 'ks', 'ur'];

function sh(cmd) {
  return execSync(cmd, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, stdio: ['ignore', 'pipe', 'ignore'] });
}

// 'key': ['a', 'b', ...]  (list form used by every Part 3 and Part 5 (U30 to U44) table)
function parse(text) {
  const out = new Map();
  const re = /'([A-Za-z0-9_]+)':\s*\[([\s\S]*?)\],?\s*(?=\n\s*'[A-Za-z0-9_]+':|\n\};)/g;
  let m;
  while ((m = re.exec(text))) {
    const items = [...m[2].matchAll(/'((?:[^'\\]|\\.)*)'/g)].map((x) => x[1].replace(/\\'/g, "'").replace(/\\\\/g, '\\').replace(/\\n/g, '\n'));
    if (items.length === 12) out.set(m[1], items);
  }
  return out;
}

const files = sh('git ls-files lib/core/l10n').split('\n').filter((f) => f.endsWith('_strings.dart'));
const rows = [];
for (const f of files) {
  const now = parse(fs.readFileSync(f, 'utf8'));
  let before = new Map();
  try {
    before = parse(sh(`git show ${BASE}:${f}`));
  } catch {
    // a file that did not exist then: everything in it is new
  }
  for (const [key, texts] of now) {
    const old = before.get(key);
    if (old && JSON.stringify(old) === JSON.stringify(texts)) continue;
    texts.forEach((t, i) => rows.push([key, f.split('/').pop(), LANGS[i], t]));
  }
}
const q = (s) => '"' + String(s).replace(/"/g, '""').replace(/\r?\n/g, ' ') + '"';
const csv = ['key,language,text,reviewer,status', ...rows.map((r) => [q(r[0]), r[2], q(r[3]), '', 'pending'].join(','))].join(String.fromCharCode(10)) + String.fromCharCode(10);
fs.writeFileSync('docs/TRANSLATION_REVIEW_PART5.csv', '﻿' + csv);
console.log(`${rows.length / 12} texts x 12 languages -> docs/TRANSLATION_REVIEW_PART5.csv`);
