const __vite__mapDeps = (
  i,
  m = __vite__mapDeps,
  d = m.f ||
    (m.f = [
      "./init-sentry-browser-C19iq1G1.js",
      "./sentry-common-BxRELKId.js",
      "./report-dialog-7bETf2vU.js",
      "./index-Cw3pknxT.js",
      "./index-Dhe7xemD.js",
      "./main-process-state-wkFhis-C.js",
    ]),
) => i.map((i) => d[i]);
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
      (e._sentryDebugIds[n] = "b57f0be3-e812-45c2-bae2-00cb48d209a8"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-b57f0be3-e812-45c2-bae2-00cb48d209a8"));
  } catch {}
})();
const y = (function () {
    const n = typeof document < "u" && document.createElement("link").relList;
    return n && n.supports && n.supports("modulepreload")
      ? "modulepreload"
      : "preload";
  })(),
  T = function (e, n) {
    return new URL(e, n).href;
  },
  E = {},
  u = function (n, a, f) {
    let m = Promise.resolve();
    if (a && a.length > 0) {
      let b = function (t) {
        return Promise.all(
          t.map((i) =>
            Promise.resolve(i).then(
              (l) => ({ status: "fulfilled", value: l }),
              (l) => ({ status: "rejected", reason: l }),
            ),
          ),
        );
      };
      const s = document.getElementsByTagName("link"),
        r = document.querySelector("meta[property=csp-nonce]"),
        _ = r?.nonce || r?.getAttribute("nonce");
      m = b(
        a.map((t) => {
          if (((t = T(t, f)), t in E)) return;
          E[t] = !0;
          const i = t.endsWith(".css"),
            l = i ? '[rel="stylesheet"]' : "";
          if (f)
            for (let c = s.length - 1; c >= 0; c--) {
              const d = s[c];
              if (d.href === t && (!i || d.rel === "stylesheet")) return;
            }
          else if (document.querySelector(`link[href="${t}"]${l}`)) return;
          const o = document.createElement("link");
          if (
            ((o.rel = i ? "stylesheet" : y),
            i || (o.as = "script"),
            (o.crossOrigin = ""),
            (o.href = t),
            _ && o.setAttribute("nonce", _),
            document.head.appendChild(o),
            i)
          )
            return new Promise((c, d) => {
              (o.addEventListener("load", c),
                o.addEventListener("error", () =>
                  d(new Error(`Unable to preload CSS for ${t}`)),
                ));
            });
        }),
      );
    }
    function p(s) {
      const r = new Event("vite:preloadError", { cancelable: !0 });
      if (((r.payload = s), window.dispatchEvent(r), !r.defaultPrevented))
        throw s;
    }
    return m.then((s) => {
      for (const r of s || []) r.status === "rejected" && p(r.reason);
      return n().catch(p);
    });
  },
  h = window.desktopAPI?.getRendererBootstrapSync?.();
globalThis.INITIAL_STATE ??= h?.initialState;
globalThis.STARTUP_BOOTSTRAP ??= h?.startupBootstrap ?? void 0;
u(
  () => import("./main-process-state-wkFhis-C.js").then((e) => e.m),
  [],
  import.meta.url,
);
u(
  () => import("./init-sentry-browser-C19iq1G1.js"),
  __vite__mapDeps([0, 1, 2, 3]),
  import.meta.url,
);
window.RENDERER_INDEX_IMPORT_STARTED = Date.now();
u(
  () => import("./index-Dhe7xemD.js").then((e) => e.i),
  __vite__mapDeps([4, 1, 5]),
  import.meta.url,
);
export { u as _ };
//# sourceMappingURL=index-CcYzEQCb.js.map
