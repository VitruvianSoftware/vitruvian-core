import {
  cT as f,
  de as h,
  b5 as p,
  K as k,
  z as E,
  cF as r,
  aO as B,
  d5 as y,
  ai as I,
  e as L,
  aY as x,
  k as N,
  aG as R,
  c5 as C,
} from "./App-BHgTsVmv.js";
import { cA as m, J as b, c3 as O, a1 as n } from "./matrix-util-8DbIGEm-.js";
import { f as V, t as T } from "./load-stores-BlYvfTx9.js";
import { K as w, M as u } from "./sentry-common-BNqrY_yc.js";
import "./index-Cw3pknxT.js";
import "./index-Ch31Akxs.js";
import "./index-5FBEE1WD.js";
import "./main-process-state-BDOn7dvV.js";
import "./report-dialog-C-g_klPx.js";
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
    var e = new t.Error().stack;
    e &&
      ((t._sentryDebugIds = t._sentryDebugIds || {}),
      (t._sentryDebugIds[e] = "01c0052a-a668-4239-97f2-a96e566883ee"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-01c0052a-a668-4239-97f2-a96e566883ee"));
  } catch {}
})();
const D = "_trigger_1uwd4_1",
  W = { trigger: D },
  A = new Set([
    "discord",
    "facebook",
    "instagram",
    "linkedin",
    "slack",
    "twitter",
  ]),
  M = {
    "facebookgo/messenger": () => n("Login with Browser"),
    "twitter/cookies": () => n("Login with Browser"),
    "slackgo/token": () => n("Login with Browser"),
    "discordgo/token": () => n("Login with Browser"),
    "gvoice/cookies": () => n("Login with Browser"),
    "linkedin/cookies": () => n("Login with Browser"),
    "facebookgo/messenger-lite": () => n("Login with Password"),
    "signal/qr": () => n("QR Code"),
    "whatsapp/qr": () => n("QR Code"),
  },
  P = {
    facebookgo: ["messenger-lite", "messenger"],
    slackgo: ["email", "token"],
    discordgo: ["token", "qr"],
    telegram: ["phone", "qr"],
  },
  v = f(() => {
    const t = h.useContext(p),
      e = t.prefsViewStore,
      o = e.subViewProps.accountInstance,
      a = o && P[o.bridgeType],
      l = (e.loginState.availableFlows ?? [])
        .filter((s) => !a || a.includes(s.id))
        .filter((s) => s.id !== e.loginState.selectedFlowID),
      c =
        !!o?.platform.network &&
        A.has(o.platform.network) &&
        m.features[k.BROWSER_EXTENSION].show;
    if (e.subView !== b.ADD_ACCOUNT || !o || (l.length === 0 && !c))
      return null;
    const g = l.map((s) => {
      const i = V(o.bridgeType, s.id);
      return {
        label: M[i]?.() ?? T(i, "flowName", s.name) ?? s.id,
        disabled: e.loginState.startingLoginProcess,
        action: () => {
          o.startLogin(s.id, !!e.subViewProps.isOnboarding).catch((S) =>
            e.setErrorMessage(S.message),
          );
        },
      };
    });
    c && g.push({ label: n("Download Chrome Extension"), action: () => O(E) });
    const _ = (s) => {
      const i = s.currentTarget.getBoundingClientRect();
      y(t, g, t.threadSelectionMode, { position: { x: i.left, y: i.bottom } });
    };
    return r.jsx("button", {
      type: "button",
      className: W.trigger,
      "aria-label": n("Login options"),
      onClick: _,
      children: r.jsx(B, { name: "chevron-down", width: 20, height: 20 }),
    });
  }),
  j = "_modal_qkhwt_1",
  F = "_titleBar_qkhwt_10",
  q = "_titleBarMenu_qkhwt_27",
  G = "_container_qkhwt_36",
  d = { modal: j, titleBar: F, titleBarMenu: q, container: G },
  H = f(() => {
    const t = h.useContext(p),
      { selectedPlatformName: e, subViewProps: o } = t.prefsViewStore,
      a = !!o.reauthenticating,
      c =
        o.accountInstance?.platform ||
        (e ? m.platformStore.platforms[e] : void 0);
    return r.jsxs(I, {
      className: d.modal,
      children: [
        r.jsxs("div", {
          className: d.titleBar,
          children: [
            c?.displayName ??
              (a ? n("Reconnect account") : n("Add an account")),
            r.jsx("span", {
              className: d.titleBarMenu,
              children: r.jsx(v, {}),
            }),
          ],
        }),
        r.jsx("div", { className: d.container, children: r.jsx(L, {}) }),
        r.jsx(x, {}),
      ],
    });
  });
function K(t) {
  if (t.kind !== "new") return 0;
  const e = C(t.loginCreds);
  return e === void 0 ? 0 : Math.min(e, 6) * 24;
}
class te extends N {
  constructor(e, o) {
    (super(), (this.windowID = e), (this.target = o));
  }
  get id() {
    return this.windowID;
  }
  get title() {
    return this.target.kind === "new"
      ? `Add ${this.target.platform.displayName}`
      : `Reconnect ${this.target.accountInstance.platform.displayName}`;
  }
  get windowType() {
    return this.target.kind === "new"
      ? "prefs-new-account"
      : "prefs-reauthenticate-account";
  }
  get windowFeatures() {
    const e = K(this.target);
    return {
      width: u,
      height: w,
      ...(e === 0
        ? { center: "screen" }
        : {
            left: (window.screen.width - u) / 2 + e,
            top: (window.screen.height - w) / 2 + e,
          }),
      toolbar: !1,
      resizable: !1,
      titleBarStyle: "hidden",
      trafficLightY: 9.5,
    };
  }
  configureWindowState(e) {
    if (
      ((e.sidebarDisabled = !0),
      e.setSidebarHidden(!0),
      e.setRightPaneView(R.PREFS),
      this.target.kind === "new")
    ) {
      e.prefsViewStore.setAddNewAccountProps(
        this.target.platform,
        this.target.loginCreds,
        this.target.isOnboarding,
      );
      return;
    }
    (e.prefsViewStore.setSubView(b.ADD_ACCOUNT),
      e.prefsViewStore.setPlatform(this.target.accountInstance.platform),
      e.prefsViewStore.setSubViewProps({
        accountInstance: this.target.accountInstance,
        reauthenticating: !0,
      }));
  }
  render() {
    return r.jsx(H, {
      "data-sentry-element": "LoginWindow",
      "data-sentry-component": "LoginBrowserWindow",
      "data-sentry-source-file": "LoginBrowserWindow.tsx",
    });
  }
  onEscapePressed() {
    this.close();
  }
}
export { te as LoginBrowserWindow };
//# sourceMappingURL=LoginBrowserWindow-BymoA2TP.js.map
