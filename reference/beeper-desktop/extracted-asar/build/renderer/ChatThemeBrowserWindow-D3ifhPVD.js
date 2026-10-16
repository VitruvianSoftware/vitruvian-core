import { cK as t, bw as i, I as o, b1 as d, l as c } from "./App-CsJiApxN.js";
import { w as h } from "./sentry-common-BxRELKId.js";
import { a2 as n } from "./matrix-util-Cr_UwXbj.js";
import "./index-Cw3pknxT.js";
import "./index-Dhe7xemD.js";
import "./index-CcYzEQCb.js";
import "./main-process-state-wkFhis-C.js";
import "./report-dialog-7bETf2vU.js";
import "./helpHubMessages-CXhGQ9cB.js";
(function () {
  try {
    var e =
      typeof r < "u"
        ? r
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
      (e._sentryDebugIds[a] = "29cec8c5-ecb6-41b3-a48c-f372f8b5f2fb"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-29cec8c5-ecb6-41b3-a48c-f372f8b5f2fb"));
  } catch {}
})();
const r = "ChatThemeWindow-module__window",
  l = "ChatThemeWindow-module__titleBar",
  m = "ChatThemeWindow-module__isMac",
  u = "ChatThemeWindow-module__card",
  s = { window: r, titleBar: l, isMac: m, card: u },
  w = ({ uniqueThreadID: e }) =>
    t.jsxs("div", {
      className: s.window,
      "data-sentry-component": "ChatThemeWindow",
      "data-sentry-source-file": "ChatThemeWindow.tsx",
      children: [
        t.jsx("div", {
          className: i(s.titleBar, { [s.isMac]: h }),
          children: n("Chat Theme"),
        }),
        t.jsx("div", {
          className: s.card,
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
    return t.jsx(w, {
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
//# sourceMappingURL=ChatThemeBrowserWindow-D3ifhPVD.js.map
