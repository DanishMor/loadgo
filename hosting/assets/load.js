(function () {
  var m = location.pathname.match(/^\/load\/([^\/]+)/);
  if (m) document.getElementById('code').textContent = decodeURIComponent(m[1]);
})();
