import { k as f } from "./util-CrY9x2BW.mjs";
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
      (e._sentryDebugIds[r] = "9e2d3f2e-3688-4675-aded-3e11e17c2772"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-9e2d3f2e-3688-4675-aded-3e11e17c2772"));
  } catch {}
})();
const i = 500,
  u = 1e4;
function d() {
  const e = [],
    r =
      (t, o = !1) =>
      (...n) => {
        const s = globalThis.Sentry;
        if (s && !s.__isBufferedSentry) {
          const a = s[t];
          return a?.(...n);
        }
        if ((e.length < i && e.push({ method: t, args: n }), o)) return "";
      };
  return {
    __isBufferedSentry: !0,
    __bufferedOperations: e,
    addBreadcrumb: r("addBreadcrumb"),
    captureEvent: r("captureEvent", !0),
    captureException: r("captureException", !0),
    captureMessage: r("captureMessage", !0),
    setTag: r("setTag"),
    setUser: r("setUser"),
  };
}
function l() {
  globalThis.Sentry || (globalThis.Sentry = d());
}
function c(e) {
  if (!e?.__isBufferedSentry) return;
  const r = globalThis.Sentry;
  if (!(!r || r.__isBufferedSentry))
    for (const { method: t, args: o } of e.__bufferedOperations)
      try {
        const n = r[t];
        n?.(...o);
      } catch (n) {
        logger?.error?.(`Failed to replay buffered Sentry.${t}`, n);
      }
}
async function S(e = {}) {
  (l(),
    e.awaitBeforeImport &&
      (await Promise.race([
        Promise.resolve(e.awaitBeforeImport).then(
          () => {},
          () => {},
        ),
        f(u),
      ])));
  try {
    const t = (await import("./init-sentry-node-XqPS3sg6.mjs")).default,
      o = globalThis.Sentry;
    return ((globalThis.Sentry = t), c(o), t);
  } catch (r) {
    logger?.error?.("Failed to initialize Sentry", r);
  } finally {
    e.onSettled?.();
  }
}
export { S as l, l as s };
//# sourceMappingURL=sentry-buffer-BdjgCKZo.mjs.map
