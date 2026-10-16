import { _ as o } from "./index-CcYzEQCb.js";
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
      (e._sentryDebugIds[t] = "de6a3444-95f6-4ff9-9780-d2d10645768d"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-de6a3444-95f6-4ff9-9780-d2d10645768d"));
  } catch {}
})();
function n(e) {
  e &&
    e instanceof Function &&
    o(
      async () => {
        const {
          getCLS: t,
          getFID: d,
          getFCP: i,
          getLCP: a,
          getTTFB: s,
        } = await import("./web-vitals-Byxqmm75.js");
        return { getCLS: t, getFID: d, getFCP: i, getLCP: a, getTTFB: s };
      },
      [],
      import.meta.url,
    ).then(({ getCLS: t, getFID: d, getFCP: i, getLCP: a, getTTFB: s }) => {
      (t(e), d(e), i(e), a(e), s(e));
    });
}
export { n as default };
//# sourceMappingURL=report-web-vitals-tANsp-lU.js.map
