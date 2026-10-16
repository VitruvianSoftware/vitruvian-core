import { u as o } from "./index-DKkZ9dV1.mjs";
import { BUNDLE_ID as d } from "./constants-BL_pdRyX.mjs";
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
    var n = new e.Error().stack;
    n &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[n] = "97847d1b-3360-40ff-b814-7da26928013a"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-97847d1b-3360-40ff-b814-7da26928013a"));
  } catch {}
})();
const s = d.endsWith(".nightly"),
  t = o.developer_mode || !1,
  i = Object.freeze(
    Object.defineProperty(
      { __proto__: null, IS_NIGHTLY: s, default: t },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  ),
  l = process.env.FORCE_SENTRY != null || (!t && !o.sentry_disabled);
export { t as I, l as S, s as a, i };
//# sourceMappingURL=sentry-enabled-COAVq6nC.mjs.map
