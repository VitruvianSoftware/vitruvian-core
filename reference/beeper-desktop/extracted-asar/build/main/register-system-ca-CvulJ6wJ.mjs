import d from "node:tls";
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
    var s = new e.Error().stack;
    s &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[s] = "f66b58ab-792a-4f31-91a3-2008d8667c84"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-f66b58ab-792a-4f31-91a3-2008d8667c84"));
  } catch {}
})();
const t = d;
try {
  t.setDefaultCACertificates([
    ...new Set([
      ...t.getCACertificates("default"),
      ...t.getCACertificates("system"),
    ]),
  ]);
} catch (e) {
  console.error("failed to add system CA certificates", e);
}
//# sourceMappingURL=register-system-ca-CvulJ6wJ.mjs.map
