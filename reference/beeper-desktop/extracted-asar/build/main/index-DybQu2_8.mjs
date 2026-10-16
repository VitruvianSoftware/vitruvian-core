import { a as i } from "./_commonjsHelpers-CBUqixCJ.mjs";
import { r as a } from "./index-BbIDQpmR.mjs";
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
      (e._sentryDebugIds[r] = "9cc74116-ec7f-4c3b-98f5-8aaa193d239c"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-9cc74116-ec7f-4c3b-98f5-8aaa193d239c"));
  } catch {}
})();
function d(e, r) {
  for (var n = 0; n < r.length; n++) {
    const t = r[n];
    if (typeof t != "string" && !Array.isArray(t)) {
      for (const o in t)
        if (o !== "default" && !(o in e)) {
          const s = Object.getOwnPropertyDescriptor(t, o);
          s &&
            Object.defineProperty(
              e,
              o,
              s.get ? s : { enumerable: !0, get: () => t[o] },
            );
        }
    }
  }
  return Object.freeze(
    Object.defineProperty(e, Symbol.toStringTag, { value: "Module" }),
  );
}
var f = a();
const c = i(f),
  u = d({ __proto__: null, default: c }, [f]);
export { u as i };
//# sourceMappingURL=index-DybQu2_8.mjs.map
