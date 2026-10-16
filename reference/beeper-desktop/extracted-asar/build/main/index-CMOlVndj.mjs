import { c as q, a as vt } from "./_commonjsHelpers-CBUqixCJ.mjs";
import K from "path";
import dt from "child_process";
import Ee from "fs";
import we from "os";
import xt from "assert";
import yt from "events";
import bt from "buffer";
import Ie from "stream";
import Et from "util";
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
      (t._sentryDebugIds[r] = "c10d2e89-7ceb-46b1-8eec-22c99f49e24f"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-c10d2e89-7ceb-46b1-8eec-22c99f49e24f"));
  } catch {}
})();
var $ = { exports: {} },
  A = { exports: {} },
  ne,
  qe;
function wt() {
  if (qe) return ne;
  ((qe = 1), (ne = i), (i.sync = s));
  var t = Ee;
  function r(n, e) {
    var u = e.pathExt !== void 0 ? e.pathExt : process.env.PATHEXT;
    if (!u || ((u = u.split(";")), u.indexOf("") !== -1)) return !0;
    for (var o = 0; o < u.length; o++) {
      var a = u[o].toLowerCase();
      if (a && n.substr(-a.length).toLowerCase() === a) return !0;
    }
    return !1;
  }
  function d(n, e, u) {
    return !n.isSymbolicLink() && !n.isFile() ? !1 : r(e, u);
  }
  function i(n, e, u) {
    t.stat(n, function (o, a) {
      u(o, o ? !1 : d(a, n, e));
    });
  }
  function s(n, e) {
    return d(t.statSync(n), n, e);
  }
  return ne;
}
var re, $e;
function It() {
  if ($e) return re;
  (($e = 1), (re = r), (r.sync = d));
  var t = Ee;
  function r(n, e, u) {
    t.stat(n, function (o, a) {
      u(o, o ? !1 : i(a, e));
    });
  }
  function d(n, e) {
    return i(t.statSync(n), e);
  }
  function i(n, e) {
    return n.isFile() && s(n, e);
  }
  function s(n, e) {
    var u = n.mode,
      o = n.uid,
      a = n.gid,
      c = e.uid !== void 0 ? e.uid : process.getuid && process.getuid(),
      f = e.gid !== void 0 ? e.gid : process.getgid && process.getgid(),
      h = parseInt("100", 8),
      l = parseInt("010", 8),
      p = parseInt("001", 8),
      g = h | l,
      m =
        u & p || (u & l && a === f) || (u & h && o === c) || (u & g && c === 0);
    return m;
  }
  return re;
}
var ie, Ae;
function Rt() {
  if (Ae) return ie;
  Ae = 1;
  var t;
  (process.platform === "win32" || q.TESTING_WINDOWS ? (t = wt()) : (t = It()),
    (ie = r),
    (r.sync = d));
  function r(i, s, n) {
    if ((typeof s == "function" && ((n = s), (s = {})), !n)) {
      if (typeof Promise != "function")
        throw new TypeError("callback not provided");
      return new Promise(function (e, u) {
        r(i, s || {}, function (o, a) {
          o ? u(o) : e(a);
        });
      });
    }
    t(i, s || {}, function (e, u) {
      (e &&
        (e.code === "EACCES" || (s && s.ignoreErrors)) &&
        ((e = null), (u = !1)),
        n(e, u));
    });
  }
  function d(i, s) {
    try {
      return t.sync(i, s || {});
    } catch (n) {
      if ((s && s.ignoreErrors) || n.code === "EACCES") return !1;
      throw n;
    }
  }
  return ie;
}
var oe, _e;
function Pt() {
  if (_e) return oe;
  _e = 1;
  const t =
      process.platform === "win32" ||
      process.env.OSTYPE === "cygwin" ||
      process.env.OSTYPE === "msys",
    r = K,
    d = t ? ";" : ":",
    i = Rt(),
    s = (o) => Object.assign(new Error(`not found: ${o}`), { code: "ENOENT" }),
    n = (o, a) => {
      const c = a.colon || d,
        f =
          o.match(/\//) || (t && o.match(/\\/))
            ? [""]
            : [
                ...(t ? [process.cwd()] : []),
                ...(a.path || process.env.PATH || "").split(c),
              ],
        h = t ? a.pathExt || process.env.PATHEXT || ".EXE;.CMD;.BAT;.COM" : "",
        l = t ? h.split(c) : [""];
      return (
        t && o.indexOf(".") !== -1 && l[0] !== "" && l.unshift(""),
        { pathEnv: f, pathExt: l, pathExtExe: h }
      );
    },
    e = (o, a, c) => {
      (typeof a == "function" && ((c = a), (a = {})), a || (a = {}));
      const { pathEnv: f, pathExt: h, pathExtExe: l } = n(o, a),
        p = [],
        g = (S) =>
          new Promise((x, E) => {
            if (S === f.length) return a.all && p.length ? x(p) : E(s(o));
            const R = f[S],
              P = /^".*"$/.test(R) ? R.slice(1, -1) : R,
              G = r.join(P, o),
              L = !P && /^\.[\\\/]/.test(o) ? o.slice(0, 2) + G : G;
            x(m(L, S, 0));
          }),
        m = (S, x, E) =>
          new Promise((R, P) => {
            if (E === h.length) return R(g(x + 1));
            const G = h[E];
            i(S + G, { pathExt: l }, (L, H) => {
              if (!L && H)
                if (a.all) p.push(S + G);
                else return R(S + G);
              return R(m(S, x, E + 1));
            });
          });
      return c ? g(0).then((S) => c(null, S), c) : g(0);
    },
    u = (o, a) => {
      a = a || {};
      const { pathEnv: c, pathExt: f, pathExtExe: h } = n(o, a),
        l = [];
      for (let p = 0; p < c.length; p++) {
        const g = c[p],
          m = /^".*"$/.test(g) ? g.slice(1, -1) : g,
          S = r.join(m, o),
          x = !m && /^\.[\\\/]/.test(o) ? o.slice(0, 2) + S : S;
        for (let E = 0; E < f.length; E++) {
          const R = x + f[E];
          try {
            if (i.sync(R, { pathExt: h }))
              if (a.all) l.push(R);
              else return R;
          } catch {}
        }
      }
      if (a.all && l.length) return l;
      if (a.nothrow) return null;
      throw s(o);
    };
  return ((oe = e), (e.sync = u), oe);
}
var Q = { exports: {} },
  Oe;
function lt() {
  if (Oe) return Q.exports;
  Oe = 1;
  const t = (r = {}) => {
    const d = r.env || process.env;
    return (r.platform || process.platform) !== "win32"
      ? "PATH"
      : Object.keys(d)
          .reverse()
          .find((s) => s.toUpperCase() === "PATH") || "Path";
  };
  return ((Q.exports = t), (Q.exports.default = t), Q.exports);
}
var se, Ne;
function Tt() {
  if (Ne) return se;
  Ne = 1;
  const t = K,
    r = Pt(),
    d = lt();
  function i(n, e) {
    const u = n.options.env || process.env,
      o = process.cwd(),
      a = n.options.cwd != null,
      c = a && process.chdir !== void 0 && !process.chdir.disabled;
    if (c)
      try {
        process.chdir(n.options.cwd);
      } catch {}
    let f;
    try {
      f = r.sync(n.command, {
        path: u[d({ env: u })],
        pathExt: e ? t.delimiter : void 0,
      });
    } catch {
    } finally {
      c && process.chdir(o);
    }
    return (f && (f = t.resolve(a ? n.options.cwd : "", f)), f);
  }
  function s(n) {
    return i(n) || i(n, !0);
  }
  return ((se = s), se);
}
var Z = {},
  Me;
function Ct() {
  if (Me) return Z;
  Me = 1;
  const t = /([()\][%!^"`<>&|;, *?])/g;
  function r(i) {
    return ((i = i.replace(t, "^$1")), i);
  }
  function d(i, s) {
    return (
      (i = `${i}`),
      (i = i.replace(/(\\*)"/g, '$1$1\\"')),
      (i = i.replace(/(\\*)$/, "$1$1")),
      (i = `"${i}"`),
      (i = i.replace(t, "^$1")),
      s && (i = i.replace(t, "^$1")),
      i
    );
  }
  return ((Z.command = r), (Z.argument = d), Z);
}
var ae, ke;
function Gt() {
  return (ke || ((ke = 1), (ae = /^#!(.*)/)), ae);
}
var ce, Be;
function qt() {
  if (Be) return ce;
  Be = 1;
  const t = Gt();
  return (
    (ce = (r = "") => {
      const d = r.match(t);
      if (!d) return null;
      const [i, s] = d[0].replace(/#! ?/, "").split(" "),
        n = i.split("/").pop();
      return n === "env" ? s : s ? `${n} ${s}` : n;
    }),
    ce
  );
}
var ue, Le;
function $t() {
  if (Le) return ue;
  Le = 1;
  const t = Ee,
    r = qt();
  function d(i) {
    const n = Buffer.alloc(150);
    let e;
    try {
      ((e = t.openSync(i, "r")), t.readSync(e, n, 0, 150, 0), t.closeSync(e));
    } catch {}
    return r(n.toString());
  }
  return ((ue = d), ue);
}
var de, je;
function At() {
  if (je) return de;
  je = 1;
  const t = K,
    r = Tt(),
    d = Ct(),
    i = $t(),
    s = process.platform === "win32",
    n = /\.(?:com|exe)$/i,
    e = /node_modules[\\/].bin[\\/][^\\/]+\.cmd$/i;
  function u(c) {
    c.file = r(c);
    const f = c.file && i(c.file);
    return f ? (c.args.unshift(c.file), (c.command = f), r(c)) : c.file;
  }
  function o(c) {
    if (!s) return c;
    const f = u(c),
      h = !n.test(f);
    if (c.options.forceShell || h) {
      const l = e.test(f);
      ((c.command = t.normalize(c.command)),
        (c.command = d.command(c.command)),
        (c.args = c.args.map((g) => d.argument(g, l))));
      const p = [c.command].concat(c.args).join(" ");
      ((c.args = ["/d", "/s", "/c", `"${p}"`]),
        (c.command = process.env.comspec || "cmd.exe"),
        (c.options.windowsVerbatimArguments = !0));
    }
    return c;
  }
  function a(c, f, h) {
    (f && !Array.isArray(f) && ((h = f), (f = null)),
      (f = f ? f.slice(0) : []),
      (h = Object.assign({}, h)));
    const l = {
      command: c,
      args: f,
      options: h,
      file: void 0,
      original: { command: c, args: f },
    };
    return h.shell ? l : o(l);
  }
  return ((de = a), de);
}
var le, Fe;
function _t() {
  if (Fe) return le;
  Fe = 1;
  const t = process.platform === "win32";
  function r(n, e) {
    return Object.assign(new Error(`${e} ${n.command} ENOENT`), {
      code: "ENOENT",
      errno: "ENOENT",
      syscall: `${e} ${n.command}`,
      path: n.command,
      spawnargs: n.args,
    });
  }
  function d(n, e) {
    if (!t) return;
    const u = n.emit;
    n.emit = function (o, a) {
      if (o === "exit") {
        const c = i(a, e);
        if (c) return u.call(n, "error", c);
      }
      return u.apply(n, arguments);
    };
  }
  function i(n, e) {
    return t && n === 1 && !e.file ? r(e.original, "spawn") : null;
  }
  function s(n, e) {
    return t && n === 1 && !e.file ? r(e.original, "spawnSync") : null;
  }
  return (
    (le = {
      hookChildProcess: d,
      verifyENOENT: i,
      verifyENOENTSync: s,
      notFoundError: r,
    }),
    le
  );
}
var Ue;
function Ot() {
  if (Ue) return A.exports;
  Ue = 1;
  const t = dt,
    r = At(),
    d = _t();
  function i(n, e, u) {
    const o = r(n, e, u),
      a = t.spawn(o.command, o.args, o.options);
    return (d.hookChildProcess(a, o), a);
  }
  function s(n, e, u) {
    const o = r(n, e, u),
      a = t.spawnSync(o.command, o.args, o.options);
    return ((a.error = a.error || d.verifyENOENTSync(a.status, o)), a);
  }
  return (
    (A.exports = i),
    (A.exports.spawn = i),
    (A.exports.sync = s),
    (A.exports._parse = r),
    (A.exports._enoent = d),
    A.exports
  );
}
var fe, De;
function Nt() {
  return (
    De ||
      ((De = 1),
      (fe = (t) => {
        const r =
            typeof t == "string"
              ? `
`
              : 10,
          d = typeof t == "string" ? "\r" : 13;
        return (
          t[t.length - 1] === r && (t = t.slice(0, t.length - 1)),
          t[t.length - 1] === d && (t = t.slice(0, t.length - 1)),
          t
        );
      })),
    fe
  );
}
var te = { exports: {} };
te.exports;
var Ke;
function Mt() {
  return (
    Ke ||
      ((Ke = 1),
      (function (t) {
        const r = K,
          d = lt(),
          i = (s) => {
            s = {
              cwd: process.cwd(),
              path: process.env[d()],
              execPath: process.execPath,
              ...s,
            };
            let n,
              e = r.resolve(s.cwd);
            const u = [];
            for (; n !== e;)
              (u.push(r.join(e, "node_modules/.bin")),
                (n = e),
                (e = r.resolve(e, "..")));
            const o = r.resolve(s.cwd, s.execPath, "..");
            return (u.push(o), u.concat(s.path).join(r.delimiter));
          };
        ((t.exports = i),
          (t.exports.default = i),
          (t.exports.env = (s) => {
            s = { env: process.env, ...s };
            const n = { ...s.env },
              e = d({ env: n });
            return ((s.path = n[e]), (n[e] = t.exports(s)), n);
          }));
      })(te)),
    te.exports
  );
}
var F = { exports: {} },
  J = { exports: {} },
  He;
function kt() {
  if (He) return J.exports;
  He = 1;
  const t = (r, d) => {
    for (const i of Reflect.ownKeys(d))
      Object.defineProperty(r, i, Object.getOwnPropertyDescriptor(d, i));
    return r;
  };
  return ((J.exports = t), (J.exports.default = t), J.exports);
}
var We;
function Bt() {
  if (We) return F.exports;
  We = 1;
  const t = kt(),
    r = new WeakMap(),
    d = (i, s = {}) => {
      if (typeof i != "function") throw new TypeError("Expected a function");
      let n,
        e = 0;
      const u = i.displayName || i.name || "<anonymous>",
        o = function (...a) {
          if ((r.set(o, ++e), e === 1)) ((n = i.apply(this, a)), (i = null));
          else if (s.throw === !0)
            throw new Error(`Function \`${u}\` can only be called once`);
          return n;
        };
      return (t(o, i), r.set(o, e), o);
    };
  return (
    (F.exports = d),
    (F.exports.default = d),
    (F.exports.callCount = (i) => {
      if (!r.has(i))
        throw new Error(
          `The given function \`${i.name}\` is not wrapped by the \`onetime\` package`,
        );
      return r.get(i);
    }),
    F.exports
  );
}
var _ = {},
  U = {},
  D = {},
  Xe;
function Lt() {
  if (Xe) return D;
  ((Xe = 1),
    Object.defineProperty(D, "__esModule", { value: !0 }),
    (D.SIGNALS = void 0));
  const t = [
    {
      name: "SIGHUP",
      number: 1,
      action: "terminate",
      description: "Terminal closed",
      standard: "posix",
    },
    {
      name: "SIGINT",
      number: 2,
      action: "terminate",
      description: "User interruption with CTRL-C",
      standard: "ansi",
    },
    {
      name: "SIGQUIT",
      number: 3,
      action: "core",
      description: "User interruption with CTRL-\\",
      standard: "posix",
    },
    {
      name: "SIGILL",
      number: 4,
      action: "core",
      description: "Invalid machine instruction",
      standard: "ansi",
    },
    {
      name: "SIGTRAP",
      number: 5,
      action: "core",
      description: "Debugger breakpoint",
      standard: "posix",
    },
    {
      name: "SIGABRT",
      number: 6,
      action: "core",
      description: "Aborted",
      standard: "ansi",
    },
    {
      name: "SIGIOT",
      number: 6,
      action: "core",
      description: "Aborted",
      standard: "bsd",
    },
    {
      name: "SIGBUS",
      number: 7,
      action: "core",
      description:
        "Bus error due to misaligned, non-existing address or paging error",
      standard: "bsd",
    },
    {
      name: "SIGEMT",
      number: 7,
      action: "terminate",
      description: "Command should be emulated but is not implemented",
      standard: "other",
    },
    {
      name: "SIGFPE",
      number: 8,
      action: "core",
      description: "Floating point arithmetic error",
      standard: "ansi",
    },
    {
      name: "SIGKILL",
      number: 9,
      action: "terminate",
      description: "Forced termination",
      standard: "posix",
      forced: !0,
    },
    {
      name: "SIGUSR1",
      number: 10,
      action: "terminate",
      description: "Application-specific signal",
      standard: "posix",
    },
    {
      name: "SIGSEGV",
      number: 11,
      action: "core",
      description: "Segmentation fault",
      standard: "ansi",
    },
    {
      name: "SIGUSR2",
      number: 12,
      action: "terminate",
      description: "Application-specific signal",
      standard: "posix",
    },
    {
      name: "SIGPIPE",
      number: 13,
      action: "terminate",
      description: "Broken pipe or socket",
      standard: "posix",
    },
    {
      name: "SIGALRM",
      number: 14,
      action: "terminate",
      description: "Timeout or timer",
      standard: "posix",
    },
    {
      name: "SIGTERM",
      number: 15,
      action: "terminate",
      description: "Termination",
      standard: "ansi",
    },
    {
      name: "SIGSTKFLT",
      number: 16,
      action: "terminate",
      description: "Stack is empty or overflowed",
      standard: "other",
    },
    {
      name: "SIGCHLD",
      number: 17,
      action: "ignore",
      description: "Child process terminated, paused or unpaused",
      standard: "posix",
    },
    {
      name: "SIGCLD",
      number: 17,
      action: "ignore",
      description: "Child process terminated, paused or unpaused",
      standard: "other",
    },
    {
      name: "SIGCONT",
      number: 18,
      action: "unpause",
      description: "Unpaused",
      standard: "posix",
      forced: !0,
    },
    {
      name: "SIGSTOP",
      number: 19,
      action: "pause",
      description: "Paused",
      standard: "posix",
      forced: !0,
    },
    {
      name: "SIGTSTP",
      number: 20,
      action: "pause",
      description: 'Paused using CTRL-Z or "suspend"',
      standard: "posix",
    },
    {
      name: "SIGTTIN",
      number: 21,
      action: "pause",
      description: "Background process cannot read terminal input",
      standard: "posix",
    },
    {
      name: "SIGBREAK",
      number: 21,
      action: "terminate",
      description: "User interruption with CTRL-BREAK",
      standard: "other",
    },
    {
      name: "SIGTTOU",
      number: 22,
      action: "pause",
      description: "Background process cannot write to terminal output",
      standard: "posix",
    },
    {
      name: "SIGURG",
      number: 23,
      action: "ignore",
      description: "Socket received out-of-band data",
      standard: "bsd",
    },
    {
      name: "SIGXCPU",
      number: 24,
      action: "core",
      description: "Process timed out",
      standard: "bsd",
    },
    {
      name: "SIGXFSZ",
      number: 25,
      action: "core",
      description: "File too big",
      standard: "bsd",
    },
    {
      name: "SIGVTALRM",
      number: 26,
      action: "terminate",
      description: "Timeout or timer",
      standard: "bsd",
    },
    {
      name: "SIGPROF",
      number: 27,
      action: "terminate",
      description: "Timeout or timer",
      standard: "bsd",
    },
    {
      name: "SIGWINCH",
      number: 28,
      action: "ignore",
      description: "Terminal window size changed",
      standard: "bsd",
    },
    {
      name: "SIGIO",
      number: 29,
      action: "terminate",
      description: "I/O is available",
      standard: "other",
    },
    {
      name: "SIGPOLL",
      number: 29,
      action: "terminate",
      description: "Watched event",
      standard: "other",
    },
    {
      name: "SIGINFO",
      number: 29,
      action: "ignore",
      description: "Request for process information",
      standard: "other",
    },
    {
      name: "SIGPWR",
      number: 30,
      action: "terminate",
      description: "Device running out of power",
      standard: "systemv",
    },
    {
      name: "SIGSYS",
      number: 31,
      action: "core",
      description: "Invalid system call",
      standard: "other",
    },
    {
      name: "SIGUNUSED",
      number: 31,
      action: "terminate",
      description: "Invalid system call",
      standard: "other",
    },
  ];
  return ((D.SIGNALS = t), D);
}
var O = {},
  ze;
function ft() {
  if (ze) return O;
  ((ze = 1),
    Object.defineProperty(O, "__esModule", { value: !0 }),
    (O.SIGRTMAX = O.getRealtimeSignals = void 0));
  const t = function () {
    const s = i - d + 1;
    return Array.from({ length: s }, r);
  };
  O.getRealtimeSignals = t;
  const r = function (s, n) {
      return {
        name: `SIGRT${n + 1}`,
        number: d + n,
        action: "terminate",
        description: "Application-specific signal (realtime)",
        standard: "posix",
      };
    },
    d = 34,
    i = 64;
  return ((O.SIGRTMAX = i), O);
}
var Ve;
function jt() {
  if (Ve) return U;
  ((Ve = 1),
    Object.defineProperty(U, "__esModule", { value: !0 }),
    (U.getSignals = void 0));
  var t = we,
    r = Lt(),
    d = ft();
  const i = function () {
    const n = (0, d.getRealtimeSignals)();
    return [...r.SIGNALS, ...n].map(s);
  };
  U.getSignals = i;
  const s = function ({
    name: n,
    number: e,
    description: u,
    action: o,
    forced: a = !1,
    standard: c,
  }) {
    const {
        signals: { [n]: f },
      } = t.constants,
      h = f !== void 0;
    return {
      name: n,
      number: h ? f : e,
      description: u,
      supported: h,
      action: o,
      forced: a,
      standard: c,
    };
  };
  return U;
}
var Ye;
function Ft() {
  if (Ye) return _;
  ((Ye = 1),
    Object.defineProperty(_, "__esModule", { value: !0 }),
    (_.signalsByNumber = _.signalsByName = void 0));
  var t = we,
    r = jt(),
    d = ft();
  const i = function () {
      return (0, r.getSignals)().reduce(s, {});
    },
    s = function (
      c,
      {
        name: f,
        number: h,
        description: l,
        supported: p,
        action: g,
        forced: m,
        standard: S,
      },
    ) {
      return {
        ...c,
        [f]: {
          name: f,
          number: h,
          description: l,
          supported: p,
          action: g,
          forced: m,
          standard: S,
        },
      };
    },
    n = i();
  _.signalsByName = n;
  const e = function () {
      const c = (0, r.getSignals)(),
        f = d.SIGRTMAX + 1,
        h = Array.from({ length: f }, (l, p) => u(p, c));
      return Object.assign({}, ...h);
    },
    u = function (c, f) {
      const h = o(c, f);
      if (h === void 0) return {};
      const {
        name: l,
        description: p,
        supported: g,
        action: m,
        forced: S,
        standard: x,
      } = h;
      return {
        [c]: {
          name: l,
          number: c,
          description: p,
          supported: g,
          action: m,
          forced: S,
          standard: x,
        },
      };
    },
    o = function (c, f) {
      const h = f.find(({ name: l }) => t.constants.signals[l] === c);
      return h !== void 0 ? h : f.find((l) => l.number === c);
    },
    a = e();
  return ((_.signalsByNumber = a), _);
}
var me, Qe;
function Ut() {
  if (Qe) return me;
  Qe = 1;
  const { signalsByName: t } = Ft(),
    r = ({
      timedOut: i,
      timeout: s,
      errorCode: n,
      signal: e,
      signalDescription: u,
      exitCode: o,
      isCanceled: a,
    }) =>
      i
        ? `timed out after ${s} milliseconds`
        : a
          ? "was canceled"
          : n !== void 0
            ? `failed with ${n}`
            : e !== void 0
              ? `was killed with ${e} (${u})`
              : o !== void 0
                ? `failed with exit code ${o}`
                : "failed";
  return (
    (me = ({
      stdout: i,
      stderr: s,
      all: n,
      error: e,
      signal: u,
      exitCode: o,
      command: a,
      escapedCommand: c,
      timedOut: f,
      isCanceled: h,
      killed: l,
      parsed: {
        options: { timeout: p },
      },
    }) => {
      ((o = o === null ? void 0 : o), (u = u === null ? void 0 : u));
      const g = u === void 0 ? void 0 : t[u].description,
        m = e && e.code,
        x = `Command ${r({ timedOut: f, timeout: p, errorCode: m, signal: u, signalDescription: g, exitCode: o, isCanceled: h })}: ${a}`,
        E = Object.prototype.toString.call(e) === "[object Error]",
        R = E
          ? `${x}
${e.message}`
          : x,
        P = [R, s, i].filter(Boolean).join(`
`);
      return (
        E
          ? ((e.originalMessage = e.message), (e.message = P))
          : (e = new Error(P)),
        (e.shortMessage = R),
        (e.command = a),
        (e.escapedCommand = c),
        (e.exitCode = o),
        (e.signal = u),
        (e.signalDescription = g),
        (e.stdout = i),
        (e.stderr = s),
        n !== void 0 && (e.all = n),
        "bufferedData" in e && delete e.bufferedData,
        (e.failed = !0),
        (e.timedOut = !!f),
        (e.isCanceled = h),
        (e.killed = l && !f),
        e
      );
    }),
    me
  );
}
var ee = { exports: {} },
  Ze;
function Dt() {
  if (Ze) return ee.exports;
  Ze = 1;
  const t = ["stdin", "stdout", "stderr"],
    r = (i) => t.some((s) => i[s] !== void 0),
    d = (i) => {
      if (!i) return;
      const { stdio: s } = i;
      if (s === void 0) return t.map((e) => i[e]);
      if (r(i))
        throw new Error(
          `It's not possible to provide \`stdio\` in combination with one of ${t.map((e) => `\`${e}\``).join(", ")}`,
        );
      if (typeof s == "string") return s;
      if (!Array.isArray(s))
        throw new TypeError(
          `Expected \`stdio\` to be of type \`string\` or \`Array\`, got \`${typeof s}\``,
        );
      const n = Math.max(s.length, t.length);
      return Array.from({ length: n }, (e, u) => s[u]);
    };
  return (
    (ee.exports = d),
    (ee.exports.node = (i) => {
      const s = d(i);
      return s === "ipc"
        ? "ipc"
        : s === void 0 || typeof s == "string"
          ? [s, s, s, "ipc"]
          : s.includes("ipc")
            ? s
            : [...s, "ipc"];
    }),
    ee.exports
  );
}
var N = { exports: {} },
  pe = { exports: {} },
  Je;
function Kt() {
  return (
    Je ||
      ((Je = 1),
      (function (t) {
        ((t.exports = ["SIGABRT", "SIGALRM", "SIGHUP", "SIGINT", "SIGTERM"]),
          process.platform !== "win32" &&
            t.exports.push(
              "SIGVTALRM",
              "SIGXCPU",
              "SIGXFSZ",
              "SIGUSR2",
              "SIGTRAP",
              "SIGSYS",
              "SIGQUIT",
              "SIGIOT",
            ),
          process.platform === "linux" &&
            t.exports.push(
              "SIGIO",
              "SIGPOLL",
              "SIGPWR",
              "SIGSTKFLT",
              "SIGUNUSED",
            ));
      })(pe)),
    pe.exports
  );
}
var et;
function Ht() {
  if (et) return N.exports;
  et = 1;
  var t = q.process;
  const r = function (m) {
    return (
      m &&
      typeof m == "object" &&
      typeof m.removeListener == "function" &&
      typeof m.emit == "function" &&
      typeof m.reallyExit == "function" &&
      typeof m.listeners == "function" &&
      typeof m.kill == "function" &&
      typeof m.pid == "number" &&
      typeof m.on == "function"
    );
  };
  if (!r(t))
    N.exports = function () {
      return function () {};
    };
  else {
    var d = xt,
      i = Kt(),
      s = /^win/i.test(t.platform),
      n = yt;
    typeof n != "function" && (n = n.EventEmitter);
    var e;
    (t.__signal_exit_emitter__
      ? (e = t.__signal_exit_emitter__)
      : ((e = t.__signal_exit_emitter__ = new n()),
        (e.count = 0),
        (e.emitted = {})),
      e.infinite || (e.setMaxListeners(1 / 0), (e.infinite = !0)),
      (N.exports = function (m, S) {
        if (!r(q.process)) return function () {};
        (d.equal(
          typeof m,
          "function",
          "a callback must be provided for exit handler",
        ),
          c === !1 && f());
        var x = "exit";
        S && S.alwaysLast && (x = "afterexit");
        var E = function () {
          (e.removeListener(x, m),
            e.listeners("exit").length === 0 &&
              e.listeners("afterexit").length === 0 &&
              u());
        };
        return (e.on(x, m), E);
      }));
    var u = function () {
      !c ||
        !r(q.process) ||
        ((c = !1),
        i.forEach(function (S) {
          try {
            t.removeListener(S, a[S]);
          } catch {}
        }),
        (t.emit = p),
        (t.reallyExit = h),
        (e.count -= 1));
    };
    N.exports.unload = u;
    var o = function (S, x, E) {
        e.emitted[S] || ((e.emitted[S] = !0), e.emit(S, x, E));
      },
      a = {};
    (i.forEach(function (m) {
      a[m] = function () {
        if (r(q.process)) {
          var x = t.listeners(m);
          x.length === e.count &&
            (u(),
            o("exit", null, m),
            o("afterexit", null, m),
            s && m === "SIGHUP" && (m = "SIGINT"),
            t.kill(t.pid, m));
        }
      };
    }),
      (N.exports.signals = function () {
        return i;
      }));
    var c = !1,
      f = function () {
        c ||
          !r(q.process) ||
          ((c = !0),
          (e.count += 1),
          (i = i.filter(function (S) {
            try {
              return (t.on(S, a[S]), !0);
            } catch {
              return !1;
            }
          })),
          (t.emit = g),
          (t.reallyExit = l));
      };
    N.exports.load = f;
    var h = t.reallyExit,
      l = function (S) {
        r(q.process) &&
          ((t.exitCode = S || 0),
          o("exit", t.exitCode, null),
          o("afterexit", t.exitCode, null),
          h.call(t, t.exitCode));
      },
      p = t.emit,
      g = function (S, x) {
        if (S === "exit" && r(q.process)) {
          x !== void 0 && (t.exitCode = x);
          var E = p.apply(this, arguments);
          return (
            o("exit", t.exitCode, null),
            o("afterexit", t.exitCode, null),
            E
          );
        } else return p.apply(this, arguments);
      };
  }
  return N.exports;
}
var he, tt;
function Wt() {
  if (tt) return he;
  tt = 1;
  const t = we,
    r = Ht(),
    d = 1e3 * 5,
    i = (l, p = "SIGTERM", g = {}) => {
      const m = l(p);
      return (s(l, p, g, m), m);
    },
    s = (l, p, g, m) => {
      if (!n(p, g, m)) return;
      const S = u(g),
        x = setTimeout(() => {
          l("SIGKILL");
        }, S);
      x.unref && x.unref();
    },
    n = (l, { forceKillAfterTimeout: p }, g) => e(l) && p !== !1 && g,
    e = (l) =>
      l === t.constants.signals.SIGTERM ||
      (typeof l == "string" && l.toUpperCase() === "SIGTERM"),
    u = ({ forceKillAfterTimeout: l = !0 }) => {
      if (l === !0) return d;
      if (!Number.isFinite(l) || l < 0)
        throw new TypeError(
          `Expected the \`forceKillAfterTimeout\` option to be a non-negative integer, got \`${l}\` (${typeof l})`,
        );
      return l;
    },
    o = (l, p) => {
      l.kill() && (p.isCanceled = !0);
    },
    a = (l, p, g) => {
      (l.kill(p),
        g(Object.assign(new Error("Timed out"), { timedOut: !0, signal: p })));
    };
  return (
    (he = {
      spawnedKill: i,
      spawnedCancel: o,
      setupTimeout: (l, { timeout: p, killSignal: g = "SIGTERM" }, m) => {
        if (p === 0 || p === void 0) return m;
        let S;
        const x = new Promise((R, P) => {
            S = setTimeout(() => {
              a(l, g, P);
            }, p);
          }),
          E = m.finally(() => {
            clearTimeout(S);
          });
        return Promise.race([x, E]);
      },
      validateTimeout: ({ timeout: l }) => {
        if (l !== void 0 && (!Number.isFinite(l) || l < 0))
          throw new TypeError(
            `Expected the \`timeout\` option to be a non-negative integer, got \`${l}\` (${typeof l})`,
          );
      },
      setExitHandler: async (l, { cleanup: p, detached: g }, m) => {
        if (!p || g) return m;
        const S = r(() => {
          l.kill();
        });
        return m.finally(() => {
          S();
        });
      },
    }),
    he
  );
}
var Se, nt;
function Xt() {
  if (nt) return Se;
  nt = 1;
  const t = (r) =>
    r !== null && typeof r == "object" && typeof r.pipe == "function";
  return (
    (t.writable = (r) =>
      t(r) &&
      r.writable !== !1 &&
      typeof r._write == "function" &&
      typeof r._writableState == "object"),
    (t.readable = (r) =>
      t(r) &&
      r.readable !== !1 &&
      typeof r._read == "function" &&
      typeof r._readableState == "object"),
    (t.duplex = (r) => t.writable(r) && t.readable(r)),
    (t.transform = (r) => t.duplex(r) && typeof r._transform == "function"),
    (Se = t),
    Se
  );
}
var B = { exports: {} },
  ge,
  rt;
function zt() {
  if (rt) return ge;
  rt = 1;
  const { PassThrough: t } = Ie;
  return (
    (ge = (r) => {
      r = { ...r };
      const { array: d } = r;
      let { encoding: i } = r;
      const s = i === "buffer";
      let n = !1;
      (d ? (n = !(i || s)) : (i = i || "utf8"), s && (i = null));
      const e = new t({ objectMode: n });
      i && e.setEncoding(i);
      let u = 0;
      const o = [];
      return (
        e.on("data", (a) => {
          (o.push(a), n ? (u = o.length) : (u += a.length));
        }),
        (e.getBufferedValue = () =>
          d ? o : s ? Buffer.concat(o, u) : o.join("")),
        (e.getBufferedLength = () => u),
        e
      );
    }),
    ge
  );
}
var it;
function Vt() {
  if (it) return B.exports;
  it = 1;
  const { constants: t } = bt,
    r = Ie,
    { promisify: d } = Et,
    i = zt(),
    s = d(r.pipeline);
  class n extends Error {
    constructor() {
      (super("maxBuffer exceeded"), (this.name = "MaxBufferError"));
    }
  }
  async function e(u, o) {
    if (!u) throw new Error("Expected a stream");
    o = { maxBuffer: 1 / 0, ...o };
    const { maxBuffer: a } = o,
      c = i(o);
    return (
      await new Promise((f, h) => {
        const l = (p) => {
          (p &&
            c.getBufferedLength() <= t.MAX_LENGTH &&
            (p.bufferedData = c.getBufferedValue()),
            h(p));
        };
        ((async () => {
          try {
            (await s(u, c), f());
          } catch (p) {
            l(p);
          }
        })(),
          c.on("data", () => {
            c.getBufferedLength() > a && l(new n());
          }));
      }),
      c.getBufferedValue()
    );
  }
  return (
    (B.exports = e),
    (B.exports.buffer = (u, o) => e(u, { ...o, encoding: "buffer" })),
    (B.exports.array = (u, o) => e(u, { ...o, array: !0 })),
    (B.exports.MaxBufferError = n),
    B.exports
  );
}
var ve, ot;
function Yt() {
  if (ot) return ve;
  ot = 1;
  const { PassThrough: t } = Ie;
  return (
    (ve = function () {
      var r = [],
        d = new t({ objectMode: !0 });
      return (
        d.setMaxListeners(0),
        (d.add = i),
        (d.isEmpty = s),
        d.on("unpipe", n),
        Array.prototype.slice.call(arguments).forEach(i),
        d
      );
      function i(e) {
        return Array.isArray(e)
          ? (e.forEach(i), this)
          : (r.push(e),
            e.once("end", n.bind(null, e)),
            e.once("error", d.emit.bind(d, "error")),
            e.pipe(d, { end: !1 }),
            this);
      }
      function s() {
        return r.length == 0;
      }
      function n(e) {
        ((r = r.filter(function (u) {
          return u !== e;
        })),
          !r.length && d.readable && d.end());
      }
    }),
    ve
  );
}
var xe, st;
function Qt() {
  if (st) return xe;
  st = 1;
  const t = Xt(),
    r = Vt(),
    d = Yt(),
    i = (a, c) => {
      c === void 0 ||
        a.stdin === void 0 ||
        (t(c) ? c.pipe(a.stdin) : a.stdin.end(c));
    },
    s = (a, { all: c }) => {
      if (!c || (!a.stdout && !a.stderr)) return;
      const f = d();
      return (a.stdout && f.add(a.stdout), a.stderr && f.add(a.stderr), f);
    },
    n = async (a, c) => {
      if (a) {
        a.destroy();
        try {
          return await c;
        } catch (f) {
          return f.bufferedData;
        }
      }
    },
    e = (a, { encoding: c, buffer: f, maxBuffer: h }) => {
      if (!(!a || !f))
        return c
          ? r(a, { encoding: c, maxBuffer: h })
          : r.buffer(a, { maxBuffer: h });
    };
  return (
    (xe = {
      handleInput: i,
      makeAllStream: s,
      getSpawnedResult: async (
        { stdout: a, stderr: c, all: f },
        { encoding: h, buffer: l, maxBuffer: p },
        g,
      ) => {
        const m = e(a, { encoding: h, buffer: l, maxBuffer: p }),
          S = e(c, { encoding: h, buffer: l, maxBuffer: p }),
          x = e(f, { encoding: h, buffer: l, maxBuffer: p * 2 });
        try {
          return await Promise.all([g, m, S, x]);
        } catch (E) {
          return Promise.all([
            { error: E, signal: E.signal, timedOut: E.timedOut },
            n(a, m),
            n(c, S),
            n(f, x),
          ]);
        }
      },
      validateInputSync: ({ input: a }) => {
        if (t(a))
          throw new TypeError(
            "The `input` option cannot be a stream in sync mode",
          );
      },
    }),
    xe
  );
}
var ye, at;
function Zt() {
  if (at) return ye;
  at = 1;
  const t = (async () => {})().constructor.prototype,
    r = ["then", "catch", "finally"].map((s) => [
      s,
      Reflect.getOwnPropertyDescriptor(t, s),
    ]);
  return (
    (ye = {
      mergePromise: (s, n) => {
        for (const [e, u] of r) {
          const o =
            typeof n == "function"
              ? (...a) => Reflect.apply(u.value, n(), a)
              : u.value.bind(n);
          Reflect.defineProperty(s, e, { ...u, value: o });
        }
        return s;
      },
      getSpawnedPromise: (s) =>
        new Promise((n, e) => {
          (s.on("exit", (u, o) => {
            n({ exitCode: u, signal: o });
          }),
            s.on("error", (u) => {
              e(u);
            }),
            s.stdin &&
              s.stdin.on("error", (u) => {
                e(u);
              }));
        }),
    }),
    ye
  );
}
var be, ct;
function Jt() {
  if (ct) return be;
  ct = 1;
  const t = (o, a = []) => (Array.isArray(a) ? [o, ...a] : [o]),
    r = /^[\w.-]+$/,
    d = /"/g,
    i = (o) =>
      typeof o != "string" || r.test(o) ? o : `"${o.replace(d, '\\"')}"`,
    s = (o, a) => t(o, a).join(" "),
    n = (o, a) =>
      t(o, a)
        .map((c) => i(c))
        .join(" "),
    e = / +/g;
  return (
    (be = {
      joinCommand: s,
      getEscapedCommand: n,
      parseCommand: (o) => {
        const a = [];
        for (const c of o.trim().split(e)) {
          const f = a[a.length - 1];
          f && f.endsWith("\\")
            ? (a[a.length - 1] = `${f.slice(0, -1)} ${c}`)
            : a.push(c);
        }
        return a;
      },
    }),
    be
  );
}
var ut;
function en() {
  if (ut) return $.exports;
  ut = 1;
  const t = K,
    r = dt,
    d = Ot(),
    i = Nt(),
    s = Mt(),
    n = Bt(),
    e = Ut(),
    u = Dt(),
    {
      spawnedKill: o,
      spawnedCancel: a,
      setupTimeout: c,
      validateTimeout: f,
      setExitHandler: h,
    } = Wt(),
    {
      handleInput: l,
      getSpawnedResult: p,
      makeAllStream: g,
      validateInputSync: m,
    } = Qt(),
    { mergePromise: S, getSpawnedPromise: x } = Zt(),
    { joinCommand: E, parseCommand: R, getEscapedCommand: P } = Jt(),
    G = 1e3 * 1e3 * 100,
    L = ({
      env: I,
      extendEnv: b,
      preferLocal: w,
      localDir: v,
      execPath: C,
    }) => {
      const T = b ? { ...process.env, ...I } : I;
      return w ? s.env({ env: T, cwd: v, execPath: C }) : T;
    },
    H = (I, b, w = {}) => {
      const v = d._parse(I, b, w);
      return (
        (I = v.command),
        (b = v.args),
        (w = v.options),
        (w = {
          maxBuffer: G,
          buffer: !0,
          stripFinalNewline: !0,
          extendEnv: !0,
          preferLocal: !1,
          localDir: w.cwd || process.cwd(),
          execPath: process.execPath,
          encoding: "utf8",
          reject: !0,
          cleanup: !0,
          all: !1,
          windowsHide: !0,
          ...w,
        }),
        (w.env = L(w)),
        (w.stdio = u(w)),
        process.platform === "win32" &&
          t.basename(I, ".exe") === "cmd" &&
          b.unshift("/q"),
        { file: I, args: b, options: w, parsed: v }
      );
    },
    j = (I, b, w) =>
      typeof b != "string" && !Buffer.isBuffer(b)
        ? w === void 0
          ? void 0
          : ""
        : I.stripFinalNewline
          ? i(b)
          : b,
    W = (I, b, w) => {
      const v = H(I, b, w),
        C = E(I, b),
        T = P(I, b);
      f(v.options);
      let y;
      try {
        y = r.spawn(v.file, v.args, v.options);
      } catch (z) {
        const V = new r.ChildProcess(),
          Y = Promise.reject(
            e({
              error: z,
              stdout: "",
              stderr: "",
              all: "",
              command: C,
              escapedCommand: T,
              parsed: v,
              timedOut: !1,
              isCanceled: !1,
              killed: !1,
            }),
          );
        return S(V, Y);
      }
      const M = x(y),
        X = c(y, v.options, M),
        k = h(y, v.options, X),
        Re = { isCanceled: !1 };
      ((y.kill = o.bind(null, y.kill.bind(y))),
        (y.cancel = a.bind(null, y, Re)));
      const mt = n(async () => {
        const [{ error: z, exitCode: V, signal: Y, timedOut: pt }, ht, St, gt] =
            await p(y, v.options, k),
          Pe = j(v.options, ht),
          Te = j(v.options, St),
          Ce = j(v.options, gt);
        if (z || V !== 0 || Y !== null) {
          const Ge = e({
            error: z,
            exitCode: V,
            signal: Y,
            stdout: Pe,
            stderr: Te,
            all: Ce,
            command: C,
            escapedCommand: T,
            parsed: v,
            timedOut: pt,
            isCanceled: Re.isCanceled,
            killed: y.killed,
          });
          if (!v.options.reject) return Ge;
          throw Ge;
        }
        return {
          command: C,
          escapedCommand: T,
          exitCode: 0,
          stdout: Pe,
          stderr: Te,
          all: Ce,
          failed: !1,
          timedOut: !1,
          isCanceled: !1,
          killed: !1,
        };
      });
      return (l(y, v.options.input), (y.all = g(y, v.options)), S(y, mt));
    };
  return (
    ($.exports = W),
    ($.exports.sync = (I, b, w) => {
      const v = H(I, b, w),
        C = E(I, b),
        T = P(I, b);
      m(v.options);
      let y;
      try {
        y = r.spawnSync(v.file, v.args, v.options);
      } catch (k) {
        throw e({
          error: k,
          stdout: "",
          stderr: "",
          all: "",
          command: C,
          escapedCommand: T,
          parsed: v,
          timedOut: !1,
          isCanceled: !1,
          killed: !1,
        });
      }
      const M = j(v.options, y.stdout, y.error),
        X = j(v.options, y.stderr, y.error);
      if (y.error || y.status !== 0 || y.signal !== null) {
        const k = e({
          stdout: M,
          stderr: X,
          error: y.error,
          signal: y.signal,
          exitCode: y.status,
          command: C,
          escapedCommand: T,
          parsed: v,
          timedOut: y.error && y.error.code === "ETIMEDOUT",
          isCanceled: !1,
          killed: y.signal !== null,
        });
        if (!v.options.reject) return k;
        throw k;
      }
      return {
        command: C,
        escapedCommand: T,
        exitCode: 0,
        stdout: M,
        stderr: X,
        failed: !1,
        timedOut: !1,
        isCanceled: !1,
        killed: !1,
      };
    }),
    ($.exports.command = (I, b) => {
      const [w, ...v] = R(I);
      return W(w, v, b);
    }),
    ($.exports.commandSync = (I, b) => {
      const [w, ...v] = R(I);
      return W.sync(w, v, b);
    }),
    ($.exports.node = (I, b, w = {}) => {
      b && !Array.isArray(b) && typeof b == "object" && ((w = b), (b = []));
      const v = u.node(w),
        C = process.execArgv.filter((M) => !M.startsWith("--inspect")),
        { nodePath: T = process.execPath, nodeOptions: y = C } = w;
      return W(T, [...y, I, ...(Array.isArray(b) ? b : [])], {
        ...w,
        stdin: void 0,
        stdout: void 0,
        stderr: void 0,
        stdio: v,
        shell: !1,
      });
    }),
    $.exports
  );
}
var tn = en();
const pn = vt(tn);
export { lt as a, qt as b, pn as e, Rt as r };
//# sourceMappingURL=index-CMOlVndj.mjs.map
