const __vite__mapDeps = (
  i,
  m = __vite__mapDeps,
  d = m.f ||
    (m.f = [
      "./init-sentry-browser-BK0oRUvD.js",
      "./sentry-common-BNqrY_yc.js",
      "./report-dialog-C-g_klPx.js",
      "./index-Cw3pknxT.js",
      "./index-Ch31Akxs.js",
      "./main-process-state-BDOn7dvV.js",
    ]),
) => i.map((i) => d[i]);
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
    var s = new t.Error().stack;
    s &&
      ((t._sentryDebugIds = t._sentryDebugIds || {}),
      (t._sentryDebugIds[s] = "f8ddb8b9-979d-44e6-a543-46bd1885eca0"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-f8ddb8b9-979d-44e6-a543-46bd1885eca0"));
  } catch {}
})();
(function () {
  const s = document.createElement("link").relList;
  if (s && s.supports && s.supports("modulepreload")) return;
  for (const e of document.querySelectorAll('link[rel="modulepreload"]')) a(e);
  new MutationObserver((e) => {
    for (const r of e)
      if (r.type === "childList")
        for (const o of r.addedNodes)
          o.tagName === "LINK" && o.rel === "modulepreload" && a(o);
  }).observe(document, { childList: !0, subtree: !0 });
  function d(e) {
    const r = {};
    return (
      e.integrity && (r.integrity = e.integrity),
      e.referrerPolicy && (r.referrerPolicy = e.referrerPolicy),
      e.crossOrigin === "use-credentials"
        ? (r.credentials = "include")
        : e.crossOrigin === "anonymous"
          ? (r.credentials = "omit")
          : (r.credentials = "same-origin"),
      r
    );
  }
  function a(e) {
    if (e.ep) return;
    e.ep = !0;
    const r = d(e);
    fetch(e.href, r);
  }
})();
const g = "modulepreload",
  b = function (t, s) {
    return new URL(t, s).href;
  },
  _ = {},
  p = function (s, d, a) {
    let e = Promise.resolve();
    if (d && d.length > 0) {
      let E = function (n) {
        return Promise.all(
          n.map((c) =>
            Promise.resolve(c).then(
              (u) => ({ status: "fulfilled", value: u }),
              (u) => ({ status: "rejected", reason: u }),
            ),
          ),
        );
      };
      const o = document.getElementsByTagName("link"),
        i = document.querySelector("meta[property=csp-nonce]"),
        h = i?.nonce || i?.getAttribute("nonce");
      e = E(
        d.map((n) => {
          if (((n = b(n, a)), n in _)) return;
          _[n] = !0;
          const c = n.endsWith(".css"),
            u = c ? '[rel="stylesheet"]' : "";
          if (a)
            for (let f = o.length - 1; f >= 0; f--) {
              const m = o[f];
              if (m.href === n && (!c || m.rel === "stylesheet")) return;
            }
          else if (document.querySelector(`link[href="${n}"]${u}`)) return;
          const l = document.createElement("link");
          if (
            ((l.rel = c ? "stylesheet" : g),
            c || (l.as = "script"),
            (l.crossOrigin = ""),
            (l.href = n),
            h && l.setAttribute("nonce", h),
            document.head.appendChild(l),
            c)
          )
            return new Promise((f, m) => {
              (l.addEventListener("load", f),
                l.addEventListener("error", () =>
                  m(new Error(`Unable to preload CSS for ${n}`)),
                ));
            });
        }),
      );
    }
    function r(o) {
      const i = new Event("vite:preloadError", { cancelable: !0 });
      if (((i.payload = o), window.dispatchEvent(i), !i.defaultPrevented))
        throw o;
    }
    return e.then((o) => {
      for (const i of o || []) i.status === "rejected" && r(i.reason);
      return s().catch(r);
    });
  };
var v = {};
const y = window.desktopAPI?.getRendererBootstrapSync?.();
v ??= y?.initialState;
globalThis.STARTUP_BOOTSTRAP ??= y?.startupBootstrap ?? void 0;
p(
  () => import("./main-process-state-BDOn7dvV.js").then((t) => t.m),
  [],
  import.meta.url,
);
p(
  () => import("./init-sentry-browser-BK0oRUvD.js"),
  __vite__mapDeps([0, 1, 2, 3]),
  import.meta.url,
);
window.RENDERER_INDEX_IMPORT_STARTED = Date.now();
p(
  () => import("./index-Ch31Akxs.js").then((t) => t.i),
  __vite__mapDeps([4, 1, 5]),
  import.meta.url,
);
export { p as _ };
//# sourceMappingURL=index-5FBEE1WD.js.map
