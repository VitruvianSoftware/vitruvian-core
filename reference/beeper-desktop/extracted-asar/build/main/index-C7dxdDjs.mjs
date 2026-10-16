import { a as K } from "./_commonjsHelpers-CBUqixCJ.mjs";
(function () {
  try {
    var p =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    p.SENTRY_RELEASE = { id: "4.3.209" };
    var v = new p.Error().stack;
    v &&
      ((p._sentryDebugIds = p._sentryDebugIds || {}),
      (p._sentryDebugIds[v] = "eff050e8-1328-45e9-a5fc-5ca715231b41"),
      (p._sentryDebugIdIdentifier =
        "sentry-dbid-eff050e8-1328-45e9-a5fc-5ca715231b41"));
  } catch {}
})();
var A, Z;
function Q() {
  if (Z) return A;
  ((Z = 1), (A = p));
  function p(i, f, r) {
    (i instanceof RegExp && (i = v(i, r)),
      f instanceof RegExp && (f = v(f, r)));
    var a = x(i, f, r);
    return (
      a && {
        start: a[0],
        end: a[1],
        pre: r.slice(0, a[0]),
        body: r.slice(a[0] + i.length, a[1]),
        post: r.slice(a[1] + f.length),
      }
    );
  }
  function v(i, f) {
    var r = f.match(i);
    return r ? r[0] : null;
  }
  p.range = x;
  function x(i, f, r) {
    var a,
      j,
      E,
      O,
      M,
      s = r.indexOf(i),
      u = r.indexOf(f, s + 1),
      h = s;
    if (s >= 0 && u > 0) {
      if (i === f) return [s, u];
      for (a = [], E = r.length; h >= 0 && !M;)
        (h == s
          ? (a.push(h), (s = r.indexOf(i, h + 1)))
          : a.length == 1
            ? (M = [a.pop(), u])
            : ((j = a.pop()),
              j < E && ((E = j), (O = u)),
              (u = r.indexOf(f, h + 1))),
          (h = s < u && s >= 0 ? s : u));
      a.length && (M = [E, O]);
    }
    return M;
  }
  return A;
}
var B, z;
function U() {
  if (z) return B;
  z = 1;
  var p = Q();
  B = M;
  var v = "\0SLASH" + Math.random() + "\0",
    x = "\0OPEN" + Math.random() + "\0",
    i = "\0CLOSE" + Math.random() + "\0",
    f = "\0COMMA" + Math.random() + "\0",
    r = "\0PERIOD" + Math.random() + "\0";
  function a(e) {
    return parseInt(e, 10) == e ? parseInt(e, 10) : e.charCodeAt(0);
  }
  function j(e) {
    return e
      .split("\\\\")
      .join(v)
      .split("\\{")
      .join(x)
      .split("\\}")
      .join(i)
      .split("\\,")
      .join(f)
      .split("\\.")
      .join(r);
  }
  function E(e) {
    return e
      .split(v)
      .join("\\")
      .split(x)
      .join("{")
      .split(i)
      .join("}")
      .split(f)
      .join(",")
      .split(r)
      .join(".");
  }
  function O(e) {
    if (!e) return [""];
    var d = [],
      c = p("{", "}", e);
    if (!c) return e.split(",");
    var n = c.pre,
      w = c.body,
      g = c.post,
      o = n.split(",");
    o[o.length - 1] += "{" + w + "}";
    var b = O(g);
    return (
      g.length && ((o[o.length - 1] += b.shift()), o.push.apply(o, b)),
      d.push.apply(d, o),
      d
    );
  }
  function M(e) {
    return e
      ? (e.substr(0, 2) === "{}" && (e = "\\{\\}" + e.substr(2)),
        C(j(e), !0).map(E))
      : [];
  }
  function s(e) {
    return "{" + e + "}";
  }
  function u(e) {
    return /^-?0\d/.test(e);
  }
  function h(e, d) {
    return e <= d;
  }
  function F(e, d) {
    return e >= d;
  }
  function C(e, d) {
    var c = [],
      n = p("{", "}", e);
    if (!n) return [e];
    var w = n.pre,
      g = n.post.length ? C(n.post, !1) : [""];
    if (/\$$/.test(n.pre))
      for (var o = 0; o < g.length; o++) {
        var b = w + "{" + n.body + "}" + g[o];
        c.push(b);
      }
    else {
      var H = /^-?\d+\.\.-?\d+(?:\.\.-?\d+)?$/.test(n.body),
        D = /^[a-zA-Z]\.\.[a-zA-Z](?:\.\.-?\d+)?$/.test(n.body),
        R = H || D,
        Y = n.body.indexOf(",") >= 0;
      if (!R && !Y)
        return n.post.match(/,.*\}/)
          ? ((e = n.pre + "{" + n.body + i + n.post), C(e))
          : [e];
      var t;
      if (R) t = n.body.split(/\.\./);
      else if (
        ((t = O(n.body)),
        t.length === 1 && ((t = C(t[0], !1).map(s)), t.length === 1))
      )
        return g.map(function (J) {
          return n.pre + t[0] + J;
        });
      var m;
      if (R) {
        var P = a(t[0]),
          _ = a(t[1]),
          k = Math.max(t[0].length, t[1].length),
          S = t.length == 3 ? Math.abs(a(t[2])) : 1,
          T = h,
          q = _ < P;
        q && ((S *= -1), (T = F));
        var G = t.some(u);
        m = [];
        for (var I = P; T(I, _); I += S) {
          var l;
          if (D) ((l = String.fromCharCode(I)), l === "\\" && (l = ""));
          else if (((l = String(I)), G)) {
            var $ = k - l.length;
            if ($ > 0) {
              var L = new Array($ + 1).join("0");
              I < 0 ? (l = "-" + L + l.slice(1)) : (l = L + l);
            }
          }
          m.push(l);
        }
      } else {
        m = [];
        for (var y = 0; y < t.length; y++) m.push.apply(m, C(t[y], !1));
      }
      for (var y = 0; y < m.length; y++)
        for (var o = 0; o < g.length; o++) {
          var b = w + m[y] + g[o];
          (!d || R || b) && c.push(b);
        }
    }
    return c;
  }
  return B;
}
var V = U();
const X = K(V);
export { X as e };
//# sourceMappingURL=index-C7dxdDjs.mjs.map
