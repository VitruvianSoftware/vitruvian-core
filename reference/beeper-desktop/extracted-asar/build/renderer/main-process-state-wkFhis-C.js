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
      (e._sentryDebugIds[s] = "cb7b50d2-a2e5-4eb5-8c33-948c2d537124"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-cb7b50d2-a2e5-4eb5-8c33-948c2d537124"));
  } catch {}
})();
class a extends Error {
  constructor(s, t, o) {
    (super(`failed to call ${s} method ${t}: ${o.message}`, { cause: o }),
      (this.name = "IPCError"),
      Error.captureStackTrace?.(this, a));
  }
}
const r = (e, ...s) => {
    const t = s?.[0] ?? "?",
      o = s?.[1]?.methodName ?? "?";
    throw new a(t, o, e);
  },
  A = (e, ...s) => {
    try {
      return window.desktopAPI?.ipcSend(e, ...s);
    } catch (t) {
      r(t, e, ...s);
    }
  },
  d = async (e, ...s) => {
    try {
      return await window.desktopAPI?.ipcInvoke(e, ...s);
    } catch (t) {
      r(t, e, ...s);
    }
  },
  D = (e, s) => window.desktopAPI?.ipcOnEvent(e, s),
  l = window.location.hash.slice(1),
  i = Object.fromEntries(new URLSearchParams(l).entries()),
  {
    lastSessionAliveUntil: p,
    previousSessionExitedCleanly: h,
    osBootTime: b,
    appBootTime: u,
    machineID: n,
    transportNonce: m,
    pasHost: f,
    pasOrigin: w,
    pasAdvertisedHost: y,
    pasAdvertisedOrigin: g,
    userDataDirPath: E,
    appPath: I,
    downloadsPath: v,
    countryCode: T,
    logLevel: c,
    serverEnv: S,
    systemLocale: _,
    timeFormat: P,
  } = i,
  k = !!i.smokeTest;
globalThis.MACHINE_ID = n;
globalThis.LOG_LEVEL = c;
n ||
  d("get-machine-id").then((e) => {
    e &&
      ((globalThis.MACHINE_ID = e), globalThis.Sentry?.setTag("device_id", e));
  });
const O = Object.freeze(
  Object.defineProperty(
    {
      __proto__: null,
      appBootTime: u,
      appPath: I,
      countryCode: T,
      downloadsPath: v,
      lastSessionAliveUntil: p,
      logLevel: c,
      machineID: n,
      osBootTime: b,
      pasAdvertisedHost: y,
      pasAdvertisedOrigin: g,
      pasHost: f,
      pasOrigin: w,
      previousSessionExitedCleanly: h,
      serverEnv: S,
      smokeTest: k,
      systemLocale: _,
      timeFormat: P,
      transportNonce: m,
      userDataDirPath: E,
    },
    Symbol.toStringTag,
    { value: "Module" },
  ),
);
export {
  u as a,
  D as b,
  T as c,
  v as d,
  A as e,
  f,
  w as g,
  h,
  d as i,
  k as j,
  _ as k,
  p as l,
  O as m,
  m as n,
  b as o,
  g as p,
  S as s,
  P as t,
  E as u,
};
//# sourceMappingURL=main-process-state-wkFhis-C.js.map
