(function () {
  try {
    var e =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    e.SENTRY_RELEASE = { id: "4.3.209" };
    var r = new e.Error().stack;
    r &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[r] = "26d0c124-afa9-4384-92c5-197dd446eb7c"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-26d0c124-afa9-4384-92c5-197dd446eb7c"));
  } catch {}
})();
var f, i;
function o() {
  if (i) return f;
  ((i = 1), (f = r));
  var e = Object.prototype.hasOwnProperty;
  function r() {
    for (var t = {}, n = 0; n < arguments.length; n++) {
      var a = arguments[n];
      for (var d in a) e.call(a, d) && (t[d] = a[d]);
    }
    return t;
  }
  return f;
}
export { o as r };
//# sourceMappingURL=immutable-XCMBOkhu.mjs.map
