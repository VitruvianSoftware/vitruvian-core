const __vite__mapDeps = (
  i,
  m = __vite__mapDeps,
  d = m.f ||
    (m.f = [
      "./deep-link-BFauSXrQ.js",
      "./index-5FBEE1WD.js",
      "./matrix-util-8DbIGEm-.js",
      "./sentry-common-BNqrY_yc.js",
      "./index-Cw3pknxT.js",
      "./main-process-state-BDOn7dvV.js",
      "./load-stores-BlYvfTx9.js",
      "./App-BHgTsVmv.js",
      "./report-dialog-C-g_klPx.js",
      "./App-9NsBNeXQ.css",
      "./load-stores-B2Yvv-OZ.css",
      "./react-wSXM5Iby.js",
      "./report-web-vitals-_vfUb9C9.js",
    ]),
) => i.map((i) => d[i]);
import { _ as l } from "./index-5FBEE1WD.js";
import {
  a9 as E,
  w as c,
  aj as S,
  C as R,
  ac as T,
  ab as i,
  N as P,
  a8 as u,
  af as y,
  a0 as I,
  o as A,
  H as L,
} from "./sentry-common-BNqrY_yc.js";
import { b as D, s as N } from "./main-process-state-BDOn7dvV.js";
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
      (e._sentryDebugIds[t] = "31d39230-27ab-4a01-9bf7-b93e0ef2dd19"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-31d39230-27ab-4a01-9bf7-b93e0ef2dd19"));
  } catch {}
})();
const O = {
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
globalThis.logger = O;
window.setImmediate ||= (e, ...t) => window.setTimeout(e, 0, ...t);
function k() {
  ((window.requestIdleCallback ||= (e, t) => {
    const o = t || {},
      n = 1,
      h = o.timeout || n,
      f = performance.now();
    return setTimeout(() => {
      e({
        get didTimeout() {
          return o.timeout ? !1 : performance.now() - f - n > h;
        },
        timeRemaining() {
          return Math.max(0, n + (performance.now() - f));
        },
      });
    }, n);
  }),
    (Array.prototype.at ||= function (t) {
      return this.slice(t, t + 1)[0];
    }));
}
k();
E.posix.sep;
var M = {};
const V = !0,
  B = typeof T < "u" && M.BEEPER_BENCH_SUMMARY_ONLY === "true",
  r = B
    ? !1
    : globalThis.LOG_LEVEL === "dev" || c || S.log_level === "dev" || R || V,
  x = u.platform(),
  C = u.release(),
  Y = {
    os: { name: x, version: C },
    appVersion: i.version,
    arch: "arm64",
    isWKWV: !0,
  },
  s = [];
let a = null;
const p = async () => {
    if (s.length === 0) return;
    const e = s.splice(0, s.length);
    (a && clearTimeout(a), (a = null));
    try {
      logger.info("skipped sending events to legacy /metrics endpoint", e);
    } catch (t) {
      logger.error("Error recording events", t, e);
    }
  },
  b = ({ type: e, data: t }, o = {}) => {
    (s.push({ deviceId: P, type: e, eventData: t, metadata: { ...Y, ...o } }),
      s.length >= 20 ? p() : a || (a = setTimeout(p, 5e3)));
  },
  X = (e, t, o) => {
    (r && logger.debug("Time:", e, "—", t, "—", o),
      b({
        type: "timing",
        data: { category: e, value: t, time: o.toFixed(0) },
      }));
  };
function v(e, t) {
  (r && logger.debug("Event:", e, "—", t), b({ type: e, data: t }, {}));
}
const G = (e) => v("platform-event", e);
function Q(e, t, o = "") {
  const n = y(o ? t.replace(o, "<scrubbed>") : t);
  return v("unpleasant-message", { origin: e, text: n });
}
function H() {
  const e = {
    IS_DEV: c,
    isLoggingEnabled: r,
    log: r ? (...t) => logger.log(...t) : () => {},
    error: r ? (...t) => logger.error(...t) : () => {},
    constants: { USER_AGENT: I, APP_VERSION: i.version },
    Sentry: globalThis.Sentry,
    trackPlatformEvent: G,
    getBinariesDirPath(t) {
      return E.join(A, "platform-" + t);
    },
  };
  globalThis.texts = e;
}
globalThis.IS_WKWV = !!window.webkit;
H();
function U() {
  return L ? "System Settings" : "System Preferences";
}
function J(e) {
  const t = e.getHours();
  return t >= 5 && t < 12
    ? "Good morning"
    : t >= 12 && t < 18
      ? "Good afternoon"
      : t >= 18 && t < 22
        ? "Good evening"
        : "Good night";
}
const $ = Object.freeze({
    BRAND_NAME: "Beeper",
    APP_NAME: "Beeper",
    BROWSER_EXTENSION_NAME: "Beeper browser extension",
    SYSTEM_PREFS_LABEL: U(),
    TRAY_NAME: "Menu Bar",
    SHOW_IN_FOLDER_LABEL: "Show in Finder",
  }),
  d = {};
function Z() {
  return { ...d };
}
function g(e, t = Date.now()) {
  const o = d[e];
  (o !== void 0 && o <= t) || (d[e] = t);
}
async function w(e) {
  const { default: t } = await l(
    async () => {
      const { default: o } = await import("./deep-link-BFauSXrQ.js");
      return { default: o };
    },
    __vite__mapDeps([0, 1, 2, 3, 4, 5]),
    import.meta.url,
  );
  await t(e);
}
function W() {
  D("deep-link", w);
}
globalThis.handleDeepLink = w;
const j = N ?? "production",
  _ = window.desktopAPI?.getPreloadBootstrapReturnedAt?.();
_ != null && g("preload bootstrap returned", _);
g("renderer index import started", window.RENDERER_INDEX_IMPORT_STARTED);
logger.log(
  `You're running ${$.APP_NAME} v${i.version} on darwin ${u.release()} arm64 (server env: ${j})`,
);
const m = new URLSearchParams(window.location.search).get("appVersion");
i.version !== m &&
  logger.warn(
    `The runtime appVersion (${m}) from URL does not match the build version (${i.version})`,
  );
g("renderer entry");
W();
const F = l(
  async () => {
    const { loadStoresPromise: e } =
      await import("./load-stores-BlYvfTx9.js").then((t) => t.l);
    return { loadStoresPromise: e };
  },
  __vite__mapDeps([6, 2, 3, 4, 5, 1, 7, 8, 9, 10]),
  import.meta.url,
).then(({ loadStoresPromise: e }) => e);
l(
  async () => {
    const { default: e } = await import("./react-wSXM5Iby.js");
    return { default: e };
  },
  __vite__mapDeps([11, 7, 3, 2, 4, 5, 1, 8, 9]),
  import.meta.url,
).then(({ default: e }) => {
  e(F);
});
c &&
  l(
    async () => {
      const { default: e } = await import("./report-web-vitals-_vfUb9C9.js");
      return { default: e };
    },
    __vite__mapDeps([12, 1]),
    import.meta.url,
  ).then(({ default: e }) => {
    e((t) => logger.log(t));
  });
const ee = Object.freeze(
  Object.defineProperty({ __proto__: null }, Symbol.toStringTag, {
    value: "Module",
  }),
);
export {
  Z as a,
  r as b,
  X as c,
  Q as d,
  $ as e,
  J as g,
  w as h,
  ee as i,
  g as m,
  p as s,
  v as t,
};
//# sourceMappingURL=index-Ch31Akxs.js.map
