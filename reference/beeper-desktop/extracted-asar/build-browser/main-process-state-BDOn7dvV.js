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
      (e._sentryDebugIds[s] = "7bdfad07-7d9d-43b0-9277-3d240255a268"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-7bdfad07-7d9d-43b0-9277-3d240255a268"));
  } catch {}
})();
const w = (e, ...s) =>
    globalThis.rt.callObjProxyMethod({
      objName: "ipcMainShim",
      methodName: "send",
      args: [e, ...s],
    }),
  n = async (e, ...s) =>
    globalThis.rt.callObjProxyMethod({
      objName: "ipcMainShim",
      methodName: "invoke",
      args: [e, ...s],
    }),
  D = (e, s) => globalThis.rt?.registerIPCHandler(e, s),
  i = window.location.hash.slice(1),
  t = Object.fromEntries(new URLSearchParams(i).entries()),
  {
    lastSessionAliveUntil: r,
    previousSessionExitedCleanly: d,
    osBootTime: l,
    appBootTime: c,
    machineID: a,
    transportNonce: b,
    pasHost: g,
    pasOrigin: h,
    pasAdvertisedHost: p,
    pasAdvertisedOrigin: m,
    userDataDirPath: f,
    appPath: u,
    downloadsPath: y,
    countryCode: T,
    logLevel: o,
    serverEnv: v,
    systemLocale: E,
    timeFormat: _,
  } = t,
  I = !!t.smokeTest;
globalThis.MACHINE_ID = a;
globalThis.LOG_LEVEL = o;
a ||
  n("get-machine-id").then((e) => {
    e &&
      ((globalThis.MACHINE_ID = e), globalThis.Sentry?.setTag("device_id", e));
  });
const O = Object.freeze(
  Object.defineProperty(
    {
      __proto__: null,
      appBootTime: c,
      appPath: u,
      countryCode: T,
      downloadsPath: y,
      lastSessionAliveUntil: r,
      logLevel: o,
      machineID: a,
      osBootTime: l,
      pasAdvertisedHost: p,
      pasAdvertisedOrigin: m,
      pasHost: g,
      pasOrigin: h,
      previousSessionExitedCleanly: d,
      serverEnv: v,
      smokeTest: I,
      systemLocale: E,
      timeFormat: _,
      transportNonce: b,
      userDataDirPath: f,
    },
    Symbol.toStringTag,
    { value: "Module" },
  ),
);
export {
  c as a,
  D as b,
  T as c,
  y as d,
  w as e,
  g as f,
  h as g,
  d as h,
  n as i,
  I as j,
  E as k,
  r as l,
  O as m,
  b as n,
  l as o,
  m as p,
  v as s,
  _ as t,
  f as u,
};
//# sourceMappingURL=main-process-state-BDOn7dvV.js.map
