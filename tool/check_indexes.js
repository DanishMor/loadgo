// Z4: finds the Firestore queries in lib/ that need a composite index and compares them with
// firestore.indexes.json. Read-only. Run: node tool/check_indexes.js [--write-doc] [--json]
// Exit code 1 when an index is missing. Limits are listed in docs/INDEX_CHECK.md.
'use strict';
const fs = require('fs');
const path = require('path');

const rootArg = process.argv.indexOf('--root');
const root = rootArg > 0 ? path.resolve(process.argv[rootArg + 1]) : path.resolve(__dirname, '..');
const EQ = new Set(['isEqualTo', 'isNull']);
const IN = new Set(['whereIn']);
const ARR = new Set(['arrayContains', 'arrayContainsAny']);
const RANGE = new Set(['isLessThan', 'isLessThanOrEqualTo', 'isGreaterThan', 'isGreaterThanOrEqualTo', 'isNotEqualTo', 'whereNotIn']);

function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.dart')) out.push(p);
  }
  return out;
}

// Returns the index of the ')' that closes the '(' at position i (strings are skipped).
function closeParen(s, i) {
  let depth = 0;
  for (let k = i; k < s.length; k++) {
    const c = s[k];
    if (c === "'" || c === '"') {
      const q = c;
      k++;
      while (k < s.length && s[k] !== q) { if (s[k] === '\\') k++; k++; }
      continue;
    }
    if (c === '(') depth++;
    else if (c === ')') { depth--; if (depth === 0) return k; }
  }
  return -1;
}

function parseChain(s, start, base) {
  const q = { base, eq: [], arr: [], range: [], order: [], seen: [] };
  let i = start;
  for (;;) {
    const m = /^\s*\.\s*(\w+)\s*\(/.exec(s.slice(i, i + 200));
    if (!m) break;
    const open = i + m[0].length - 1;
    const close = closeParen(s, open);
    if (close < 0) break;
    const args = s.slice(open + 1, close);
    const name = m[1];
    q.seen.push(open - m[0].length + 1 + m[0].indexOf(name));
    if (name === 'where') {
      const f = /^\s*'([^']+)'/.exec(args);
      if (f) {
        const field = f[1];
        const named = (args.match(/\b(isEqualTo|isNull|whereIn|arrayContainsAny|arrayContains|isNotEqualTo|isLessThanOrEqualTo|isLessThan|isGreaterThanOrEqualTo|isGreaterThan|whereNotIn)\s*:/) || [])[1];
        if (EQ.has(named) || IN.has(named)) q.eq.push(field);
        else if (ARR.has(named)) q.arr.push(field);
        else if (RANGE.has(named)) q.range.push(field);
      }
    } else if (name === 'orderBy') {
      const f = /^\s*'([^']+)'/.exec(args);
      if (f) q.order.push({ field: f[1], dir: /descending\s*:\s*true/.test(args) ? 'DESCENDING' : 'ASCENDING' });
    }
    i = close + 1;
  }
  return q;
}

function requirement(q) {
  const eqSet = [...new Set([...q.eq, ...q.arr])];
  const tail = [];
  for (const o of q.order) if (!eqSet.includes(o.field) && !tail.some((t) => t.field === o.field)) tail.push(o);
  for (const r of q.range) if (!eqSet.includes(r) && !tail.some((t) => t.field === r)) tail.unshift({ field: r, dir: 'ASCENDING' });
  if (eqSet.length === 0 && tail.length <= 1) return null; // single-field index is automatic
  if (tail.length === 0) return null; // equality only: merged from single-field indexes
  return { eq: eqSet, arr: new Set(q.arr), tail };
}

function served(idx, group, scope, req) {
  if (idx.collectionGroup !== group || idx.queryScope !== scope) return false;
  const f = idx.fields.filter((x) => x.fieldPath !== '__name__');
  if (f.length !== req.eq.length + req.tail.length) return false;
  const head = f.slice(0, req.eq.length).map((x) => x.fieldPath).sort().join(',');
  if (head !== [...req.eq].sort().join(',')) return false;
  const rest = f.slice(req.eq.length);
  const same = rest.every((x, k) => x.fieldPath === req.tail[k].field && (x.order || 'ASCENDING') === req.tail[k].dir);
  const flip = (d) => (d === 'ASCENDING' ? 'DESCENDING' : 'ASCENDING');
  const reversed = rest.every((x, k) => x.fieldPath === req.tail[k].field && (x.order || 'ASCENDING') === flip(req.tail[k].dir));
  return same || reversed;
}

function scanFile(file, text) {
  // Getters such as `static CollectionReference<...> get _lrs => _db.collection('lrs');`
  const aliases = {};
  const aliasRe = /get\s+(\w+)\s*=>[^;]*?\bcollection\(\s*'([^']+)'\s*\)\s*;/g;
  let a;
  while ((a = aliasRe.exec(text))) aliases[a[1]] = a[2];
  const found = [];
  // Helpers such as `_col(String n) => _db.collection(n)` count as a collection start too.
  const helpers = ['collection'];
  const helperRe = /(\w+)\(\s*(?:final\s+)?String\s+\w+\s*\)\s*(?:=>|\{\s*return)\s*[^;]*?\bcollection\(\s*\w+\s*\)/g;
  let h;
  while ((h = helperRe.exec(text))) helpers.push(h[1]);
  const startRe = new RegExp('\\b(collectionGroup|' + helpers.join('|') + ")\\(\\s*'([^']+)'\\s*\\)", 'g');
  let m;
  while ((m = startRe.exec(text))) {
    const q = parseChain(text, m.index + m[0].length, { name: m[2], group: m[1] === 'collectionGroup' });
    found.push({ file, line: text.slice(0, m.index).split('\n').length, q });
  }
  for (const [alias, coll] of Object.entries(aliases)) {
    const re = new RegExp('\\b' + alias + '\\b(?=\\s*\\.\\s*(?:where|orderBy))', 'g');
    while ((m = re.exec(text))) {
      const q = parseChain(text, m.index + m[0].length, { name: coll, group: false });
      found.push({ file, line: text.slice(0, m.index).split('\n').length, q });
    }
  }
  const seen = new Set();
  for (const x of found) for (const p of x.q.seen) seen.add(p);
  const unresolved = [];
  const loose = /\.\s*(where|orderBy)\(\s*'/g;
  while ((m = loose.exec(text))) {
    const pos = m.index + m[0].indexOf(m[1]);
    if (!seen.has(pos)) unresolved.push(`${file}:${text.slice(0, m.index).split('\n').length}`);
  }
  found.unresolved = unresolved;
  return found;
}

function main() {
  const idxFile = path.join(root, 'firestore.indexes.json');
  const indexes = JSON.parse(fs.readFileSync(idxFile, 'utf8')).indexes;
  const queries = [];
  const unresolved = [];
  for (const f of walk(path.join(root, 'lib'), [])) {
    const t = fs.readFileSync(f, 'utf8');
    if (!/\.(where|orderBy)\(/.test(t)) continue;
    const r = scanFile(path.relative(root, f).replace(/\\/g, '/'), t);
    queries.push(...r);
    unresolved.push(...r.unresolved);
  }
  const needed = new Map();
  for (const x of queries) {
    const req = requirement(x.q);
    if (!req) continue;
    const scope = x.q.base.group ? 'COLLECTION_GROUP' : 'COLLECTION';
    const key = JSON.stringify([x.q.base.name, scope, req.eq.sort(), req.tail]);
    if (!needed.has(key)) needed.set(key, { group: x.q.base.name, scope, req, where: [] });
    needed.get(key).where.push(`${x.file}:${x.line}`);
  }
  const missing = [];
  const covered = [];
  for (const n of needed.values()) {
    (indexes.some((i) => served(i, n.group, n.scope, n.req)) ? covered : missing).push(n);
  }
  const toIndex = (n) => ({
    collectionGroup: n.group,
    queryScope: n.scope,
    fields: [
      ...n.req.eq.map((f) => (n.req.arr.has(f) ? { fieldPath: f, arrayConfig: 'CONTAINS' } : { fieldPath: f, order: 'ASCENDING' })),
      ...n.req.tail.map((t) => ({ fieldPath: t.field, order: t.dir })),
    ],
  });
  const result = { unresolved, queriesSeen: queries.length, compositeNeeded: needed.size, covered: covered.length, missing: missing.map((n) => ({ index: toIndex(n), where: n.where })) };
  if (process.argv.includes('--json')) console.log(JSON.stringify(result, null, 2));
  else {
    console.log(`queries seen: ${result.queriesSeen}, composite needed: ${result.compositeNeeded}, covered: ${result.covered}, missing: ${missing.length}`);
    console.log(`unresolved (query built step by step, check by hand): ${unresolved.length}`);
    if (process.argv.includes('--verbose')) for (const u of unresolved) console.log('  ' + u);
    for (const n of missing) console.log(`MISSING ${JSON.stringify(toIndex(n))}\n  at ${n.where.join(', ')}`);
  }
  if (process.argv.includes('--add')) {
    const j = JSON.parse(fs.readFileSync(idxFile, 'utf8'));
    for (const n of missing) j.indexes.push(toIndex(n));
    fs.writeFileSync(idxFile, JSON.stringify(j, null, 2) + '\n');
    console.log(`added ${missing.length} index(es) to firestore.indexes.json`);
    return 0;
  }
  return missing.length ? 1 : 0;
}

process.exitCode = main();
