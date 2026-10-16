import { protocol as t, app as i } from "electron";
import { h as o } from "./index-DKkZ9dV1.mjs";
import "worker_threads";
import "./constants-BL_pdRyX.mjs";
import "path";
import "os";
import "url";
import "fs";
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
    var r = new e.Error().stack;
    r &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[r] = "cf32f769-a91a-4bc0-aa0e-9214a4571fbd"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-cf32f769-a91a-4bc0-aa0e-9214a4571fbd"));
  } catch {}
})();
t.registerSchemesAsPrivileged([
  {
    scheme: "fileproxy",
    privileges: {
      standard: !0,
      secure: !0,
      supportFetchAPI: !0,
      corsEnabled: !0,
      stream: !0,
    },
  },
]);
o || i.disableHardwareAcceleration();
//# sourceMappingURL=electron-before-ready-BIYuVIr8.mjs.map
