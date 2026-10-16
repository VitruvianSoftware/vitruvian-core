import { parentPort as a } from "node:worker_threads";
import { performance as c } from "node:perf_hooks";
import d from "better-sqlite3";
import { W as f, i as m } from "./AsyncSqlite-CpInlfQ-.mjs";
import { s as h } from "./setup-BqAdqlA3.mjs";
import "os";
import "./sentry-enabled-COAVq6nC.mjs";
import "./index-DKkZ9dV1.mjs";
import "worker_threads";
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
import "./logger-DoW0T1f3.mjs";
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
import "./util-CrY9x2BW.mjs";
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
import "./sentry-buffer-BdjgCKZo.mjs";
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
      (e._sentryDebugIds[t] = "f2c63a50-cc0a-49ee-9e00-caa4a627449d"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-f2c63a50-cc0a-49ee-9e00-caa4a627449d"));
  } catch {}
})();
await h(f.SQLITE_WORKER, {
  injectGlobals: !1,
  registerSystemStatsReporting: !1,
});
class u {
  constructor() {
    this.statementMap = new Map();
  }
  prepareSQL(t) {
    const i = this.statementMap.get(t);
    if (i) return i;
    const r = this.db.prepare(t);
    return (this.statementMap.set(t, r), r);
  }
  runBatchOp({ method: t, sql: i, params: r }) {
    try {
      const o = this.prepareSQL(i);
      if (t.includes("_")) {
        const [s, p] = t.split("_");
        return o[s]()[p](...r);
      }
      return o[t](...r);
    } catch (o) {
      throw (o && !o.batchOpSql && (o.batchOpSql = i), o);
    }
  }
  processMessage({ sql: t, methodName: i, args: r }) {
    switch (i) {
      case "init":
        if (this.db) throw Error("db already initialized");
        return (
          (this.filePath = r[0]),
          (this.db = d(this.filePath, { ...r[1] })),
          Sentry.setTag("sql_file_path", this.filePath),
          !0
        );
      case "exec":
        return (this.db.exec(t), !0);
      case "close":
        return (
          m && logger.log("closing db", this.filePath),
          this.db.close(),
          !0
        );
      case "batch": {
        if (!this.db) throw Error("db not initialized");
        const o = r[0];
        return this.db.transaction((p) => p.map((l) => this.runBatchOp(l)))(o);
      }
    }
    if (!this.db) throw Error("db not initialized");
    {
      m && logger.silently.debug(`[sqlite-worker] ${t}`);
      const o = this.prepareSQL(t);
      if (i.includes("_")) {
        const [s, p] = i.split("_");
        return o[s]()[p](...r);
      }
      return o[i](...r);
    }
  }
}
const n = new u();
a.on("message", (e) => {
  switch (e) {
    case "cleanup":
      (n.db?.close(), a?.postMessage({ cleanup: !0 }));
      return;
    case "powermonitor-on-resume":
      return;
  }
  const { reqID: t } = e,
    i = c.now();
  try {
    const r = n.processMessage(e);
    a.postMessage({ reqID: t, result: r, workerExecMs: c.now() - i });
  } catch (r) {
    const o = c.now() - i;
    logger.error("sqlite-worker error", n.filePath, r, m ? e : null);
    const s =
      r?.name === "SqliteError" &&
      (r?.message === "file is not a database" ||
        r?.message === "database disk image is malformed");
    a.postMessage({
      reqID: t,
      errorMessage: s ? "$TextsDbCorrupted$" + n.filePath : r.message,
      errorName: r?.name,
      errorCode: r?.code,
      errorStack: r?.stack,
      errorSql: e.sql ?? r?.batchOpSql,
      errorMethodName: e.methodName,
      workerExecMs: o,
    });
  }
});
//# sourceMappingURL=sqlite-worker-BYmkyVxU.mjs.map
