import {
  cT as o,
  de as n,
  cF as s,
  ai as c,
  dQ as a,
  br as i,
  s as l,
  d as u,
  c as m,
  aY as h,
  k as f,
} from "./App-BHgTsVmv.js";
import { y as A, b as p, A as b, a as g } from "./sentry-common-BNqrY_yc.js";
import { a1 as d } from "./matrix-util-8DbIGEm-.js";
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
    var t = new e.Error().stack;
    t &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[t] = "bbd1f140-7716-442e-a277-747e2ef746fd"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-bbd1f140-7716-442e-a277-747e2ef746fd"));
  } catch {}
})();
const w = o(() => {
  const [e, t] = n.useState("");
  return s.jsxs(c, {
    className: a.modal,
    children: [
      s.jsx("header", {
        className: i(a.modalHeader, { [a.isMac]: A }),
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
class E extends f {
  get id() {
    return p;
  }
  get title() {
    return "Add an Account";
  }
  get windowFeatures() {
    return {
      width: g,
      height: b,
      resizable: !1,
      toolbar: !1,
      center: "screen",
      titleBarStyle: "hidden",
      trafficLightY: 9.5,
    };
  }
  render() {
    return s.jsx(w, {
      "data-sentry-element": "AddAccountsModal",
      "data-sentry-component": "AddAccountsBrowserWindow",
      "data-sentry-source-file": "AddAccountsBrowserWindow.tsx",
    });
  }
  onEscapePressed() {
    this.close();
  }
}
export { E as AddAccountsBrowserWindow };
//# sourceMappingURL=AddAccountsBrowserWindow-DvooLEAF.js.map
