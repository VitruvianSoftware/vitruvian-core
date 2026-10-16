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
      (e._sentryDebugIds[n] = "628c3292-3b4c-46c7-a613-e1b6d1add10e"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-628c3292-3b4c-46c7-a613-e1b6d1add10e"));
  } catch {}
})();
const o = "helphub",
  r = "5ce428058c6e1ad31ea08ed1fe53f85e",
  s = 15e3,
  t = s + 5e3;
function b(e) {
  if (typeof e != "object" || e === null || !("helphub" in e)) return !1;
  const n = e.helphub;
  return n === "ready" || n === "close" || n === "error";
}
export { r as A, s as H, t as a, o as b, b as i };
//# sourceMappingURL=helpHubMessages-CXhGQ9cB.js.map
