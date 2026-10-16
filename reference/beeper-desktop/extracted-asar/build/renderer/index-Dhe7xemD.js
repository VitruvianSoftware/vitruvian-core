const __vite__mapDeps = (
  i,
  m = __vite__mapDeps,
  d = m.f ||
    (m.f = [
      "./deep-link-BH4jEnGW.js",
      "./index-CcYzEQCb.js",
      "./matrix-util-Cr_UwXbj.js",
      "./sentry-common-BxRELKId.js",
      "./index-Cw3pknxT.js",
      "./main-process-state-wkFhis-C.js",
      "./load-stores-B_4F31ws.js",
      "./App-CsJiApxN.js",
      "./report-dialog-7bETf2vU.js",
      "./helpHubMessages-CXhGQ9cB.js",
      "./App-BKmiiN0s.css",
      "./load-stores-B2Yvv-OZ.css",
      "./react-D2Mza1zY.js",
      "./report-web-vitals-tANsp-lU.js",
    ]),
) => i.map((i) => d[i]);
import { _ as i } from "./index-CcYzEQCb.js";
import {
  a7 as _,
  u as d,
  ah as h,
  y as S,
  aa as R,
  a6 as c,
  a9 as a,
  M as P,
  ad as w,
  _ as T,
  o as y,
  C as I,
} from "./sentry-common-BxRELKId.js";
import { b as L, s as A } from "./main-process-state-wkFhis-C.js";
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
      (e._sentryDebugIds[t] = "be9260eb-32c2-4d9e-af49-6bdb7ff5f1f4"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-be9260eb-32c2-4d9e-af49-6bdb7ff5f1f4"));
  } catch {}
})();
const D = {
  info: console.info,
  error: console.error,
  warn: console.warn,
  debug: console.debug,
  log: console.log,
  trace: console.trace,
  buddyOriginOverride: null,
  silently: {
    info: console.info,
    error: console.error,
    warn: console.warn,
    debug: console.debug,
    log: console.log,
    trace: console.trace,
  },
};
globalThis.logger = D;
window.setImmediate ||= (e, ...t) => window.setTimeout(e, 0, ...t);
_.posix.sep;
var N = {};
const O = !0,
  k = typeof R < "u" && N.BEEPER_BENCH_SUMMARY_ONLY === "true",
  n = k
    ? !1
    : globalThis.LOG_LEVEL === "dev" || d || h.log_level === "dev" || S || O,
  M = c.platform(),
  B = c.release(),
  V = {
    os: { name: M, version: B },
    appVersion: a.version,
    arch: "arm64",
    isWKWV: !1,
  },
  r = [];
let s = null;
const g = async () => {
    if (r.length === 0) return;
    const e = r.splice(0, r.length);
    (s && clearTimeout(s), (s = null));
    try {
      logger.info("skipped sending events to legacy /metrics endpoint", e);
    } catch (t) {
      logger.error("Error recording events", t, e);
    }
  },
  E = ({ type: e, data: t }, o = {}) => {
    (r.push({ deviceId: P, type: e, eventData: t, metadata: { ...V, ...o } }),
      r.length >= 20 ? g() : s || (s = setTimeout(g, 5e3)));
  },
  q = (e, t, o) => {
    (n && logger.debug("Time:", e, "—", t, "—", o),
      E({
        type: "timing",
        data: { category: e, value: t, time: o.toFixed(0) },
      }));
  };
function m(e, t) {
  (n && logger.debug("Event:", e, "—", t), E({ type: e, data: t }, {}));
}
const x = (e) => m("platform-event", e);
function z(e, t, o = "") {
  const v = w(o ? t.replace(o, "<scrubbed>") : t);
  return m("unpleasant-message", { origin: e, text: v });
}
function Y() {
  const e = {
    IS_DEV: d,
    isLoggingEnabled: n,
    log: n ? (...t) => logger.log(...t) : () => {},
    error: n ? (...t) => logger.error(...t) : () => {},
    constants: { USER_AGENT: T, APP_VERSION: a.version },
    Sentry: globalThis.Sentry,
    trackPlatformEvent: x,
    getBinariesDirPath(t) {
      return _.join(y, "platform-" + t);
    },
  };
  globalThis.texts = e;
}
Y();
function C() {
  return I ? "System Settings" : "System Preferences";
}
function X(e) {
  const t = e.getHours();
  return t >= 5 && t < 12
    ? "Good morning"
    : t >= 12 && t < 18
      ? "Good afternoon"
      : t >= 18 && t < 22
        ? "Good evening"
        : "Good night";
}
const G = Object.freeze({
    BRAND_NAME: "Beeper",
    APP_NAME: "Beeper",
    BROWSER_EXTENSION_NAME: "Beeper browser extension",
    SYSTEM_PREFS_LABEL: C(),
    TRAY_NAME: "Menu Bar",
    SHOW_IN_FOLDER_LABEL: "Show in Finder",
  }),
  l = {};
function K() {
  return { ...l };
}
function u(e, t = Date.now()) {
  const o = l[e];
  (o !== void 0 && o <= t) || (l[e] = t);
}
async function b(e) {
  const { default: t } = await i(
    async () => {
      const { default: o } = await import("./deep-link-BH4jEnGW.js");
      return { default: o };
    },
    __vite__mapDeps([0, 1, 2, 3, 4, 5]),
    import.meta.url,
  );
  await t(e);
}
function U() {
  L("deep-link", b);
}
globalThis.handleDeepLink = b;
const $ = A ?? "production",
  f = window.desktopAPI?.getPreloadBootstrapReturnedAt?.();
f != null && u("preload bootstrap returned", f);
u("renderer index import started", window.RENDERER_INDEX_IMPORT_STARTED);
logger.log(
  `You're running ${G.APP_NAME} v${a.version} on darwin ${c.release()} arm64 (server env: ${$})`,
);
const p = new URLSearchParams(window.location.search).get("appVersion");
a.version !== p &&
  logger.warn(
    `The runtime appVersion (${p}) from URL does not match the build version (${a.version})`,
  );
u("renderer entry");
U();
const H = i(
  async () => {
    const { loadStoresPromise: e } =
      await import("./load-stores-B_4F31ws.js").then((t) => t.l);
    return { loadStoresPromise: e };
  },
  __vite__mapDeps([6, 2, 3, 4, 5, 1, 7, 8, 9, 10, 11]),
  import.meta.url,
).then(({ loadStoresPromise: e }) => e);
i(
  async () => {
    const { default: e } = await import("./react-D2Mza1zY.js");
    return { default: e };
  },
  __vite__mapDeps([12, 7, 3, 2, 4, 5, 1, 8, 9, 10]),
  import.meta.url,
).then(({ default: e }) => {
  e(H);
});
d &&
  i(
    async () => {
      const { default: e } = await import("./report-web-vitals-tANsp-lU.js");
      return { default: e };
    },
    __vite__mapDeps([13, 1]),
    import.meta.url,
  ).then(({ default: e }) => {
    e((t) => logger.log(t));
  });
const Q = Object.freeze(
  Object.defineProperty({ __proto__: null }, Symbol.toStringTag, {
    value: "Module",
  }),
);
export {
  K as a,
  n as b,
  q as c,
  z as d,
  G as e,
  X as g,
  b as h,
  Q as i,
  u as m,
  g as s,
  m as t,
};
//# sourceMappingURL=index-Dhe7xemD.js.map
