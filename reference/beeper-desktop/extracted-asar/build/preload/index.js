"use strict";
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
    var o = new e.Error().stack;
    o &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[o] = "b1ff568a-8672-4717-b307-1a4f4a5e8ee6"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-b1ff568a-8672-4717-b307-1a4f4a5e8ee6"));
  } catch {}
})();
const r = require("electron"),
  a = () => r.webFrame.getZoomFactor(),
  d = r.ipcRenderer.sendSync("renderer-bootstrap-sync"),
  i = Date.now(),
  p = () => d,
  l = () => i,
  u = (e) => {
    r.webFrame.setZoomFactor(e);
  },
  f = [
    "async-remote",
    "async-remote-fn",
    "native-remote",
    "get-machine-id",
    "startup-checkpoints",
  ],
  g = ["renderer-ready", "root-store-result", "show-tray-icon-toggled"],
  s = [
    "async-remote-fn-callback",
    "async-remote-fn-release-callback",
    "deep-link",
    "root-store-call",
    "scroller-style-changed",
    "system-resource-metrics",
    "powermonitor-on-resume",
    "powermonitor-on-suspend",
    "powermonitor-lock-screen",
    "powermonitor-unlock-screen",
  ],
  t = (e, o) => {
    if (!e.includes(o))
      throw new Error(`Blocked IPC on unregistered channel: ${o}`);
    return o;
  },
  y = (e, ...o) => {
    r.ipcRenderer.send(t(g, e), ...o);
  },
  m = (e, ...o) => r.ipcRenderer.invoke(t(f, e), ...o),
  b = (e, o) => {
    const n = (R, c) => {
      o(c);
    };
    return (r.ipcRenderer.on(t(s, e), n), n);
  },
  w = (e, o) => {
    r.ipcRenderer.removeListener(t(s, e), o);
  },
  E = () => process.uptime(),
  _ = async () => process.getProcessMemoryInfo(),
  I = () => process.getCPUUsage(),
  h = () => {
    process.crash();
  },
  k = Object.freeze(
    Object.defineProperty(
      {
        __proto__: null,
        crashRendererProcess: h,
        getPreloadBootstrapReturnedAt: l,
        getProcessCpuUsage: I,
        getProcessMemoryInfo: _,
        getProcessUptime: E,
        getRendererBootstrapSync: p,
        getZoomFactor: a,
        ipcInvoke: m,
        ipcOffEvent: w,
        ipcOnEvent: b,
        ipcSend: y,
        setZoomFactor: u,
      },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  );
r.contextBridge.exposeInMainWorld("desktopAPI", k);
//# sourceMappingURL=index.js.map
