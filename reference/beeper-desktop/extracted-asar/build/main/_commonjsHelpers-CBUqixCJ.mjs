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
    var t = new e.Error().stack;
    t &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[t] = "bc8ac399-16f0-411b-9828-c3fdde82e46d"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-bc8ac399-16f0-411b-9828-c3fdde82e46d"));
  } catch {}
})();
var f =
  typeof globalThis < "u"
    ? globalThis
    : typeof window < "u"
      ? window
      : typeof global < "u"
        ? global
        : typeof self < "u"
          ? self
          : {};
function d(e) {
  return e && e.__esModule && Object.prototype.hasOwnProperty.call(e, "default")
    ? e.default
    : e;
}
function s(e) {
  if (Object.prototype.hasOwnProperty.call(e, "__esModule")) return e;
  var t = e.default;
  if (typeof t == "function") {
    var r = function n() {
      var o = !1;
      try {
        o = this instanceof n;
      } catch {}
      return o
        ? Reflect.construct(t, arguments, this.constructor)
        : t.apply(this, arguments);
    };
    r.prototype = t.prototype;
  } else r = {};
  return (
    Object.defineProperty(r, "__esModule", { value: !0 }),
    Object.keys(e).forEach(function (n) {
      var o = Object.getOwnPropertyDescriptor(e, n);
      Object.defineProperty(
        r,
        n,
        o.get
          ? o
          : {
              enumerable: !0,
              get: function () {
                return e[n];
              },
            },
      );
    }),
    r
  );
}
export { d as a, f as c, s as g };
//# sourceMappingURL=_commonjsHelpers-CBUqixCJ.mjs.map
