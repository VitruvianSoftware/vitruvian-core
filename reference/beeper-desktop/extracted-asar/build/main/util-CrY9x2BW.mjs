import "path";
import { a as g } from "./_commonjsHelpers-CBUqixCJ.mjs";
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
    var r = new e.Error().stack;
    r &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[r] = "097fb489-45c8-4954-a43d-18ebb3b4406d"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-097fb489-45c8-4954-a43d-18ebb3b4406d"));
  } catch {}
})();
const v = {
    "--no-enforce-app-location": "NO_ENFORCE_APP_LOCATION",
    "--load-prod-frontend-build": "LOAD_PROD_FRONTEND_BUILD",
    "--run-in-browser": "RUN_IN_BROWSER",
    "--run-in-electron": "RUN_IN_ELECTRON",
    "--use-default-electron-updater": "USE_DEFAULT_ELECTRON_UPDATER",
    "--allow-downgrade": "ALLOW_DOWNGRADE",
    "--no-tls-verify": "NO_TLS_VERIFY",
    "--open-devtools": "OPEN_DEVTOOLS",
  },
  d = (e) =>
    process.argv.find((r) => r.startsWith(`--${e}=`))?.split("=", 2)?.[1],
  y = d("run-in-tab"),
  h = d("pas-hostname"),
  w = d("pas-port"),
  S = d("log-level"),
  D = d("server-env"),
  {
    NO_ENFORCE_APP_LOCATION: I,
    RUN_IN_BROWSER: U,
    RUN_IN_ELECTRON: x,
    USE_DEFAULT_ELECTRON_UPDATER: C,
    ALLOW_DOWNGRADE: F,
    OPEN_DEVTOOLS: P,
  } = (() => {
    const e = {};
    return (
      process.argv.forEach((r) => {
        const n = v[r];
        n && (e[n] = !0);
      }),
      e
    );
  })();
var f, p;
function O() {
  if (p) return f;
  p = 1;
  function e(n) {
    return n >= 55296 && n <= 56319;
  }
  function r(n) {
    return n >= 56320 && n <= 57343;
  }
  return (
    (f = function (l, t, u) {
      if (typeof t != "string") throw new Error("Input must be string");
      for (var c = t.length, i = 0, s, o, a = 0; a < c; a += 1) {
        if (
          ((s = t.charCodeAt(a)),
          (o = t[a]),
          e(s) && r(t.charCodeAt(a + 1)) && ((a += 1), (o += t[a])),
          (i += l(o)),
          i === u)
        )
          return t.slice(0, a + 1);
        if (i > u) return t.slice(0, a - o.length + 1);
      }
      return t;
    }),
    f
  );
}
var E, N;
function m() {
  if (N) return E;
  N = 1;
  var e = O(),
    r = Buffer.byteLength.bind(Buffer);
  return ((E = e.bind(null, r)), E);
}
var _, R;
function L() {
  if (R) return _;
  R = 1;
  var e = m(),
    r = /[\/\?<>\\:\*\|"]/g,
    n = /[\x00-\x1f\x80-\x9f]/g,
    l = /^\.+$/,
    t = /^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\..*)?$/i,
    u = /[\. ]+$/;
  function c(i, s) {
    if (typeof i != "string") throw new Error("Input must be string");
    var o = i
      .replace(r, s)
      .replace(n, s)
      .replace(l, s)
      .replace(t, s)
      .replace(u, s);
    return e(o, 255);
  }
  return (
    (_ = function (i, s) {
      var o = (s && s.replacement) || "",
        a = c(i, o);
      return o === "" ? a : c(a, "");
    }),
    _
  );
}
var T = L();
const B = g(T),
  M = 864e5,
  W = (e) => Math.round(e * 1e3),
  z = (e) => e.includes("@") && !e.startsWith("@"),
  q = (e) => /@[a-zA-Z0-9]/.exec(e) && e.length > 1,
  V = (e) =>
    e instanceof Error ? e.message : typeof e == "string" ? e : "Unknown error",
  H = (e) =>
    new Promise((r) => {
      setTimeout(r, e).unref?.();
    }),
  $ = () => {
    let e,
      r,
      n = !1;
    const l = new Promise((t, u) => {
      ((e = (c) => {
        ((n = !0), t(c));
      }),
        (r = u));
    });
    return {
      resolve: e,
      reject: r,
      promise: l,
      get resolved() {
        return n;
      },
    };
  },
  k = (e = {}) => {
    let r = null;
    if (
      (e?.["m.text"] &&
        Array.isArray(e["m.text"]) &&
        e["m.text"].forEach((n) => {
          n?.body &&
            (!n.mimetype || n.mimetype === "text/plain") &&
            (r = n.body);
        }),
      r)
    )
      return {
        transcription: r,
        engine: e["com.beeper.transcription.model"] || "unknown",
        language: e["com.beeper.transcription.language"] || void 0,
      };
  };
function j(e) {
  const r = e instanceof Error ? e.message : String(e);
  return (
    r.includes("Cannot find module") ||
    r.includes("ERR_MODULE_NOT_FOUND") ||
    r.includes("Failed to fetch dynamically imported module")
  );
}
const G = "0.0.0.0",
  Y = "127.0.0.1",
  K = (e) =>
    e.startsWith("[") && e.endsWith("]")
      ? e.slice(1, -1).toLowerCase()
      : e.toLowerCase();
export {
  F as A,
  G as B,
  S as L,
  M,
  I as N,
  P as O,
  h as P,
  U as R,
  D as S,
  C as U,
  Y as a,
  w as b,
  x as c,
  y as d,
  W as e,
  V as f,
  j as g,
  q as h,
  z as i,
  K as j,
  H as k,
  $ as n,
  k as p,
  B as s,
};
//# sourceMappingURL=util-CrY9x2BW.mjs.map
