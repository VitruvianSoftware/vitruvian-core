(function () {
  try {
    var t =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    t.SENTRY_RELEASE = { id: "4.3.209" };
    var e = new t.Error().stack;
    e &&
      ((t._sentryDebugIds = t._sentryDebugIds || {}),
      (t._sentryDebugIds[e] = "1946e9f1-00d4-4218-b9f8-cbda60c746a8"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-1946e9f1-00d4-4218-b9f8-cbda60c746a8"));
  } catch {}
})();
const o = {};
function r() {
  return { ...o };
}
function i(t, e = Date.now()) {
  const n = o[t];
  (n !== void 0 && n <= e) || (o[t] = e);
}
function d(t, e = Date.now()) {
  return globalThis.reportStartupCheckpoint?.(t, e);
}
export {
  r as getStartupCheckpoints,
  i as markStartupCheckpoint,
  d as reportStartupCheckpoint,
};
//# sourceMappingURL=startup-checkpoints-BQimOHWq.mjs.map
