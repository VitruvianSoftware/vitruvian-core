import { _ as o } from "./index-5FBEE1WD.js";
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
      (e._sentryDebugIds[t] = "6f344482-78ae-45d9-92a5-108000eabde2"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-6f344482-78ae-45d9-92a5-108000eabde2"));
  } catch {}
})();
function u(e) {
  e &&
    e instanceof Function &&
    o(
      async () => {
        const {
          getCLS: t,
          getFID: d,
          getFCP: a,
          getLCP: i,
          getTTFB: s,
        } = await import("./web-vitals-Byxqmm75.js");
        return { getCLS: t, getFID: d, getFCP: a, getLCP: i, getTTFB: s };
      },
      [],
      import.meta.url,
    ).then(({ getCLS: t, getFID: d, getFCP: a, getLCP: i, getTTFB: s }) => {
      (t(e), d(e), a(e), i(e), s(e));
    });
}
export { u as default };
//# sourceMappingURL=report-web-vitals-_vfUb9C9.js.map
