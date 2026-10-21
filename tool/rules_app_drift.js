// Z5: compares the fields the app writes to each Firestore collection (map keys of set / add / update) with the field lists in
// firestore.rules (hasOnly([...]) of that collection's match block). Read-only.
// Run: node tool/rules_app_drift.js [--write] [--verbose]    (--write rewrites docs/RULES_APP_DRIFT.md)
// Limits are written into the generated document.
'use strict';
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');

function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.dart')) out.push(p);
  }
  return out;
}

// ---- rules: collection -> every quoted field name inside a hasOnly([...]) / hasAll / keys().hasOnly of its match block
function rulesFields() {
  const text = fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8').replace(/\r/g, '');
  const res = {};
  const re = /match\s+\/(\w+)\/\{[^}]*\}\s*\{/g;
  let m;
  const starts = [];
  while ((m = re.exec(text))) starts.push({ name: m[1], at: m.index, open: m.index + m[0].length - 1 });
  for (const s of starts) {
    let depth = 0;
    let end = s.open;
    for (let k = s.open; k < text.length; k++) {
      if (text[k] === '{') depth++;
      else if (text[k] === '}') { depth--; if (depth === 0) { end = k; break; } }
    }
    const block = text.slice(s.open, end);
    const fields = new Set();
    for (const h of block.matchAll(/hasOnly\(\[([^\]]*)\]\)/g)) for (const q of h[1].matchAll(/'(\w+)'/g)) fields.add(q[1]);
    // fields named elsewhere in the block (shape checks such as `'route' in l`, `d.field`) count as known too
    for (const q of block.matchAll(/'(\w+)'\s+in\s+\w+/g)) fields.add(q[1]);
    for (const q of block.matchAll(/\b(?:data|d|l|b|resource\.data|request\.resource\.data)\.(\w+)/g)) fields.add(q[1]);
    const key = s.name;
    res[key] = res[key] || { fields: new Set(), hasList: false };
    for (const f of fields) res[key].fields.add(f);
    if (/hasOnly\(\[/.test(block)) res[key].hasList = true;
  }
  return res;
}

// ---- app: collection -> keys written
function topLevelKeys(src, openIdx) {
  // src[openIdx] === '{'
  const keys = [];
  let depth = 0;
  let dynamic = 0;
  let i = openIdx;
  for (; i < src.length; i++) {
    const c = src[i];
    if (c === "'" || c === '"') {
      const q = c;
      const start = i + 1;
      i++;
      while (i < src.length && src[i] !== q) { if (src[i] === '\\') i++; i++; }
      const lit = src.slice(start, i);
      if (depth === 1 && /^\s*:/.test(src.slice(i + 1, i + 6)) && /^\w+$/.test(lit)) keys.push(lit);
      continue;
    }
    if (c === '{' || c === '[' || c === '(') depth++;
    else if (c === '}' || c === ']' || c === ')') { depth--; if (depth === 0) break; }
    else if (depth === 1 && c === '$') dynamic++;
  }
  return { keys, dynamic };
}

function collectionBefore(text, idx, aliases) {
  const win = text.slice(Math.max(0, idx - 500), idx);
  let best = null;
  let bestAt = -1;
  for (const m of win.matchAll(/\b(?:collection|_col|_c)\(\s*'(\w+)'\s*\)/g)) {
    if (m.index > bestAt) { best = m[1]; bestAt = m.index; }
  }
  for (const [alias, coll] of Object.entries(aliases)) {
    const re = new RegExp('\\b' + alias + '\\b', 'g');
    for (const m of win.matchAll(re)) if (m.index > bestAt) { best = coll; bestAt = m.index; }
  }
  // a nested .doc(x).collection('messages') wins over its parent because it is later in the text
  return best;
}

function appWrites() {
  const writes = {};
  let unresolved = 0;
  let total = 0;
  for (const f of walk(path.join(root, 'lib'), [])) {
    const text = fs.readFileSync(f, 'utf8');
    if (!/\.(set|update|add)\(/.test(text)) continue;
    const aliases = {};
    for (const a of text.matchAll(/get\s+(\w+)\s*=>[^;]*?\bcollection\(\s*'(\w+)'\s*\)\s*;/g)) aliases[a[1]] = a[2];
    for (const m of text.matchAll(/\.(set|update|add)\(\s*(?:[\w.()'$\[\]]+\s*,\s*)?(?:<[^>{]*>)?\{/g)) {
      const open = m.index + m[0].length - 1;
      const { keys, dynamic } = topLevelKeys(text, open);
      if (keys.length === 0) continue;
      total++;
      const coll = collectionBefore(text, m.index, aliases);
      if (!coll) { unresolved++; continue; }
      const rel = path.relative(root, f).replace(/\\/g, '/');
      const line = text.slice(0, m.index).split('\n').length;
      const w = (writes[coll] = writes[coll] || { keys: new Map(), dynamic: 0 });
      w.dynamic += dynamic;
      for (const k of keys) if (!w.keys.has(k)) w.keys.set(k, `${rel}:${line}`);
    }
  }
  return { writes, unresolved, total };
}

// Always allowed by the rules machinery or written through FieldValue helpers of the function-owned documents.
const SKIP = new Set(['createdAt', 'updatedAt']);

function main() {
  const rules = rulesFields();
  // Field checks often live in helper functions (validBooking, lrPublicShape ...) outside the collection's block, so a field counts as
  // known when its name appears anywhere in firestore.rules. The report lists only names the rules never mention.
  const allWords = new Set((fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8').match(/\w+/g) || []));
  const { writes, unresolved, total } = appWrites();
  const drift = [];
  let checked = 0;
  for (const [coll, w] of Object.entries(writes)) {
    const r = rules[coll];
    if (!r) continue; // subcollections and collections without a top-level match are listed below
    if (!r.hasList) continue;
    checked++;
    const missing = [...w.keys.entries()].filter(([k]) => !r.fields.has(k) && !allWords.has(k) && !SKIP.has(k));
    if (missing.length) drift.push({ coll, missing });
  }
  const noRule = Object.keys(writes).filter((c) => !rules[c]).sort();
  let md = '# Rules vs app field drift (Z5)\n\nGenerated by `node tool/rules_app_drift.js --write`.\n\n';
  md += `App writes scanned: ${total} map literals (set / add / update), ${unresolved} with an unknown collection (skipped). Collections compared: ${checked}.\n\n`;
  md += '## Possible drift (the app writes a field name that firestore.rules never mentions)\n\n';
  if (!drift.length) md += 'None found.\n\n';
  for (const d of drift.sort((a, b) => a.coll.localeCompare(b.coll))) {
    md += `### ${d.coll}\n` + d.missing.map(([k, where]) => `- \`${k}\` (${where})`).join('\n') + '\n\n';
  }
  md += '## Collections written by the app with no top-level rule block of that name\n\n' + (noRule.join(', ') || 'none') + '\n\n(They are subcollections or covered by a different match name; see the limits.)\n\n';
  md += '## Limits\n' +
    '- Only map literals with quoted keys are read. Keys built at run time (`{\'a_$x\': 1}`, spread `...map`, `toMap()` helpers) are invisible; dynamic keys seen in literals are counted but not named.\n' +
    '- The collection is guessed from the nearest `collection(\'x\')` (or a getter / helper for it) before the write. Nested documents and batch writes through a stored reference can be attributed wrongly or skipped.\n' +
    '- A field counts as known when its name appears anywhere in `firestore.rules` (checks often sit in helper functions outside the collection block). A name the rules mention only for another collection is therefore not reported: that is a miss of this tool, and a stricter per-collection check gave mostly false alarms. Fields written only by functions (admin SDK) are not rule-checked at all.' +
    '- A report line is a lead, not proof. The real proof is `docs/RULES_CONTRACT.md` (the app\'s own writes replayed against the rules) and `sh run-tests.sh`.\n' +
    '- Rules are never edited by this tool. A needed rules change goes to `docs/RULES_CHANGES_NEEDED.md` for the owner.\n';
  if (process.argv.includes('--write')) {
    fs.writeFileSync(path.join(root, 'docs/RULES_APP_DRIFT.md'), md);
    console.log(`wrote docs/RULES_APP_DRIFT.md: ${drift.length} collection(s) with possible drift`);
  } else console.log(md);
}

main();
