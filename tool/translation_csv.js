// Shared helpers for the translation tools (Z14): a small CSV reader and writer, and the string-table parser.
'use strict';
const LANGS = ['en', 'hi', 'hinglish', 'kn', 'ta', 'te', 'mr', 'gu', 'bn', 'pa', 'ks', 'ur'];

function parseCsv(text) {
  const t = text.replace(/^\uFEFF/, '');
  const rows = [];
  let row = [];
  let cur = '';
  let q = false;
  for (let i = 0; i < t.length; i++) {
    const c = t[i];
    if (q) {
      if (c === '"') {
        if (t[i + 1] === '"') { cur += '"'; i++; } else q = false;
      } else cur += c;
    } else if (c === '"') q = true;
    else if (c === ',') { row.push(cur); cur = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && t[i + 1] === '\n') i++;
      row.push(cur); cur = '';
      if (row.length > 1 || row[0] !== '') rows.push(row);
      row = [];
    } else cur += c;
  }
  if (cur !== '' || row.length) { row.push(cur); rows.push(row); }
  return rows;
}

function csvCell(v) {
  const s = String(v == null ? '' : v);
  return /[",\n\r]/.test(s) || s === '' ? '"' + s.replace(/"/g, '""') + '"' : s;
}
const toCsv = (rows) => '\uFEFF' + rows.map((r) => r.map(csvCell).join(',')).join('\r\n') + '\r\n';

// Unescapes the inside of a Dart single-quoted string.
function unescapeDart(s) {
  return s.replace(/\\(['\\n$])/g, (m, c) => (c === 'n' ? '\n' : c));
}
// Escapes text for a Dart single-quoted string.
function escapeDart(s) {
  return s.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\n/g, '\\n');
}

// 'key': ['a', 'b', ... 12 items]   (the list form of lib/core/l10n/*_strings.dart)
function parseTable(text) {
  const out = new Map();
  const re = /'([A-Za-z0-9_]+)':\s*\[([\s\S]*?)\],?\s*(?=\n\s*'[A-Za-z0-9_]+':|\n\};)/g;
  let m;
  while ((m = re.exec(text))) {
    const items = [...m[2].matchAll(/'((?:[^'\\]|\\.)*)'/g)].map((x) => unescapeDart(x[1]));
    if (items.length === 12) out.set(m[1], items);
  }
  return out;
}

const placeholders = (s) => [...String(s).matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort().join(',');

module.exports = { LANGS, parseCsv, toCsv, parseTable, placeholders, escapeDart, unescapeDart };
