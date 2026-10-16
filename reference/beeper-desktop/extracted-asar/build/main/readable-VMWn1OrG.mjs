import it from "stream";
import { c as fe } from "./_commonjsHelpers-CBUqixCJ.mjs";
import ht from "events";
import oe from "buffer";
import Ce from "util";
import ct from "node:module";
(function () {
  try {
    var E =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    E.SENTRY_RELEASE = { id: "4.3.209" };
    var _ = new E.Error().stack;
    _ &&
      ((E._sentryDebugIds = E._sentryDebugIds || {}),
      (E._sentryDebugIds[_] = "72145978-3cd8-49d1-b59f-d68448c4e141"),
      (E._sentryDebugIdIdentifier =
        "sentry-dbid-72145978-3cd8-49d1-b59f-d68448c4e141"));
  } catch {}
})();
const Pt = import.meta.filename,
  Nt = import.meta.dirname,
  pt = ct.createRequire(import.meta.url);
var re = { exports: {} },
  be,
  je;
function at() {
  return (je || ((je = 1), (be = it)), be);
}
var ye, ke;
function _t() {
  if (ke) return ye;
  ke = 1;
  function E(v, R) {
    var b = Object.keys(v);
    if (Object.getOwnPropertySymbols) {
      var r = Object.getOwnPropertySymbols(v);
      (R &&
        (r = r.filter(function (o) {
          return Object.getOwnPropertyDescriptor(v, o).enumerable;
        })),
        b.push.apply(b, r));
    }
    return b;
  }
  function _(v) {
    for (var R = 1; R < arguments.length; R++) {
      var b = arguments[R] != null ? arguments[R] : {};
      R % 2
        ? E(Object(b), !0).forEach(function (r) {
            T(v, r, b[r]);
          })
        : Object.getOwnPropertyDescriptors
          ? Object.defineProperties(v, Object.getOwnPropertyDescriptors(b))
          : E(Object(b)).forEach(function (r) {
              Object.defineProperty(
                v,
                r,
                Object.getOwnPropertyDescriptor(b, r),
              );
            });
    }
    return v;
  }
  function T(v, R, b) {
    return (
      (R = a(R)),
      R in v
        ? Object.defineProperty(v, R, {
            value: b,
            enumerable: !0,
            configurable: !0,
            writable: !0,
          })
        : (v[R] = b),
      v
    );
  }
  function O(v, R) {
    if (!(v instanceof R))
      throw new TypeError("Cannot call a class as a function");
  }
  function P(v, R) {
    for (var b = 0; b < R.length; b++) {
      var r = R[b];
      ((r.enumerable = r.enumerable || !1),
        (r.configurable = !0),
        "value" in r && (r.writable = !0),
        Object.defineProperty(v, a(r.key), r));
    }
  }
  function d(v, R, b) {
    return (
      R && P(v.prototype, R),
      Object.defineProperty(v, "prototype", { writable: !1 }),
      v
    );
  }
  function a(v) {
    var R = l(v, "string");
    return typeof R == "symbol" ? R : String(R);
  }
  function l(v, R) {
    if (typeof v != "object" || v === null) return v;
    var b = v[Symbol.toPrimitive];
    if (b !== void 0) {
      var r = b.call(v, R);
      if (typeof r != "object") return r;
      throw new TypeError("@@toPrimitive must return a primitive value.");
    }
    return String(v);
  }
  var f = oe,
    s = f.Buffer,
    u = Ce,
    g = u.inspect,
    c = (g && g.custom) || "inspect";
  function M(v, R, b) {
    s.prototype.copy.call(v, R, b);
  }
  return (
    (ye = (function () {
      function v() {
        (O(this, v), (this.head = null), (this.tail = null), (this.length = 0));
      }
      return (
        d(v, [
          {
            key: "push",
            value: function (b) {
              var r = { data: b, next: null };
              (this.length > 0 ? (this.tail.next = r) : (this.head = r),
                (this.tail = r),
                ++this.length);
            },
          },
          {
            key: "unshift",
            value: function (b) {
              var r = { data: b, next: this.head };
              (this.length === 0 && (this.tail = r),
                (this.head = r),
                ++this.length);
            },
          },
          {
            key: "shift",
            value: function () {
              if (this.length !== 0) {
                var b = this.head.data;
                return (
                  this.length === 1
                    ? (this.head = this.tail = null)
                    : (this.head = this.head.next),
                  --this.length,
                  b
                );
              }
            },
          },
          {
            key: "clear",
            value: function () {
              ((this.head = this.tail = null), (this.length = 0));
            },
          },
          {
            key: "join",
            value: function (b) {
              if (this.length === 0) return "";
              for (var r = this.head, o = "" + r.data; (r = r.next);)
                o += b + r.data;
              return o;
            },
          },
          {
            key: "concat",
            value: function (b) {
              if (this.length === 0) return s.alloc(0);
              for (var r = s.allocUnsafe(b >>> 0), o = this.head, p = 0; o;)
                (M(o.data, r, p), (p += o.data.length), (o = o.next));
              return r;
            },
          },
          {
            key: "consume",
            value: function (b, r) {
              var o;
              return (
                b < this.head.data.length
                  ? ((o = this.head.data.slice(0, b)),
                    (this.head.data = this.head.data.slice(b)))
                  : b === this.head.data.length
                    ? (o = this.shift())
                    : (o = r ? this._getString(b) : this._getBuffer(b)),
                o
              );
            },
          },
          {
            key: "first",
            value: function () {
              return this.head.data;
            },
          },
          {
            key: "_getString",
            value: function (b) {
              var r = this.head,
                o = 1,
                p = r.data;
              for (b -= p.length; (r = r.next);) {
                var w = r.data,
                  S = b > w.length ? w.length : b;
                if (
                  (S === w.length ? (p += w) : (p += w.slice(0, b)),
                  (b -= S),
                  b === 0)
                ) {
                  S === w.length
                    ? (++o,
                      r.next
                        ? (this.head = r.next)
                        : (this.head = this.tail = null))
                    : ((this.head = r), (r.data = w.slice(S)));
                  break;
                }
                ++o;
              }
              return ((this.length -= o), p);
            },
          },
          {
            key: "_getBuffer",
            value: function (b) {
              var r = s.allocUnsafe(b),
                o = this.head,
                p = 1;
              for (o.data.copy(r), b -= o.data.length; (o = o.next);) {
                var w = o.data,
                  S = b > w.length ? w.length : b;
                if ((w.copy(r, r.length - b, 0, S), (b -= S), b === 0)) {
                  S === w.length
                    ? (++p,
                      o.next
                        ? (this.head = o.next)
                        : (this.head = this.tail = null))
                    : ((this.head = o), (o.data = w.slice(S)));
                  break;
                }
                ++p;
              }
              return ((this.length -= p), r);
            },
          },
          {
            key: c,
            value: function (b, r) {
              return g(this, _(_({}, r), {}, { depth: 0, customInspect: !1 }));
            },
          },
        ]),
        v
      );
    })()),
    ye
  );
}
var ve, We;
function ft() {
  if (We) return ve;
  We = 1;
  function E(a, l) {
    var f = this,
      s = this._readableState && this._readableState.destroyed,
      u = this._writableState && this._writableState.destroyed;
    return s || u
      ? (l
          ? l(a)
          : a &&
            (this._writableState
              ? this._writableState.errorEmitted ||
                ((this._writableState.errorEmitted = !0),
                process.nextTick(P, this, a))
              : process.nextTick(P, this, a)),
        this)
      : (this._readableState && (this._readableState.destroyed = !0),
        this._writableState && (this._writableState.destroyed = !0),
        this._destroy(a || null, function (g) {
          !l && g
            ? f._writableState
              ? f._writableState.errorEmitted
                ? process.nextTick(T, f)
                : ((f._writableState.errorEmitted = !0),
                  process.nextTick(_, f, g))
              : process.nextTick(_, f, g)
            : l
              ? (process.nextTick(T, f), l(g))
              : process.nextTick(T, f);
        }),
        this);
  }
  function _(a, l) {
    (P(a, l), T(a));
  }
  function T(a) {
    (a._writableState && !a._writableState.emitClose) ||
      (a._readableState && !a._readableState.emitClose) ||
      a.emit("close");
  }
  function O() {
    (this._readableState &&
      ((this._readableState.destroyed = !1),
      (this._readableState.reading = !1),
      (this._readableState.ended = !1),
      (this._readableState.endEmitted = !1)),
      this._writableState &&
        ((this._writableState.destroyed = !1),
        (this._writableState.ended = !1),
        (this._writableState.ending = !1),
        (this._writableState.finalCalled = !1),
        (this._writableState.prefinished = !1),
        (this._writableState.finished = !1),
        (this._writableState.errorEmitted = !1)));
  }
  function P(a, l) {
    a.emit("error", l);
  }
  function d(a, l) {
    var f = a._readableState,
      s = a._writableState;
    (f && f.autoDestroy) || (s && s.autoDestroy)
      ? a.destroy(l)
      : a.emit("error", l);
  }
  return ((ve = { destroy: E, undestroy: O, errorOrDestroy: d }), ve);
}
var we = {},
  Be;
function U() {
  if (Be) return we;
  Be = 1;
  const E = {};
  function _(a, l, f) {
    f || (f = Error);
    function s(g, c, M) {
      return typeof l == "string" ? l : l(g, c, M);
    }
    class u extends f {
      constructor(c, M, v) {
        super(s(c, M, v));
      }
    }
    ((u.prototype.name = f.name), (u.prototype.code = a), (E[a] = u));
  }
  function T(a, l) {
    if (Array.isArray(a)) {
      const f = a.length;
      return (
        (a = a.map((s) => String(s))),
        f > 2
          ? `one of ${l} ${a.slice(0, f - 1).join(", ")}, or ` + a[f - 1]
          : f === 2
            ? `one of ${l} ${a[0]} or ${a[1]}`
            : `of ${l} ${a[0]}`
      );
    } else return `of ${l} ${String(a)}`;
  }
  function O(a, l, f) {
    return a.substr(0, l.length) === l;
  }
  function P(a, l, f) {
    return (
      (f === void 0 || f > a.length) && (f = a.length),
      a.substring(f - l.length, f) === l
    );
  }
  function d(a, l, f) {
    return (
      typeof f != "number" && (f = 0),
      f + l.length > a.length ? !1 : a.indexOf(l, f) !== -1
    );
  }
  return (
    _(
      "ERR_INVALID_OPT_VALUE",
      function (a, l) {
        return 'The value "' + l + '" is invalid for option "' + a + '"';
      },
      TypeError,
    ),
    _(
      "ERR_INVALID_ARG_TYPE",
      function (a, l, f) {
        let s;
        typeof l == "string" && O(l, "not ")
          ? ((s = "must not be"), (l = l.replace(/^not /, "")))
          : (s = "must be");
        let u;
        if (P(a, " argument")) u = `The ${a} ${s} ${T(l, "type")}`;
        else {
          const g = d(a, ".") ? "property" : "argument";
          u = `The "${a}" ${g} ${s} ${T(l, "type")}`;
        }
        return ((u += `. Received type ${typeof f}`), u);
      },
      TypeError,
    ),
    _("ERR_STREAM_PUSH_AFTER_EOF", "stream.push() after EOF"),
    _("ERR_METHOD_NOT_IMPLEMENTED", function (a) {
      return "The " + a + " method is not implemented";
    }),
    _("ERR_STREAM_PREMATURE_CLOSE", "Premature close"),
    _("ERR_STREAM_DESTROYED", function (a) {
      return "Cannot call " + a + " after a stream was destroyed";
    }),
    _("ERR_MULTIPLE_CALLBACK", "Callback called multiple times"),
    _("ERR_STREAM_CANNOT_PIPE", "Cannot pipe, not readable"),
    _("ERR_STREAM_WRITE_AFTER_END", "write after end"),
    _(
      "ERR_STREAM_NULL_VALUES",
      "May not write null values to stream",
      TypeError,
    ),
    _(
      "ERR_UNKNOWN_ENCODING",
      function (a) {
        return "Unknown encoding: " + a;
      },
      TypeError,
    ),
    _("ERR_STREAM_UNSHIFT_AFTER_END_EVENT", "stream.unshift() after end event"),
    (we.codes = E),
    we
  );
}
var Re, Ue;
function ot() {
  if (Ue) return Re;
  Ue = 1;
  var E = U().codes.ERR_INVALID_OPT_VALUE;
  function _(O, P, d) {
    return O.highWaterMark != null ? O.highWaterMark : P ? O[d] : null;
  }
  function T(O, P, d, a) {
    var l = _(P, a, d);
    if (l != null) {
      if (!(isFinite(l) && Math.floor(l) === l) || l < 0) {
        var f = a ? d : "highWaterMark";
        throw new E(f, l);
      }
      return Math.floor(l);
    }
    return O.objectMode ? 16 : 16 * 1024;
  }
  return ((Re = { getHighWaterMark: T }), Re);
}
var ne = { exports: {} },
  ie = { exports: {} },
  Fe;
function gt() {
  return (
    Fe ||
      ((Fe = 1),
      typeof Object.create == "function"
        ? (ie.exports = function (_, T) {
            T &&
              ((_.super_ = T),
              (_.prototype = Object.create(T.prototype, {
                constructor: {
                  value: _,
                  enumerable: !1,
                  writable: !0,
                  configurable: !0,
                },
              })));
          })
        : (ie.exports = function (_, T) {
            if (T) {
              _.super_ = T;
              var O = function () {};
              ((O.prototype = T.prototype),
                (_.prototype = new O()),
                (_.prototype.constructor = _));
            }
          })),
    ie.exports
  );
}
var He;
function J() {
  if (He) return ne.exports;
  He = 1;
  try {
    var E = pt("util");
    if (typeof E.inherits != "function") throw "";
    ne.exports = E.inherits;
  } catch {
    ne.exports = gt();
  }
  return ne.exports;
}
var Ee, $e;
function bt() {
  return ($e || (($e = 1), (Ee = Ce.deprecate)), Ee);
}
var Se, Ge;
function lt() {
  if (Ge) return Se;
  ((Ge = 1), (Se = x));
  function E(i) {
    var n = this;
    ((this.next = null),
      (this.entry = null),
      (this.finish = function () {
        ce(n, i);
      }));
  }
  var _;
  x.WritableState = N;
  var T = { deprecate: bt() },
    O = at(),
    P = oe.Buffer,
    d =
      (typeof fe < "u"
        ? fe
        : typeof window < "u"
          ? window
          : typeof self < "u"
            ? self
            : {}
      ).Uint8Array || function () {};
  function a(i) {
    return P.from(i);
  }
  function l(i) {
    return P.isBuffer(i) || i instanceof d;
  }
  var f = ft(),
    s = ot(),
    u = s.getHighWaterMark,
    g = U().codes,
    c = g.ERR_INVALID_ARG_TYPE,
    M = g.ERR_METHOD_NOT_IMPLEMENTED,
    v = g.ERR_MULTIPLE_CALLBACK,
    R = g.ERR_STREAM_CANNOT_PIPE,
    b = g.ERR_STREAM_DESTROYED,
    r = g.ERR_STREAM_NULL_VALUES,
    o = g.ERR_STREAM_WRITE_AFTER_END,
    p = g.ERR_UNKNOWN_ENCODING,
    w = f.errorOrDestroy;
  J()(x, O);
  function S() {}
  function N(i, n, y) {
    ((_ = _ || Y()),
      (i = i || {}),
      typeof y != "boolean" && (y = n instanceof _),
      (this.objectMode = !!i.objectMode),
      y && (this.objectMode = this.objectMode || !!i.writableObjectMode),
      (this.highWaterMark = u(this, i, "writableHighWaterMark", y)),
      (this.finalCalled = !1),
      (this.needDrain = !1),
      (this.ending = !1),
      (this.ended = !1),
      (this.finished = !1),
      (this.destroyed = !1));
    var A = i.decodeStrings === !1;
    ((this.decodeStrings = !A),
      (this.defaultEncoding = i.defaultEncoding || "utf8"),
      (this.length = 0),
      (this.writing = !1),
      (this.corked = 0),
      (this.sync = !0),
      (this.bufferProcessing = !1),
      (this.onwrite = function (C) {
        se(n, C);
      }),
      (this.writecb = null),
      (this.writelen = 0),
      (this.bufferedRequest = null),
      (this.lastBufferedRequest = null),
      (this.pendingcb = 0),
      (this.prefinished = !1),
      (this.errorEmitted = !1),
      (this.emitClose = i.emitClose !== !1),
      (this.autoDestroy = !!i.autoDestroy),
      (this.bufferedRequestCount = 0),
      (this.corkedRequestsFree = new E(this)));
  }
  ((N.prototype.getBuffer = function () {
    for (var n = this.bufferedRequest, y = []; n;) (y.push(n), (n = n.next));
    return y;
  }),
    (function () {
      try {
        Object.defineProperty(N.prototype, "buffer", {
          get: T.deprecate(
            function () {
              return this.getBuffer();
            },
            "_writableState.buffer is deprecated. Use _writableState.getBuffer instead.",
            "DEP0003",
          ),
        });
      } catch {}
    })());
  var j;
  typeof Symbol == "function" &&
  Symbol.hasInstance &&
  typeof Function.prototype[Symbol.hasInstance] == "function"
    ? ((j = Function.prototype[Symbol.hasInstance]),
      Object.defineProperty(x, Symbol.hasInstance, {
        value: function (n) {
          return j.call(this, n)
            ? !0
            : this !== x
              ? !1
              : n && n._writableState instanceof N;
        },
      }))
    : (j = function (n) {
        return n instanceof this;
      });
  function x(i) {
    _ = _ || Y();
    var n = this instanceof _;
    if (!n && !j.call(x, this)) return new x(i);
    ((this._writableState = new N(i, this, n)),
      (this.writable = !0),
      i &&
        (typeof i.write == "function" && (this._write = i.write),
        typeof i.writev == "function" && (this._writev = i.writev),
        typeof i.destroy == "function" && (this._destroy = i.destroy),
        typeof i.final == "function" && (this._final = i.final)),
      O.call(this));
  }
  x.prototype.pipe = function () {
    w(this, new R());
  };
  function L(i, n) {
    var y = new o();
    (w(i, y), process.nextTick(n, y));
  }
  function k(i, n, y, A) {
    var C;
    return (
      y === null
        ? (C = new r())
        : typeof y != "string" &&
          !n.objectMode &&
          (C = new c("chunk", ["string", "Buffer"], y)),
      C ? (w(i, C), process.nextTick(A, C), !1) : !0
    );
  }
  ((x.prototype.write = function (i, n, y) {
    var A = this._writableState,
      C = !1,
      e = !A.objectMode && l(i);
    return (
      e && !P.isBuffer(i) && (i = a(i)),
      typeof n == "function" && ((y = n), (n = null)),
      e ? (n = "buffer") : n || (n = A.defaultEncoding),
      typeof y != "function" && (y = S),
      A.ending
        ? L(this, y)
        : (e || k(this, A, i, y)) &&
          (A.pendingcb++, (C = le(this, A, e, i, n, y))),
      C
    );
  }),
    (x.prototype.cork = function () {
      this._writableState.corked++;
    }),
    (x.prototype.uncork = function () {
      var i = this._writableState;
      i.corked &&
        (i.corked--,
        !i.writing &&
          !i.corked &&
          !i.bufferProcessing &&
          i.bufferedRequest &&
          H(this, i));
    }),
    (x.prototype.setDefaultEncoding = function (n) {
      if (
        (typeof n == "string" && (n = n.toLowerCase()),
        !(
          [
            "hex",
            "utf8",
            "utf-8",
            "ascii",
            "binary",
            "base64",
            "ucs2",
            "ucs-2",
            "utf16le",
            "utf-16le",
            "raw",
          ].indexOf((n + "").toLowerCase()) > -1
        ))
      )
        throw new p(n);
      return ((this._writableState.defaultEncoding = n), this);
    }),
    Object.defineProperty(x.prototype, "writableBuffer", {
      enumerable: !1,
      get: function () {
        return this._writableState && this._writableState.getBuffer();
      },
    }));
  function K(i, n, y) {
    return (
      !i.objectMode &&
        i.decodeStrings !== !1 &&
        typeof n == "string" &&
        (n = P.from(n, y)),
      n
    );
  }
  Object.defineProperty(x.prototype, "writableHighWaterMark", {
    enumerable: !1,
    get: function () {
      return this._writableState.highWaterMark;
    },
  });
  function le(i, n, y, A, C, e) {
    if (!y) {
      var t = K(n, A, C);
      A !== t && ((y = !0), (C = "buffer"), (A = t));
    }
    var h = n.objectMode ? 1 : A.length;
    n.length += h;
    var m = n.length < n.highWaterMark;
    if ((m || (n.needDrain = !0), n.writing || n.corked)) {
      var I = n.lastBufferedRequest;
      ((n.lastBufferedRequest = {
        chunk: A,
        encoding: C,
        isBuf: y,
        callback: e,
        next: null,
      }),
        I
          ? (I.next = n.lastBufferedRequest)
          : (n.bufferedRequest = n.lastBufferedRequest),
        (n.bufferedRequestCount += 1));
    } else F(i, n, !1, h, A, C, e);
    return m;
  }
  function F(i, n, y, A, C, e, t) {
    ((n.writelen = A),
      (n.writecb = t),
      (n.writing = !0),
      (n.sync = !0),
      n.destroyed
        ? n.onwrite(new b("write"))
        : y
          ? i._writev(C, n.onwrite)
          : i._write(C, e, n.onwrite),
      (n.sync = !1));
  }
  function ue(i, n, y, A, C) {
    (--n.pendingcb,
      y
        ? (process.nextTick(C, A),
          process.nextTick(B, i, n),
          (i._writableState.errorEmitted = !0),
          w(i, A))
        : (C(A), (i._writableState.errorEmitted = !0), w(i, A), B(i, n)));
  }
  function Q(i) {
    ((i.writing = !1),
      (i.writecb = null),
      (i.length -= i.writelen),
      (i.writelen = 0));
  }
  function se(i, n) {
    var y = i._writableState,
      A = y.sync,
      C = y.writecb;
    if (typeof C != "function") throw new v();
    if ((Q(y), n)) ue(i, y, A, n, C);
    else {
      var e = z(y) || i.destroyed;
      (!e && !y.corked && !y.bufferProcessing && y.bufferedRequest && H(i, y),
        A ? process.nextTick(W, i, y, e, C) : W(i, y, e, C));
    }
  }
  function W(i, n, y, A) {
    (y || Z(i, n), n.pendingcb--, A(), B(i, n));
  }
  function Z(i, n) {
    n.length === 0 && n.needDrain && ((n.needDrain = !1), i.emit("drain"));
  }
  function H(i, n) {
    n.bufferProcessing = !0;
    var y = n.bufferedRequest;
    if (i._writev && y && y.next) {
      var A = n.bufferedRequestCount,
        C = new Array(A),
        e = n.corkedRequestsFree;
      e.entry = y;
      for (var t = 0, h = !0; y;)
        ((C[t] = y), y.isBuf || (h = !1), (y = y.next), (t += 1));
      ((C.allBuffers = h),
        F(i, n, !0, n.length, C, "", e.finish),
        n.pendingcb++,
        (n.lastBufferedRequest = null),
        e.next
          ? ((n.corkedRequestsFree = e.next), (e.next = null))
          : (n.corkedRequestsFree = new E(n)),
        (n.bufferedRequestCount = 0));
    } else {
      for (; y;) {
        var m = y.chunk,
          I = y.encoding,
          D = y.callback,
          q = n.objectMode ? 1 : m.length;
        if (
          (F(i, n, !1, q, m, I, D),
          (y = y.next),
          n.bufferedRequestCount--,
          n.writing)
        )
          break;
      }
      y === null && (n.lastBufferedRequest = null);
    }
    ((n.bufferedRequest = y), (n.bufferProcessing = !1));
  }
  ((x.prototype._write = function (i, n, y) {
    y(new M("_write()"));
  }),
    (x.prototype._writev = null),
    (x.prototype.end = function (i, n, y) {
      var A = this._writableState;
      return (
        typeof i == "function"
          ? ((y = i), (i = null), (n = null))
          : typeof n == "function" && ((y = n), (n = null)),
        i != null && this.write(i, n),
        A.corked && ((A.corked = 1), this.uncork()),
        A.ending || he(this, A, y),
        this
      );
    }),
    Object.defineProperty(x.prototype, "writableLength", {
      enumerable: !1,
      get: function () {
        return this._writableState.length;
      },
    }));
  function z(i) {
    return (
      i.ending &&
      i.length === 0 &&
      i.bufferedRequest === null &&
      !i.finished &&
      !i.writing
    );
  }
  function de(i, n) {
    i._final(function (y) {
      (n.pendingcb--,
        y && w(i, y),
        (n.prefinished = !0),
        i.emit("prefinish"),
        B(i, n));
    });
  }
  function ee(i, n) {
    !n.prefinished &&
      !n.finalCalled &&
      (typeof i._final == "function" && !n.destroyed
        ? (n.pendingcb++, (n.finalCalled = !0), process.nextTick(de, i, n))
        : ((n.prefinished = !0), i.emit("prefinish")));
  }
  function B(i, n) {
    var y = z(n);
    if (
      y &&
      (ee(i, n),
      n.pendingcb === 0 && ((n.finished = !0), i.emit("finish"), n.autoDestroy))
    ) {
      var A = i._readableState;
      (!A || (A.autoDestroy && A.endEmitted)) && i.destroy();
    }
    return y;
  }
  function he(i, n, y) {
    ((n.ending = !0),
      B(i, n),
      y && (n.finished ? process.nextTick(y) : i.once("finish", y)),
      (n.ended = !0),
      (i.writable = !1));
  }
  function ce(i, n, y) {
    var A = i.entry;
    for (i.entry = null; A;) {
      var C = A.callback;
      (n.pendingcb--, C(y), (A = A.next));
    }
    n.corkedRequestsFree.next = i;
  }
  return (
    Object.defineProperty(x.prototype, "destroyed", {
      enumerable: !1,
      get: function () {
        return this._writableState === void 0
          ? !1
          : this._writableState.destroyed;
      },
      set: function (n) {
        this._writableState && (this._writableState.destroyed = n);
      },
    }),
    (x.prototype.destroy = f.destroy),
    (x.prototype._undestroy = f.undestroy),
    (x.prototype._destroy = function (i, n) {
      n(i);
    }),
    Se
  );
}
var me, Ve;
function Y() {
  if (Ve) return me;
  Ve = 1;
  var E =
    Object.keys ||
    function (s) {
      var u = [];
      for (var g in s) u.push(g);
      return u;
    };
  me = a;
  var _ = ut(),
    T = lt();
  J()(a, _);
  for (var O = E(T.prototype), P = 0; P < O.length; P++) {
    var d = O[P];
    a.prototype[d] || (a.prototype[d] = T.prototype[d]);
  }
  function a(s) {
    if (!(this instanceof a)) return new a(s);
    (_.call(this, s),
      T.call(this, s),
      (this.allowHalfOpen = !0),
      s &&
        (s.readable === !1 && (this.readable = !1),
        s.writable === !1 && (this.writable = !1),
        s.allowHalfOpen === !1 &&
          ((this.allowHalfOpen = !1), this.once("end", l))));
  }
  (Object.defineProperty(a.prototype, "writableHighWaterMark", {
    enumerable: !1,
    get: function () {
      return this._writableState.highWaterMark;
    },
  }),
    Object.defineProperty(a.prototype, "writableBuffer", {
      enumerable: !1,
      get: function () {
        return this._writableState && this._writableState.getBuffer();
      },
    }),
    Object.defineProperty(a.prototype, "writableLength", {
      enumerable: !1,
      get: function () {
        return this._writableState.length;
      },
    }));
  function l() {
    this._writableState.ended || process.nextTick(f, this);
  }
  function f(s) {
    s.end();
  }
  return (
    Object.defineProperty(a.prototype, "destroyed", {
      enumerable: !1,
      get: function () {
        return this._readableState === void 0 || this._writableState === void 0
          ? !1
          : this._readableState.destroyed && this._writableState.destroyed;
      },
      set: function (u) {
        this._readableState === void 0 ||
          this._writableState === void 0 ||
          ((this._readableState.destroyed = u),
          (this._writableState.destroyed = u));
      },
    }),
    me
  );
}
var Te = {},
  ae = { exports: {} };
var Ye;
function yt() {
  return (
    Ye ||
      ((Ye = 1),
      (function (E, _) {
        var T = oe,
          O = T.Buffer;
        function P(a, l) {
          for (var f in a) l[f] = a[f];
        }
        O.from && O.alloc && O.allocUnsafe && O.allocUnsafeSlow
          ? (E.exports = T)
          : (P(T, _), (_.Buffer = d));
        function d(a, l, f) {
          return O(a, l, f);
        }
        ((d.prototype = Object.create(O.prototype)),
          P(O, d),
          (d.from = function (a, l, f) {
            if (typeof a == "number")
              throw new TypeError("Argument must not be a number");
            return O(a, l, f);
          }),
          (d.alloc = function (a, l, f) {
            if (typeof a != "number")
              throw new TypeError("Argument must be a number");
            var s = O(a);
            return (
              l !== void 0
                ? typeof f == "string"
                  ? s.fill(l, f)
                  : s.fill(l)
                : s.fill(0),
              s
            );
          }),
          (d.allocUnsafe = function (a) {
            if (typeof a != "number")
              throw new TypeError("Argument must be a number");
            return O(a);
          }),
          (d.allocUnsafeSlow = function (a) {
            if (typeof a != "number")
              throw new TypeError("Argument must be a number");
            return T.SlowBuffer(a);
          }));
      })(ae, ae.exports)),
    ae.exports
  );
}
var Ke;
function Xe() {
  if (Ke) return Te;
  Ke = 1;
  var E = yt().Buffer,
    _ =
      E.isEncoding ||
      function (r) {
        switch (((r = "" + r), r && r.toLowerCase())) {
          case "hex":
          case "utf8":
          case "utf-8":
          case "ascii":
          case "binary":
          case "base64":
          case "ucs2":
          case "ucs-2":
          case "utf16le":
          case "utf-16le":
          case "raw":
            return !0;
          default:
            return !1;
        }
      };
  function T(r) {
    if (!r) return "utf8";
    for (var o; ;)
      switch (r) {
        case "utf8":
        case "utf-8":
          return "utf8";
        case "ucs2":
        case "ucs-2":
        case "utf16le":
        case "utf-16le":
          return "utf16le";
        case "latin1":
        case "binary":
          return "latin1";
        case "base64":
        case "ascii":
        case "hex":
          return r;
        default:
          if (o) return;
          ((r = ("" + r).toLowerCase()), (o = !0));
      }
  }
  function O(r) {
    var o = T(r);
    if (typeof o != "string" && (E.isEncoding === _ || !_(r)))
      throw new Error("Unknown encoding: " + r);
    return o || r;
  }
  Te.StringDecoder = P;
  function P(r) {
    this.encoding = O(r);
    var o;
    switch (this.encoding) {
      case "utf16le":
        ((this.text = g), (this.end = c), (o = 4));
        break;
      case "utf8":
        ((this.fillLast = f), (o = 4));
        break;
      case "base64":
        ((this.text = M), (this.end = v), (o = 3));
        break;
      default:
        ((this.write = R), (this.end = b));
        return;
    }
    ((this.lastNeed = 0),
      (this.lastTotal = 0),
      (this.lastChar = E.allocUnsafe(o)));
  }
  ((P.prototype.write = function (r) {
    if (r.length === 0) return "";
    var o, p;
    if (this.lastNeed) {
      if (((o = this.fillLast(r)), o === void 0)) return "";
      ((p = this.lastNeed), (this.lastNeed = 0));
    } else p = 0;
    return p < r.length ? (o ? o + this.text(r, p) : this.text(r, p)) : o || "";
  }),
    (P.prototype.end = u),
    (P.prototype.text = s),
    (P.prototype.fillLast = function (r) {
      if (this.lastNeed <= r.length)
        return (
          r.copy(
            this.lastChar,
            this.lastTotal - this.lastNeed,
            0,
            this.lastNeed,
          ),
          this.lastChar.toString(this.encoding, 0, this.lastTotal)
        );
      (r.copy(this.lastChar, this.lastTotal - this.lastNeed, 0, r.length),
        (this.lastNeed -= r.length));
    }));
  function d(r) {
    return r <= 127
      ? 0
      : r >> 5 === 6
        ? 2
        : r >> 4 === 14
          ? 3
          : r >> 3 === 30
            ? 4
            : r >> 6 === 2
              ? -1
              : -2;
  }
  function a(r, o, p) {
    var w = o.length - 1;
    if (w < p) return 0;
    var S = d(o[w]);
    return S >= 0
      ? (S > 0 && (r.lastNeed = S - 1), S)
      : --w < p || S === -2
        ? 0
        : ((S = d(o[w])),
          S >= 0
            ? (S > 0 && (r.lastNeed = S - 2), S)
            : --w < p || S === -2
              ? 0
              : ((S = d(o[w])),
                S >= 0
                  ? (S > 0 && (S === 2 ? (S = 0) : (r.lastNeed = S - 3)), S)
                  : 0));
  }
  function l(r, o, p) {
    if ((o[0] & 192) !== 128) return ((r.lastNeed = 0), "�");
    if (r.lastNeed > 1 && o.length > 1) {
      if ((o[1] & 192) !== 128) return ((r.lastNeed = 1), "�");
      if (r.lastNeed > 2 && o.length > 2 && (o[2] & 192) !== 128)
        return ((r.lastNeed = 2), "�");
    }
  }
  function f(r) {
    var o = this.lastTotal - this.lastNeed,
      p = l(this, r);
    if (p !== void 0) return p;
    if (this.lastNeed <= r.length)
      return (
        r.copy(this.lastChar, o, 0, this.lastNeed),
        this.lastChar.toString(this.encoding, 0, this.lastTotal)
      );
    (r.copy(this.lastChar, o, 0, r.length), (this.lastNeed -= r.length));
  }
  function s(r, o) {
    var p = a(this, r, o);
    if (!this.lastNeed) return r.toString("utf8", o);
    this.lastTotal = p;
    var w = r.length - (p - this.lastNeed);
    return (r.copy(this.lastChar, 0, w), r.toString("utf8", o, w));
  }
  function u(r) {
    var o = r && r.length ? this.write(r) : "";
    return this.lastNeed ? o + "�" : o;
  }
  function g(r, o) {
    if ((r.length - o) % 2 === 0) {
      var p = r.toString("utf16le", o);
      if (p) {
        var w = p.charCodeAt(p.length - 1);
        if (w >= 55296 && w <= 56319)
          return (
            (this.lastNeed = 2),
            (this.lastTotal = 4),
            (this.lastChar[0] = r[r.length - 2]),
            (this.lastChar[1] = r[r.length - 1]),
            p.slice(0, -1)
          );
      }
      return p;
    }
    return (
      (this.lastNeed = 1),
      (this.lastTotal = 2),
      (this.lastChar[0] = r[r.length - 1]),
      r.toString("utf16le", o, r.length - 1)
    );
  }
  function c(r) {
    var o = r && r.length ? this.write(r) : "";
    if (this.lastNeed) {
      var p = this.lastTotal - this.lastNeed;
      return o + this.lastChar.toString("utf16le", 0, p);
    }
    return o;
  }
  function M(r, o) {
    var p = (r.length - o) % 3;
    return p === 0
      ? r.toString("base64", o)
      : ((this.lastNeed = 3 - p),
        (this.lastTotal = 3),
        p === 1
          ? (this.lastChar[0] = r[r.length - 1])
          : ((this.lastChar[0] = r[r.length - 2]),
            (this.lastChar[1] = r[r.length - 1])),
        r.toString("base64", o, r.length - p));
  }
  function v(r) {
    var o = r && r.length ? this.write(r) : "";
    return this.lastNeed
      ? o + this.lastChar.toString("base64", 0, 3 - this.lastNeed)
      : o;
  }
  function R(r) {
    return r.toString(this.encoding);
  }
  function b(r) {
    return r && r.length ? this.write(r) : "";
  }
  return Te;
}
var Me, Je;
function xe() {
  if (Je) return Me;
  Je = 1;
  var E = U().codes.ERR_STREAM_PREMATURE_CLOSE;
  function _(d) {
    var a = !1;
    return function () {
      if (!a) {
        a = !0;
        for (var l = arguments.length, f = new Array(l), s = 0; s < l; s++)
          f[s] = arguments[s];
        d.apply(this, f);
      }
    };
  }
  function T() {}
  function O(d) {
    return d.setHeader && typeof d.abort == "function";
  }
  function P(d, a, l) {
    if (typeof a == "function") return P(d, null, a);
    (a || (a = {}), (l = _(l || T)));
    var f = a.readable || (a.readable !== !1 && d.readable),
      s = a.writable || (a.writable !== !1 && d.writable),
      u = function () {
        d.writable || c();
      },
      g = d._writableState && d._writableState.finished,
      c = function () {
        ((s = !1), (g = !0), f || l.call(d));
      },
      M = d._readableState && d._readableState.endEmitted,
      v = function () {
        ((f = !1), (M = !0), s || l.call(d));
      },
      R = function (p) {
        l.call(d, p);
      },
      b = function () {
        var p;
        if (f && !M)
          return (
            (!d._readableState || !d._readableState.ended) && (p = new E()),
            l.call(d, p)
          );
        if (s && !g)
          return (
            (!d._writableState || !d._writableState.ended) && (p = new E()),
            l.call(d, p)
          );
      },
      r = function () {
        d.req.on("finish", c);
      };
    return (
      O(d)
        ? (d.on("complete", c),
          d.on("abort", b),
          d.req ? r() : d.on("request", r))
        : s && !d._writableState && (d.on("end", u), d.on("close", u)),
      d.on("end", v),
      d.on("finish", c),
      a.error !== !1 && d.on("error", R),
      d.on("close", b),
      function () {
        (d.removeListener("complete", c),
          d.removeListener("abort", b),
          d.removeListener("request", r),
          d.req && d.req.removeListener("finish", c),
          d.removeListener("end", u),
          d.removeListener("close", u),
          d.removeListener("finish", c),
          d.removeListener("end", v),
          d.removeListener("error", R),
          d.removeListener("close", b));
      }
    );
  }
  return ((Me = P), Me);
}
var Oe, Qe;
function vt() {
  if (Qe) return Oe;
  Qe = 1;
  var E;
  function _(p, w, S) {
    return (
      (w = T(w)),
      w in p
        ? Object.defineProperty(p, w, {
            value: S,
            enumerable: !0,
            configurable: !0,
            writable: !0,
          })
        : (p[w] = S),
      p
    );
  }
  function T(p) {
    var w = O(p, "string");
    return typeof w == "symbol" ? w : String(w);
  }
  function O(p, w) {
    if (typeof p != "object" || p === null) return p;
    var S = p[Symbol.toPrimitive];
    if (S !== void 0) {
      var N = S.call(p, w);
      if (typeof N != "object") return N;
      throw new TypeError("@@toPrimitive must return a primitive value.");
    }
    return (w === "string" ? String : Number)(p);
  }
  var P = xe(),
    d = Symbol("lastResolve"),
    a = Symbol("lastReject"),
    l = Symbol("error"),
    f = Symbol("ended"),
    s = Symbol("lastPromise"),
    u = Symbol("handlePromise"),
    g = Symbol("stream");
  function c(p, w) {
    return { value: p, done: w };
  }
  function M(p) {
    var w = p[d];
    if (w !== null) {
      var S = p[g].read();
      S !== null && ((p[s] = null), (p[d] = null), (p[a] = null), w(c(S, !1)));
    }
  }
  function v(p) {
    process.nextTick(M, p);
  }
  function R(p, w) {
    return function (S, N) {
      p.then(function () {
        if (w[f]) {
          S(c(void 0, !0));
          return;
        }
        w[u](S, N);
      }, N);
    };
  }
  var b = Object.getPrototypeOf(function () {}),
    r = Object.setPrototypeOf(
      ((E = {
        get stream() {
          return this[g];
        },
        next: function () {
          var w = this,
            S = this[l];
          if (S !== null) return Promise.reject(S);
          if (this[f]) return Promise.resolve(c(void 0, !0));
          if (this[g].destroyed)
            return new Promise(function (L, k) {
              process.nextTick(function () {
                w[l] ? k(w[l]) : L(c(void 0, !0));
              });
            });
          var N = this[s],
            j;
          if (N) j = new Promise(R(N, this));
          else {
            var x = this[g].read();
            if (x !== null) return Promise.resolve(c(x, !1));
            j = new Promise(this[u]);
          }
          return ((this[s] = j), j);
        },
      }),
      _(E, Symbol.asyncIterator, function () {
        return this;
      }),
      _(E, "return", function () {
        var w = this;
        return new Promise(function (S, N) {
          w[g].destroy(null, function (j) {
            if (j) {
              N(j);
              return;
            }
            S(c(void 0, !0));
          });
        });
      }),
      E),
      b,
    ),
    o = function (w) {
      var S,
        N = Object.create(
          r,
          ((S = {}),
          _(S, g, { value: w, writable: !0 }),
          _(S, d, { value: null, writable: !0 }),
          _(S, a, { value: null, writable: !0 }),
          _(S, l, { value: null, writable: !0 }),
          _(S, f, { value: w._readableState.endEmitted, writable: !0 }),
          _(S, u, {
            value: function (x, L) {
              var k = N[g].read();
              k
                ? ((N[s] = null), (N[d] = null), (N[a] = null), x(c(k, !1)))
                : ((N[d] = x), (N[a] = L));
            },
            writable: !0,
          }),
          S),
        );
      return (
        (N[s] = null),
        P(w, function (j) {
          if (j && j.code !== "ERR_STREAM_PREMATURE_CLOSE") {
            var x = N[a];
            (x !== null && ((N[s] = null), (N[d] = null), (N[a] = null), x(j)),
              (N[l] = j));
            return;
          }
          var L = N[d];
          (L !== null &&
            ((N[s] = null), (N[d] = null), (N[a] = null), L(c(void 0, !0))),
            (N[f] = !0));
        }),
        w.on("readable", v.bind(null, N)),
        N
      );
    };
  return ((Oe = o), Oe);
}
var Ae, Ze;
function wt() {
  if (Ze) return Ae;
  Ze = 1;
  function E(s, u, g, c, M, v, R) {
    try {
      var b = s[v](R),
        r = b.value;
    } catch (o) {
      g(o);
      return;
    }
    b.done ? u(r) : Promise.resolve(r).then(c, M);
  }
  function _(s) {
    return function () {
      var u = this,
        g = arguments;
      return new Promise(function (c, M) {
        var v = s.apply(u, g);
        function R(r) {
          E(v, c, M, R, b, "next", r);
        }
        function b(r) {
          E(v, c, M, R, b, "throw", r);
        }
        R(void 0);
      });
    };
  }
  function T(s, u) {
    var g = Object.keys(s);
    if (Object.getOwnPropertySymbols) {
      var c = Object.getOwnPropertySymbols(s);
      (u &&
        (c = c.filter(function (M) {
          return Object.getOwnPropertyDescriptor(s, M).enumerable;
        })),
        g.push.apply(g, c));
    }
    return g;
  }
  function O(s) {
    for (var u = 1; u < arguments.length; u++) {
      var g = arguments[u] != null ? arguments[u] : {};
      u % 2
        ? T(Object(g), !0).forEach(function (c) {
            P(s, c, g[c]);
          })
        : Object.getOwnPropertyDescriptors
          ? Object.defineProperties(s, Object.getOwnPropertyDescriptors(g))
          : T(Object(g)).forEach(function (c) {
              Object.defineProperty(
                s,
                c,
                Object.getOwnPropertyDescriptor(g, c),
              );
            });
    }
    return s;
  }
  function P(s, u, g) {
    return (
      (u = d(u)),
      u in s
        ? Object.defineProperty(s, u, {
            value: g,
            enumerable: !0,
            configurable: !0,
            writable: !0,
          })
        : (s[u] = g),
      s
    );
  }
  function d(s) {
    var u = a(s, "string");
    return typeof u == "symbol" ? u : String(u);
  }
  function a(s, u) {
    if (typeof s != "object" || s === null) return s;
    var g = s[Symbol.toPrimitive];
    if (g !== void 0) {
      var c = g.call(s, u);
      if (typeof c != "object") return c;
      throw new TypeError("@@toPrimitive must return a primitive value.");
    }
    return (u === "string" ? String : Number)(s);
  }
  var l = U().codes.ERR_INVALID_ARG_TYPE;
  function f(s, u, g) {
    var c;
    if (u && typeof u.next == "function") c = u;
    else if (u && u[Symbol.asyncIterator]) c = u[Symbol.asyncIterator]();
    else if (u && u[Symbol.iterator]) c = u[Symbol.iterator]();
    else throw new l("iterable", ["Iterable"], u);
    var M = new s(O({ objectMode: !0 }, g)),
      v = !1;
    M._read = function () {
      v || ((v = !0), R());
    };
    function R() {
      return b.apply(this, arguments);
    }
    function b() {
      return (
        (b = _(function* () {
          try {
            var r = yield c.next(),
              o = r.value,
              p = r.done;
            p ? M.push(null) : M.push(yield o) ? R() : (v = !1);
          } catch (w) {
            M.destroy(w);
          }
        })),
        b.apply(this, arguments)
      );
    }
    return M;
  }
  return ((Ae = f), Ae);
}
var Pe, ze;
function ut() {
  if (ze) return Pe;
  ((ze = 1), (Pe = L));
  var E;
  ((L.ReadableState = x), ht.EventEmitter);
  var _ = function (t, h) {
      return t.listeners(h).length;
    },
    T = at(),
    O = oe.Buffer,
    P =
      (typeof fe < "u"
        ? fe
        : typeof window < "u"
          ? window
          : typeof self < "u"
            ? self
            : {}
      ).Uint8Array || function () {};
  function d(e) {
    return O.from(e);
  }
  function a(e) {
    return O.isBuffer(e) || e instanceof P;
  }
  var l = Ce,
    f;
  l && l.debuglog ? (f = l.debuglog("stream")) : (f = function () {});
  var s = _t(),
    u = ft(),
    g = ot(),
    c = g.getHighWaterMark,
    M = U().codes,
    v = M.ERR_INVALID_ARG_TYPE,
    R = M.ERR_STREAM_PUSH_AFTER_EOF,
    b = M.ERR_METHOD_NOT_IMPLEMENTED,
    r = M.ERR_STREAM_UNSHIFT_AFTER_END_EVENT,
    o,
    p,
    w;
  J()(L, T);
  var S = u.errorOrDestroy,
    N = ["error", "close", "destroy", "pause", "resume"];
  function j(e, t, h) {
    if (typeof e.prependListener == "function") return e.prependListener(t, h);
    !e._events || !e._events[t]
      ? e.on(t, h)
      : Array.isArray(e._events[t])
        ? e._events[t].unshift(h)
        : (e._events[t] = [h, e._events[t]]);
  }
  function x(e, t, h) {
    ((E = E || Y()),
      (e = e || {}),
      typeof h != "boolean" && (h = t instanceof E),
      (this.objectMode = !!e.objectMode),
      h && (this.objectMode = this.objectMode || !!e.readableObjectMode),
      (this.highWaterMark = c(this, e, "readableHighWaterMark", h)),
      (this.buffer = new s()),
      (this.length = 0),
      (this.pipes = null),
      (this.pipesCount = 0),
      (this.flowing = null),
      (this.ended = !1),
      (this.endEmitted = !1),
      (this.reading = !1),
      (this.sync = !0),
      (this.needReadable = !1),
      (this.emittedReadable = !1),
      (this.readableListening = !1),
      (this.resumeScheduled = !1),
      (this.paused = !0),
      (this.emitClose = e.emitClose !== !1),
      (this.autoDestroy = !!e.autoDestroy),
      (this.destroyed = !1),
      (this.defaultEncoding = e.defaultEncoding || "utf8"),
      (this.awaitDrain = 0),
      (this.readingMore = !1),
      (this.decoder = null),
      (this.encoding = null),
      e.encoding &&
        (o || (o = Xe().StringDecoder),
        (this.decoder = new o(e.encoding)),
        (this.encoding = e.encoding)));
  }
  function L(e) {
    if (((E = E || Y()), !(this instanceof L))) return new L(e);
    var t = this instanceof E;
    ((this._readableState = new x(e, this, t)),
      (this.readable = !0),
      e &&
        (typeof e.read == "function" && (this._read = e.read),
        typeof e.destroy == "function" && (this._destroy = e.destroy)),
      T.call(this));
  }
  (Object.defineProperty(L.prototype, "destroyed", {
    enumerable: !1,
    get: function () {
      return this._readableState === void 0
        ? !1
        : this._readableState.destroyed;
    },
    set: function (t) {
      this._readableState && (this._readableState.destroyed = t);
    },
  }),
    (L.prototype.destroy = u.destroy),
    (L.prototype._undestroy = u.undestroy),
    (L.prototype._destroy = function (e, t) {
      t(e);
    }),
    (L.prototype.push = function (e, t) {
      var h = this._readableState,
        m;
      return (
        h.objectMode
          ? (m = !0)
          : typeof e == "string" &&
            ((t = t || h.defaultEncoding),
            t !== h.encoding && ((e = O.from(e, t)), (t = "")),
            (m = !0)),
        k(this, e, t, !1, m)
      );
    }),
    (L.prototype.unshift = function (e) {
      return k(this, e, null, !0, !1);
    }));
  function k(e, t, h, m, I) {
    f("readableAddChunk", t);
    var D = e._readableState;
    if (t === null) ((D.reading = !1), se(e, D));
    else {
      var q;
      if ((I || (q = le(D, t)), q)) S(e, q);
      else if (D.objectMode || (t && t.length > 0))
        if (
          (typeof t != "string" &&
            !D.objectMode &&
            Object.getPrototypeOf(t) !== O.prototype &&
            (t = d(t)),
          m)
        )
          D.endEmitted ? S(e, new r()) : K(e, D, t, !0);
        else if (D.ended) S(e, new R());
        else {
          if (D.destroyed) return !1;
          ((D.reading = !1),
            D.decoder && !h
              ? ((t = D.decoder.write(t)),
                D.objectMode || t.length !== 0 ? K(e, D, t, !1) : H(e, D))
              : K(e, D, t, !1));
        }
      else m || ((D.reading = !1), H(e, D));
    }
    return !D.ended && (D.length < D.highWaterMark || D.length === 0);
  }
  function K(e, t, h, m) {
    (t.flowing && t.length === 0 && !t.sync
      ? ((t.awaitDrain = 0), e.emit("data", h))
      : ((t.length += t.objectMode ? 1 : h.length),
        m ? t.buffer.unshift(h) : t.buffer.push(h),
        t.needReadable && W(e)),
      H(e, t));
  }
  function le(e, t) {
    var h;
    return (
      !a(t) &&
        typeof t != "string" &&
        t !== void 0 &&
        !e.objectMode &&
        (h = new v("chunk", ["string", "Buffer", "Uint8Array"], t)),
      h
    );
  }
  ((L.prototype.isPaused = function () {
    return this._readableState.flowing === !1;
  }),
    (L.prototype.setEncoding = function (e) {
      o || (o = Xe().StringDecoder);
      var t = new o(e);
      ((this._readableState.decoder = t),
        (this._readableState.encoding = this._readableState.decoder.encoding));
      for (var h = this._readableState.buffer.head, m = ""; h !== null;)
        ((m += t.write(h.data)), (h = h.next));
      return (
        this._readableState.buffer.clear(),
        m !== "" && this._readableState.buffer.push(m),
        (this._readableState.length = m.length),
        this
      );
    }));
  var F = 1073741824;
  function ue(e) {
    return (
      e >= F
        ? (e = F)
        : (e--,
          (e |= e >>> 1),
          (e |= e >>> 2),
          (e |= e >>> 4),
          (e |= e >>> 8),
          (e |= e >>> 16),
          e++),
      e
    );
  }
  function Q(e, t) {
    return e <= 0 || (t.length === 0 && t.ended)
      ? 0
      : t.objectMode
        ? 1
        : e !== e
          ? t.flowing && t.length
            ? t.buffer.head.data.length
            : t.length
          : (e > t.highWaterMark && (t.highWaterMark = ue(e)),
            e <= t.length
              ? e
              : t.ended
                ? t.length
                : ((t.needReadable = !0), 0));
  }
  L.prototype.read = function (e) {
    (f("read", e), (e = parseInt(e, 10)));
    var t = this._readableState,
      h = e;
    if (
      (e !== 0 && (t.emittedReadable = !1),
      e === 0 &&
        t.needReadable &&
        ((t.highWaterMark !== 0 ? t.length >= t.highWaterMark : t.length > 0) ||
          t.ended))
    )
      return (
        f("read: emitReadable", t.length, t.ended),
        t.length === 0 && t.ended ? y(this) : W(this),
        null
      );
    if (((e = Q(e, t)), e === 0 && t.ended))
      return (t.length === 0 && y(this), null);
    var m = t.needReadable;
    (f("need readable", m),
      (t.length === 0 || t.length - e < t.highWaterMark) &&
        ((m = !0), f("length less than watermark", m)),
      t.ended || t.reading
        ? ((m = !1), f("reading or ended", m))
        : m &&
          (f("do read"),
          (t.reading = !0),
          (t.sync = !0),
          t.length === 0 && (t.needReadable = !0),
          this._read(t.highWaterMark),
          (t.sync = !1),
          t.reading || (e = Q(h, t))));
    var I;
    return (
      e > 0 ? (I = n(e, t)) : (I = null),
      I === null
        ? ((t.needReadable = t.length <= t.highWaterMark), (e = 0))
        : ((t.length -= e), (t.awaitDrain = 0)),
      t.length === 0 &&
        (t.ended || (t.needReadable = !0), h !== e && t.ended && y(this)),
      I !== null && this.emit("data", I),
      I
    );
  };
  function se(e, t) {
    if ((f("onEofChunk"), !t.ended)) {
      if (t.decoder) {
        var h = t.decoder.end();
        h &&
          h.length &&
          (t.buffer.push(h), (t.length += t.objectMode ? 1 : h.length));
      }
      ((t.ended = !0),
        t.sync
          ? W(e)
          : ((t.needReadable = !1),
            t.emittedReadable || ((t.emittedReadable = !0), Z(e))));
    }
  }
  function W(e) {
    var t = e._readableState;
    (f("emitReadable", t.needReadable, t.emittedReadable),
      (t.needReadable = !1),
      t.emittedReadable ||
        (f("emitReadable", t.flowing),
        (t.emittedReadable = !0),
        process.nextTick(Z, e)));
  }
  function Z(e) {
    var t = e._readableState;
    (f("emitReadable_", t.destroyed, t.length, t.ended),
      !t.destroyed &&
        (t.length || t.ended) &&
        (e.emit("readable"), (t.emittedReadable = !1)),
      (t.needReadable = !t.flowing && !t.ended && t.length <= t.highWaterMark),
      i(e));
  }
  function H(e, t) {
    t.readingMore || ((t.readingMore = !0), process.nextTick(z, e, t));
  }
  function z(e, t) {
    for (
      ;
      !t.reading &&
      !t.ended &&
      (t.length < t.highWaterMark || (t.flowing && t.length === 0));
    ) {
      var h = t.length;
      if ((f("maybeReadMore read 0"), e.read(0), h === t.length)) break;
    }
    t.readingMore = !1;
  }
  ((L.prototype._read = function (e) {
    S(this, new b("_read()"));
  }),
    (L.prototype.pipe = function (e, t) {
      var h = this,
        m = this._readableState;
      switch (m.pipesCount) {
        case 0:
          m.pipes = e;
          break;
        case 1:
          m.pipes = [m.pipes, e];
          break;
        default:
          m.pipes.push(e);
          break;
      }
      ((m.pipesCount += 1), f("pipe count=%d opts=%j", m.pipesCount, t));
      var I =
          (!t || t.end !== !1) && e !== process.stdout && e !== process.stderr,
        D = I ? $ : X;
      (m.endEmitted ? process.nextTick(D) : h.once("end", D),
        e.on("unpipe", q));
      function q(G, V) {
        (f("onunpipe"),
          G === h && V && V.hasUnpiped === !1 && ((V.hasUnpiped = !0), dt()));
      }
      function $() {
        (f("onend"), e.end());
      }
      var te = de(h);
      e.on("drain", te);
      var qe = !1;
      function dt() {
        (f("cleanup"),
          e.removeListener("close", _e),
          e.removeListener("finish", ge),
          e.removeListener("drain", te),
          e.removeListener("error", pe),
          e.removeListener("unpipe", q),
          h.removeListener("end", $),
          h.removeListener("end", X),
          h.removeListener("data", Ie),
          (qe = !0),
          m.awaitDrain &&
            (!e._writableState || e._writableState.needDrain) &&
            te());
      }
      h.on("data", Ie);
      function Ie(G) {
        f("ondata");
        var V = e.write(G);
        (f("dest.write", V),
          V === !1 &&
            (((m.pipesCount === 1 && m.pipes === e) ||
              (m.pipesCount > 1 && C(m.pipes, e) !== -1)) &&
              !qe &&
              (f("false write response, pause", m.awaitDrain), m.awaitDrain++),
            h.pause()));
      }
      function pe(G) {
        (f("onerror", G),
          X(),
          e.removeListener("error", pe),
          _(e, "error") === 0 && S(e, G));
      }
      j(e, "error", pe);
      function _e() {
        (e.removeListener("finish", ge), X());
      }
      e.once("close", _e);
      function ge() {
        (f("onfinish"), e.removeListener("close", _e), X());
      }
      e.once("finish", ge);
      function X() {
        (f("unpipe"), h.unpipe(e));
      }
      return (
        e.emit("pipe", h),
        m.flowing || (f("pipe resume"), h.resume()),
        e
      );
    }));
  function de(e) {
    return function () {
      var h = e._readableState;
      (f("pipeOnDrain", h.awaitDrain),
        h.awaitDrain && h.awaitDrain--,
        h.awaitDrain === 0 && _(e, "data") && ((h.flowing = !0), i(e)));
    };
  }
  ((L.prototype.unpipe = function (e) {
    var t = this._readableState,
      h = { hasUnpiped: !1 };
    if (t.pipesCount === 0) return this;
    if (t.pipesCount === 1)
      return e && e !== t.pipes
        ? this
        : (e || (e = t.pipes),
          (t.pipes = null),
          (t.pipesCount = 0),
          (t.flowing = !1),
          e && e.emit("unpipe", this, h),
          this);
    if (!e) {
      var m = t.pipes,
        I = t.pipesCount;
      ((t.pipes = null), (t.pipesCount = 0), (t.flowing = !1));
      for (var D = 0; D < I; D++) m[D].emit("unpipe", this, { hasUnpiped: !1 });
      return this;
    }
    var q = C(t.pipes, e);
    return q === -1
      ? this
      : (t.pipes.splice(q, 1),
        (t.pipesCount -= 1),
        t.pipesCount === 1 && (t.pipes = t.pipes[0]),
        e.emit("unpipe", this, h),
        this);
  }),
    (L.prototype.on = function (e, t) {
      var h = T.prototype.on.call(this, e, t),
        m = this._readableState;
      return (
        e === "data"
          ? ((m.readableListening = this.listenerCount("readable") > 0),
            m.flowing !== !1 && this.resume())
          : e === "readable" &&
            !m.endEmitted &&
            !m.readableListening &&
            ((m.readableListening = m.needReadable = !0),
            (m.flowing = !1),
            (m.emittedReadable = !1),
            f("on readable", m.length, m.reading),
            m.length ? W(this) : m.reading || process.nextTick(B, this)),
        h
      );
    }),
    (L.prototype.addListener = L.prototype.on),
    (L.prototype.removeListener = function (e, t) {
      var h = T.prototype.removeListener.call(this, e, t);
      return (e === "readable" && process.nextTick(ee, this), h);
    }),
    (L.prototype.removeAllListeners = function (e) {
      var t = T.prototype.removeAllListeners.apply(this, arguments);
      return (
        (e === "readable" || e === void 0) && process.nextTick(ee, this),
        t
      );
    }));
  function ee(e) {
    var t = e._readableState;
    ((t.readableListening = e.listenerCount("readable") > 0),
      t.resumeScheduled && !t.paused
        ? (t.flowing = !0)
        : e.listenerCount("data") > 0 && e.resume());
  }
  function B(e) {
    (f("readable nexttick read 0"), e.read(0));
  }
  L.prototype.resume = function () {
    var e = this._readableState;
    return (
      e.flowing ||
        (f("resume"), (e.flowing = !e.readableListening), he(this, e)),
      (e.paused = !1),
      this
    );
  };
  function he(e, t) {
    t.resumeScheduled || ((t.resumeScheduled = !0), process.nextTick(ce, e, t));
  }
  function ce(e, t) {
    (f("resume", t.reading),
      t.reading || e.read(0),
      (t.resumeScheduled = !1),
      e.emit("resume"),
      i(e),
      t.flowing && !t.reading && e.read(0));
  }
  L.prototype.pause = function () {
    return (
      f("call pause flowing=%j", this._readableState.flowing),
      this._readableState.flowing !== !1 &&
        (f("pause"), (this._readableState.flowing = !1), this.emit("pause")),
      (this._readableState.paused = !0),
      this
    );
  };
  function i(e) {
    var t = e._readableState;
    for (f("flow", t.flowing); t.flowing && e.read() !== null;);
  }
  ((L.prototype.wrap = function (e) {
    var t = this,
      h = this._readableState,
      m = !1;
    (e.on("end", function () {
      if ((f("wrapped end"), h.decoder && !h.ended)) {
        var q = h.decoder.end();
        q && q.length && t.push(q);
      }
      t.push(null);
    }),
      e.on("data", function (q) {
        if (
          (f("wrapped data"),
          h.decoder && (q = h.decoder.write(q)),
          !(h.objectMode && q == null) && !(!h.objectMode && (!q || !q.length)))
        ) {
          var $ = t.push(q);
          $ || ((m = !0), e.pause());
        }
      }));
    for (var I in e)
      this[I] === void 0 &&
        typeof e[I] == "function" &&
        (this[I] = (function ($) {
          return function () {
            return e[$].apply(e, arguments);
          };
        })(I));
    for (var D = 0; D < N.length; D++) e.on(N[D], this.emit.bind(this, N[D]));
    return (
      (this._read = function (q) {
        (f("wrapped _read", q), m && ((m = !1), e.resume()));
      }),
      this
    );
  }),
    typeof Symbol == "function" &&
      (L.prototype[Symbol.asyncIterator] = function () {
        return (p === void 0 && (p = vt()), p(this));
      }),
    Object.defineProperty(L.prototype, "readableHighWaterMark", {
      enumerable: !1,
      get: function () {
        return this._readableState.highWaterMark;
      },
    }),
    Object.defineProperty(L.prototype, "readableBuffer", {
      enumerable: !1,
      get: function () {
        return this._readableState && this._readableState.buffer;
      },
    }),
    Object.defineProperty(L.prototype, "readableFlowing", {
      enumerable: !1,
      get: function () {
        return this._readableState.flowing;
      },
      set: function (t) {
        this._readableState && (this._readableState.flowing = t);
      },
    }),
    (L._fromList = n),
    Object.defineProperty(L.prototype, "readableLength", {
      enumerable: !1,
      get: function () {
        return this._readableState.length;
      },
    }));
  function n(e, t) {
    if (t.length === 0) return null;
    var h;
    return (
      t.objectMode
        ? (h = t.buffer.shift())
        : !e || e >= t.length
          ? (t.decoder
              ? (h = t.buffer.join(""))
              : t.buffer.length === 1
                ? (h = t.buffer.first())
                : (h = t.buffer.concat(t.length)),
            t.buffer.clear())
          : (h = t.buffer.consume(e, t.decoder)),
      h
    );
  }
  function y(e) {
    var t = e._readableState;
    (f("endReadable", t.endEmitted),
      t.endEmitted || ((t.ended = !0), process.nextTick(A, t, e)));
  }
  function A(e, t) {
    if (
      (f("endReadableNT", e.endEmitted, e.length),
      !e.endEmitted &&
        e.length === 0 &&
        ((e.endEmitted = !0), (t.readable = !1), t.emit("end"), e.autoDestroy))
    ) {
      var h = t._writableState;
      (!h || (h.autoDestroy && h.finished)) && t.destroy();
    }
  }
  typeof Symbol == "function" &&
    (L.from = function (e, t) {
      return (w === void 0 && (w = wt()), w(L, e, t));
    });
  function C(e, t) {
    for (var h = 0, m = e.length; h < m; h++) if (e[h] === t) return h;
    return -1;
  }
  return Pe;
}
var Ne, et;
function st() {
  if (et) return Ne;
  ((et = 1), (Ne = l));
  var E = U().codes,
    _ = E.ERR_METHOD_NOT_IMPLEMENTED,
    T = E.ERR_MULTIPLE_CALLBACK,
    O = E.ERR_TRANSFORM_ALREADY_TRANSFORMING,
    P = E.ERR_TRANSFORM_WITH_LENGTH_0,
    d = Y();
  J()(l, d);
  function a(u, g) {
    var c = this._transformState;
    c.transforming = !1;
    var M = c.writecb;
    if (M === null) return this.emit("error", new T());
    ((c.writechunk = null),
      (c.writecb = null),
      g != null && this.push(g),
      M(u));
    var v = this._readableState;
    ((v.reading = !1),
      (v.needReadable || v.length < v.highWaterMark) &&
        this._read(v.highWaterMark));
  }
  function l(u) {
    if (!(this instanceof l)) return new l(u);
    (d.call(this, u),
      (this._transformState = {
        afterTransform: a.bind(this),
        needTransform: !1,
        transforming: !1,
        writecb: null,
        writechunk: null,
        writeencoding: null,
      }),
      (this._readableState.needReadable = !0),
      (this._readableState.sync = !1),
      u &&
        (typeof u.transform == "function" && (this._transform = u.transform),
        typeof u.flush == "function" && (this._flush = u.flush)),
      this.on("prefinish", f));
  }
  function f() {
    var u = this;
    typeof this._flush == "function" && !this._readableState.destroyed
      ? this._flush(function (g, c) {
          s(u, g, c);
        })
      : s(this, null, null);
  }
  ((l.prototype.push = function (u, g) {
    return (
      (this._transformState.needTransform = !1),
      d.prototype.push.call(this, u, g)
    );
  }),
    (l.prototype._transform = function (u, g, c) {
      c(new _("_transform()"));
    }),
    (l.prototype._write = function (u, g, c) {
      var M = this._transformState;
      if (
        ((M.writecb = c),
        (M.writechunk = u),
        (M.writeencoding = g),
        !M.transforming)
      ) {
        var v = this._readableState;
        (M.needTransform || v.needReadable || v.length < v.highWaterMark) &&
          this._read(v.highWaterMark);
      }
    }),
    (l.prototype._read = function (u) {
      var g = this._transformState;
      g.writechunk !== null && !g.transforming
        ? ((g.transforming = !0),
          this._transform(g.writechunk, g.writeencoding, g.afterTransform))
        : (g.needTransform = !0);
    }),
    (l.prototype._destroy = function (u, g) {
      d.prototype._destroy.call(this, u, function (c) {
        g(c);
      });
    }));
  function s(u, g, c) {
    if (g) return u.emit("error", g);
    if ((c != null && u.push(c), u._writableState.length)) throw new P();
    if (u._transformState.transforming) throw new O();
    return u.push(null);
  }
  return Ne;
}
var Le, tt;
function Rt() {
  if (tt) return Le;
  ((tt = 1), (Le = _));
  var E = st();
  J()(_, E);
  function _(T) {
    if (!(this instanceof _)) return new _(T);
    E.call(this, T);
  }
  return (
    (_.prototype._transform = function (T, O, P) {
      P(null, T);
    }),
    Le
  );
}
var De, rt;
function Et() {
  if (rt) return De;
  rt = 1;
  var E;
  function _(c) {
    var M = !1;
    return function () {
      M || ((M = !0), c.apply(void 0, arguments));
    };
  }
  var T = U().codes,
    O = T.ERR_MISSING_ARGS,
    P = T.ERR_STREAM_DESTROYED;
  function d(c) {
    if (c) throw c;
  }
  function a(c) {
    return c.setHeader && typeof c.abort == "function";
  }
  function l(c, M, v, R) {
    R = _(R);
    var b = !1;
    (c.on("close", function () {
      b = !0;
    }),
      E === void 0 && (E = xe()),
      E(c, { readable: M, writable: v }, function (o) {
        if (o) return R(o);
        ((b = !0), R());
      }));
    var r = !1;
    return function (o) {
      if (!b && !r) {
        if (((r = !0), a(c))) return c.abort();
        if (typeof c.destroy == "function") return c.destroy();
        R(o || new P("pipe"));
      }
    };
  }
  function f(c) {
    c();
  }
  function s(c, M) {
    return c.pipe(M);
  }
  function u(c) {
    return !c.length || typeof c[c.length - 1] != "function" ? d : c.pop();
  }
  function g() {
    for (var c = arguments.length, M = new Array(c), v = 0; v < c; v++)
      M[v] = arguments[v];
    var R = u(M);
    if ((Array.isArray(M[0]) && (M = M[0]), M.length < 2))
      throw new O("streams");
    var b,
      r = M.map(function (o, p) {
        var w = p < M.length - 1,
          S = p > 0;
        return l(o, w, S, function (N) {
          (b || (b = N), N && r.forEach(f), !w && (r.forEach(f), R(b)));
        });
      });
    return M.reduce(s);
  }
  return ((De = g), De);
}
var nt;
function Lt() {
  return (
    nt ||
      ((nt = 1),
      (function (E, _) {
        var T = it;
        process.env.READABLE_STREAM === "disable" && T
          ? ((E.exports = T.Readable),
            Object.assign(E.exports, T),
            (E.exports.Stream = T))
          : ((_ = E.exports = ut()),
            (_.Stream = T || _),
            (_.Readable = _),
            (_.Writable = lt()),
            (_.Duplex = Y()),
            (_.Transform = st()),
            (_.PassThrough = Rt()),
            (_.finished = xe()),
            (_.pipeline = Et()));
      })(re, re.exports)),
    re.exports
  );
}
export { bt as a, Lt as b, yt as c, J as r };
//# sourceMappingURL=readable-VMWn1OrG.mjs.map
