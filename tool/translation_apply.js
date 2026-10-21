// Z14: applies reviewer fixes from docs/translation/<lang>.csv (column "fix") to lib/core/l10n/*_strings.dart.
// DRY RUN by default: prints what would change and writes nothing. Add --apply to write.
// Stops (writes nothing) on the first problem: unknown key, placeholders that differ from the current text, an empty or too long fix.
// Run: node tool/translation_apply.js [--lang hi|all] [--apply] [--root <dir>]
'use strict';
const fs = require('fs');
const path = require('path');
const { LANGS, parseCsv, parseTable, placeholders, escapeDart } = require('./translation_csv');

const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };
const apply = args.includes('--apply');
const root = path.resolve(opt('--root', path.resolve(__dirname, '..')));
const langOpt = opt('--lang', 'all');
const langs = langOpt === 'all' ? LANGS : [langOpt];
if (langs.some((l) => !LANGS.includes(l))) { console.error(`unknown language: ${langOpt}`); process.exit(2); }

const l10n = path.join(root, 'lib/core/l10n');
const files = fs.readdirSync(l10n).filter((f) => f.endsWith('_strings.dart')).map((f) => path.join(l10n, f));
const texts = new Map(files.map((f) => [f, fs.readFileSync(f, 'utf8')]));
const where = new Map(); // key -> file
for (const [f, t] of texts) for (const k of parseTable(t).keys()) if (!where.has(k)) where.set(k, f);

const problems = [];
const changes = [];
for (const lang of langs) {
  const csv = path.join(root, 'docs/translation', `${lang}.csv`);
  if (!fs.existsSync(csv)) continue;
  const rows = parseCsv(fs.readFileSync(csv, 'utf8'));
  const head = rows[0];
  const ik = head.indexOf('key');
  const it = head.indexOf('text');
  const ifx = head.indexOf('fix');
  const ien = head.indexOf('english');
  for (const r of rows.slice(1)) {
    const fix = (r[ifx] || '').trim();
    if (!fix) continue;
    const key = r[ik];
    const file = where.get(key);
    if (!file) { problems.push(`${lang}/${key}: key not found in lib/core/l10n (list-form tables only)`); continue; }
    const items = parseTable(texts.get(file)).get(key);
    const idx = LANGS.indexOf(lang);
    const current = items[idx];
    if (placeholders(fix) !== placeholders(current)) {
      problems.push(`${lang}/${key}: placeholders differ (now {${placeholders(current)}}, fix {${placeholders(fix)}})`);
      continue;
    }
    if (ien >= 0 && placeholders(fix) !== placeholders(r[ien] || '')) {
      problems.push(`${lang}/${key}: placeholders do not match the English text`);
      continue;
    }
    if (fix.length > 600) { problems.push(`${lang}/${key}: fix is longer than 600 characters`); continue; }
    if (fix === current) continue;
    changes.push({ lang, key, file, idx, from: current, to: fix, csvText: r[it] });
  }
}

if (problems.length) {
  console.error('STOPPED. Nothing was written. Fix these first:\n- ' + problems.join('\n- '));
  process.exit(1);
}

for (const c of changes) console.log(`${apply ? 'apply' : 'would change'} ${c.lang}/${c.key}: ${JSON.stringify(c.from)} -> ${JSON.stringify(c.to)}`);

if (apply) {
  for (const c of changes) {
    let t = texts.get(c.file);
    const start = new RegExp("'" + c.key + "':\\s*\\[").exec(t);
    let pos = start.index + start[0].length;
    let seen = -1;
    const lit = /'((?:[^'\\]|\\.)*)'/g;
    lit.lastIndex = pos;
    let m;
    while ((m = lit.exec(t))) {
      seen++;
      if (seen === c.idx) {
        t = t.slice(0, m.index) + "'" + escapeDart(c.to) + "'" + t.slice(m.index + m[0].length);
        break;
      }
    }
    texts.set(c.file, t);
  }
  for (const [f, t] of texts) fs.writeFileSync(f, t);
}
console.log(`${changes.length} change(s)${apply ? ' written' : ' (dry run, use --apply to write)'}`);
