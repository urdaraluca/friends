// Removes the HTML splash once Flutter has drawn its first frame. A file rather than an
// inline script: the Content-Security-Policy allows no inline scripts.
window.addEventListener("flutter-first-frame", function () {
  var splash = document.getElementById("splash");
  if (splash) splash.remove();
});
