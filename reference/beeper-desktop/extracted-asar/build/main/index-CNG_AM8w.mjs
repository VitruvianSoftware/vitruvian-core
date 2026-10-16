import { a as c } from "./_commonjsHelpers-CBUqixCJ.mjs";
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
      (e._sentryDebugIds[t] = "4979ec79-4ace-4e1e-bb4c-f78f9746d6c5"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-4979ec79-4ace-4e1e-bb4c-f78f9746d6c5"));
  } catch {}
})();
var i, d;
function u() {
  if (d) return i;
  d = 1;
  const e = new Set();
  let t = !1,
    n = !1;
  function o(r, s) {
    if (!t) {
      t = !0;
      for (const f of e) f();
      r === !0 && process.exit(128 + s);
    }
  }
  return (
    (i = (r) => (
      e.add(r),
      n ||
        ((n = !0),
        process.once("exit", o),
        process.once("SIGINT", o.bind(null, !0, 2)),
        process.once("SIGTERM", o.bind(null, !0, 15)),
        process.on("message", (s) => {
          s === "shutdown" && o(!0, -128);
        })),
      () => {
        e.delete(r);
      }
    )),
    i
  );
}
var a = u();
const b = c(a);
export { b as o };
//# sourceMappingURL=index-CNG_AM8w.mjs.map
