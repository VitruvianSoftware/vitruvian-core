import {
  cY as f,
  dk as m,
  ba as p,
  L as _,
  D as E,
  cK as i,
  aT as B,
  da as y,
  am as I,
  e as k,
  b1 as x,
  l as N,
  aL as R,
  cb as C,
} from "./App-CsJiApxN.js";
import { cD as h, K as b, c7 as W, a2 as n } from "./matrix-util-Cr_UwXbj.js";
import { f as D, t as O } from "./load-stores-B_4F31ws.js";
import { H as w, J as u } from "./sentry-common-BxRELKId.js";
import "./index-Cw3pknxT.js";
import "./index-Dhe7xemD.js";
import "./index-CcYzEQCb.js";
import "./main-process-state-wkFhis-C.js";
import "./report-dialog-7bETf2vU.js";
import "./helpHubMessages-CXhGQ9cB.js";
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
      (t._sentryDebugIds[e] = "d9b31ef4-96c0-4989-9457-b7170abcf512"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-d9b31ef4-96c0-4989-9457-b7170abcf512"));
  } catch {}
})();
const V = "LoginMethodMenu-module__trigger",
  T = { trigger: V },
  M = new Set([
    "discord",
    "facebook",
    "instagram",
    "linkedin",
    "slack",
    "twitter",
  ]),
  P = {
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
  A = {
    facebookgo: ["messenger-lite", "messenger"],
    slackgo: ["email", "token"],
    discordgo: ["token", "qr"],
    telegram: ["phone", "qr"],
  },
  v = f(() => {
    const t = m.useContext(p),
      e = t.prefsViewStore,
      o = e.subViewProps.accountInstance,
      a = o && A[o.bridgeType],
      l = (e.loginState.availableFlows ?? [])
        .filter((s) => !a || a.includes(s.id))
        .filter((s) => s.id !== e.loginState.selectedFlowID),
      c =
        !!o?.platform.network &&
        M.has(o.platform.network) &&
        h.features[_.BROWSER_EXTENSION].show;
    if (e.subView !== b.ADD_ACCOUNT || !o || (l.length === 0 && !c))
      return null;
    const g = l.map((s) => {
      const r = D(o.bridgeType, s.id);
      return {
        label: P[r]?.() ?? O(r, "flowName", s.name) ?? s.id,
        disabled: e.loginState.startingLoginProcess,
        action: () => {
          o.startLogin(s.id, !!e.subViewProps.isOnboarding).catch((S) =>
            e.setErrorMessage(S.message),
          );
        },
      };
    });
    c && g.push({ label: n("Download Chrome Extension"), action: () => W(E) });
    const L = (s) => {
      const r = s.currentTarget.getBoundingClientRect();
      y(t, g, t.threadSelectionMode, { position: { x: r.left, y: r.bottom } });
    };
    return i.jsx("button", {
      type: "button",
      className: T.trigger,
      "aria-label": n("Login options"),
      onClick: L,
      children: i.jsx(B, { name: "chevron-down", width: 20, height: 20 }),
    });
  }),
  j = "LoginWindow-module__modal",
  F = "LoginWindow-module__titleBar",
  H = "LoginWindow-module__titleBarMenu",
  K = "LoginWindow-module__container",
  d = { modal: j, titleBar: F, titleBarMenu: H, container: K },
  q = f(() => {
    const t = m.useContext(p),
      { selectedPlatformName: e, subViewProps: o } = t.prefsViewStore,
      a = !!o.reauthenticating,
      c =
        o.accountInstance?.platform ||
        (e ? h.platformStore.platforms[e] : void 0);
    return i.jsxs(I, {
      className: d.modal,
      children: [
        i.jsxs("div", {
          className: d.titleBar,
          children: [
            c?.displayName ??
              (a ? n("Reconnect account") : n("Add an account")),
            i.jsx("span", {
              className: d.titleBarMenu,
              children: i.jsx(v, {}),
            }),
          ],
        }),
        i.jsx("div", { className: d.container, children: i.jsx(k, {}) }),
        i.jsx(x, {}),
      ],
    });
  });
function G(t) {
  if (t.kind !== "new") return 0;
  const e = C(t.loginCreds);
  return e === void 0 ? 0 : Math.min(e, 6) * 24;
}
class oe extends N {
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
    const e = G(this.target);
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
    return i.jsx(q, {
      "data-sentry-element": "LoginWindow",
      "data-sentry-component": "LoginBrowserWindow",
      "data-sentry-source-file": "LoginBrowserWindow.tsx",
    });
  }
  onEscapePressed() {
    this.close();
  }
}
export { oe as LoginBrowserWindow };
//# sourceMappingURL=LoginBrowserWindow-BmVwY1n-.js.map
