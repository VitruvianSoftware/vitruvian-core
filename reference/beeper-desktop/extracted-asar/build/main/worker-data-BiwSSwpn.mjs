import { workerData as a } from "worker_threads";
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
      (e._sentryDebugIds[s] = "78b1e7ed-2d6f-4d59-97b7-c13b37b10526"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-78b1e7ed-2d6f-4d59-97b7-c13b37b10526"));
  } catch {}
})();
const {
  workerName: t,
  pasHostname: d,
  pasPort: o,
  transportNonce: b,
  dbKey: f,
  noSentry: i,
  userDataDirPath: u,
  serverEnv: y,
  RUN_IN_BROWSER_MODE: g,
  userAgent: p,
  preferredSystemLanguage: l,
} = a || {};
export {
  g as R,
  o as a,
  l as b,
  u as c,
  i as n,
  d as p,
  y as s,
  b as t,
  p as u,
  t as w,
};
//# sourceMappingURL=worker-data-BiwSSwpn.mjs.map
