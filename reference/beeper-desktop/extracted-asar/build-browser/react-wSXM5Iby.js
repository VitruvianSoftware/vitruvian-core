import { dJ as a, aC as d, cF as t, ad as s, de as i } from "./App-BHgTsVmv.js";
import { bF as c, cO as u, b5 as n } from "./matrix-util-8DbIGEm-.js";
import "./sentry-common-BNqrY_yc.js";
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
    var o = new e.Error().stack;
    o &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[o] = "54a97153-2632-4dfc-9a98-5e385436a89c"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-54a97153-2632-4dfc-9a98-5e385436a89c"));
  } catch {}
})();
const l = ({ children: e }) => (
  i.useSyncExternalStore(u, n, n),
  t.jsx(t.Fragment, { children: e })
);
function x(e) {
  (window.addEventListener("unhandledrejection", ({ reason: r }) => {
    c(r) && a(String(r));
  }),
    d
      .createRoot(document.getElementById("root"))
      .render(t.jsx(l, { children: t.jsx(s, { loadStoresPromise: e }) })));
}
export { x as default };
//# sourceMappingURL=react-wSXM5Iby.js.map
