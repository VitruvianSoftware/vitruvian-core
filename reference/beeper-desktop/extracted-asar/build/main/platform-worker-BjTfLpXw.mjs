import { parentPort as s } from "node:worker_threads";
import { W as g } from "./AsyncSqlite-CpInlfQ-.mjs";
import {
  c as m,
  p as a,
  a as n,
  R as f,
  b as u,
  u as h,
  s as b,
  t as w,
  n as y,
} from "./worker-data-BiwSSwpn.mjs";
import { parentPort as p } from "worker_threads";
import { s as S } from "./setup-BqAdqlA3.mjs";
import { l as E } from "./logger-DoW0T1f3.mjs";
import { g as k } from "./util-CrY9x2BW.mjs";
import { l as R } from "./sentry-buffer-BdjgCKZo.mjs";
import "os";
import "./sentry-enabled-COAVq6nC.mjs";
import "./index-DKkZ9dV1.mjs";
import "./constants-BL_pdRyX.mjs";
import "path";
import "url";
import "fs";
import "./machine-id-DFkLVgcU.mjs";
import "./package-CIHfweXK.mjs";
import "./sentry-common-CDPx3Glo.mjs";
import "./_commonjsHelpers-CBUqixCJ.mjs";
import "perf_hooks";
import "child_process";
import "./index-CNG_AM8w.mjs";
import "timers/promises";
import "async_hooks";
import "./dev-B4WdIoV1.mjs";
import "node:module";
import "node:path";
import "node:url";
import "./v8-compile-cache-DHFLdCfD.mjs";
import "module";
import "crypto";
import "vm";
import "./register-proxy-7lV9pun2.mjs";
import "domain";
import "http";
import "https";
import "./index-BiHJsdYm.mjs";
import "net";
import "tls";
import "./register-system-ca-CvulJ6wJ.mjs";
import "node:tls";
import "./inject-globals-BH1_SLF2.mjs";
import "./got-_wC7Q_ix.mjs";
import "events";
import "util";
import "stream";
import "dns";
import "buffer";
import "zlib";
import "http2";
import "./got-fetch-BkprknxZ.mjs";
import "./system-stats-BLVoJrkB.mjs";
(function () {
  try {
    var r =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    r.SENTRY_RELEASE = { id: "4.3.209" };
    var o = new r.Error().stack;
    o &&
      ((r._sentryDebugIds = r._sentryDebugIds || {}),
      (r._sentryDebugIds[o] = "7e9835aa-c52e-4a01-9813-b5b3512a27df"),
      (r._sentryDebugIdIdentifier =
        "sentry-dbid-7e9835aa-c52e-4a01-9813-b5b3512a27df"));
  } catch {}
})();
let P = 0;
function D(r, o) {
  const t = P++;
  return new Promise((l, c) => {
    (p.once("message", (i) => {
      i?.reqID === t &&
        ("error" in i ? c(new Error(i.error.message)) : l(i.result));
    }),
      p.postMessage({ reqID: t, methodName: r, args: o }));
  });
}
const e = new Proxy(
  {},
  {
    get:
      (r, o) =>
      (...t) =>
        D(o, t),
  },
);
function d(r) {
  if (!k(r)) return;
  const o = r instanceof Error ? r : new Error(String(r));
  e.handleError({ errorMessage: o.message, errorStack: o.stack || "" });
}
process.on("uncaughtException", d);
process.on("unhandledRejection", d);
await S(g.PLATFORM_WORKER, {
  injectGlobals: {
    userDataDirPath: m,
    overriddenGlobalMethods: { openBrowserWindow: e.openBrowserWindow },
  },
  registerSystemStatsReporting: !0,
});
globalThis.reportStartupCheckpoint = (r, o = Date.now()) => {
  Promise.resolve(e.startupCheckpoint({ name: r, at: o })).catch((t) => {
    logger.warn(
      "[StartupCheckpoint] Failed to report checkpoint to main thread",
      r,
      t,
    );
  });
};
s?.on("message", (r) => {
  r === "powermonitor-on-resume" && globalThis.pas?.onSystemResume?.();
});
import("./index-BJhQkpW6.mjs")
  .then((r) => r.x)
  .then(async ({ default: r }) => {
    if (
      (E(`Running PAS on ${a}:${n}`),
      await r({
        hostname: a,
        port: n,
        transportNonce: w,
        serverEnv: b,
        userDataDirPath: m,
        userAgent: h,
        preferredSystemLanguage: u,
        proxyFileURLs: f,
        mainThread: e,
        onExit(o) {
          s.on("message", async (t) => {
            t === "cleanup" && (await o(), s?.postMessage({ cleanup: !0 }));
          });
        },
      }),
      s?.postMessage("PASInitComplete"),
      !y)
    ) {
      const o = globalThis.pas.beeperClient.sdkStarted.promise;
      R({ awaitBeforeImport: o });
    }
  })
  .catch((r) => {
    e.handleError({ errorMessage: r.message, errorStack: r.stack });
  });
//# sourceMappingURL=platform-worker-BjTfLpXw.mjs.map
