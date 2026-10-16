import { cF as t, br as i, H as o, aY as d, k as c } from "./App-BHgTsVmv.js";
import { y as h } from "./sentry-common-BNqrY_yc.js";
import { a1 as n } from "./matrix-util-8DbIGEm-.js";
import "./index-Cw3pknxT.js";
import "./index-Ch31Akxs.js";
import "./index-5FBEE1WD.js";
import "./main-process-state-BDOn7dvV.js";
import "./report-dialog-C-g_klPx.js";
(function () {
  try {
    var e =
      typeof s < "u"
        ? s
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    e.SENTRY_RELEASE = { id: "4.3.209" };
    var a = new e.Error().stack;
    a &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[a] = "ffec799a-e66d-4a69-9aba-624149578af8"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-ffec799a-e66d-4a69-9aba-624149578af8"));
  } catch {}
})();
const s = "_window_prm9o_1",
  l = "_titleBar_prm9o_11",
  m = "_isMac_prm9o_21",
  u = "_card_prm9o_25",
  r = { window: s, titleBar: l, isMac: m, card: u },
  f = ({ uniqueThreadID: e }) =>
    t.jsxs("div", {
      className: r.window,
      "data-sentry-component": "ChatThemeWindow",
      "data-sentry-source-file": "ChatThemeWindow.tsx",
      children: [
        t.jsx("div", {
          className: i(r.titleBar, { [r.isMac]: h }),
          children: n("Chat Theme"),
        }),
        t.jsx("div", {
          className: r.card,
          children: t.jsx(o, {
            threadID: e,
            "data-sentry-element": "ChatAppearancePicker",
            "data-sentry-source-file": "ChatThemeWindow.tsx",
          }),
        }),
        t.jsx(d, {
          matchWindowName: !0,
          "data-sentry-element": "Toasts",
          "data-sentry-source-file": "ChatThemeWindow.tsx",
        }),
      ],
    });
class I extends c {
  constructor(a) {
    (super(), (this.uniqueThreadID = a));
  }
  get id() {
    return `chat-theme-${this.uniqueThreadID}`;
  }
  get title() {
    return n("Chat Theme");
  }
  get windowFeatures() {
    return {
      width: 380,
      height: 620,
      resizable: !1,
      toolbar: !1,
      center: "parent",
      titleBarStyle: "hidden",
      trafficLightY: 9.5,
    };
  }
  render() {
    return t.jsx(f, {
      uniqueThreadID: this.uniqueThreadID,
      "data-sentry-element": "ChatThemeWindow",
      "data-sentry-component": "ChatThemeBrowserWindow",
      "data-sentry-source-file": "ChatThemeBrowserWindow.tsx",
    });
  }
  onEscapePressed() {
    this.close();
  }
}
export { I as ChatThemeBrowserWindow };
//# sourceMappingURL=ChatThemeBrowserWindow-CE8YsHUi.js.map
