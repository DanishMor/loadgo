// E15: writes docs/VEHICLE_REVIEW.csv from assets/vehicles/catalog.json (and the English and Hindi names from
// lib/core/l10n/vehicle_catalog_strings.dart) so the owner can correct the approximate numbers.
//   node tool/vehicle_review_csv.js            -> prints the CSV
//   node tool/vehicle_review_csv.js --write    -> writes docs/VEHICLE_REVIEW.csv
// After the owner fills "correct_*" columns, copy the numbers into catalog.json by hand and run the catalog test.
'use strict';
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');
const catalog = JSON.parse(fs.readFileSync(path.join(root, 'assets/vehicles/catalog.json'), 'utf8'));
const strings = fs.readFileSync(path.join(root, 'lib/core/l10n/vehicle_catalog_strings.dart'), 'utf8');

function names(id) {
  const m = strings.match(new RegExp(`'vc_${id}': \\['((?:[^'\\\\]|\\\\.)*)', '((?:[^'\\\\]|\\\\.)*)'`));
  return m ? [m[1].replace(/\\'/g, "'"), m[2]] : ['', ''];
}
const cell = v => {
  const s = String(v);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};
const head = ['id', 'name_en', 'name_hi', 'group', 'legacy_id', 'wheels', 'axles', 'length_ft', 'width_ft', 'height_ft', 'min_tons', 'max_tons', 'goods', 'bodies', 'price_band', 'approximate', 'correct_length_ft', 'correct_width_ft', 'correct_height_ft', 'correct_min_tons', 'correct_max_tons', 'owner_note'];
const rows = [head.join(',')];
for (const v of catalog.vehicles) {
  const [en, hi] = names(v.id);
  rows.push([v.id, en, hi, v.group, v.legacyId || '', v.axles.reduce((a, b) => a + b, 0), v.axles.join('+'), v.lengthFt, v.widthFt, v.heightFt, v.minTons, v.maxTons, v.goods.join(' '), v.bodies.join(' '), v.priceBand, 'yes', '', '', '', '', '', ''].map(cell).join(','));
}
const csv = rows.join('\n') + '\n';
if (process.argv.includes('--write')) {
  fs.writeFileSync(path.join(root, 'docs/VEHICLE_REVIEW.csv'), '﻿' + csv);
  console.log(`wrote docs/VEHICLE_REVIEW.csv (${catalog.vehicles.length} vehicles)`);
} else {
  process.stdout.write(csv);
}
