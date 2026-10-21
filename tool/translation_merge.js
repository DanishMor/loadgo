// Z14: merges docs/TRANSLATION_REVIEW_PART3/4/5.csv into docs/TRANSLATION_REVIEW_ALL.csv (one row per key and language, a later part wins)
// and splits it into docs/translation/<lang>.csv (key, english, text, fix, status) for one reviewer per language.
// Run: node tool/translation_merge.js        Read-only for the app; writes only docs/.
'use strict';
const fs = require('fs');
const path = require('path');
const { LANGS, parseCsv, toCsv } = require('./translation_csv');

const root = path.resolve(__dirname, '..');
const docs = path.join(root, 'docs');
const merged = new Map(); // "key|lang" -> {key, lang, text, reviewer, status, part}
let order = [];

for (const part of [3, 4, 5]) {
  const rows = parseCsv(fs.readFileSync(path.join(docs, `TRANSLATION_REVIEW_PART${part}.csv`), 'utf8'));
  const head = rows[0];
  const col = (n) => head.indexOf(n);
  for (const r of rows.slice(1)) {
    const key = r[col('key')];
    const lang = r[col('language')];
    if (!key || !LANGS.includes(lang)) continue;
    const id = `${key}|${lang}`;
    const reviewer = col('reviewer') >= 0 ? r[col('reviewer')] : r[col('reviewer_name')] || '';
    const status = col('status') >= 0 ? r[col('status')] : r[col('reviewer_ok')] ? 'ok' : 'pending';
    if (!merged.has(id)) order.push(id);
    merged.set(id, { key, lang, text: r[col('text')], reviewer: reviewer || '', status: status || 'pending', part });
  }
}

const out = [['key', 'language', 'text', 'reviewer', 'status']];
for (const id of order) {
  const m = merged.get(id);
  out.push([m.key, m.lang, m.text, m.reviewer, m.status]);
}
fs.writeFileSync(path.join(docs, 'TRANSLATION_REVIEW_ALL.csv'), toCsv(out));

fs.mkdirSync(path.join(docs, 'translation'), { recursive: true });
const english = new Map();
for (const id of order) { const m = merged.get(id); if (m.lang === 'en') english.set(m.key, m.text); }
for (const lang of LANGS) {
  const rows = [['key', 'english', 'text', 'fix', 'status']];
  for (const id of order) {
    const m = merged.get(id);
    if (m.lang === lang) rows.push([m.key, english.get(m.key) || '', m.text, '', m.status]);
  }
  fs.writeFileSync(path.join(docs, 'translation', `${lang}.csv`), toCsv(rows));
}
const keys = new Set(order.map((i) => merged.get(i).key));
console.log(`merged ${order.length} rows, ${keys.size} keys, ${LANGS.length} language files`);
