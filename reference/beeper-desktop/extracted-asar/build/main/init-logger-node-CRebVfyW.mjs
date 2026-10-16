import { c as r } from "./rolling-logger-C9NTeNo3.mjs";
import "fs";
import "fs/promises";
import "path";
import "./constants-BL_pdRyX.mjs";
import "os";
import "url";
import "./logger-DoW0T1f3.mjs";
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
      (e._sentryDebugIds[o] = "15d4370e-8c27-43b0-856d-8a7cd56ac4e5"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-15d4370e-8c27-43b0-856d-8a7cd56ac4e5"));
  } catch {}
})();
function l() {
  globalThis.logger = (() => {
    const e = process.env.ENTRY_POINT ?? process.type ?? "unknown";
    return r(e);
  })();
}
export { l as default };
//# sourceMappingURL=init-logger-node-CRebVfyW.mjs.map
