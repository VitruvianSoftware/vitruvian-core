import O from "util";
import j from "stream";
import ae from "path";
import se from "http";
import oe from "https";
import ue from "url";
import fe from "fs";
import { r as he } from "./index-DaNOOrJg.mjs";
(function () {
  try {
    var o =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    o.SENTRY_RELEASE = { id: "4.3.209" };
    var u = new o.Error().stack;
    u &&
      ((o._sentryDebugIds = o._sentryDebugIds || {}),
      (o._sentryDebugIds[u] = "668a6790-22a7-4d1e-8d51-bdb0f3f2b01d"),
      (o._sentryDebugIdIdentifier =
        "sentry-dbid-668a6790-22a7-4d1e-8d51-bdb0f3f2b01d"));
  } catch {}
})();
var L, I;
function de() {
  if (I) return L;
  I = 1;
  var o = j.Stream,
    u = O;
  L = a;
  function a() {
    ((this.source = null),
      (this.dataSize = 0),
      (this.maxDataSize = 1024 * 1024),
      (this.pauseStream = !0),
      (this._maxDataSizeExceeded = !1),
      (this._released = !1),
      (this._bufferedEvents = []));
  }
  return (
    u.inherits(a, o),
    (a.create = function (i, t) {
      var f = new this();
      t = t || {};
      for (var s in t) f[s] = t[s];
      f.source = i;
      var p = i.emit;
      return (
        (i.emit = function () {
          return (f._handleEmit(arguments), p.apply(i, arguments));
        }),
        i.on("error", function () {}),
        f.pauseStream && i.pause(),
        f
      );
    }),
    Object.defineProperty(a.prototype, "readable", {
      configurable: !0,
      enumerable: !0,
      get: function () {
        return this.source.readable;
      },
    }),
    (a.prototype.setEncoding = function () {
      return this.source.setEncoding.apply(this.source, arguments);
    }),
    (a.prototype.resume = function () {
      (this._released || this.release(), this.source.resume());
    }),
    (a.prototype.pause = function () {
      this.source.pause();
    }),
    (a.prototype.release = function () {
      ((this._released = !0),
        this._bufferedEvents.forEach(
          function (i) {
            this.emit.apply(this, i);
          }.bind(this),
        ),
        (this._bufferedEvents = []));
    }),
    (a.prototype.pipe = function () {
      var i = o.prototype.pipe.apply(this, arguments);
      return (this.resume(), i);
    }),
    (a.prototype._handleEmit = function (i) {
      if (this._released) {
        this.emit.apply(this, i);
        return;
      }
      (i[0] === "data" &&
        ((this.dataSize += i[1].length), this._checkIfMaxDataSizeExceeded()),
        this._bufferedEvents.push(i));
    }),
    (a.prototype._checkIfMaxDataSizeExceeded = function () {
      if (!this._maxDataSizeExceeded && !(this.dataSize <= this.maxDataSize)) {
        this._maxDataSizeExceeded = !0;
        var i =
          "DelayedStream#maxDataSize of " +
          this.maxDataSize +
          " bytes exceeded.";
        this.emit("error", new Error(i));
      }
    }),
    L
  );
}
var E, P;
function pe() {
  if (P) return E;
  P = 1;
  var o = O,
    u = j.Stream,
    a = de();
  E = i;
  function i() {
    ((this.writable = !1),
      (this.readable = !0),
      (this.dataSize = 0),
      (this.maxDataSize = 2 * 1024 * 1024),
      (this.pauseStreams = !0),
      (this._released = !1),
      (this._streams = []),
      (this._currentStream = null),
      (this._insideLoop = !1),
      (this._pendingNext = !1));
  }
  return (
    o.inherits(i, u),
    (i.create = function (t) {
      var f = new this();
      t = t || {};
      for (var s in t) f[s] = t[s];
      return f;
    }),
    (i.isStreamLike = function (t) {
      return (
        typeof t != "function" &&
        typeof t != "string" &&
        typeof t != "boolean" &&
        typeof t != "number" &&
        !Buffer.isBuffer(t)
      );
    }),
    (i.prototype.append = function (t) {
      var f = i.isStreamLike(t);
      if (f) {
        if (!(t instanceof a)) {
          var s = a.create(t, {
            maxDataSize: 1 / 0,
            pauseStream: this.pauseStreams,
          });
          (t.on("data", this._checkDataSize.bind(this)), (t = s));
        }
        (this._handleErrors(t), this.pauseStreams && t.pause());
      }
      return (this._streams.push(t), this);
    }),
    (i.prototype.pipe = function (t, f) {
      return (u.prototype.pipe.call(this, t, f), this.resume(), t);
    }),
    (i.prototype._getNext = function () {
      if (((this._currentStream = null), this._insideLoop)) {
        this._pendingNext = !0;
        return;
      }
      this._insideLoop = !0;
      try {
        do ((this._pendingNext = !1), this._realGetNext());
        while (this._pendingNext);
      } finally {
        this._insideLoop = !1;
      }
    }),
    (i.prototype._realGetNext = function () {
      var t = this._streams.shift();
      if (typeof t > "u") {
        this.end();
        return;
      }
      if (typeof t != "function") {
        this._pipeNext(t);
        return;
      }
      var f = t;
      f(
        function (s) {
          var p = i.isStreamLike(s);
          (p &&
            (s.on("data", this._checkDataSize.bind(this)),
            this._handleErrors(s)),
            this._pipeNext(s));
        }.bind(this),
      );
    }),
    (i.prototype._pipeNext = function (t) {
      this._currentStream = t;
      var f = i.isStreamLike(t);
      if (f) {
        (t.on("end", this._getNext.bind(this)), t.pipe(this, { end: !1 }));
        return;
      }
      var s = t;
      (this.write(s), this._getNext());
    }),
    (i.prototype._handleErrors = function (t) {
      var f = this;
      t.on("error", function (s) {
        f._emitError(s);
      });
    }),
    (i.prototype.write = function (t) {
      this.emit("data", t);
    }),
    (i.prototype.pause = function () {
      this.pauseStreams &&
        (this.pauseStreams &&
          this._currentStream &&
          typeof this._currentStream.pause == "function" &&
          this._currentStream.pause(),
        this.emit("pause"));
    }),
    (i.prototype.resume = function () {
      (this._released ||
        ((this._released = !0), (this.writable = !0), this._getNext()),
        this.pauseStreams &&
          this._currentStream &&
          typeof this._currentStream.resume == "function" &&
          this._currentStream.resume(),
        this.emit("resume"));
    }),
    (i.prototype.end = function () {
      (this._reset(), this.emit("end"));
    }),
    (i.prototype.destroy = function () {
      (this._reset(), this.emit("close"));
    }),
    (i.prototype._reset = function () {
      ((this.writable = !1),
        (this._streams = []),
        (this._currentStream = null));
    }),
    (i.prototype._checkDataSize = function () {
      if ((this._updateDataSize(), !(this.dataSize <= this.maxDataSize))) {
        var t =
          "DelayedStream#maxDataSize of " +
          this.maxDataSize +
          " bytes exceeded.";
        this._emitError(new Error(t));
      }
    }),
    (i.prototype._updateDataSize = function () {
      this.dataSize = 0;
      var t = this;
      (this._streams.forEach(function (f) {
        f.dataSize && (t.dataSize += f.dataSize);
      }),
        this._currentStream &&
          this._currentStream.dataSize &&
          (this.dataSize += this._currentStream.dataSize));
    }),
    (i.prototype._emitError = function (t) {
      (this._reset(), this.emit("error", t));
    }),
    E
  );
}
var x, C;
function ce() {
  if (C) return x;
  ((C = 1), (x = o));
  function o(u) {
    var a =
      typeof setImmediate == "function"
        ? setImmediate
        : typeof process == "object" && typeof process.nextTick == "function"
          ? process.nextTick
          : null;
    a ? a(u) : setTimeout(u, 0);
  }
  return x;
}
var w, $;
function W() {
  if ($) return w;
  $ = 1;
  var o = ce();
  w = u;
  function u(a) {
    var i = !1;
    return (
      o(function () {
        i = !0;
      }),
      function (f, s) {
        i
          ? a(f, s)
          : o(function () {
              a(f, s);
            });
      }
    );
  }
  return w;
}
var D, K;
function X() {
  if (K) return D;
  ((K = 1), (D = o));
  function o(a) {
    (Object.keys(a.jobs).forEach(u.bind(a)), (a.jobs = {}));
  }
  function u(a) {
    typeof this.jobs[a] == "function" && this.jobs[a]();
  }
  return D;
}
var B, M;
function Z() {
  if (M) return B;
  M = 1;
  var o = W(),
    u = X();
  B = a;
  function a(t, f, s, p) {
    var c = s.keyedList ? s.keyedList[s.index] : s.index;
    s.jobs[c] = i(f, c, t[c], function (_, l) {
      c in s.jobs &&
        (delete s.jobs[c], _ ? u(s) : (s.results[c] = l), p(_, s.results));
    });
  }
  function i(t, f, s, p) {
    var c;
    return (t.length == 2 ? (c = t(s, o(p))) : (c = t(s, f, o(p))), c);
  }
  return B;
}
var q, F;
function ee() {
  if (F) return q;
  ((F = 1), (q = o));
  function o(u, a) {
    var i = !Array.isArray(u),
      t = {
        index: 0,
        keyedList: i || a ? Object.keys(u) : null,
        jobs: {},
        results: i ? {} : [],
        size: i ? Object.keys(u).length : u.length,
      };
    return (
      a &&
        t.keyedList.sort(
          i
            ? a
            : function (f, s) {
                return a(u[f], u[s]);
              },
        ),
      t
    );
  }
  return q;
}
var z, H;
function te() {
  if (H) return z;
  H = 1;
  var o = X(),
    u = W();
  z = a;
  function a(i) {
    Object.keys(this.jobs).length &&
      ((this.index = this.size), o(this), u(i)(null, this.results));
  }
  return z;
}
var k, U;
function le() {
  if (U) return k;
  U = 1;
  var o = Z(),
    u = ee(),
    a = te();
  k = i;
  function i(t, f, s) {
    for (var p = u(t); p.index < (p.keyedList || t).length;)
      (o(t, f, p, function (c, _) {
        if (c) {
          s(c, _);
          return;
        }
        if (Object.keys(p.jobs).length === 0) {
          s(null, p.results);
          return;
        }
      }),
        p.index++);
    return a.bind(p, s);
  }
  return k;
}
var b = { exports: {} },
  V;
function re() {
  if (V) return b.exports;
  V = 1;
  var o = Z(),
    u = ee(),
    a = te();
  ((b.exports = i), (b.exports.ascending = t), (b.exports.descending = f));
  function i(s, p, c, _) {
    var l = u(s, c);
    return (
      o(s, p, l, function h(e, n) {
        if (e) {
          _(e, n);
          return;
        }
        if ((l.index++, l.index < (l.keyedList || s).length)) {
          o(s, p, l, h);
          return;
        }
        _(null, l.results);
      }),
      a.bind(l, _)
    );
  }
  function t(s, p) {
    return s < p ? -1 : s > p ? 1 : 0;
  }
  function f(s, p) {
    return -1 * t(s, p);
  }
  return b.exports;
}
var T, Y;
function ye() {
  if (Y) return T;
  Y = 1;
  var o = re();
  T = u;
  function u(a, i, t) {
    return o(a, i, null, t);
  }
  return T;
}
var N, G;
function me() {
  return (
    G || ((G = 1), (N = { parallel: le(), serial: ye(), serialOrdered: re() })),
    N
  );
}
var A, J;
function _e() {
  return (
    J ||
      ((J = 1),
      (A = function (o, u) {
        return (
          Object.keys(u).forEach(function (a) {
            o[a] = o[a] || u[a];
          }),
          o
        );
      })),
    A
  );
}
var R, Q;
function De() {
  if (Q) return R;
  Q = 1;
  var o = pe(),
    u = O,
    a = ae,
    i = se,
    t = oe,
    f = ue.parse,
    s = fe,
    p = j.Stream,
    c = he(),
    _ = me(),
    l = _e();
  ((R = h), u.inherits(h, o));
  function h(e) {
    if (!(this instanceof h)) return new h(e);
    ((this._overheadLength = 0),
      (this._valueLength = 0),
      (this._valuesToMeasure = []),
      o.call(this),
      (e = e || {}));
    for (var n in e) this[n] = e[n];
  }
  return (
    (h.LINE_BREAK = `\r
`),
    (h.DEFAULT_CONTENT_TYPE = "application/octet-stream"),
    (h.prototype.append = function (e, n, r) {
      ((r = r || {}), typeof r == "string" && (r = { filename: r }));
      var d = o.prototype.append.bind(this);
      if ((typeof n == "number" && (n = "" + n), u.isArray(n))) {
        this._error(new Error("Arrays are not supported."));
        return;
      }
      var y = this._multiPartHeader(e, n, r),
        g = this._multiPartFooter();
      (d(y), d(n), d(g), this._trackLength(y, n, r));
    }),
    (h.prototype._trackLength = function (e, n, r) {
      var d = 0;
      (r.knownLength != null
        ? (d += +r.knownLength)
        : Buffer.isBuffer(n)
          ? (d = n.length)
          : typeof n == "string" && (d = Buffer.byteLength(n)),
        (this._valueLength += d),
        (this._overheadLength += Buffer.byteLength(e) + h.LINE_BREAK.length),
        !(
          !n ||
          (!n.path &&
            !(n.readable && n.hasOwnProperty("httpVersion")) &&
            !(n instanceof p))
        ) &&
          (r.knownLength || this._valuesToMeasure.push(n)));
    }),
    (h.prototype._lengthRetriever = function (e, n) {
      e.hasOwnProperty("fd")
        ? e.end != null && e.end != 1 / 0 && e.start != null
          ? n(null, e.end + 1 - (e.start ? e.start : 0))
          : s.stat(e.path, function (r, d) {
              var y;
              if (r) {
                n(r);
                return;
              }
              ((y = d.size - (e.start ? e.start : 0)), n(null, y));
            })
        : e.hasOwnProperty("httpVersion")
          ? n(null, +e.headers["content-length"])
          : e.hasOwnProperty("httpModule")
            ? (e.on("response", function (r) {
                (e.pause(), n(null, +r.headers["content-length"]));
              }),
              e.resume())
            : n("Unknown stream");
    }),
    (h.prototype._multiPartHeader = function (e, n, r) {
      if (typeof r.header == "string") return r.header;
      var d = this._getContentDisposition(n, r),
        y = this._getContentType(n, r),
        g = "",
        S = {
          "Content-Disposition": ["form-data", 'name="' + e + '"'].concat(
            d || [],
          ),
          "Content-Type": [].concat(y || []),
        };
      typeof r.header == "object" && l(S, r.header);
      var m;
      for (var v in S)
        S.hasOwnProperty(v) &&
          ((m = S[v]),
          m != null &&
            (Array.isArray(m) || (m = [m]),
            m.length && (g += v + ": " + m.join("; ") + h.LINE_BREAK)));
      return "--" + this.getBoundary() + h.LINE_BREAK + g + h.LINE_BREAK;
    }),
    (h.prototype._getContentDisposition = function (e, n) {
      var r, d;
      return (
        typeof n.filepath == "string"
          ? (r = a.normalize(n.filepath).replace(/\\/g, "/"))
          : n.filename || e.name || e.path
            ? (r = a.basename(n.filename || e.name || e.path))
            : e.readable &&
              e.hasOwnProperty("httpVersion") &&
              (r = a.basename(e.client._httpMessage.path || "")),
        r && (d = 'filename="' + r + '"'),
        d
      );
    }),
    (h.prototype._getContentType = function (e, n) {
      var r = n.contentType;
      return (
        !r && e.name && (r = c.lookup(e.name)),
        !r && e.path && (r = c.lookup(e.path)),
        !r &&
          e.readable &&
          e.hasOwnProperty("httpVersion") &&
          (r = e.headers["content-type"]),
        !r &&
          (n.filepath || n.filename) &&
          (r = c.lookup(n.filepath || n.filename)),
        !r && typeof e == "object" && (r = h.DEFAULT_CONTENT_TYPE),
        r
      );
    }),
    (h.prototype._multiPartFooter = function () {
      return function (e) {
        var n = h.LINE_BREAK,
          r = this._streams.length === 0;
        (r && (n += this._lastBoundary()), e(n));
      }.bind(this);
    }),
    (h.prototype._lastBoundary = function () {
      return "--" + this.getBoundary() + "--" + h.LINE_BREAK;
    }),
    (h.prototype.getHeaders = function (e) {
      var n,
        r = {
          "content-type": "multipart/form-data; boundary=" + this.getBoundary(),
        };
      for (n in e) e.hasOwnProperty(n) && (r[n.toLowerCase()] = e[n]);
      return r;
    }),
    (h.prototype.setBoundary = function (e) {
      this._boundary = e;
    }),
    (h.prototype.getBoundary = function () {
      return (this._boundary || this._generateBoundary(), this._boundary);
    }),
    (h.prototype.getBuffer = function () {
      for (
        var e = new Buffer.alloc(0),
          n = this.getBoundary(),
          r = 0,
          d = this._streams.length;
        r < d;
        r++
      )
        typeof this._streams[r] != "function" &&
          (Buffer.isBuffer(this._streams[r])
            ? (e = Buffer.concat([e, this._streams[r]]))
            : (e = Buffer.concat([e, Buffer.from(this._streams[r])])),
          (typeof this._streams[r] != "string" ||
            this._streams[r].substring(2, n.length + 2) !== n) &&
            (e = Buffer.concat([e, Buffer.from(h.LINE_BREAK)])));
      return Buffer.concat([e, Buffer.from(this._lastBoundary())]);
    }),
    (h.prototype._generateBoundary = function () {
      for (var e = "--------------------------", n = 0; n < 24; n++)
        e += Math.floor(Math.random() * 10).toString(16);
      this._boundary = e;
    }),
    (h.prototype.getLengthSync = function () {
      var e = this._overheadLength + this._valueLength;
      return (
        this._streams.length && (e += this._lastBoundary().length),
        this.hasKnownLength() ||
          this._error(
            new Error("Cannot calculate proper length in synchronous way."),
          ),
        e
      );
    }),
    (h.prototype.hasKnownLength = function () {
      var e = !0;
      return (this._valuesToMeasure.length && (e = !1), e);
    }),
    (h.prototype.getLength = function (e) {
      var n = this._overheadLength + this._valueLength;
      if (
        (this._streams.length && (n += this._lastBoundary().length),
        !this._valuesToMeasure.length)
      ) {
        process.nextTick(e.bind(this, null, n));
        return;
      }
      _.parallel(this._valuesToMeasure, this._lengthRetriever, function (r, d) {
        if (r) {
          e(r);
          return;
        }
        (d.forEach(function (y) {
          n += y;
        }),
          e(null, n));
      });
    }),
    (h.prototype.submit = function (e, n) {
      var r,
        d,
        y = { method: "post" };
      return (
        typeof e == "string"
          ? ((e = f(e)),
            (d = l(
              {
                port: e.port,
                path: e.pathname,
                host: e.hostname,
                protocol: e.protocol,
              },
              y,
            )))
          : ((d = l(e, y)),
            d.port || (d.port = d.protocol == "https:" ? 443 : 80)),
        (d.headers = this.getHeaders(e.headers)),
        d.protocol == "https:" ? (r = t.request(d)) : (r = i.request(d)),
        this.getLength(
          function (g, S) {
            if (g && g !== "Unknown stream") {
              this._error(g);
              return;
            }
            if ((S && r.setHeader("Content-Length", S), this.pipe(r), n)) {
              var m,
                v = function (ne, ie) {
                  return (
                    r.removeListener("error", v),
                    r.removeListener("response", m),
                    n.call(this, ne, ie)
                  );
                };
              ((m = v.bind(this, null)), r.on("error", v), r.on("response", m));
            }
          }.bind(this),
        ),
        r
      );
    }),
    (h.prototype._error = function (e) {
      this.error || ((this.error = e), this.pause(), this.emit("error", e));
    }),
    (h.prototype.toString = function () {
      return "[object FormData]";
    }),
    R
  );
}
export { De as r };
//# sourceMappingURL=form_data-B2rulTP3.mjs.map
