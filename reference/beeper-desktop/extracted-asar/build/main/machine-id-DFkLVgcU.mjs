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
    var d = new e.Error().stack;
    d &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[d] = "5a578917-5330-45b2-9e9b-b83cd2ab75fa"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-5a578917-5330-45b2-9e9b-b83cd2ab75fa"));
  } catch {}
})();
const b = globalThis.MACHINE_ID;
export { b as M };
//# sourceMappingURL=machine-id-DFkLVgcU.mjs.map
