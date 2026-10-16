import s from "os";
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
      (e._sentryDebugIds[t] = "cd0c9baf-7fa4-4372-a4dc-2f124b68ea01"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-cd0c9baf-7fa4-4372-a4dc-2f124b68ea01"));
  } catch {}
})();
function* r() {
  const e = s.networkInterfaces();
  for (const t of Object.values(e))
    for (const n of t || [])
      n.family === "IPv4" && n.internal && (yield n.address);
}
function f() {
  for (const e of r()) if (e === "127.0.0.1") return e;
  return r().next().value || "127.0.0.1";
}
function* a() {
  const e = s.networkInterfaces();
  for (const t of Object.values(e))
    for (const n of t || [])
      n.family === "IPv4" && !n.internal && (yield n.address);
}
function d() {
  return a().next().value || f();
}
export { d as getDefaultExternalHostname, f as getDefaultLocalHostname };
//# sourceMappingURL=local-ips-64rTQJNz.mjs.map
