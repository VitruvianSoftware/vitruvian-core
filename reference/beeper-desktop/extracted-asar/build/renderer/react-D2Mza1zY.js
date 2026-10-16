import { dP as a, aH as d, cK as t, ah as s, dk as i } from "./App-CsJiApxN.js";
import { bJ as c, cR as f, b6 as n } from "./matrix-util-Cr_UwXbj.js";
import "./sentry-common-BxRELKId.js";
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
    var o = new e.Error().stack;
    o &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[o] = "a2a8474c-9a85-4a89-8891-04f8d47b6f5c"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-a2a8474c-9a85-4a89-8891-04f8d47b6f5c"));
  } catch {}
})();
const u = ({ children: e }) => (
  i.useSyncExternalStore(f, n, n),
  t.jsx(t.Fragment, { children: e })
);
function w(e) {
  (window.addEventListener("unhandledrejection", ({ reason: r }) => {
    c(r) && a(String(r));
  }),
    d
      .createRoot(document.getElementById("root"))
      .render(t.jsx(u, { children: t.jsx(s, { loadStoresPromise: e }) })));
}
export { w as default };
//# sourceMappingURL=react-D2Mza1zY.js.map
