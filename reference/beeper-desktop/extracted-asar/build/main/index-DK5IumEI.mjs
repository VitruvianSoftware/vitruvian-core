import { a as $ } from "./_commonjsHelpers-CBUqixCJ.mjs";
import E from "path";
import I from "fs";
import _ from "util";
import { b as w } from "./register-proxy-7lV9pun2.mjs";
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
    var c = new e.Error().stack;
    c &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[c] = "96d87833-28eb-4802-b558-ea1f6581ed14"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-96d87833-28eb-4802-b558-ea1f6581ed14"));
  } catch {}
})();
function T(e, c) {
  for (var d = 0; d < c.length; d++) {
    const o = c[d];
    if (typeof o != "string" && !Array.isArray(o)) {
      for (const u in o)
        if (u !== "default" && !(u in e)) {
          const p = Object.getOwnPropertyDescriptor(o, u);
          p &&
            Object.defineProperty(
              e,
              u,
              p.get ? p : { enumerable: !0, get: () => o[u] },
            );
        }
    }
  }
  return Object.freeze(
    Object.defineProperty(e, Symbol.toStringTag, { value: "Module" }),
  );
}
var f = { exports: {} },
  m = { exports: {} },
  g;
function P() {
  if (g) return m.exports;
  g = 1;
  const e = I,
    { promisify: c } = _,
    d = c(e.access);
  return (
    (m.exports = async (o) => {
      try {
        return (await d(o), !0);
      } catch {
        return !1;
      }
    }),
    (m.exports.sync = (o) => {
      try {
        return (e.accessSync(o), !0);
      } catch {
        return !1;
      }
    }),
    m.exports
  );
}
var h;
function S() {
  if (h) return f.exports;
  h = 1;
  const e = E,
    c = P(),
    d = w();
  class o extends Error {
    constructor(n, s) {
      (super("Max tries reached."),
        (this.originalPath = n),
        (this.lastTriedPath = s));
    }
  }
  const u = (r, n) => {
      const s = r.match(/^(?<filename>.*)\((?<index>\d+)\)$/);
      let { filename: a, index: i } = s ? s.groups : { filename: r, index: 0 };
      return ((a = a.trim()), [`${a}${n}`, `${a} (${++i})${n}`]);
    },
    p = (r) => {
      const n = d(r);
      return (s, a) => {
        const i = new RegExp(`^(?<filename>.*)${n}(?<index>\\d+)$`).exec(s);
        let { filename: t, index: b } = i
          ? i.groups
          : { filename: s, index: 0 };
        return [`${t}${a}`, `${t.trim()}${r}${++b}${a}`];
      };
    },
    l = (r, n) => {
      const s = e.extname(r),
        a = e.dirname(r),
        [i, t] = n(e.basename(r, s), s);
      return [e.join(a, i), e.join(a, t)];
    },
    x = async (
      r,
      { incrementer: n = u, maxTries: s = Number.POSITIVE_INFINITY } = {},
    ) => {
      let a = 0,
        [i] = l(r, n),
        t = r;
      for (;;) {
        if (!(await c(t))) return t;
        if (++a > s) throw new o(i, t);
        [i, t] = l(t, n);
      }
    };
  return (
    (f.exports = x),
    (f.exports.default = x),
    (f.exports.sync = (
      r,
      { incrementer: n = u, maxTries: s = Number.POSITIVE_INFINITY } = {},
    ) => {
      let a = 0,
        [i] = l(r, n),
        t = r;
      for (;;) {
        if (!c.sync(t)) return t;
        if (++a > s) throw new o(i, t);
        [i, t] = l(t, n);
      }
    }),
    (f.exports.MaxTryError = o),
    (f.exports.separatorIncrementer = p),
    f.exports
  );
}
var y = S();
const v = $(y),
  q = T({ __proto__: null, default: v }, [y]);
export { q as i };
//# sourceMappingURL=index-DK5IumEI.mjs.map
