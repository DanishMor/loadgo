(function () {
  var out = document.getElementById('out');
  var m = location.pathname.match(/^\/trip\/([a-z2-9]{24})\/?$/);
  function show(html) { out.innerHTML = html; }
  function esc(s) { var d = document.createElement('div'); d.textContent = s; return d.innerHTML; }
  if (!m) { show('<p>This link is not valid.</p>'); return; }
  var labels = {accepted: 'Driver assigned', driver_arriving: 'Driver is on the way to pickup', loading: 'Loading', picked_up: 'Goods picked up', in_transit: 'On the road', unloading: 'Unloading', delivered: 'Delivered', cancelled: 'Cancelled'};
  var url = 'https://firestore.googleapis.com/v1/projects/loadgo-defc2/databases/(default)/documents/trip_shares/' + m[1];
  fetch(url).then(function (r) {
    if (!r.ok) throw new Error('gone');
    return r.json();
  }).then(function (doc) {
    var f = doc.fields || {};
    function s(k) { return f[k] && f[k].stringValue ? f[k].stringValue : ''; }
    function t(k) { return f[k] && f[k].timestampValue ? new Date(f[k].timestampValue) : null; }
    var st = s('status');
    var at = t('statusAt'), ends = t('expiresAt');
    var h = '<p class="big">' + esc(s('pickup')) + ' &rarr; ' + esc(s('drop')) + '</p>' +
      '<p class="big">' + esc(labels[st] || st.replace(/_/g, ' ')) + '</p>';
    if (s('vehicleNumber')) h += '<p>Vehicle: ' + esc(s('vehicleNumber')) + '</p>';
    if (s('driverName')) h += '<p>Driver: ' + esc(s('driverName')) + '</p>';
    if (at) h += '<p class="muted">Status updated ' + esc(at.toLocaleString()) + '</p>';
    if (ends) h += '<p class="muted">Link valid until ' + esc(ends.toLocaleString()) + '</p>';
    show(h);
  }).catch(function () {
    show('<p>This link has ended or is not valid. Ask the sender for a new one.</p>');
  });
})();
