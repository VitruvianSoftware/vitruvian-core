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
    var u = new t.Error().stack;
    u &&
      ((t._sentryDebugIds = t._sentryDebugIds || {}),
      (t._sentryDebugIds[u] = "de149a15-32ed-49cf-8caa-df23519f7750"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-de149a15-32ed-49cf-8caa-df23519f7750"));
  } catch {}
})();
var M = { exports: {} },
  ee,
  Ke;
function k() {
  if (Ke) return ee;
  Ke = 1;
  const t = "2.0.0",
    u = 256,
    n = Number.MAX_SAFE_INTEGER || 9007199254740991,
    r = 16,
    i = u - 6;
  return (
    (ee = {
      MAX_LENGTH: u,
      MAX_SAFE_COMPONENT_LENGTH: r,
      MAX_SAFE_BUILD_LENGTH: i,
      MAX_SAFE_INTEGER: n,
      RELEASE_TYPES: [
        "major",
        "premajor",
        "minor",
        "preminor",
        "patch",
        "prepatch",
        "prerelease",
      ],
      SEMVER_SPEC_VERSION: t,
      FLAG_INCLUDE_PRERELEASE: 1,
      FLAG_LOOSE: 2,
    }),
    ee
  );
}
var re, Ze;
function B() {
  return (
    Ze ||
      ((Ze = 1),
      (re =
        typeof process == "object" &&
        process.env &&
        process.env.NODE_DEBUG &&
        /\bsemver\b/i.test(process.env.NODE_DEBUG)
          ? (...u) => console.error("SEMVER", ...u)
          : () => {})),
    re
  );
}
var Je;
function H() {
  return (
    Je ||
      ((Je = 1),
      (function (t, u) {
        const {
            MAX_SAFE_COMPONENT_LENGTH: n,
            MAX_SAFE_BUILD_LENGTH: r,
            MAX_LENGTH: i,
          } = k(),
          p = B();
        u = t.exports = {};
        const c = (u.re = []),
          f = (u.safeRe = []),
          s = (u.src = []),
          e = (u.t = {});
        let a = 0;
        const o = "[a-zA-Z0-9-]",
          l = [
            ["\\s", 1],
            ["\\d", i],
            [o, r],
          ],
          m = (T) => {
            for (const [O, w] of l)
              T = T.split(`${O}*`)
                .join(`${O}{0,${w}}`)
                .split(`${O}+`)
                .join(`${O}{1,${w}}`);
            return T;
          },
          E = (T, O, w) => {
            const _ = m(O),
              A = a++;
            (p(T, A, O),
              (e[T] = A),
              (s[A] = O),
              (c[A] = new RegExp(O, w ? "g" : void 0)),
              (f[A] = new RegExp(_, w ? "g" : void 0)));
          };
        (E("NUMERICIDENTIFIER", "0|[1-9]\\d*"),
          E("NUMERICIDENTIFIERLOOSE", "\\d+"),
          E("NONNUMERICIDENTIFIER", `\\d*[a-zA-Z-]${o}*`),
          E(
            "MAINVERSION",
            `(${s[e.NUMERICIDENTIFIER]})\\.(${s[e.NUMERICIDENTIFIER]})\\.(${s[e.NUMERICIDENTIFIER]})`,
          ),
          E(
            "MAINVERSIONLOOSE",
            `(${s[e.NUMERICIDENTIFIERLOOSE]})\\.(${s[e.NUMERICIDENTIFIERLOOSE]})\\.(${s[e.NUMERICIDENTIFIERLOOSE]})`,
          ),
          E(
            "PRERELEASEIDENTIFIER",
            `(?:${s[e.NUMERICIDENTIFIER]}|${s[e.NONNUMERICIDENTIFIER]})`,
          ),
          E(
            "PRERELEASEIDENTIFIERLOOSE",
            `(?:${s[e.NUMERICIDENTIFIERLOOSE]}|${s[e.NONNUMERICIDENTIFIER]})`,
          ),
          E(
            "PRERELEASE",
            `(?:-(${s[e.PRERELEASEIDENTIFIER]}(?:\\.${s[e.PRERELEASEIDENTIFIER]})*))`,
          ),
          E(
            "PRERELEASELOOSE",
            `(?:-?(${s[e.PRERELEASEIDENTIFIERLOOSE]}(?:\\.${s[e.PRERELEASEIDENTIFIERLOOSE]})*))`,
          ),
          E("BUILDIDENTIFIER", `${o}+`),
          E(
            "BUILD",
            `(?:\\+(${s[e.BUILDIDENTIFIER]}(?:\\.${s[e.BUILDIDENTIFIER]})*))`,
          ),
          E(
            "FULLPLAIN",
            `v?${s[e.MAINVERSION]}${s[e.PRERELEASE]}?${s[e.BUILD]}?`,
          ),
          E("FULL", `^${s[e.FULLPLAIN]}$`),
          E(
            "LOOSEPLAIN",
            `[v=\\s]*${s[e.MAINVERSIONLOOSE]}${s[e.PRERELEASELOOSE]}?${s[e.BUILD]}?`,
          ),
          E("LOOSE", `^${s[e.LOOSEPLAIN]}$`),
          E("GTLT", "((?:<|>)?=?)"),
          E("XRANGEIDENTIFIERLOOSE", `${s[e.NUMERICIDENTIFIERLOOSE]}|x|X|\\*`),
          E("XRANGEIDENTIFIER", `${s[e.NUMERICIDENTIFIER]}|x|X|\\*`),
          E(
            "XRANGEPLAIN",
            `[v=\\s]*(${s[e.XRANGEIDENTIFIER]})(?:\\.(${s[e.XRANGEIDENTIFIER]})(?:\\.(${s[e.XRANGEIDENTIFIER]})(?:${s[e.PRERELEASE]})?${s[e.BUILD]}?)?)?`,
          ),
          E(
            "XRANGEPLAINLOOSE",
            `[v=\\s]*(${s[e.XRANGEIDENTIFIERLOOSE]})(?:\\.(${s[e.XRANGEIDENTIFIERLOOSE]})(?:\\.(${s[e.XRANGEIDENTIFIERLOOSE]})(?:${s[e.PRERELEASELOOSE]})?${s[e.BUILD]}?)?)?`,
          ),
          E("XRANGE", `^${s[e.GTLT]}\\s*${s[e.XRANGEPLAIN]}$`),
          E("XRANGELOOSE", `^${s[e.GTLT]}\\s*${s[e.XRANGEPLAINLOOSE]}$`),
          E(
            "COERCEPLAIN",
            `(^|[^\\d])(\\d{1,${n}})(?:\\.(\\d{1,${n}}))?(?:\\.(\\d{1,${n}}))?`,
          ),
          E("COERCE", `${s[e.COERCEPLAIN]}(?:$|[^\\d])`),
          E(
            "COERCEFULL",
            s[e.COERCEPLAIN] +
              `(?:${s[e.PRERELEASE]})?(?:${s[e.BUILD]})?(?:$|[^\\d])`,
          ),
          E("COERCERTL", s[e.COERCE], !0),
          E("COERCERTLFULL", s[e.COERCEFULL], !0),
          E("LONETILDE", "(?:~>?)"),
          E("TILDETRIM", `(\\s*)${s[e.LONETILDE]}\\s+`, !0),
          (u.tildeTrimReplace = "$1~"),
          E("TILDE", `^${s[e.LONETILDE]}${s[e.XRANGEPLAIN]}$`),
          E("TILDELOOSE", `^${s[e.LONETILDE]}${s[e.XRANGEPLAINLOOSE]}$`),
          E("LONECARET", "(?:\\^)"),
          E("CARETTRIM", `(\\s*)${s[e.LONECARET]}\\s+`, !0),
          (u.caretTrimReplace = "$1^"),
          E("CARET", `^${s[e.LONECARET]}${s[e.XRANGEPLAIN]}$`),
          E("CARETLOOSE", `^${s[e.LONECARET]}${s[e.XRANGEPLAINLOOSE]}$`),
          E("COMPARATORLOOSE", `^${s[e.GTLT]}\\s*(${s[e.LOOSEPLAIN]})$|^$`),
          E("COMPARATOR", `^${s[e.GTLT]}\\s*(${s[e.FULLPLAIN]})$|^$`),
          E(
            "COMPARATORTRIM",
            `(\\s*)${s[e.GTLT]}\\s*(${s[e.LOOSEPLAIN]}|${s[e.XRANGEPLAIN]})`,
            !0,
          ),
          (u.comparatorTrimReplace = "$1$2$3"),
          E(
            "HYPHENRANGE",
            `^\\s*(${s[e.XRANGEPLAIN]})\\s+-\\s+(${s[e.XRANGEPLAIN]})\\s*$`,
          ),
          E(
            "HYPHENRANGELOOSE",
            `^\\s*(${s[e.XRANGEPLAINLOOSE]})\\s+-\\s+(${s[e.XRANGEPLAINLOOSE]})\\s*$`,
          ),
          E("STAR", "(<|>)?=?\\s*\\*"),
          E("GTE0", "^\\s*>=\\s*0\\.0\\.0\\s*$"),
          E("GTE0PRE", "^\\s*>=\\s*0\\.0\\.0-0\\s*$"));
      })(M, M.exports)),
    M.exports
  );
}
var te, Qe;
function Me() {
  if (Qe) return te;
  Qe = 1;
  const t = Object.freeze({ loose: !0 }),
    u = Object.freeze({});
  return ((te = (r) => (r ? (typeof r != "object" ? t : r) : u)), te);
}
var se, er;
function br() {
  if (er) return se;
  er = 1;
  const t = /^[0-9]+$/,
    u = (r, i) => {
      const p = t.test(r),
        c = t.test(i);
      return (
        p && c && ((r = +r), (i = +i)),
        r === i ? 0 : p && !c ? -1 : c && !p ? 1 : r < i ? -1 : 1
      );
    };
  return (
    (se = { compareIdentifiers: u, rcompareIdentifiers: (r, i) => u(i, r) }),
    se
  );
}
var ne, rr;
function G() {
  if (rr) return ne;
  rr = 1;
  const t = B(),
    { MAX_LENGTH: u, MAX_SAFE_INTEGER: n } = k(),
    { safeRe: r, t: i } = H(),
    p = Me(),
    { compareIdentifiers: c } = br();
  class f {
    constructor(e, a) {
      if (((a = p(a)), e instanceof f)) {
        if (
          e.loose === !!a.loose &&
          e.includePrerelease === !!a.includePrerelease
        )
          return e;
        e = e.version;
      } else if (typeof e != "string")
        throw new TypeError(
          `Invalid version. Must be a string. Got type "${typeof e}".`,
        );
      if (e.length > u)
        throw new TypeError(`version is longer than ${u} characters`);
      (t("SemVer", e, a),
        (this.options = a),
        (this.loose = !!a.loose),
        (this.includePrerelease = !!a.includePrerelease));
      const o = e.trim().match(a.loose ? r[i.LOOSE] : r[i.FULL]);
      if (!o) throw new TypeError(`Invalid Version: ${e}`);
      if (
        ((this.raw = e),
        (this.major = +o[1]),
        (this.minor = +o[2]),
        (this.patch = +o[3]),
        this.major > n || this.major < 0)
      )
        throw new TypeError("Invalid major version");
      if (this.minor > n || this.minor < 0)
        throw new TypeError("Invalid minor version");
      if (this.patch > n || this.patch < 0)
        throw new TypeError("Invalid patch version");
      (o[4]
        ? (this.prerelease = o[4].split(".").map((l) => {
            if (/^[0-9]+$/.test(l)) {
              const m = +l;
              if (m >= 0 && m < n) return m;
            }
            return l;
          }))
        : (this.prerelease = []),
        (this.build = o[5] ? o[5].split(".") : []),
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
    compare(e) {
      if (
        (t("SemVer.compare", this.version, this.options, e), !(e instanceof f))
      ) {
        if (typeof e == "string" && e === this.version) return 0;
        e = new f(e, this.options);
      }
      return e.version === this.version
        ? 0
        : this.compareMain(e) || this.comparePre(e);
    }
    compareMain(e) {
      return (
        e instanceof f || (e = new f(e, this.options)),
        c(this.major, e.major) ||
          c(this.minor, e.minor) ||
          c(this.patch, e.patch)
      );
    }
    comparePre(e) {
      if (
        (e instanceof f || (e = new f(e, this.options)),
        this.prerelease.length && !e.prerelease.length)
      )
        return -1;
      if (!this.prerelease.length && e.prerelease.length) return 1;
      if (!this.prerelease.length && !e.prerelease.length) return 0;
      let a = 0;
      do {
        const o = this.prerelease[a],
          l = e.prerelease[a];
        if ((t("prerelease compare", a, o, l), o === void 0 && l === void 0))
          return 0;
        if (l === void 0) return 1;
        if (o === void 0) return -1;
        if (o === l) continue;
        return c(o, l);
      } while (++a);
    }
    compareBuild(e) {
      e instanceof f || (e = new f(e, this.options));
      let a = 0;
      do {
        const o = this.build[a],
          l = e.build[a];
        if ((t("build compare", a, o, l), o === void 0 && l === void 0))
          return 0;
        if (l === void 0) return 1;
        if (o === void 0) return -1;
        if (o === l) continue;
        return c(o, l);
      } while (++a);
    }
    inc(e, a, o) {
      switch (e) {
        case "premajor":
          ((this.prerelease.length = 0),
            (this.patch = 0),
            (this.minor = 0),
            this.major++,
            this.inc("pre", a, o));
          break;
        case "preminor":
          ((this.prerelease.length = 0),
            (this.patch = 0),
            this.minor++,
            this.inc("pre", a, o));
          break;
        case "prepatch":
          ((this.prerelease.length = 0),
            this.inc("patch", a, o),
            this.inc("pre", a, o));
          break;
        case "prerelease":
          (this.prerelease.length === 0 && this.inc("patch", a, o),
            this.inc("pre", a, o));
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
          const l = Number(o) ? 1 : 0;
          if (!a && o === !1)
            throw new Error("invalid increment argument: identifier is empty");
          if (this.prerelease.length === 0) this.prerelease = [l];
          else {
            let m = this.prerelease.length;
            for (; --m >= 0;)
              typeof this.prerelease[m] == "number" &&
                (this.prerelease[m]++, (m = -2));
            if (m === -1) {
              if (a === this.prerelease.join(".") && o === !1)
                throw new Error(
                  "invalid increment argument: identifier already exists",
                );
              this.prerelease.push(l);
            }
          }
          if (a) {
            let m = [a, l];
            (o === !1 && (m = [a]),
              c(this.prerelease[0], a) === 0
                ? isNaN(this.prerelease[1]) && (this.prerelease = m)
                : (this.prerelease = m));
          }
          break;
        }
        default:
          throw new Error(`invalid increment argument: ${e}`);
      }
      return (
        (this.raw = this.format()),
        this.build.length && (this.raw += `+${this.build.join(".")}`),
        this
      );
    }
  }
  return ((ne = f), ne);
}
var ie, tr;
function V() {
  if (tr) return ie;
  tr = 1;
  const t = G();
  return (
    (ie = (n, r, i = !1) => {
      if (n instanceof t) return n;
      try {
        return new t(n, r);
      } catch (p) {
        if (!i) return null;
        throw p;
      }
    }),
    ie
  );
}
var ae, sr;
function kr() {
  if (sr) return ae;
  sr = 1;
  const t = V();
  return (
    (ae = (n, r) => {
      const i = t(n, r);
      return i ? i.version : null;
    }),
    ae
  );
}
var oe, nr;
function Br() {
  if (nr) return oe;
  nr = 1;
  const t = V();
  return (
    (oe = (n, r) => {
      const i = t(n.trim().replace(/^[=v]+/, ""), r);
      return i ? i.version : null;
    }),
    oe
  );
}
var ce, ir;
function Yr() {
  if (ir) return ce;
  ir = 1;
  const t = G();
  return (
    (ce = (n, r, i, p, c) => {
      typeof i == "string" && ((c = p), (p = i), (i = void 0));
      try {
        return new t(n instanceof t ? n.version : n, i).inc(r, p, c).version;
      } catch {
        return null;
      }
    }),
    ce
  );
}
var ue, ar;
function Wr() {
  if (ar) return ue;
  ar = 1;
  const t = V();
  return (
    (ue = (n, r) => {
      const i = t(n, null, !0),
        p = t(r, null, !0),
        c = i.compare(p);
      if (c === 0) return null;
      const f = c > 0,
        s = f ? i : p,
        e = f ? p : i,
        a = !!s.prerelease.length;
      if (!!e.prerelease.length && !a)
        return !e.patch && !e.minor
          ? "major"
          : s.patch
            ? "patch"
            : s.minor
              ? "minor"
              : "major";
      const l = a ? "pre" : "";
      return i.major !== p.major
        ? l + "major"
        : i.minor !== p.minor
          ? l + "minor"
          : i.patch !== p.patch
            ? l + "patch"
            : "prerelease";
    }),
    ue
  );
}
var le, or;
function zr() {
  if (or) return le;
  or = 1;
  const t = G();
  return ((le = (n, r) => new t(n, r).major), le);
}
var fe, cr;
function Kr() {
  if (cr) return fe;
  cr = 1;
  const t = G();
  return ((fe = (n, r) => new t(n, r).minor), fe);
}
var he, ur;
function Zr() {
  if (ur) return he;
  ur = 1;
  const t = G();
  return ((he = (n, r) => new t(n, r).patch), he);
}
var Ee, lr;
function Jr() {
  if (lr) return Ee;
  lr = 1;
  const t = V();
  return (
    (Ee = (n, r) => {
      const i = t(n, r);
      return i && i.prerelease.length ? i.prerelease : null;
    }),
    Ee
  );
}
var pe, fr;
function F() {
  if (fr) return pe;
  fr = 1;
  const t = G();
  return ((pe = (n, r, i) => new t(n, i).compare(new t(r, i))), pe);
}
var Re, hr;
function Qr() {
  if (hr) return Re;
  hr = 1;
  const t = F();
  return ((Re = (n, r, i) => t(r, n, i)), Re);
}
var me, Er;
function et() {
  if (Er) return me;
  Er = 1;
  const t = F();
  return ((me = (n, r) => t(n, r, !0)), me);
}
var de, pr;
function ke() {
  if (pr) return de;
  pr = 1;
  const t = G();
  return (
    (de = (n, r, i) => {
      const p = new t(n, i),
        c = new t(r, i);
      return p.compare(c) || p.compareBuild(c);
    }),
    de
  );
}
var $e, Rr;
function rt() {
  if (Rr) return $e;
  Rr = 1;
  const t = ke();
  return (($e = (n, r) => n.sort((i, p) => t(i, p, r))), $e);
}
var Ie, mr;
function tt() {
  if (mr) return Ie;
  mr = 1;
  const t = ke();
  return ((Ie = (n, r) => n.sort((i, p) => t(p, i, r))), Ie);
}
var ve, dr;
function Y() {
  if (dr) return ve;
  dr = 1;
  const t = F();
  return ((ve = (n, r, i) => t(n, r, i) > 0), ve);
}
var Le, $r;
function Be() {
  if ($r) return Le;
  $r = 1;
  const t = F();
  return ((Le = (n, r, i) => t(n, r, i) < 0), Le);
}
var Ne, Ir;
function xr() {
  if (Ir) return Ne;
  Ir = 1;
  const t = F();
  return ((Ne = (n, r, i) => t(n, r, i) === 0), Ne);
}
var Oe, vr;
function Hr() {
  if (vr) return Oe;
  vr = 1;
  const t = F();
  return ((Oe = (n, r, i) => t(n, r, i) !== 0), Oe);
}
var Se, Lr;
function Ye() {
  if (Lr) return Se;
  Lr = 1;
  const t = F();
  return ((Se = (n, r, i) => t(n, r, i) >= 0), Se);
}
var Te, Nr;
function We() {
  if (Nr) return Te;
  Nr = 1;
  const t = F();
  return ((Te = (n, r, i) => t(n, r, i) <= 0), Te);
}
var Ae, Or;
function Mr() {
  if (Or) return Ae;
  Or = 1;
  const t = xr(),
    u = Hr(),
    n = Y(),
    r = Ye(),
    i = Be(),
    p = We();
  return (
    (Ae = (f, s, e, a) => {
      switch (s) {
        case "===":
          return (
            typeof f == "object" && (f = f.version),
            typeof e == "object" && (e = e.version),
            f === e
          );
        case "!==":
          return (
            typeof f == "object" && (f = f.version),
            typeof e == "object" && (e = e.version),
            f !== e
          );
        case "":
        case "=":
        case "==":
          return t(f, e, a);
        case "!=":
          return u(f, e, a);
        case ">":
          return n(f, e, a);
        case ">=":
          return r(f, e, a);
        case "<":
          return i(f, e, a);
        case "<=":
          return p(f, e, a);
        default:
          throw new TypeError(`Invalid operator: ${s}`);
      }
    }),
    Ae
  );
}
var ge, Sr;
function st() {
  if (Sr) return ge;
  Sr = 1;
  const t = G(),
    u = V(),
    { safeRe: n, t: r } = H();
  return (
    (ge = (p, c) => {
      if (p instanceof t) return p;
      if ((typeof p == "number" && (p = String(p)), typeof p != "string"))
        return null;
      c = c || {};
      let f = null;
      if (!c.rtl)
        f = p.match(c.includePrerelease ? n[r.COERCEFULL] : n[r.COERCE]);
      else {
        const m = c.includePrerelease ? n[r.COERCERTLFULL] : n[r.COERCERTL];
        let E;
        for (; (E = m.exec(p)) && (!f || f.index + f[0].length !== p.length);)
          ((!f || E.index + E[0].length !== f.index + f[0].length) && (f = E),
            (m.lastIndex = E.index + E[1].length + E[2].length));
        m.lastIndex = -1;
      }
      if (f === null) return null;
      const s = f[2],
        e = f[3] || "0",
        a = f[4] || "0",
        o = c.includePrerelease && f[5] ? `-${f[5]}` : "",
        l = c.includePrerelease && f[6] ? `+${f[6]}` : "";
      return u(`${s}.${e}.${a}${o}${l}`, c);
    }),
    ge
  );
}
var we, Tr;
function nt() {
  if (Tr) return we;
  Tr = 1;
  class t {
    constructor() {
      ((this.max = 1e3), (this.map = new Map()));
    }
    get(n) {
      const r = this.map.get(n);
      if (r !== void 0) return (this.map.delete(n), this.map.set(n, r), r);
    }
    delete(n) {
      return this.map.delete(n);
    }
    set(n, r) {
      if (!this.delete(n) && r !== void 0) {
        if (this.map.size >= this.max) {
          const p = this.map.keys().next().value;
          this.delete(p);
        }
        this.map.set(n, r);
      }
      return this;
    }
  }
  return ((we = t), we);
}
var qe, Ar;
function U() {
  if (Ar) return qe;
  Ar = 1;
  const t = /\s+/g;
  class u {
    constructor(h, I) {
      if (((I = i(I)), h instanceof u))
        return h.loose === !!I.loose &&
          h.includePrerelease === !!I.includePrerelease
          ? h
          : new u(h.raw, I);
      if (h instanceof p)
        return (
          (this.raw = h.value),
          (this.set = [[h]]),
          (this.formatted = void 0),
          this
        );
      if (
        ((this.options = I),
        (this.loose = !!I.loose),
        (this.includePrerelease = !!I.includePrerelease),
        (this.raw = h.trim().replace(t, " ")),
        (this.set = this.raw
          .split("||")
          .map((d) => this.parseRange(d.trim()))
          .filter((d) => d.length)),
        !this.set.length)
      )
        throw new TypeError(`Invalid SemVer Range: ${this.raw}`);
      if (this.set.length > 1) {
        const d = this.set[0];
        if (
          ((this.set = this.set.filter((v) => !T(v[0]))), this.set.length === 0)
        )
          this.set = [d];
        else if (this.set.length > 1) {
          for (const v of this.set)
            if (v.length === 1 && O(v[0])) {
              this.set = [v];
              break;
            }
        }
      }
      this.formatted = void 0;
    }
    get range() {
      if (this.formatted === void 0) {
        this.formatted = "";
        for (let h = 0; h < this.set.length; h++) {
          h > 0 && (this.formatted += "||");
          const I = this.set[h];
          for (let d = 0; d < I.length; d++)
            (d > 0 && (this.formatted += " "),
              (this.formatted += I[d].toString().trim()));
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
    parseRange(h) {
      const d =
          ((this.options.includePrerelease && m) | (this.options.loose && E)) +
          ":" +
          h,
        v = r.get(d);
      if (v) return v;
      const $ = this.options.loose,
        L = $ ? s[e.HYPHENRANGELOOSE] : s[e.HYPHENRANGE];
      ((h = h.replace(L, J(this.options.includePrerelease))),
        c("hyphen replace", h),
        (h = h.replace(s[e.COMPARATORTRIM], a)),
        c("comparator trim", h),
        (h = h.replace(s[e.TILDETRIM], o)),
        c("tilde trim", h),
        (h = h.replace(s[e.CARETTRIM], l)),
        c("caret trim", h));
      let g = h
        .split(" ")
        .map((P) => _(P, this.options))
        .join(" ")
        .split(/\s+/)
        .map((P) => Z(P, this.options));
      ($ &&
        (g = g.filter(
          (P) => (
            c("loose invalid filter", P, this.options),
            !!P.match(s[e.COMPARATORLOOSE])
          ),
        )),
        c("range list", g));
      const S = new Map(),
        q = g.map((P) => new p(P, this.options));
      for (const P of q) {
        if (T(P)) return [P];
        S.set(P.value, P);
      }
      S.size > 1 && S.has("") && S.delete("");
      const D = [...S.values()];
      return (r.set(d, D), D);
    }
    intersects(h, I) {
      if (!(h instanceof u)) throw new TypeError("a Range is required");
      return this.set.some(
        (d) =>
          w(d, I) &&
          h.set.some(
            (v) =>
              w(v, I) && d.every(($) => v.every((L) => $.intersects(L, I))),
          ),
      );
    }
    test(h) {
      if (!h) return !1;
      if (typeof h == "string")
        try {
          h = new f(h, this.options);
        } catch {
          return !1;
        }
      for (let I = 0; I < this.set.length; I++)
        if (Q(this.set[I], h, this.options)) return !0;
      return !1;
    }
  }
  qe = u;
  const n = nt(),
    r = new n(),
    i = Me(),
    p = W(),
    c = B(),
    f = G(),
    {
      safeRe: s,
      t: e,
      comparatorTrimReplace: a,
      tildeTrimReplace: o,
      caretTrimReplace: l,
    } = H(),
    { FLAG_INCLUDE_PRERELEASE: m, FLAG_LOOSE: E } = k(),
    T = (R) => R.value === "<0.0.0-0",
    O = (R) => R.value === "",
    w = (R, h) => {
      let I = !0;
      const d = R.slice();
      let v = d.pop();
      for (; I && d.length;)
        ((I = d.every(($) => v.intersects($, h))), (v = d.pop()));
      return I;
    },
    _ = (R, h) => (
      c("comp", R, h),
      (R = C(R, h)),
      c("caret", R),
      (R = X(R, h)),
      c("tildes", R),
      (R = N(R, h)),
      c("xrange", R),
      (R = K(R, h)),
      c("stars", R),
      R
    ),
    A = (R) => !R || R.toLowerCase() === "x" || R === "*",
    X = (R, h) =>
      R.trim()
        .split(/\s+/)
        .map((I) => j(I, h))
        .join(" "),
    j = (R, h) => {
      const I = h.loose ? s[e.TILDELOOSE] : s[e.TILDE];
      return R.replace(I, (d, v, $, L, g) => {
        c("tilde", R, d, v, $, L, g);
        let S;
        return (
          A(v)
            ? (S = "")
            : A($)
              ? (S = `>=${v}.0.0 <${+v + 1}.0.0-0`)
              : A(L)
                ? (S = `>=${v}.${$}.0 <${v}.${+$ + 1}.0-0`)
                : g
                  ? (c("replaceTilde pr", g),
                    (S = `>=${v}.${$}.${L}-${g} <${v}.${+$ + 1}.0-0`))
                  : (S = `>=${v}.${$}.${L} <${v}.${+$ + 1}.0-0`),
          c("tilde return", S),
          S
        );
      });
    },
    C = (R, h) =>
      R.trim()
        .split(/\s+/)
        .map((I) => y(I, h))
        .join(" "),
    y = (R, h) => {
      c("caret", R, h);
      const I = h.loose ? s[e.CARETLOOSE] : s[e.CARET],
        d = h.includePrerelease ? "-0" : "";
      return R.replace(I, (v, $, L, g, S) => {
        c("caret", R, v, $, L, g, S);
        let q;
        return (
          A($)
            ? (q = "")
            : A(L)
              ? (q = `>=${$}.0.0${d} <${+$ + 1}.0.0-0`)
              : A(g)
                ? $ === "0"
                  ? (q = `>=${$}.${L}.0${d} <${$}.${+L + 1}.0-0`)
                  : (q = `>=${$}.${L}.0${d} <${+$ + 1}.0.0-0`)
                : S
                  ? (c("replaceCaret pr", S),
                    $ === "0"
                      ? L === "0"
                        ? (q = `>=${$}.${L}.${g}-${S} <${$}.${L}.${+g + 1}-0`)
                        : (q = `>=${$}.${L}.${g}-${S} <${$}.${+L + 1}.0-0`)
                      : (q = `>=${$}.${L}.${g}-${S} <${+$ + 1}.0.0-0`))
                  : (c("no pr"),
                    $ === "0"
                      ? L === "0"
                        ? (q = `>=${$}.${L}.${g}${d} <${$}.${L}.${+g + 1}-0`)
                        : (q = `>=${$}.${L}.${g}${d} <${$}.${+L + 1}.0-0`)
                      : (q = `>=${$}.${L}.${g} <${+$ + 1}.0.0-0`)),
          c("caret return", q),
          q
        );
      });
    },
    N = (R, h) => (
      c("replaceXRanges", R, h),
      R.split(/\s+/)
        .map((I) => b(I, h))
        .join(" ")
    ),
    b = (R, h) => {
      R = R.trim();
      const I = h.loose ? s[e.XRANGELOOSE] : s[e.XRANGE];
      return R.replace(I, (d, v, $, L, g, S) => {
        c("xRange", R, d, v, $, L, g, S);
        const q = A($),
          D = q || A(L),
          P = D || A(g),
          x = P;
        return (
          v === "=" && x && (v = ""),
          (S = h.includePrerelease ? "-0" : ""),
          q
            ? v === ">" || v === "<"
              ? (d = "<0.0.0-0")
              : (d = "*")
            : v && x
              ? (D && (L = 0),
                (g = 0),
                v === ">"
                  ? ((v = ">="),
                    D
                      ? (($ = +$ + 1), (L = 0), (g = 0))
                      : ((L = +L + 1), (g = 0)))
                  : v === "<=" && ((v = "<"), D ? ($ = +$ + 1) : (L = +L + 1)),
                v === "<" && (S = "-0"),
                (d = `${v + $}.${L}.${g}${S}`))
              : D
                ? (d = `>=${$}.0.0${S} <${+$ + 1}.0.0-0`)
                : P && (d = `>=${$}.${L}.0${S} <${$}.${+L + 1}.0-0`),
          c("xRange return", d),
          d
        );
      });
    },
    K = (R, h) => (c("replaceStars", R, h), R.trim().replace(s[e.STAR], "")),
    Z = (R, h) => (
      c("replaceGTE0", R, h),
      R.trim().replace(s[h.includePrerelease ? e.GTE0PRE : e.GTE0], "")
    ),
    J = (R) => (h, I, d, v, $, L, g, S, q, D, P, x) => (
      A(d)
        ? (I = "")
        : A(v)
          ? (I = `>=${d}.0.0${R ? "-0" : ""}`)
          : A($)
            ? (I = `>=${d}.${v}.0${R ? "-0" : ""}`)
            : L
              ? (I = `>=${I}`)
              : (I = `>=${I}${R ? "-0" : ""}`),
      A(q)
        ? (S = "")
        : A(D)
          ? (S = `<${+q + 1}.0.0-0`)
          : A(P)
            ? (S = `<${q}.${+D + 1}.0-0`)
            : x
              ? (S = `<=${q}.${D}.${P}-${x}`)
              : R
                ? (S = `<${q}.${D}.${+P + 1}-0`)
                : (S = `<=${S}`),
      `${I} ${S}`.trim()
    ),
    Q = (R, h, I) => {
      for (let d = 0; d < R.length; d++) if (!R[d].test(h)) return !1;
      if (h.prerelease.length && !I.includePrerelease) {
        for (let d = 0; d < R.length; d++)
          if (
            (c(R[d].semver),
            R[d].semver !== p.ANY && R[d].semver.prerelease.length > 0)
          ) {
            const v = R[d].semver;
            if (
              v.major === h.major &&
              v.minor === h.minor &&
              v.patch === h.patch
            )
              return !0;
          }
        return !1;
      }
      return !0;
    };
  return qe;
}
var Ce, gr;
function W() {
  if (gr) return Ce;
  gr = 1;
  const t = Symbol("SemVer ANY");
  class u {
    static get ANY() {
      return t;
    }
    constructor(a, o) {
      if (((o = n(o)), a instanceof u)) {
        if (a.loose === !!o.loose) return a;
        a = a.value;
      }
      ((a = a.trim().split(/\s+/).join(" ")),
        c("comparator", a, o),
        (this.options = o),
        (this.loose = !!o.loose),
        this.parse(a),
        this.semver === t
          ? (this.value = "")
          : (this.value = this.operator + this.semver.version),
        c("comp", this));
    }
    parse(a) {
      const o = this.options.loose ? r[i.COMPARATORLOOSE] : r[i.COMPARATOR],
        l = a.match(o);
      if (!l) throw new TypeError(`Invalid comparator: ${a}`);
      ((this.operator = l[1] !== void 0 ? l[1] : ""),
        this.operator === "=" && (this.operator = ""),
        l[2]
          ? (this.semver = new f(l[2], this.options.loose))
          : (this.semver = t));
    }
    toString() {
      return this.value;
    }
    test(a) {
      if (
        (c("Comparator.test", a, this.options.loose),
        this.semver === t || a === t)
      )
        return !0;
      if (typeof a == "string")
        try {
          a = new f(a, this.options);
        } catch {
          return !1;
        }
      return p(a, this.operator, this.semver, this.options);
    }
    intersects(a, o) {
      if (!(a instanceof u)) throw new TypeError("a Comparator is required");
      return this.operator === ""
        ? this.value === ""
          ? !0
          : new s(a.value, o).test(this.value)
        : a.operator === ""
          ? a.value === ""
            ? !0
            : new s(this.value, o).test(a.semver)
          : ((o = n(o)),
            (o.includePrerelease &&
              (this.value === "<0.0.0-0" || a.value === "<0.0.0-0")) ||
            (!o.includePrerelease &&
              (this.value.startsWith("<0.0.0") || a.value.startsWith("<0.0.0")))
              ? !1
              : !!(
                  (this.operator.startsWith(">") &&
                    a.operator.startsWith(">")) ||
                  (this.operator.startsWith("<") &&
                    a.operator.startsWith("<")) ||
                  (this.semver.version === a.semver.version &&
                    this.operator.includes("=") &&
                    a.operator.includes("=")) ||
                  (p(this.semver, "<", a.semver, o) &&
                    this.operator.startsWith(">") &&
                    a.operator.startsWith("<")) ||
                  (p(this.semver, ">", a.semver, o) &&
                    this.operator.startsWith("<") &&
                    a.operator.startsWith(">"))
                ));
    }
  }
  Ce = u;
  const n = Me(),
    { safeRe: r, t: i } = H(),
    p = Mr(),
    c = B(),
    f = G(),
    s = U();
  return Ce;
}
var Pe, wr;
function z() {
  if (wr) return Pe;
  wr = 1;
  const t = U();
  return (
    (Pe = (n, r, i) => {
      try {
        r = new t(r, i);
      } catch {
        return !1;
      }
      return r.test(n);
    }),
    Pe
  );
}
var ye, qr;
function it() {
  if (qr) return ye;
  qr = 1;
  const t = U();
  return (
    (ye = (n, r) =>
      new t(n, r).set.map((i) =>
        i
          .map((p) => p.value)
          .join(" ")
          .trim()
          .split(" "),
      )),
    ye
  );
}
var De, Cr;
function at() {
  if (Cr) return De;
  Cr = 1;
  const t = G(),
    u = U();
  return (
    (De = (r, i, p) => {
      let c = null,
        f = null,
        s = null;
      try {
        s = new u(i, p);
      } catch {
        return null;
      }
      return (
        r.forEach((e) => {
          s.test(e) &&
            (!c || f.compare(e) === -1) &&
            ((c = e), (f = new t(c, p)));
        }),
        c
      );
    }),
    De
  );
}
var Ge, Pr;
function ot() {
  if (Pr) return Ge;
  Pr = 1;
  const t = G(),
    u = U();
  return (
    (Ge = (r, i, p) => {
      let c = null,
        f = null,
        s = null;
      try {
        s = new u(i, p);
      } catch {
        return null;
      }
      return (
        r.forEach((e) => {
          s.test(e) &&
            (!c || f.compare(e) === 1) &&
            ((c = e), (f = new t(c, p)));
        }),
        c
      );
    }),
    Ge
  );
}
var _e, yr;
function ct() {
  if (yr) return _e;
  yr = 1;
  const t = G(),
    u = U(),
    n = Y();
  return (
    (_e = (i, p) => {
      i = new u(i, p);
      let c = new t("0.0.0");
      if (i.test(c) || ((c = new t("0.0.0-0")), i.test(c))) return c;
      c = null;
      for (let f = 0; f < i.set.length; ++f) {
        const s = i.set[f];
        let e = null;
        (s.forEach((a) => {
          const o = new t(a.semver.version);
          switch (a.operator) {
            case ">":
              (o.prerelease.length === 0 ? o.patch++ : o.prerelease.push(0),
                (o.raw = o.format()));
            case "":
            case ">=":
              (!e || n(o, e)) && (e = o);
              break;
            case "<":
            case "<=":
              break;
            default:
              throw new Error(`Unexpected operation: ${a.operator}`);
          }
        }),
          e && (!c || n(c, e)) && (c = e));
      }
      return c && i.test(c) ? c : null;
    }),
    _e
  );
}
var je, Dr;
function ut() {
  if (Dr) return je;
  Dr = 1;
  const t = U();
  return (
    (je = (n, r) => {
      try {
        return new t(n, r).range || "*";
      } catch {
        return null;
      }
    }),
    je
  );
}
var Fe, Gr;
function ze() {
  if (Gr) return Fe;
  Gr = 1;
  const t = G(),
    u = W(),
    { ANY: n } = u,
    r = U(),
    i = z(),
    p = Y(),
    c = Be(),
    f = We(),
    s = Ye();
  return (
    (Fe = (a, o, l, m) => {
      ((a = new t(a, m)), (o = new r(o, m)));
      let E, T, O, w, _;
      switch (l) {
        case ">":
          ((E = p), (T = f), (O = c), (w = ">"), (_ = ">="));
          break;
        case "<":
          ((E = c), (T = s), (O = p), (w = "<"), (_ = "<="));
          break;
        default:
          throw new TypeError('Must provide a hilo val of "<" or ">"');
      }
      if (i(a, o, m)) return !1;
      for (let A = 0; A < o.set.length; ++A) {
        const X = o.set[A];
        let j = null,
          C = null;
        if (
          (X.forEach((y) => {
            (y.semver === n && (y = new u(">=0.0.0")),
              (j = j || y),
              (C = C || y),
              E(y.semver, j.semver, m)
                ? (j = y)
                : O(y.semver, C.semver, m) && (C = y));
          }),
          j.operator === w ||
            j.operator === _ ||
            ((!C.operator || C.operator === w) && T(a, C.semver)))
        )
          return !1;
        if (C.operator === _ && O(a, C.semver)) return !1;
      }
      return !0;
    }),
    Fe
  );
}
var Ue, _r;
function lt() {
  if (_r) return Ue;
  _r = 1;
  const t = ze();
  return ((Ue = (n, r, i) => t(n, r, ">", i)), Ue);
}
var Xe, jr;
function ft() {
  if (jr) return Xe;
  jr = 1;
  const t = ze();
  return ((Xe = (n, r, i) => t(n, r, "<", i)), Xe);
}
var Ve, Fr;
function ht() {
  if (Fr) return Ve;
  Fr = 1;
  const t = U();
  return (
    (Ve = (n, r, i) => (
      (n = new t(n, i)),
      (r = new t(r, i)),
      n.intersects(r, i)
    )),
    Ve
  );
}
var be, Ur;
function Et() {
  if (Ur) return be;
  Ur = 1;
  const t = z(),
    u = F();
  return (
    (be = (n, r, i) => {
      const p = [];
      let c = null,
        f = null;
      const s = n.sort((l, m) => u(l, m, i));
      for (const l of s)
        t(l, r, i)
          ? ((f = l), c || (c = l))
          : (f && p.push([c, f]), (f = null), (c = null));
      c && p.push([c, null]);
      const e = [];
      for (const [l, m] of p)
        l === m
          ? e.push(l)
          : !m && l === s[0]
            ? e.push("*")
            : m
              ? l === s[0]
                ? e.push(`<=${m}`)
                : e.push(`${l} - ${m}`)
              : e.push(`>=${l}`);
      const a = e.join(" || "),
        o = typeof r.raw == "string" ? r.raw : String(r);
      return a.length < o.length ? a : r;
    }),
    be
  );
}
var xe, Xr;
function pt() {
  if (Xr) return xe;
  Xr = 1;
  const t = U(),
    u = W(),
    { ANY: n } = u,
    r = z(),
    i = F(),
    p = (o, l, m = {}) => {
      if (o === l) return !0;
      ((o = new t(o, m)), (l = new t(l, m)));
      let E = !1;
      e: for (const T of o.set) {
        for (const O of l.set) {
          const w = s(T, O, m);
          if (((E = E || w !== null), w)) continue e;
        }
        if (E) return !1;
      }
      return !0;
    },
    c = [new u(">=0.0.0-0")],
    f = [new u(">=0.0.0")],
    s = (o, l, m) => {
      if (o === l) return !0;
      if (o.length === 1 && o[0].semver === n) {
        if (l.length === 1 && l[0].semver === n) return !0;
        m.includePrerelease ? (o = c) : (o = f);
      }
      if (l.length === 1 && l[0].semver === n) {
        if (m.includePrerelease) return !0;
        l = f;
      }
      const E = new Set();
      let T, O;
      for (const N of o)
        N.operator === ">" || N.operator === ">="
          ? (T = e(T, N, m))
          : N.operator === "<" || N.operator === "<="
            ? (O = a(O, N, m))
            : E.add(N.semver);
      if (E.size > 1) return null;
      let w;
      if (T && O) {
        if (((w = i(T.semver, O.semver, m)), w > 0)) return null;
        if (w === 0 && (T.operator !== ">=" || O.operator !== "<="))
          return null;
      }
      for (const N of E) {
        if ((T && !r(N, String(T), m)) || (O && !r(N, String(O), m)))
          return null;
        for (const b of l) if (!r(N, String(b), m)) return !1;
        return !0;
      }
      let _,
        A,
        X,
        j,
        C =
          O && !m.includePrerelease && O.semver.prerelease.length
            ? O.semver
            : !1,
        y =
          T && !m.includePrerelease && T.semver.prerelease.length
            ? T.semver
            : !1;
      C &&
        C.prerelease.length === 1 &&
        O.operator === "<" &&
        C.prerelease[0] === 0 &&
        (C = !1);
      for (const N of l) {
        if (
          ((j = j || N.operator === ">" || N.operator === ">="),
          (X = X || N.operator === "<" || N.operator === "<="),
          T)
        ) {
          if (
            (y &&
              N.semver.prerelease &&
              N.semver.prerelease.length &&
              N.semver.major === y.major &&
              N.semver.minor === y.minor &&
              N.semver.patch === y.patch &&
              (y = !1),
            N.operator === ">" || N.operator === ">=")
          ) {
            if (((_ = e(T, N, m)), _ === N && _ !== T)) return !1;
          } else if (T.operator === ">=" && !r(T.semver, String(N), m))
            return !1;
        }
        if (O) {
          if (
            (C &&
              N.semver.prerelease &&
              N.semver.prerelease.length &&
              N.semver.major === C.major &&
              N.semver.minor === C.minor &&
              N.semver.patch === C.patch &&
              (C = !1),
            N.operator === "<" || N.operator === "<=")
          ) {
            if (((A = a(O, N, m)), A === N && A !== O)) return !1;
          } else if (O.operator === "<=" && !r(O.semver, String(N), m))
            return !1;
        }
        if (!N.operator && (O || T) && w !== 0) return !1;
      }
      return !(
        (T && X && !O && w !== 0) ||
        (O && j && !T && w !== 0) ||
        y ||
        C
      );
    },
    e = (o, l, m) => {
      if (!o) return l;
      const E = i(o.semver, l.semver, m);
      return E > 0
        ? o
        : E < 0 || (l.operator === ">" && o.operator === ">=")
          ? l
          : o;
    },
    a = (o, l, m) => {
      if (!o) return l;
      const E = i(o.semver, l.semver, m);
      return E < 0
        ? o
        : E > 0 || (l.operator === "<" && o.operator === "<=")
          ? l
          : o;
    };
  return ((xe = p), xe);
}
var He, Vr;
function Rt() {
  if (Vr) return He;
  Vr = 1;
  const t = H(),
    u = k(),
    n = G(),
    r = br(),
    i = V(),
    p = kr(),
    c = Br(),
    f = Yr(),
    s = Wr(),
    e = zr(),
    a = Kr(),
    o = Zr(),
    l = Jr(),
    m = F(),
    E = Qr(),
    T = et(),
    O = ke(),
    w = rt(),
    _ = tt(),
    A = Y(),
    X = Be(),
    j = xr(),
    C = Hr(),
    y = Ye(),
    N = We(),
    b = Mr(),
    K = st(),
    Z = W(),
    J = U(),
    Q = z(),
    R = it(),
    h = at(),
    I = ot(),
    d = ct(),
    v = ut(),
    $ = ze(),
    L = lt(),
    g = ft(),
    S = ht(),
    q = Et(),
    D = pt();
  return (
    (He = {
      parse: i,
      valid: p,
      clean: c,
      inc: f,
      diff: s,
      major: e,
      minor: a,
      patch: o,
      prerelease: l,
      compare: m,
      rcompare: E,
      compareLoose: T,
      compareBuild: O,
      sort: w,
      rsort: _,
      gt: A,
      lt: X,
      eq: j,
      neq: C,
      gte: y,
      lte: N,
      cmp: b,
      coerce: K,
      Comparator: Z,
      Range: J,
      satisfies: Q,
      toComparators: R,
      maxSatisfying: h,
      minSatisfying: I,
      minVersion: d,
      validRange: v,
      outside: $,
      gtr: L,
      ltr: g,
      intersects: S,
      simplifyRange: q,
      subset: D,
      SemVer: n,
      re: t.re,
      src: t.src,
      tokens: t.t,
      SEMVER_SPEC_VERSION: u.SEMVER_SPEC_VERSION,
      RELEASE_TYPES: u.RELEASE_TYPES,
      compareIdentifiers: r.compareIdentifiers,
      rcompareIdentifiers: r.rcompareIdentifiers,
    }),
    He
  );
}
export { Rt as r };
//# sourceMappingURL=index-BiHJsdYm.mjs.map
