(function () {
  try {
    var r =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    r.SENTRY_RELEASE = { id: "4.3.209" };
    var f = new r.Error().stack;
    f &&
      ((r._sentryDebugIds = r._sentryDebugIds || {}),
      (r._sentryDebugIds[f] = "63594d01-881a-408e-a7f4-39e940c6e06b"),
      (r._sentryDebugIdIdentifier =
        "sentry-dbid-63594d01-881a-408e-a7f4-39e940c6e06b"));
  } catch {}
})();
var u, l;
function p() {
  if (l) return u;
  l = 1;
  var r = Object.getOwnPropertySymbols,
    f = Object.prototype.hasOwnProperty,
    b = Object.prototype.propertyIsEnumerable;
  function d(t) {
    if (t == null)
      throw new TypeError(
        "Object.assign cannot be called with null or undefined",
      );
    return Object(t);
  }
  function g() {
    try {
      if (!Object.assign) return !1;
      var t = new String("abc");
      if (((t[5] = "de"), Object.getOwnPropertyNames(t)[0] === "5")) return !1;
      for (var i = {}, e = 0; e < 10; e++) i["_" + String.fromCharCode(e)] = e;
      var o = Object.getOwnPropertyNames(i).map(function (n) {
        return i[n];
      });
      if (o.join("") !== "0123456789") return !1;
      var a = {};
      return (
        "abcdefghijklmnopqrst".split("").forEach(function (n) {
          a[n] = n;
        }),
        Object.keys(Object.assign({}, a)).join("") === "abcdefghijklmnopqrst"
      );
    } catch {
      return !1;
    }
  }
  return (
    (u = g()
      ? Object.assign
      : function (t, i) {
          for (var e, o = d(t), a, n = 1; n < arguments.length; n++) {
            e = Object(arguments[n]);
            for (var c in e) f.call(e, c) && (o[c] = e[c]);
            if (r) {
              a = r(e);
              for (var s = 0; s < a.length; s++)
                b.call(e, a[s]) && (o[a[s]] = e[a[s]]);
            }
          }
          return o;
        }),
    u
  );
}
export { p as r };
//# sourceMappingURL=index-CvW2ssNt.mjs.map
