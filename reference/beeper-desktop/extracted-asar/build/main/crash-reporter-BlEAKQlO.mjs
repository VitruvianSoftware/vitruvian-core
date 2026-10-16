import { crashReporter as a, app as o } from "electron";
import { S as d } from "./sentry-enabled-COAVq6nC.mjs";
import "./index-DKkZ9dV1.mjs";
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
    var t = new e.Error().stack;
    t &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[t] = "06d816be-643b-47d0-88ed-1113d42a57e0"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-06d816be-643b-47d0-88ed-1113d42a57e0"));
  } catch {}
})();
let r = !1;
function c() {
  r ||
    process.mas ||
    !d ||
    ((r = !0),
    a.start({
      companyName: "",
      ignoreSystemCrashHandler: !0,
      productName: o.name || o.getName(),
      submitURL: "https://f.a.k/e",
      uploadToServer: !1,
      compress: !0,
    }));
}
function g() {
  return r;
}
export { g as crashReporterAlreadyStarted, c as startCrashReporter };
//# sourceMappingURL=crash-reporter-BlEAKQlO.mjs.map
