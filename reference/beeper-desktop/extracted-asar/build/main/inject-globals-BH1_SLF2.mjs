import n from "path";
import { promises as s } from "fs";
import { s as a } from "./logger-DoW0T1f3.mjs";
import { I as g } from "./sentry-enabled-COAVq6nC.mjs";
import { A as h, h as u, i, a as b, d as y } from "./AsyncSqlite-CpInlfQ-.mjs";
import { USER_AGENT as E, BUILD_DIR_PATH as _ } from "./constants-BL_pdRyX.mjs";
import { version as p } from "./package-CIHfweXK.mjs";
import { g as d } from "./got-_wC7Q_ix.mjs";
import { c as T } from "./got-fetch-BkprknxZ.mjs";
import { u as I } from "./index-DKkZ9dV1.mjs";
import "os";
import "./machine-id-DFkLVgcU.mjs";
import "./sentry-common-CDPx3Glo.mjs";
import "./_commonjsHelpers-CBUqixCJ.mjs";
import "perf_hooks";
import "child_process";
import "worker_threads";
import "./index-CNG_AM8w.mjs";
import "timers/promises";
import "async_hooks";
import "url";
import "events";
import "util";
import "stream";
import "http";
import "https";
import "dns";
import "buffer";
import "zlib";
import "http2";
import "tls";
import "net";
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
    var r = new t.Error().stack;
    r &&
      ((t._sentryDebugIds = t._sentryDebugIds || {}),
      (t._sentryDebugIds[r] = "19418a46-ddc8-4767-a2a4-736d4ecb3da5"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-19418a46-ddc8-4767-a2a4-736d4ecb3da5"));
  } catch {}
})();
const f = (t) =>
  [
    "-----BEGIN CERTIFICATE-----",
    t.toString("base64"),
    "-----END CERTIFICATE-----",
  ].join(`
`);
async function S(t, r = {}) {
  const e = await d(t, {
    throwHttpErrors: !1,
    ...r,
    responseType: "buffer",
    https: { certificateAuthority: r.pinnedCertificates?.map((o) => f(o)) },
  });
  return { statusCode: e.statusCode, headers: e.headers, body: e.body };
}
async function w(t, r = {}) {
  return d.stream(t, {
    throwHttpErrors: !1,
    ...r,
    https: { certificateAuthority: r.pinnedCertificates?.map((e) => f(e)) },
  });
}
const A = S,
  m = w;
function it(
  t,
  r = {
    openBrowserWindow: void 0,
    nativeFetch: void 0,
    nativeFetchStream: void 0,
  },
) {
  const e = n.join(t, "worker-log.log");
  ((globalThis.AsyncSqlite = h),
    (globalThis.AppVersion = p),
    (globalThis.DONT_LOCK_SQLITE = I.dont_lock_sqlite || !1),
    (globalThis.texts = {
      IS_DEV: g,
      isLoggingEnabled: i,
      log: i
        ? (...o) => {
            (s.appendFile(
              e,
              a([new Date(), ...o]) +
                `
`,
            ),
              logger.log(...o));
          }
        : () => {},
      error: i
        ? (...o) => {
            (s.appendFile(
              e,
              a([new Date(), ...o]) +
                `
`,
            ),
              logger.error(...o));
          }
        : () => {},
      constants: { USER_AGENT: E, APP_VERSION: p },
      Sentry,
      trackPlatformEvent: u,
      runWorker: y(t),
      forkChildProcess: b(t),
      fetch: A,
      fetchStream: m,
      createHttpClient: T,
      ...r,
      nativeFetchStream: (o, l, c) => m(l, c),
      getOriginalObject: void 0,
      getBinariesDirPath(o) {
        return n.join(_, "platform-" + o);
      },
    }));
}
export { it as default };
//# sourceMappingURL=inject-globals-BH1_SLF2.mjs.map
