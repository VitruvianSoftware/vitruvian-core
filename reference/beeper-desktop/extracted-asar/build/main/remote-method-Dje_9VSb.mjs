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
      (e._sentryDebugIds[n] = "b17952ae-54fd-470f-ab45-42259f044e62"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-b17952ae-54fd-470f-ab45-42259f044e62"));
  } catch {}
})();
const r = 23373,
  o = (e, n) =>
    typeof n == "string" && Object.hasOwn(e, n) && typeof e[n] == "function";
function f(e, n) {
  if (!o(e, n))
    throw new Error(`Blocked remote call to unknown method: ${String(n)}`);
  return (...t) => e[n](...t);
}
export { r as D, o as i, f as r };
//# sourceMappingURL=remote-method-Dje_9VSb.mjs.map
