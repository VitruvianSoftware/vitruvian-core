import {
  cY as S,
  dk as r,
  ba as L,
  cK as a,
  am as M,
  bw as h,
  aR as B,
  l as I,
} from "./App-CsJiApxN.js";
import { w as R } from "./sentry-common-BxRELKId.js";
import { cD as _, a2 as o } from "./matrix-util-Cr_UwXbj.js";
import { a as W, i as j, b as v } from "./helpHubMessages-CXhGQ9cB.js";
import "./index-Cw3pknxT.js";
import "./index-Dhe7xemD.js";
import "./index-CcYzEQCb.js";
import "./main-process-state-wkFhis-C.js";
import "./report-dialog-7bETf2vU.js";
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
    var d = new e.Error().stack;
    d &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[d] = "89c34b09-0b5f-4040-ba7d-61b71c2f743c"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-89c34b09-0b5f-4040-ba7d-61b71c2f743c"));
  } catch {}
})();
const N = "HelpHubView-module__modal",
  T = "HelpHubView-module__titleBar",
  V = "HelpHubView-module__isMac",
  P = "HelpHubView-module__container",
  D = "HelpHubView-module__iframe",
  k = "HelpHubView-module__iframeLoading",
  F = "HelpHubView-module__loading",
  U = "HelpHubView-module__error",
  C = "HelpHubView-module__retry",
  t = {
    modal: N,
    titleBar: T,
    isMac: V,
    container: P,
    iframe: D,
    iframeLoading: k,
    loading: F,
    error: U,
    retry: C,
  };
function O() {
  return _.mainWSS?.window.location.href ?? window.location.href;
}
function w(e) {
  const d = new URLSearchParams({ theme: e });
  return `${new URL("HelpHub/helpHubFrame.html", O()).href}?${d}`;
}
const A = S(({ onClose: e }) => {
  const c = r.useContext(L).window,
    u = _.layoutStore.colorScheme === "dark" ? "darkMode" : "lightMode",
    p = r.useRef(null),
    g = r.useRef(e);
  g.current = e;
  const [H, y] = r.useState(0),
    [s, f] = r.useState(!0),
    [m, b] = r.useState(null),
    [n, x] = r.useState(() => w(u)),
    E = r.useCallback(() => {
      (f(!0), b(null), x(w(u)), y((i) => i + 1));
    }, [u]);
  return (
    r.useEffect(() => {
      logger.info("[HelpHub] loading frame", n);
      const i = (l) => {
        l.source === p.current?.contentWindow &&
          j(l.data) &&
          (l.data.helphub === "ready"
            ? f(!1)
            : l.data.helphub === "close"
              ? g.current()
              : l.data.helphub === "error" &&
                (logger.error("[HelpHub] iframe boot failed", l.data.message),
                b(o("Failed to load help. Please try again.")),
                f(!1)));
      };
      return (
        c.addEventListener("message", i),
        () => c.removeEventListener("message", i)
      );
    }, [c, n]),
    r.useEffect(() => {
      if (!s || m) return;
      const i = setTimeout(() => {
        (logger.error("[HelpHub] parent boot watchdog timed out", n),
          b(o("Failed to load help. Please try again.")),
          f(!1));
      }, W);
      return () => clearTimeout(i);
    }, [s, m, H, n]),
    r.useEffect(() => {
      s || p.current?.contentWindow?.postMessage({ helphubTheme: u }, "*");
    }, [u, s]),
    r.useEffect(
      () => () => {
        p.current?.contentWindow?.postMessage({ helphub: "shutdown" }, "*");
      },
      [],
    ),
    a.jsxs(M, {
      className: t.modal,
      style: {
        background: "transparent",
        padding: 8,
        overflow: "hidden",
        display: "flex",
        flexDirection: "column",
        alignItems: "stretch",
      },
      children: [
        a.jsx("div", {
          className: h(t.titleBar, { [t.isMac]: R }),
          children: o("Help"),
        }),
        a.jsxs("div", {
          className: t.container,
          children: [
            a.jsx(
              "iframe",
              {
                ref: p,
                className: h(t.iframe, { [t.iframeLoading]: s }),
                title: o("Help"),
                src: n,
                onError: () => {
                  (logger.error("[HelpHub] iframe element error", n),
                    b(o("Failed to load help. Please try again.")),
                    f(!1));
                },
              },
              H,
            ),
            s &&
              !m &&
              a.jsx("div", {
                className: t.loading,
                children: a.jsx(B, { width: 22, height: 22 }),
              }),
            m &&
              a.jsxs("div", {
                className: t.loading,
                children: [
                  a.jsx("span", { className: t.error, children: m }),
                  a.jsx("button", {
                    type: "button",
                    className: t.retry,
                    onClick: E,
                    children: o("Try again"),
                  }),
                ],
              }),
          ],
        }),
      ],
    })
  );
});
class Z extends I {
  get id() {
    return v;
  }
  get title() {
    return o("Help");
  }
  get windowFeatures() {
    return {
      width: 420,
      height: 700,
      toolbar: !1,
      center: "parent",
      titleBarStyle: "hidden",
      trafficLightX: 10,
      trafficLightY: 10,
    };
  }
  render() {
    return a.jsx(A, {
      onClose: () => this.close(),
      "data-sentry-element": "HelpHubView",
      "data-sentry-component": "HelpHubBrowserWindow",
      "data-sentry-source-file": "HelpHubBrowserWindow.tsx",
    });
  }
  onEscapePressed() {
    this.close();
  }
}
export { Z as HelpHubBrowserWindow };
//# sourceMappingURL=HelpHubBrowserWindow-JRHyBmnb.js.map
