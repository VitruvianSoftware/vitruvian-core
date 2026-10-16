import { g as vt, c as D } from "./_commonjsHelpers-CBUqixCJ.mjs";
import Mt from "domain";
import ht from "http";
import bt from "https";
import { r as jt } from "./index-BiHJsdYm.mjs";
import mt from "net";
import Ct from "tls";
import _t from "url";
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
    var r = new e.Error().stack;
    r &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[r] = "c7f1deff-5827-47bc-ab77-3a5ece8633e9"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-c7f1deff-5827-47bc-ab77-3a5ece8633e9"));
  } catch {}
})();
var me = {},
  _e = {},
  z = {},
  X = {},
  B = {},
  Pe = {},
  Y = {},
  cr;
function Ut() {
  if (cr) return Y;
  ((cr = 1),
    Object.defineProperty(Y, "__esModule", { value: !0 }),
    (Y.boolean = void 0));
  const e = function (r) {
    switch (Object.prototype.toString.call(r)) {
      case "[object String]":
        return ["true", "t", "yes", "y", "on", "1"].includes(
          r.trim().toLowerCase(),
        );
      case "[object Number]":
        return r.valueOf() === 1;
      case "[object Boolean]":
        return r.valueOf();
      default:
        return !1;
    }
  };
  return ((Y.boolean = e), Y);
}
var W = {},
  fr;
function Gt() {
  if (fr) return W;
  ((fr = 1),
    Object.defineProperty(W, "__esModule", { value: !0 }),
    (W.isBooleanable = void 0));
  const e = function (r) {
    switch (Object.prototype.toString.call(r)) {
      case "[object String]":
        return [
          "true",
          "t",
          "yes",
          "y",
          "on",
          "1",
          "false",
          "f",
          "no",
          "n",
          "off",
          "0",
        ].includes(r.trim().toLowerCase());
      case "[object Number]":
        return [0, 1].includes(r.valueOf());
      case "[object Boolean]":
        return !0;
      default:
        return !1;
    }
  };
  return ((W.isBooleanable = e), W);
}
var pr;
function nr() {
  return (
    pr ||
      ((pr = 1),
      (function (e) {
        (Object.defineProperty(e, "__esModule", { value: !0 }),
          (e.isBooleanable = e.boolean = void 0));
        const r = Ut();
        Object.defineProperty(e, "boolean", {
          enumerable: !0,
          get: function () {
            return r.boolean;
          },
        });
        const s = Gt();
        Object.defineProperty(e, "isBooleanable", {
          enumerable: !0,
          get: function () {
            return s.isBooleanable;
          },
        });
      })(Pe)),
    Pe
  );
}
const Dt =
    Object.prototype.toString.call(typeof process < "u" ? process : 0) ===
    "[object process]",
  Lt = Object.freeze(
    Object.defineProperty(
      { __proto__: null, default: Dt },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  ),
  or = vt(Lt);
var Oe, yr;
function Pt() {
  if (yr) return Oe;
  yr = 1;
  var e = Object.prototype.toString;
  return (
    (Oe = function (s) {
      var l = e.call(s),
        u = l === "[object Arguments]";
      return (
        u ||
          (u =
            l !== "[object Array]" &&
            s !== null &&
            typeof s == "object" &&
            typeof s.length == "number" &&
            s.length >= 0 &&
            e.call(s.callee) === "[object Function]"),
        u
      );
    }),
    Oe
  );
}
var Ae, dr;
function kt() {
  if (dr) return Ae;
  dr = 1;
  var e;
  if (!Object.keys) {
    var r = Object.prototype.hasOwnProperty,
      s = Object.prototype.toString,
      l = Pt(),
      u = Object.prototype.propertyIsEnumerable,
      n = !u.call({ toString: null }, "toString"),
      i = u.call(function () {}, "prototype"),
      f = [
        "toString",
        "toLocaleString",
        "valueOf",
        "hasOwnProperty",
        "isPrototypeOf",
        "propertyIsEnumerable",
        "constructor",
      ],
      c = function (d) {
        var p = d.constructor;
        return p && p.prototype === d;
      },
      a = {
        $applicationCache: !0,
        $console: !0,
        $external: !0,
        $frame: !0,
        $frameElement: !0,
        $frames: !0,
        $innerHeight: !0,
        $innerWidth: !0,
        $onmozfullscreenchange: !0,
        $onmozfullscreenerror: !0,
        $outerHeight: !0,
        $outerWidth: !0,
        $pageXOffset: !0,
        $pageYOffset: !0,
        $parent: !0,
        $scrollLeft: !0,
        $scrollTop: !0,
        $scrollX: !0,
        $scrollY: !0,
        $self: !0,
        $webkitIndexedDB: !0,
        $webkitStorageInfo: !0,
        $window: !0,
      },
      o = (function () {
        if (typeof window > "u") return !1;
        for (var d in window)
          try {
            if (
              !a["$" + d] &&
              r.call(window, d) &&
              window[d] !== null &&
              typeof window[d] == "object"
            )
              try {
                c(window[d]);
              } catch {
                return !0;
              }
          } catch {
            return !0;
          }
        return !1;
      })(),
      t = function (d) {
        if (typeof window > "u" || !o) return c(d);
        try {
          return c(d);
        } catch {
          return !1;
        }
      };
    e = function (p) {
      var b = p !== null && typeof p == "object",
        y = s.call(p) === "[object Function]",
        g = l(p),
        v = b && s.call(p) === "[object String]",
        h = [];
      if (!b && !y && !g)
        throw new TypeError("Object.keys called on a non-object");
      var m = i && y;
      if (v && p.length > 0 && !r.call(p, 0))
        for (var _ = 0; _ < p.length; ++_) h.push(String(_));
      if (g && p.length > 0)
        for (var P = 0; P < p.length; ++P) h.push(String(P));
      else
        for (var O in p)
          !(m && O === "prototype") && r.call(p, O) && h.push(String(O));
      if (n)
        for (var w = t(p), S = 0; S < f.length; ++S)
          !(w && f[S] === "constructor") && r.call(p, f[S]) && h.push(f[S]);
      return h;
    };
  }
  return ((Ae = e), Ae);
}
var Re, gr;
function Bt() {
  if (gr) return Re;
  gr = 1;
  var e = Array.prototype.slice,
    r = Pt(),
    s = Object.keys,
    l = s
      ? function (i) {
          return s(i);
        }
      : kt(),
    u = Object.keys;
  return (
    (l.shim = function () {
      if (Object.keys) {
        var i = (function () {
          var f = Object.keys(arguments);
          return f && f.length === arguments.length;
        })(1, 2);
        i ||
          (Object.keys = function (c) {
            return r(c) ? u(e.call(c)) : u(c);
          });
      } else Object.keys = l;
      return Object.keys || l;
    }),
    (Re = l),
    Re
  );
}
var Se, vr;
function Ft() {
  return (vr || ((vr = 1), (Se = Error)), Se);
}
var we, hr;
function Ht() {
  return (hr || ((hr = 1), (we = EvalError)), we);
}
var Ee, br;
function zt() {
  return (br || ((br = 1), (Ee = RangeError)), Ee);
}
var xe, mr;
function Xt() {
  return (mr || ((mr = 1), (xe = ReferenceError)), xe);
}
var qe, _r;
function Ot() {
  return (_r || ((_r = 1), (qe = SyntaxError)), qe);
}
var Te, Pr;
function At() {
  return (Pr || ((Pr = 1), (Te = TypeError)), Te);
}
var Ne, Or;
function Yt() {
  return (Or || ((Or = 1), (Ne = URIError)), Ne);
}
var $e, Ar;
function Wt() {
  return (
    Ar ||
      ((Ar = 1),
      ($e = function () {
        if (
          typeof Symbol != "function" ||
          typeof Object.getOwnPropertySymbols != "function"
        )
          return !1;
        if (typeof Symbol.iterator == "symbol") return !0;
        var r = {},
          s = Symbol("test"),
          l = Object(s);
        if (
          typeof s == "string" ||
          Object.prototype.toString.call(s) !== "[object Symbol]" ||
          Object.prototype.toString.call(l) !== "[object Symbol]"
        )
          return !1;
        var u = 42;
        r[s] = u;
        for (s in r) return !1;
        if (
          (typeof Object.keys == "function" && Object.keys(r).length !== 0) ||
          (typeof Object.getOwnPropertyNames == "function" &&
            Object.getOwnPropertyNames(r).length !== 0)
        )
          return !1;
        var n = Object.getOwnPropertySymbols(r);
        if (
          n.length !== 1 ||
          n[0] !== s ||
          !Object.prototype.propertyIsEnumerable.call(r, s)
        )
          return !1;
        if (typeof Object.getOwnPropertyDescriptor == "function") {
          var i = Object.getOwnPropertyDescriptor(r, s);
          if (i.value !== u || i.enumerable !== !0) return !1;
        }
        return !0;
      })),
    $e
  );
}
var Ie, Rr;
function Vt() {
  if (Rr) return Ie;
  Rr = 1;
  var e = typeof Symbol < "u" && Symbol,
    r = Wt();
  return (
    (Ie = function () {
      return typeof e != "function" ||
        typeof Symbol != "function" ||
        typeof e("foo") != "symbol" ||
        typeof Symbol("bar") != "symbol"
        ? !1
        : r();
    }),
    Ie
  );
}
var Me, Sr;
function Jt() {
  if (Sr) return Me;
  Sr = 1;
  var e = { __proto__: null, foo: {} },
    r = Object;
  return (
    (Me = function () {
      return { __proto__: e }.foo === e.foo && !(e instanceof r);
    }),
    Me
  );
}
var je, wr;
function Kt() {
  if (wr) return je;
  wr = 1;
  var e = "Function.prototype.bind called on incompatible ",
    r = Object.prototype.toString,
    s = Math.max,
    l = "[object Function]",
    u = function (c, a) {
      for (var o = [], t = 0; t < c.length; t += 1) o[t] = c[t];
      for (var d = 0; d < a.length; d += 1) o[d + c.length] = a[d];
      return o;
    },
    n = function (c, a) {
      for (var o = [], t = a, d = 0; t < c.length; t += 1, d += 1) o[d] = c[t];
      return o;
    },
    i = function (f, c) {
      for (var a = "", o = 0; o < f.length; o += 1)
        ((a += f[o]), o + 1 < f.length && (a += c));
      return a;
    };
  return (
    (je = function (c) {
      var a = this;
      if (typeof a != "function" || r.apply(a) !== l)
        throw new TypeError(e + a);
      for (
        var o = n(arguments, 1),
          t,
          d = function () {
            if (this instanceof t) {
              var v = a.apply(this, u(o, arguments));
              return Object(v) === v ? v : this;
            }
            return a.apply(c, u(o, arguments));
          },
          p = s(0, a.length - o.length),
          b = [],
          y = 0;
        y < p;
        y++
      )
        b[y] = "$" + y;
      if (
        ((t = Function(
          "binder",
          "return function (" +
            i(b, ",") +
            "){ return binder.apply(this,arguments); }",
        )(d)),
        a.prototype)
      ) {
        var g = function () {};
        ((g.prototype = a.prototype),
          (t.prototype = new g()),
          (g.prototype = null));
      }
      return t;
    }),
    je
  );
}
var Ce, Er;
function Rt() {
  if (Er) return Ce;
  Er = 1;
  var e = Kt();
  return ((Ce = Function.prototype.bind || e), Ce);
}
var Ue, xr;
function Zt() {
  if (xr) return Ue;
  xr = 1;
  var e = Function.prototype.call,
    r = Object.prototype.hasOwnProperty,
    s = Rt();
  return ((Ue = s.call(e, r)), Ue);
}
var Ge, qr;
function ar() {
  if (qr) return Ge;
  qr = 1;
  var e,
    r = Ft(),
    s = Ht(),
    l = zt(),
    u = Xt(),
    n = Ot(),
    i = At(),
    f = Yt(),
    c = Function,
    a = function (q) {
      try {
        return c('"use strict"; return (' + q + ").constructor;")();
      } catch {}
    },
    o = Object.getOwnPropertyDescriptor;
  if (o)
    try {
      o({}, "");
    } catch {
      o = null;
    }
  var t = function () {
      throw new i();
    },
    d = o
      ? (function () {
          try {
            return (arguments.callee, t);
          } catch {
            try {
              return o(arguments, "callee").get;
            } catch {
              return t;
            }
          }
        })()
      : t,
    p = Vt()(),
    b = Jt()(),
    y =
      Object.getPrototypeOf ||
      (b
        ? function (q) {
            return q.__proto__;
          }
        : null),
    g = {},
    v = typeof Uint8Array > "u" || !y ? e : y(Uint8Array),
    h = {
      __proto__: null,
      "%AggregateError%": typeof AggregateError > "u" ? e : AggregateError,
      "%Array%": Array,
      "%ArrayBuffer%": typeof ArrayBuffer > "u" ? e : ArrayBuffer,
      "%ArrayIteratorPrototype%": p && y ? y([][Symbol.iterator]()) : e,
      "%AsyncFromSyncIteratorPrototype%": e,
      "%AsyncFunction%": g,
      "%AsyncGenerator%": g,
      "%AsyncGeneratorFunction%": g,
      "%AsyncIteratorPrototype%": g,
      "%Atomics%": typeof Atomics > "u" ? e : Atomics,
      "%BigInt%": typeof BigInt > "u" ? e : BigInt,
      "%BigInt64Array%": typeof BigInt64Array > "u" ? e : BigInt64Array,
      "%BigUint64Array%": typeof BigUint64Array > "u" ? e : BigUint64Array,
      "%Boolean%": Boolean,
      "%DataView%": typeof DataView > "u" ? e : DataView,
      "%Date%": Date,
      "%decodeURI%": decodeURI,
      "%decodeURIComponent%": decodeURIComponent,
      "%encodeURI%": encodeURI,
      "%encodeURIComponent%": encodeURIComponent,
      "%Error%": r,
      "%eval%": eval,
      "%EvalError%": s,
      "%Float32Array%": typeof Float32Array > "u" ? e : Float32Array,
      "%Float64Array%": typeof Float64Array > "u" ? e : Float64Array,
      "%FinalizationRegistry%":
        typeof FinalizationRegistry > "u" ? e : FinalizationRegistry,
      "%Function%": c,
      "%GeneratorFunction%": g,
      "%Int8Array%": typeof Int8Array > "u" ? e : Int8Array,
      "%Int16Array%": typeof Int16Array > "u" ? e : Int16Array,
      "%Int32Array%": typeof Int32Array > "u" ? e : Int32Array,
      "%isFinite%": isFinite,
      "%isNaN%": isNaN,
      "%IteratorPrototype%": p && y ? y(y([][Symbol.iterator]())) : e,
      "%JSON%": typeof JSON == "object" ? JSON : e,
      "%Map%": typeof Map > "u" ? e : Map,
      "%MapIteratorPrototype%":
        typeof Map > "u" || !p || !y ? e : y(new Map()[Symbol.iterator]()),
      "%Math%": Math,
      "%Number%": Number,
      "%Object%": Object,
      "%parseFloat%": parseFloat,
      "%parseInt%": parseInt,
      "%Promise%": typeof Promise > "u" ? e : Promise,
      "%Proxy%": typeof Proxy > "u" ? e : Proxy,
      "%RangeError%": l,
      "%ReferenceError%": u,
      "%Reflect%": typeof Reflect > "u" ? e : Reflect,
      "%RegExp%": RegExp,
      "%Set%": typeof Set > "u" ? e : Set,
      "%SetIteratorPrototype%":
        typeof Set > "u" || !p || !y ? e : y(new Set()[Symbol.iterator]()),
      "%SharedArrayBuffer%":
        typeof SharedArrayBuffer > "u" ? e : SharedArrayBuffer,
      "%String%": String,
      "%StringIteratorPrototype%": p && y ? y(""[Symbol.iterator]()) : e,
      "%Symbol%": p ? Symbol : e,
      "%SyntaxError%": n,
      "%ThrowTypeError%": d,
      "%TypedArray%": v,
      "%TypeError%": i,
      "%Uint8Array%": typeof Uint8Array > "u" ? e : Uint8Array,
      "%Uint8ClampedArray%":
        typeof Uint8ClampedArray > "u" ? e : Uint8ClampedArray,
      "%Uint16Array%": typeof Uint16Array > "u" ? e : Uint16Array,
      "%Uint32Array%": typeof Uint32Array > "u" ? e : Uint32Array,
      "%URIError%": f,
      "%WeakMap%": typeof WeakMap > "u" ? e : WeakMap,
      "%WeakRef%": typeof WeakRef > "u" ? e : WeakRef,
      "%WeakSet%": typeof WeakSet > "u" ? e : WeakSet,
    };
  if (y)
    try {
      null.error;
    } catch (q) {
      var m = y(y(q));
      h["%Error.prototype%"] = m;
    }
  var _ = function q(R) {
      var E;
      if (R === "%AsyncFunction%") E = a("async function () {}");
      else if (R === "%GeneratorFunction%") E = a("function* () {}");
      else if (R === "%AsyncGeneratorFunction%") E = a("async function* () {}");
      else if (R === "%AsyncGenerator%") {
        var A = q("%AsyncGeneratorFunction%");
        A && (E = A.prototype);
      } else if (R === "%AsyncIteratorPrototype%") {
        var x = q("%AsyncGenerator%");
        x && y && (E = y(x.prototype));
      }
      return ((h[R] = E), E);
    },
    P = {
      __proto__: null,
      "%ArrayBufferPrototype%": ["ArrayBuffer", "prototype"],
      "%ArrayPrototype%": ["Array", "prototype"],
      "%ArrayProto_entries%": ["Array", "prototype", "entries"],
      "%ArrayProto_forEach%": ["Array", "prototype", "forEach"],
      "%ArrayProto_keys%": ["Array", "prototype", "keys"],
      "%ArrayProto_values%": ["Array", "prototype", "values"],
      "%AsyncFunctionPrototype%": ["AsyncFunction", "prototype"],
      "%AsyncGenerator%": ["AsyncGeneratorFunction", "prototype"],
      "%AsyncGeneratorPrototype%": [
        "AsyncGeneratorFunction",
        "prototype",
        "prototype",
      ],
      "%BooleanPrototype%": ["Boolean", "prototype"],
      "%DataViewPrototype%": ["DataView", "prototype"],
      "%DatePrototype%": ["Date", "prototype"],
      "%ErrorPrototype%": ["Error", "prototype"],
      "%EvalErrorPrototype%": ["EvalError", "prototype"],
      "%Float32ArrayPrototype%": ["Float32Array", "prototype"],
      "%Float64ArrayPrototype%": ["Float64Array", "prototype"],
      "%FunctionPrototype%": ["Function", "prototype"],
      "%Generator%": ["GeneratorFunction", "prototype"],
      "%GeneratorPrototype%": ["GeneratorFunction", "prototype", "prototype"],
      "%Int8ArrayPrototype%": ["Int8Array", "prototype"],
      "%Int16ArrayPrototype%": ["Int16Array", "prototype"],
      "%Int32ArrayPrototype%": ["Int32Array", "prototype"],
      "%JSONParse%": ["JSON", "parse"],
      "%JSONStringify%": ["JSON", "stringify"],
      "%MapPrototype%": ["Map", "prototype"],
      "%NumberPrototype%": ["Number", "prototype"],
      "%ObjectPrototype%": ["Object", "prototype"],
      "%ObjProto_toString%": ["Object", "prototype", "toString"],
      "%ObjProto_valueOf%": ["Object", "prototype", "valueOf"],
      "%PromisePrototype%": ["Promise", "prototype"],
      "%PromiseProto_then%": ["Promise", "prototype", "then"],
      "%Promise_all%": ["Promise", "all"],
      "%Promise_reject%": ["Promise", "reject"],
      "%Promise_resolve%": ["Promise", "resolve"],
      "%RangeErrorPrototype%": ["RangeError", "prototype"],
      "%ReferenceErrorPrototype%": ["ReferenceError", "prototype"],
      "%RegExpPrototype%": ["RegExp", "prototype"],
      "%SetPrototype%": ["Set", "prototype"],
      "%SharedArrayBufferPrototype%": ["SharedArrayBuffer", "prototype"],
      "%StringPrototype%": ["String", "prototype"],
      "%SymbolPrototype%": ["Symbol", "prototype"],
      "%SyntaxErrorPrototype%": ["SyntaxError", "prototype"],
      "%TypedArrayPrototype%": ["TypedArray", "prototype"],
      "%TypeErrorPrototype%": ["TypeError", "prototype"],
      "%Uint8ArrayPrototype%": ["Uint8Array", "prototype"],
      "%Uint8ClampedArrayPrototype%": ["Uint8ClampedArray", "prototype"],
      "%Uint16ArrayPrototype%": ["Uint16Array", "prototype"],
      "%Uint32ArrayPrototype%": ["Uint32Array", "prototype"],
      "%URIErrorPrototype%": ["URIError", "prototype"],
      "%WeakMapPrototype%": ["WeakMap", "prototype"],
      "%WeakSetPrototype%": ["WeakSet", "prototype"],
    },
    O = Rt(),
    w = Zt(),
    S = O.call(Function.call, Array.prototype.concat),
    $ = O.call(Function.apply, Array.prototype.splice),
    M = O.call(Function.call, String.prototype.replace),
    T = O.call(Function.call, String.prototype.slice),
    I = O.call(Function.call, RegExp.prototype.exec),
    L =
      /[^%.[\]]+|\[(?:(-?\d+(?:\.\d+)?)|(["'])((?:(?!\2)[^\\]|\\.)*?)\2)\]|(?=(?:\.|\[\])(?:\.|\[\]|%$))/g,
    k = /\\(\\)?/g,
    U = function (R) {
      var E = T(R, 0, 1),
        A = T(R, -1);
      if (E === "%" && A !== "%")
        throw new n("invalid intrinsic syntax, expected closing `%`");
      if (A === "%" && E !== "%")
        throw new n("invalid intrinsic syntax, expected opening `%`");
      var x = [];
      return (
        M(R, L, function (C, F, N, le) {
          x[x.length] = N ? M(le, k, "$1") : F || C;
        }),
        x
      );
    },
    j = function (R, E) {
      var A = R,
        x;
      if ((w(P, A) && ((x = P[A]), (A = "%" + x[0] + "%")), w(h, A))) {
        var C = h[A];
        if ((C === g && (C = _(A)), typeof C > "u" && !E))
          throw new i(
            "intrinsic " +
              R +
              " exists, but is not available. Please file an issue!",
          );
        return { alias: x, name: A, value: C };
      }
      throw new n("intrinsic " + R + " does not exist!");
    };
  return (
    (Ge = function (R, E) {
      if (typeof R != "string" || R.length === 0)
        throw new i("intrinsic name must be a non-empty string");
      if (arguments.length > 1 && typeof E != "boolean")
        throw new i('"allowMissing" argument must be a boolean');
      if (I(/^%?[^%]*%?$/, R) === null)
        throw new n(
          "`%` may not be present anywhere but at the beginning and end of the intrinsic name",
        );
      var A = U(R),
        x = A.length > 0 ? A[0] : "",
        C = j("%" + x + "%", E),
        F = C.name,
        N = C.value,
        le = !1,
        be = C.alias;
      be && ((x = be[0]), $(A, S([0, 1], be)));
      for (var ce = 1, H = !0; ce < A.length; ce += 1) {
        var G = A[ce],
          fe = T(G, 0, 1),
          pe = T(G, -1);
        if (
          (fe === '"' ||
            fe === "'" ||
            fe === "`" ||
            pe === '"' ||
            pe === "'" ||
            pe === "`") &&
          fe !== pe
        )
          throw new n("property names with quotes must have matching quotes");
        if (
          ((G === "constructor" || !H) && (le = !0),
          (x += "." + G),
          (F = "%" + x + "%"),
          w(h, F))
        )
          N = h[F];
        else if (N != null) {
          if (!(G in N)) {
            if (!E)
              throw new i(
                "base intrinsic for " +
                  R +
                  " exists, but the property is not available.",
              );
            return;
          }
          if (o && ce + 1 >= A.length) {
            var ye = o(N, G);
            ((H = !!ye),
              H && "get" in ye && !("originalValue" in ye.get)
                ? (N = ye.get)
                : (N = N[G]));
          } else ((H = w(N, G)), (N = N[G]));
          H && !le && (h[F] = N);
        }
      }
      return N;
    }),
    Ge
  );
}
var De, Tr;
function Qt() {
  if (Tr) return De;
  Tr = 1;
  var e = ar(),
    r = e("%Object.defineProperty%", !0) || !1;
  if (r)
    try {
      r({}, "a", { value: 1 });
    } catch {
      r = !1;
    }
  return ((De = r), De);
}
var Le, Nr;
function St() {
  if (Nr) return Le;
  Nr = 1;
  var e = ar(),
    r = e("%Object.getOwnPropertyDescriptor%", !0);
  if (r)
    try {
      r([], "length");
    } catch {
      r = null;
    }
  return ((Le = r), Le);
}
var ke, $r;
function en() {
  if ($r) return ke;
  $r = 1;
  var e = Qt(),
    r = Ot(),
    s = At(),
    l = St();
  return (
    (ke = function (n, i, f) {
      if (!n || (typeof n != "object" && typeof n != "function"))
        throw new s("`obj` must be an object or a function`");
      if (typeof i != "string" && typeof i != "symbol")
        throw new s("`property` must be a string or a symbol`");
      if (
        arguments.length > 3 &&
        typeof arguments[3] != "boolean" &&
        arguments[3] !== null
      )
        throw new s("`nonEnumerable`, if provided, must be a boolean or null");
      if (
        arguments.length > 4 &&
        typeof arguments[4] != "boolean" &&
        arguments[4] !== null
      )
        throw new s("`nonWritable`, if provided, must be a boolean or null");
      if (
        arguments.length > 5 &&
        typeof arguments[5] != "boolean" &&
        arguments[5] !== null
      )
        throw new s(
          "`nonConfigurable`, if provided, must be a boolean or null",
        );
      if (arguments.length > 6 && typeof arguments[6] != "boolean")
        throw new s("`loose`, if provided, must be a boolean");
      var c = arguments.length > 3 ? arguments[3] : null,
        a = arguments.length > 4 ? arguments[4] : null,
        o = arguments.length > 5 ? arguments[5] : null,
        t = arguments.length > 6 ? arguments[6] : !1,
        d = !!l && l(n, i);
      if (e)
        e(n, i, {
          configurable: o === null && d ? d.configurable : !o,
          enumerable: c === null && d ? d.enumerable : !c,
          value: f,
          writable: a === null && d ? d.writable : !a,
        });
      else if (t || (!c && !a && !o)) n[i] = f;
      else
        throw new r(
          "This environment does not support defining a property as non-configurable, non-writable, or non-enumerable.",
        );
    }),
    ke
  );
}
var Be, Ir;
function rn() {
  if (Ir) return Be;
  Ir = 1;
  var e = ar(),
    r = e("%Object.defineProperty%", !0) || !1;
  if (r)
    try {
      r({}, "a", { value: 1 });
    } catch {
      r = !1;
    }
  return ((Be = r), Be);
}
var Fe, Mr;
function tn() {
  if (Mr) return Fe;
  Mr = 1;
  var e = rn(),
    r = function () {
      return !!e;
    };
  return (
    (r.hasArrayLengthDefineBug = function () {
      if (!e) return null;
      try {
        return e([], "length", { value: 1 }).length !== 1;
      } catch {
        return !0;
      }
    }),
    (Fe = r),
    Fe
  );
}
var He, jr;
function wt() {
  if (jr) return He;
  jr = 1;
  var e = Bt(),
    r = typeof Symbol == "function" && typeof Symbol("foo") == "symbol",
    s = Object.prototype.toString,
    l = Array.prototype.concat,
    u = en(),
    n = function (a) {
      return typeof a == "function" && s.call(a) === "[object Function]";
    },
    i = tn()(),
    f = function (a, o, t, d) {
      if (o in a) {
        if (d === !0) {
          if (a[o] === t) return;
        } else if (!n(d) || !d()) return;
      }
      i ? u(a, o, t, !0) : u(a, o, t);
    },
    c = function (a, o) {
      var t = arguments.length > 2 ? arguments[2] : {},
        d = e(o);
      r && (d = l.call(d, Object.getOwnPropertySymbols(o)));
      for (var p = 0; p < d.length; p += 1) f(a, d[p], o[d[p]], t[d[p]]);
    };
  return ((c.supportsDescriptors = !!i), (He = c), He);
}
var ze, Cr;
function Et() {
  return (Cr || ((Cr = 1), (ze = D)), ze);
}
var Xe, Ur;
function xt() {
  if (Ur) return Xe;
  Ur = 1;
  var e = Et();
  return (
    (Xe = function () {
      return typeof D != "object" || !D || D.Math !== Math || D.Array !== Array
        ? e
        : D;
    }),
    Xe
  );
}
var Ye, Gr;
function nn() {
  if (Gr) return Ye;
  Gr = 1;
  var e = wt(),
    r = St(),
    s = xt();
  return (
    (Ye = function () {
      var u = s();
      if (e.supportsDescriptors) {
        var n = r(u, "globalThis");
        (!n ||
          (n.configurable &&
            (n.enumerable || !n.writable || globalThis !== u))) &&
          Object.defineProperty(u, "globalThis", {
            configurable: !0,
            enumerable: !1,
            value: u,
            writable: !0,
          });
      } else
        (typeof globalThis != "object" || globalThis !== u) &&
          (u.globalThis = u);
      return u;
    }),
    Ye
  );
}
var We, Dr;
function qt() {
  if (Dr) return We;
  Dr = 1;
  var e = wt(),
    r = Et(),
    s = xt(),
    l = nn(),
    u = s(),
    n = function () {
      return u;
    };
  return (e(n, { getPolyfill: s, implementation: r, shim: l }), (We = n), We);
}
var Ve = {},
  V = {},
  de = { exports: {} },
  Lr;
function on() {
  return (
    Lr ||
      ((Lr = 1),
      (function (e, r) {
        ((r = e.exports = s), (r.getSerialize = l));
        function s(u, n, i, f) {
          return JSON.stringify(u, l(n, f), i);
        }
        function l(u, n) {
          var i = [],
            f = [];
          return (
            n == null &&
              (n = function (c, a) {
                return i[0] === a
                  ? "[Circular ~]"
                  : "[Circular ~." + f.slice(0, i.indexOf(a)).join(".") + "]";
              }),
            function (c, a) {
              if (i.length > 0) {
                var o = i.indexOf(this);
                (~o ? i.splice(o + 1) : i.push(this),
                  ~o ? f.splice(o, 1 / 0, c) : f.push(c),
                  ~i.indexOf(a) && (a = n.call(this, c, a)));
              } else i.push(a);
              return u == null ? a : u.call(this, c, a);
            }
          );
        }
      })(de, de.exports)),
    de.exports
  );
}
var Je = {},
  kr;
function an() {
  return (
    kr ||
      ((kr = 1),
      (function (e) {
        (function () {
          var r = {
            not_type: /[^T]/,
            not_primitive: /[^v]/,
            number: /[diefg]/,
            numeric_arg: /[bcdiefguxX]/,
            json: /[j]/,
            text: /^[^\x25]+/,
            modulo: /^\x25{2}/,
            placeholder:
              /^\x25(?:([1-9]\d*)\$|\(([^)]+)\))?(\+)?(0|'[^$])?(-)?(\d+)?(?:\.(\d+))?([b-gijostTuvxX])/,
            key: /^([a-z_][a-z_\d]*)/i,
            key_access: /^\.([a-z_][a-z_\d]*)/i,
            index_access: /^\[(\d+)\]/,
            sign: /^[+-]/,
          };
          function s(f) {
            return u(i(f), arguments);
          }
          function l(f, c) {
            return s.apply(null, [f].concat(c || []));
          }
          function u(f, c) {
            var a = 1,
              o = f.length,
              t,
              d = "",
              p,
              b,
              y,
              g,
              v,
              h,
              m,
              _;
            for (p = 0; p < o; p++)
              if (typeof f[p] == "string") d += f[p];
              else if (typeof f[p] == "object") {
                if (((y = f[p]), y.keys))
                  for (t = c[a], b = 0; b < y.keys.length; b++) {
                    if (t == null)
                      throw new Error(
                        s(
                          '[sprintf] Cannot access property "%s" of undefined value "%s"',
                          y.keys[b],
                          y.keys[b - 1],
                        ),
                      );
                    t = t[y.keys[b]];
                  }
                else y.param_no ? (t = c[y.param_no]) : (t = c[a++]);
                if (
                  (r.not_type.test(y.type) &&
                    r.not_primitive.test(y.type) &&
                    t instanceof Function &&
                    (t = t()),
                  r.numeric_arg.test(y.type) &&
                    typeof t != "number" &&
                    isNaN(t))
                )
                  throw new TypeError(
                    s("[sprintf] expecting number but found %T", t),
                  );
                switch ((r.number.test(y.type) && (m = t >= 0), y.type)) {
                  case "b":
                    t = parseInt(t, 10).toString(2);
                    break;
                  case "c":
                    t = String.fromCharCode(parseInt(t, 10));
                    break;
                  case "d":
                  case "i":
                    t = parseInt(t, 10);
                    break;
                  case "j":
                    t = JSON.stringify(
                      t,
                      null,
                      y.width ? parseInt(y.width) : 0,
                    );
                    break;
                  case "e":
                    t = y.precision
                      ? parseFloat(t).toExponential(y.precision)
                      : parseFloat(t).toExponential();
                    break;
                  case "f":
                    t = y.precision
                      ? parseFloat(t).toFixed(y.precision)
                      : parseFloat(t);
                    break;
                  case "g":
                    t = y.precision
                      ? String(Number(t.toPrecision(y.precision)))
                      : parseFloat(t);
                    break;
                  case "o":
                    t = (parseInt(t, 10) >>> 0).toString(8);
                    break;
                  case "s":
                    ((t = String(t)),
                      (t = y.precision ? t.substring(0, y.precision) : t));
                    break;
                  case "t":
                    ((t = String(!!t)),
                      (t = y.precision ? t.substring(0, y.precision) : t));
                    break;
                  case "T":
                    ((t = Object.prototype.toString
                      .call(t)
                      .slice(8, -1)
                      .toLowerCase()),
                      (t = y.precision ? t.substring(0, y.precision) : t));
                    break;
                  case "u":
                    t = parseInt(t, 10) >>> 0;
                    break;
                  case "v":
                    ((t = t.valueOf()),
                      (t = y.precision ? t.substring(0, y.precision) : t));
                    break;
                  case "x":
                    t = (parseInt(t, 10) >>> 0).toString(16);
                    break;
                  case "X":
                    t = (parseInt(t, 10) >>> 0).toString(16).toUpperCase();
                    break;
                }
                r.json.test(y.type)
                  ? (d += t)
                  : (r.number.test(y.type) && (!m || y.sign)
                      ? ((_ = m ? "+" : "-"),
                        (t = t.toString().replace(r.sign, "")))
                      : (_ = ""),
                    (v = y.pad_char
                      ? y.pad_char === "0"
                        ? "0"
                        : y.pad_char.charAt(1)
                      : " "),
                    (h = y.width - (_ + t).length),
                    (g = y.width && h > 0 ? v.repeat(h) : ""),
                    (d += y.align
                      ? _ + t + g
                      : v === "0"
                        ? _ + g + t
                        : g + _ + t));
              }
            return d;
          }
          var n = Object.create(null);
          function i(f) {
            if (n[f]) return n[f];
            for (var c = f, a, o = [], t = 0; c;) {
              if ((a = r.text.exec(c)) !== null) o.push(a[0]);
              else if ((a = r.modulo.exec(c)) !== null) o.push("%");
              else if ((a = r.placeholder.exec(c)) !== null) {
                if (a[2]) {
                  t |= 1;
                  var d = [],
                    p = a[2],
                    b = [];
                  if ((b = r.key.exec(p)) !== null)
                    for (d.push(b[1]); (p = p.substring(b[0].length)) !== "";)
                      if ((b = r.key_access.exec(p)) !== null) d.push(b[1]);
                      else if ((b = r.index_access.exec(p)) !== null)
                        d.push(b[1]);
                      else
                        throw new SyntaxError(
                          "[sprintf] failed to parse named argument key",
                        );
                  else
                    throw new SyntaxError(
                      "[sprintf] failed to parse named argument key",
                    );
                  a[2] = d;
                } else t |= 2;
                if (t === 3)
                  throw new Error(
                    "[sprintf] mixing positional and named placeholders is not (yet) supported",
                  );
                o.push({
                  placeholder: a[0],
                  param_no: a[1],
                  keys: a[2],
                  sign: a[3],
                  pad_char: a[4],
                  align: a[5],
                  width: a[6],
                  precision: a[7],
                  type: a[8],
                });
              } else throw new SyntaxError("[sprintf] unexpected placeholder");
              c = c.substring(a[0].length);
            }
            return (n[f] = o);
          }
          ((e.sprintf = s),
            (e.vsprintf = l),
            typeof window < "u" &&
              ((window.sprintf = s), (window.vsprintf = l)));
        })();
      })(Je)),
    Je
  );
}
var J = {},
  Br;
function Tt() {
  if (Br) return J;
  ((Br = 1),
    Object.defineProperty(J, "__esModule", { value: !0 }),
    (J.logLevels = void 0));
  const e = { debug: 20, error: 50, fatal: 60, info: 30, trace: 10, warn: 40 };
  return ((J.logLevels = e), J);
}
var Fr;
function un() {
  if (Fr) return V;
  ((Fr = 1),
    Object.defineProperty(V, "__esModule", { value: !0 }),
    (V.default = void 0));
  var e = n(or),
    r = n(qt()),
    s = n(on()),
    l = an(),
    u = Tt();
  function n(g) {
    return g && g.__esModule ? g : { default: g };
  }
  function i() {
    return (
      (i =
        Object.assign ||
        function (g) {
          for (var v = 1; v < arguments.length; v++) {
            var h = arguments[v];
            for (var m in h)
              Object.prototype.hasOwnProperty.call(h, m) && (g[m] = h[m]);
          }
          return g;
        }),
      i.apply(this, arguments)
    );
  }
  function f(g, v) {
    var h = Object.keys(g);
    if (Object.getOwnPropertySymbols) {
      var m = Object.getOwnPropertySymbols(g);
      (v &&
        (m = m.filter(function (_) {
          return Object.getOwnPropertyDescriptor(g, _).enumerable;
        })),
        h.push.apply(h, m));
    }
    return h;
  }
  function c(g) {
    for (var v = 1; v < arguments.length; v++) {
      var h = arguments[v] != null ? arguments[v] : {};
      v % 2
        ? f(Object(h), !0).forEach(function (m) {
            a(g, m, h[m]);
          })
        : Object.getOwnPropertyDescriptors
          ? Object.defineProperties(g, Object.getOwnPropertyDescriptors(h))
          : f(Object(h)).forEach(function (m) {
              Object.defineProperty(
                g,
                m,
                Object.getOwnPropertyDescriptor(h, m),
              );
            });
    }
    return g;
  }
  function a(g, v, h) {
    return (
      v in g
        ? Object.defineProperty(g, v, {
            value: h,
            enumerable: !0,
            configurable: !0,
            writable: !0,
          })
        : (g[v] = h),
      g
    );
  }
  const o = (0, r.default)();
  let t;
  e.default && (t = Mt);
  const d = () => {
      if (!t) return {};
      const g = [];
      let v = process.domain;
      if (!v || !v.parentDomain) return {};
      for (; v && v.parentDomain;)
        ((v = v.parentDomain),
          v.roarr && v.roarr.context && g.push(v.roarr.context));
      let h = {};
      for (const m of g) h = c(c({}, h), m);
      return h;
    },
    p = () => {
      if (!t) return {};
      let g = process.domain;
      if (g && g.roarr && g.roarr.context) return g.roarr.context;
      if (!g || !g.parentDomain) return {};
      for (; g && g.parentDomain;)
        if (((g = g.parentDomain), g.roarr && g.roarr.context))
          return g.roarr.context;
      return {};
    },
    b = (g, v) => {
      const h = (m, _, P, O, w, S, $, M, T, I) => {
        const L = Date.now(),
          k = o.ROARR.sequence++;
        let U, j;
        if (typeof m == "string") {
          U = c(c({}, p()), v || {});
          const q = i(
            {},
            { a: m, b: _, c: P, d: O, e: w, f: S, g: $, h: M, i: T, k: I },
          );
          j =
            Object.keys(q)
              .map((A) => q[A])
              .reduce((A, x) => (A += typeof x > "u" ? 0 : 1), 0) === 1
              ? (0, l.sprintf)("%s", m)
              : (0, l.sprintf)(m, _, P, O, w, S, $, M, T, I);
        } else {
          if (typeof _ != "string")
            throw new TypeError("Message must be a string.");
          ((U = JSON.parse((0, s.default)(c(c(c({}, p()), v || {}), m)))),
            (j = (0, l.sprintf)(_, P, O, w, S, $, M, T, I)));
        }
        g({ context: U, message: j, sequence: k, time: L, version: "1.0.0" });
      };
      ((h.child = (m) =>
        typeof m == "function"
          ? b((_) => {
              if (typeof m != "function")
                throw new TypeError("Unexpected state.");
              g(m(_));
            }, v)
          : b(g, c(c(c({}, p()), v), m))),
        (h.getContext = () => c(c({}, p()), v || {})),
        (h.adopt = async (m, _) => {
          if (!t) return m();
          const P = t.create();
          return P.run(() => ((P.roarr = { context: c(c({}, d()), _) }), m()));
        }));
      for (const m of Object.keys(u.logLevels))
        h[m] = (_, P, O, w, S, $, M, T, I, L) =>
          h.child({ logLevel: u.logLevels[m] })(_, P, O, w, S, $, M, T, I, L);
      return h;
    };
  var y = b;
  return ((V.default = y), V);
}
var K = {},
  Hr;
function sn() {
  if (Hr) return K;
  ((Hr = 1),
    Object.defineProperty(K, "__esModule", { value: !0 }),
    (K.default = void 0));
  var e = Tt();
  const r = (l, u) => {
    const n = (i, f, c, a, o, t, d, p, b, y) => {};
    ((n.adopt = async (i) => i()),
      (n.child = (i) => r()),
      (n.getContext = () => ({})));
    for (const i of Object.keys(e.logLevels))
      n[i] = (f, c, a, o, t, d, p, b, y, g) =>
        n.child({ logLevel: e.logLevels[i] })(f, c, a, o, t, d, p, b, y, g);
    return n;
  };
  var s = r;
  return ((K.default = s), K);
}
var Z = {},
  Ke,
  zr;
function ln() {
  return (
    zr ||
      ((zr = 1),
      (Ke = function (r, s) {
        for (var l = r.split("."), u = s.split("."), n = 0; n < 3; n++) {
          var i = Number(l[n]),
            f = Number(u[n]);
          if (i > f) return 1;
          if (f > i) return -1;
          if (!isNaN(i) && isNaN(f)) return 1;
          if (isNaN(i) && !isNaN(f)) return -1;
        }
        return 0;
      })),
    Ke
  );
}
const cn = "2.15.4",
  fn = { version: cn };
var Q = {},
  Xr;
function pn() {
  if (Xr) return Q;
  ((Xr = 1),
    Object.defineProperty(Q, "__esModule", { value: !0 }),
    (Q.default = void 0));
  const e = (l) => ({
    write: (u) => {
      l.write(
        u +
          `
`,
      );
    },
  });
  var s = () => {
    const u =
      (process.env.ROARR_STREAM || "STDOUT").toUpperCase().toUpperCase() ===
      "STDOUT"
        ? process.stdout
        : process.stderr;
    return e(u);
  };
  return ((Q.default = s), Q);
}
var Yr;
function yn() {
  if (Yr) return Z;
  ((Yr = 1),
    Object.defineProperty(Z, "__esModule", { value: !0 }),
    (Z.default = void 0));
  var e = u(or),
    r = u(ln()),
    s = fn,
    l = u(pn());
  function u(o) {
    return o && o.__esModule ? o : { default: o };
  }
  function n(o, t) {
    var d = Object.keys(o);
    if (Object.getOwnPropertySymbols) {
      var p = Object.getOwnPropertySymbols(o);
      (t &&
        (p = p.filter(function (b) {
          return Object.getOwnPropertyDescriptor(o, b).enumerable;
        })),
        d.push.apply(d, p));
    }
    return d;
  }
  function i(o) {
    for (var t = 1; t < arguments.length; t++) {
      var d = arguments[t] != null ? arguments[t] : {};
      t % 2
        ? n(Object(d), !0).forEach(function (p) {
            f(o, p, d[p]);
          })
        : Object.getOwnPropertyDescriptors
          ? Object.defineProperties(o, Object.getOwnPropertyDescriptors(d))
          : n(Object(d)).forEach(function (p) {
              Object.defineProperty(
                o,
                p,
                Object.getOwnPropertyDescriptor(d, p),
              );
            });
    }
    return o;
  }
  function f(o, t, d) {
    return (
      t in o
        ? Object.defineProperty(o, t, {
            value: d,
            enumerable: !0,
            configurable: !0,
            writable: !0,
          })
        : (o[t] = d),
      o
    );
  }
  var a = (o) => {
    const t = (o.versions || []).concat();
    t.sort(r.default);
    const d = !t.length || (0, r.default)(s.version, t[t.length - 1]) === 1;
    (t.includes(s.version) || t.push(s.version), t.sort(r.default));
    let p = i(i({ sequence: 0 }, o), {}, { versions: t });
    return (
      e.default && (d || !p.write) && (p = i(i({}, p), (0, l.default)())),
      p
    );
  };
  return ((Z.default = a), Z);
}
var Wr;
function dn() {
  return (
    Wr ||
      ((Wr = 1),
      (function (e) {
        (Object.defineProperty(e, "__esModule", { value: !0 }),
          Object.defineProperty(e, "createLogger", {
            enumerable: !0,
            get: function () {
              return r.default;
            },
          }),
          Object.defineProperty(e, "createMockLogger", {
            enumerable: !0,
            get: function () {
              return s.default;
            },
          }),
          Object.defineProperty(e, "createRoarrInititialGlobalState", {
            enumerable: !0,
            get: function () {
              return l.default;
            },
          }));
        var r = u(un()),
          s = u(sn()),
          l = u(yn());
        function u(n) {
          return n && n.__esModule ? n : { default: n };
        }
      })(Ve)),
    Ve
  );
}
var Vr;
function gn() {
  if (Vr) return B;
  ((Vr = 1),
    Object.defineProperty(B, "__esModule", { value: !0 }),
    (B.default = B.ROARR = void 0));
  var e = nr(),
    r = u(or),
    s = u(qt()),
    l = dn();
  function u(a) {
    return a && a.__esModule ? a : { default: a };
  }
  const n = (0, s.default)(),
    i = (n.ROARR = (0, l.createRoarrInititialGlobalState)(n.ROARR || {}));
  B.ROARR = i;
  let f = l.createLogger;
  r.default &&
    ((0, e.boolean)(process.env.ROARR_LOG || "") || (f = l.createMockLogger));
  var c = f((a) => {
    if (i.write) {
      const o = JSON.stringify(a);
      i.write(o);
    }
  });
  return ((B.default = c), B);
}
var Jr;
function he() {
  if (Jr) return X;
  ((Jr = 1),
    Object.defineProperty(X, "__esModule", { value: !0 }),
    (X.default = void 0));
  var e = r(gn());
  function r(u) {
    return u && u.__esModule ? u : { default: u };
  }
  var l = e.default.child({ package: "global-agent" });
  return ((X.default = l), X);
}
var Ze = {},
  ee = {},
  Qe = {},
  re = {},
  er,
  Kr;
function vn() {
  if (Kr) return er;
  Kr = 1;
  class e extends Error {
    constructor(i) {
      (super(e._prepareSuperMessage(i)),
        Object.defineProperty(this, "name", {
          value: "NonError",
          configurable: !0,
          writable: !0,
        }),
        Error.captureStackTrace && Error.captureStackTrace(this, e));
    }
    static _prepareSuperMessage(i) {
      try {
        return JSON.stringify(i);
      } catch {
        return String(i);
      }
    }
  }
  const r = [
      { property: "name", enumerable: !1 },
      { property: "message", enumerable: !1 },
      { property: "stack", enumerable: !1 },
      { property: "code", enumerable: !0 },
    ],
    s = ({ from: n, seen: i, to_: f, forceEnumerable: c }) => {
      const a = f || (Array.isArray(n) ? [] : {});
      i.push(n);
      for (const [o, t] of Object.entries(n))
        if (typeof t != "function") {
          if (!t || typeof t != "object") {
            a[o] = t;
            continue;
          }
          if (!i.includes(n[o])) {
            a[o] = s({ from: n[o], seen: i.slice(), forceEnumerable: c });
            continue;
          }
          a[o] = "[Circular]";
        }
      for (const { property: o, enumerable: t } of r)
        typeof n[o] == "string" &&
          Object.defineProperty(a, o, {
            value: n[o],
            enumerable: c ? !0 : t,
            configurable: !0,
            writable: !0,
          });
      return a;
    };
  return (
    (er = {
      serializeError: (n) =>
        typeof n == "object" && n !== null
          ? s({ from: n, seen: [], forceEnumerable: !0 })
          : typeof n == "function"
            ? `[Function: ${n.name || "anonymous"}]`
            : n,
      deserializeError: (n) => {
        if (n instanceof Error) return n;
        if (typeof n == "object" && n !== null && !Array.isArray(n)) {
          const i = new Error();
          return (s({ from: n, seen: [], to_: i }), i);
        }
        return new e(n);
      },
    }),
    er
  );
}
var Zr;
function ir() {
  if (Zr) return re;
  ((Zr = 1),
    Object.defineProperty(re, "__esModule", { value: !0 }),
    (re.default = void 0));
  var e = vn(),
    r = nr(),
    s = l(he());
  function l(c) {
    return c && c.__esModule ? c : { default: c };
  }
  const u = s.default.child({ namespace: "Agent" });
  let n = 0;
  var f = class {
    constructor(a, o, t, d, p) {
      ((this.fallbackAgent = d),
        (this.isProxyConfigured = a),
        (this.mustUrlUseProxy = o),
        (this.getUrlProxy = t),
        (this.socketConnectionTimeout = p));
    }
    addRequest(a, o) {
      let t;
      if (
        (a.path.startsWith("http://") || a.path.startsWith("https://")
          ? (t = a.path)
          : (t =
              this.protocol +
              "//" +
              (o.hostname || o.host) +
              (o.port === 80 || o.port === 443 ? "" : ":" + o.port) +
              a.path),
        !this.isProxyConfigured())
      ) {
        (u.trace(
          { destination: t },
          "not proxying request; GLOBAL_AGENT.HTTP_PROXY is not configured",
        ),
          this.fallbackAgent.addRequest(a, o));
        return;
      }
      if (!this.mustUrlUseProxy(t)) {
        (u.trace(
          { destination: t },
          "not proxying request; url matches GLOBAL_AGENT.NO_PROXY",
        ),
          this.fallbackAgent.addRequest(a, o));
        return;
      }
      const d = n++,
        p = this.getUrlProxy(t);
      (this.protocol === "http:" &&
        ((a.path = t),
        p.authorization &&
          a.setHeader(
            "proxy-authorization",
            "Basic " + Buffer.from(p.authorization).toString("base64"),
          )),
        u.trace(
          {
            destination: t,
            proxy: "http://" + p.hostname + ":" + p.port,
            requestId: d,
          },
          "proxying request",
        ),
        a.on("error", (y) => {
          u.error({ error: (0, e.serializeError)(y) }, "request error");
        }),
        a.once("response", (y) => {
          u.trace(
            { headers: y.headers, requestId: d, statusCode: y.statusCode },
            "proxying response",
          );
        }),
        (a.shouldKeepAlive = !1));
      const b = {
        host: o.hostname || o.host,
        port: o.port || 80,
        proxy: p,
        tls: {},
      };
      (this.protocol === "https:" &&
        ((b.tls = {
          ca: o.ca,
          cert: o.cert,
          ciphers: o.ciphers,
          clientCertEngine: o.clientCertEngine,
          crl: o.crl,
          dhparam: o.dhparam,
          ecdhCurve: o.ecdhCurve,
          honorCipherOrder: o.honorCipherOrder,
          key: o.key,
          passphrase: o.passphrase,
          pfx: o.pfx,
          rejectUnauthorized: o.rejectUnauthorized,
          secureOptions: o.secureOptions,
          secureProtocol: o.secureProtocol,
          servername: o.servername || b.host,
          sessionIdContext: o.sessionIdContext,
        }),
        typeof process.env.NODE_TLS_REJECT_UNAUTHORIZED == "string" &&
          (0, r.boolean)(process.env.NODE_TLS_REJECT_UNAUTHORIZED) === !1 &&
          (b.tls.rejectUnauthorized = !1)),
        this.createConnection(b, (y, g) => {
          (u.trace({ target: b }, "connecting"),
            g &&
              (g.setTimeout(this.socketConnectionTimeout, () => {
                g.destroy();
              }),
              g.once("connect", () => {
                (u.trace({ target: b }, "connected"), g.setTimeout(0));
              }),
              g.once("secureConnect", () => {
                (u.trace({ target: b }, "connected (secure)"), g.setTimeout(0));
              })),
            y
              ? a.emit("error", y)
              : (u.debug("created socket"),
                g.on("error", (v) => {
                  u.error({ error: (0, e.serializeError)(v) }, "socket error");
                }),
                a.onSocket(g)));
        }));
    }
  };
  return ((re.default = f), re);
}
var te = {},
  Qr;
function hn() {
  if (Qr) return te;
  ((Qr = 1),
    Object.defineProperty(te, "__esModule", { value: !0 }),
    (te.default = void 0));
  var e = s(mt),
    r = s(ir());
  function s(n) {
    return n && n.__esModule ? n : { default: n };
  }
  var u = class extends r.default {
    constructor(...i) {
      (super(...i), (this.protocol = "http:"), (this.defaultPort = 80));
    }
    createConnection(i, f) {
      const c = e.default.connect(i.proxy.port, i.proxy.hostname);
      f(null, c);
    }
  };
  return ((te.default = u), te);
}
var ne = {},
  et;
function bn() {
  if (et) return ne;
  ((et = 1),
    Object.defineProperty(ne, "__esModule", { value: !0 }),
    (ne.default = void 0));
  var e = l(mt),
    r = l(Ct),
    s = l(ir());
  function l(i) {
    return i && i.__esModule ? i : { default: i };
  }
  var n = class extends s.default {
    constructor(...f) {
      (super(...f), (this.protocol = "https:"), (this.defaultPort = 443));
    }
    createConnection(f, c) {
      const a = e.default.connect(f.proxy.port, f.proxy.hostname);
      (a.on("error", (t) => {
        c(t);
      }),
        a.once("data", () => {
          const t = r.default.connect({ ...f.tls, socket: a });
          c(null, t);
        }));
      let o = "";
      ((o +=
        "CONNECT " +
        f.host +
        ":" +
        f.port +
        ` HTTP/1.1\r
`),
        (o +=
          "Host: " +
          f.host +
          ":" +
          f.port +
          `\r
`),
        f.proxy.authorization &&
          (o +=
            "Proxy-Authorization: Basic " +
            Buffer.from(f.proxy.authorization).toString("base64") +
            `\r
`),
        (o += `\r
`),
        a.write(o));
    }
  };
  return ((ne.default = n), ne);
}
var rt;
function mn() {
  return (
    rt ||
      ((rt = 1),
      (function (e) {
        (Object.defineProperty(e, "__esModule", { value: !0 }),
          Object.defineProperty(e, "Agent", {
            enumerable: !0,
            get: function () {
              return r.default;
            },
          }),
          Object.defineProperty(e, "HttpProxyAgent", {
            enumerable: !0,
            get: function () {
              return s.default;
            },
          }),
          Object.defineProperty(e, "HttpsProxyAgent", {
            enumerable: !0,
            get: function () {
              return l.default;
            },
          }));
        var r = u(ir()),
          s = u(hn()),
          l = u(bn());
        function u(n) {
          return n && n.__esModule ? n : { default: n };
        }
      })(Qe)),
    Qe
  );
}
var oe = {};
function _n(e, r) {
  if (!(e instanceof r))
    throw new TypeError("Cannot call a class as a function");
}
function tt(e, r) {
  if (!e)
    throw new ReferenceError(
      "this hasn't been initialised - super() hasn't been called",
    );
  return r && (typeof r == "object" || typeof r == "function") ? r : e;
}
function Pn(e, r) {
  if (typeof r != "function" && r !== null)
    throw new TypeError(
      "Super expression must either be null or a function, not " + typeof r,
    );
  ((e.prototype = Object.create(r && r.prototype, {
    constructor: { value: e, enumerable: !1, writable: !0, configurable: !0 },
  })),
    r &&
      (Object.setPrototypeOf
        ? Object.setPrototypeOf(e, r)
        : (e.__proto__ = r)));
}
function On(e) {
  function r() {
    e.apply(this, arguments);
  }
  return (
    (r.prototype = Object.create(e.prototype, {
      constructor: { value: e, enumerable: !1, writable: !0, configurable: !0 },
    })),
    Object.setPrototypeOf ? Object.setPrototypeOf(r, e) : (r.__proto__ = e),
    r
  );
}
var An = (function (e) {
  Pn(r, e);
  function r() {
    var s = arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : "";
    _n(this, r);
    var l = tt(this, (r.__proto__ || Object.getPrototypeOf(r)).call(this, s));
    return (
      Object.defineProperty(l, "message", {
        configurable: !0,
        enumerable: !1,
        value: s,
        writable: !0,
      }),
      Object.defineProperty(l, "name", {
        configurable: !0,
        enumerable: !1,
        value: l.constructor.name,
        writable: !0,
      }),
      Error.hasOwnProperty("captureStackTrace")
        ? (Error.captureStackTrace(l, l.constructor), tt(l))
        : (Object.defineProperty(l, "stack", {
            configurable: !0,
            enumerable: !1,
            value: new Error(s).stack,
            writable: !0,
          }),
          l)
    );
  }
  return r;
})(On(Error));
const Rn = Object.freeze(
    Object.defineProperty(
      { __proto__: null, default: An },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  ),
  Sn = vt(Rn);
var nt;
function ur() {
  if (nt) return oe;
  ((nt = 1),
    Object.defineProperty(oe, "__esModule", { value: !0 }),
    (oe.UnexpectedStateError = void 0));
  var e = r(Sn);
  function r(l) {
    return l && l.__esModule ? l : { default: l };
  }
  class s extends e.default {
    constructor(u, n = "UNEXPECTED_STATE_ERROR") {
      (super(u), (this.code = n));
    }
  }
  return ((oe.UnexpectedStateError = s), oe);
}
var rr = {},
  ae = {},
  ot;
function wn() {
  if (ot) return ae;
  ((ot = 1),
    Object.defineProperty(ae, "__esModule", { value: !0 }),
    (ae.default = void 0));
  var e = s(ht),
    r = s(bt);
  function s(n) {
    return n && n.__esModule ? n : { default: n };
  }
  var u =
    (n, i, f) =>
    (...c) => {
      let a, o, t;
      return (
        typeof c[0] == "string" || c[0] instanceof URL
          ? ((a = c[0]),
            typeof c[1] == "function"
              ? ((o = {}), (t = c[1]))
              : ((o = { ...c[1] }), (t = c[2])))
          : ((o = { ...c[0] }), (t = c[1])),
        f
          ? (o.agent = i)
          : (o.agent || (o.agent = i),
            (o.agent === e.default.globalAgent ||
              o.agent === r.default.globalAgent) &&
              (o.agent = i)),
        a ? n(a, o, t) : n(o, t)
      );
    };
  return ((ae.default = u), ae);
}
var ie = {},
  ge = { exports: {} },
  tr,
  at;
function En() {
  return (
    at ||
      ((at = 1),
      (tr = (e) => {
        if (typeof e != "string") throw new TypeError("Expected a string");
        return e.replace(/[|\\{}()[\]^$+*?.]/g, "\\$&").replace(/-/g, "\\x2d");
      })),
    tr
  );
}
var it;
function xn() {
  if (it) return ge.exports;
  it = 1;
  const e = En(),
    r = new Map();
  function s(l, u) {
    u = { caseSensitive: !1, ...u };
    const n = l + JSON.stringify(u);
    if (r.has(n)) return r.get(n);
    const i = l[0] === "!";
    (i && (l = l.slice(1)), (l = e(l).replace(/\\\*/g, "[\\s\\S]*")));
    const f = new RegExp(`^${l}$`, u.caseSensitive ? "" : "i");
    return ((f.negated = i), r.set(n, f), f);
  }
  return (
    (ge.exports = (l, u, n) => {
      if (!(Array.isArray(l) && Array.isArray(u)))
        throw new TypeError(`Expected two arrays, got ${typeof l} ${typeof u}`);
      if (u.length === 0) return l;
      const i = u[0][0] === "!";
      u = u.map((c) => s(c, n));
      const f = [];
      for (const c of l) {
        let a = i;
        for (const o of u) o.test(c) && (a = !o.negated);
        a && f.push(c);
      }
      return f;
    }),
    (ge.exports.isMatch = (l, u, n) => {
      const i = Array.isArray(l) ? l : [l],
        f = Array.isArray(u) ? u : [u];
      return i.some((c) =>
        f.every((a) => {
          const o = s(a, n),
            t = o.test(c);
          return o.negated ? !t : t;
        }),
      );
    }),
    ge.exports
  );
}
var ut;
function qn() {
  if (ut) return ie;
  ((ut = 1),
    Object.defineProperty(ie, "__esModule", { value: !0 }),
    (ie.default = void 0));
  var e = _t,
    r = l(xn()),
    s = ur();
  function l(i) {
    return i && i.__esModule ? i : { default: i };
  }
  var n = (i, f) => {
    const c = (0, e.parse)(i),
      a = f.split(/[\s,]+/);
    for (const o of a) {
      const t = o
        .replace(/^(?<leadingDot>\.)/, "*")
        .match(/^(?<hostname>.+?)(?::(?<port>\d+))?$/);
      if (!t || !t.groups)
        throw new s.UnexpectedStateError("Invalid NO_PROXY pattern.");
      if (!t.groups.hostname)
        throw new s.UnexpectedStateError(
          "NO_PROXY entry pattern must include hostname. Use * to match any hostname.",
        );
      if (
        r.default.isMatch(c.hostname, t.groups.hostname) &&
        (!t.groups || !t.groups.port || (c.port && c.port === t.groups.port))
      )
        return !0;
    }
    return !1;
  };
  return ((ie.default = n), ie);
}
var ue = {},
  st;
function Tn() {
  if (st) return ue;
  ((st = 1),
    Object.defineProperty(ue, "__esModule", { value: !0 }),
    (ue.default = void 0));
  var e = _t,
    r = ur(),
    l = (u) => {
      const n = (0, e.parse)(u);
      if (n.query !== null)
        throw new r.UnexpectedStateError(
          "Unsupported `GLOBAL_AGENT.HTTP_PROXY` configuration value: URL must not have query.",
        );
      if (n.hash !== null)
        throw new r.UnexpectedStateError(
          "Unsupported `GLOBAL_AGENT.HTTP_PROXY` configuration value: URL must not have hash.",
        );
      if (n.protocol !== "http:")
        throw new r.UnexpectedStateError(
          'Unsupported `GLOBAL_AGENT.HTTP_PROXY` configuration value: URL protocol must be "http:".',
        );
      let i = 80;
      return (
        n.port && (i = Number.parseInt(n.port, 10)),
        { authorization: n.auth || null, hostname: n.hostname, port: i }
      );
    };
  return ((ue.default = l), ue);
}
var lt;
function Nn() {
  return (
    lt ||
      ((lt = 1),
      (function (e) {
        (Object.defineProperty(e, "__esModule", { value: !0 }),
          Object.defineProperty(e, "bindHttpMethod", {
            enumerable: !0,
            get: function () {
              return r.default;
            },
          }),
          Object.defineProperty(e, "isUrlMatchingNoProxy", {
            enumerable: !0,
            get: function () {
              return s.default;
            },
          }),
          Object.defineProperty(e, "parseProxyUrl", {
            enumerable: !0,
            get: function () {
              return l.default;
            },
          }));
        var r = u(wn()),
          s = u(qn()),
          l = u(Tn());
        function u(n) {
          return n && n.__esModule ? n : { default: n };
        }
      })(rr)),
    rr
  );
}
var se = {},
  ct;
function Nt() {
  if (ct) return se;
  ((ct = 1),
    Object.defineProperty(se, "__esModule", { value: !0 }),
    (se.default = void 0));
  var e = r(he());
  function r(i) {
    return i && i.__esModule ? i : { default: i };
  }
  const s = e.default.child({ namespace: "createProxyController" }),
    l = ["HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY"];
  var n = () =>
    new Proxy(
      { HTTP_PROXY: null, HTTPS_PROXY: null, NO_PROXY: null },
      {
        set: (i, f, c) => {
          if (!l.includes(f))
            throw new Error('Cannot set an unmapped property "' + f + '".');
          return (
            (i[f] = c),
            s.info(
              { change: { name: f, value: c }, newConfiguration: i },
              "configuration changed",
            ),
            !0
          );
        },
      },
    );
  return ((se.default = n), se);
}
var ft;
function $n() {
  if (ft) return ee;
  ((ft = 1),
    Object.defineProperty(ee, "__esModule", { value: !0 }),
    (ee.default = void 0));
  var e = a(ht),
    r = a(bt),
    s = nr(),
    l = a(jt()),
    u = a(he()),
    n = mn(),
    i = ur(),
    f = Nn(),
    c = a(Nt());
  function a(_) {
    return _ && _.__esModule ? _ : { default: _ };
  }
  const o = e.default.get,
    t = e.default.request,
    d = r.default.get,
    p = r.default.request,
    b = u.default.child({ namespace: "createGlobalProxyAgent" }),
    y = {
      environmentVariableNamespace: void 0,
      forceGlobalAgent: void 0,
      socketConnectionTimeout: 6e4,
    },
    g = (_) => {
      const P = Object.keys(_),
        O = {};
      for (const w of P) {
        const S = _[w];
        S !== void 0 && (O[w] = S);
      }
      return O;
    },
    v = (_) => {
      const P = process.env;
      return {
        ...{
          environmentVariableNamespace:
            typeof P.GLOBAL_AGENT_ENVIRONMENT_VARIABLE_NAMESPACE == "string"
              ? P.GLOBAL_AGENT_ENVIRONMENT_VARIABLE_NAMESPACE
              : "GLOBAL_AGENT_",
          forceGlobalAgent:
            typeof P.GLOBAL_AGENT_FORCE_GLOBAL_AGENT == "string"
              ? (0, s.boolean)(P.GLOBAL_AGENT_FORCE_GLOBAL_AGENT)
              : !0,
          socketConnectionTimeout:
            typeof P.GLOBAL_AGENT_SOCKET_CONNECTION_TIMEOUT == "string"
              ? Number.parseInt(P.GLOBAL_AGENT_SOCKET_CONNECTION_TIMEOUT, 10)
              : y.socketConnectionTimeout,
        },
        ...g(_),
      };
    };
  var m = (_ = y) => {
    const P = v(_),
      O = (0, c.default)();
    ((O.HTTP_PROXY =
      process.env[P.environmentVariableNamespace + "HTTP_PROXY"] || null),
      (O.HTTPS_PROXY =
        process.env[P.environmentVariableNamespace + "HTTPS_PROXY"] || null),
      (O.NO_PROXY =
        process.env[P.environmentVariableNamespace + "NO_PROXY"] || null),
      b.info(
        { configuration: P, state: O },
        "global agent has been initialized",
      ));
    const w = (U) => (j) =>
        U()
          ? O.NO_PROXY
            ? !(0, f.isUrlMatchingNoProxy)(j, O.NO_PROXY)
            : !0
          : !1,
      S = (U) => () => {
        const j = U();
        if (!j)
          throw new i.UnexpectedStateError("HTTP(S) proxy must be configured.");
        return (0, f.parseProxyUrl)(j);
      },
      $ = () => O.HTTP_PROXY,
      M = class extends n.HttpProxyAgent {
        constructor() {
          super(
            () => $(),
            w($),
            S($),
            e.default.globalAgent,
            P.socketConnectionTimeout,
          );
        }
      },
      T = new M(),
      I = () => O.HTTPS_PROXY || O.HTTP_PROXY,
      L = class extends n.HttpsProxyAgent {
        constructor() {
          super(
            () => I(),
            w(I),
            S(I),
            r.default.globalAgent,
            P.socketConnectionTimeout,
          );
        }
      },
      k = new L();
    return (
      l.default.gte(process.version, "v11.7.0") &&
        ((e.default.globalAgent = T), (r.default.globalAgent = k)),
      l.default.gte(process.version, "v10.0.0")
        ? ((e.default.get = (0, f.bindHttpMethod)(o, T, P.forceGlobalAgent)),
          (e.default.request = (0, f.bindHttpMethod)(t, T, P.forceGlobalAgent)),
          (r.default.get = (0, f.bindHttpMethod)(d, k, P.forceGlobalAgent)),
          (r.default.request = (0, f.bindHttpMethod)(p, k, P.forceGlobalAgent)))
        : b.warn(
            "attempt to initialize global-agent in unsupported Node.js version was ignored",
          ),
      O
    );
  };
  return ((ee.default = m), ee);
}
var pt;
function $t() {
  return (
    pt ||
      ((pt = 1),
      (function (e) {
        (Object.defineProperty(e, "__esModule", { value: !0 }),
          Object.defineProperty(e, "createGlobalProxyAgent", {
            enumerable: !0,
            get: function () {
              return r.default;
            },
          }),
          Object.defineProperty(e, "createProxyController", {
            enumerable: !0,
            get: function () {
              return s.default;
            },
          }));
        var r = l($n()),
          s = l(Nt());
        function l(u) {
          return u && u.__esModule ? u : { default: u };
        }
      })(Ze)),
    Ze
  );
}
var yt;
function In() {
  if (yt) return z;
  ((yt = 1),
    Object.defineProperty(z, "__esModule", { value: !0 }),
    (z.default = void 0));
  var e = s(he()),
    r = $t();
  function s(i) {
    return i && i.__esModule ? i : { default: i };
  }
  const l = e.default.child({ namespace: "bootstrap" });
  var n = (i) =>
    D.GLOBAL_AGENT
      ? (l.warn(
          "found global.GLOBAL_AGENT; second attempt to bootstrap global-agent was ignored",
        ),
        !1)
      : ((D.GLOBAL_AGENT = (0, r.createGlobalProxyAgent)(i)), !0);
  return ((z.default = n), z);
}
var dt;
function Mn() {
  return (
    dt ||
      ((dt = 1),
      (function (e) {
        (Object.defineProperty(e, "__esModule", { value: !0 }),
          Object.defineProperty(e, "bootstrap", {
            enumerable: !0,
            get: function () {
              return r.default;
            },
          }));
        var r = s(In());
        function s(l) {
          return l && l.__esModule ? l : { default: l };
        }
      })(_e)),
    _e
  );
}
var gt;
function jn() {
  return (
    gt ||
      ((gt = 1),
      (function (e) {
        (Object.defineProperty(e, "__esModule", { value: !0 }),
          Object.defineProperty(e, "bootstrap", {
            enumerable: !0,
            get: function () {
              return r.bootstrap;
            },
          }),
          Object.defineProperty(e, "createGlobalProxyAgent", {
            enumerable: !0,
            get: function () {
              return s.createGlobalProxyAgent;
            },
          }));
        var r = Mn(),
          s = $t();
      })(me)),
    me
  );
}
var It = jn();
const { GLOBAL_AGENT_HTTP_PROXY: sr, GLOBAL_AGENT_HTTPS_PROXY: lr } =
  process.env;
(sr || lr) && It.bootstrap();
let ve;
function Cn(e) {
  if (sr || lr) return;
  const r = e.startsWith("http://") ? e : null;
  if (!ve) {
    if (!r) return;
    ((ve = It.createGlobalProxyAgent({ forceGlobalAgent: !1 })),
      (ve.NO_PROXY = "localhost,127.0.0.1"));
  }
  ve.HTTP_PROXY = r;
}
const Wn = Object.freeze(
  Object.defineProperty(
    {
      __proto__: null,
      GLOBAL_AGENT_HTTPS_PROXY: lr,
      GLOBAL_AGENT_HTTP_PROXY: sr,
      setSystemProxy: Cn,
    },
    Symbol.toStringTag,
    { value: "Module" },
  ),
);
export {
  Ft as a,
  En as b,
  Rt as c,
  Zt as d,
  zt as e,
  Xt as f,
  Ot as g,
  At as h,
  Yt as i,
  Ht as j,
  Wn as r,
  Cn as s,
};
//# sourceMappingURL=register-proxy-7lV9pun2.mjs.map
