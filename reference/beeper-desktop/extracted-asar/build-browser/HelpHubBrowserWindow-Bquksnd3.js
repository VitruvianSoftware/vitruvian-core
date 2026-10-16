import {
  cT as S,
  de as r,
  b5 as M,
  $ as L,
  cF as a,
  ai as B,
  br as b,
  aM as I,
  cr as T,
  k as W,
  a0 as j,
} from "./App-BHgTsVmv.js";
import { y as v } from "./sentry-common-BNqrY_yc.js";
import { cA as y, a1 as s } from "./matrix-util-8DbIGEm-.js";
import "./index-Cw3pknxT.js";
import "./index-Ch31Akxs.js";
import "./index-5FBEE1WD.js";
import "./main-process-state-BDOn7dvV.js";
import "./report-dialog-C-g_klPx.js";
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
    var c = new e.Error().stack;
    c &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[c] = "a36c0066-b96d-4772-8605-72387cce38c1"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-a36c0066-b96d-4772-8605-72387cce38c1"));
  } catch {}
})();
const N = "_modal_1i1c0_1",
  R = "_titleBar_1i1c0_5",
  P = "_isMac_1i1c0_15",
  F = "_container_1i1c0_19",
  k = "_iframe_1i1c0_31",
  D = "_iframeLoading_1i1c0_40",
  U = "_loading_1i1c0_44",
  C = "_error_1i1c0_54",
  O = "_retry_1i1c0_64",
  t = {
    modal: N,
    titleBar: R,
    isMac: P,
    container: F,
    iframe: k,
    iframeLoading: D,
    loading: U,
    error: C,
    retry: O,
  };
function A() {
  return y.mainWSS?.window.location.href ?? window.location.href;
}
function w(e) {
  const c = new URLSearchParams({ theme: e });
  return `${new URL("HelpHub/helpHubFrame.html", A()).href}?${c}`;
}
const $ = S(({ onClose: e }) => {
  const d = r.useContext(M).window,
    u = y.layoutStore.colorScheme === "dark" ? "darkMode" : "lightMode",
    g = r.useRef(null),
    h = r.useRef(e);
  h.current = e;
  const [_, H] = r.useState(0),
    [o, f] = r.useState(!0),
    [m, p] = r.useState(null),
    [n, x] = r.useState(() => w(u)),
    E = r.useCallback(() => {
      (f(!0), p(null), x(w(u)), H((i) => i + 1));
    }, [u]);
  return (
    r.useEffect(() => {
      logger.info("[HelpHub] loading frame", n);
      const i = (l) => {
        l.source === g.current?.contentWindow &&
          T(l.data) &&
          (l.data.helphub === "ready"
            ? f(!1)
            : l.data.helphub === "close"
              ? h.current()
              : l.data.helphub === "error" &&
                (logger.error("[HelpHub] iframe boot failed", l.data.message),
                p(s("Failed to load help. Please try again.")),
                f(!1)));
      };
      return (
        d.addEventListener("message", i),
        () => d.removeEventListener("message", i)
      );
    }, [d, n]),
    r.useEffect(() => {
      if (!o || m) return;
      const i = setTimeout(() => {
        (logger.error("[HelpHub] parent boot watchdog timed out", n),
          p(s("Failed to load help. Please try again.")),
          f(!1));
      }, L);
      return () => clearTimeout(i);
    }, [o, m, _, n]),
    r.useEffect(() => {
      o || g.current?.contentWindow?.postMessage({ helphubTheme: u }, "*");
    }, [u, o]),
    r.useEffect(
      () => () => {
        g.current?.contentWindow?.postMessage({ helphub: "shutdown" }, "*");
      },
      [],
    ),
    a.jsxs(B, {
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
          className: b(t.titleBar, { [t.isMac]: v }),
          children: s("Help"),
        }),
        a.jsxs("div", {
          className: t.container,
          children: [
            a.jsx(
              "iframe",
              {
                ref: g,
                className: b(t.iframe, { [t.iframeLoading]: o }),
                title: s("Help"),
                src: n,
                onError: () => {
                  (logger.error("[HelpHub] iframe element error", n),
                    p(s("Failed to load help. Please try again.")),
                    f(!1));
                },
              },
              _,
            ),
            o &&
              !m &&
              a.jsx("div", {
                className: t.loading,
                children: a.jsx(I, { width: 22, height: 22 }),
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
                    children: s("Try again"),
                  }),
                ],
              }),
          ],
        }),
      ],
    })
  );
});
class Q extends W {
  get id() {
    return j;
  }
  get title() {
    return s("Help");
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
    return a.jsx($, {
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
export { Q as HelpHubBrowserWindow };
//# sourceMappingURL=HelpHubBrowserWindow-Bquksnd3.js.map
