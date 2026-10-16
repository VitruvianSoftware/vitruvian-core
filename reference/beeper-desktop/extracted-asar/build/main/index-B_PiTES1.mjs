import { a as Dr } from "./_commonjsHelpers-CBUqixCJ.mjs";
import Mr from "node:util";
import Or from "node:stream";
import zr from "child_process";
import Gr from "fs";
import Ur from "node:child_process";
import Hr from "node:crypto";
import Wr from "node:path";
import Xr from "node:events";
import Vr from "node:os";
import Qr from "node:module";
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
    var i = new e.Error().stack;
    i &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[i] = "8874c95c-0f2b-49e2-9eeb-5d45ab5efcf3"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-8874c95c-0f2b-49e2-9eeb-5d45ab5efcf3"));
  } catch {}
})();
const zt = import.meta.filename,
  Gt = import.meta.dirname,
  O = Qr.createRequire(import.meta.url);
var K, Ge;
function G() {
  if (Ge) return K;
  Ge = 1;
  const e = function (m) {
    return typeof m < "u" && m !== null;
  };
  return (
    (K = {
      defined: e,
      object: function (m) {
        return typeof m == "object";
      },
      plainObject: function (m) {
        return Object.prototype.toString.call(m) === "[object Object]";
      },
      fn: function (m) {
        return typeof m == "function";
      },
      bool: function (m) {
        return typeof m == "boolean";
      },
      buffer: function (m) {
        return m instanceof Buffer;
      },
      typedArray: function (m) {
        if (e(m))
          switch (m.constructor) {
            case Uint8Array:
            case Uint8ClampedArray:
            case Int8Array:
            case Uint16Array:
            case Int16Array:
            case Uint32Array:
            case Int32Array:
            case Float32Array:
            case Float64Array:
              return !0;
          }
        return !1;
      },
      arrayBuffer: function (m) {
        return m instanceof ArrayBuffer;
      },
      string: function (m) {
        return typeof m == "string" && m.length > 0;
      },
      number: function (m) {
        return typeof m == "number" && !Number.isNaN(m);
      },
      integer: function (m) {
        return Number.isInteger(m);
      },
      inRange: function (m, p, E) {
        return m >= p && m <= E;
      },
      inArray: function (m, p) {
        return p.includes(m);
      },
      invalidParameterError: function (m, p, E) {
        return new Error(
          `Expected ${p} for ${m} but received ${E} of type ${typeof E}`,
        );
      },
      nativeError: function (m, p) {
        return ((p.message = m.message), p);
      },
    }),
    K
  );
}
var J = { exports: {} },
  Z,
  Ue;
function Yr() {
  if (Ue) return Z;
  Ue = 1;
  const e = () => process.platform === "linux";
  let i = null;
  return (
    (Z = {
      isLinux: e,
      getReport: () => {
        if (!i)
          if (e() && process.report) {
            const w = process.report.excludeNetwork;
            ((process.report.excludeNetwork = !0),
              (i = process.report.getReport()),
              (process.report.excludeNetwork = w));
          } else i = {};
        return i;
      },
    }),
    Z
  );
}
var ee, He;
function Kr() {
  if (He) return ee;
  He = 1;
  const e = Gr;
  return (
    (ee = {
      LDD_PATH: "/usr/bin/ldd",
      readFileSync: (a) => e.readFileSync(a, "utf-8"),
      readFile: (a) =>
        new Promise((c, o) => {
          e.readFile(a, "utf-8", (l, n) => {
            l ? o(l) : c(n);
          });
        }),
    }),
    ee
  );
}
var re, We;
function Me() {
  if (We) return re;
  We = 1;
  const e = zr,
    { isLinux: i, getReport: b } = Yr(),
    { LDD_PATH: w, readFile: a, readFileSync: c } = Kr();
  let o, l;
  const n = "getconf GNU_LIBC_VERSION 2>&1 || true; ldd --version 2>&1 || true";
  let f = "";
  const s = () =>
      f ||
      new Promise((v) => {
        e.exec(n, (I, j) => {
          ((f = I ? " " : j), v(f));
        });
      }),
    u = () => {
      if (!f)
        try {
          f = e.execSync(n, { encoding: "utf8" });
        } catch {
          f = " ";
        }
      return f;
    },
    r = "glibc",
    g = /LIBC[a-z0-9 \-).]*?(\d+\.\d+)/i,
    h = "musl",
    m = (v) => v.includes("libc.musl-") || v.includes("ld-musl-"),
    p = () => {
      const v = b();
      return v.header && v.header.glibcVersionRuntime
        ? r
        : Array.isArray(v.sharedObjects) && v.sharedObjects.some(m)
          ? h
          : null;
    },
    E = (v) => {
      const [I, j] = v.split(/[\r\n]+/);
      return I && I.includes(r) ? r : j && j.includes(h) ? h : null;
    },
    N = (v) =>
      v.includes("musl") ? h : v.includes("GNU C Library") ? r : null,
    k = async () => {
      if (o !== void 0) return o;
      o = null;
      try {
        const v = await a(w);
        o = N(v);
      } catch {}
      return o;
    },
    _ = () => {
      if (o !== void 0) return o;
      o = null;
      try {
        const v = c(w);
        o = N(v);
      } catch {}
      return o;
    },
    F = async () => {
      let v = null;
      if (i() && ((v = await k()), v || (v = p()), !v)) {
        const I = await s();
        v = E(I);
      }
      return v;
    },
    B = () => {
      let v = null;
      if (i() && ((v = _()), v || (v = p()), !v)) {
        const I = u();
        v = E(I);
      }
      return v;
    },
    D = async () => i() && (await F()) !== r,
    T = () => i() && B() !== r,
    d = async () => {
      if (l !== void 0) return l;
      l = null;
      try {
        const I = (await a(w)).match(g);
        I && (l = I[1]);
      } catch {}
      return l;
    },
    R = () => {
      if (l !== void 0) return l;
      l = null;
      try {
        const I = c(w).match(g);
        I && (l = I[1]);
      } catch {}
      return l;
    },
    q = () => {
      const v = b();
      return v.header && v.header.glibcVersionRuntime
        ? v.header.glibcVersionRuntime
        : null;
    },
    M = (v) => v.trim().split(/\s+/)[1],
    U = (v) => {
      const [I, j, $] = v.split(/[\r\n]+/);
      return I && I.includes(r) ? M(I) : j && $ && j.includes(h) ? M($) : null;
    };
  return (
    (re = {
      GLIBC: r,
      MUSL: h,
      family: F,
      familySync: B,
      isNonGlibcLinux: D,
      isNonGlibcLinuxSync: T,
      version: async () => {
        let v = null;
        if (i() && ((v = await d()), v || (v = q()), !v)) {
          const I = await s();
          v = U(I);
        }
        return v;
      },
      versionSync: () => {
        let v = null;
        if (i() && ((v = R()), v || (v = q()), !v)) {
          const I = u();
          v = U(I);
        }
        return v;
      },
    }),
    re
  );
}
var te, Xe;
function V() {
  return (
    Xe ||
      ((Xe = 1),
      (te =
        typeof process == "object" &&
        process.env &&
        process.env.NODE_DEBUG &&
        /\bsemver\b/i.test(process.env.NODE_DEBUG)
          ? (...i) => console.error("SEMVER", ...i)
          : () => {})),
    te
  );
}
var ie, Ve;
function Oe() {
  if (Ve) return ie;
  Ve = 1;
  const e = "2.0.0",
    i = 256,
    b = Number.MAX_SAFE_INTEGER || 9007199254740991,
    w = 16,
    a = i - 6;
  return (
    (ie = {
      MAX_LENGTH: i,
      MAX_SAFE_COMPONENT_LENGTH: w,
      MAX_SAFE_BUILD_LENGTH: a,
      MAX_SAFE_INTEGER: b,
      RELEASE_TYPES: [
        "major",
        "premajor",
        "minor",
        "preminor",
        "patch",
        "prepatch",
        "prerelease",
      ],
      SEMVER_SPEC_VERSION: e,
      FLAG_INCLUDE_PRERELEASE: 1,
      FLAG_LOOSE: 2,
    }),
    ie
  );
}
var X = { exports: {} },
  Qe;
function Q() {
  return (
    Qe ||
      ((Qe = 1),
      (function (e, i) {
        const {
            MAX_SAFE_COMPONENT_LENGTH: b,
            MAX_SAFE_BUILD_LENGTH: w,
            MAX_LENGTH: a,
          } = Oe(),
          c = V();
        i = e.exports = {};
        const o = (i.re = []),
          l = (i.safeRe = []),
          n = (i.src = []),
          f = (i.safeSrc = []),
          s = (i.t = {});
        let u = 0;
        const r = "[a-zA-Z0-9-]",
          g = [
            ["\\s", 1],
            ["\\d", a],
            [r, w],
          ],
          h = (p) => {
            for (const [E, N] of g)
              p = p
                .split(`${E}*`)
                .join(`${E}{0,${N}}`)
                .split(`${E}+`)
                .join(`${E}{1,${N}}`);
            return p;
          },
          m = (p, E, N) => {
            const k = h(E),
              _ = u++;
            (c(p, _, E),
              (s[p] = _),
              (n[_] = E),
              (f[_] = k),
              (o[_] = new RegExp(E, N ? "g" : void 0)),
              (l[_] = new RegExp(k, N ? "g" : void 0)));
          };
        (m("NUMERICIDENTIFIER", "0|[1-9]\\d*"),
          m("NUMERICIDENTIFIERLOOSE", "\\d+"),
          m("NONNUMERICIDENTIFIER", `\\d*[a-zA-Z-]${r}*`),
          m(
            "MAINVERSION",
            `(${n[s.NUMERICIDENTIFIER]})\\.(${n[s.NUMERICIDENTIFIER]})\\.(${n[s.NUMERICIDENTIFIER]})`,
          ),
          m(
            "MAINVERSIONLOOSE",
            `(${n[s.NUMERICIDENTIFIERLOOSE]})\\.(${n[s.NUMERICIDENTIFIERLOOSE]})\\.(${n[s.NUMERICIDENTIFIERLOOSE]})`,
          ),
          m(
            "PRERELEASEIDENTIFIER",
            `(?:${n[s.NONNUMERICIDENTIFIER]}|${n[s.NUMERICIDENTIFIER]})`,
          ),
          m(
            "PRERELEASEIDENTIFIERLOOSE",
            `(?:${n[s.NONNUMERICIDENTIFIER]}|${n[s.NUMERICIDENTIFIERLOOSE]})`,
          ),
          m(
            "PRERELEASE",
            `(?:-(${n[s.PRERELEASEIDENTIFIER]}(?:\\.${n[s.PRERELEASEIDENTIFIER]})*))`,
          ),
          m(
            "PRERELEASELOOSE",
            `(?:-?(${n[s.PRERELEASEIDENTIFIERLOOSE]}(?:\\.${n[s.PRERELEASEIDENTIFIERLOOSE]})*))`,
          ),
          m("BUILDIDENTIFIER", `${r}+`),
          m(
            "BUILD",
            `(?:\\+(${n[s.BUILDIDENTIFIER]}(?:\\.${n[s.BUILDIDENTIFIER]})*))`,
          ),
          m(
            "FULLPLAIN",
            `v?${n[s.MAINVERSION]}${n[s.PRERELEASE]}?${n[s.BUILD]}?`,
          ),
          m("FULL", `^${n[s.FULLPLAIN]}$`),
          m(
            "LOOSEPLAIN",
            `[v=\\s]*${n[s.MAINVERSIONLOOSE]}${n[s.PRERELEASELOOSE]}?${n[s.BUILD]}?`,
          ),
          m("LOOSE", `^${n[s.LOOSEPLAIN]}$`),
          m("GTLT", "((?:<|>)?=?)"),
          m("XRANGEIDENTIFIERLOOSE", `${n[s.NUMERICIDENTIFIERLOOSE]}|x|X|\\*`),
          m("XRANGEIDENTIFIER", `${n[s.NUMERICIDENTIFIER]}|x|X|\\*`),
          m(
            "XRANGEPLAIN",
            `[v=\\s]*(${n[s.XRANGEIDENTIFIER]})(?:\\.(${n[s.XRANGEIDENTIFIER]})(?:\\.(${n[s.XRANGEIDENTIFIER]})(?:${n[s.PRERELEASE]})?${n[s.BUILD]}?)?)?`,
          ),
          m(
            "XRANGEPLAINLOOSE",
            `[v=\\s]*(${n[s.XRANGEIDENTIFIERLOOSE]})(?:\\.(${n[s.XRANGEIDENTIFIERLOOSE]})(?:\\.(${n[s.XRANGEIDENTIFIERLOOSE]})(?:${n[s.PRERELEASELOOSE]})?${n[s.BUILD]}?)?)?`,
          ),
          m("XRANGE", `^${n[s.GTLT]}\\s*${n[s.XRANGEPLAIN]}$`),
          m("XRANGELOOSE", `^${n[s.GTLT]}\\s*${n[s.XRANGEPLAINLOOSE]}$`),
          m(
            "COERCEPLAIN",
            `(^|[^\\d])(\\d{1,${b}})(?:\\.(\\d{1,${b}}))?(?:\\.(\\d{1,${b}}))?`,
          ),
          m("COERCE", `${n[s.COERCEPLAIN]}(?:$|[^\\d])`),
          m(
            "COERCEFULL",
            n[s.COERCEPLAIN] +
              `(?:${n[s.PRERELEASE]})?(?:${n[s.BUILD]})?(?:$|[^\\d])`,
          ),
          m("COERCERTL", n[s.COERCE], !0),
          m("COERCERTLFULL", n[s.COERCEFULL], !0),
          m("LONETILDE", "(?:~>?)"),
          m("TILDETRIM", `(\\s*)${n[s.LONETILDE]}\\s+`, !0),
          (i.tildeTrimReplace = "$1~"),
          m("TILDE", `^${n[s.LONETILDE]}${n[s.XRANGEPLAIN]}$`),
          m("TILDELOOSE", `^${n[s.LONETILDE]}${n[s.XRANGEPLAINLOOSE]}$`),
          m("LONECARET", "(?:\\^)"),
          m("CARETTRIM", `(\\s*)${n[s.LONECARET]}\\s+`, !0),
          (i.caretTrimReplace = "$1^"),
          m("CARET", `^${n[s.LONECARET]}${n[s.XRANGEPLAIN]}$`),
          m("CARETLOOSE", `^${n[s.LONECARET]}${n[s.XRANGEPLAINLOOSE]}$`),
          m("COMPARATORLOOSE", `^${n[s.GTLT]}\\s*(${n[s.LOOSEPLAIN]})$|^$`),
          m("COMPARATOR", `^${n[s.GTLT]}\\s*(${n[s.FULLPLAIN]})$|^$`),
          m(
            "COMPARATORTRIM",
            `(\\s*)${n[s.GTLT]}\\s*(${n[s.LOOSEPLAIN]}|${n[s.XRANGEPLAIN]})`,
            !0,
          ),
          (i.comparatorTrimReplace = "$1$2$3"),
          m(
            "HYPHENRANGE",
            `^\\s*(${n[s.XRANGEPLAIN]})\\s+-\\s+(${n[s.XRANGEPLAIN]})\\s*$`,
          ),
          m(
            "HYPHENRANGELOOSE",
            `^\\s*(${n[s.XRANGEPLAINLOOSE]})\\s+-\\s+(${n[s.XRANGEPLAINLOOSE]})\\s*$`,
          ),
          m("STAR", "(<|>)?=?\\s*\\*"),
          m("GTE0", "^\\s*>=\\s*0\\.0\\.0\\s*$"),
          m("GTE0PRE", "^\\s*>=\\s*0\\.0\\.0-0\\s*$"));
      })(X, X.exports)),
    X.exports
  );
}
var ne, Ye;
function ze() {
  if (Ye) return ne;
  Ye = 1;
  const e = Object.freeze({ loose: !0 }),
    i = Object.freeze({});
  return ((ne = (w) => (w ? (typeof w != "object" ? e : w) : i)), ne);
}
var ae, Ke;
function Jr() {
  if (Ke) return ae;
  Ke = 1;
  const e = /^[0-9]+$/,
    i = (w, a) => {
      const c = e.test(w),
        o = e.test(a);
      return (
        c && o && ((w = +w), (a = +a)),
        w === a ? 0 : c && !o ? -1 : o && !c ? 1 : w < a ? -1 : 1
      );
    };
  return (
    (ae = { compareIdentifiers: i, rcompareIdentifiers: (w, a) => i(a, w) }),
    ae
  );
}
var se, Je;
function W() {
  if (Je) return se;
  Je = 1;
  const e = V(),
    { MAX_LENGTH: i, MAX_SAFE_INTEGER: b } = Oe(),
    { safeRe: w, t: a } = Q(),
    c = ze(),
    { compareIdentifiers: o } = Jr();
  class l {
    constructor(f, s) {
      if (((s = c(s)), f instanceof l)) {
        if (
          f.loose === !!s.loose &&
          f.includePrerelease === !!s.includePrerelease
        )
          return f;
        f = f.version;
      } else if (typeof f != "string")
        throw new TypeError(
          `Invalid version. Must be a string. Got type "${typeof f}".`,
        );
      if (f.length > i)
        throw new TypeError(`version is longer than ${i} characters`);
      (e("SemVer", f, s),
        (this.options = s),
        (this.loose = !!s.loose),
        (this.includePrerelease = !!s.includePrerelease));
      const u = f.trim().match(s.loose ? w[a.LOOSE] : w[a.FULL]);
      if (!u) throw new TypeError(`Invalid Version: ${f}`);
      if (
        ((this.raw = f),
        (this.major = +u[1]),
        (this.minor = +u[2]),
        (this.patch = +u[3]),
        this.major > b || this.major < 0)
      )
        throw new TypeError("Invalid major version");
      if (this.minor > b || this.minor < 0)
        throw new TypeError("Invalid minor version");
      if (this.patch > b || this.patch < 0)
        throw new TypeError("Invalid patch version");
      (u[4]
        ? (this.prerelease = u[4].split(".").map((r) => {
            if (/^[0-9]+$/.test(r)) {
              const g = +r;
              if (g >= 0 && g < b) return g;
            }
            return r;
          }))
        : (this.prerelease = []),
        (this.build = u[5] ? u[5].split(".") : []),
        this.format());
    }
    format() {
      return (
        (this.version = `${this.major}.${this.minor}.${this.patch}`),
        this.prerelease.length &&
          (this.version += `-${this.prerelease.join(".")}`),
        this.version
      );
    }
    toString() {
      return this.version;
    }
    compare(f) {
      if (
        (e("SemVer.compare", this.version, this.options, f), !(f instanceof l))
      ) {
        if (typeof f == "string" && f === this.version) return 0;
        f = new l(f, this.options);
      }
      return f.version === this.version
        ? 0
        : this.compareMain(f) || this.comparePre(f);
    }
    compareMain(f) {
      return (
        f instanceof l || (f = new l(f, this.options)),
        o(this.major, f.major) ||
          o(this.minor, f.minor) ||
          o(this.patch, f.patch)
      );
    }
    comparePre(f) {
      if (
        (f instanceof l || (f = new l(f, this.options)),
        this.prerelease.length && !f.prerelease.length)
      )
        return -1;
      if (!this.prerelease.length && f.prerelease.length) return 1;
      if (!this.prerelease.length && !f.prerelease.length) return 0;
      let s = 0;
      do {
        const u = this.prerelease[s],
          r = f.prerelease[s];
        if ((e("prerelease compare", s, u, r), u === void 0 && r === void 0))
          return 0;
        if (r === void 0) return 1;
        if (u === void 0) return -1;
        if (u === r) continue;
        return o(u, r);
      } while (++s);
    }
    compareBuild(f) {
      f instanceof l || (f = new l(f, this.options));
      let s = 0;
      do {
        const u = this.build[s],
          r = f.build[s];
        if ((e("build compare", s, u, r), u === void 0 && r === void 0))
          return 0;
        if (r === void 0) return 1;
        if (u === void 0) return -1;
        if (u === r) continue;
        return o(u, r);
      } while (++s);
    }
    inc(f, s, u) {
      if (f.startsWith("pre")) {
        if (!s && u === !1)
          throw new Error("invalid increment argument: identifier is empty");
        if (s) {
          const r = `-${s}`.match(
            this.options.loose ? w[a.PRERELEASELOOSE] : w[a.PRERELEASE],
          );
          if (!r || r[1] !== s) throw new Error(`invalid identifier: ${s}`);
        }
      }
      switch (f) {
        case "premajor":
          ((this.prerelease.length = 0),
            (this.patch = 0),
            (this.minor = 0),
            this.major++,
            this.inc("pre", s, u));
          break;
        case "preminor":
          ((this.prerelease.length = 0),
            (this.patch = 0),
            this.minor++,
            this.inc("pre", s, u));
          break;
        case "prepatch":
          ((this.prerelease.length = 0),
            this.inc("patch", s, u),
            this.inc("pre", s, u));
          break;
        case "prerelease":
          (this.prerelease.length === 0 && this.inc("patch", s, u),
            this.inc("pre", s, u));
          break;
        case "release":
          if (this.prerelease.length === 0)
            throw new Error(`version ${this.raw} is not a prerelease`);
          this.prerelease.length = 0;
          break;
        case "major":
          ((this.minor !== 0 ||
            this.patch !== 0 ||
            this.prerelease.length === 0) &&
            this.major++,
            (this.minor = 0),
            (this.patch = 0),
            (this.prerelease = []));
          break;
        case "minor":
          ((this.patch !== 0 || this.prerelease.length === 0) && this.minor++,
            (this.patch = 0),
            (this.prerelease = []));
          break;
        case "patch":
          (this.prerelease.length === 0 && this.patch++,
            (this.prerelease = []));
          break;
        case "pre": {
          const r = Number(u) ? 1 : 0;
          if (this.prerelease.length === 0) this.prerelease = [r];
          else {
            let g = this.prerelease.length;
            for (; --g >= 0;)
              typeof this.prerelease[g] == "number" &&
                (this.prerelease[g]++, (g = -2));
            if (g === -1) {
              if (s === this.prerelease.join(".") && u === !1)
                throw new Error(
                  "invalid increment argument: identifier already exists",
                );
              this.prerelease.push(r);
            }
          }
          if (s) {
            let g = [s, r];
            (u === !1 && (g = [s]),
              o(this.prerelease[0], s) === 0
                ? isNaN(this.prerelease[1]) && (this.prerelease = g)
                : (this.prerelease = g));
          }
          break;
        }
        default:
          throw new Error(`invalid increment argument: ${f}`);
      }
      return (
        (this.raw = this.format()),
        this.build.length && (this.raw += `+${this.build.join(".")}`),
        this
      );
    }
  }
  return ((se = l), se);
}
var oe, Ze;
function Zr() {
  if (Ze) return oe;
  Ze = 1;
  const e = W();
  return (
    (oe = (b, w, a = !1) => {
      if (b instanceof e) return b;
      try {
        return new e(b, w);
      } catch (c) {
        if (!a) return null;
        throw c;
      }
    }),
    oe
  );
}
var le, er;
function et() {
  if (er) return le;
  er = 1;
  const e = W(),
    i = Zr(),
    { safeRe: b, t: w } = Q();
  return (
    (le = (c, o) => {
      if (c instanceof e) return c;
      if ((typeof c == "number" && (c = String(c)), typeof c != "string"))
        return null;
      o = o || {};
      let l = null;
      if (!o.rtl)
        l = c.match(o.includePrerelease ? b[w.COERCEFULL] : b[w.COERCE]);
      else {
        const g = o.includePrerelease ? b[w.COERCERTLFULL] : b[w.COERCERTL];
        let h;
        for (; (h = g.exec(c)) && (!l || l.index + l[0].length !== c.length);)
          ((!l || h.index + h[0].length !== l.index + l[0].length) && (l = h),
            (g.lastIndex = h.index + h[1].length + h[2].length));
        g.lastIndex = -1;
      }
      if (l === null) return null;
      const n = l[2],
        f = l[3] || "0",
        s = l[4] || "0",
        u = o.includePrerelease && l[5] ? `-${l[5]}` : "",
        r = o.includePrerelease && l[6] ? `+${l[6]}` : "";
      return i(`${n}.${f}.${s}${u}${r}`, o);
    }),
    le
  );
}
var fe, rr;
function H() {
  if (rr) return fe;
  rr = 1;
  const e = W();
  return ((fe = (b, w, a) => new e(b, a).compare(new e(w, a))), fe);
}
var he, tr;
function Cr() {
  if (tr) return he;
  tr = 1;
  const e = H();
  return ((he = (b, w, a) => e(b, w, a) >= 0), he);
}
var ce, ir;
function rt() {
  if (ir) return ce;
  ir = 1;
  class e {
    constructor() {
      ((this.max = 1e3), (this.map = new Map()));
    }
    get(b) {
      const w = this.map.get(b);
      if (w !== void 0) return (this.map.delete(b), this.map.set(b, w), w);
    }
    delete(b) {
      return this.map.delete(b);
    }
    set(b, w) {
      if (!this.delete(b) && w !== void 0) {
        if (this.map.size >= this.max) {
          const c = this.map.keys().next().value;
          this.delete(c);
        }
        this.map.set(b, w);
      }
      return this;
    }
  }
  return ((ce = e), ce);
}
var ue, nr;
function tt() {
  if (nr) return ue;
  nr = 1;
  const e = H();
  return ((ue = (b, w, a) => e(b, w, a) === 0), ue);
}
var de, ar;
function it() {
  if (ar) return de;
  ar = 1;
  const e = H();
  return ((de = (b, w, a) => e(b, w, a) !== 0), de);
}
var ge, sr;
function nt() {
  if (sr) return ge;
  sr = 1;
  const e = H();
  return ((ge = (b, w, a) => e(b, w, a) > 0), ge);
}
var me, or;
function at() {
  if (or) return me;
  or = 1;
  const e = H();
  return ((me = (b, w, a) => e(b, w, a) < 0), me);
}
var be, lr;
function st() {
  if (lr) return be;
  lr = 1;
  const e = H();
  return ((be = (b, w, a) => e(b, w, a) <= 0), be);
}
var pe, fr;
function ot() {
  if (fr) return pe;
  fr = 1;
  const e = tt(),
    i = it(),
    b = nt(),
    w = Cr(),
    a = at(),
    c = st();
  return (
    (pe = (l, n, f, s) => {
      switch (n) {
        case "===":
          return (
            typeof l == "object" && (l = l.version),
            typeof f == "object" && (f = f.version),
            l === f
          );
        case "!==":
          return (
            typeof l == "object" && (l = l.version),
            typeof f == "object" && (f = f.version),
            l !== f
          );
        case "":
        case "=":
        case "==":
          return e(l, f, s);
        case "!=":
          return i(l, f, s);
        case ">":
          return b(l, f, s);
        case ">=":
          return w(l, f, s);
        case "<":
          return a(l, f, s);
        case "<=":
          return c(l, f, s);
        default:
          throw new TypeError(`Invalid operator: ${n}`);
      }
    }),
    pe
  );
}
var ve, hr;
function lt() {
  if (hr) return ve;
  hr = 1;
  const e = Symbol("SemVer ANY");
  class i {
    static get ANY() {
      return e;
    }
    constructor(s, u) {
      if (((u = b(u)), s instanceof i)) {
        if (s.loose === !!u.loose) return s;
        s = s.value;
      }
      ((s = s.trim().split(/\s+/).join(" ")),
        o("comparator", s, u),
        (this.options = u),
        (this.loose = !!u.loose),
        this.parse(s),
        this.semver === e
          ? (this.value = "")
          : (this.value = this.operator + this.semver.version),
        o("comp", this));
    }
    parse(s) {
      const u = this.options.loose ? w[a.COMPARATORLOOSE] : w[a.COMPARATOR],
        r = s.match(u);
      if (!r) throw new TypeError(`Invalid comparator: ${s}`);
      ((this.operator = r[1] !== void 0 ? r[1] : ""),
        this.operator === "=" && (this.operator = ""),
        r[2]
          ? (this.semver = new l(r[2], this.options.loose))
          : (this.semver = e));
    }
    toString() {
      return this.value;
    }
    test(s) {
      if (
        (o("Comparator.test", s, this.options.loose),
        this.semver === e || s === e)
      )
        return !0;
      if (typeof s == "string")
        try {
          s = new l(s, this.options);
        } catch {
          return !1;
        }
      return c(s, this.operator, this.semver, this.options);
    }
    intersects(s, u) {
      if (!(s instanceof i)) throw new TypeError("a Comparator is required");
      return this.operator === ""
        ? this.value === ""
          ? !0
          : new n(s.value, u).test(this.value)
        : s.operator === ""
          ? s.value === ""
            ? !0
            : new n(this.value, u).test(s.semver)
          : ((u = b(u)),
            (u.includePrerelease &&
              (this.value === "<0.0.0-0" || s.value === "<0.0.0-0")) ||
            (!u.includePrerelease &&
              (this.value.startsWith("<0.0.0") || s.value.startsWith("<0.0.0")))
              ? !1
              : !!(
                  (this.operator.startsWith(">") &&
                    s.operator.startsWith(">")) ||
                  (this.operator.startsWith("<") &&
                    s.operator.startsWith("<")) ||
                  (this.semver.version === s.semver.version &&
                    this.operator.includes("=") &&
                    s.operator.includes("=")) ||
                  (c(this.semver, "<", s.semver, u) &&
                    this.operator.startsWith(">") &&
                    s.operator.startsWith("<")) ||
                  (c(this.semver, ">", s.semver, u) &&
                    this.operator.startsWith("<") &&
                    s.operator.startsWith(">"))
                ));
    }
  }
  ve = i;
  const b = ze(),
    { safeRe: w, t: a } = Q(),
    c = ot(),
    o = V(),
    l = W(),
    n = qr();
  return ve;
}
var we, cr;
function qr() {
  if (cr) return we;
  cr = 1;
  const e = /\s+/g;
  class i {
    constructor(P, v) {
      if (((v = a(v)), P instanceof i))
        return P.loose === !!v.loose &&
          P.includePrerelease === !!v.includePrerelease
          ? P
          : new i(P.raw, v);
      if (P instanceof c)
        return (
          (this.raw = P.value),
          (this.set = [[P]]),
          (this.formatted = void 0),
          this
        );
      if (
        ((this.options = v),
        (this.loose = !!v.loose),
        (this.includePrerelease = !!v.includePrerelease),
        (this.raw = P.trim().replace(e, " ")),
        (this.set = this.raw
          .split("||")
          .map((I) => this.parseRange(I.trim()))
          .filter((I) => I.length)),
        !this.set.length)
      )
        throw new TypeError(`Invalid SemVer Range: ${this.raw}`);
      if (this.set.length > 1) {
        const I = this.set[0];
        if (
          ((this.set = this.set.filter((j) => !m(j[0]))), this.set.length === 0)
        )
          this.set = [I];
        else if (this.set.length > 1) {
          for (const j of this.set)
            if (j.length === 1 && p(j[0])) {
              this.set = [j];
              break;
            }
        }
      }
      this.formatted = void 0;
    }
    get range() {
      if (this.formatted === void 0) {
        this.formatted = "";
        for (let P = 0; P < this.set.length; P++) {
          P > 0 && (this.formatted += "||");
          const v = this.set[P];
          for (let I = 0; I < v.length; I++)
            (I > 0 && (this.formatted += " "),
              (this.formatted += v[I].toString().trim()));
        }
      }
      return this.formatted;
    }
    format() {
      return this.range;
    }
    toString() {
      return this.range;
    }
    parseRange(P) {
      const I =
          ((this.options.includePrerelease && g) | (this.options.loose && h)) +
          ":" +
          P,
        j = w.get(I);
      if (j) return j;
      const $ = this.options.loose,
        t = $ ? n[f.HYPHENRANGELOOSE] : n[f.HYPHENRANGE];
      ((P = P.replace(t, M(this.options.includePrerelease))),
        o("hyphen replace", P),
        (P = P.replace(n[f.COMPARATORTRIM], s)),
        o("comparator trim", P),
        (P = P.replace(n[f.TILDETRIM], u)),
        o("tilde trim", P),
        (P = P.replace(n[f.CARETTRIM], r)),
        o("caret trim", P));
      let x = P.split(" ")
        .map((C) => N(C, this.options))
        .join(" ")
        .split(/\s+/)
        .map((C) => q(C, this.options));
      ($ &&
        (x = x.filter(
          (C) => (
            o("loose invalid filter", C, this.options),
            !!C.match(n[f.COMPARATORLOOSE])
          ),
        )),
        o("range list", x));
      const A = new Map(),
        L = x.map((C) => new c(C, this.options));
      for (const C of L) {
        if (m(C)) return [C];
        A.set(C.value, C);
      }
      A.size > 1 && A.has("") && A.delete("");
      const S = [...A.values()];
      return (w.set(I, S), S);
    }
    intersects(P, v) {
      if (!(P instanceof i)) throw new TypeError("a Range is required");
      return this.set.some(
        (I) =>
          E(I, v) &&
          P.set.some(
            (j) =>
              E(j, v) && I.every(($) => j.every((t) => $.intersects(t, v))),
          ),
      );
    }
    test(P) {
      if (!P) return !1;
      if (typeof P == "string")
        try {
          P = new l(P, this.options);
        } catch {
          return !1;
        }
      for (let v = 0; v < this.set.length; v++)
        if (U(this.set[v], P, this.options)) return !0;
      return !1;
    }
  }
  we = i;
  const b = rt(),
    w = new b(),
    a = ze(),
    c = lt(),
    o = V(),
    l = W(),
    {
      safeRe: n,
      t: f,
      comparatorTrimReplace: s,
      tildeTrimReplace: u,
      caretTrimReplace: r,
    } = Q(),
    { FLAG_INCLUDE_PRERELEASE: g, FLAG_LOOSE: h } = Oe(),
    m = (y) => y.value === "<0.0.0-0",
    p = (y) => y.value === "",
    E = (y, P) => {
      let v = !0;
      const I = y.slice();
      let j = I.pop();
      for (; v && I.length;)
        ((v = I.every(($) => j.intersects($, P))), (j = I.pop()));
      return v;
    },
    N = (y, P) => (
      o("comp", y, P),
      (y = B(y, P)),
      o("caret", y),
      (y = _(y, P)),
      o("tildes", y),
      (y = T(y, P)),
      o("xrange", y),
      (y = R(y, P)),
      o("stars", y),
      y
    ),
    k = (y) => !y || y.toLowerCase() === "x" || y === "*",
    _ = (y, P) =>
      y
        .trim()
        .split(/\s+/)
        .map((v) => F(v, P))
        .join(" "),
    F = (y, P) => {
      const v = P.loose ? n[f.TILDELOOSE] : n[f.TILDE];
      return y.replace(v, (I, j, $, t, x) => {
        o("tilde", y, I, j, $, t, x);
        let A;
        return (
          k(j)
            ? (A = "")
            : k($)
              ? (A = `>=${j}.0.0 <${+j + 1}.0.0-0`)
              : k(t)
                ? (A = `>=${j}.${$}.0 <${j}.${+$ + 1}.0-0`)
                : x
                  ? (o("replaceTilde pr", x),
                    (A = `>=${j}.${$}.${t}-${x} <${j}.${+$ + 1}.0-0`))
                  : (A = `>=${j}.${$}.${t} <${j}.${+$ + 1}.0-0`),
          o("tilde return", A),
          A
        );
      });
    },
    B = (y, P) =>
      y
        .trim()
        .split(/\s+/)
        .map((v) => D(v, P))
        .join(" "),
    D = (y, P) => {
      o("caret", y, P);
      const v = P.loose ? n[f.CARETLOOSE] : n[f.CARET],
        I = P.includePrerelease ? "-0" : "";
      return y.replace(v, (j, $, t, x, A) => {
        o("caret", y, j, $, t, x, A);
        let L;
        return (
          k($)
            ? (L = "")
            : k(t)
              ? (L = `>=${$}.0.0${I} <${+$ + 1}.0.0-0`)
              : k(x)
                ? $ === "0"
                  ? (L = `>=${$}.${t}.0${I} <${$}.${+t + 1}.0-0`)
                  : (L = `>=${$}.${t}.0${I} <${+$ + 1}.0.0-0`)
                : A
                  ? (o("replaceCaret pr", A),
                    $ === "0"
                      ? t === "0"
                        ? (L = `>=${$}.${t}.${x}-${A} <${$}.${t}.${+x + 1}-0`)
                        : (L = `>=${$}.${t}.${x}-${A} <${$}.${+t + 1}.0-0`)
                      : (L = `>=${$}.${t}.${x}-${A} <${+$ + 1}.0.0-0`))
                  : (o("no pr"),
                    $ === "0"
                      ? t === "0"
                        ? (L = `>=${$}.${t}.${x}${I} <${$}.${t}.${+x + 1}-0`)
                        : (L = `>=${$}.${t}.${x}${I} <${$}.${+t + 1}.0-0`)
                      : (L = `>=${$}.${t}.${x} <${+$ + 1}.0.0-0`)),
          o("caret return", L),
          L
        );
      });
    },
    T = (y, P) => (
      o("replaceXRanges", y, P),
      y
        .split(/\s+/)
        .map((v) => d(v, P))
        .join(" ")
    ),
    d = (y, P) => {
      y = y.trim();
      const v = P.loose ? n[f.XRANGELOOSE] : n[f.XRANGE];
      return y.replace(v, (I, j, $, t, x, A) => {
        o("xRange", y, I, j, $, t, x, A);
        const L = k($),
          S = L || k(t),
          C = S || k(x),
          z = C;
        return (
          j === "=" && z && (j = ""),
          (A = P.includePrerelease ? "-0" : ""),
          L
            ? j === ">" || j === "<"
              ? (I = "<0.0.0-0")
              : (I = "*")
            : j && z
              ? (S && (t = 0),
                (x = 0),
                j === ">"
                  ? ((j = ">="),
                    S
                      ? (($ = +$ + 1), (t = 0), (x = 0))
                      : ((t = +t + 1), (x = 0)))
                  : j === "<=" && ((j = "<"), S ? ($ = +$ + 1) : (t = +t + 1)),
                j === "<" && (A = "-0"),
                (I = `${j + $}.${t}.${x}${A}`))
              : S
                ? (I = `>=${$}.0.0${A} <${+$ + 1}.0.0-0`)
                : C && (I = `>=${$}.${t}.0${A} <${$}.${+t + 1}.0-0`),
          o("xRange return", I),
          I
        );
      });
    },
    R = (y, P) => (o("replaceStars", y, P), y.trim().replace(n[f.STAR], "")),
    q = (y, P) => (
      o("replaceGTE0", y, P),
      y.trim().replace(n[P.includePrerelease ? f.GTE0PRE : f.GTE0], "")
    ),
    M = (y) => (P, v, I, j, $, t, x, A, L, S, C, z) => (
      k(I)
        ? (v = "")
        : k(j)
          ? (v = `>=${I}.0.0${y ? "-0" : ""}`)
          : k($)
            ? (v = `>=${I}.${j}.0${y ? "-0" : ""}`)
            : t
              ? (v = `>=${v}`)
              : (v = `>=${v}${y ? "-0" : ""}`),
      k(L)
        ? (A = "")
        : k(S)
          ? (A = `<${+L + 1}.0.0-0`)
          : k(C)
            ? (A = `<${L}.${+S + 1}.0-0`)
            : z
              ? (A = `<=${L}.${S}.${C}-${z}`)
              : y
                ? (A = `<${L}.${S}.${+C + 1}-0`)
                : (A = `<=${A}`),
      `${v} ${A}`.trim()
    ),
    U = (y, P, v) => {
      for (let I = 0; I < y.length; I++) if (!y[I].test(P)) return !1;
      if (P.prerelease.length && !v.includePrerelease) {
        for (let I = 0; I < y.length; I++)
          if (
            (o(y[I].semver),
            y[I].semver !== c.ANY && y[I].semver.prerelease.length > 0)
          ) {
            const j = y[I].semver;
            if (
              j.major === P.major &&
              j.minor === P.minor &&
              j.patch === P.patch
            )
              return !0;
          }
        return !1;
      }
      return !0;
    };
  return we;
}
var Ee, ur;
function ft() {
  if (ur) return Ee;
  ur = 1;
  const e = qr();
  return (
    (Ee = (b, w, a) => {
      try {
        w = new e(w, a);
      } catch {
        return !1;
      }
      return w.test(b);
    }),
    Ee
  );
}
const ht = "0.34.3",
  ct = {
    "@img/sharp-darwin-arm64": "0.34.3",
    "@img/sharp-darwin-x64": "0.34.3",
    "@img/sharp-libvips-darwin-arm64": "1.2.0",
    "@img/sharp-libvips-darwin-x64": "1.2.0",
    "@img/sharp-libvips-linux-arm": "1.2.0",
    "@img/sharp-libvips-linux-arm64": "1.2.0",
    "@img/sharp-libvips-linux-ppc64": "1.2.0",
    "@img/sharp-libvips-linux-s390x": "1.2.0",
    "@img/sharp-libvips-linux-x64": "1.2.0",
    "@img/sharp-libvips-linuxmusl-arm64": "1.2.0",
    "@img/sharp-libvips-linuxmusl-x64": "1.2.0",
    "@img/sharp-linux-arm": "0.34.3",
    "@img/sharp-linux-arm64": "0.34.3",
    "@img/sharp-linux-ppc64": "0.34.3",
    "@img/sharp-linux-s390x": "0.34.3",
    "@img/sharp-linux-x64": "0.34.3",
    "@img/sharp-linuxmusl-arm64": "0.34.3",
    "@img/sharp-linuxmusl-x64": "0.34.3",
    "@img/sharp-wasm32": "0.34.3",
    "@img/sharp-win32-arm64": "0.34.3",
    "@img/sharp-win32-ia32": "0.34.3",
    "@img/sharp-win32-x64": "0.34.3",
  },
  ut = { node: "^18.17.0 || ^20.3.0 || >=21.0.0" },
  dt = { libvips: ">=8.17.1" },
  _r = { version: ht, optionalDependencies: ct, engines: ut, config: dt };
var ye, dr;
function Fr() {
  if (dr) return ye;
  dr = 1;
  const { spawnSync: e } = Ur,
    { createHash: i } = Hr,
    b = et(),
    w = Cr(),
    a = ft(),
    c = Me(),
    { config: o, engines: l, optionalDependencies: n } = _r,
    f = process.env.npm_package_config_libvips || o.libvips,
    s = b(f).version,
    u = [
      "darwin-arm64",
      "darwin-x64",
      "linux-arm",
      "linux-arm64",
      "linux-ppc64",
      "linux-s390x",
      "linux-x64",
      "linuxmusl-arm64",
      "linuxmusl-x64",
      "win32-arm64",
      "win32-ia32",
      "win32-x64",
    ],
    r = { encoding: "utf8", shell: !0 },
    g = (y) => {
      y instanceof Error
        ? console.error(`sharp: Installation error: ${y.message}`)
        : console.log(`sharp: ${y}`);
    },
    h = () => (c.isNonGlibcLinuxSync() ? c.familySync() : ""),
    m = () => `${process.platform}${h()}-${process.arch}`,
    p = () => {
      if (F()) return "wasm32";
      const {
          npm_config_arch: y,
          npm_config_platform: P,
          npm_config_libc: v,
        } = process.env,
        I = typeof v == "string" ? v : h();
      return `${P || process.platform}${I}-${y || process.arch}`;
    },
    E = () => {
      try {
        return O(`@img/sharp-libvips-dev-${p()}/include`);
      } catch {
        try {
          return O("@img/sharp-libvips-dev/include");
        } catch {}
      }
      return "";
    },
    N = () => {
      try {
        return O("@img/sharp-libvips-dev/cplusplus");
      } catch {}
      return "";
    },
    k = () => {
      try {
        return O(`@img/sharp-libvips-dev-${p()}/lib`);
      } catch {
        try {
          return O(`@img/sharp-libvips-${p()}/lib`);
        } catch {}
      }
      return "";
    },
    _ = () => {
      if (
        process.release?.name === "node" &&
        process.versions &&
        !a(process.versions.node, l.node)
      )
        return { found: process.versions.node, expected: l.node };
    },
    F = () => {
      const { CC: y } = process.env;
      return !!(y && y.endsWith("/emcc"));
    },
    B = () =>
      process.platform === "darwin" && process.arch === "x64"
        ? (e("sysctl sysctl.proc_translated", r).stdout || "").trim() ===
          "sysctl.proc_translated: 1"
        : !1,
    D = (y) => i("sha512").update(y).digest("hex"),
    T = () => {
      try {
        const y = D(`imgsharp-libvips-${p()}`),
          P = b(n[`@img/sharp-libvips-${p()}`], {
            includePrerelease: !0,
          }).version;
        return D(`${y}npm:${P}`).slice(0, 10);
      } catch {}
      return "";
    },
    d = () =>
      e(
        `node-gyp rebuild --directory=src ${F() ? "--nodedir=emscripten" : ""}`,
        { ...r, stdio: "inherit" },
      ).status,
    R = () =>
      process.platform !== "win32"
        ? (
            e("pkg-config --modversion vips-cpp", {
              ...r,
              env: { ...process.env, PKG_CONFIG_PATH: q() },
            }).stdout || ""
          ).trim()
        : "",
    q = () =>
      process.platform !== "win32"
        ? [
            (
              e(
                'which brew >/dev/null 2>&1 && brew environment --plain | grep PKG_CONFIG_LIBDIR | cut -d" " -f2',
                r,
              ).stdout || ""
            ).trim(),
            process.env.PKG_CONFIG_PATH,
            "/usr/local/lib/pkgconfig",
            "/usr/lib/pkgconfig",
            "/usr/local/libdata/pkgconfig",
            "/usr/libdata/pkgconfig",
          ]
            .filter(Boolean)
            .join(":")
        : "",
    M = (y, P, v) => (
      v && v(`Detected ${P}, skipping search for globally-installed libvips`),
      y
    );
  return (
    (ye = {
      minimumLibvipsVersion: s,
      prebuiltPlatforms: u,
      buildPlatformArch: p,
      buildSharpLibvipsIncludeDir: E,
      buildSharpLibvipsCPlusPlusDir: N,
      buildSharpLibvipsLibDir: k,
      isUnsupportedNodeRuntime: _,
      runtimePlatformArch: m,
      log: g,
      yarnLocator: T,
      spawnRebuild: d,
      globalLibvipsVersion: R,
      pkgConfigPath: q,
      useGlobalLibvips: (y) => {
        if (process.env.SHARP_IGNORE_GLOBAL_LIBVIPS)
          return M(!1, "SHARP_IGNORE_GLOBAL_LIBVIPS", y);
        if (process.env.SHARP_FORCE_GLOBAL_LIBVIPS)
          return M(!0, "SHARP_FORCE_GLOBAL_LIBVIPS", y);
        if (B()) return M(!1, "Rosetta", y);
        const P = R();
        return !!P && w(P, s);
      },
    }),
    ye
  );
}
var gr;
function Y() {
  if (gr) return J.exports;
  gr = 1;
  const { familySync: e, versionSync: i } = Me(),
    {
      runtimePlatformArch: b,
      isUnsupportedNodeRuntime: w,
      prebuiltPlatforms: a,
      minimumLibvipsVersion: c,
    } = Fr(),
    o = b(),
    l = [
      `../src/build/Release/sharp-${o}.node`,
      "../src/build/Release/sharp-wasm32.node",
      `@img/sharp-${o}/sharp.node`,
      "@img/sharp-wasm32/sharp.node",
    ];
  let n, f;
  const s = [];
  for (n of l)
    try {
      f = O(n);
      break;
    } catch (u) {
      s.push(u);
    }
  if (f && n.startsWith("@img/sharp-linux-x64") && !f._isUsingX64V2()) {
    const u = new Error(
      "Prebuilt binaries for linux-x64 require v2 microarchitecture",
    );
    ((u.code = "Unsupported CPU"), s.push(u), (f = null));
  }
  if (f) J.exports = f;
  else {
    const [u, r, g] = ["linux", "darwin", "win32"].map((p) => o.startsWith(p)),
      h = [`Could not load the "sharp" module using the ${o} runtime`];
    s.forEach((p) => {
      p.code !== "MODULE_NOT_FOUND" && h.push(`${p.code}: ${p.message}`);
    });
    const m = s.map((p) => p.message).join(" ");
    if ((h.push("Possible solutions:"), w())) {
      const { found: p, expected: E } = w();
      h.push(
        "- Please upgrade Node.js:",
        `    Found ${p}`,
        `    Requires ${E}`,
      );
    } else if (a.includes(o)) {
      const [p, E] = o.split("-"),
        N = p.endsWith("musl") ? " --libc=musl" : "";
      h.push(
        "- Ensure optional dependencies can be installed:",
        "    npm install --include=optional sharp",
        "- Ensure your package manager supports multi-platform installation:",
        "    See https://sharp.pixelplumbing.com/install#cross-platform",
        "- Add platform-specific dependencies:",
        `    npm install --os=${p.replace("musl", "")}${N} --cpu=${E} sharp`,
      );
    } else
      h.push(
        `- Manually install libvips >= ${c}`,
        "- Add experimental WebAssembly-based dependencies:",
        "    npm install --cpu=wasm32 sharp",
        "    npm install @img/sharp-wasm32",
      );
    if (u && /(symbol not found|CXXABI_)/i.test(m))
      try {
        const { config: p } = O(`@img/sharp-libvips-${o}/package`),
          E = `${e()} ${i()}`,
          N = `${p.musl ? "musl" : "glibc"} ${p.musl || p.glibc}`;
        h.push("- Update your OS:", `    Found ${E}`, `    Requires ${N}`);
      } catch {}
    throw (
      u &&
        /\/snap\/core[0-9]{2}/.test(m) &&
        h.push(
          "- Remove the Node.js Snap, which does not support native modules",
          "    snap remove node",
        ),
      r &&
        /Incompatible library version/.test(m) &&
        h.push("- Update Homebrew:", "    brew update && brew upgrade vips"),
      s.some((p) => p.code === "ERR_DLOPEN_DISABLED") &&
        h.push("- Run Node.js without using the --no-addons flag"),
      g &&
        /The specified procedure could not be found/.test(m) &&
        h.push(
          "- Using the canvas package on Windows?",
          "    See https://sharp.pixelplumbing.com/install#canvas-and-windows",
          "- Check for outdated versions of sharp in the dependency tree:",
          "    npm ls sharp",
        ),
      h.push(
        "- Consult the installation documentation:",
        "    See https://sharp.pixelplumbing.com/install",
      ),
      new Error(
        h.join(`
`),
      )
    );
  }
  return J.exports;
}
var Pe, mr;
function gt() {
  if (mr) return Pe;
  mr = 1;
  const e = Mr,
    i = Or,
    b = G();
  Y();
  const w = e.debuglog("sharp"),
    a = function (o, l) {
      if (arguments.length === 1 && !b.defined(o))
        throw new Error("Invalid input");
      return this instanceof a
        ? (i.Duplex.call(this),
          (this.options = {
            topOffsetPre: -1,
            leftOffsetPre: -1,
            widthPre: -1,
            heightPre: -1,
            topOffsetPost: -1,
            leftOffsetPost: -1,
            widthPost: -1,
            heightPost: -1,
            width: -1,
            height: -1,
            canvas: "crop",
            position: 0,
            resizeBackground: [0, 0, 0, 255],
            angle: 0,
            rotationAngle: 0,
            rotationBackground: [0, 0, 0, 255],
            rotateBeforePreExtract: !1,
            flip: !1,
            flop: !1,
            extendTop: 0,
            extendBottom: 0,
            extendLeft: 0,
            extendRight: 0,
            extendBackground: [0, 0, 0, 255],
            extendWith: "background",
            withoutEnlargement: !1,
            withoutReduction: !1,
            affineMatrix: [],
            affineBackground: [0, 0, 0, 255],
            affineIdx: 0,
            affineIdy: 0,
            affineOdx: 0,
            affineOdy: 0,
            affineInterpolator: this.constructor.interpolators.bilinear,
            kernel: "lanczos3",
            fastShrinkOnLoad: !0,
            tint: [-1, 0, 0, 0],
            flatten: !1,
            flattenBackground: [0, 0, 0],
            unflatten: !1,
            negate: !1,
            negateAlpha: !0,
            medianSize: 0,
            blurSigma: 0,
            precision: "integer",
            minAmpl: 0.2,
            sharpenSigma: 0,
            sharpenM1: 1,
            sharpenM2: 2,
            sharpenX1: 2,
            sharpenY2: 10,
            sharpenY3: 20,
            threshold: 0,
            thresholdGrayscale: !0,
            trimBackground: [],
            trimThreshold: -1,
            trimLineArt: !1,
            dilateWidth: 0,
            erodeWidth: 0,
            gamma: 0,
            gammaOut: 0,
            greyscale: !1,
            normalise: !1,
            normaliseLower: 1,
            normaliseUpper: 99,
            claheWidth: 0,
            claheHeight: 0,
            claheMaxSlope: 3,
            brightness: 1,
            saturation: 1,
            hue: 0,
            lightness: 0,
            booleanBufferIn: null,
            booleanFileIn: "",
            joinChannelIn: [],
            extractChannel: -1,
            removeAlpha: !1,
            ensureAlpha: -1,
            colourspace: "srgb",
            colourspacePipeline: "last",
            composite: [],
            fileOut: "",
            formatOut: "input",
            streamOut: !1,
            keepMetadata: 0,
            withMetadataOrientation: -1,
            withMetadataDensity: 0,
            withIccProfile: "",
            withExif: {},
            withExifMerge: !0,
            withXmp: "",
            resolveWithObject: !1,
            loop: -1,
            delay: [],
            jpegQuality: 80,
            jpegProgressive: !1,
            jpegChromaSubsampling: "4:2:0",
            jpegTrellisQuantisation: !1,
            jpegOvershootDeringing: !1,
            jpegOptimiseScans: !1,
            jpegOptimiseCoding: !0,
            jpegQuantisationTable: 0,
            pngProgressive: !1,
            pngCompressionLevel: 6,
            pngAdaptiveFiltering: !1,
            pngPalette: !1,
            pngQuality: 100,
            pngEffort: 7,
            pngBitdepth: 8,
            pngDither: 1,
            jp2Quality: 80,
            jp2TileHeight: 512,
            jp2TileWidth: 512,
            jp2Lossless: !1,
            jp2ChromaSubsampling: "4:4:4",
            webpQuality: 80,
            webpAlphaQuality: 100,
            webpLossless: !1,
            webpNearLossless: !1,
            webpSmartSubsample: !1,
            webpSmartDeblock: !1,
            webpPreset: "default",
            webpEffort: 4,
            webpMinSize: !1,
            webpMixed: !1,
            gifBitdepth: 8,
            gifEffort: 7,
            gifDither: 1,
            gifInterFrameMaxError: 0,
            gifInterPaletteMaxError: 3,
            gifKeepDuplicateFrames: !1,
            gifReuse: !0,
            gifProgressive: !1,
            tiffQuality: 80,
            tiffCompression: "jpeg",
            tiffPredictor: "horizontal",
            tiffPyramid: !1,
            tiffMiniswhite: !1,
            tiffBitdepth: 8,
            tiffTile: !1,
            tiffTileHeight: 256,
            tiffTileWidth: 256,
            tiffXres: 1,
            tiffYres: 1,
            tiffResolutionUnit: "inch",
            heifQuality: 50,
            heifLossless: !1,
            heifCompression: "av1",
            heifEffort: 4,
            heifChromaSubsampling: "4:4:4",
            heifBitdepth: 8,
            jxlDistance: 1,
            jxlDecodingTier: 0,
            jxlEffort: 7,
            jxlLossless: !1,
            rawDepth: "uchar",
            tileSize: 256,
            tileOverlap: 0,
            tileContainer: "fs",
            tileLayout: "dz",
            tileFormat: "last",
            tileDepth: "last",
            tileAngle: 0,
            tileSkipBlanks: -1,
            tileBackground: [255, 255, 255, 255],
            tileCentre: !1,
            tileId: "https://example.com/iiif",
            tileBasename: "",
            timeoutSeconds: 0,
            linearA: [],
            linearB: [],
            pdfBackground: [255, 255, 255, 255],
            debuglog: (n) => {
              (this.emit("warning", n), w(n));
            },
            queueListener: function (n) {
              a.queue.emit("change", n);
            },
          }),
          (this.options.input = this._createInputDescriptor(o, l, {
            allowStream: !0,
          })),
          this)
        : new a(o, l);
    };
  (Object.setPrototypeOf(a.prototype, i.Duplex.prototype),
    Object.setPrototypeOf(a, i.Duplex));
  function c() {
    const o = this.constructor.call(),
      { debuglog: l, queueListener: n, ...f } = this.options;
    return (
      (o.options = structuredClone(f)),
      (o.options.debuglog = l),
      (o.options.queueListener = n),
      this._isStreamInput() &&
        this.on("finish", () => {
          (this._flattenBufferIn(),
            (o.options.input.buffer = this.options.input.buffer),
            o.emit("finish"));
        }),
      o
    );
  }
  return (Object.assign(a.prototype, { clone: c }), (Pe = a), Pe);
}
var Re, br;
function mt() {
  if (br) return Re;
  br = 1;
  const e = G(),
    i = Y(),
    b = {
      left: "low",
      top: "low",
      low: "low",
      center: "centre",
      centre: "centre",
      right: "high",
      bottom: "high",
      high: "high",
    },
    w = [
      "failOn",
      "limitInputPixels",
      "unlimited",
      "animated",
      "autoOrient",
      "density",
      "ignoreIcc",
      "page",
      "pages",
      "sequentialRead",
      "jp2",
      "openSlide",
      "pdf",
      "raw",
      "svg",
      "tiff",
      "failOnError",
      "openSlideLevel",
      "pdfBackground",
      "tiffSubifd",
    ];
  function a(u) {
    const r = w.filter((g) => e.defined(u[g])).map((g) => [g, u[g]]);
    return r.length ? Object.fromEntries(r) : void 0;
  }
  function c(u, r, g) {
    const h = {
      autoOrient: !1,
      failOn: "warning",
      limitInputPixels: Math.pow(16383, 2),
      ignoreIcc: !1,
      unlimited: !1,
      sequentialRead: !0,
    };
    if (e.string(u)) h.file = u;
    else if (e.buffer(u)) {
      if (u.length === 0) throw Error("Input Buffer is empty");
      h.buffer = u;
    } else if (e.arrayBuffer(u)) {
      if (u.byteLength === 0) throw Error("Input bit Array is empty");
      h.buffer = Buffer.from(u, 0, u.byteLength);
    } else if (e.typedArray(u)) {
      if (u.length === 0) throw Error("Input Bit Array is empty");
      h.buffer = Buffer.from(u.buffer, u.byteOffset, u.byteLength);
    } else if (e.plainObject(u) && !e.defined(r))
      ((r = u), a(r) && (h.buffer = []));
    else if (!e.defined(u) && !e.defined(r) && e.object(g) && g.allowStream)
      h.buffer = [];
    else if (Array.isArray(u))
      if (u.length > 1)
        if (!this.options.joining)
          ((this.options.joining = !0),
            (this.options.join = u.map((m) => this._createInputDescriptor(m))));
        else throw new Error("Recursive join is unsupported");
      else throw new Error("Expected at least two images to join");
    else
      throw new Error(
        `Unsupported input '${u}' of type ${typeof u}${e.defined(r) ? ` when also providing options of type ${typeof r}` : ""}`,
      );
    if (e.object(r)) {
      if (e.defined(r.failOnError))
        if (e.bool(r.failOnError))
          h.failOn = r.failOnError ? "warning" : "none";
        else
          throw e.invalidParameterError(
            "failOnError",
            "boolean",
            r.failOnError,
          );
      if (e.defined(r.failOn))
        if (
          e.string(r.failOn) &&
          e.inArray(r.failOn, ["none", "truncated", "error", "warning"])
        )
          h.failOn = r.failOn;
        else
          throw e.invalidParameterError(
            "failOn",
            "one of: none, truncated, error, warning",
            r.failOn,
          );
      if (e.defined(r.autoOrient))
        if (e.bool(r.autoOrient)) h.autoOrient = r.autoOrient;
        else
          throw e.invalidParameterError("autoOrient", "boolean", r.autoOrient);
      if (e.defined(r.density))
        if (e.inRange(r.density, 1, 1e5)) h.density = r.density;
        else
          throw e.invalidParameterError(
            "density",
            "number between 1 and 100000",
            r.density,
          );
      if (e.defined(r.ignoreIcc))
        if (e.bool(r.ignoreIcc)) h.ignoreIcc = r.ignoreIcc;
        else throw e.invalidParameterError("ignoreIcc", "boolean", r.ignoreIcc);
      if (e.defined(r.limitInputPixels))
        if (e.bool(r.limitInputPixels))
          h.limitInputPixels = r.limitInputPixels ? Math.pow(16383, 2) : 0;
        else if (
          e.integer(r.limitInputPixels) &&
          e.inRange(r.limitInputPixels, 0, Number.MAX_SAFE_INTEGER)
        )
          h.limitInputPixels = r.limitInputPixels;
        else
          throw e.invalidParameterError(
            "limitInputPixels",
            "positive integer",
            r.limitInputPixels,
          );
      if (e.defined(r.unlimited))
        if (e.bool(r.unlimited)) h.unlimited = r.unlimited;
        else throw e.invalidParameterError("unlimited", "boolean", r.unlimited);
      if (e.defined(r.sequentialRead))
        if (e.bool(r.sequentialRead)) h.sequentialRead = r.sequentialRead;
        else
          throw e.invalidParameterError(
            "sequentialRead",
            "boolean",
            r.sequentialRead,
          );
      if (e.defined(r.raw)) {
        if (
          e.object(r.raw) &&
          e.integer(r.raw.width) &&
          r.raw.width > 0 &&
          e.integer(r.raw.height) &&
          r.raw.height > 0 &&
          e.integer(r.raw.channels) &&
          e.inRange(r.raw.channels, 1, 4)
        )
          switch (
            ((h.rawWidth = r.raw.width),
            (h.rawHeight = r.raw.height),
            (h.rawChannels = r.raw.channels),
            u.constructor)
          ) {
            case Uint8Array:
            case Uint8ClampedArray:
              h.rawDepth = "uchar";
              break;
            case Int8Array:
              h.rawDepth = "char";
              break;
            case Uint16Array:
              h.rawDepth = "ushort";
              break;
            case Int16Array:
              h.rawDepth = "short";
              break;
            case Uint32Array:
              h.rawDepth = "uint";
              break;
            case Int32Array:
              h.rawDepth = "int";
              break;
            case Float32Array:
              h.rawDepth = "float";
              break;
            case Float64Array:
              h.rawDepth = "double";
              break;
            default:
              h.rawDepth = "uchar";
              break;
          }
        else
          throw new Error(
            "Expected width, height and channels for raw pixel input",
          );
        if (((h.rawPremultiplied = !1), e.defined(r.raw.premultiplied)))
          if (e.bool(r.raw.premultiplied))
            h.rawPremultiplied = r.raw.premultiplied;
          else
            throw e.invalidParameterError(
              "raw.premultiplied",
              "boolean",
              r.raw.premultiplied,
            );
        if (((h.rawPageHeight = 0), e.defined(r.raw.pageHeight)))
          if (
            e.integer(r.raw.pageHeight) &&
            r.raw.pageHeight > 0 &&
            r.raw.pageHeight <= r.raw.height
          ) {
            if (r.raw.height % r.raw.pageHeight !== 0)
              throw new Error(
                `Expected raw.height ${r.raw.height} to be a multiple of raw.pageHeight ${r.raw.pageHeight}`,
              );
            h.rawPageHeight = r.raw.pageHeight;
          } else
            throw e.invalidParameterError(
              "raw.pageHeight",
              "positive integer",
              r.raw.pageHeight,
            );
      }
      if (e.defined(r.animated))
        if (e.bool(r.animated)) h.pages = r.animated ? -1 : 1;
        else throw e.invalidParameterError("animated", "boolean", r.animated);
      if (e.defined(r.pages))
        if (e.integer(r.pages) && e.inRange(r.pages, -1, 1e5))
          h.pages = r.pages;
        else
          throw e.invalidParameterError(
            "pages",
            "integer between -1 and 100000",
            r.pages,
          );
      if (e.defined(r.page))
        if (e.integer(r.page) && e.inRange(r.page, 0, 1e5)) h.page = r.page;
        else
          throw e.invalidParameterError(
            "page",
            "integer between 0 and 100000",
            r.page,
          );
      if (e.object(r.openSlide) && e.defined(r.openSlide.level))
        if (
          e.integer(r.openSlide.level) &&
          e.inRange(r.openSlide.level, 0, 256)
        )
          h.openSlideLevel = r.openSlide.level;
        else
          throw e.invalidParameterError(
            "openSlide.level",
            "integer between 0 and 256",
            r.openSlide.level,
          );
      else if (e.defined(r.level))
        if (e.integer(r.level) && e.inRange(r.level, 0, 256))
          h.openSlideLevel = r.level;
        else
          throw e.invalidParameterError(
            "level",
            "integer between 0 and 256",
            r.level,
          );
      if (e.object(r.tiff) && e.defined(r.tiff.subifd))
        if (e.integer(r.tiff.subifd) && e.inRange(r.tiff.subifd, -1, 1e5))
          h.tiffSubifd = r.tiff.subifd;
        else
          throw e.invalidParameterError(
            "tiff.subifd",
            "integer between -1 and 100000",
            r.tiff.subifd,
          );
      else if (e.defined(r.subifd))
        if (e.integer(r.subifd) && e.inRange(r.subifd, -1, 1e5))
          h.tiffSubifd = r.subifd;
        else
          throw e.invalidParameterError(
            "subifd",
            "integer between -1 and 100000",
            r.subifd,
          );
      if (e.object(r.svg)) {
        if (e.defined(r.svg.stylesheet))
          if (e.string(r.svg.stylesheet)) h.svgStylesheet = r.svg.stylesheet;
          else
            throw e.invalidParameterError(
              "svg.stylesheet",
              "string",
              r.svg.stylesheet,
            );
        if (e.defined(r.svg.highBitdepth))
          if (e.bool(r.svg.highBitdepth))
            h.svgHighBitdepth = r.svg.highBitdepth;
          else
            throw e.invalidParameterError(
              "svg.highBitdepth",
              "boolean",
              r.svg.highBitdepth,
            );
      }
      if (
        (e.object(r.pdf) && e.defined(r.pdf.background)
          ? (h.pdfBackground = this._getBackgroundColourOption(
              r.pdf.background,
            ))
          : e.defined(r.pdfBackground) &&
            (h.pdfBackground = this._getBackgroundColourOption(
              r.pdfBackground,
            )),
        e.object(r.jp2) && e.defined(r.jp2.oneshot))
      )
        if (e.bool(r.jp2.oneshot)) h.jp2Oneshot = r.jp2.oneshot;
        else
          throw e.invalidParameterError(
            "jp2.oneshot",
            "boolean",
            r.jp2.oneshot,
          );
      if (e.defined(r.create))
        if (
          e.object(r.create) &&
          e.integer(r.create.width) &&
          r.create.width > 0 &&
          e.integer(r.create.height) &&
          r.create.height > 0 &&
          e.integer(r.create.channels)
        ) {
          if (
            ((h.createWidth = r.create.width),
            (h.createHeight = r.create.height),
            (h.createChannels = r.create.channels),
            (h.createPageHeight = 0),
            e.defined(r.create.pageHeight))
          )
            if (
              e.integer(r.create.pageHeight) &&
              r.create.pageHeight > 0 &&
              r.create.pageHeight <= r.create.height
            ) {
              if (r.create.height % r.create.pageHeight !== 0)
                throw new Error(
                  `Expected create.height ${r.create.height} to be a multiple of create.pageHeight ${r.create.pageHeight}`,
                );
              h.createPageHeight = r.create.pageHeight;
            } else
              throw e.invalidParameterError(
                "create.pageHeight",
                "positive integer",
                r.create.pageHeight,
              );
          if (e.defined(r.create.noise)) {
            if (!e.object(r.create.noise))
              throw new Error("Expected noise to be an object");
            if (r.create.noise.type !== "gaussian")
              throw new Error("Only gaussian noise is supported at the moment");
            if (
              ((h.createNoiseType = r.create.noise.type),
              !e.inRange(r.create.channels, 1, 4))
            )
              throw e.invalidParameterError(
                "create.channels",
                "number between 1 and 4",
                r.create.channels,
              );
            if (((h.createNoiseMean = 128), e.defined(r.create.noise.mean)))
              if (
                e.number(r.create.noise.mean) &&
                e.inRange(r.create.noise.mean, 0, 1e4)
              )
                h.createNoiseMean = r.create.noise.mean;
              else
                throw e.invalidParameterError(
                  "create.noise.mean",
                  "number between 0 and 10000",
                  r.create.noise.mean,
                );
            if (((h.createNoiseSigma = 30), e.defined(r.create.noise.sigma)))
              if (
                e.number(r.create.noise.sigma) &&
                e.inRange(r.create.noise.sigma, 0, 1e4)
              )
                h.createNoiseSigma = r.create.noise.sigma;
              else
                throw e.invalidParameterError(
                  "create.noise.sigma",
                  "number between 0 and 10000",
                  r.create.noise.sigma,
                );
          } else if (e.defined(r.create.background)) {
            if (!e.inRange(r.create.channels, 3, 4))
              throw e.invalidParameterError(
                "create.channels",
                "number between 3 and 4",
                r.create.channels,
              );
            h.createBackground = this._getBackgroundColourOption(
              r.create.background,
            );
          } else
            throw new Error(
              "Expected valid noise or background to create a new input image",
            );
          delete h.buffer;
        } else
          throw new Error(
            "Expected valid width, height and channels to create a new input image",
          );
      if (e.defined(r.text))
        if (e.object(r.text) && e.string(r.text.text)) {
          if (
            ((h.textValue = r.text.text),
            e.defined(r.text.height) && e.defined(r.text.dpi))
          )
            throw new Error("Expected only one of dpi or height");
          if (e.defined(r.text.font))
            if (e.string(r.text.font)) h.textFont = r.text.font;
            else
              throw e.invalidParameterError("text.font", "string", r.text.font);
          if (e.defined(r.text.fontfile))
            if (e.string(r.text.fontfile)) h.textFontfile = r.text.fontfile;
            else
              throw e.invalidParameterError(
                "text.fontfile",
                "string",
                r.text.fontfile,
              );
          if (e.defined(r.text.width))
            if (e.integer(r.text.width) && r.text.width > 0)
              h.textWidth = r.text.width;
            else
              throw e.invalidParameterError(
                "text.width",
                "positive integer",
                r.text.width,
              );
          if (e.defined(r.text.height))
            if (e.integer(r.text.height) && r.text.height > 0)
              h.textHeight = r.text.height;
            else
              throw e.invalidParameterError(
                "text.height",
                "positive integer",
                r.text.height,
              );
          if (e.defined(r.text.align))
            if (
              e.string(r.text.align) &&
              e.string(this.constructor.align[r.text.align])
            )
              h.textAlign = this.constructor.align[r.text.align];
            else
              throw e.invalidParameterError(
                "text.align",
                "valid alignment",
                r.text.align,
              );
          if (e.defined(r.text.justify))
            if (e.bool(r.text.justify)) h.textJustify = r.text.justify;
            else
              throw e.invalidParameterError(
                "text.justify",
                "boolean",
                r.text.justify,
              );
          if (e.defined(r.text.dpi))
            if (e.integer(r.text.dpi) && e.inRange(r.text.dpi, 1, 1e6))
              h.textDpi = r.text.dpi;
            else
              throw e.invalidParameterError(
                "text.dpi",
                "integer between 1 and 1000000",
                r.text.dpi,
              );
          if (e.defined(r.text.rgba))
            if (e.bool(r.text.rgba)) h.textRgba = r.text.rgba;
            else
              throw e.invalidParameterError("text.rgba", "bool", r.text.rgba);
          if (e.defined(r.text.spacing))
            if (
              e.integer(r.text.spacing) &&
              e.inRange(r.text.spacing, -1e6, 1e6)
            )
              h.textSpacing = r.text.spacing;
            else
              throw e.invalidParameterError(
                "text.spacing",
                "integer between -1000000 and 1000000",
                r.text.spacing,
              );
          if (e.defined(r.text.wrap))
            if (
              e.string(r.text.wrap) &&
              e.inArray(r.text.wrap, ["word", "char", "word-char", "none"])
            )
              h.textWrap = r.text.wrap;
            else
              throw e.invalidParameterError(
                "text.wrap",
                "one of: word, char, word-char, none",
                r.text.wrap,
              );
          delete h.buffer;
        } else
          throw new Error(
            "Expected a valid string to create an image with text.",
          );
      if (e.defined(r.join))
        if (e.defined(this.options.join)) {
          if (e.defined(r.join.animated))
            if (e.bool(r.join.animated)) h.joinAnimated = r.join.animated;
            else
              throw e.invalidParameterError(
                "join.animated",
                "boolean",
                r.join.animated,
              );
          if (e.defined(r.join.across))
            if (e.integer(r.join.across) && e.inRange(r.join.across, 1, 1e6))
              h.joinAcross = r.join.across;
            else
              throw e.invalidParameterError(
                "join.across",
                "integer between 1 and 100000",
                r.join.across,
              );
          if (e.defined(r.join.shim))
            if (e.integer(r.join.shim) && e.inRange(r.join.shim, 0, 1e6))
              h.joinShim = r.join.shim;
            else
              throw e.invalidParameterError(
                "join.shim",
                "integer between 0 and 100000",
                r.join.shim,
              );
          if (
            (e.defined(r.join.background) &&
              (h.joinBackground = this._getBackgroundColourOption(
                r.join.background,
              )),
            e.defined(r.join.halign))
          )
            if (
              e.string(r.join.halign) &&
              e.string(this.constructor.align[r.join.halign])
            )
              h.joinHalign = this.constructor.align[r.join.halign];
            else
              throw e.invalidParameterError(
                "join.halign",
                "valid alignment",
                r.join.halign,
              );
          if (e.defined(r.join.valign))
            if (
              e.string(r.join.valign) &&
              e.string(this.constructor.align[r.join.valign])
            )
              h.joinValign = this.constructor.align[r.join.valign];
            else
              throw e.invalidParameterError(
                "join.valign",
                "valid alignment",
                r.join.valign,
              );
        } else
          throw new Error("Expected input to be an array of images to join");
    } else if (e.defined(r)) throw new Error("Invalid input options " + r);
    return h;
  }
  function o(u, r, g) {
    Array.isArray(this.options.input.buffer)
      ? e.buffer(u)
        ? (this.options.input.buffer.length === 0 &&
            this.on("finish", () => {
              this.streamInFinished = !0;
            }),
          this.options.input.buffer.push(u),
          g())
        : g(new Error("Non-Buffer data on Writable Stream"))
      : g(new Error("Unexpected data on Writable Stream"));
  }
  function l() {
    this._isStreamInput() &&
      (this.options.input.buffer = Buffer.concat(this.options.input.buffer));
  }
  function n() {
    return Array.isArray(this.options.input.buffer);
  }
  function f(u) {
    const r = Error();
    return e.fn(u)
      ? (this._isStreamInput()
          ? this.on("finish", () => {
              (this._flattenBufferIn(),
                i.metadata(this.options, (g, h) => {
                  g ? u(e.nativeError(g, r)) : u(null, h);
                }));
            })
          : i.metadata(this.options, (g, h) => {
              g ? u(e.nativeError(g, r)) : u(null, h);
            }),
        this)
      : this._isStreamInput()
        ? new Promise((g, h) => {
            const m = () => {
              (this._flattenBufferIn(),
                i.metadata(this.options, (p, E) => {
                  p ? h(e.nativeError(p, r)) : g(E);
                }));
            };
            this.writableFinished ? m() : this.once("finish", m);
          })
        : new Promise((g, h) => {
            i.metadata(this.options, (m, p) => {
              m ? h(e.nativeError(m, r)) : g(p);
            });
          });
  }
  function s(u) {
    const r = Error();
    return e.fn(u)
      ? (this._isStreamInput()
          ? this.on("finish", () => {
              (this._flattenBufferIn(),
                i.stats(this.options, (g, h) => {
                  g ? u(e.nativeError(g, r)) : u(null, h);
                }));
            })
          : i.stats(this.options, (g, h) => {
              g ? u(e.nativeError(g, r)) : u(null, h);
            }),
        this)
      : this._isStreamInput()
        ? new Promise((g, h) => {
            this.on("finish", function () {
              (this._flattenBufferIn(),
                i.stats(this.options, (m, p) => {
                  m ? h(e.nativeError(m, r)) : g(p);
                }));
            });
          })
        : new Promise((g, h) => {
            i.stats(this.options, (m, p) => {
              m ? h(e.nativeError(m, r)) : g(p);
            });
          });
  }
  return (
    (Re = function (u) {
      (Object.assign(u.prototype, {
        _inputOptionsFromObject: a,
        _createInputDescriptor: c,
        _write: o,
        _flattenBufferIn: l,
        _isStreamInput: n,
        metadata: f,
        stats: s,
      }),
        (u.align = b));
    }),
    Re
  );
}
var xe, pr;
function bt() {
  if (pr) return xe;
  pr = 1;
  const e = G(),
    i = {
      center: 0,
      centre: 0,
      north: 1,
      east: 2,
      south: 3,
      west: 4,
      northeast: 5,
      southeast: 6,
      southwest: 7,
      northwest: 8,
    },
    b = {
      top: 1,
      right: 2,
      bottom: 3,
      left: 4,
      "right top": 5,
      "right bottom": 6,
      "left bottom": 7,
      "left top": 8,
    },
    w = {
      background: "background",
      copy: "copy",
      repeat: "repeat",
      mirror: "mirror",
    },
    a = { entropy: 16, attention: 17 },
    c = {
      nearest: "nearest",
      linear: "linear",
      cubic: "cubic",
      mitchell: "mitchell",
      lanczos2: "lanczos2",
      lanczos3: "lanczos3",
      mks2013: "mks2013",
      mks2021: "mks2021",
    },
    o = {
      contain: "contain",
      cover: "cover",
      fill: "fill",
      inside: "inside",
      outside: "outside",
    },
    l = {
      contain: "embed",
      cover: "crop",
      fill: "ignore_aspect",
      inside: "max",
      outside: "min",
    };
  function n(h) {
    return (
      h.angle % 360 !== 0 || h.input.autoOrient === !0 || h.rotationAngle !== 0
    );
  }
  function f(h) {
    return h.width !== -1 || h.height !== -1;
  }
  function s(h, m, p) {
    if (
      (f(this.options) &&
        this.options.debuglog("ignoring previous resize options"),
      this.options.widthPost !== -1 &&
        this.options.debuglog(
          "operation order will be: extract, resize, extract",
        ),
      e.defined(h))
    )
      if (e.object(h) && !e.defined(p)) p = h;
      else if (e.integer(h) && h > 0) this.options.width = h;
      else throw e.invalidParameterError("width", "positive integer", h);
    else this.options.width = -1;
    if (e.defined(m))
      if (e.integer(m) && m > 0) this.options.height = m;
      else throw e.invalidParameterError("height", "positive integer", m);
    else this.options.height = -1;
    if (e.object(p)) {
      if (e.defined(p.width))
        if (e.integer(p.width) && p.width > 0) this.options.width = p.width;
        else
          throw e.invalidParameterError("width", "positive integer", p.width);
      if (e.defined(p.height))
        if (e.integer(p.height) && p.height > 0) this.options.height = p.height;
        else
          throw e.invalidParameterError("height", "positive integer", p.height);
      if (e.defined(p.fit)) {
        const E = l[p.fit];
        if (e.string(E)) this.options.canvas = E;
        else throw e.invalidParameterError("fit", "valid fit", p.fit);
      }
      if (e.defined(p.position)) {
        const E = e.integer(p.position)
          ? p.position
          : a[p.position] || b[p.position] || i[p.position];
        if (e.integer(E) && (e.inRange(E, 0, 8) || e.inRange(E, 16, 17)))
          this.options.position = E;
        else
          throw e.invalidParameterError(
            "position",
            "valid position/gravity/strategy",
            p.position,
          );
      }
      if (
        (this._setBackgroundColourOption("resizeBackground", p.background),
        e.defined(p.kernel))
      )
        if (e.string(c[p.kernel])) this.options.kernel = c[p.kernel];
        else
          throw e.invalidParameterError(
            "kernel",
            "valid kernel name",
            p.kernel,
          );
      (e.defined(p.withoutEnlargement) &&
        this._setBooleanOption("withoutEnlargement", p.withoutEnlargement),
        e.defined(p.withoutReduction) &&
          this._setBooleanOption("withoutReduction", p.withoutReduction),
        e.defined(p.fastShrinkOnLoad) &&
          this._setBooleanOption("fastShrinkOnLoad", p.fastShrinkOnLoad));
    }
    return (
      n(this.options) &&
        f(this.options) &&
        (this.options.rotateBeforePreExtract = !0),
      this
    );
  }
  function u(h) {
    if (e.integer(h) && h > 0)
      ((this.options.extendTop = h),
        (this.options.extendBottom = h),
        (this.options.extendLeft = h),
        (this.options.extendRight = h));
    else if (e.object(h)) {
      if (e.defined(h.top))
        if (e.integer(h.top) && h.top >= 0) this.options.extendTop = h.top;
        else throw e.invalidParameterError("top", "positive integer", h.top);
      if (e.defined(h.bottom))
        if (e.integer(h.bottom) && h.bottom >= 0)
          this.options.extendBottom = h.bottom;
        else
          throw e.invalidParameterError("bottom", "positive integer", h.bottom);
      if (e.defined(h.left))
        if (e.integer(h.left) && h.left >= 0) this.options.extendLeft = h.left;
        else throw e.invalidParameterError("left", "positive integer", h.left);
      if (e.defined(h.right))
        if (e.integer(h.right) && h.right >= 0)
          this.options.extendRight = h.right;
        else
          throw e.invalidParameterError("right", "positive integer", h.right);
      if (
        (this._setBackgroundColourOption("extendBackground", h.background),
        e.defined(h.extendWith))
      )
        if (e.string(w[h.extendWith]))
          this.options.extendWith = w[h.extendWith];
        else
          throw e.invalidParameterError(
            "extendWith",
            "one of: background, copy, repeat, mirror",
            h.extendWith,
          );
    } else throw e.invalidParameterError("extend", "integer or object", h);
    return this;
  }
  function r(h) {
    const m = f(this.options) || this.options.widthPre !== -1 ? "Post" : "Pre";
    return (
      this.options[`width${m}`] !== -1 &&
        this.options.debuglog("ignoring previous extract options"),
      ["left", "top", "width", "height"].forEach(function (p) {
        const E = h[p];
        if (e.integer(E) && E >= 0)
          this.options[p + (p === "left" || p === "top" ? "Offset" : "") + m] =
            E;
        else throw e.invalidParameterError(p, "integer", E);
      }, this),
      n(this.options) &&
        !f(this.options) &&
        (this.options.widthPre === -1 || this.options.widthPost === -1) &&
        (this.options.rotateBeforePreExtract = !0),
      this
    );
  }
  function g(h) {
    if (((this.options.trimThreshold = 10), e.defined(h)))
      if (e.object(h)) {
        if (
          (e.defined(h.background) &&
            this._setBackgroundColourOption("trimBackground", h.background),
          e.defined(h.threshold))
        )
          if (e.number(h.threshold) && h.threshold >= 0)
            this.options.trimThreshold = h.threshold;
          else
            throw e.invalidParameterError(
              "threshold",
              "positive number",
              h.threshold,
            );
        e.defined(h.lineArt) &&
          this._setBooleanOption("trimLineArt", h.lineArt);
      } else throw e.invalidParameterError("trim", "object", h);
    return (
      n(this.options) && (this.options.rotateBeforePreExtract = !0),
      this
    );
  }
  return (
    (xe = function (h) {
      (Object.assign(h.prototype, {
        resize: s,
        extend: u,
        extract: r,
        trim: g,
      }),
        (h.gravity = i),
        (h.strategy = a),
        (h.kernel = c),
        (h.fit = o),
        (h.position = b));
    }),
    xe
  );
}
var Ie, vr;
function pt() {
  if (vr) return Ie;
  vr = 1;
  const e = G(),
    i = {
      clear: "clear",
      source: "source",
      over: "over",
      in: "in",
      out: "out",
      atop: "atop",
      dest: "dest",
      "dest-over": "dest-over",
      "dest-in": "dest-in",
      "dest-out": "dest-out",
      "dest-atop": "dest-atop",
      xor: "xor",
      add: "add",
      saturate: "saturate",
      multiply: "multiply",
      screen: "screen",
      overlay: "overlay",
      darken: "darken",
      lighten: "lighten",
      "colour-dodge": "colour-dodge",
      "color-dodge": "colour-dodge",
      "colour-burn": "colour-burn",
      "color-burn": "colour-burn",
      "hard-light": "hard-light",
      "soft-light": "soft-light",
      difference: "difference",
      exclusion: "exclusion",
    };
  function b(w) {
    if (!Array.isArray(w))
      throw e.invalidParameterError("images to composite", "array", w);
    return (
      (this.options.composite = w.map((a) => {
        if (!e.object(a))
          throw e.invalidParameterError("image to composite", "object", a);
        const c = this._inputOptionsFromObject(a),
          o = {
            input: this._createInputDescriptor(a.input, c, { allowStream: !1 }),
            blend: "over",
            tile: !1,
            left: 0,
            top: 0,
            hasOffset: !1,
            gravity: 0,
            premultiplied: !1,
          };
        if (e.defined(a.blend))
          if (e.string(i[a.blend])) o.blend = i[a.blend];
          else
            throw e.invalidParameterError("blend", "valid blend name", a.blend);
        if (e.defined(a.tile))
          if (e.bool(a.tile)) o.tile = a.tile;
          else throw e.invalidParameterError("tile", "boolean", a.tile);
        if (e.defined(a.left))
          if (e.integer(a.left)) o.left = a.left;
          else throw e.invalidParameterError("left", "integer", a.left);
        if (e.defined(a.top))
          if (e.integer(a.top)) o.top = a.top;
          else throw e.invalidParameterError("top", "integer", a.top);
        if (e.defined(a.top) !== e.defined(a.left))
          throw new Error("Expected both left and top to be set");
        if (
          ((o.hasOffset = e.integer(a.top) && e.integer(a.left)),
          e.defined(a.gravity))
        )
          if (e.integer(a.gravity) && e.inRange(a.gravity, 0, 8))
            o.gravity = a.gravity;
          else if (
            e.string(a.gravity) &&
            e.integer(this.constructor.gravity[a.gravity])
          )
            o.gravity = this.constructor.gravity[a.gravity];
          else
            throw e.invalidParameterError(
              "gravity",
              "valid gravity",
              a.gravity,
            );
        if (e.defined(a.premultiplied))
          if (e.bool(a.premultiplied)) o.premultiplied = a.premultiplied;
          else
            throw e.invalidParameterError(
              "premultiplied",
              "boolean",
              a.premultiplied,
            );
        return o;
      })),
      this
    );
  }
  return (
    (Ie = function (w) {
      ((w.prototype.composite = b), (w.blend = i));
    }),
    Ie
  );
}
var Ae, wr;
function vt() {
  if (wr) return Ae;
  wr = 1;
  const e = G(),
    i = { integer: "integer", float: "float", approximate: "approximate" };
  function b(d, R) {
    if (!e.defined(d)) return this.autoOrient();
    if (
      ((this.options.angle || this.options.rotationAngle) &&
        (this.options.debuglog("ignoring previous rotate options"),
        (this.options.angle = 0),
        (this.options.rotationAngle = 0)),
      e.integer(d) && !(d % 90))
    )
      this.options.angle = d;
    else if (e.number(d))
      ((this.options.rotationAngle = d),
        e.object(R) &&
          R.background &&
          this._setBackgroundColourOption("rotationBackground", R.background));
    else throw e.invalidParameterError("angle", "numeric", d);
    return this;
  }
  function w() {
    return ((this.options.input.autoOrient = !0), this);
  }
  function a(d) {
    return ((this.options.flip = e.bool(d) ? d : !0), this);
  }
  function c(d) {
    return ((this.options.flop = e.bool(d) ? d : !0), this);
  }
  function o(d, R) {
    const q = [].concat(...d);
    if (q.length === 4 && q.every(e.number)) this.options.affineMatrix = q;
    else throw e.invalidParameterError("matrix", "1x4 or 2x2 array", d);
    if (e.defined(R))
      if (e.object(R)) {
        if (
          (this._setBackgroundColourOption("affineBackground", R.background),
          e.defined(R.idx))
        )
          if (e.number(R.idx)) this.options.affineIdx = R.idx;
          else throw e.invalidParameterError("options.idx", "number", R.idx);
        if (e.defined(R.idy))
          if (e.number(R.idy)) this.options.affineIdy = R.idy;
          else throw e.invalidParameterError("options.idy", "number", R.idy);
        if (e.defined(R.odx))
          if (e.number(R.odx)) this.options.affineOdx = R.odx;
          else throw e.invalidParameterError("options.odx", "number", R.odx);
        if (e.defined(R.ody))
          if (e.number(R.ody)) this.options.affineOdy = R.ody;
          else throw e.invalidParameterError("options.ody", "number", R.ody);
        if (e.defined(R.interpolator))
          if (
            e.inArray(
              R.interpolator,
              Object.values(this.constructor.interpolators),
            )
          )
            this.options.affineInterpolator = R.interpolator;
          else
            throw e.invalidParameterError(
              "options.interpolator",
              "valid interpolator name",
              R.interpolator,
            );
      } else throw e.invalidParameterError("options", "object", R);
    return this;
  }
  function l(d, R, q) {
    if (!e.defined(d)) this.options.sharpenSigma = -1;
    else if (e.bool(d)) this.options.sharpenSigma = d ? -1 : 0;
    else if (e.number(d) && e.inRange(d, 0.01, 1e4)) {
      if (((this.options.sharpenSigma = d), e.defined(R)))
        if (e.number(R) && e.inRange(R, 0, 1e4)) this.options.sharpenM1 = R;
        else
          throw e.invalidParameterError(
            "flat",
            "number between 0 and 10000",
            R,
          );
      if (e.defined(q))
        if (e.number(q) && e.inRange(q, 0, 1e4)) this.options.sharpenM2 = q;
        else
          throw e.invalidParameterError(
            "jagged",
            "number between 0 and 10000",
            q,
          );
    } else if (e.plainObject(d)) {
      if (e.number(d.sigma) && e.inRange(d.sigma, 1e-6, 10))
        this.options.sharpenSigma = d.sigma;
      else
        throw e.invalidParameterError(
          "options.sigma",
          "number between 0.000001 and 10",
          d.sigma,
        );
      if (e.defined(d.m1))
        if (e.number(d.m1) && e.inRange(d.m1, 0, 1e6))
          this.options.sharpenM1 = d.m1;
        else
          throw e.invalidParameterError(
            "options.m1",
            "number between 0 and 1000000",
            d.m1,
          );
      if (e.defined(d.m2))
        if (e.number(d.m2) && e.inRange(d.m2, 0, 1e6))
          this.options.sharpenM2 = d.m2;
        else
          throw e.invalidParameterError(
            "options.m2",
            "number between 0 and 1000000",
            d.m2,
          );
      if (e.defined(d.x1))
        if (e.number(d.x1) && e.inRange(d.x1, 0, 1e6))
          this.options.sharpenX1 = d.x1;
        else
          throw e.invalidParameterError(
            "options.x1",
            "number between 0 and 1000000",
            d.x1,
          );
      if (e.defined(d.y2))
        if (e.number(d.y2) && e.inRange(d.y2, 0, 1e6))
          this.options.sharpenY2 = d.y2;
        else
          throw e.invalidParameterError(
            "options.y2",
            "number between 0 and 1000000",
            d.y2,
          );
      if (e.defined(d.y3))
        if (e.number(d.y3) && e.inRange(d.y3, 0, 1e6))
          this.options.sharpenY3 = d.y3;
        else
          throw e.invalidParameterError(
            "options.y3",
            "number between 0 and 1000000",
            d.y3,
          );
    } else
      throw e.invalidParameterError(
        "sigma",
        "number between 0.01 and 10000",
        d,
      );
    return this;
  }
  function n(d) {
    if (!e.defined(d)) this.options.medianSize = 3;
    else if (e.integer(d) && e.inRange(d, 1, 1e3)) this.options.medianSize = d;
    else throw e.invalidParameterError("size", "integer between 1 and 1000", d);
    return this;
  }
  function f(d) {
    let R;
    if (e.number(d)) R = d;
    else if (e.plainObject(d)) {
      if (!e.number(d.sigma))
        throw e.invalidParameterError(
          "options.sigma",
          "number between 0.3 and 1000",
          R,
        );
      if (((R = d.sigma), "precision" in d))
        if (e.string(i[d.precision])) this.options.precision = i[d.precision];
        else
          throw e.invalidParameterError(
            "precision",
            "one of: integer, float, approximate",
            d.precision,
          );
      if ("minAmplitude" in d)
        if (e.number(d.minAmplitude) && e.inRange(d.minAmplitude, 0.001, 1))
          this.options.minAmpl = d.minAmplitude;
        else
          throw e.invalidParameterError(
            "minAmplitude",
            "number between 0.001 and 1",
            d.minAmplitude,
          );
    }
    if (!e.defined(d)) this.options.blurSigma = -1;
    else if (e.bool(d)) this.options.blurSigma = d ? -1 : 0;
    else if (e.number(R) && e.inRange(R, 0.3, 1e3)) this.options.blurSigma = R;
    else
      throw e.invalidParameterError("sigma", "number between 0.3 and 1000", R);
    return this;
  }
  function s(d) {
    if (!e.defined(d)) this.options.dilateWidth = 1;
    else if (e.integer(d) && d > 0) this.options.dilateWidth = d;
    else throw e.invalidParameterError("dilate", "positive integer", s);
    return this;
  }
  function u(d) {
    if (!e.defined(d)) this.options.erodeWidth = 1;
    else if (e.integer(d) && d > 0) this.options.erodeWidth = d;
    else throw e.invalidParameterError("erode", "positive integer", u);
    return this;
  }
  function r(d) {
    return (
      (this.options.flatten = e.bool(d) ? d : !0),
      e.object(d) &&
        this._setBackgroundColourOption("flattenBackground", d.background),
      this
    );
  }
  function g() {
    return ((this.options.unflatten = !0), this);
  }
  function h(d, R) {
    if (!e.defined(d)) this.options.gamma = 2.2;
    else if (e.number(d) && e.inRange(d, 1, 3)) this.options.gamma = d;
    else
      throw e.invalidParameterError("gamma", "number between 1.0 and 3.0", d);
    if (!e.defined(R)) this.options.gammaOut = this.options.gamma;
    else if (e.number(R) && e.inRange(R, 1, 3)) this.options.gammaOut = R;
    else
      throw e.invalidParameterError(
        "gammaOut",
        "number between 1.0 and 3.0",
        R,
      );
    return this;
  }
  function m(d) {
    if (
      ((this.options.negate = e.bool(d) ? d : !0),
      e.plainObject(d) && "alpha" in d)
    )
      if (e.bool(d.alpha)) this.options.negateAlpha = d.alpha;
      else
        throw e.invalidParameterError(
          "alpha",
          "should be boolean value",
          d.alpha,
        );
    return this;
  }
  function p(d) {
    if (e.plainObject(d)) {
      if (e.defined(d.lower))
        if (e.number(d.lower) && e.inRange(d.lower, 0, 99))
          this.options.normaliseLower = d.lower;
        else
          throw e.invalidParameterError(
            "lower",
            "number between 0 and 99",
            d.lower,
          );
      if (e.defined(d.upper))
        if (e.number(d.upper) && e.inRange(d.upper, 1, 100))
          this.options.normaliseUpper = d.upper;
        else
          throw e.invalidParameterError(
            "upper",
            "number between 1 and 100",
            d.upper,
          );
    }
    if (this.options.normaliseLower >= this.options.normaliseUpper)
      throw e.invalidParameterError(
        "range",
        "lower to be less than upper",
        `${this.options.normaliseLower} >= ${this.options.normaliseUpper}`,
      );
    return ((this.options.normalise = !0), this);
  }
  function E(d) {
    return this.normalise(d);
  }
  function N(d) {
    if (e.plainObject(d)) {
      if (e.integer(d.width) && d.width > 0) this.options.claheWidth = d.width;
      else
        throw e.invalidParameterError(
          "width",
          "integer greater than zero",
          d.width,
        );
      if (e.integer(d.height) && d.height > 0)
        this.options.claheHeight = d.height;
      else
        throw e.invalidParameterError(
          "height",
          "integer greater than zero",
          d.height,
        );
      if (e.defined(d.maxSlope))
        if (e.integer(d.maxSlope) && e.inRange(d.maxSlope, 0, 100))
          this.options.claheMaxSlope = d.maxSlope;
        else
          throw e.invalidParameterError(
            "maxSlope",
            "integer between 0 and 100",
            d.maxSlope,
          );
    } else throw e.invalidParameterError("options", "plain object", d);
    return this;
  }
  function k(d) {
    if (
      !e.object(d) ||
      !Array.isArray(d.kernel) ||
      !e.integer(d.width) ||
      !e.integer(d.height) ||
      !e.inRange(d.width, 3, 1001) ||
      !e.inRange(d.height, 3, 1001) ||
      d.height * d.width !== d.kernel.length
    )
      throw new Error("Invalid convolution kernel");
    return (
      e.integer(d.scale) ||
        (d.scale = d.kernel.reduce(function (R, q) {
          return R + q;
        }, 0)),
      d.scale < 1 && (d.scale = 1),
      e.integer(d.offset) || (d.offset = 0),
      (this.options.convKernel = d),
      this
    );
  }
  function _(d, R) {
    if (!e.defined(d)) this.options.threshold = 128;
    else if (e.bool(d)) this.options.threshold = d ? 128 : 0;
    else if (e.integer(d) && e.inRange(d, 0, 255)) this.options.threshold = d;
    else
      throw e.invalidParameterError(
        "threshold",
        "integer between 0 and 255",
        d,
      );
    return (
      !e.object(R) || R.greyscale === !0 || R.grayscale === !0
        ? (this.options.thresholdGrayscale = !0)
        : (this.options.thresholdGrayscale = !1),
      this
    );
  }
  function F(d, R, q) {
    if (
      ((this.options.boolean = this._createInputDescriptor(d, q)),
      e.string(R) && e.inArray(R, ["and", "or", "eor"]))
    )
      this.options.booleanOp = R;
    else throw e.invalidParameterError("operator", "one of: and, or, eor", R);
    return this;
  }
  function B(d, R) {
    if (
      (!e.defined(d) && e.number(R)
        ? (d = 1)
        : e.number(d) && !e.defined(R) && (R = 0),
      !e.defined(d))
    )
      this.options.linearA = [];
    else if (e.number(d)) this.options.linearA = [d];
    else if (Array.isArray(d) && d.length && d.every(e.number))
      this.options.linearA = d;
    else throw e.invalidParameterError("a", "number or array of numbers", d);
    if (!e.defined(R)) this.options.linearB = [];
    else if (e.number(R)) this.options.linearB = [R];
    else if (Array.isArray(R) && R.length && R.every(e.number))
      this.options.linearB = R;
    else throw e.invalidParameterError("b", "number or array of numbers", R);
    if (this.options.linearA.length !== this.options.linearB.length)
      throw new Error("Expected a and b to be arrays of the same length");
    return this;
  }
  function D(d) {
    if (!Array.isArray(d))
      throw e.invalidParameterError("inputMatrix", "array", d);
    if (d.length !== 3 && d.length !== 4)
      throw e.invalidParameterError(
        "inputMatrix",
        "3x3 or 4x4 array",
        d.length,
      );
    const R = d.flat().map(Number);
    if (R.length !== 9 && R.length !== 16)
      throw e.invalidParameterError(
        "inputMatrix",
        "cardinality of 9 or 16",
        R.length,
      );
    return ((this.options.recombMatrix = R), this);
  }
  function T(d) {
    if (!e.plainObject(d))
      throw e.invalidParameterError("options", "plain object", d);
    if ("brightness" in d)
      if (e.number(d.brightness) && d.brightness >= 0)
        this.options.brightness = d.brightness;
      else
        throw e.invalidParameterError(
          "brightness",
          "number above zero",
          d.brightness,
        );
    if ("saturation" in d)
      if (e.number(d.saturation) && d.saturation >= 0)
        this.options.saturation = d.saturation;
      else
        throw e.invalidParameterError(
          "saturation",
          "number above zero",
          d.saturation,
        );
    if ("hue" in d)
      if (e.integer(d.hue)) this.options.hue = d.hue % 360;
      else throw e.invalidParameterError("hue", "number", d.hue);
    if ("lightness" in d)
      if (e.number(d.lightness)) this.options.lightness = d.lightness;
      else throw e.invalidParameterError("lightness", "number", d.lightness);
    return this;
  }
  return (
    (Ae = function (d) {
      Object.assign(d.prototype, {
        autoOrient: w,
        rotate: b,
        flip: a,
        flop: c,
        affine: o,
        sharpen: l,
        erode: u,
        dilate: s,
        median: n,
        blur: f,
        flatten: r,
        unflatten: g,
        gamma: h,
        negate: m,
        normalise: p,
        normalize: E,
        clahe: N,
        convolve: k,
        threshold: _,
        boolean: F,
        linear: B,
        recomb: D,
        modulate: T,
      });
    }),
    Ae
  );
}
var $e = { exports: {} },
  je,
  Er;
function Tr() {
  return (
    Er ||
      ((Er = 1),
      (je = {
        aliceblue: [240, 248, 255],
        antiquewhite: [250, 235, 215],
        aqua: [0, 255, 255],
        aquamarine: [127, 255, 212],
        azure: [240, 255, 255],
        beige: [245, 245, 220],
        bisque: [255, 228, 196],
        black: [0, 0, 0],
        blanchedalmond: [255, 235, 205],
        blue: [0, 0, 255],
        blueviolet: [138, 43, 226],
        brown: [165, 42, 42],
        burlywood: [222, 184, 135],
        cadetblue: [95, 158, 160],
        chartreuse: [127, 255, 0],
        chocolate: [210, 105, 30],
        coral: [255, 127, 80],
        cornflowerblue: [100, 149, 237],
        cornsilk: [255, 248, 220],
        crimson: [220, 20, 60],
        cyan: [0, 255, 255],
        darkblue: [0, 0, 139],
        darkcyan: [0, 139, 139],
        darkgoldenrod: [184, 134, 11],
        darkgray: [169, 169, 169],
        darkgreen: [0, 100, 0],
        darkgrey: [169, 169, 169],
        darkkhaki: [189, 183, 107],
        darkmagenta: [139, 0, 139],
        darkolivegreen: [85, 107, 47],
        darkorange: [255, 140, 0],
        darkorchid: [153, 50, 204],
        darkred: [139, 0, 0],
        darksalmon: [233, 150, 122],
        darkseagreen: [143, 188, 143],
        darkslateblue: [72, 61, 139],
        darkslategray: [47, 79, 79],
        darkslategrey: [47, 79, 79],
        darkturquoise: [0, 206, 209],
        darkviolet: [148, 0, 211],
        deeppink: [255, 20, 147],
        deepskyblue: [0, 191, 255],
        dimgray: [105, 105, 105],
        dimgrey: [105, 105, 105],
        dodgerblue: [30, 144, 255],
        firebrick: [178, 34, 34],
        floralwhite: [255, 250, 240],
        forestgreen: [34, 139, 34],
        fuchsia: [255, 0, 255],
        gainsboro: [220, 220, 220],
        ghostwhite: [248, 248, 255],
        gold: [255, 215, 0],
        goldenrod: [218, 165, 32],
        gray: [128, 128, 128],
        green: [0, 128, 0],
        greenyellow: [173, 255, 47],
        grey: [128, 128, 128],
        honeydew: [240, 255, 240],
        hotpink: [255, 105, 180],
        indianred: [205, 92, 92],
        indigo: [75, 0, 130],
        ivory: [255, 255, 240],
        khaki: [240, 230, 140],
        lavender: [230, 230, 250],
        lavenderblush: [255, 240, 245],
        lawngreen: [124, 252, 0],
        lemonchiffon: [255, 250, 205],
        lightblue: [173, 216, 230],
        lightcoral: [240, 128, 128],
        lightcyan: [224, 255, 255],
        lightgoldenrodyellow: [250, 250, 210],
        lightgray: [211, 211, 211],
        lightgreen: [144, 238, 144],
        lightgrey: [211, 211, 211],
        lightpink: [255, 182, 193],
        lightsalmon: [255, 160, 122],
        lightseagreen: [32, 178, 170],
        lightskyblue: [135, 206, 250],
        lightslategray: [119, 136, 153],
        lightslategrey: [119, 136, 153],
        lightsteelblue: [176, 196, 222],
        lightyellow: [255, 255, 224],
        lime: [0, 255, 0],
        limegreen: [50, 205, 50],
        linen: [250, 240, 230],
        magenta: [255, 0, 255],
        maroon: [128, 0, 0],
        mediumaquamarine: [102, 205, 170],
        mediumblue: [0, 0, 205],
        mediumorchid: [186, 85, 211],
        mediumpurple: [147, 112, 219],
        mediumseagreen: [60, 179, 113],
        mediumslateblue: [123, 104, 238],
        mediumspringgreen: [0, 250, 154],
        mediumturquoise: [72, 209, 204],
        mediumvioletred: [199, 21, 133],
        midnightblue: [25, 25, 112],
        mintcream: [245, 255, 250],
        mistyrose: [255, 228, 225],
        moccasin: [255, 228, 181],
        navajowhite: [255, 222, 173],
        navy: [0, 0, 128],
        oldlace: [253, 245, 230],
        olive: [128, 128, 0],
        olivedrab: [107, 142, 35],
        orange: [255, 165, 0],
        orangered: [255, 69, 0],
        orchid: [218, 112, 214],
        palegoldenrod: [238, 232, 170],
        palegreen: [152, 251, 152],
        paleturquoise: [175, 238, 238],
        palevioletred: [219, 112, 147],
        papayawhip: [255, 239, 213],
        peachpuff: [255, 218, 185],
        peru: [205, 133, 63],
        pink: [255, 192, 203],
        plum: [221, 160, 221],
        powderblue: [176, 224, 230],
        purple: [128, 0, 128],
        rebeccapurple: [102, 51, 153],
        red: [255, 0, 0],
        rosybrown: [188, 143, 143],
        royalblue: [65, 105, 225],
        saddlebrown: [139, 69, 19],
        salmon: [250, 128, 114],
        sandybrown: [244, 164, 96],
        seagreen: [46, 139, 87],
        seashell: [255, 245, 238],
        sienna: [160, 82, 45],
        silver: [192, 192, 192],
        skyblue: [135, 206, 235],
        slateblue: [106, 90, 205],
        slategray: [112, 128, 144],
        slategrey: [112, 128, 144],
        snow: [255, 250, 250],
        springgreen: [0, 255, 127],
        steelblue: [70, 130, 180],
        tan: [210, 180, 140],
        teal: [0, 128, 128],
        thistle: [216, 191, 216],
        tomato: [255, 99, 71],
        turquoise: [64, 224, 208],
        violet: [238, 130, 238],
        wheat: [245, 222, 179],
        white: [255, 255, 255],
        whitesmoke: [245, 245, 245],
        yellow: [255, 255, 0],
        yellowgreen: [154, 205, 50],
      })),
    je
  );
}
var Le = { exports: {} },
  Se,
  yr;
function wt() {
  return (
    yr ||
      ((yr = 1),
      (Se = function (i) {
        return !i || typeof i == "string"
          ? !1
          : i instanceof Array ||
              Array.isArray(i) ||
              (i.length >= 0 &&
                (i.splice instanceof Function ||
                  (Object.getOwnPropertyDescriptor(i, i.length - 1) &&
                    i.constructor.name !== "String")));
      })),
    Se
  );
}
var Pr;
function Et() {
  if (Pr) return Le.exports;
  Pr = 1;
  var e = wt(),
    i = Array.prototype.concat,
    b = Array.prototype.slice,
    w = (Le.exports = function (c) {
      for (var o = [], l = 0, n = c.length; l < n; l++) {
        var f = c[l];
        e(f) ? (o = i.call(o, b.call(f))) : o.push(f);
      }
      return o;
    });
  return (
    (w.wrap = function (a) {
      return function () {
        return a(w(arguments));
      };
    }),
    Le.exports
  );
}
var Rr;
function yt() {
  if (Rr) return $e.exports;
  Rr = 1;
  var e = Tr(),
    i = Et(),
    b = Object.hasOwnProperty,
    w = Object.create(null);
  for (var a in e) b.call(e, a) && (w[e[a]] = a);
  var c = ($e.exports = { to: {}, get: {} });
  ((c.get = function (n) {
    var f = n.substring(0, 3).toLowerCase(),
      s,
      u;
    switch (f) {
      case "hsl":
        ((s = c.get.hsl(n)), (u = "hsl"));
        break;
      case "hwb":
        ((s = c.get.hwb(n)), (u = "hwb"));
        break;
      default:
        ((s = c.get.rgb(n)), (u = "rgb"));
        break;
    }
    return s ? { model: u, value: s } : null;
  }),
    (c.get.rgb = function (n) {
      if (!n) return null;
      var f = /^#([a-f0-9]{3,4})$/i,
        s = /^#([a-f0-9]{6})([a-f0-9]{2})?$/i,
        u =
          /^rgba?\(\s*([+-]?\d+)(?=[\s,])\s*(?:,\s*)?([+-]?\d+)(?=[\s,])\s*(?:,\s*)?([+-]?\d+)\s*(?:[,|\/]\s*([+-]?[\d\.]+)(%?)\s*)?\)$/,
        r =
          /^rgba?\(\s*([+-]?[\d\.]+)\%\s*,?\s*([+-]?[\d\.]+)\%\s*,?\s*([+-]?[\d\.]+)\%\s*(?:[,|\/]\s*([+-]?[\d\.]+)(%?)\s*)?\)$/,
        g = /^(\w+)$/,
        h = [0, 0, 0, 1],
        m,
        p,
        E;
      if ((m = n.match(s))) {
        for (E = m[2], m = m[1], p = 0; p < 3; p++) {
          var N = p * 2;
          h[p] = parseInt(m.slice(N, N + 2), 16);
        }
        E && (h[3] = parseInt(E, 16) / 255);
      } else if ((m = n.match(f))) {
        for (m = m[1], E = m[3], p = 0; p < 3; p++)
          h[p] = parseInt(m[p] + m[p], 16);
        E && (h[3] = parseInt(E + E, 16) / 255);
      } else if ((m = n.match(u))) {
        for (p = 0; p < 3; p++) h[p] = parseInt(m[p + 1], 0);
        m[4] &&
          (m[5] ? (h[3] = parseFloat(m[4]) * 0.01) : (h[3] = parseFloat(m[4])));
      } else if ((m = n.match(r))) {
        for (p = 0; p < 3; p++) h[p] = Math.round(parseFloat(m[p + 1]) * 2.55);
        m[4] &&
          (m[5] ? (h[3] = parseFloat(m[4]) * 0.01) : (h[3] = parseFloat(m[4])));
      } else
        return (m = n.match(g))
          ? m[1] === "transparent"
            ? [0, 0, 0, 0]
            : b.call(e, m[1])
              ? ((h = e[m[1]]), (h[3] = 1), h)
              : null
          : null;
      for (p = 0; p < 3; p++) h[p] = o(h[p], 0, 255);
      return ((h[3] = o(h[3], 0, 1)), h);
    }),
    (c.get.hsl = function (n) {
      if (!n) return null;
      var f =
          /^hsla?\(\s*([+-]?(?:\d{0,3}\.)?\d+)(?:deg)?\s*,?\s*([+-]?[\d\.]+)%\s*,?\s*([+-]?[\d\.]+)%\s*(?:[,|\/]\s*([+-]?(?=\.\d|\d)(?:0|[1-9]\d*)?(?:\.\d*)?(?:[eE][+-]?\d+)?)\s*)?\)$/,
        s = n.match(f);
      if (s) {
        var u = parseFloat(s[4]),
          r = ((parseFloat(s[1]) % 360) + 360) % 360,
          g = o(parseFloat(s[2]), 0, 100),
          h = o(parseFloat(s[3]), 0, 100),
          m = o(isNaN(u) ? 1 : u, 0, 1);
        return [r, g, h, m];
      }
      return null;
    }),
    (c.get.hwb = function (n) {
      if (!n) return null;
      var f =
          /^hwb\(\s*([+-]?\d{0,3}(?:\.\d+)?)(?:deg)?\s*,\s*([+-]?[\d\.]+)%\s*,\s*([+-]?[\d\.]+)%\s*(?:,\s*([+-]?(?=\.\d|\d)(?:0|[1-9]\d*)?(?:\.\d*)?(?:[eE][+-]?\d+)?)\s*)?\)$/,
        s = n.match(f);
      if (s) {
        var u = parseFloat(s[4]),
          r = ((parseFloat(s[1]) % 360) + 360) % 360,
          g = o(parseFloat(s[2]), 0, 100),
          h = o(parseFloat(s[3]), 0, 100),
          m = o(isNaN(u) ? 1 : u, 0, 1);
        return [r, g, h, m];
      }
      return null;
    }),
    (c.to.hex = function () {
      var n = i(arguments);
      return (
        "#" +
        l(n[0]) +
        l(n[1]) +
        l(n[2]) +
        (n[3] < 1 ? l(Math.round(n[3] * 255)) : "")
      );
    }),
    (c.to.rgb = function () {
      var n = i(arguments);
      return n.length < 4 || n[3] === 1
        ? "rgb(" +
            Math.round(n[0]) +
            ", " +
            Math.round(n[1]) +
            ", " +
            Math.round(n[2]) +
            ")"
        : "rgba(" +
            Math.round(n[0]) +
            ", " +
            Math.round(n[1]) +
            ", " +
            Math.round(n[2]) +
            ", " +
            n[3] +
            ")";
    }),
    (c.to.rgb.percent = function () {
      var n = i(arguments),
        f = Math.round((n[0] / 255) * 100),
        s = Math.round((n[1] / 255) * 100),
        u = Math.round((n[2] / 255) * 100);
      return n.length < 4 || n[3] === 1
        ? "rgb(" + f + "%, " + s + "%, " + u + "%)"
        : "rgba(" + f + "%, " + s + "%, " + u + "%, " + n[3] + ")";
    }),
    (c.to.hsl = function () {
      var n = i(arguments);
      return n.length < 4 || n[3] === 1
        ? "hsl(" + n[0] + ", " + n[1] + "%, " + n[2] + "%)"
        : "hsla(" + n[0] + ", " + n[1] + "%, " + n[2] + "%, " + n[3] + ")";
    }),
    (c.to.hwb = function () {
      var n = i(arguments),
        f = "";
      return (
        n.length >= 4 && n[3] !== 1 && (f = ", " + n[3]),
        "hwb(" + n[0] + ", " + n[1] + "%, " + n[2] + "%" + f + ")"
      );
    }),
    (c.to.keyword = function (n) {
      return w[n.slice(0, 3)];
    }));
  function o(n, f, s) {
    return Math.min(Math.max(f, n), s);
  }
  function l(n) {
    var f = Math.round(n).toString(16).toUpperCase();
    return f.length < 2 ? "0" + f : f;
  }
  return $e.exports;
}
var ke, xr;
function Br() {
  if (xr) return ke;
  xr = 1;
  const e = Tr(),
    i = {};
  for (const a of Object.keys(e)) i[e[a]] = a;
  const b = {
    rgb: { channels: 3, labels: "rgb" },
    hsl: { channels: 3, labels: "hsl" },
    hsv: { channels: 3, labels: "hsv" },
    hwb: { channels: 3, labels: "hwb" },
    cmyk: { channels: 4, labels: "cmyk" },
    xyz: { channels: 3, labels: "xyz" },
    lab: { channels: 3, labels: "lab" },
    lch: { channels: 3, labels: "lch" },
    hex: { channels: 1, labels: ["hex"] },
    keyword: { channels: 1, labels: ["keyword"] },
    ansi16: { channels: 1, labels: ["ansi16"] },
    ansi256: { channels: 1, labels: ["ansi256"] },
    hcg: { channels: 3, labels: ["h", "c", "g"] },
    apple: { channels: 3, labels: ["r16", "g16", "b16"] },
    gray: { channels: 1, labels: ["gray"] },
  };
  ke = b;
  for (const a of Object.keys(b)) {
    if (!("channels" in b[a]))
      throw new Error("missing channels property: " + a);
    if (!("labels" in b[a]))
      throw new Error("missing channel labels property: " + a);
    if (b[a].labels.length !== b[a].channels)
      throw new Error("channel and label counts mismatch: " + a);
    const { channels: c, labels: o } = b[a];
    (delete b[a].channels,
      delete b[a].labels,
      Object.defineProperty(b[a], "channels", { value: c }),
      Object.defineProperty(b[a], "labels", { value: o }));
  }
  ((b.rgb.hsl = function (a) {
    const c = a[0] / 255,
      o = a[1] / 255,
      l = a[2] / 255,
      n = Math.min(c, o, l),
      f = Math.max(c, o, l),
      s = f - n;
    let u, r;
    (f === n
      ? (u = 0)
      : c === f
        ? (u = (o - l) / s)
        : o === f
          ? (u = 2 + (l - c) / s)
          : l === f && (u = 4 + (c - o) / s),
      (u = Math.min(u * 60, 360)),
      u < 0 && (u += 360));
    const g = (n + f) / 2;
    return (
      f === n ? (r = 0) : g <= 0.5 ? (r = s / (f + n)) : (r = s / (2 - f - n)),
      [u, r * 100, g * 100]
    );
  }),
    (b.rgb.hsv = function (a) {
      let c, o, l, n, f;
      const s = a[0] / 255,
        u = a[1] / 255,
        r = a[2] / 255,
        g = Math.max(s, u, r),
        h = g - Math.min(s, u, r),
        m = function (p) {
          return (g - p) / 6 / h + 1 / 2;
        };
      return (
        h === 0
          ? ((n = 0), (f = 0))
          : ((f = h / g),
            (c = m(s)),
            (o = m(u)),
            (l = m(r)),
            s === g
              ? (n = l - o)
              : u === g
                ? (n = 1 / 3 + c - l)
                : r === g && (n = 2 / 3 + o - c),
            n < 0 ? (n += 1) : n > 1 && (n -= 1)),
        [n * 360, f * 100, g * 100]
      );
    }),
    (b.rgb.hwb = function (a) {
      const c = a[0],
        o = a[1];
      let l = a[2];
      const n = b.rgb.hsl(a)[0],
        f = (1 / 255) * Math.min(c, Math.min(o, l));
      return (
        (l = 1 - (1 / 255) * Math.max(c, Math.max(o, l))),
        [n, f * 100, l * 100]
      );
    }),
    (b.rgb.cmyk = function (a) {
      const c = a[0] / 255,
        o = a[1] / 255,
        l = a[2] / 255,
        n = Math.min(1 - c, 1 - o, 1 - l),
        f = (1 - c - n) / (1 - n) || 0,
        s = (1 - o - n) / (1 - n) || 0,
        u = (1 - l - n) / (1 - n) || 0;
      return [f * 100, s * 100, u * 100, n * 100];
    }));
  function w(a, c) {
    return (a[0] - c[0]) ** 2 + (a[1] - c[1]) ** 2 + (a[2] - c[2]) ** 2;
  }
  return (
    (b.rgb.keyword = function (a) {
      const c = i[a];
      if (c) return c;
      let o = 1 / 0,
        l;
      for (const n of Object.keys(e)) {
        const f = e[n],
          s = w(a, f);
        s < o && ((o = s), (l = n));
      }
      return l;
    }),
    (b.keyword.rgb = function (a) {
      return e[a];
    }),
    (b.rgb.xyz = function (a) {
      let c = a[0] / 255,
        o = a[1] / 255,
        l = a[2] / 255;
      ((c = c > 0.04045 ? ((c + 0.055) / 1.055) ** 2.4 : c / 12.92),
        (o = o > 0.04045 ? ((o + 0.055) / 1.055) ** 2.4 : o / 12.92),
        (l = l > 0.04045 ? ((l + 0.055) / 1.055) ** 2.4 : l / 12.92));
      const n = c * 0.4124 + o * 0.3576 + l * 0.1805,
        f = c * 0.2126 + o * 0.7152 + l * 0.0722,
        s = c * 0.0193 + o * 0.1192 + l * 0.9505;
      return [n * 100, f * 100, s * 100];
    }),
    (b.rgb.lab = function (a) {
      const c = b.rgb.xyz(a);
      let o = c[0],
        l = c[1],
        n = c[2];
      ((o /= 95.047),
        (l /= 100),
        (n /= 108.883),
        (o = o > 0.008856 ? o ** (1 / 3) : 7.787 * o + 16 / 116),
        (l = l > 0.008856 ? l ** (1 / 3) : 7.787 * l + 16 / 116),
        (n = n > 0.008856 ? n ** (1 / 3) : 7.787 * n + 16 / 116));
      const f = 116 * l - 16,
        s = 500 * (o - l),
        u = 200 * (l - n);
      return [f, s, u];
    }),
    (b.hsl.rgb = function (a) {
      const c = a[0] / 360,
        o = a[1] / 100,
        l = a[2] / 100;
      let n, f, s;
      if (o === 0) return ((s = l * 255), [s, s, s]);
      l < 0.5 ? (n = l * (1 + o)) : (n = l + o - l * o);
      const u = 2 * l - n,
        r = [0, 0, 0];
      for (let g = 0; g < 3; g++)
        ((f = c + (1 / 3) * -(g - 1)),
          f < 0 && f++,
          f > 1 && f--,
          6 * f < 1
            ? (s = u + (n - u) * 6 * f)
            : 2 * f < 1
              ? (s = n)
              : 3 * f < 2
                ? (s = u + (n - u) * (2 / 3 - f) * 6)
                : (s = u),
          (r[g] = s * 255));
      return r;
    }),
    (b.hsl.hsv = function (a) {
      const c = a[0];
      let o = a[1] / 100,
        l = a[2] / 100,
        n = o;
      const f = Math.max(l, 0.01);
      ((l *= 2), (o *= l <= 1 ? l : 2 - l), (n *= f <= 1 ? f : 2 - f));
      const s = (l + o) / 2,
        u = l === 0 ? (2 * n) / (f + n) : (2 * o) / (l + o);
      return [c, u * 100, s * 100];
    }),
    (b.hsv.rgb = function (a) {
      const c = a[0] / 60,
        o = a[1] / 100;
      let l = a[2] / 100;
      const n = Math.floor(c) % 6,
        f = c - Math.floor(c),
        s = 255 * l * (1 - o),
        u = 255 * l * (1 - o * f),
        r = 255 * l * (1 - o * (1 - f));
      switch (((l *= 255), n)) {
        case 0:
          return [l, r, s];
        case 1:
          return [u, l, s];
        case 2:
          return [s, l, r];
        case 3:
          return [s, u, l];
        case 4:
          return [r, s, l];
        case 5:
          return [l, s, u];
      }
    }),
    (b.hsv.hsl = function (a) {
      const c = a[0],
        o = a[1] / 100,
        l = a[2] / 100,
        n = Math.max(l, 0.01);
      let f, s;
      s = (2 - o) * l;
      const u = (2 - o) * n;
      return (
        (f = o * n),
        (f /= u <= 1 ? u : 2 - u),
        (f = f || 0),
        (s /= 2),
        [c, f * 100, s * 100]
      );
    }),
    (b.hwb.rgb = function (a) {
      const c = a[0] / 360;
      let o = a[1] / 100,
        l = a[2] / 100;
      const n = o + l;
      let f;
      n > 1 && ((o /= n), (l /= n));
      const s = Math.floor(6 * c),
        u = 1 - l;
      ((f = 6 * c - s), (s & 1) !== 0 && (f = 1 - f));
      const r = o + f * (u - o);
      let g, h, m;
      switch (s) {
        default:
        case 6:
        case 0:
          ((g = u), (h = r), (m = o));
          break;
        case 1:
          ((g = r), (h = u), (m = o));
          break;
        case 2:
          ((g = o), (h = u), (m = r));
          break;
        case 3:
          ((g = o), (h = r), (m = u));
          break;
        case 4:
          ((g = r), (h = o), (m = u));
          break;
        case 5:
          ((g = u), (h = o), (m = r));
          break;
      }
      return [g * 255, h * 255, m * 255];
    }),
    (b.cmyk.rgb = function (a) {
      const c = a[0] / 100,
        o = a[1] / 100,
        l = a[2] / 100,
        n = a[3] / 100,
        f = 1 - Math.min(1, c * (1 - n) + n),
        s = 1 - Math.min(1, o * (1 - n) + n),
        u = 1 - Math.min(1, l * (1 - n) + n);
      return [f * 255, s * 255, u * 255];
    }),
    (b.xyz.rgb = function (a) {
      const c = a[0] / 100,
        o = a[1] / 100,
        l = a[2] / 100;
      let n, f, s;
      return (
        (n = c * 3.2406 + o * -1.5372 + l * -0.4986),
        (f = c * -0.9689 + o * 1.8758 + l * 0.0415),
        (s = c * 0.0557 + o * -0.204 + l * 1.057),
        (n = n > 0.0031308 ? 1.055 * n ** (1 / 2.4) - 0.055 : n * 12.92),
        (f = f > 0.0031308 ? 1.055 * f ** (1 / 2.4) - 0.055 : f * 12.92),
        (s = s > 0.0031308 ? 1.055 * s ** (1 / 2.4) - 0.055 : s * 12.92),
        (n = Math.min(Math.max(0, n), 1)),
        (f = Math.min(Math.max(0, f), 1)),
        (s = Math.min(Math.max(0, s), 1)),
        [n * 255, f * 255, s * 255]
      );
    }),
    (b.xyz.lab = function (a) {
      let c = a[0],
        o = a[1],
        l = a[2];
      ((c /= 95.047),
        (o /= 100),
        (l /= 108.883),
        (c = c > 0.008856 ? c ** (1 / 3) : 7.787 * c + 16 / 116),
        (o = o > 0.008856 ? o ** (1 / 3) : 7.787 * o + 16 / 116),
        (l = l > 0.008856 ? l ** (1 / 3) : 7.787 * l + 16 / 116));
      const n = 116 * o - 16,
        f = 500 * (c - o),
        s = 200 * (o - l);
      return [n, f, s];
    }),
    (b.lab.xyz = function (a) {
      const c = a[0],
        o = a[1],
        l = a[2];
      let n, f, s;
      ((f = (c + 16) / 116), (n = o / 500 + f), (s = f - l / 200));
      const u = f ** 3,
        r = n ** 3,
        g = s ** 3;
      return (
        (f = u > 0.008856 ? u : (f - 16 / 116) / 7.787),
        (n = r > 0.008856 ? r : (n - 16 / 116) / 7.787),
        (s = g > 0.008856 ? g : (s - 16 / 116) / 7.787),
        (n *= 95.047),
        (f *= 100),
        (s *= 108.883),
        [n, f, s]
      );
    }),
    (b.lab.lch = function (a) {
      const c = a[0],
        o = a[1],
        l = a[2];
      let n;
      ((n = (Math.atan2(l, o) * 360) / 2 / Math.PI), n < 0 && (n += 360));
      const s = Math.sqrt(o * o + l * l);
      return [c, s, n];
    }),
    (b.lch.lab = function (a) {
      const c = a[0],
        o = a[1],
        n = (a[2] / 360) * 2 * Math.PI,
        f = o * Math.cos(n),
        s = o * Math.sin(n);
      return [c, f, s];
    }),
    (b.rgb.ansi16 = function (a, c = null) {
      const [o, l, n] = a;
      let f = c === null ? b.rgb.hsv(a)[2] : c;
      if (((f = Math.round(f / 50)), f === 0)) return 30;
      let s =
        30 +
        ((Math.round(n / 255) << 2) |
          (Math.round(l / 255) << 1) |
          Math.round(o / 255));
      return (f === 2 && (s += 60), s);
    }),
    (b.hsv.ansi16 = function (a) {
      return b.rgb.ansi16(b.hsv.rgb(a), a[2]);
    }),
    (b.rgb.ansi256 = function (a) {
      const c = a[0],
        o = a[1],
        l = a[2];
      return c === o && o === l
        ? c < 8
          ? 16
          : c > 248
            ? 231
            : Math.round(((c - 8) / 247) * 24) + 232
        : 16 +
            36 * Math.round((c / 255) * 5) +
            6 * Math.round((o / 255) * 5) +
            Math.round((l / 255) * 5);
    }),
    (b.ansi16.rgb = function (a) {
      let c = a % 10;
      if (c === 0 || c === 7)
        return (a > 50 && (c += 3.5), (c = (c / 10.5) * 255), [c, c, c]);
      const o = (~~(a > 50) + 1) * 0.5,
        l = (c & 1) * o * 255,
        n = ((c >> 1) & 1) * o * 255,
        f = ((c >> 2) & 1) * o * 255;
      return [l, n, f];
    }),
    (b.ansi256.rgb = function (a) {
      if (a >= 232) {
        const f = (a - 232) * 10 + 8;
        return [f, f, f];
      }
      a -= 16;
      let c;
      const o = (Math.floor(a / 36) / 5) * 255,
        l = (Math.floor((c = a % 36) / 6) / 5) * 255,
        n = ((c % 6) / 5) * 255;
      return [o, l, n];
    }),
    (b.rgb.hex = function (a) {
      const o = (
        ((Math.round(a[0]) & 255) << 16) +
        ((Math.round(a[1]) & 255) << 8) +
        (Math.round(a[2]) & 255)
      )
        .toString(16)
        .toUpperCase();
      return "000000".substring(o.length) + o;
    }),
    (b.hex.rgb = function (a) {
      const c = a.toString(16).match(/[a-f0-9]{6}|[a-f0-9]{3}/i);
      if (!c) return [0, 0, 0];
      let o = c[0];
      c[0].length === 3 &&
        (o = o
          .split("")
          .map((u) => u + u)
          .join(""));
      const l = parseInt(o, 16),
        n = (l >> 16) & 255,
        f = (l >> 8) & 255,
        s = l & 255;
      return [n, f, s];
    }),
    (b.rgb.hcg = function (a) {
      const c = a[0] / 255,
        o = a[1] / 255,
        l = a[2] / 255,
        n = Math.max(Math.max(c, o), l),
        f = Math.min(Math.min(c, o), l),
        s = n - f;
      let u, r;
      return (
        s < 1 ? (u = f / (1 - s)) : (u = 0),
        s <= 0
          ? (r = 0)
          : n === c
            ? (r = ((o - l) / s) % 6)
            : n === o
              ? (r = 2 + (l - c) / s)
              : (r = 4 + (c - o) / s),
        (r /= 6),
        (r %= 1),
        [r * 360, s * 100, u * 100]
      );
    }),
    (b.hsl.hcg = function (a) {
      const c = a[1] / 100,
        o = a[2] / 100,
        l = o < 0.5 ? 2 * c * o : 2 * c * (1 - o);
      let n = 0;
      return (l < 1 && (n = (o - 0.5 * l) / (1 - l)), [a[0], l * 100, n * 100]);
    }),
    (b.hsv.hcg = function (a) {
      const c = a[1] / 100,
        o = a[2] / 100,
        l = c * o;
      let n = 0;
      return (l < 1 && (n = (o - l) / (1 - l)), [a[0], l * 100, n * 100]);
    }),
    (b.hcg.rgb = function (a) {
      const c = a[0] / 360,
        o = a[1] / 100,
        l = a[2] / 100;
      if (o === 0) return [l * 255, l * 255, l * 255];
      const n = [0, 0, 0],
        f = (c % 1) * 6,
        s = f % 1,
        u = 1 - s;
      let r = 0;
      switch (Math.floor(f)) {
        case 0:
          ((n[0] = 1), (n[1] = s), (n[2] = 0));
          break;
        case 1:
          ((n[0] = u), (n[1] = 1), (n[2] = 0));
          break;
        case 2:
          ((n[0] = 0), (n[1] = 1), (n[2] = s));
          break;
        case 3:
          ((n[0] = 0), (n[1] = u), (n[2] = 1));
          break;
        case 4:
          ((n[0] = s), (n[1] = 0), (n[2] = 1));
          break;
        default:
          ((n[0] = 1), (n[1] = 0), (n[2] = u));
      }
      return (
        (r = (1 - o) * l),
        [(o * n[0] + r) * 255, (o * n[1] + r) * 255, (o * n[2] + r) * 255]
      );
    }),
    (b.hcg.hsv = function (a) {
      const c = a[1] / 100,
        o = a[2] / 100,
        l = c + o * (1 - c);
      let n = 0;
      return (l > 0 && (n = c / l), [a[0], n * 100, l * 100]);
    }),
    (b.hcg.hsl = function (a) {
      const c = a[1] / 100,
        l = (a[2] / 100) * (1 - c) + 0.5 * c;
      let n = 0;
      return (
        l > 0 && l < 0.5
          ? (n = c / (2 * l))
          : l >= 0.5 && l < 1 && (n = c / (2 * (1 - l))),
        [a[0], n * 100, l * 100]
      );
    }),
    (b.hcg.hwb = function (a) {
      const c = a[1] / 100,
        o = a[2] / 100,
        l = c + o * (1 - c);
      return [a[0], (l - c) * 100, (1 - l) * 100];
    }),
    (b.hwb.hcg = function (a) {
      const c = a[1] / 100,
        l = 1 - a[2] / 100,
        n = l - c;
      let f = 0;
      return (n < 1 && (f = (l - n) / (1 - n)), [a[0], n * 100, f * 100]);
    }),
    (b.apple.rgb = function (a) {
      return [(a[0] / 65535) * 255, (a[1] / 65535) * 255, (a[2] / 65535) * 255];
    }),
    (b.rgb.apple = function (a) {
      return [(a[0] / 255) * 65535, (a[1] / 255) * 65535, (a[2] / 255) * 65535];
    }),
    (b.gray.rgb = function (a) {
      return [(a[0] / 100) * 255, (a[0] / 100) * 255, (a[0] / 100) * 255];
    }),
    (b.gray.hsl = function (a) {
      return [0, 0, a[0]];
    }),
    (b.gray.hsv = b.gray.hsl),
    (b.gray.hwb = function (a) {
      return [0, 100, a[0]];
    }),
    (b.gray.cmyk = function (a) {
      return [0, 0, 0, a[0]];
    }),
    (b.gray.lab = function (a) {
      return [a[0], 0, 0];
    }),
    (b.gray.hex = function (a) {
      const c = Math.round((a[0] / 100) * 255) & 255,
        l = ((c << 16) + (c << 8) + c).toString(16).toUpperCase();
      return "000000".substring(l.length) + l;
    }),
    (b.rgb.gray = function (a) {
      return [((a[0] + a[1] + a[2]) / 3 / 255) * 100];
    }),
    ke
  );
}
var Ne, Ir;
function Pt() {
  if (Ir) return Ne;
  Ir = 1;
  const e = Br();
  function i() {
    const c = {},
      o = Object.keys(e);
    for (let l = o.length, n = 0; n < l; n++)
      c[o[n]] = { distance: -1, parent: null };
    return c;
  }
  function b(c) {
    const o = i(),
      l = [c];
    for (o[c].distance = 0; l.length;) {
      const n = l.pop(),
        f = Object.keys(e[n]);
      for (let s = f.length, u = 0; u < s; u++) {
        const r = f[u],
          g = o[r];
        g.distance === -1 &&
          ((g.distance = o[n].distance + 1), (g.parent = n), l.unshift(r));
      }
    }
    return o;
  }
  function w(c, o) {
    return function (l) {
      return o(c(l));
    };
  }
  function a(c, o) {
    const l = [o[c].parent, c];
    let n = e[o[c].parent][c],
      f = o[c].parent;
    for (; o[f].parent;)
      (l.unshift(o[f].parent),
        (n = w(e[o[f].parent][f], n)),
        (f = o[f].parent));
    return ((n.conversion = l), n);
  }
  return (
    (Ne = function (c) {
      const o = b(c),
        l = {},
        n = Object.keys(o);
      for (let f = n.length, s = 0; s < f; s++) {
        const u = n[s];
        o[u].parent !== null && (l[u] = a(u, o));
      }
      return l;
    }),
    Ne
  );
}
var Ce, Ar;
function Rt() {
  if (Ar) return Ce;
  Ar = 1;
  const e = Br(),
    i = Pt(),
    b = {},
    w = Object.keys(e);
  function a(o) {
    const l = function (...n) {
      const f = n[0];
      return f == null ? f : (f.length > 1 && (n = f), o(n));
    };
    return ("conversion" in o && (l.conversion = o.conversion), l);
  }
  function c(o) {
    const l = function (...n) {
      const f = n[0];
      if (f == null) return f;
      f.length > 1 && (n = f);
      const s = o(n);
      if (typeof s == "object")
        for (let u = s.length, r = 0; r < u; r++) s[r] = Math.round(s[r]);
      return s;
    };
    return ("conversion" in o && (l.conversion = o.conversion), l);
  }
  return (
    w.forEach((o) => {
      ((b[o] = {}),
        Object.defineProperty(b[o], "channels", { value: e[o].channels }),
        Object.defineProperty(b[o], "labels", { value: e[o].labels }));
      const l = i(o);
      Object.keys(l).forEach((f) => {
        const s = l[f];
        ((b[o][f] = c(s)), (b[o][f].raw = a(s)));
      });
    }),
    (Ce = b),
    Ce
  );
}
var qe, $r;
function xt() {
  if ($r) return qe;
  $r = 1;
  const e = yt(),
    i = Rt(),
    b = ["keyword", "gray", "hex"],
    w = {};
  for (const r of Object.keys(i)) w[[...i[r].labels].sort().join("")] = r;
  const a = {};
  function c(r, g) {
    if (!(this instanceof c)) return new c(r, g);
    if ((g && g in b && (g = null), g && !(g in i)))
      throw new Error("Unknown model: " + g);
    let h, m;
    if (r == null)
      ((this.model = "rgb"), (this.color = [0, 0, 0]), (this.valpha = 1));
    else if (r instanceof c)
      ((this.model = r.model),
        (this.color = [...r.color]),
        (this.valpha = r.valpha));
    else if (typeof r == "string") {
      const p = e.get(r);
      if (p === null)
        throw new Error("Unable to parse color from string: " + r);
      ((this.model = p.model),
        (m = i[this.model].channels),
        (this.color = p.value.slice(0, m)),
        (this.valpha = typeof p.value[m] == "number" ? p.value[m] : 1));
    } else if (r.length > 0) {
      ((this.model = g || "rgb"), (m = i[this.model].channels));
      const p = Array.prototype.slice.call(r, 0, m);
      ((this.color = u(p, m)),
        (this.valpha = typeof r[m] == "number" ? r[m] : 1));
    } else if (typeof r == "number")
      ((this.model = "rgb"),
        (this.color = [(r >> 16) & 255, (r >> 8) & 255, r & 255]),
        (this.valpha = 1));
    else {
      this.valpha = 1;
      const p = Object.keys(r);
      "alpha" in r &&
        (p.splice(p.indexOf("alpha"), 1),
        (this.valpha = typeof r.alpha == "number" ? r.alpha : 0));
      const E = p.sort().join("");
      if (!(E in w))
        throw new Error(
          "Unable to parse color from object: " + JSON.stringify(r),
        );
      this.model = w[E];
      const { labels: N } = i[this.model],
        k = [];
      for (h = 0; h < N.length; h++) k.push(r[N[h]]);
      this.color = u(k);
    }
    if (a[this.model])
      for (m = i[this.model].channels, h = 0; h < m; h++) {
        const p = a[this.model][h];
        p && (this.color[h] = p(this.color[h]));
      }
    ((this.valpha = Math.max(0, Math.min(1, this.valpha))),
      Object.freeze && Object.freeze(this));
  }
  c.prototype = {
    toString() {
      return this.string();
    },
    toJSON() {
      return this[this.model]();
    },
    string(r) {
      let g = this.model in e.to ? this : this.rgb();
      g = g.round(typeof r == "number" ? r : 1);
      const h = g.valpha === 1 ? g.color : [...g.color, this.valpha];
      return e.to[g.model](h);
    },
    percentString(r) {
      const g = this.rgb().round(typeof r == "number" ? r : 1),
        h = g.valpha === 1 ? g.color : [...g.color, this.valpha];
      return e.to.rgb.percent(h);
    },
    array() {
      return this.valpha === 1 ? [...this.color] : [...this.color, this.valpha];
    },
    object() {
      const r = {},
        { channels: g } = i[this.model],
        { labels: h } = i[this.model];
      for (let m = 0; m < g; m++) r[h[m]] = this.color[m];
      return (this.valpha !== 1 && (r.alpha = this.valpha), r);
    },
    unitArray() {
      const r = this.rgb().color;
      return (
        (r[0] /= 255),
        (r[1] /= 255),
        (r[2] /= 255),
        this.valpha !== 1 && r.push(this.valpha),
        r
      );
    },
    unitObject() {
      const r = this.rgb().object();
      return (
        (r.r /= 255),
        (r.g /= 255),
        (r.b /= 255),
        this.valpha !== 1 && (r.alpha = this.valpha),
        r
      );
    },
    round(r) {
      return (
        (r = Math.max(r || 0, 0)),
        new c([...this.color.map(l(r)), this.valpha], this.model)
      );
    },
    alpha(r) {
      return r !== void 0
        ? new c([...this.color, Math.max(0, Math.min(1, r))], this.model)
        : this.valpha;
    },
    red: n("rgb", 0, f(255)),
    green: n("rgb", 1, f(255)),
    blue: n("rgb", 2, f(255)),
    hue: n(
      ["hsl", "hsv", "hsl", "hwb", "hcg"],
      0,
      (r) => ((r % 360) + 360) % 360,
    ),
    saturationl: n("hsl", 1, f(100)),
    lightness: n("hsl", 2, f(100)),
    saturationv: n("hsv", 1, f(100)),
    value: n("hsv", 2, f(100)),
    chroma: n("hcg", 1, f(100)),
    gray: n("hcg", 2, f(100)),
    white: n("hwb", 1, f(100)),
    wblack: n("hwb", 2, f(100)),
    cyan: n("cmyk", 0, f(100)),
    magenta: n("cmyk", 1, f(100)),
    yellow: n("cmyk", 2, f(100)),
    black: n("cmyk", 3, f(100)),
    x: n("xyz", 0, f(95.047)),
    y: n("xyz", 1, f(100)),
    z: n("xyz", 2, f(108.833)),
    l: n("lab", 0, f(100)),
    a: n("lab", 1),
    b: n("lab", 2),
    keyword(r) {
      return r !== void 0 ? new c(r) : i[this.model].keyword(this.color);
    },
    hex(r) {
      return r !== void 0 ? new c(r) : e.to.hex(this.rgb().round().color);
    },
    hexa(r) {
      if (r !== void 0) return new c(r);
      const g = this.rgb().round().color;
      let h = Math.round(this.valpha * 255)
        .toString(16)
        .toUpperCase();
      return (h.length === 1 && (h = "0" + h), e.to.hex(g) + h);
    },
    rgbNumber() {
      const r = this.rgb().color;
      return ((r[0] & 255) << 16) | ((r[1] & 255) << 8) | (r[2] & 255);
    },
    luminosity() {
      const r = this.rgb().color,
        g = [];
      for (const [h, m] of r.entries()) {
        const p = m / 255;
        g[h] = p <= 0.04045 ? p / 12.92 : ((p + 0.055) / 1.055) ** 2.4;
      }
      return 0.2126 * g[0] + 0.7152 * g[1] + 0.0722 * g[2];
    },
    contrast(r) {
      const g = this.luminosity(),
        h = r.luminosity();
      return g > h ? (g + 0.05) / (h + 0.05) : (h + 0.05) / (g + 0.05);
    },
    level(r) {
      const g = this.contrast(r);
      return g >= 7 ? "AAA" : g >= 4.5 ? "AA" : "";
    },
    isDark() {
      const r = this.rgb().color;
      return (r[0] * 2126 + r[1] * 7152 + r[2] * 722) / 1e4 < 128;
    },
    isLight() {
      return !this.isDark();
    },
    negate() {
      const r = this.rgb();
      for (let g = 0; g < 3; g++) r.color[g] = 255 - r.color[g];
      return r;
    },
    lighten(r) {
      const g = this.hsl();
      return ((g.color[2] += g.color[2] * r), g);
    },
    darken(r) {
      const g = this.hsl();
      return ((g.color[2] -= g.color[2] * r), g);
    },
    saturate(r) {
      const g = this.hsl();
      return ((g.color[1] += g.color[1] * r), g);
    },
    desaturate(r) {
      const g = this.hsl();
      return ((g.color[1] -= g.color[1] * r), g);
    },
    whiten(r) {
      const g = this.hwb();
      return ((g.color[1] += g.color[1] * r), g);
    },
    blacken(r) {
      const g = this.hwb();
      return ((g.color[2] += g.color[2] * r), g);
    },
    grayscale() {
      const r = this.rgb().color,
        g = r[0] * 0.3 + r[1] * 0.59 + r[2] * 0.11;
      return c.rgb(g, g, g);
    },
    fade(r) {
      return this.alpha(this.valpha - this.valpha * r);
    },
    opaquer(r) {
      return this.alpha(this.valpha + this.valpha * r);
    },
    rotate(r) {
      const g = this.hsl();
      let h = g.color[0];
      return (
        (h = (h + r) % 360),
        (h = h < 0 ? 360 + h : h),
        (g.color[0] = h),
        g
      );
    },
    mix(r, g) {
      if (!r || !r.rgb)
        throw new Error(
          'Argument to "mix" was not a Color instance, but rather an instance of ' +
            typeof r,
        );
      const h = r.rgb(),
        m = this.rgb(),
        p = g === void 0 ? 0.5 : g,
        E = 2 * p - 1,
        N = h.alpha() - m.alpha(),
        k = ((E * N === -1 ? E : (E + N) / (1 + E * N)) + 1) / 2,
        _ = 1 - k;
      return c.rgb(
        k * h.red() + _ * m.red(),
        k * h.green() + _ * m.green(),
        k * h.blue() + _ * m.blue(),
        h.alpha() * p + m.alpha() * (1 - p),
      );
    },
  };
  for (const r of Object.keys(i)) {
    if (b.includes(r)) continue;
    const { channels: g } = i[r];
    ((c.prototype[r] = function (...h) {
      return this.model === r
        ? new c(this)
        : h.length > 0
          ? new c(h, r)
          : new c([...s(i[this.model][r].raw(this.color)), this.valpha], r);
    }),
      (c[r] = function (...h) {
        let m = h[0];
        return (typeof m == "number" && (m = u(h, g)), new c(m, r));
      }));
  }
  function o(r, g) {
    return Number(r.toFixed(g));
  }
  function l(r) {
    return function (g) {
      return o(g, r);
    };
  }
  function n(r, g, h) {
    r = Array.isArray(r) ? r : [r];
    for (const m of r) (a[m] || (a[m] = []))[g] = h;
    return (
      (r = r[0]),
      function (m) {
        let p;
        return m !== void 0
          ? (h && (m = h(m)), (p = this[r]()), (p.color[g] = m), p)
          : ((p = this[r]().color[g]), h && (p = h(p)), p);
      }
    );
  }
  function f(r) {
    return function (g) {
      return Math.max(0, Math.min(r, g));
    };
  }
  function s(r) {
    return Array.isArray(r) ? r : [r];
  }
  function u(r, g) {
    for (let h = 0; h < g; h++) typeof r[h] != "number" && (r[h] = 0);
    return r;
  }
  return ((qe = c), qe);
}
var _e, jr;
function It() {
  if (jr) return _e;
  jr = 1;
  const e = xt(),
    i = G(),
    b = {
      multiband: "multiband",
      "b-w": "b-w",
      bw: "b-w",
      cmyk: "cmyk",
      srgb: "srgb",
    };
  function w(r) {
    return (this._setBackgroundColourOption("tint", r), this);
  }
  function a(r) {
    return ((this.options.greyscale = i.bool(r) ? r : !0), this);
  }
  function c(r) {
    return this.greyscale(r);
  }
  function o(r) {
    if (!i.string(r)) throw i.invalidParameterError("colourspace", "string", r);
    return ((this.options.colourspacePipeline = r), this);
  }
  function l(r) {
    return this.pipelineColourspace(r);
  }
  function n(r) {
    if (!i.string(r)) throw i.invalidParameterError("colourspace", "string", r);
    return ((this.options.colourspace = r), this);
  }
  function f(r) {
    return this.toColourspace(r);
  }
  function s(r) {
    if (i.object(r) || i.string(r)) {
      const g = e(r);
      return [g.red(), g.green(), g.blue(), Math.round(g.alpha() * 255)];
    } else throw i.invalidParameterError("background", "object or string", r);
  }
  function u(r, g) {
    i.defined(g) && (this.options[r] = s(g));
  }
  return (
    (_e = function (r) {
      (Object.assign(r.prototype, {
        tint: w,
        greyscale: a,
        grayscale: c,
        pipelineColourspace: o,
        pipelineColorspace: l,
        toColourspace: n,
        toColorspace: f,
        _getBackgroundColourOption: s,
        _setBackgroundColourOption: u,
      }),
        (r.colourspace = b),
        (r.colorspace = b));
    }),
    _e
  );
}
var Fe, Lr;
function At() {
  if (Lr) return Fe;
  Lr = 1;
  const e = G(),
    i = { and: "and", or: "or", eor: "eor" };
  function b() {
    return ((this.options.removeAlpha = !0), this);
  }
  function w(l) {
    if (e.defined(l))
      if (e.number(l) && e.inRange(l, 0, 1)) this.options.ensureAlpha = l;
      else throw e.invalidParameterError("alpha", "number between 0 and 1", l);
    else this.options.ensureAlpha = 1;
    return this;
  }
  function a(l) {
    const n = { red: 0, green: 1, blue: 2, alpha: 3 };
    if (
      (Object.keys(n).includes(l) && (l = n[l]),
      e.integer(l) && e.inRange(l, 0, 4))
    )
      this.options.extractChannel = l;
    else
      throw e.invalidParameterError(
        "channel",
        "integer or one of: red, green, blue, alpha",
        l,
      );
    return this;
  }
  function c(l, n) {
    return (
      Array.isArray(l)
        ? l.forEach(function (f) {
            this.options.joinChannelIn.push(this._createInputDescriptor(f, n));
          }, this)
        : this.options.joinChannelIn.push(this._createInputDescriptor(l, n)),
      this
    );
  }
  function o(l) {
    if (e.string(l) && e.inArray(l, ["and", "or", "eor"]))
      this.options.bandBoolOp = l;
    else throw e.invalidParameterError("boolOp", "one of: and, or, eor", l);
    return this;
  }
  return (
    (Fe = function (l) {
      (Object.assign(l.prototype, {
        removeAlpha: b,
        ensureAlpha: w,
        extractChannel: a,
        joinChannel: c,
        bandbool: o,
      }),
        (l.bool = i));
    }),
    Fe
  );
}
var Te, Sr;
function $t() {
  if (Sr) return Te;
  Sr = 1;
  const e = Wr,
    i = G(),
    b = Y(),
    w = new Map([
      ["heic", "heif"],
      ["heif", "heif"],
      ["avif", "avif"],
      ["jpeg", "jpeg"],
      ["jpg", "jpeg"],
      ["jpe", "jpeg"],
      ["tile", "tile"],
      ["dz", "tile"],
      ["png", "png"],
      ["raw", "raw"],
      ["tiff", "tiff"],
      ["tif", "tiff"],
      ["webp", "webp"],
      ["gif", "gif"],
      ["jp2", "jp2"],
      ["jpx", "jp2"],
      ["j2k", "jp2"],
      ["j2c", "jp2"],
      ["jxl", "jxl"],
    ]),
    a = /\.(jp[2x]|j2[kc])$/i,
    c = () =>
      new Error("JP2 output requires libvips with support for OpenJPEG"),
    o = (t) => 1 << (31 - Math.clz32(Math.ceil(Math.log2(t))));
  function l(t, x) {
    let A;
    if (
      (i.string(t)
        ? i.string(this.options.input.file) &&
          e.resolve(this.options.input.file) === e.resolve(t)
          ? (A = new Error("Cannot use same file for input and output"))
          : a.test(e.extname(t)) &&
            !this.constructor.format.jp2k.output.file &&
            (A = c())
        : (A = new Error("Missing output file path")),
      A)
    )
      if (i.fn(x)) x(A);
      else return Promise.reject(A);
    else {
      this.options.fileOut = t;
      const L = Error();
      return this._pipeline(x, L);
    }
    return this;
  }
  function n(t, x) {
    (i.object(t)
      ? this._setBooleanOption("resolveWithObject", t.resolveWithObject)
      : this.options.resolveWithObject && (this.options.resolveWithObject = !1),
      (this.options.fileOut = ""));
    const A = Error();
    return this._pipeline(i.fn(t) ? t : x, A);
  }
  function f() {
    return ((this.options.keepMetadata |= 1), this);
  }
  function s(t) {
    if (i.object(t))
      for (const [x, A] of Object.entries(t))
        if (i.object(A))
          for (const [L, S] of Object.entries(A))
            if (i.string(S))
              this.options.withExif[`exif-${x.toLowerCase()}-${L}`] = S;
            else throw i.invalidParameterError(`${x}.${L}`, "string", S);
        else throw i.invalidParameterError(x, "object", A);
    else throw i.invalidParameterError("exif", "object", t);
    return ((this.options.withExifMerge = !1), this.keepExif());
  }
  function u(t) {
    return (this.withExif(t), (this.options.withExifMerge = !0), this);
  }
  function r() {
    return ((this.options.keepMetadata |= 8), this);
  }
  function g(t, x) {
    if (i.string(t)) this.options.withIccProfile = t;
    else throw i.invalidParameterError("icc", "string", t);
    if ((this.keepIccProfile(), i.object(x) && i.defined(x.attach)))
      if (i.bool(x.attach)) x.attach || (this.options.keepMetadata &= -9);
      else throw i.invalidParameterError("attach", "boolean", x.attach);
    return this;
  }
  function h() {
    return ((this.options.keepMetadata |= 2), this);
  }
  function m(t) {
    if (i.string(t) && t.length > 0)
      ((this.options.withXmp = t), (this.options.keepMetadata |= 2));
    else throw i.invalidParameterError("xmp", "non-empty string", t);
    return this;
  }
  function p() {
    return ((this.options.keepMetadata = 31), this);
  }
  function E(t) {
    if ((this.keepMetadata(), this.withIccProfile("srgb"), i.object(t))) {
      if (i.defined(t.orientation))
        if (i.integer(t.orientation) && i.inRange(t.orientation, 1, 8))
          this.options.withMetadataOrientation = t.orientation;
        else
          throw i.invalidParameterError(
            "orientation",
            "integer between 1 and 8",
            t.orientation,
          );
      if (i.defined(t.density))
        if (i.number(t.density) && t.density > 0)
          this.options.withMetadataDensity = t.density;
        else
          throw i.invalidParameterError(
            "density",
            "positive number",
            t.density,
          );
      (i.defined(t.icc) && this.withIccProfile(t.icc),
        i.defined(t.exif) && this.withExifMerge(t.exif));
    }
    return this;
  }
  function N(t, x) {
    const A = w.get((i.object(t) && i.string(t.id) ? t.id : t).toLowerCase());
    if (!A)
      throw i.invalidParameterError(
        "format",
        `one of: ${[...w.keys()].join(", ")}`,
        t,
      );
    return this[A](x);
  }
  function k(t) {
    if (i.object(t)) {
      if (i.defined(t.quality))
        if (i.integer(t.quality) && i.inRange(t.quality, 1, 100))
          this.options.jpegQuality = t.quality;
        else
          throw i.invalidParameterError(
            "quality",
            "integer between 1 and 100",
            t.quality,
          );
      if (
        (i.defined(t.progressive) &&
          this._setBooleanOption("jpegProgressive", t.progressive),
        i.defined(t.chromaSubsampling))
      )
        if (
          i.string(t.chromaSubsampling) &&
          i.inArray(t.chromaSubsampling, ["4:2:0", "4:4:4"])
        )
          this.options.jpegChromaSubsampling = t.chromaSubsampling;
        else
          throw i.invalidParameterError(
            "chromaSubsampling",
            "one of: 4:2:0, 4:4:4",
            t.chromaSubsampling,
          );
      const x = i.bool(t.optimizeCoding) ? t.optimizeCoding : t.optimiseCoding;
      if (
        (i.defined(x) && this._setBooleanOption("jpegOptimiseCoding", x),
        i.defined(t.mozjpeg))
      )
        if (i.bool(t.mozjpeg))
          t.mozjpeg &&
            ((this.options.jpegTrellisQuantisation = !0),
            (this.options.jpegOvershootDeringing = !0),
            (this.options.jpegOptimiseScans = !0),
            (this.options.jpegProgressive = !0),
            (this.options.jpegQuantisationTable = 3));
        else throw i.invalidParameterError("mozjpeg", "boolean", t.mozjpeg);
      const A = i.bool(t.trellisQuantization)
        ? t.trellisQuantization
        : t.trellisQuantisation;
      (i.defined(A) && this._setBooleanOption("jpegTrellisQuantisation", A),
        i.defined(t.overshootDeringing) &&
          this._setBooleanOption(
            "jpegOvershootDeringing",
            t.overshootDeringing,
          ));
      const L = i.bool(t.optimizeScans) ? t.optimizeScans : t.optimiseScans;
      i.defined(L) &&
        (this._setBooleanOption("jpegOptimiseScans", L),
        L && (this.options.jpegProgressive = !0));
      const S = i.number(t.quantizationTable)
        ? t.quantizationTable
        : t.quantisationTable;
      if (i.defined(S))
        if (i.integer(S) && i.inRange(S, 0, 8))
          this.options.jpegQuantisationTable = S;
        else
          throw i.invalidParameterError(
            "quantisationTable",
            "integer between 0 and 8",
            S,
          );
    }
    return this._updateFormatOut("jpeg", t);
  }
  function _(t) {
    if (i.object(t)) {
      if (
        (i.defined(t.progressive) &&
          this._setBooleanOption("pngProgressive", t.progressive),
        i.defined(t.compressionLevel))
      )
        if (
          i.integer(t.compressionLevel) &&
          i.inRange(t.compressionLevel, 0, 9)
        )
          this.options.pngCompressionLevel = t.compressionLevel;
        else
          throw i.invalidParameterError(
            "compressionLevel",
            "integer between 0 and 9",
            t.compressionLevel,
          );
      i.defined(t.adaptiveFiltering) &&
        this._setBooleanOption("pngAdaptiveFiltering", t.adaptiveFiltering);
      const x = t.colours || t.colors;
      if (i.defined(x))
        if (i.integer(x) && i.inRange(x, 2, 256))
          this.options.pngBitdepth = o(x);
        else
          throw i.invalidParameterError(
            "colours",
            "integer between 2 and 256",
            x,
          );
      if (
        (i.defined(t.palette)
          ? this._setBooleanOption("pngPalette", t.palette)
          : [t.quality, t.effort, t.colours, t.colors, t.dither].some(
              i.defined,
            ) && this._setBooleanOption("pngPalette", !0),
        this.options.pngPalette)
      ) {
        if (i.defined(t.quality))
          if (i.integer(t.quality) && i.inRange(t.quality, 0, 100))
            this.options.pngQuality = t.quality;
          else
            throw i.invalidParameterError(
              "quality",
              "integer between 0 and 100",
              t.quality,
            );
        if (i.defined(t.effort))
          if (i.integer(t.effort) && i.inRange(t.effort, 1, 10))
            this.options.pngEffort = t.effort;
          else
            throw i.invalidParameterError(
              "effort",
              "integer between 1 and 10",
              t.effort,
            );
        if (i.defined(t.dither))
          if (i.number(t.dither) && i.inRange(t.dither, 0, 1))
            this.options.pngDither = t.dither;
          else
            throw i.invalidParameterError(
              "dither",
              "number between 0.0 and 1.0",
              t.dither,
            );
      }
    }
    return this._updateFormatOut("png", t);
  }
  function F(t) {
    if (i.object(t)) {
      if (i.defined(t.quality))
        if (i.integer(t.quality) && i.inRange(t.quality, 1, 100))
          this.options.webpQuality = t.quality;
        else
          throw i.invalidParameterError(
            "quality",
            "integer between 1 and 100",
            t.quality,
          );
      if (i.defined(t.alphaQuality))
        if (i.integer(t.alphaQuality) && i.inRange(t.alphaQuality, 0, 100))
          this.options.webpAlphaQuality = t.alphaQuality;
        else
          throw i.invalidParameterError(
            "alphaQuality",
            "integer between 0 and 100",
            t.alphaQuality,
          );
      if (
        (i.defined(t.lossless) &&
          this._setBooleanOption("webpLossless", t.lossless),
        i.defined(t.nearLossless) &&
          this._setBooleanOption("webpNearLossless", t.nearLossless),
        i.defined(t.smartSubsample) &&
          this._setBooleanOption("webpSmartSubsample", t.smartSubsample),
        i.defined(t.smartDeblock) &&
          this._setBooleanOption("webpSmartDeblock", t.smartDeblock),
        i.defined(t.preset))
      )
        if (
          i.string(t.preset) &&
          i.inArray(t.preset, [
            "default",
            "photo",
            "picture",
            "drawing",
            "icon",
            "text",
          ])
        )
          this.options.webpPreset = t.preset;
        else
          throw i.invalidParameterError(
            "preset",
            "one of: default, photo, picture, drawing, icon, text",
            t.preset,
          );
      if (i.defined(t.effort))
        if (i.integer(t.effort) && i.inRange(t.effort, 0, 6))
          this.options.webpEffort = t.effort;
        else
          throw i.invalidParameterError(
            "effort",
            "integer between 0 and 6",
            t.effort,
          );
      (i.defined(t.minSize) && this._setBooleanOption("webpMinSize", t.minSize),
        i.defined(t.mixed) && this._setBooleanOption("webpMixed", t.mixed));
    }
    return (T(t, this.options), this._updateFormatOut("webp", t));
  }
  function B(t) {
    if (i.object(t)) {
      (i.defined(t.reuse) && this._setBooleanOption("gifReuse", t.reuse),
        i.defined(t.progressive) &&
          this._setBooleanOption("gifProgressive", t.progressive));
      const x = t.colours || t.colors;
      if (i.defined(x))
        if (i.integer(x) && i.inRange(x, 2, 256))
          this.options.gifBitdepth = o(x);
        else
          throw i.invalidParameterError(
            "colours",
            "integer between 2 and 256",
            x,
          );
      if (i.defined(t.effort))
        if (i.number(t.effort) && i.inRange(t.effort, 1, 10))
          this.options.gifEffort = t.effort;
        else
          throw i.invalidParameterError(
            "effort",
            "integer between 1 and 10",
            t.effort,
          );
      if (i.defined(t.dither))
        if (i.number(t.dither) && i.inRange(t.dither, 0, 1))
          this.options.gifDither = t.dither;
        else
          throw i.invalidParameterError(
            "dither",
            "number between 0.0 and 1.0",
            t.dither,
          );
      if (i.defined(t.interFrameMaxError))
        if (
          i.number(t.interFrameMaxError) &&
          i.inRange(t.interFrameMaxError, 0, 32)
        )
          this.options.gifInterFrameMaxError = t.interFrameMaxError;
        else
          throw i.invalidParameterError(
            "interFrameMaxError",
            "number between 0.0 and 32.0",
            t.interFrameMaxError,
          );
      if (i.defined(t.interPaletteMaxError))
        if (
          i.number(t.interPaletteMaxError) &&
          i.inRange(t.interPaletteMaxError, 0, 256)
        )
          this.options.gifInterPaletteMaxError = t.interPaletteMaxError;
        else
          throw i.invalidParameterError(
            "interPaletteMaxError",
            "number between 0.0 and 256.0",
            t.interPaletteMaxError,
          );
      if (i.defined(t.keepDuplicateFrames))
        if (i.bool(t.keepDuplicateFrames))
          this._setBooleanOption(
            "gifKeepDuplicateFrames",
            t.keepDuplicateFrames,
          );
        else
          throw i.invalidParameterError(
            "keepDuplicateFrames",
            "boolean",
            t.keepDuplicateFrames,
          );
    }
    return (T(t, this.options), this._updateFormatOut("gif", t));
  }
  function D(t) {
    if (!this.constructor.format.jp2k.output.buffer) throw c();
    if (i.object(t)) {
      if (i.defined(t.quality))
        if (i.integer(t.quality) && i.inRange(t.quality, 1, 100))
          this.options.jp2Quality = t.quality;
        else
          throw i.invalidParameterError(
            "quality",
            "integer between 1 and 100",
            t.quality,
          );
      if (i.defined(t.lossless))
        if (i.bool(t.lossless)) this.options.jp2Lossless = t.lossless;
        else throw i.invalidParameterError("lossless", "boolean", t.lossless);
      if (i.defined(t.tileWidth))
        if (i.integer(t.tileWidth) && i.inRange(t.tileWidth, 1, 32768))
          this.options.jp2TileWidth = t.tileWidth;
        else
          throw i.invalidParameterError(
            "tileWidth",
            "integer between 1 and 32768",
            t.tileWidth,
          );
      if (i.defined(t.tileHeight))
        if (i.integer(t.tileHeight) && i.inRange(t.tileHeight, 1, 32768))
          this.options.jp2TileHeight = t.tileHeight;
        else
          throw i.invalidParameterError(
            "tileHeight",
            "integer between 1 and 32768",
            t.tileHeight,
          );
      if (i.defined(t.chromaSubsampling))
        if (
          i.string(t.chromaSubsampling) &&
          i.inArray(t.chromaSubsampling, ["4:2:0", "4:4:4"])
        )
          this.options.jp2ChromaSubsampling = t.chromaSubsampling;
        else
          throw i.invalidParameterError(
            "chromaSubsampling",
            "one of: 4:2:0, 4:4:4",
            t.chromaSubsampling,
          );
    }
    return this._updateFormatOut("jp2", t);
  }
  function T(t, x) {
    if (i.object(t) && i.defined(t.loop))
      if (i.integer(t.loop) && i.inRange(t.loop, 0, 65535)) x.loop = t.loop;
      else
        throw i.invalidParameterError(
          "loop",
          "integer between 0 and 65535",
          t.loop,
        );
    if (i.object(t) && i.defined(t.delay))
      if (i.integer(t.delay) && i.inRange(t.delay, 0, 65535))
        x.delay = [t.delay];
      else if (
        Array.isArray(t.delay) &&
        t.delay.every(i.integer) &&
        t.delay.every((A) => i.inRange(A, 0, 65535))
      )
        x.delay = t.delay;
      else
        throw i.invalidParameterError(
          "delay",
          "integer or an array of integers between 0 and 65535",
          t.delay,
        );
  }
  function d(t) {
    if (i.object(t)) {
      if (i.defined(t.quality))
        if (i.integer(t.quality) && i.inRange(t.quality, 1, 100))
          this.options.tiffQuality = t.quality;
        else
          throw i.invalidParameterError(
            "quality",
            "integer between 1 and 100",
            t.quality,
          );
      if (i.defined(t.bitdepth))
        if (i.integer(t.bitdepth) && i.inArray(t.bitdepth, [1, 2, 4, 8]))
          this.options.tiffBitdepth = t.bitdepth;
        else
          throw i.invalidParameterError("bitdepth", "1, 2, 4 or 8", t.bitdepth);
      if (
        (i.defined(t.tile) && this._setBooleanOption("tiffTile", t.tile),
        i.defined(t.tileWidth))
      )
        if (i.integer(t.tileWidth) && t.tileWidth > 0)
          this.options.tiffTileWidth = t.tileWidth;
        else
          throw i.invalidParameterError(
            "tileWidth",
            "integer greater than zero",
            t.tileWidth,
          );
      if (i.defined(t.tileHeight))
        if (i.integer(t.tileHeight) && t.tileHeight > 0)
          this.options.tiffTileHeight = t.tileHeight;
        else
          throw i.invalidParameterError(
            "tileHeight",
            "integer greater than zero",
            t.tileHeight,
          );
      if (
        (i.defined(t.miniswhite) &&
          this._setBooleanOption("tiffMiniswhite", t.miniswhite),
        i.defined(t.pyramid) &&
          this._setBooleanOption("tiffPyramid", t.pyramid),
        i.defined(t.xres))
      )
        if (i.number(t.xres) && t.xres > 0) this.options.tiffXres = t.xres;
        else
          throw i.invalidParameterError(
            "xres",
            "number greater than zero",
            t.xres,
          );
      if (i.defined(t.yres))
        if (i.number(t.yres) && t.yres > 0) this.options.tiffYres = t.yres;
        else
          throw i.invalidParameterError(
            "yres",
            "number greater than zero",
            t.yres,
          );
      if (i.defined(t.compression))
        if (
          i.string(t.compression) &&
          i.inArray(t.compression, [
            "none",
            "jpeg",
            "deflate",
            "packbits",
            "ccittfax4",
            "lzw",
            "webp",
            "zstd",
            "jp2k",
          ])
        )
          this.options.tiffCompression = t.compression;
        else
          throw i.invalidParameterError(
            "compression",
            "one of: none, jpeg, deflate, packbits, ccittfax4, lzw, webp, zstd, jp2k",
            t.compression,
          );
      if (i.defined(t.predictor))
        if (
          i.string(t.predictor) &&
          i.inArray(t.predictor, ["none", "horizontal", "float"])
        )
          this.options.tiffPredictor = t.predictor;
        else
          throw i.invalidParameterError(
            "predictor",
            "one of: none, horizontal, float",
            t.predictor,
          );
      if (i.defined(t.resolutionUnit))
        if (
          i.string(t.resolutionUnit) &&
          i.inArray(t.resolutionUnit, ["inch", "cm"])
        )
          this.options.tiffResolutionUnit = t.resolutionUnit;
        else
          throw i.invalidParameterError(
            "resolutionUnit",
            "one of: inch, cm",
            t.resolutionUnit,
          );
    }
    return this._updateFormatOut("tiff", t);
  }
  function R(t) {
    return this.heif({ ...t, compression: "av1" });
  }
  function q(t) {
    if (i.object(t)) {
      if (i.string(t.compression) && i.inArray(t.compression, ["av1", "hevc"]))
        this.options.heifCompression = t.compression;
      else
        throw i.invalidParameterError(
          "compression",
          "one of: av1, hevc",
          t.compression,
        );
      if (i.defined(t.quality))
        if (i.integer(t.quality) && i.inRange(t.quality, 1, 100))
          this.options.heifQuality = t.quality;
        else
          throw i.invalidParameterError(
            "quality",
            "integer between 1 and 100",
            t.quality,
          );
      if (i.defined(t.lossless))
        if (i.bool(t.lossless)) this.options.heifLossless = t.lossless;
        else throw i.invalidParameterError("lossless", "boolean", t.lossless);
      if (i.defined(t.effort))
        if (i.integer(t.effort) && i.inRange(t.effort, 0, 9))
          this.options.heifEffort = t.effort;
        else
          throw i.invalidParameterError(
            "effort",
            "integer between 0 and 9",
            t.effort,
          );
      if (i.defined(t.chromaSubsampling))
        if (
          i.string(t.chromaSubsampling) &&
          i.inArray(t.chromaSubsampling, ["4:2:0", "4:4:4"])
        )
          this.options.heifChromaSubsampling = t.chromaSubsampling;
        else
          throw i.invalidParameterError(
            "chromaSubsampling",
            "one of: 4:2:0, 4:4:4",
            t.chromaSubsampling,
          );
      if (i.defined(t.bitdepth))
        if (i.integer(t.bitdepth) && i.inArray(t.bitdepth, [8, 10, 12])) {
          if (t.bitdepth !== 8 && this.constructor.versions.heif)
            throw i.invalidParameterError(
              "bitdepth when using prebuilt binaries",
              8,
              t.bitdepth,
            );
          this.options.heifBitdepth = t.bitdepth;
        } else
          throw i.invalidParameterError("bitdepth", "8, 10 or 12", t.bitdepth);
    } else throw i.invalidParameterError("options", "Object", t);
    return this._updateFormatOut("heif", t);
  }
  function M(t) {
    if (i.object(t)) {
      if (i.defined(t.quality))
        if (i.integer(t.quality) && i.inRange(t.quality, 1, 100))
          this.options.jxlDistance =
            t.quality >= 30
              ? 0.1 + (100 - t.quality) * 0.09
              : (53 / 3e3) * t.quality * t.quality - (23 / 20) * t.quality + 25;
        else
          throw i.invalidParameterError(
            "quality",
            "integer between 1 and 100",
            t.quality,
          );
      else if (i.defined(t.distance))
        if (i.number(t.distance) && i.inRange(t.distance, 0, 15))
          this.options.jxlDistance = t.distance;
        else
          throw i.invalidParameterError(
            "distance",
            "number between 0.0 and 15.0",
            t.distance,
          );
      if (i.defined(t.decodingTier))
        if (i.integer(t.decodingTier) && i.inRange(t.decodingTier, 0, 4))
          this.options.jxlDecodingTier = t.decodingTier;
        else
          throw i.invalidParameterError(
            "decodingTier",
            "integer between 0 and 4",
            t.decodingTier,
          );
      if (i.defined(t.lossless))
        if (i.bool(t.lossless)) this.options.jxlLossless = t.lossless;
        else throw i.invalidParameterError("lossless", "boolean", t.lossless);
      if (i.defined(t.effort))
        if (i.integer(t.effort) && i.inRange(t.effort, 1, 9))
          this.options.jxlEffort = t.effort;
        else
          throw i.invalidParameterError(
            "effort",
            "integer between 1 and 9",
            t.effort,
          );
    }
    return (T(t, this.options), this._updateFormatOut("jxl", t));
  }
  function U(t) {
    if (i.object(t) && i.defined(t.depth))
      if (
        i.string(t.depth) &&
        i.inArray(t.depth, [
          "char",
          "uchar",
          "short",
          "ushort",
          "int",
          "uint",
          "float",
          "complex",
          "double",
          "dpcomplex",
        ])
      )
        this.options.rawDepth = t.depth;
      else
        throw i.invalidParameterError(
          "depth",
          "one of: char, uchar, short, ushort, int, uint, float, complex, double, dpcomplex",
          t.depth,
        );
    return this._updateFormatOut("raw");
  }
  function y(t) {
    if (i.object(t)) {
      if (i.defined(t.size))
        if (i.integer(t.size) && i.inRange(t.size, 1, 8192))
          this.options.tileSize = t.size;
        else
          throw i.invalidParameterError(
            "size",
            "integer between 1 and 8192",
            t.size,
          );
      if (i.defined(t.overlap))
        if (i.integer(t.overlap) && i.inRange(t.overlap, 0, 8192)) {
          if (t.overlap > this.options.tileSize)
            throw i.invalidParameterError(
              "overlap",
              `<= size (${this.options.tileSize})`,
              t.overlap,
            );
          this.options.tileOverlap = t.overlap;
        } else
          throw i.invalidParameterError(
            "overlap",
            "integer between 0 and 8192",
            t.overlap,
          );
      if (i.defined(t.container))
        if (i.string(t.container) && i.inArray(t.container, ["fs", "zip"]))
          this.options.tileContainer = t.container;
        else
          throw i.invalidParameterError(
            "container",
            "one of: fs, zip",
            t.container,
          );
      if (i.defined(t.layout))
        if (
          i.string(t.layout) &&
          i.inArray(t.layout, ["dz", "google", "iiif", "iiif3", "zoomify"])
        )
          this.options.tileLayout = t.layout;
        else
          throw i.invalidParameterError(
            "layout",
            "one of: dz, google, iiif, iiif3, zoomify",
            t.layout,
          );
      if (i.defined(t.angle))
        if (i.integer(t.angle) && !(t.angle % 90))
          this.options.tileAngle = t.angle;
        else
          throw i.invalidParameterError(
            "angle",
            "positive/negative multiple of 90",
            t.angle,
          );
      if (
        (this._setBackgroundColourOption("tileBackground", t.background),
        i.defined(t.depth))
      )
        if (
          i.string(t.depth) &&
          i.inArray(t.depth, ["onepixel", "onetile", "one"])
        )
          this.options.tileDepth = t.depth;
        else
          throw i.invalidParameterError(
            "depth",
            "one of: onepixel, onetile, one",
            t.depth,
          );
      if (i.defined(t.skipBlanks))
        if (i.integer(t.skipBlanks) && i.inRange(t.skipBlanks, -1, 65535))
          this.options.tileSkipBlanks = t.skipBlanks;
        else
          throw i.invalidParameterError(
            "skipBlanks",
            "integer between -1 and 255/65535",
            t.skipBlanks,
          );
      else
        i.defined(t.layout) &&
          t.layout === "google" &&
          (this.options.tileSkipBlanks = 5);
      const x = i.bool(t.center) ? t.center : t.centre;
      if (
        (i.defined(x) && this._setBooleanOption("tileCentre", x),
        i.defined(t.id))
      )
        if (i.string(t.id)) this.options.tileId = t.id;
        else throw i.invalidParameterError("id", "string", t.id);
      if (i.defined(t.basename))
        if (i.string(t.basename)) this.options.tileBasename = t.basename;
        else throw i.invalidParameterError("basename", "string", t.basename);
    }
    if (i.inArray(this.options.formatOut, ["jpeg", "png", "webp"]))
      this.options.tileFormat = this.options.formatOut;
    else if (this.options.formatOut !== "input")
      throw i.invalidParameterError(
        "format",
        "one of: jpeg, png, webp",
        this.options.formatOut,
      );
    return this._updateFormatOut("dz");
  }
  function P(t) {
    if (!i.plainObject(t))
      throw i.invalidParameterError("options", "object", t);
    if (i.integer(t.seconds) && i.inRange(t.seconds, 0, 3600))
      this.options.timeoutSeconds = t.seconds;
    else
      throw i.invalidParameterError(
        "seconds",
        "integer between 0 and 3600",
        t.seconds,
      );
    return this;
  }
  function v(t, x) {
    return (
      (i.object(x) && x.force === !1) || (this.options.formatOut = t),
      this
    );
  }
  function I(t, x) {
    if (i.bool(x)) this.options[t] = x;
    else throw i.invalidParameterError(t, "boolean", x);
  }
  function j() {
    if (!this.options.streamOut) {
      this.options.streamOut = !0;
      const t = Error();
      this._pipeline(void 0, t);
    }
  }
  function $(t, x) {
    return typeof t == "function"
      ? (this._isStreamInput()
          ? this.on("finish", () => {
              (this._flattenBufferIn(),
                b.pipeline(this.options, (A, L, S) => {
                  A ? t(i.nativeError(A, x)) : t(null, L, S);
                }));
            })
          : b.pipeline(this.options, (A, L, S) => {
              A ? t(i.nativeError(A, x)) : t(null, L, S);
            }),
        this)
      : this.options.streamOut
        ? (this._isStreamInput()
            ? (this.once("finish", () => {
                (this._flattenBufferIn(),
                  b.pipeline(this.options, (A, L, S) => {
                    (A
                      ? this.emit("error", i.nativeError(A, x))
                      : (this.emit("info", S), this.push(L)),
                      this.push(null),
                      this.on("end", () => this.emit("close")));
                  }));
              }),
              this.streamInFinished && this.emit("finish"))
            : b.pipeline(this.options, (A, L, S) => {
                (A
                  ? this.emit("error", i.nativeError(A, x))
                  : (this.emit("info", S), this.push(L)),
                  this.push(null),
                  this.on("end", () => this.emit("close")));
              }),
          this)
        : this._isStreamInput()
          ? new Promise((A, L) => {
              this.once("finish", () => {
                (this._flattenBufferIn(),
                  b.pipeline(this.options, (S, C, z) => {
                    S
                      ? L(i.nativeError(S, x))
                      : this.options.resolveWithObject
                        ? A({ data: C, info: z })
                        : A(C);
                  }));
              });
            })
          : new Promise((A, L) => {
              b.pipeline(this.options, (S, C, z) => {
                S
                  ? L(i.nativeError(S, x))
                  : this.options.resolveWithObject
                    ? A({ data: C, info: z })
                    : A(C);
              });
            });
  }
  return (
    (Te = function (t) {
      Object.assign(t.prototype, {
        toFile: l,
        toBuffer: n,
        keepExif: f,
        withExif: s,
        withExifMerge: u,
        keepIccProfile: r,
        withIccProfile: g,
        keepXmp: h,
        withXmp: m,
        keepMetadata: p,
        withMetadata: E,
        toFormat: N,
        jpeg: k,
        jp2: D,
        png: _,
        webp: F,
        tiff: d,
        avif: R,
        heif: q,
        jxl: M,
        gif: B,
        raw: U,
        tile: y,
        timeout: P,
        _updateFormatOut: v,
        _setBooleanOption: I,
        _read: j,
        _pipeline: $,
      });
    }),
    Te
  );
}
var Be, kr;
function jt() {
  if (kr) return Be;
  kr = 1;
  const e = Xr,
    i = Me(),
    b = G(),
    { runtimePlatformArch: w } = Fr(),
    a = Y(),
    c = w(),
    o = a.libvipsVersion(),
    l = a.format();
  ((l.heif.output.alias = ["avif", "heic"]),
    (l.jpeg.output.alias = ["jpe", "jpg"]),
    (l.tiff.output.alias = ["tif"]),
    (l.jp2k.output.alias = ["j2c", "j2k", "jp2", "jpx"]));
  const n = {
    nearest: "nearest",
    bilinear: "bilinear",
    bicubic: "bicubic",
    locallyBoundedBicubic: "lbb",
    nohalo: "nohalo",
    vertexSplitQuadraticBasisSpline: "vsqbs",
  };
  let f = { vips: o.semver };
  if (!o.isGlobal)
    if (o.isWasm)
      try {
        f = O("@img/sharp-wasm32/versions");
      } catch {}
    else
      try {
        f = O(`@img/sharp-${c}/versions`);
      } catch {
        try {
          f = O(`@img/sharp-libvips-${c}/versions`);
        } catch {}
      }
  ((f.sharp = _r.version),
    f.heif &&
      l.heif &&
      ((l.heif.input.fileSuffix = [".avif"]),
      (l.heif.output.alias = ["avif"])));
  function s(E) {
    return b.bool(E)
      ? E
        ? a.cache(50, 20, 100)
        : a.cache(0, 0, 0)
      : b.object(E)
        ? a.cache(E.memory, E.files, E.items)
        : a.cache();
  }
  s(!0);
  function u(E) {
    return a.concurrency(b.integer(E) ? E : null);
  }
  i.familySync() === i.GLIBC && !a._isUsingJemalloc()
    ? a.concurrency(1)
    : i.familySync() === i.MUSL &&
      a.concurrency() === 1024 &&
      a.concurrency(Vr.availableParallelism());
  const r = new e.EventEmitter();
  function g() {
    return a.counters();
  }
  function h(E) {
    return a.simd(b.bool(E) ? E : null);
  }
  function m(E) {
    if (b.object(E))
      if (Array.isArray(E.operation) && E.operation.every(b.string))
        a.block(E.operation, !0);
      else
        throw b.invalidParameterError(
          "operation",
          "Array<string>",
          E.operation,
        );
    else throw b.invalidParameterError("options", "object", E);
  }
  function p(E) {
    if (b.object(E))
      if (Array.isArray(E.operation) && E.operation.every(b.string))
        a.block(E.operation, !1);
      else
        throw b.invalidParameterError(
          "operation",
          "Array<string>",
          E.operation,
        );
    else throw b.invalidParameterError("options", "object", E);
  }
  return (
    (Be = function (E) {
      ((E.cache = s),
        (E.concurrency = u),
        (E.counters = g),
        (E.simd = h),
        (E.format = l),
        (E.interpolators = n),
        (E.versions = f),
        (E.queue = r),
        (E.block = m),
        (E.unblock = p));
    }),
    Be
  );
}
var De, Nr;
function Lt() {
  if (Nr) return De;
  Nr = 1;
  const e = gt();
  return (
    mt()(e),
    bt()(e),
    pt()(e),
    vt()(e),
    It()(e),
    At()(e),
    $t()(e),
    jt()(e),
    (De = e),
    De
  );
}
var St = Lt();
const Ut = Dr(St);
export { Rt as r, Ut as s };
//# sourceMappingURL=index-B_PiTES1.mjs.map
