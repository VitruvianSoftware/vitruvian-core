import { threadId as a, workerData as i } from "node:worker_threads";
import { registerNativeModuleResolutionHooks as d } from "./dev-B4WdIoV1.mjs";
import "./v8-compile-cache-DHFLdCfD.mjs";
import "./register-proxy-7lV9pun2.mjs";
import "./register-system-ca-CvulJ6wJ.mjs";
import { L as f } from "./util-CrY9x2BW.mjs";
import l from "./inject-globals-BH1_SLF2.mjs";
import { registerSystemStatsReporting as c } from "./system-stats-BLVoJrkB.mjs";
import { s as g } from "./sentry-buffer-BdjgCKZo.mjs";
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
      (e._sentryDebugIds[t] = "2c2cbef0-5137-41ff-b407-cdead1e12966"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-2c2cbef0-5137-41ff-b407-cdead1e12966"));
  } catch {}
})();
const b = (e) => {
  process.env.ENTRY_POINT = `${e}-${a}`;
};
async function w(e, t) {
  const o = i.machineID,
    s = i.noSentry;
  (d(),
    (globalThis.USE_SENTRY_NODE = !0),
    (globalThis.LOG_LEVEL = f),
    (globalThis.MACHINE_ID = o),
    b(e),
    (await import("./init-logger-node-CRebVfyW.mjs")).default(),
    logger.log(`Howdy from ${e}!`),
    s || g());
  const { default: n } = await import("./sentry-enabled-COAVq6nC.mjs").then(
    (r) => r.i,
  );
  if (n) {
    const { addAppNodeModulesPath: r } = await import("./dev-B4WdIoV1.mjs");
  }
  (t.injectGlobals &&
    l(t.injectGlobals.userDataDirPath, t.injectGlobals.overriddenGlobalMethods),
    t.registerSystemStatsReporting && c());
}
export { w as s };
//# sourceMappingURL=setup-BqAdqlA3.mjs.map
