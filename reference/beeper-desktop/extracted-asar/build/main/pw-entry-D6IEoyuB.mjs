import { o as e } from "./index-CNG_AM8w.mjs";
import { app as n } from "electron";
import { registerSystemStatsReporting as a } from "./system-stats-BLVoJrkB.mjs";
import s from "./inject-globals-BH1_SLF2.mjs";
import { l as d, u as m, a as f, S as u } from "./main-entry-CnfqTXzU.mjs";
import { a2 as l } from "./Keychain-CHHka2u7.mjs";
import "./_commonjsHelpers-CBUqixCJ.mjs";
import "./index-DKkZ9dV1.mjs";
import "worker_threads";
import "./constants-BL_pdRyX.mjs";
import "path";
import "os";
import "url";
import "fs";
import "./logger-DoW0T1f3.mjs";
import "./sentry-enabled-COAVq6nC.mjs";
import "./AsyncSqlite-CpInlfQ-.mjs";
import "./machine-id-DFkLVgcU.mjs";
import "./package-CIHfweXK.mjs";
import "./sentry-common-CDPx3Glo.mjs";
import "perf_hooks";
import "child_process";
import "timers/promises";
import "async_hooks";
import "./got-_wC7Q_ix.mjs";
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
import "./got-fetch-BkprknxZ.mjs";
import "electron-drag-click";
import "./util-CrY9x2BW.mjs";
import "node:net";
import "node:os";
import "./remote-method-Dje_9VSb.mjs";
import "crypto";
import "./local-ips-64rTQJNz.mjs";
import "fs/promises";
import "./startup-checkpoints-BQimOHWq.mjs";
import "./index-CMOlVndj.mjs";
import "assert";
import "./index-B_PiTES1.mjs";
import "node:util";
import "node:stream";
import "node:child_process";
import "node:crypto";
import "node:path";
import "node:events";
import "./app-api-NqP9XGk0.mjs";
import "./macos-contacts-server-D9gt4gn9.mjs";
import "./fs-xattr-D7o0ii7n.mjs";
import "diskusage";
import "./rolling-logger-C9NTeNo3.mjs";
import "node:fs/promises";
import "./fromFile-Bd43zJBF.mjs";
import "node:fs";
import "./utils-D8MokWSu.mjs";
import "stream/promises";
import "./v4-BcIr5opf.mjs";
import "node:url";
import "./download-DaM5ZnbT.mjs";
import "constants";
import "tty";
import "string_decoder";
import "./index-BiHJsdYm.mjs";
import "./SimpleHTMLParser-DYKa0uJQ.mjs";
import "./SimpleTwitterClient-BlyQEWJV.mjs";
import "./index-BE_LQecc.mjs";
import "./readable-VMWn1OrG.mjs";
import "./register-proxy-7lV9pun2.mjs";
import "domain";
import "./sentry-buffer-BdjgCKZo.mjs";
import "./crash-reporter-BlEAKQlO.mjs";
import "better-sqlite3";
import "node:module";
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
    var t = new r.Error().stack;
    t &&
      ((r._sentryDebugIds = r._sentryDebugIds || {}),
      (r._sentryDebugIds[t] = "c19c711e-eed9-41f9-9b45-362598301f0b"),
      (r._sentryDebugIdIdentifier =
        "sentry-dbid-c19c711e-eed9-41f9-9b45-362598301f0b"));
  } catch {}
})();
async function Gr({ pasHostname: r, pasPort: t, transportNonce: i }) {
  (a(), s(m, { openBrowserWindow: d }));
  const { default: p } = await import("./index-BJhQkpW6.mjs").then((o) => o.x);
  await p({
    hostname: r,
    port: t,
    transportNonce: i,
    serverEnv: u,
    userDataDirPath: m,
    userAgent: "",
    preferredSystemLanguage: n.getPreferredSystemLanguages()[0],
    proxyFileURLs: l,
    mainThread: f,
    onExit(o) {
      e(o);
    },
  });
}
export { Gr as default };
//# sourceMappingURL=pw-entry-D6IEoyuB.mjs.map
