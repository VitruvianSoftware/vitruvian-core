import "./v8-compile-cache-DHFLdCfD.mjs";
import "./register-proxy-7lV9pun2.mjs";
import "./register-system-ca-CvulJ6wJ.mjs";
import { L as o } from "./util-CrY9x2BW.mjs";
import { markStartupCheckpoint as r } from "./startup-checkpoints-BQimOHWq.mjs";
import { s as e } from "./sentry-buffer-BdjgCKZo.mjs";
import "./_commonjsHelpers-CBUqixCJ.mjs";
import "module";
import "crypto";
import "fs";
import "path";
import "vm";
import "os";
import "domain";
import "http";
import "https";
import "./index-BiHJsdYm.mjs";
import "net";
import "tls";
import "url";
import "node:tls";
(function () {
  try {
    var t =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    t.SENTRY_RELEASE = { id: "4.3.209" };
    var i = new t.Error().stack;
    i &&
      ((t._sentryDebugIds = t._sentryDebugIds || {}),
      (t._sentryDebugIds[i] = "e86649ad-8737-4ea6-b732-95724983e9f5"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-e86649ad-8737-4ea6-b732-95724983e9f5"));
  } catch {}
})();
globalThis.MAIN_BOOT_TIME = Date.now();
e();
const { registerNativeModuleResolutionHooks: a } =
  await import("./dev-B4WdIoV1.mjs");
a();
async function n() {
  try {
    const { machineId: t } = await import("./get-machine-id-My_mZ3BR.mjs");
    return await t(!1);
  } catch (t) {
    logger.error(t);
  }
}
async function m() {
  ((await import("./init-logger-node-CRebVfyW.mjs")).default(),
    await import("./electron-before-ready-BIYuVIr8.mjs"),
    (globalThis.MACHINE_ID = ""),
    (globalThis.MACHINE_ID_PROMISE = n().then(
      (t) => ((globalThis.MACHINE_ID = t ?? ""), globalThis.MACHINE_ID),
    )),
    (globalThis.LOG_LEVEL = o),
    await import("./index-BiKiNEmj.mjs"),
    r("beeper sdk module imported"),
    (globalThis.mainWindow = void 0),
    await import("./main-entry-CnfqTXzU.mjs").then((t) => t.m));
}
m();
//# sourceMappingURL=index.mjs.map
