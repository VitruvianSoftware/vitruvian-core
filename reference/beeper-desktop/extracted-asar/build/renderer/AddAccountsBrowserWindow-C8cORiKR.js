import {
  cY as o,
  dk as n,
  cK as s,
  am as c,
  dW as a,
  bw as i,
  t as l,
  d as u,
  c as m,
  b1 as h,
  l as A,
} from "./App-CsJiApxN.js";
import { w as f, b as p, A as w, a as g } from "./sentry-common-BxRELKId.js";
import { a2 as d } from "./matrix-util-Cr_UwXbj.js";
import "./index-Cw3pknxT.js";
import "./index-Dhe7xemD.js";
import "./index-CcYzEQCb.js";
import "./main-process-state-wkFhis-C.js";
import "./report-dialog-7bETf2vU.js";
import "./helpHubMessages-CXhGQ9cB.js";
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
      (e._sentryDebugIds[t] = "f624916e-11ee-4d54-900d-ca74738a7b16"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-f624916e-11ee-4d54-900d-ca74738a7b16"));
  } catch {}
})();
const _ = o(() => {
  const [e, t] = n.useState("");
  return s.jsxs(c, {
    className: a.modal,
    children: [
      s.jsx("header", {
        className: i(a.modalHeader, { [a.isMac]: f }),
        children: d("Add an Account"),
      }),
      s.jsxs("div", {
        className: a.modalCard,
        children: [
          s.jsx("div", {
            className: a.modalSearch,
            children: s.jsx(l, {
              autoFocus: !0,
              className: a.modalSearchInput,
              placeholder: d("Search..."),
              value: e,
              onChange: (r) => t(r.target.value),
              leftIcon: "search",
              rightIcons: e
                ? [
                    {
                      icon: "cancel",
                      width: 14,
                      height: 14,
                      onClick: () => t(""),
                    },
                  ]
                : void 0,
            }),
          }),
          s.jsx("section", {
            className: a.modalContainer,
            children: s.jsx(u, { searchQuery: e }),
          }),
        ],
      }),
      s.jsx(m, {}),
      s.jsx(h, { matchWindowName: !0 }),
    ],
  });
});
class j extends A {
  get id() {
    return p;
  }
  get title() {
    return "Add an Account";
  }
  get windowFeatures() {
    return {
      width: g,
      height: w,
      resizable: !1,
      toolbar: !1,
      center: "screen",
      titleBarStyle: "hidden",
      trafficLightY: 9.5,
    };
  }
  render() {
    return s.jsx(_, {
      "data-sentry-element": "AddAccountsModal",
      "data-sentry-component": "AddAccountsBrowserWindow",
      "data-sentry-source-file": "AddAccountsBrowserWindow.tsx",
    });
  }
  onEscapePressed() {
    this.close();
  }
}
export { j as AddAccountsBrowserWindow };
//# sourceMappingURL=AddAccountsBrowserWindow-C8cORiKR.js.map
