// Makes docs/TRANSLATION_REVIEW_PART4.csv: every text added in Part 4 (new *_strings.dart files and the new feat_ and featHelp_
// keys), 12 languages each, with empty columns for the native reader. Run: node tool/translation_review_part4.js
// It compares with the commit before Part 4 (BASE). Read-only for the app; writes only the CSV.
const { execSync } = require('node:child_process');
const fs = require('node:fs');

const BASE = 'ec29376'; // last commit before Part 4 (U1)
const LANGS = ['en', 'hi', 'hinglish', 'kn', 'ta', 'te', 'mr', 'gu', 'bn', 'pa', 'ks', 'ur'];

function sh(cmd) {
  return execSync(cmd, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, stdio: ['ignore', 'pipe', 'ignore'] });
}

// 'key': ['a', 'b', ...]  (list form used by every Part 3 and Part 4 table)
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
const csv = ['key,file,language,text,reviewer_ok,reviewer_fix,reviewer_name', ...rows.map((r) => [q(r[0]), q(r[1]), r[2], q(r[3]), '', '', ''].join(','))].join('\n') + '\n';
fs.writeFileSync('docs/TRANSLATION_REVIEW_PART4.csv', '﻿' + csv);
console.log(`${rows.length / 12} texts x 12 languages -> docs/TRANSLATION_REVIEW_PART4.csv`);
