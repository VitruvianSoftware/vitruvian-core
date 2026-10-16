import { a as F } from "./_commonjsHelpers-CBUqixCJ.mjs";
import z from "child_process";
import $ from "path";
import { r as W, a as U, b as V } from "./index-CMOlVndj.mjs";
import Y from "fs";
import C from "node:process";
import { PassThrough as k } from "node:stream";
import { J } from "./index-o5KnLmKX.mjs";
import "os";
import "assert";
import "events";
import "buffer";
import "stream";
import "util";
import "node:events";
import "node:crypto";
import "node:stream/web";
import "node:async_hooks";
import "./Keychain-CHHka2u7.mjs";
import "./constants-BL_pdRyX.mjs";
import "url";
import "./index-DKkZ9dV1.mjs";
import "worker_threads";
import "./util-CrY9x2BW.mjs";
import "./sentry-common-CDPx3Glo.mjs";
import "./package-CIHfweXK.mjs";
import "./sentry-enabled-COAVq6nC.mjs";
import "tty";
import "better-sqlite3";
import "node:url";
import "node:path";
import "./logger-DoW0T1f3.mjs";
import "./startup-checkpoints-BQimOHWq.mjs";
import "./AsyncSqlite-CpInlfQ-.mjs";
import "./machine-id-DFkLVgcU.mjs";
import "perf_hooks";
import "./index-CNG_AM8w.mjs";
import "timers/promises";
import "async_hooks";
import "fs/promises";
import "./index-B_PiTES1.mjs";
import "node:util";
import "node:child_process";
import "node:os";
import "node:fs";
import "node:module";
import "./index-BJhQkpW6.mjs";
import "crypto";
import "http";
import "zlib";
import "https";
import "net";
import "tls";
import "stream/promises";
import "node:fs/promises";
import "./index-C7dxdDjs.mjs";
import "node:string_decoder";
import "./index-DaNOOrJg.mjs";
import "./utils-D8MokWSu.mjs";
import "./index-BiKiNEmj.mjs";
import "./register-proxy-7lV9pun2.mjs";
import "domain";
import "./index-BiHJsdYm.mjs";
import "./rolling-logger-C9NTeNo3.mjs";
import "./got-_wC7Q_ix.mjs";
import "dns";
import "http2";
import "module";
import "./index-8JaOpgio.mjs";
import "node:worker_threads";
import "./index-Bo2CLT1C.mjs";
import "node:timers";
import "./client-DMtubo6I.mjs";
(function () {
  try {
    var s =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    s.SENTRY_RELEASE = { id: "4.3.209" };
    var t = new s.Error().stack;
    t &&
      ((s._sentryDebugIds = s._sentryDebugIds || {}),
      (s._sentryDebugIds[t] = "82117403-6c25-423d-a22d-36f0a17c07e3"),
      (s._sentryDebugIdIdentifier =
        "sentry-dbid-82117403-6c25-423d-a22d-36f0a17c07e3"));
  } catch {}
})();
var S = { exports: {} },
  P,
  q;
function G() {
  if (q) return P;
  q = 1;
  const s =
      process.platform === "win32" ||
      process.env.OSTYPE === "cygwin" ||
      process.env.OSTYPE === "msys",
    t = $,
    i = s ? ";" : ":",
    n = W(),
    u = (o) => Object.assign(new Error(`not found: ${o}`), { code: "ENOENT" }),
    c = (o, r) => {
      const e = r.colon || i,
        l =
          o.match(/\//) || (s && o.match(/\\/))
            ? [""]
            : [
                ...(s ? [process.cwd()] : []),
                ...(r.path || process.env.PATH || "").split(e),
              ],
        m = s ? r.pathExt || process.env.PATHEXT || ".EXE;.CMD;.BAT;.COM" : "",
        f = s ? m.split(e) : [""];
      return (
        s && o.indexOf(".") !== -1 && f[0] !== "" && f.unshift(""),
        { pathEnv: l, pathExt: f, pathExtExe: m }
      );
    },
    a = (o, r, e) => {
      (typeof r == "function" && ((e = r), (r = {})), r || (r = {}));
      const { pathEnv: l, pathExt: m, pathExtExe: f } = c(o, r),
        v = [],
        _ = (h) =>
          new Promise((w, E) => {
            if (h === l.length) return r.all && v.length ? w(v) : E(u(o));
            const d = l[h],
              g = /^".*"$/.test(d) ? d.slice(1, -1) : d,
              b = t.join(g, o),
              R = !g && /^\.[\\\/]/.test(o) ? o.slice(0, 2) + b : b;
            w(y(R, h, 0));
          }),
        y = (h, w, E) =>
          new Promise((d, g) => {
            if (E === m.length) return d(_(w + 1));
            const b = m[E];
            n(h + b, { pathExt: f }, (R, L) => {
              if (!R && L)
                if (r.all) v.push(h + b);
                else return d(h + b);
              return d(y(h, w, E + 1));
            });
          });
      return e ? _(0).then((h) => e(null, h), e) : _(0);
    },
    p = (o, r) => {
      r = r || {};
      const { pathEnv: e, pathExt: l, pathExtExe: m } = c(o, r),
        f = [];
      for (let v = 0; v < e.length; v++) {
        const _ = e[v],
          y = /^".*"$/.test(_) ? _.slice(1, -1) : _,
          h = t.join(y, o),
          w = !y && /^\.[\\\/]/.test(o) ? o.slice(0, 2) + h : h;
        for (let E = 0; E < l.length; E++) {
          const d = w + l[E];
          try {
            if (n.sync(d, { pathExt: m }))
              if (r.all) f.push(d);
              else return d;
          } catch {}
        }
      }
      if (r.all && f.length) return f;
      if (r.nothrow) return null;
      throw u(o);
    };
  return ((P = a), (a.sync = p), P);
}
var T, M;
function K() {
  if (M) return T;
  M = 1;
  const s = $,
    t = G(),
    i = U();
  function n(c, a) {
    const p = c.options.env || process.env,
      o = process.cwd(),
      r = c.options.cwd != null,
      e = r && process.chdir !== void 0 && !process.chdir.disabled;
    if (e)
      try {
        process.chdir(c.options.cwd);
      } catch {}
    let l;
    try {
      l = t.sync(c.command, {
        path: p[i({ env: p })],
        pathExt: a ? s.delimiter : void 0,
      });
    } catch {
    } finally {
      e && process.chdir(o);
    }
    return (l && (l = s.resolve(r ? c.options.cwd : "", l)), l);
  }
  function u(c) {
    return n(c) || n(c, !0);
  }
  return ((T = u), T);
}
var x = {},
  I;
function X() {
  if (I) return x;
  I = 1;
  const s = /([()\][%!^"`<>&|;, *?])/g;
  function t(n) {
    return ((n = n.replace(s, "^$1")), n);
  }
  function i(n, u) {
    return (
      (n = `${n}`),
      (n = n.replace(/(?=(\\+?)?)\1"/g, '$1$1\\"')),
      (n = n.replace(/(?=(\\+?)?)\1$/, "$1$1")),
      (n = `"${n}"`),
      (n = n.replace(s, "^$1")),
      u && (n = n.replace(s, "^$1")),
      n
    );
  }
  return ((x.command = t), (x.argument = i), x);
}
var O, D;
function Q() {
  if (D) return O;
  D = 1;
  const s = Y,
    t = V();
  function i(n) {
    const c = Buffer.alloc(150);
    let a;
    try {
      ((a = s.openSync(n, "r")), s.readSync(a, c, 0, 150, 0), s.closeSync(a));
    } catch {}
    return t(c.toString());
  }
  return ((O = i), O);
}
var A, H;
function Z() {
  if (H) return A;
  H = 1;
  const s = $,
    t = K(),
    i = X(),
    n = Q(),
    u = process.platform === "win32",
    c = /\.(?:com|exe)$/i,
    a = /node_modules[\\/].bin[\\/][^\\/]+\.cmd$/i;
  function p(e) {
    e.file = t(e);
    const l = e.file && n(e.file);
    return l ? (e.args.unshift(e.file), (e.command = l), t(e)) : e.file;
  }
  function o(e) {
    if (!u) return e;
    const l = p(e),
      m = !c.test(l);
    if (e.options.forceShell || m) {
      const f = a.test(l);
      ((e.command = s.normalize(e.command)),
        (e.command = i.command(e.command)),
        (e.args = e.args.map((_) => i.argument(_, f))));
      const v = [e.command].concat(e.args).join(" ");
      ((e.args = ["/d", "/s", "/c", `"${v}"`]),
        (e.command = process.env.comspec || "cmd.exe"),
        (e.options.windowsVerbatimArguments = !0));
    }
    return e;
  }
  function r(e, l, m) {
    (l && !Array.isArray(l) && ((m = l), (l = null)),
      (l = l ? l.slice(0) : []),
      (m = Object.assign({}, m)));
    const f = {
      command: e,
      args: l,
      options: m,
      file: void 0,
      original: { command: e, args: l },
    };
    return m.shell ? f : o(f);
  }
  return ((A = r), A);
}
var N, j;
function tt() {
  if (j) return N;
  j = 1;
  const s = process.platform === "win32";
  function t(c, a) {
    return Object.assign(new Error(`${a} ${c.command} ENOENT`), {
      code: "ENOENT",
      errno: "ENOENT",
      syscall: `${a} ${c.command}`,
      path: c.command,
      spawnargs: c.args,
    });
  }
  function i(c, a) {
    if (!s) return;
    const p = c.emit;
    c.emit = function (o, r) {
      if (o === "exit") {
        const e = n(r, a);
        if (e) return p.call(c, "error", e);
      }
      return p.apply(c, arguments);
    };
  }
  function n(c, a) {
    return s && c === 1 && !a.file ? t(a.original, "spawn") : null;
  }
  function u(c, a) {
    return s && c === 1 && !a.file ? t(a.original, "spawnSync") : null;
  }
  return (
    (N = {
      hookChildProcess: i,
      verifyENOENT: n,
      verifyENOENTSync: u,
      notFoundError: t,
    }),
    N
  );
}
var B;
function rt() {
  if (B) return S.exports;
  B = 1;
  const s = z,
    t = Z(),
    i = tt();
  function n(c, a, p) {
    const o = t(c, a, p),
      r = s.spawn(o.command, o.args, o.options);
    return (i.hookChildProcess(r, o), r);
  }
  function u(c, a, p) {
    const o = t(c, a, p),
      r = s.spawnSync(o.command, o.args, o.options);
    return ((r.error = r.error || i.verifyENOENTSync(r.status, o)), r);
  }
  return (
    (S.exports = n),
    (S.exports.spawn = n),
    (S.exports.sync = u),
    (S.exports._parse = t),
    (S.exports._enoent = i),
    S.exports
  );
}
var et = rt();
const nt = F(et);
class ot {
  append(t) {
    this._buffer = this._buffer ? Buffer.concat([this._buffer, t]) : t;
  }
  readMessage() {
    if (!this._buffer) return null;
    const t = this._buffer.indexOf(`
`);
    if (t === -1) return null;
    const i = this._buffer.toString("utf8", 0, t).replace(/\r$/, "");
    return ((this._buffer = this._buffer.subarray(t + 1)), st(i));
  }
  clear() {
    this._buffer = void 0;
  }
}
function st(s) {
  return J.parse(JSON.parse(s));
}
function it(s) {
  return (
    JSON.stringify(s) +
    `
`
  );
}
const ct =
  C.platform === "win32"
    ? [
        "APPDATA",
        "HOMEDRIVE",
        "HOMEPATH",
        "LOCALAPPDATA",
        "PATH",
        "PROCESSOR_ARCHITECTURE",
        "SYSTEMDRIVE",
        "SYSTEMROOT",
        "TEMP",
        "USERNAME",
        "USERPROFILE",
        "PROGRAMFILES",
      ]
    : ["HOME", "LOGNAME", "PATH", "SHELL", "TERM", "USER"];
function at() {
  const s = {};
  for (const t of ct) {
    const i = C.env[t];
    i !== void 0 && (i.startsWith("()") || (s[t] = i));
  }
  return s;
}
class Or {
  constructor(t) {
    ((this._abortController = new AbortController()),
      (this._readBuffer = new ot()),
      (this._stderrStream = null),
      (this._serverParams = t),
      (t.stderr === "pipe" || t.stderr === "overlapped") &&
        (this._stderrStream = new k()));
  }
  async start() {
    if (this._process)
      throw new Error(
        "StdioClientTransport already started! If using Client class, note that connect() calls start() automatically.",
      );
    return new Promise((t, i) => {
      var n, u, c, a, p;
      ((this._process = nt(
        this._serverParams.command,
        (n = this._serverParams.args) !== null && n !== void 0 ? n : [],
        {
          env: { ...at(), ...this._serverParams.env },
          stdio: [
            "pipe",
            "pipe",
            (u = this._serverParams.stderr) !== null && u !== void 0
              ? u
              : "inherit",
          ],
          shell: !1,
          signal: this._abortController.signal,
          windowsHide: C.platform === "win32" && lt(),
          cwd: this._serverParams.cwd,
        },
      )),
        this._process.on("error", (o) => {
          var r, e;
          if (o.name === "AbortError") {
            (r = this.onclose) === null || r === void 0 || r.call(this);
            return;
          }
          (i(o),
            (e = this.onerror) === null || e === void 0 || e.call(this, o));
        }),
        this._process.on("spawn", () => {
          t();
        }),
        this._process.on("close", (o) => {
          var r;
          ((this._process = void 0),
            (r = this.onclose) === null || r === void 0 || r.call(this));
        }),
        (c = this._process.stdin) === null ||
          c === void 0 ||
          c.on("error", (o) => {
            var r;
            (r = this.onerror) === null || r === void 0 || r.call(this, o);
          }),
        (a = this._process.stdout) === null ||
          a === void 0 ||
          a.on("data", (o) => {
            (this._readBuffer.append(o), this.processReadBuffer());
          }),
        (p = this._process.stdout) === null ||
          p === void 0 ||
          p.on("error", (o) => {
            var r;
            (r = this.onerror) === null || r === void 0 || r.call(this, o);
          }),
        this._stderrStream &&
          this._process.stderr &&
          this._process.stderr.pipe(this._stderrStream));
    });
  }
  get stderr() {
    var t, i;
    return this._stderrStream
      ? this._stderrStream
      : (i =
            (t = this._process) === null || t === void 0
              ? void 0
              : t.stderr) !== null && i !== void 0
        ? i
        : null;
  }
  get pid() {
    var t, i;
    return (i =
      (t = this._process) === null || t === void 0 ? void 0 : t.pid) !== null &&
      i !== void 0
      ? i
      : null;
  }
  processReadBuffer() {
    for (var t, i; ;)
      try {
        const n = this._readBuffer.readMessage();
        if (n === null) break;
        (t = this.onmessage) === null || t === void 0 || t.call(this, n);
      } catch (n) {
        (i = this.onerror) === null || i === void 0 || i.call(this, n);
      }
  }
  async close() {
    (this._abortController.abort(),
      (this._process = void 0),
      this._readBuffer.clear());
  }
  send(t) {
    return new Promise((i) => {
      var n;
      if (!(!((n = this._process) === null || n === void 0) && n.stdin))
        throw new Error("Not connected");
      const u = it(t);
      this._process.stdin.write(u) ? i() : this._process.stdin.once("drain", i);
    });
  }
}
function lt() {
  return "type" in C;
}
export {
  ct as DEFAULT_INHERITED_ENV_VARS,
  Or as StdioClientTransport,
  at as getDefaultEnvironment,
};
//# sourceMappingURL=stdio-DSoBbdMS.mjs.map
