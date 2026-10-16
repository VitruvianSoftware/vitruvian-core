import {
  mkdirSync as b,
  createWriteStream as P,
  readdirSync as f,
  statSync as S,
  rmSync as E,
  copyFileSync as v,
  readFileSync as I,
  writeFileSync as F,
  existsSync as T,
  unlinkSync as $,
} from "fs";
import { unlink as k } from "fs/promises";
import { join as o } from "path";
import { resolveUserDataDir as u } from "./constants-BL_pdRyX.mjs";
import { R as z, b as A } from "./logger-DoW0T1f3.mjs";
(function () {
  try {
    var d =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    d.SENTRY_RELEASE = { id: "4.3.209" };
    var t = new d.Error().stack;
    t &&
      ((d._sentryDebugIds = d._sentryDebugIds || {}),
      (d._sentryDebugIds[t] = "19b18aed-d128-4ad5-8f4d-4d50d3f06bdb"),
      (d._sentryDebugIdIdentifier =
        "sentry-dbid-19b18aed-d128-4ad5-8f4d-4d50d3f06bdb"));
  } catch {}
})();
process.env.BEEPER_BENCH;
class a {
  constructor(t) {
    ((this.options = t),
      (this.index = 0),
      (this.size = 0),
      (this.segments = new Map()),
      (this.pendingEntries = []),
      (this.drainScheduled = !1),
      (this.buddyOriginOverride = null),
      (this.silently = {
        info: this.push.bind(this, "info", !0),
        error: this.push.bind(this, "error", !0),
        warn: this.push.bind(this, "warn", !0),
        debug: this.push.bind(this, "debug", !0),
        log: this.push.bind(this, "log", !0),
        trace: this.push.bind(this, "trace", !0),
      }),
      (this.boundDrain = () => this.drain()),
      (this.path = o(u(), "logs", this.options.name)),
      console.log("[RollingLogger]", this.options.name, this.path),
      b(this.path, { recursive: !0 }),
      this.initializeLogs(),
      (this.stream = a.createStream(this.computeFilePath(this.index))),
      a.instances.add(this));
  }
  static {
    this.instances = new Set();
  }
  static createStream(t) {
    const e = P(t, { flags: "a" });
    return (
      e.on("error", (s) =>
        console.error("There was an error writing to a logfile", s),
      ),
      e
    );
  }
  static {
    this.buddyOriginOverride = Symbol.for("buddyOriginOverride");
  }
  initializeLogs() {
    const t = (s) => {
        try {
          const i = s.lastIndexOf("-");
          return parseInt(s.substring(i + 1, s.length - 4), 10);
        } catch (i) {
          return (
            this.error(
              "Error getting index for file name when initializing RollingLogger logs:",
              i,
            ),
            0
          );
        }
      },
      e = f(this.path, { withFileTypes: !0 });
    if (e?.length > this.index) {
      const s = e[e.length - 1];
      this.index = t(s.name);
    }
    e.forEach((s) => {
      const i = S(o(this.path, s.name));
      ((this.size += i.size), this.segments.set(t(s.name), i.size));
    });
  }
  info(...t) {
    this.push("info", !1, ...t);
  }
  error(...t) {
    this.push("error", !1, ...t);
  }
  warn(...t) {
    this.push("warn", !1, ...t);
  }
  debug(...t) {
    this.push("debug", !1, ...t);
  }
  log(...t) {
    this.push("log", !1, ...t);
  }
  trace() {
    this.push("trace", !1);
  }
  push(t, e, ...s) {
    const { prefix: i } = this.options;
    (this.pendingEntries.push({
      level: t,
      silently: e,
      args: s,
      computedPrefix: (typeof i == "function" ? i() : i) ?? null,
      timestamp: Date.now(),
      instanceBuddyOrigin: this.buddyOriginOverride,
    }),
      this.drainScheduled ||
        ((this.drainScheduled = !0), setImmediate(this.boundDrain)));
  }
  drain() {
    if (((this.drainScheduled = !1), this.pendingEntries.length === 0)) return;
    const t = this.pendingEntries;
    ((this.pendingEntries = []), this.stream.cork());
    try {
      for (const e of t)
        try {
          this.formatAndWriteEntry(e);
        } catch (s) {
          console.error("Error processing log entry", s);
        }
    } finally {
      process.nextTick(() => this.stream.uncork());
    }
  }
  formatAndWriteEntry(t) {
    const {
        level: e,
        silently: s,
        args: i,
        computedPrefix: h,
        timestamp: n,
        instanceBuddyOrigin: c,
      } = t,
      l = [],
      m = [];
    for (const r of i) {
      if (typeof r == "object" && r != null && a.buddyOriginOverride in r) {
        r[a.buddyOriginOverride];
        continue;
      }
      r instanceof z
        ? (l.push(r.toRedactedString()), m.push(r.toOriginal()))
        : (l.push(r), m.push(r));
    }
    const p = l.map((r) => (typeof r != "string" ? A(r) : r)).join(" "),
      g = h ? `[${e}] [${h}] ${p}` : `[${e}] ${p}`;
    this.writeToDisk(
      g +
        `
`,
    );
  }
  writePreformatted(t, e, s) {
    const { prefix: i } = this.options;
    s?.buddyOrigin ?? this.buddyOriginOverride;
    const h = typeof i == "function" ? i() : i,
      n = h
        ? `[${t}] [${h}] ${e}
`
        : `[${t}] ${e}
`;
    this.writeToDisk(n);
  }
  writeToDisk(t) {
    const { segmentCount: e, byteLimit: s } = this.options,
      i = Buffer.byteLength(t, "utf8"),
      n = (this.segments.get(this.index) ?? 0) + i;
    if (
      ((this.size += i),
      this.segments.set(this.index, n),
      this.stream.write(t),
      n > s / e &&
        (this.index++,
        this.stream.end(),
        (this.stream = a.createStream(this.computeFilePath(this.index)))),
      this.size > s)
    ) {
      const c = this.index - e,
        l = this.segments.get(c);
      l !== void 0 &&
        (k(this.computeFilePath(c)).catch((m) => {
          console.error("Failed to remove old log segment", m);
        }),
        (this.size -= l),
        this.segments.delete(c));
    }
  }
  flush() {
    return (
      this.drain(),
      new Promise((t, e) => {
        if (this.stream.writableFinished || this.stream.destroyed) {
          t();
          return;
        }
        this.stream.write("", (s) => {
          s ? e(s) : t();
        });
      })
    );
  }
  close() {
    return (
      this.drain(),
      a.instances.delete(this),
      new Promise((t) => {
        this.stream.end(t);
      })
    );
  }
  static async flushAll() {
    await Promise.all(Array.from(a.instances).map((t) => t.flush()));
  }
  static async closeAll() {
    await Promise.all(Array.from(a.instances).map((t) => t.close()));
  }
  static async snapshot() {
    await a.flushAll();
    const t = o(u(), "logs"),
      e = o(u(), "dumps");
    try {
      const s = f(t, { withFileTypes: !0 }),
        i = o(e, `dump-${new Date().getTime()}`);
      b(e, { recursive: !0 });
      const h = f(e, { withFileTypes: !0 })
        .filter((n) => n.isDirectory())
        .sort((n, c) => n.name.localeCompare(c.name));
      for (const n of h.slice(0, Math.max(0, h.length - 4)))
        E(o(e, n.name), { recursive: !0 });
      b(i, { recursive: !0 });
      for (const n of s)
        if (n.isFile() && n.name.endsWith(".log"))
          v(o(t, n.name), o(i, n.name));
        else if (n.isDirectory()) {
          const c = o(t, n.name),
            l = o(i, `${n.name}.log`),
            p = f(c).sort((r, y) => {
              const w = r.split("-"),
                x = y.split("-"),
                D = w[w.length - 1].split(".")[0],
                O = x[x.length - 1].split(".")[0];
              return parseInt(D, 10) - parseInt(O, 10);
            });
          let g = "";
          for (const r of p) {
            const y = I(o(c, r), "utf-8");
            g += y;
          }
          F(l, g);
        }
      return i;
    } catch (s) {
      console.error("Failed to dump a compressed snapshot of logs:", s);
    }
  }
  computeFilePath(t) {
    const { name: e } = this.options;
    return o(this.path, `${e}-${t}.log`);
  }
  static nuke() {
    const t = o(u(), "logs"),
      e = f(t, { withFileTypes: !0 }).filter((s) => s.isDirectory());
    for (const s of e) E(o(t, s.name), { recursive: !0 });
  }
  static redactSQL(t) {
    return t.replace(/'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*"/g, "[REDACTED]");
  }
  static markGracefulExit() {
    F(o(u(), "logs", ".exited"), new Uint8Array(0));
  }
  static wasGracefulExit(t = 0) {
    const e = o(u(), "logs", ".exited");
    if (T(e))
      try {
        const { mtimeMs: s } = S(e);
        return ($(e), s >= t - 3e4);
      } catch (s) {
        console.error("Error removing .exited file:", s);
      }
    return !1;
  }
}
const L = (d) =>
  new a({
    name: d,
    byteLimit: 5 * 1024 * 1024,
    segmentCount: 5,
    prefix: () => new Date().toISOString(),
  });
export { a as R, L as c };
//# sourceMappingURL=rolling-logger-C9NTeNo3.mjs.map
