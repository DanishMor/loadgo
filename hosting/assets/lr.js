(function () {
  var out = document.getElementById('out');
  var m = location.pathname.match(/^\/lr\/([0-9a-f]{32})\/?$/);
  function show(html) { out.innerHTML = html; }
  function esc(s) { var d = document.createElement('div'); d.textContent = String(s); return d.innerHTML; }
  if (!m) { show('<p>This link is not valid.</p>'); return; }
  var base = 'https://firestore.googleapis.com/v1/projects/loadgo-defc2/databases/(default)/documents';
  var labels = {lrNo: 'LR number', date: 'Date', route: 'Route', goods: 'Goods', packages: 'Packages', weightTons: 'Weight (tons)', vehicleNumber: 'Vehicle', driverName: 'Driver', consignorName: 'Consignor', consigneeName: 'Consignee', issuerName: 'Issued by', status: 'Status', version: 'Version',
    freightPaise: 'Freight', advancePaise: 'Advance', balancePaise: 'Balance', gstPaise: 'GST', goodsValuePaise: 'Goods value', invoiceNo: 'Invoice no.', consignorGstin: 'Consignor GSTIN', consigneeGstin: 'Consignee GSTIN', ewayBillNo: 'E-way bill no.', ewayValidUntil: 'E-way valid until'};
  var order = ['lrNo', 'version', 'date', 'consignorName', 'consigneeName', 'route', 'goods', 'packages', 'weightTons', 'vehicleNumber', 'driverName', 'freightPaise', 'advancePaise', 'balancePaise', 'gstPaise', 'goodsValuePaise', 'invoiceNo', 'consignorGstin', 'consigneeGstin', 'ewayBillNo', 'ewayValidUntil', 'issuerName', 'status'];
  var statusText = {issued: 'Valid', superseded: 'Replaced by a newer version', cancelled: 'CANCELLED'};
  function val(v) { if (!v) return ''; if (v.stringValue !== undefined) return v.stringValue; if (v.integerValue !== undefined) return v.integerValue; if (v.doubleValue !== undefined) return v.doubleValue; return ''; }
  function money(p) { var n = Number(p) / 100; return '₹ ' + n.toLocaleString('en-IN', {maximumFractionDigits: 2}); }
  fetch(base + '/lr_shares/' + m[1]).then(function (r) {
    if (!r.ok) throw new Error('gone');
    return r.json();
  }).then(function (doc) {
    var f = doc.fields || {};
    var snap = (f.fields && f.fields.mapValue && f.fields.mapValue.fields) || {};
    var live = f.status && f.status.stringValue;
    var h = '<table>';
    order.forEach(function (k) {
      if (!snap[k]) return;
      var v = val(snap[k]);
      if (v === '' || v === undefined) return;
      if (/Paise$/.test(k)) v = money(v);
      if (k === 'status') v = statusText[live || v] || (live || v);
      h += '<tr><td>' + esc(labels[k]) + '</td><td' + (k === 'status' && (live || v) === 'cancelled' ? ' class="bad"' : '') + '>' + esc(v) + '</td></tr>';
    });
    h += '</table>';
    show(h);
    // Count this view (rules allow only +1 on a live link).
    fetch(base + ':commit', {method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({writes: [{transform: {document: 'projects/loadgo-defc2/databases/(default)/documents/lr_shares/' + m[1], fieldTransforms: [{fieldPath: 'views', increment: {integerValue: '1'}}]}}]})}).catch(function () {});
  }).catch(function () {
    show('<p>This link has ended or is not valid. Ask the sender for a new one.</p>');
  });
})();
