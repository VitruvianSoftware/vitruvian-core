import R from "os";
import { I as C, a as T } from "./sentry-enabled-COAVq6nC.mjs";
import { u as x } from "./index-DKkZ9dV1.mjs";
import { M as W } from "./machine-id-DFkLVgcU.mjs";
import B from "./package-CIHfweXK.mjs";
import { s as F } from "./sentry-common-CDPx3Glo.mjs";
import { performance as b } from "perf_hooks";
import O, { join as Y } from "path";
import U from "child_process";
import { parentPort as P, Worker as V } from "worker_threads";
import { o as z } from "./index-CNG_AM8w.mjs";
import { setTimeout as Q } from "timers/promises";
import { l as G } from "./logger-DoW0T1f3.mjs";
import { AsyncLocalStorage as J } from "async_hooks";
import N from "node:module";
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
    var e = new t.Error().stack;
    e &&
      ((t._sentryDebugIds = t._sentryDebugIds || {}),
      (t._sentryDebugIds[e] = "2214f2c4-e4f3-4596-857e-cc849668c32d"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-2214f2c4-e4f3-4596-857e-cc849668c32d"));
  } catch {}
})();
const Me = import.meta.filename,
  A = import.meta.dirname,
  Re = N.createRequire(import.meta.url),
  X = !0,
  Z = typeof process < "u" && process.env.BEEPER_BENCH_SUMMARY_ONLY === "true",
  D = Z
    ? !1
    : globalThis.LOG_LEVEL === "dev" || C || x.log_level === "dev" || T || X;
var k = ((t) => (
  (t.PLATFORM_WORKER = "platform_worker"),
  (t.SQLITE_WORKER = "sqlite_worker"),
  (t.HEIC_WORKER = "heic_worker"),
  (t.OTHER_WORKER = "other_worker"),
  t
))(k || {});
const u = new Set(),
  f = new Set();
function $(t) {
  P ? P.postMessage({ __breadcrumb: t }) : globalThis.Sentry?.addBreadcrumb(t);
}
function d(t, e) {
  $({ type: "info", category: "worker.lifecycle", message: t, data: e });
}
function w(t) {
  if (!u.has(t)) {
    logger.warn("Worker already disposed");
    return;
  }
  (t?.postMessage("cleanup"),
    u.delete(t),
    d("disposeWorker: postMessage cleanup", { threadId: t?.threadId }));
}
function L(t, e = {}, r, n) {
  G(`runWorker(${t})`);
  let s;
  function i() {
    logger.log(t, "starting worker");
    const l = Date.now();
    return (
      d(`${t} creating`),
      (s = new V(r, {
        argv: process.argv,
        transferList: n,
        workerData: { workerName: t, userConf: x, machineID: W, ...e },
      })),
      s.on("online", () => {
        (logger.log(t, "took", Date.now() - l, "ms to be online"),
          u.add(s),
          f.add(s),
          d(`${t} online`, { threadId: s.threadId }));
      }),
      s.on("error", (o) => {
        (w(s),
          logger.error(t, "worker error event", o),
          d(`${t} error`, {
            threadId: s.threadId,
            message: o instanceof Error ? o.message : String(o),
          }),
          globalThis.Sentry?.captureException(o, { extra: { workerName: t } }));
      }),
      s.on("exit", (o) => {
        (u.delete(s),
          f.delete(s),
          logger.error(t, "worker exit event", o),
          d(`${t} exit`, { threadId: s.threadId, exitCode: o }));
      }),
      s
    );
  }
  return (
    z(() => {
      (logger.log("[exit handler] disposing worker", t), w(s));
    }),
    i()
  );
}
const Ce =
    (t) =>
    (e, r = {}) =>
      L(
        k.OTHER_WORKER,
        { ...r, userDataDirPath: t, workerFilePath: e },
        O.join(A, "ow.js"),
      ),
  Te = (t) => (e, r, n) => {
    const s = U.fork(O.join(A, "cp.js"), {
      serialization: "advanced",
      stdio: ["inherit", "inherit", "inherit", "ipc"],
      ...r,
    });
    return (
      s.once("spawn", () => {
        s.send({
          type: "init",
          userDataDirPath: t,
          entryFilePath: e,
          initData: { ...n, machineID: globalThis.MACHINE_ID },
        });
      }),
      s
    );
  },
  xe = (t) => {
    for (const e of u) e.postMessage(t);
  };
async function We() {
  let t = u.size;
  if (t !== 0)
    return new Promise((e) => {
      u.forEach((r) => {
        (w(r),
          r.on("message", (n) => {
            (n?.cleanup && t--, t === 0 && e());
          }));
      });
    });
}
async function ee() {
  d("terminateAllWorkers", { threadIds: [...f].map((e) => e.threadId) });
  const t = [];
  for (const e of f) t.push(e.terminate());
  (f.clear(), u.clear(), await Promise.allSettled(t));
}
async function Oe(t = !1) {
  if ((d("forceExit", { skipGracefulTerminate: t }), !t))
    try {
      await Promise.race([ee(), Q(1e3)]);
    } catch (e) {
      logger.warn("[forceExit]", e);
    }
  throw (process.kill(process.pid, "SIGKILL"), new Error("unreachable"));
}
const te = R.platform(),
  re = R.release(),
  se = {
    os: { name: te, version: re },
    appVersion: B.version,
    arch: process.arch,
    isWKWV: !1,
  },
  p = [];
let m = null;
const M = async () => {
    if (p.length === 0) return;
    const t = p.splice(0, p.length);
    (m && clearTimeout(m), (m = null));
    try {
      logger.info("skipped sending events to legacy /metrics endpoint", t);
    } catch (e) {
      logger.error("Error recording events", e, t);
    }
  },
  K = ({ type: t, data: e }, r = {}) => {
    (p.push({ deviceId: W, type: t, eventData: e, metadata: { ...se, ...r } }),
      p.length >= 20 ? M() : m || (m = setTimeout(M, 5e3)));
  },
  Ae = (t, e, r) => {
    (D && logger.debug("Time:", t, "—", e, "—", r),
      K({
        type: "timing",
        data: { category: t, value: e, time: r.toFixed(0) },
      }));
  };
function H(t, e) {
  (D && logger.debug("Event:", t, "—", e), K({ type: t, data: e }, {}));
}
const De = (t) => H("platform-event", t);
function $e(t, e, r = "") {
  const n = F(r ? e.replace(r, "<scrubbed>") : e);
  return H("unpleasant-message", { origin: t, text: n });
}
const g = Object.freeze([
  0, 0.1, 0.5, 1, 2, 5, 10, 25, 50, 100, 250, 500, 1e3, 2500, 5e3,
]);
class ne {
  constructor() {
    ((this.count = 0),
      (this.sum = 0),
      (this.min = Number.POSITIVE_INFINITY),
      (this.max = 0),
      (this.bucketCounts = new Array(g.length + 1).fill(0)));
  }
  observe(e) {
    ((this.count += 1),
      (this.sum += e),
      e < this.min && (this.min = e),
      e > this.max && (this.max = e));
    const r = g;
    let n = r.length;
    for (let s = 0; s < r.length; s += 1)
      if (e <= r[s]) {
        n = s;
        break;
      }
    this.bucketCounts[n] += 1;
  }
  snapshot() {
    const e = this.count === 0;
    return {
      count: this.count,
      sum: this.sum,
      min: e ? 0 : this.min,
      max: this.max,
      p50: this.percentile(0.5),
      p95: this.percentile(0.95),
      p99: this.percentile(0.99),
      buckets: this.bucketCounts.slice(),
    };
  }
  reset() {
    ((this.count = 0),
      (this.sum = 0),
      (this.min = Number.POSITIVE_INFINITY),
      (this.max = 0),
      this.bucketCounts.fill(0));
  }
  percentile(e) {
    if (this.count === 0) return 0;
    const r = this.count * e;
    let n = 0;
    const s = g;
    for (let i = 0; i < this.bucketCounts.length; i += 1)
      if (((n += this.bucketCounts[i]), n >= r))
        return i < s.length ? s[i] : this.max;
    return this.max;
  }
  static get bucketUpperBoundsMs() {
    return g;
  }
}
let q = "startup";
function oe() {
  return q;
}
function Le() {
  q = "steady";
}
class ie {
  constructor(e, r = () => "steady") {
    ((this.histograms = new Map()), (this.enabled = e), (this.getPhase = r));
  }
  isEnabled() {
    return this.enabled;
  }
  observe(e, r) {
    if (!this.enabled) return;
    const n = `${e}.${this.getPhase()}`;
    let s = this.histograms.get(n);
    (s || ((s = new ne()), this.histograms.set(n, s)), s.observe(r));
  }
  snapshot() {
    const e = {};
    for (const [r, n] of this.histograms) e[r] = n.snapshot();
    return e;
  }
  snapshotAndReset() {
    const e = this.snapshot();
    return (this.histograms.clear(), e);
  }
  clear() {
    this.histograms.clear();
  }
}
const a = new ie(C || T, oe),
  v = a.isEnabled(),
  I = new J();
async function Ke(t, e) {
  if (!v) return e();
  const r = {
    eventType: t,
    startMs: b.now(),
    dbReadCount: 0,
    dbReadMs: 0,
    dbWriteCount: 0,
    dbWriteMs: 0,
    stateSyncFrames: 0,
    stateSyncEncodeMs: 0,
  };
  try {
    return await I.run(r, e);
  } finally {
    const n = b.now() - r.startMs,
      s = `processCallback.${r.eventType}`;
    (a.observe(`${s}.total_ms`, n),
      a.observe(`${s}.db_read_count`, r.dbReadCount),
      a.observe(`${s}.db_read_total_ms`, r.dbReadMs),
      a.observe(`${s}.db_write_count`, r.dbWriteCount),
      a.observe(`${s}.db_write_total_ms`, r.dbWriteMs),
      a.observe(`${s}.state_sync_frames`, r.stateSyncFrames),
      a.observe(`${s}.state_sync_encode_ms`, r.stateSyncEncodeMs));
  }
}
function ae() {
  if (v) return I.getStore();
}
function ce(t, e, r) {
  t &&
    (e === "read"
      ? ((t.dbReadCount += 1), (t.dbReadMs += r))
      : ((t.dbWriteCount += 1), (t.dbWriteMs += r)));
}
function He(t) {
  if (!v) return;
  const e = I.getStore();
  e && ((e.stateSyncFrames += 1), (e.stateSyncEncodeMs += t));
}
const le = Y(import.meta.dirname, "./sqlite-worker-BYmkyVxU.mjs"),
  j = ["raw_all", "pluck_all", "pluck_get", "all", "get", "run", "exec"],
  de = new Set(["raw_all", "pluck_all", "pluck_get", "all", "get"]),
  ue = new Set([...j, "batch"]),
  y = a.isEnabled();
class qe {
  constructor() {
    ((this.promises = new Map()),
      (this.counter = 0),
      (this.callsIssued = 0),
      (this.onMessage = ({
        reqID: e,
        result: r,
        errorMessage: n,
        errorName: s,
        errorCode: i,
        errorStack: l,
        errorSql: o,
        errorMethodName: _,
        workerExecMs: h,
      }) => {
        const c = this.promises.get(e);
        if (!c) return logger.error("unable to find promise for", e);
        if ((this.promises.delete(e), y && c.perfKindPrefix)) {
          const E = b.now() - c.enqueueAt;
          if (
            (a.observe(`${c.perfKindPrefix}.round_trip_ms`, E),
            typeof h == "number")
          ) {
            a.observe(`${c.perfKindPrefix}.worker_exec_ms`, h);
            const S = E - h;
            a.observe(`${c.perfKindPrefix}.overhead_ms`, S > 0 ? S : 0);
          }
          ce(
            c.callbackCtx,
            c.perfKindPrefix === "db.read" ? "read" : "write",
            E,
          );
        }
        n != null ? c.reject(this.buildError(n, s, i, l, o, _)) : c.resolve(r);
      }),
      (this.buildError = (e, r, n, s, i, l) => {
        const o = Error(e);
        return (
          r && (o.name = r),
          n && (o.code = n),
          i && (o.sql = i),
          l && (o.methodName = l),
          s && (o.stack = s),
          $({
            type: "error",
            category: "sqlite.error",
            message: e,
            data: {
              code: n,
              methodName: l,
              sql: i,
              filePath: this.filePath,
              threadId: this.worker?.threadId,
            },
          }),
          o
        );
      }),
      (this.init = async (e, r) => (
        (this.filePath = e),
        await this.workerOnlinePromise,
        this.call("init", [e, r])
      )),
      (this.batch = (e) => this.call("batch", [e])),
      (this.call = (e, r, n) => {
        const s = ++this.counter;
        this.callsIssued += 1;
        const i =
            y && ue.has(e) ? (de.has(e) ? "db.read" : "db.write") : void 0,
          l = y ? b.now() : 0,
          o = i ? ae() : void 0;
        return (
          this.worker.postMessage({ reqID: s, methodName: e, args: r, sql: n }),
          new Promise((_, h) => {
            this.promises.set(s, {
              resolve: _,
              reject: h,
              enqueueAt: l,
              perfKindPrefix: i,
              callbackCtx: o,
            });
          })
        );
      }),
      (this.terminate = () => (
        d("AsyncSqlite.terminate (failure path)", {
          threadId: this.worker.threadId,
          filePath: this.filePath,
        }),
        this.worker.terminate()
      )),
      (this.workerOnlinePromise = new Promise((e) => {
        this.worker = L(k.SQLITE_WORKER, void 0, le)
          .on("message", this.onMessage)
          .once("online", () => {
            e();
          });
      })));
    for (const e of j) this[e] = (r, ...n) => this.call(e, n, r);
  }
  async dispose() {
    return (
      await this.call("close"),
      d("AsyncSqlite.dispose terminate", {
        threadId: this.worker.threadId,
        filePath: this.filePath,
      }),
      this.worker.terminate()
    );
  }
}
export {
  qe as A,
  k as W,
  Te as a,
  xe as b,
  We as c,
  Ce as d,
  Ke as e,
  Oe as f,
  L as g,
  De as h,
  D as i,
  Ae as j,
  $e as k,
  Le as m,
  a as p,
  He as r,
  M as s,
  H as t,
  d as w,
};
//# sourceMappingURL=AsyncSqlite-CpInlfQ-.mjs.map
