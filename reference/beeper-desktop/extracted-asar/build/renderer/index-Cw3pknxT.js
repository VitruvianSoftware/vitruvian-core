(function () {
  try {
    var e =
      typeof window < "u"
        ? window
        : typeof n < "u"
          ? n
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    e.SENTRY_RELEASE = { id: "4.3.209" };
    var d = new e.Error().stack;
    d &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[d] = "12811934-ed0e-42c3-94f4-193cb04e7c66"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-12811934-ed0e-42c3-94f4-193cb04e7c66"));
  } catch {}
})();
const n = globalThis || void 0 || self;
export { n as g };
//# sourceMappingURL=index-Cw3pknxT.js.map
