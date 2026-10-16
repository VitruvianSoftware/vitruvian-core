import dr, { inspect as pr, types as yt } from "util";
import Cr from "async_hooks";
import IT from "events";
import { g as Ve } from "./_commonjsHelpers-CBUqixCJ.mjs";
import { performance as DT } from "perf_hooks";
import * as K from "path";
import { normalize as gT } from "path";
import { readFileSync as UT } from "fs";
import hT from "node:module";
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
    var e = new t.Error().stack;
    e &&
      ((t._sentryDebugIds = t._sentryDebugIds || {}),
      (t._sentryDebugIds[e] = "6740550e-2d89-401e-91ad-7741c3ce8342"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-6740550e-2d89-401e-91ad-7741c3ce8342"));
  } catch {}
})();
const TC = import.meta.filename,
  SC = import.meta.dirname,
  bt = hT.createRequire(import.meta.url);
var mT = typeof globalThis == "object" ? globalThis : global,
  G = "1.9.0",
  Gt = /^(\d+)\.(\d+)\.(\d+)(-(.+))?$/;
function VT(t) {
  var e = new Set([t]),
    r = new Set(),
    n = t.match(Gt);
  if (!n)
    return function () {
      return !1;
    };
  var a = { major: +n[1], minor: +n[2], patch: +n[3], prerelease: n[4] };
  if (a.prerelease != null)
    return function (s) {
      return s === t;
    };
  function _(i) {
    return (r.add(i), !1);
  }
  function o(i) {
    return (e.add(i), !0);
  }
  return function (s) {
    if (e.has(s)) return !0;
    if (r.has(s)) return !1;
    var T = s.match(Gt);
    if (!T) return _(s);
    var E = { major: +T[1], minor: +T[2], patch: +T[3], prerelease: T[4] };
    return E.prerelease != null || a.major !== E.major
      ? _(s)
      : a.major === 0
        ? a.minor === E.minor && a.patch <= E.patch
          ? o(s)
          : _(s)
        : a.minor <= E.minor
          ? o(s)
          : _(s);
  };
}
var yT = VT(G),
  bT = G.split(".")[0],
  ie = Symbol.for("opentelemetry.js.api." + bT),
  se = mT;
function Se(t, e, r, n) {
  var a;
  n === void 0 && (n = !1);
  var _ = (se[ie] = (a = se[ie]) !== null && a !== void 0 ? a : { version: G });
  if (!n && _[t]) {
    var o = new Error(
      "@opentelemetry/api: Attempted duplicate registration of API: " + t,
    );
    return (r.error(o.stack || o.message), !1);
  }
  if (_.version !== G) {
    var o = new Error(
      "@opentelemetry/api: Registration of version v" +
        _.version +
        " for " +
        t +
        " does not match previously registered API v" +
        G,
    );
    return (r.error(o.stack || o.message), !1);
  }
  return (
    (_[t] = e),
    r.debug(
      "@opentelemetry/api: Registered a global for " + t + " v" + G + ".",
    ),
    !0
  );
}
function Y(t) {
  var e,
    r,
    n = (e = se[ie]) === null || e === void 0 ? void 0 : e.version;
  if (!(!n || !yT(n)))
    return (r = se[ie]) === null || r === void 0 ? void 0 : r[t];
}
function Ae(t, e) {
  e.debug(
    "@opentelemetry/api: Unregistering a global for " + t + " v" + G + ".",
  );
  var r = se[ie];
  r && delete r[t];
}
var GT = function (t, e) {
    var r = typeof Symbol == "function" && t[Symbol.iterator];
    if (!r) return t;
    var n = r.call(t),
      a,
      _ = [],
      o;
    try {
      for (; (e === void 0 || e-- > 0) && !(a = n.next()).done;)
        _.push(a.value);
    } catch (i) {
      o = { error: i };
    } finally {
      try {
        a && !a.done && (r = n.return) && r.call(n);
      } finally {
        if (o) throw o.error;
      }
    }
    return _;
  },
  BT = function (t, e, r) {
    if (r || arguments.length === 2)
      for (var n = 0, a = e.length, _; n < a; n++)
        (_ || !(n in e)) &&
          (_ || (_ = Array.prototype.slice.call(e, 0, n)), (_[n] = e[n]));
    return t.concat(_ || Array.prototype.slice.call(e));
  },
  wT = (function () {
    function t(e) {
      this._namespace = e.namespace || "DiagComponentLogger";
    }
    return (
      (t.prototype.debug = function () {
        for (var e = [], r = 0; r < arguments.length; r++) e[r] = arguments[r];
        return j("debug", this._namespace, e);
      }),
      (t.prototype.error = function () {
        for (var e = [], r = 0; r < arguments.length; r++) e[r] = arguments[r];
        return j("error", this._namespace, e);
      }),
      (t.prototype.info = function () {
        for (var e = [], r = 0; r < arguments.length; r++) e[r] = arguments[r];
        return j("info", this._namespace, e);
      }),
      (t.prototype.warn = function () {
        for (var e = [], r = 0; r < arguments.length; r++) e[r] = arguments[r];
        return j("warn", this._namespace, e);
      }),
      (t.prototype.verbose = function () {
        for (var e = [], r = 0; r < arguments.length; r++) e[r] = arguments[r];
        return j("verbose", this._namespace, e);
      }),
      t
    );
  })();
function j(t, e, r) {
  var n = Y("diag");
  if (n) return (r.unshift(e), n[t].apply(n, BT([], GT(r), !1)));
}
var v;
(function (t) {
  ((t[(t.NONE = 0)] = "NONE"),
    (t[(t.ERROR = 30)] = "ERROR"),
    (t[(t.WARN = 50)] = "WARN"),
    (t[(t.INFO = 60)] = "INFO"),
    (t[(t.DEBUG = 70)] = "DEBUG"),
    (t[(t.VERBOSE = 80)] = "VERBOSE"),
    (t[(t.ALL = 9999)] = "ALL"));
})(v || (v = {}));
function YT(t, e) {
  (t < v.NONE ? (t = v.NONE) : t > v.ALL && (t = v.ALL), (e = e || {}));
  function r(n, a) {
    var _ = e[n];
    return typeof _ == "function" && t >= a ? _.bind(e) : function () {};
  }
  return {
    error: r("error", v.ERROR),
    warn: r("warn", v.WARN),
    info: r("info", v.INFO),
    debug: r("debug", v.DEBUG),
    verbose: r("verbose", v.VERBOSE),
  };
}
var HT = function (t, e) {
    var r = typeof Symbol == "function" && t[Symbol.iterator];
    if (!r) return t;
    var n = r.call(t),
      a,
      _ = [],
      o;
    try {
      for (; (e === void 0 || e-- > 0) && !(a = n.next()).done;)
        _.push(a.value);
    } catch (i) {
      o = { error: i };
    } finally {
      try {
        a && !a.done && (r = n.return) && r.call(n);
      } finally {
        if (o) throw o.error;
      }
    }
    return _;
  },
  $T = function (t, e, r) {
    if (r || arguments.length === 2)
      for (var n = 0, a = e.length, _; n < a; n++)
        (_ || !(n in e)) &&
          (_ || (_ = Array.prototype.slice.call(e, 0, n)), (_[n] = e[n]));
    return t.concat(_ || Array.prototype.slice.call(e));
  },
  xT = "diag",
  g = (function () {
    function t() {
      function e(a) {
        return function () {
          for (var _ = [], o = 0; o < arguments.length; o++)
            _[o] = arguments[o];
          var i = Y("diag");
          if (i) return i[a].apply(i, $T([], HT(_), !1));
        };
      }
      var r = this,
        n = function (a, _) {
          var o, i, s;
          if ((_ === void 0 && (_ = { logLevel: v.INFO }), a === r)) {
            var T = new Error(
              "Cannot use diag as the logger for itself. Please use a DiagLogger implementation like ConsoleDiagLogger or a custom implementation",
            );
            return (
              r.error((o = T.stack) !== null && o !== void 0 ? o : T.message),
              !1
            );
          }
          typeof _ == "number" && (_ = { logLevel: _ });
          var E = Y("diag"),
            S = YT((i = _.logLevel) !== null && i !== void 0 ? i : v.INFO, a);
          if (E && !_.suppressOverrideMessage) {
            var A =
              (s = new Error().stack) !== null && s !== void 0
                ? s
                : "<failed to generate stacktrace>";
            (E.warn("Current logger will be overwritten from " + A),
              S.warn(
                "Current logger will overwrite one already registered from " +
                  A,
              ));
          }
          return Se("diag", S, r, !0);
        };
      ((r.setLogger = n),
        (r.disable = function () {
          Ae(xT, r);
        }),
        (r.createComponentLogger = function (a) {
          return new wT(a);
        }),
        (r.verbose = e("verbose")),
        (r.debug = e("debug")),
        (r.info = e("info")),
        (r.warn = e("warn")),
        (r.error = e("error")));
    }
    return (
      (t.instance = function () {
        return (this._instance || (this._instance = new t()), this._instance);
      }),
      t
    );
  })(),
  kT = function (t, e) {
    var r = typeof Symbol == "function" && t[Symbol.iterator];
    if (!r) return t;
    var n = r.call(t),
      a,
      _ = [],
      o;
    try {
      for (; (e === void 0 || e-- > 0) && !(a = n.next()).done;)
        _.push(a.value);
    } catch (i) {
      o = { error: i };
    } finally {
      try {
        a && !a.done && (r = n.return) && r.call(n);
      } finally {
        if (o) throw o.error;
      }
    }
    return _;
  },
  FT = function (t) {
    var e = typeof Symbol == "function" && Symbol.iterator,
      r = e && t[e],
      n = 0;
    if (r) return r.call(t);
    if (t && typeof t.length == "number")
      return {
        next: function () {
          return (
            t && n >= t.length && (t = void 0),
            { value: t && t[n++], done: !t }
          );
        },
      };
    throw new TypeError(
      e ? "Object is not iterable." : "Symbol.iterator is not defined.",
    );
  },
  KT = (function () {
    function t(e) {
      this._entries = e ? new Map(e) : new Map();
    }
    return (
      (t.prototype.getEntry = function (e) {
        var r = this._entries.get(e);
        if (r) return Object.assign({}, r);
      }),
      (t.prototype.getAllEntries = function () {
        return Array.from(this._entries.entries()).map(function (e) {
          var r = kT(e, 2),
            n = r[0],
            a = r[1];
          return [n, a];
        });
      }),
      (t.prototype.setEntry = function (e, r) {
        var n = new t(this._entries);
        return (n._entries.set(e, r), n);
      }),
      (t.prototype.removeEntry = function (e) {
        var r = new t(this._entries);
        return (r._entries.delete(e), r);
      }),
      (t.prototype.removeEntries = function () {
        for (var e, r, n = [], a = 0; a < arguments.length; a++)
          n[a] = arguments[a];
        var _ = new t(this._entries);
        try {
          for (var o = FT(n), i = o.next(); !i.done; i = o.next()) {
            var s = i.value;
            _._entries.delete(s);
          }
        } catch (T) {
          e = { error: T };
        } finally {
          try {
            i && !i.done && (r = o.return) && r.call(o);
          } finally {
            if (e) throw e.error;
          }
        }
        return _;
      }),
      (t.prototype.clear = function () {
        return new t();
      }),
      t
    );
  })(),
  jT = Symbol("BaggageEntryMetadata"),
  WT = g.instance();
function XT(t) {
  return (t === void 0 && (t = {}), new KT(new Map(Object.entries(t))));
}
function Lr(t) {
  return (
    typeof t != "string" &&
      (WT.error(
        "Cannot create baggage metadata from unknown type: " + typeof t,
      ),
      (t = "")),
    {
      __TYPE__: jT,
      toString: function () {
        return t;
      },
    }
  );
}
function ce(t) {
  return Symbol.for(t);
}
var qT = (function () {
    function t(e) {
      var r = this;
      ((r._currentContext = e ? new Map(e) : new Map()),
        (r.getValue = function (n) {
          return r._currentContext.get(n);
        }),
        (r.setValue = function (n, a) {
          var _ = new t(r._currentContext);
          return (_._currentContext.set(n, a), _);
        }),
        (r.deleteValue = function (n) {
          var a = new t(r._currentContext);
          return (a._currentContext.delete(n), a);
        }));
    }
    return t;
  })(),
  Ir = new qT(),
  xe = [
    { n: "error", c: "error" },
    { n: "warn", c: "warn" },
    { n: "info", c: "info" },
    { n: "debug", c: "debug" },
    { n: "verbose", c: "trace" },
  ],
  zT = (function () {
    function t() {
      function e(n) {
        return function () {
          for (var a = [], _ = 0; _ < arguments.length; _++)
            a[_] = arguments[_];
          if (console) {
            var o = console[n];
            if (
              (typeof o != "function" && (o = console.log),
              typeof o == "function")
            )
              return o.apply(console, a);
          }
        };
      }
      for (var r = 0; r < xe.length; r++) this[xe[r].n] = e(xe[r].c);
    }
    return t;
  })(),
  H = (function () {
    var t = function (e, r) {
      return (
        (t =
          Object.setPrototypeOf ||
          ({ __proto__: [] } instanceof Array &&
            function (n, a) {
              n.__proto__ = a;
            }) ||
          function (n, a) {
            for (var _ in a)
              Object.prototype.hasOwnProperty.call(a, _) && (n[_] = a[_]);
          }),
        t(e, r)
      );
    };
    return function (e, r) {
      if (typeof r != "function" && r !== null)
        throw new TypeError(
          "Class extends value " + String(r) + " is not a constructor or null",
        );
      t(e, r);
      function n() {
        this.constructor = e;
      }
      e.prototype =
        r === null ? Object.create(r) : ((n.prototype = r.prototype), new n());
    };
  })(),
  QT = (function () {
    function t() {}
    return (
      (t.prototype.createGauge = function (e, r) {
        return oS;
      }),
      (t.prototype.createHistogram = function (e, r) {
        return iS;
      }),
      (t.prototype.createCounter = function (e, r) {
        return _S;
      }),
      (t.prototype.createUpDownCounter = function (e, r) {
        return sS;
      }),
      (t.prototype.createObservableGauge = function (e, r) {
        return TS;
      }),
      (t.prototype.createObservableCounter = function (e, r) {
        return ES;
      }),
      (t.prototype.createObservableUpDownCounter = function (e, r) {
        return SS;
      }),
      (t.prototype.addBatchObservableCallback = function (e, r) {}),
      (t.prototype.removeBatchObservableCallback = function (e) {}),
      t
    );
  })(),
  ye = (function () {
    function t() {}
    return t;
  })(),
  JT = (function (t) {
    H(e, t);
    function e() {
      return (t !== null && t.apply(this, arguments)) || this;
    }
    return ((e.prototype.add = function (r, n) {}), e);
  })(ye),
  ZT = (function (t) {
    H(e, t);
    function e() {
      return (t !== null && t.apply(this, arguments)) || this;
    }
    return ((e.prototype.add = function (r, n) {}), e);
  })(ye),
  eS = (function (t) {
    H(e, t);
    function e() {
      return (t !== null && t.apply(this, arguments)) || this;
    }
    return ((e.prototype.record = function (r, n) {}), e);
  })(ye),
  tS = (function (t) {
    H(e, t);
    function e() {
      return (t !== null && t.apply(this, arguments)) || this;
    }
    return ((e.prototype.record = function (r, n) {}), e);
  })(ye),
  Rt = (function () {
    function t() {}
    return (
      (t.prototype.addCallback = function (e) {}),
      (t.prototype.removeCallback = function (e) {}),
      t
    );
  })(),
  rS = (function (t) {
    H(e, t);
    function e() {
      return (t !== null && t.apply(this, arguments)) || this;
    }
    return e;
  })(Rt),
  nS = (function (t) {
    H(e, t);
    function e() {
      return (t !== null && t.apply(this, arguments)) || this;
    }
    return e;
  })(Rt),
  aS = (function (t) {
    H(e, t);
    function e() {
      return (t !== null && t.apply(this, arguments)) || this;
    }
    return e;
  })(Rt),
  Dr = new QT(),
  _S = new JT(),
  oS = new eS(),
  iS = new tS(),
  sS = new ZT(),
  ES = new rS(),
  TS = new nS(),
  SS = new aS();
function AS() {
  return Dr;
}
var ot;
(function (t) {
  ((t[(t.INT = 0)] = "INT"), (t[(t.DOUBLE = 1)] = "DOUBLE"));
})(ot || (ot = {}));
var gr = {
    get: function (t, e) {
      if (t != null) return t[e];
    },
    keys: function (t) {
      return t == null ? [] : Object.keys(t);
    },
  },
  Ur = {
    set: function (t, e, r) {
      t != null && (t[e] = r);
    },
  },
  cS = function (t, e) {
    var r = typeof Symbol == "function" && t[Symbol.iterator];
    if (!r) return t;
    var n = r.call(t),
      a,
      _ = [],
      o;
    try {
      for (; (e === void 0 || e-- > 0) && !(a = n.next()).done;)
        _.push(a.value);
    } catch (i) {
      o = { error: i };
    } finally {
      try {
        a && !a.done && (r = n.return) && r.call(n);
      } finally {
        if (o) throw o.error;
      }
    }
    return _;
  },
  uS = function (t, e, r) {
    if (r || arguments.length === 2)
      for (var n = 0, a = e.length, _; n < a; n++)
        (_ || !(n in e)) &&
          (_ || (_ = Array.prototype.slice.call(e, 0, n)), (_[n] = e[n]));
    return t.concat(_ || Array.prototype.slice.call(e));
  },
  RS = (function () {
    function t() {}
    return (
      (t.prototype.active = function () {
        return Ir;
      }),
      (t.prototype.with = function (e, r, n) {
        for (var a = [], _ = 3; _ < arguments.length; _++)
          a[_ - 3] = arguments[_];
        return r.call.apply(r, uS([n], cS(a), !1));
      }),
      (t.prototype.bind = function (e, r) {
        return r;
      }),
      (t.prototype.enable = function () {
        return this;
      }),
      (t.prototype.disable = function () {
        return this;
      }),
      t
    );
  })(),
  lS = function (t, e) {
    var r = typeof Symbol == "function" && t[Symbol.iterator];
    if (!r) return t;
    var n = r.call(t),
      a,
      _ = [],
      o;
    try {
      for (; (e === void 0 || e-- > 0) && !(a = n.next()).done;)
        _.push(a.value);
    } catch (i) {
      o = { error: i };
    } finally {
      try {
        a && !a.done && (r = n.return) && r.call(n);
      } finally {
        if (o) throw o.error;
      }
    }
    return _;
  },
  NS = function (t, e, r) {
    if (r || arguments.length === 2)
      for (var n = 0, a = e.length, _; n < a; n++)
        (_ || !(n in e)) &&
          (_ || (_ = Array.prototype.slice.call(e, 0, n)), (_[n] = e[n]));
    return t.concat(_ || Array.prototype.slice.call(e));
  },
  ke = "context",
  OS = new RS(),
  be = (function () {
    function t() {}
    return (
      (t.getInstance = function () {
        return (this._instance || (this._instance = new t()), this._instance);
      }),
      (t.prototype.setGlobalContextManager = function (e) {
        return Se(ke, e, g.instance());
      }),
      (t.prototype.active = function () {
        return this._getContextManager().active();
      }),
      (t.prototype.with = function (e, r, n) {
        for (var a, _ = [], o = 3; o < arguments.length; o++)
          _[o - 3] = arguments[o];
        return (a = this._getContextManager()).with.apply(
          a,
          NS([e, r, n], lS(_), !1),
        );
      }),
      (t.prototype.bind = function (e, r) {
        return this._getContextManager().bind(e, r);
      }),
      (t.prototype._getContextManager = function () {
        return Y(ke) || OS;
      }),
      (t.prototype.disable = function () {
        (this._getContextManager().disable(), Ae(ke, g.instance()));
      }),
      t
    );
  })(),
  h;
(function (t) {
  ((t[(t.NONE = 0)] = "NONE"), (t[(t.SAMPLED = 1)] = "SAMPLED"));
})(h || (h = {}));
var lt = "0000000000000000",
  Nt = "00000000000000000000000000000000",
  Ot = { traceId: Nt, spanId: lt, traceFlags: h.NONE },
  ae = (function () {
    function t(e) {
      (e === void 0 && (e = Ot), (this._spanContext = e));
    }
    return (
      (t.prototype.spanContext = function () {
        return this._spanContext;
      }),
      (t.prototype.setAttribute = function (e, r) {
        return this;
      }),
      (t.prototype.setAttributes = function (e) {
        return this;
      }),
      (t.prototype.addEvent = function (e, r) {
        return this;
      }),
      (t.prototype.addLink = function (e) {
        return this;
      }),
      (t.prototype.addLinks = function (e) {
        return this;
      }),
      (t.prototype.setStatus = function (e) {
        return this;
      }),
      (t.prototype.updateName = function (e) {
        return this;
      }),
      (t.prototype.end = function (e) {}),
      (t.prototype.isRecording = function () {
        return !1;
      }),
      (t.prototype.recordException = function (e, r) {}),
      t
    );
  })(),
  vt = ce("OpenTelemetry Context Key SPAN");
function Mt(t) {
  return t.getValue(vt) || void 0;
}
function vS() {
  return Mt(be.getInstance().active());
}
function ft(t, e) {
  return t.setValue(vt, e);
}
function MS(t) {
  return t.deleteValue(vt);
}
function fS(t, e) {
  return ft(t, new ae(e));
}
function hr(t) {
  var e;
  return (e = Mt(t)) === null || e === void 0 ? void 0 : e.spanContext();
}
var PS = /^([0-9a-f]{32})$/i,
  dS = /^[0-9a-f]{16}$/i;
function Pt(t) {
  return PS.test(t) && t !== Nt;
}
function mr(t) {
  return dS.test(t) && t !== lt;
}
function ue(t) {
  return Pt(t.traceId) && mr(t.spanId);
}
function pS(t) {
  return new ae(t);
}
var Fe = be.getInstance(),
  Vr = (function () {
    function t() {}
    return (
      (t.prototype.startSpan = function (e, r, n) {
        n === void 0 && (n = Fe.active());
        var a = !!r?.root;
        if (a) return new ae();
        var _ = n && hr(n);
        return CS(_) && ue(_) ? new ae(_) : new ae();
      }),
      (t.prototype.startActiveSpan = function (e, r, n, a) {
        var _, o, i;
        if (!(arguments.length < 2)) {
          arguments.length === 2
            ? (i = r)
            : arguments.length === 3
              ? ((_ = r), (i = n))
              : ((_ = r), (o = n), (i = a));
          var s = o ?? Fe.active(),
            T = this.startSpan(e, _, s),
            E = ft(s, T);
          return Fe.with(E, i, void 0, T);
        }
      }),
      t
    );
  })();
function CS(t) {
  return (
    typeof t == "object" &&
    typeof t.spanId == "string" &&
    typeof t.traceId == "string" &&
    typeof t.traceFlags == "number"
  );
}
var LS = new Vr(),
  yr = (function () {
    function t(e, r, n, a) {
      ((this._provider = e),
        (this.name = r),
        (this.version = n),
        (this.options = a));
    }
    return (
      (t.prototype.startSpan = function (e, r, n) {
        return this._getTracer().startSpan(e, r, n);
      }),
      (t.prototype.startActiveSpan = function (e, r, n, a) {
        var _ = this._getTracer();
        return Reflect.apply(_.startActiveSpan, _, arguments);
      }),
      (t.prototype._getTracer = function () {
        if (this._delegate) return this._delegate;
        var e = this._provider.getDelegateTracer(
          this.name,
          this.version,
          this.options,
        );
        return e ? ((this._delegate = e), this._delegate) : LS;
      }),
      t
    );
  })(),
  IS = (function () {
    function t() {}
    return (
      (t.prototype.getTracer = function (e, r, n) {
        return new Vr();
      }),
      t
    );
  })(),
  DS = new IS(),
  it = (function () {
    function t() {}
    return (
      (t.prototype.getTracer = function (e, r, n) {
        var a;
        return (a = this.getDelegateTracer(e, r, n)) !== null && a !== void 0
          ? a
          : new yr(this, e, r, n);
      }),
      (t.prototype.getDelegate = function () {
        var e;
        return (e = this._delegate) !== null && e !== void 0 ? e : DS;
      }),
      (t.prototype.setDelegate = function (e) {
        this._delegate = e;
      }),
      (t.prototype.getDelegateTracer = function (e, r, n) {
        var a;
        return (a = this._delegate) === null || a === void 0
          ? void 0
          : a.getTracer(e, r, n);
      }),
      t
    );
  })(),
  Ee;
(function (t) {
  ((t[(t.NOT_RECORD = 0)] = "NOT_RECORD"),
    (t[(t.RECORD = 1)] = "RECORD"),
    (t[(t.RECORD_AND_SAMPLED = 2)] = "RECORD_AND_SAMPLED"));
})(Ee || (Ee = {}));
var pe;
(function (t) {
  ((t[(t.INTERNAL = 0)] = "INTERNAL"),
    (t[(t.SERVER = 1)] = "SERVER"),
    (t[(t.CLIENT = 2)] = "CLIENT"),
    (t[(t.PRODUCER = 3)] = "PRODUCER"),
    (t[(t.CONSUMER = 4)] = "CONSUMER"));
})(pe || (pe = {}));
var Ce;
(function (t) {
  ((t[(t.UNSET = 0)] = "UNSET"),
    (t[(t.OK = 1)] = "OK"),
    (t[(t.ERROR = 2)] = "ERROR"));
})(Ce || (Ce = {}));
var st = "[_0-9a-z-*/]",
  gS = "[a-z]" + st + "{0,255}",
  US = "[a-z0-9]" + st + "{0,240}@[a-z]" + st + "{0,13}",
  hS = new RegExp("^(?:" + gS + "|" + US + ")$"),
  mS = /^[ -~]{0,255}[!-~]$/,
  VS = /,|=/;
function yS(t) {
  return hS.test(t);
}
function bS(t) {
  return mS.test(t) && !VS.test(t);
}
var Bt = 32,
  GS = 512,
  wt = ",",
  Yt = "=",
  BS = (function () {
    function t(e) {
      ((this._internalState = new Map()), e && this._parse(e));
    }
    return (
      (t.prototype.set = function (e, r) {
        var n = this._clone();
        return (
          n._internalState.has(e) && n._internalState.delete(e),
          n._internalState.set(e, r),
          n
        );
      }),
      (t.prototype.unset = function (e) {
        var r = this._clone();
        return (r._internalState.delete(e), r);
      }),
      (t.prototype.get = function (e) {
        return this._internalState.get(e);
      }),
      (t.prototype.serialize = function () {
        var e = this;
        return this._keys()
          .reduce(function (r, n) {
            return (r.push(n + Yt + e.get(n)), r);
          }, [])
          .join(wt);
      }),
      (t.prototype._parse = function (e) {
        e.length > GS ||
          ((this._internalState = e
            .split(wt)
            .reverse()
            .reduce(function (r, n) {
              var a = n.trim(),
                _ = a.indexOf(Yt);
              if (_ !== -1) {
                var o = a.slice(0, _),
                  i = a.slice(_ + 1, n.length);
                yS(o) && bS(i) && r.set(o, i);
              }
              return r;
            }, new Map())),
          this._internalState.size > Bt &&
            (this._internalState = new Map(
              Array.from(this._internalState.entries()).reverse().slice(0, Bt),
            )));
      }),
      (t.prototype._keys = function () {
        return Array.from(this._internalState.keys()).reverse();
      }),
      (t.prototype._clone = function () {
        var e = new t();
        return ((e._internalState = new Map(this._internalState)), e);
      }),
      t
    );
  })();
function wS(t) {
  return new BS(t);
}
var B = be.getInstance(),
  c = g.instance(),
  YS = (function () {
    function t() {}
    return (
      (t.prototype.getMeter = function (e, r, n) {
        return Dr;
      }),
      t
    );
  })(),
  HS = new YS(),
  Ke = "metrics",
  $S = (function () {
    function t() {}
    return (
      (t.getInstance = function () {
        return (this._instance || (this._instance = new t()), this._instance);
      }),
      (t.prototype.setGlobalMeterProvider = function (e) {
        return Se(Ke, e, g.instance());
      }),
      (t.prototype.getMeterProvider = function () {
        return Y(Ke) || HS;
      }),
      (t.prototype.getMeter = function (e, r, n) {
        return this.getMeterProvider().getMeter(e, r, n);
      }),
      (t.prototype.disable = function () {
        Ae(Ke, g.instance());
      }),
      t
    );
  })(),
  Ge = $S.getInstance(),
  xS = (function () {
    function t() {}
    return (
      (t.prototype.inject = function (e, r) {}),
      (t.prototype.extract = function (e, r) {
        return e;
      }),
      (t.prototype.fields = function () {
        return [];
      }),
      t
    );
  })(),
  dt = ce("OpenTelemetry Baggage Key");
function br(t) {
  return t.getValue(dt) || void 0;
}
function kS() {
  return br(be.getInstance().active());
}
function FS(t, e) {
  return t.setValue(dt, e);
}
function KS(t) {
  return t.deleteValue(dt);
}
var je = "propagation",
  jS = new xS(),
  WS = (function () {
    function t() {
      ((this.createBaggage = XT),
        (this.getBaggage = br),
        (this.getActiveBaggage = kS),
        (this.setBaggage = FS),
        (this.deleteBaggage = KS));
    }
    return (
      (t.getInstance = function () {
        return (this._instance || (this._instance = new t()), this._instance);
      }),
      (t.prototype.setGlobalPropagator = function (e) {
        return Se(je, e, g.instance());
      }),
      (t.prototype.inject = function (e, r, n) {
        return (
          n === void 0 && (n = Ur),
          this._getGlobalPropagator().inject(e, r, n)
        );
      }),
      (t.prototype.extract = function (e, r, n) {
        return (
          n === void 0 && (n = gr),
          this._getGlobalPropagator().extract(e, r, n)
        );
      }),
      (t.prototype.fields = function () {
        return this._getGlobalPropagator().fields();
      }),
      (t.prototype.disable = function () {
        Ae(je, g.instance());
      }),
      (t.prototype._getGlobalPropagator = function () {
        return Y(je) || jS;
      }),
      t
    );
  })(),
  _e = WS.getInstance(),
  We = "trace",
  XS = (function () {
    function t() {
      ((this._proxyTracerProvider = new it()),
        (this.wrapSpanContext = pS),
        (this.isSpanContextValid = ue),
        (this.deleteSpan = MS),
        (this.getSpan = Mt),
        (this.getActiveSpan = vS),
        (this.getSpanContext = hr),
        (this.setSpan = ft),
        (this.setSpanContext = fS));
    }
    return (
      (t.getInstance = function () {
        return (this._instance || (this._instance = new t()), this._instance);
      }),
      (t.prototype.setGlobalTracerProvider = function (e) {
        var r = Se(We, this._proxyTracerProvider, g.instance());
        return (r && this._proxyTracerProvider.setDelegate(e), r);
      }),
      (t.prototype.getTracerProvider = function () {
        return Y(We) || this._proxyTracerProvider;
      }),
      (t.prototype.getTracer = function (e, r) {
        return this.getTracerProvider().getTracer(e, r);
      }),
      (t.prototype.disable = function () {
        (Ae(We, g.instance()), (this._proxyTracerProvider = new it()));
      }),
      t
    );
  })(),
  C = XS.getInstance();
const qS = { context: B, diag: c, metrics: Ge, propagation: _e, trace: C },
  zS = Object.freeze(
    Object.defineProperty(
      {
        __proto__: null,
        DiagConsoleLogger: zT,
        get DiagLogLevel() {
          return v;
        },
        INVALID_SPANID: lt,
        INVALID_SPAN_CONTEXT: Ot,
        INVALID_TRACEID: Nt,
        ProxyTracer: yr,
        ProxyTracerProvider: it,
        ROOT_CONTEXT: Ir,
        get SamplingDecision() {
          return Ee;
        },
        get SpanKind() {
          return pe;
        },
        get SpanStatusCode() {
          return Ce;
        },
        get TraceFlags() {
          return h;
        },
        get ValueType() {
          return ot;
        },
        baggageEntryMetadataFromString: Lr,
        context: B,
        createContextKey: ce,
        createNoopMeter: AS,
        createTraceState: wS,
        default: qS,
        defaultTextMapGetter: gr,
        defaultTextMapSetter: Ur,
        diag: c,
        isSpanContextValid: ue,
        isValidSpanId: mr,
        isValidTraceId: Pt,
        metrics: Ge,
        propagation: _e,
        trace: C,
      },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  ),
  Re = Ve(zS);
let QS = class {
  constructor(e, r, n) {}
  unhook() {}
};
class JS {
  constructor(e, r, n) {}
  unhook() {}
}
function cC() {
  throw new Error("import-in-the-middle is stubbed out (DESK-29782)");
}
var Xe, Ht;
function ZS() {
  if (Ht) return Xe;
  Ht = 1;
  var t = dr;
  function e(r, n) {
    (Error.captureStackTrace(this, e),
      (this.name = this.constructor.name),
      (this.message = r),
      (this.input = n));
  }
  return (t.inherits(e, Error), (Xe = e), Xe);
}
var qe, $t;
function eA() {
  if ($t) return qe;
  $t = 1;
  function t(a) {
    return (
      a === 34 ||
      a === 40 ||
      a === 41 ||
      a === 44 ||
      a === 47 ||
      (a >= 58 && a <= 64) ||
      (a >= 91 && a <= 93) ||
      a === 123 ||
      a === 125
    );
  }
  function e(a) {
    return (
      a === 33 ||
      (a >= 35 && a <= 39) ||
      a === 42 ||
      a === 43 ||
      a === 45 ||
      a === 46 ||
      (a >= 48 && a <= 57) ||
      (a >= 65 && a <= 90) ||
      (a >= 94 && a <= 122) ||
      a === 124 ||
      a === 126
    );
  }
  function r(a) {
    return a >= 32 && a <= 126;
  }
  function n(a) {
    return a >= 128 && a <= 255;
  }
  return (
    (qe = { isDelimiter: t, isTokenChar: e, isExtended: n, isPrint: r }),
    qe
  );
}
var ze, xt;
function uC() {
  if (xt) return ze;
  xt = 1;
  var t = dr,
    e = ZS(),
    r = eA(),
    n = r.isDelimiter,
    a = r.isTokenChar,
    _ = r.isExtended,
    o = r.isPrint;
  function i(E) {
    return E.replace(/\\(.)/g, "$1");
  }
  function s(E, S) {
    return t.format("Unexpected character '%s' at index %d", E.charAt(S), S);
  }
  function T(E) {
    for (
      var S = !1, A = !1, u = !1, M = {}, I = [], R = -1, N = -1, P, l, O = 0;
      O < E.length;
      O++
    )
      if (((l = E.charCodeAt(O)), P === void 0)) {
        if (O !== 0 && R === -1 && (l === 32 || l === 9)) continue;
        if (a(l)) R === -1 && (R = O);
        else if (l === 61 && R !== -1)
          ((P = E.slice(R, O).toLowerCase()), (R = -1));
        else throw new e(s(E, O), E);
      } else if (A && (l === 9 || o(l) || _(l))) A = !1;
      else if (a(l)) {
        if (N !== -1) throw new e(s(E, O), E);
        R === -1 && (R = O);
      } else if (n(l) || _(l))
        if (u)
          l === 34
            ? ((u = !1), (N = O))
            : l === 92
              ? (R === -1 && (R = O), (A = S = !0))
              : R === -1 && (R = O);
        else if (l === 34 && E.charCodeAt(O - 1) === 61) u = !0;
        else if ((l === 44 || l === 59) && (R !== -1 || N !== -1))
          (R !== -1
            ? (N === -1 && (N = O),
              (M[P] = S ? i(E.slice(R, N)) : E.slice(R, N)))
            : (M[P] = ""),
            l === 44 && (I.push(M), (M = {})),
            (P = void 0),
            (R = N = -1));
        else throw new e(s(E, O), E);
      else if (l === 32 || l === 9) {
        if (N !== -1) continue;
        if (u) R === -1 && (R = O);
        else if (R !== -1) N = O;
        else throw new e(s(E, O), E);
      } else throw new e(s(E, O), E);
    if (P === void 0 || u || (R === -1 && N === -1) || l === 32 || l === 9)
      throw new e("Unexpected end of input", E);
    return (
      R !== -1
        ? (N === -1 && (N = O), (M[P] = S ? i(E.slice(R, N)) : E.slice(R, N)))
        : (M[P] = ""),
      I.push(M),
      I
    );
  }
  return ((ze = T), ze);
}
const pt = ce("OpenTelemetry SDK Context Key SUPPRESS_TRACING");
function Gr(t) {
  return t.setValue(pt, !0);
}
function tA(t) {
  return t.deleteValue(pt);
}
function Be(t) {
  return t.getValue(pt) === !0;
}
const rA = "=",
  Et = ";",
  Le = ",",
  Qe = "baggage",
  nA = 180,
  aA = 4096,
  _A = 8192;
function oA(t) {
  return t.reduce((e, r) => {
    const n = `${e}${e !== "" ? Le : ""}${r}`;
    return n.length > _A ? e : n;
  }, "");
}
function iA(t) {
  return t.getAllEntries().map(([e, r]) => {
    let n = `${encodeURIComponent(e)}=${encodeURIComponent(r.value)}`;
    return (r.metadata !== void 0 && (n += Et + r.metadata.toString()), n);
  });
}
function Br(t) {
  const e = t.split(Et);
  if (e.length <= 0) return;
  const r = e.shift();
  if (!r) return;
  const n = r.indexOf(rA);
  if (n <= 0) return;
  const a = decodeURIComponent(r.substring(0, n).trim()),
    _ = decodeURIComponent(r.substring(n + 1).trim());
  let o;
  return (
    e.length > 0 && (o = Lr(e.join(Et))),
    { key: a, value: _, metadata: o }
  );
}
function sA(t) {
  const e = {};
  return (
    typeof t == "string" &&
      t.length > 0 &&
      t.split(Le).forEach((r) => {
        const n = Br(r);
        n !== void 0 && n.value.length > 0 && (e[n.key] = n.value);
      }),
    e
  );
}
class EA {
  inject(e, r, n) {
    const a = _e.getBaggage(e);
    if (!a || Be(e)) return;
    const _ = iA(a)
        .filter((i) => i.length <= aA)
        .slice(0, nA),
      o = oA(_);
    o.length > 0 && n.set(r, Qe, o);
  }
  extract(e, r, n) {
    const a = n.get(r, Qe),
      _ = Array.isArray(a) ? a.join(Le) : a;
    if (!_) return e;
    const o = {};
    return _.length === 0 ||
      (_.split(Le).forEach((s) => {
        const T = Br(s);
        if (T) {
          const E = { value: T.value };
          (T.metadata && (E.metadata = T.metadata), (o[T.key] = E));
        }
      }),
      Object.entries(o).length === 0)
      ? e
      : _e.setBaggage(e, _e.createBaggage(o));
  }
  fields() {
    return [Qe];
  }
}
class TA {
  _monotonicClock;
  _epochMillis;
  _performanceMillis;
  constructor(e, r) {
    ((this._monotonicClock = r),
      (this._epochMillis = e.now()),
      (this._performanceMillis = r.now()));
  }
  now() {
    const e = this._monotonicClock.now() - this._performanceMillis;
    return this._epochMillis + e;
  }
}
function oe(t) {
  const e = {};
  if (typeof t != "object" || t == null) return e;
  for (const [r, n] of Object.entries(t)) {
    if (!SA(r)) {
      c.warn(`Invalid attribute key: ${r}`);
      continue;
    }
    if (!Ct(n)) {
      c.warn(`Invalid attribute value set for key: ${r}`);
      continue;
    }
    Array.isArray(n) ? (e[r] = n.slice()) : (e[r] = n);
  }
  return e;
}
function SA(t) {
  return typeof t == "string" && t.length > 0;
}
function Ct(t) {
  return t == null ? !0 : Array.isArray(t) ? AA(t) : wr(t);
}
function AA(t) {
  let e;
  for (const r of t)
    if (r != null) {
      if (!e) {
        if (wr(r)) {
          e = typeof r;
          continue;
        }
        return !1;
      }
      if (typeof r !== e) return !1;
    }
  return !0;
}
function wr(t) {
  switch (typeof t) {
    case "number":
    case "boolean":
    case "string":
      return !0;
  }
  return !1;
}
function Yr() {
  return (t) => {
    c.error(cA(t));
  };
}
function cA(t) {
  return typeof t == "string" ? t : JSON.stringify(uA(t));
}
function uA(t) {
  const e = {};
  let r = t;
  for (; r !== null;)
    (Object.getOwnPropertyNames(r).forEach((n) => {
      if (e[n]) return;
      const a = r[n];
      a && (e[n] = String(a));
    }),
      (r = Object.getPrototypeOf(r)));
  return e;
}
let Hr = Yr();
function RA(t) {
  Hr = t;
}
function Lt(t) {
  try {
    Hr(t);
  } catch {}
}
function p(t) {
  const e = process.env[t];
  if (e == null || e.trim() === "") return;
  const r = Number(e);
  if (isNaN(r)) {
    c.warn(
      `Unknown value ${pr(e)} for ${t}, expected a number, using defaults`,
    );
    return;
  }
  return r;
}
function It(t) {
  const e = process.env[t];
  if (!(e == null || e.trim() === "")) return e;
}
function lA(t) {
  const e = process.env[t]?.trim().toLowerCase();
  return e == null || e === ""
    ? !1
    : e === "true"
      ? !0
      : (e === "false" ||
          c.warn(
            `Unknown value ${pr(e)} for ${t}, expected 'true' or 'false', falling back to 'false' (default)`,
          ),
        !1);
}
function NA(t) {
  return It(t)
    ?.split(",")
    .map((e) => e.trim())
    .filter((e) => e !== "");
}
const OA = typeof globalThis == "object" ? globalThis : global,
  w = DT,
  vA = "2.1.0",
  MA = "telemetry.sdk.language",
  fA = "nodejs",
  PA = "telemetry.sdk.name",
  dA = "telemetry.sdk.version",
  pA = "process.runtime.name",
  Me = { [PA]: "opentelemetry", [pA]: "node", [MA]: fA, [dA]: vA };
function CA(t) {
  t.unref();
}
const $r = 9,
  LA = 6,
  IA = Math.pow(10, LA),
  Ie = Math.pow(10, $r);
function U(t) {
  const e = t / 1e3,
    r = Math.trunc(e),
    n = Math.round((t % 1e3) * IA);
  return [r, n];
}
function we() {
  let t = w.timeOrigin;
  if (typeof t != "number") {
    const e = w;
    t = e.timing && e.timing.fetchStart;
  }
  return t;
}
function Dt(t) {
  const e = U(we()),
    r = U(typeof t == "number" ? t : w.now());
  return gt(e, r);
}
function DA(t) {
  if (Ye(t)) return t;
  if (typeof t == "number") return t < we() ? Dt(t) : U(t);
  if (t instanceof Date) return U(t.getTime());
  throw TypeError("Invalid input type");
}
function xr(t, e) {
  let r = e[0] - t[0],
    n = e[1] - t[1];
  return (n < 0 && ((r -= 1), (n += Ie)), [r, n]);
}
function gA(t) {
  const e = $r,
    r = `${"0".repeat(e)}${t[1]}Z`,
    n = r.substring(r.length - e - 1);
  return new Date(t[0] * 1e3).toISOString().replace("000Z", n);
}
function UA(t) {
  return t[0] * Ie + t[1];
}
function hA(t) {
  return t[0] * 1e3 + t[1] / 1e6;
}
function mA(t) {
  return t[0] * 1e6 + t[1] / 1e3;
}
function Ye(t) {
  return (
    Array.isArray(t) &&
    t.length === 2 &&
    typeof t[0] == "number" &&
    typeof t[1] == "number"
  );
}
function Tt(t) {
  return Ye(t) || typeof t == "number" || t instanceof Date;
}
function gt(t, e) {
  const r = [t[0] + e[0], t[1] + e[1]];
  return (r[1] >= Ie && ((r[1] -= Ie), (r[0] += 1)), r);
}
var St;
(function (t) {
  ((t[(t.SUCCESS = 0)] = "SUCCESS"), (t[(t.FAILED = 1)] = "FAILED"));
})(St || (St = {}));
class VA {
  _propagators;
  _fields;
  constructor(e = {}) {
    ((this._propagators = e.propagators ?? []),
      (this._fields = Array.from(
        new Set(
          this._propagators
            .map((r) => (typeof r.fields == "function" ? r.fields() : []))
            .reduce((r, n) => r.concat(n), []),
        ),
      )));
  }
  inject(e, r, n) {
    for (const a of this._propagators)
      try {
        a.inject(e, r, n);
      } catch (_) {
        c.warn(
          `Failed to inject with ${a.constructor.name}. Err: ${_.message}`,
        );
      }
  }
  extract(e, r, n) {
    return this._propagators.reduce((a, _) => {
      try {
        return _.extract(a, r, n);
      } catch (o) {
        c.warn(
          `Failed to extract with ${_.constructor.name}. Err: ${o.message}`,
        );
      }
      return a;
    }, e);
  }
  fields() {
    return this._fields.slice();
  }
}
const At = "[_0-9a-z-*/]",
  yA = `[a-z]${At}{0,255}`,
  bA = `[a-z0-9]${At}{0,240}@[a-z]${At}{0,13}`,
  GA = new RegExp(`^(?:${yA}|${bA})$`),
  BA = /^[ -~]{0,255}[!-~]$/,
  wA = /,|=/;
function YA(t) {
  return GA.test(t);
}
function HA(t) {
  return BA.test(t) && !wA.test(t);
}
const kt = 32,
  $A = 512,
  Ft = ",",
  Kt = "=";
class He {
  _internalState = new Map();
  constructor(e) {
    e && this._parse(e);
  }
  set(e, r) {
    const n = this._clone();
    return (
      n._internalState.has(e) && n._internalState.delete(e),
      n._internalState.set(e, r),
      n
    );
  }
  unset(e) {
    const r = this._clone();
    return (r._internalState.delete(e), r);
  }
  get(e) {
    return this._internalState.get(e);
  }
  serialize() {
    return this._keys()
      .reduce((e, r) => (e.push(r + Kt + this.get(r)), e), [])
      .join(Ft);
  }
  _parse(e) {
    e.length > $A ||
      ((this._internalState = e
        .split(Ft)
        .reverse()
        .reduce((r, n) => {
          const a = n.trim(),
            _ = a.indexOf(Kt);
          if (_ !== -1) {
            const o = a.slice(0, _),
              i = a.slice(_ + 1, n.length);
            YA(o) && HA(i) && r.set(o, i);
          }
          return r;
        }, new Map())),
      this._internalState.size > kt &&
        (this._internalState = new Map(
          Array.from(this._internalState.entries()).reverse().slice(0, kt),
        )));
  }
  _keys() {
    return Array.from(this._internalState.keys()).reverse();
  }
  _clone() {
    const e = new He();
    return ((e._internalState = new Map(this._internalState)), e);
  }
}
const fe = "traceparent",
  Pe = "tracestate",
  xA = "00",
  kA = "(?!ff)[\\da-f]{2}",
  FA = "(?![0]{32})[\\da-f]{32}",
  KA = "(?![0]{16})[\\da-f]{16}",
  jA = "[\\da-f]{2}",
  WA = new RegExp(`^\\s?(${kA})-(${FA})-(${KA})-(${jA})(-.*)?\\s?$`);
function kr(t) {
  const e = WA.exec(t);
  return !e || (e[1] === "00" && e[5])
    ? null
    : { traceId: e[2], spanId: e[3], traceFlags: parseInt(e[4], 16) };
}
class XA {
  inject(e, r, n) {
    const a = C.getSpanContext(e);
    if (!a || Be(e) || !ue(a)) return;
    const _ = `${xA}-${a.traceId}-${a.spanId}-0${Number(a.traceFlags || h.NONE).toString(16)}`;
    (n.set(r, fe, _), a.traceState && n.set(r, Pe, a.traceState.serialize()));
  }
  extract(e, r, n) {
    const a = n.get(r, fe);
    if (!a) return e;
    const _ = Array.isArray(a) ? a[0] : a;
    if (typeof _ != "string") return e;
    const o = kr(_);
    if (!o) return e;
    o.isRemote = !0;
    const i = n.get(r, Pe);
    if (i) {
      const s = Array.isArray(i) ? i.join(",") : i;
      o.traceState = new He(typeof s == "string" ? s : void 0);
    }
    return C.setSpanContext(e, o);
  }
  fields() {
    return [fe, Pe];
  }
}
const Ut = ce("OpenTelemetry SDK Context Key RPC_METADATA");
var ct;
(function (t) {
  t.HTTP = "http";
})(ct || (ct = {}));
function qA(t, e) {
  return t.setValue(Ut, e);
}
function zA(t) {
  return t.deleteValue(Ut);
}
function QA(t) {
  return t.getValue(Ut);
}
const JA = "[object Object]",
  ZA = "[object Null]",
  ec = "[object Undefined]",
  tc = Function.prototype,
  Fr = tc.toString,
  rc = Fr.call(Object),
  nc = Object.getPrototypeOf,
  Kr = Object.prototype,
  jr = Kr.hasOwnProperty,
  y = Symbol ? Symbol.toStringTag : void 0,
  Wr = Kr.toString;
function jt(t) {
  if (!ac(t) || _c(t) !== JA) return !1;
  const e = nc(t);
  if (e === null) return !0;
  const r = jr.call(e, "constructor") && e.constructor;
  return typeof r == "function" && r instanceof r && Fr.call(r) === rc;
}
function ac(t) {
  return t != null && typeof t == "object";
}
function _c(t) {
  return t == null
    ? t === void 0
      ? ec
      : ZA
    : y && y in Object(t)
      ? oc(t)
      : ic(t);
}
function oc(t) {
  const e = jr.call(t, y),
    r = t[y];
  let n = !1;
  try {
    ((t[y] = void 0), (n = !0));
  } catch {}
  const a = Wr.call(t);
  return (n && (e ? (t[y] = r) : delete t[y]), a);
}
function ic(t) {
  return Wr.call(t);
}
const sc = 20;
function Xr(...t) {
  let e = t.shift();
  const r = new WeakMap();
  for (; t.length > 0;) e = qr(e, t.shift(), 0, r);
  return e;
}
function Je(t) {
  return De(t) ? t.slice() : t;
}
function qr(t, e, r = 0, n) {
  let a;
  if (!(r > sc)) {
    if ((r++, de(t) || de(e) || zr(e))) a = Je(e);
    else if (De(t)) {
      if (((a = t.slice()), De(e)))
        for (let _ = 0, o = e.length; _ < o; _++) a.push(Je(e[_]));
      else if (W(e)) {
        const _ = Object.keys(e);
        for (let o = 0, i = _.length; o < i; o++) {
          const s = _[o];
          a[s] = Je(e[s]);
        }
      }
    } else if (W(t))
      if (W(e)) {
        if (!Ec(t, e)) return e;
        a = Object.assign({}, t);
        const _ = Object.keys(e);
        for (let o = 0, i = _.length; o < i; o++) {
          const s = _[o],
            T = e[s];
          if (de(T)) typeof T > "u" ? delete a[s] : (a[s] = T);
          else {
            const E = a[s],
              S = T;
            if (Wt(t, s, n) || Wt(e, s, n)) delete a[s];
            else {
              if (W(E) && W(S)) {
                const A = n.get(E) || [],
                  u = n.get(S) || [];
                (A.push({ obj: t, key: s }),
                  u.push({ obj: e, key: s }),
                  n.set(E, A),
                  n.set(S, u));
              }
              a[s] = qr(a[s], T, r, n);
            }
          }
        }
      } else a = e;
    return a;
  }
}
function Wt(t, e, r) {
  const n = r.get(t[e]) || [];
  for (let a = 0, _ = n.length; a < _; a++) {
    const o = n[a];
    if (o.key === e && o.obj === t) return !0;
  }
  return !1;
}
function De(t) {
  return Array.isArray(t);
}
function zr(t) {
  return typeof t == "function";
}
function W(t) {
  return !de(t) && !De(t) && !zr(t) && typeof t == "object";
}
function de(t) {
  return (
    typeof t == "string" ||
    typeof t == "number" ||
    typeof t == "boolean" ||
    typeof t > "u" ||
    t instanceof Date ||
    t instanceof RegExp ||
    t === null
  );
}
function Ec(t, e) {
  return !(!jt(t) || !jt(e));
}
class $e extends Error {
  constructor(e) {
    (super(e), Object.setPrototypeOf(this, $e.prototype));
  }
}
function Tc(t, e) {
  let r;
  const n = new Promise(function (_, o) {
    r = setTimeout(function () {
      o(new $e("Operation timed out."));
    }, e);
  });
  return Promise.race([t, n]).then(
    (a) => (clearTimeout(r), a),
    (a) => {
      throw (clearTimeout(r), a);
    },
  );
}
function Qr(t, e) {
  return typeof e == "string" ? t === e : !!t.match(e);
}
function Sc(t, e) {
  if (!e) return !1;
  for (const r of e) if (Qr(t, r)) return !0;
  return !1;
}
class Ac {
  _promise;
  _resolve;
  _reject;
  constructor() {
    this._promise = new Promise((e, r) => {
      ((this._resolve = e), (this._reject = r));
    });
  }
  get promise() {
    return this._promise;
  }
  resolve(e) {
    this._resolve(e);
  }
  reject(e) {
    this._reject(e);
  }
}
class cc {
  _callback;
  _that;
  _isCalled = !1;
  _deferred = new Ac();
  constructor(e, r) {
    ((this._callback = e), (this._that = r));
  }
  get isCalled() {
    return this._isCalled;
  }
  get promise() {
    return this._deferred.promise;
  }
  call(...e) {
    if (!this._isCalled) {
      this._isCalled = !0;
      try {
        Promise.resolve(this._callback.call(this._that, ...e)).then(
          (r) => this._deferred.resolve(r),
          (r) => this._deferred.reject(r),
        );
      } catch (r) {
        this._deferred.reject(r);
      }
    }
    return this._deferred.promise;
  }
}
const Xt = {
  ALL: v.ALL,
  VERBOSE: v.VERBOSE,
  DEBUG: v.DEBUG,
  INFO: v.INFO,
  WARN: v.WARN,
  ERROR: v.ERROR,
  NONE: v.NONE,
};
function uc(t) {
  if (t == null) return;
  const e = Xt[t.toUpperCase()];
  return (
    e ??
    (c.warn(
      `Unknown log level "${t}", expected one of ${Object.keys(Xt)}, using default`,
    ),
    v.INFO)
  );
}
function Rc(t, e) {
  return new Promise((r) => {
    B.with(Gr(B.active()), () => {
      t.export(e, (n) => {
        r(n);
      });
    });
  });
}
const lc = { _export: Rc },
  Nc = Object.freeze(
    Object.defineProperty(
      {
        __proto__: null,
        AnchoredClock: TA,
        BindOnceFuture: cc,
        CompositePropagator: VA,
        get ExportResultCode() {
          return St;
        },
        get RPCType() {
          return ct;
        },
        SDK_INFO: Me,
        TRACE_PARENT_HEADER: fe,
        TRACE_STATE_HEADER: Pe,
        TimeoutError: $e,
        TraceState: He,
        W3CBaggagePropagator: EA,
        W3CTraceContextPropagator: XA,
        _globalThis: OA,
        addHrTimes: gt,
        callWithTimeout: Tc,
        deleteRPCMetadata: zA,
        diagLogLevelFromString: uc,
        getBooleanFromEnv: lA,
        getNumberFromEnv: p,
        getRPCMetadata: QA,
        getStringFromEnv: It,
        getStringListFromEnv: NA,
        getTimeOrigin: we,
        globalErrorHandler: Lt,
        hrTime: Dt,
        hrTimeDuration: xr,
        hrTimeToMicroseconds: mA,
        hrTimeToMilliseconds: hA,
        hrTimeToNanoseconds: UA,
        hrTimeToTimeStamp: gA,
        internal: lc,
        isAttributeValue: Ct,
        isTimeInput: Tt,
        isTimeInputHrTime: Ye,
        isTracingSuppressed: Be,
        isUrlIgnored: Sc,
        loggingErrorHandler: Yr,
        merge: Xr,
        millisToHrTime: U,
        otperformance: w,
        parseKeyPairsIntoRecord: sA,
        parseTraceParent: kr,
        sanitizeAttributes: oe,
        setGlobalErrorHandler: RA,
        setRPCMetadata: qA,
        suppressTracing: Gr,
        timeInputToHrTime: DA,
        unrefTimer: CA,
        unsuppressTracing: tA,
        urlMatches: Qr,
      },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  ),
  Oc = "service.name",
  qt = "telemetry.sdk.language",
  zt = "telemetry.sdk.name",
  Qt = "telemetry.sdk.version";
function vc() {
  return `unknown_service:${process.argv0}`;
}
const ne = (t) =>
  t !== null && typeof t == "object" && typeof t.then == "function";
class ge {
  _rawAttributes;
  _asyncAttributesPending = !1;
  _schemaUrl;
  _memoizedAttributes;
  static FromAttributeList(e, r) {
    const n = new ge({}, r);
    return (
      (n._rawAttributes = Jt(e)),
      (n._asyncAttributesPending = e.filter(([a, _]) => ne(_)).length > 0),
      n
    );
  }
  constructor(e, r) {
    const n = e.attributes ?? {};
    ((this._rawAttributes = Object.entries(n).map(
      ([a, _]) => (ne(_) && (this._asyncAttributesPending = !0), [a, _]),
    )),
      (this._rawAttributes = Jt(this._rawAttributes)),
      (this._schemaUrl = Pc(r?.schemaUrl)));
  }
  get asyncAttributesPending() {
    return this._asyncAttributesPending;
  }
  async waitForAsyncAttributes() {
    if (this.asyncAttributesPending) {
      for (let e = 0; e < this._rawAttributes.length; e++) {
        const [r, n] = this._rawAttributes[e];
        this._rawAttributes[e] = [r, ne(n) ? await n : n];
      }
      this._asyncAttributesPending = !1;
    }
  }
  get attributes() {
    if (
      (this.asyncAttributesPending &&
        c.error(
          "Accessing resource attributes before async attributes settled",
        ),
      this._memoizedAttributes)
    )
      return this._memoizedAttributes;
    const e = {};
    for (const [r, n] of this._rawAttributes) {
      if (ne(n)) {
        c.debug(`Unsettled resource attribute ${r} skipped`);
        continue;
      }
      n != null && (e[r] ??= n);
    }
    return (this._asyncAttributesPending || (this._memoizedAttributes = e), e);
  }
  getRawAttributes() {
    return this._rawAttributes;
  }
  get schemaUrl() {
    return this._schemaUrl;
  }
  merge(e) {
    if (e == null) return this;
    const r = dc(this, e),
      n = r ? { schemaUrl: r } : void 0;
    return ge.FromAttributeList(
      [...e.getRawAttributes(), ...this.getRawAttributes()],
      n,
    );
  }
}
function Mc(t, e) {
  return ge.FromAttributeList(Object.entries(t), e);
}
function fc() {
  return Mc({ [Oc]: vc(), [qt]: Me[qt], [zt]: Me[zt], [Qt]: Me[Qt] });
}
function Jt(t) {
  return t.map(([e, r]) =>
    ne(r)
      ? [
          e,
          r.catch((n) => {
            c.debug("promise rejection for resource attribute: %s - %s", e, n);
          }),
        ]
      : [e, r],
  );
}
function Pc(t) {
  if (typeof t == "string" || t === void 0) return t;
  c.warn(
    "Schema URL must be string or undefined, got %s. Schema URL will be ignored.",
    t,
  );
}
function dc(t, e) {
  const r = t?.schemaUrl,
    n = e?.schemaUrl,
    a = r === void 0 || r === "",
    _ = n === void 0 || n === "";
  if (a) return n;
  if (_ || r === n) return r;
  c.warn(
    'Schema URL merge conflict: old resource has "%s", updating resource has "%s". Resulting resource will have undefined Schema URL.',
    r,
    n,
  );
}
const Ze = "exception.message",
  pc = "exception.stacktrace",
  et = "exception.type",
  Cc = "exception";
class Lc {
  _spanContext;
  kind;
  parentSpanContext;
  attributes = {};
  links = [];
  events = [];
  startTime;
  resource;
  instrumentationScope;
  _droppedAttributesCount = 0;
  _droppedEventsCount = 0;
  _droppedLinksCount = 0;
  name;
  status = { code: Ce.UNSET };
  endTime = [0, 0];
  _ended = !1;
  _duration = [-1, -1];
  _spanProcessor;
  _spanLimits;
  _attributeValueLengthLimit;
  _performanceStartTime;
  _performanceOffset;
  _startTimeProvided;
  constructor(e) {
    const r = Date.now();
    ((this._spanContext = e.spanContext),
      (this._performanceStartTime = w.now()),
      (this._performanceOffset = r - (this._performanceStartTime + we())),
      (this._startTimeProvided = e.startTime != null),
      (this._spanLimits = e.spanLimits),
      (this._attributeValueLengthLimit =
        this._spanLimits.attributeValueLengthLimit || 0),
      (this._spanProcessor = e.spanProcessor),
      (this.name = e.name),
      (this.parentSpanContext = e.parentSpanContext),
      (this.kind = e.kind),
      (this.links = e.links || []),
      (this.startTime = this._getTime(e.startTime ?? r)),
      (this.resource = e.resource),
      (this.instrumentationScope = e.scope),
      e.attributes != null && this.setAttributes(e.attributes),
      this._spanProcessor.onStart(this, e.context));
  }
  spanContext() {
    return this._spanContext;
  }
  setAttribute(e, r) {
    if (r == null || this._isSpanEnded()) return this;
    if (e.length === 0) return (c.warn(`Invalid attribute key: ${e}`), this);
    if (!Ct(r))
      return (c.warn(`Invalid attribute value set for key: ${e}`), this);
    const { attributeCountLimit: n } = this._spanLimits;
    return n !== void 0 &&
      Object.keys(this.attributes).length >= n &&
      !Object.prototype.hasOwnProperty.call(this.attributes, e)
      ? (this._droppedAttributesCount++, this)
      : ((this.attributes[e] = this._truncateToSize(r)), this);
  }
  setAttributes(e) {
    for (const [r, n] of Object.entries(e)) this.setAttribute(r, n);
    return this;
  }
  addEvent(e, r, n) {
    if (this._isSpanEnded()) return this;
    const { eventCountLimit: a } = this._spanLimits;
    if (a === 0)
      return (c.warn("No events allowed."), this._droppedEventsCount++, this);
    (a !== void 0 &&
      this.events.length >= a &&
      (this._droppedEventsCount === 0 && c.debug("Dropping extra events."),
      this.events.shift(),
      this._droppedEventsCount++),
      Tt(r) && (Tt(n) || (n = r), (r = void 0)));
    const _ = oe(r);
    return (
      this.events.push({
        name: e,
        attributes: _,
        time: this._getTime(n),
        droppedAttributesCount: 0,
      }),
      this
    );
  }
  addLink(e) {
    return (this.links.push(e), this);
  }
  addLinks(e) {
    return (this.links.push(...e), this);
  }
  setStatus(e) {
    return this._isSpanEnded()
      ? this
      : ((this.status = { ...e }),
        this.status.message != null &&
          typeof e.message != "string" &&
          (c.warn(
            `Dropping invalid status.message of type '${typeof e.message}', expected 'string'`,
          ),
          delete this.status.message),
        this);
  }
  updateName(e) {
    return this._isSpanEnded() ? this : ((this.name = e), this);
  }
  end(e) {
    if (this._isSpanEnded()) {
      c.error(
        `${this.name} ${this._spanContext.traceId}-${this._spanContext.spanId} - You can only call end() on a span once.`,
      );
      return;
    }
    ((this._ended = !0),
      (this.endTime = this._getTime(e)),
      (this._duration = xr(this.startTime, this.endTime)),
      this._duration[0] < 0 &&
        (c.warn(
          "Inconsistent start and end time, startTime > endTime. Setting span duration to 0ms.",
          this.startTime,
          this.endTime,
        ),
        (this.endTime = this.startTime.slice()),
        (this._duration = [0, 0])),
      this._droppedEventsCount > 0 &&
        c.warn(
          `Dropped ${this._droppedEventsCount} events because eventCountLimit reached`,
        ),
      this._spanProcessor.onEnd(this));
  }
  _getTime(e) {
    if (typeof e == "number" && e <= w.now())
      return Dt(e + this._performanceOffset);
    if (typeof e == "number") return U(e);
    if (e instanceof Date) return U(e.getTime());
    if (Ye(e)) return e;
    if (this._startTimeProvided) return U(Date.now());
    const r = w.now() - this._performanceStartTime;
    return gt(this.startTime, U(r));
  }
  isRecording() {
    return this._ended === !1;
  }
  recordException(e, r) {
    const n = {};
    (typeof e == "string"
      ? (n[Ze] = e)
      : e &&
        (e.code ? (n[et] = e.code.toString()) : e.name && (n[et] = e.name),
        e.message && (n[Ze] = e.message),
        e.stack && (n[pc] = e.stack)),
      n[et] || n[Ze]
        ? this.addEvent(Cc, n, r)
        : c.warn(`Failed to record an exception ${e}`));
  }
  get duration() {
    return this._duration;
  }
  get ended() {
    return this._ended;
  }
  get droppedAttributesCount() {
    return this._droppedAttributesCount;
  }
  get droppedEventsCount() {
    return this._droppedEventsCount;
  }
  get droppedLinksCount() {
    return this._droppedLinksCount;
  }
  _isSpanEnded() {
    if (this._ended) {
      const e = new Error(
        `Operation attempted on ended Span {traceId: ${this._spanContext.traceId}, spanId: ${this._spanContext.spanId}}`,
      );
      c.warn(
        `Cannot execute the operation on ended Span {traceId: ${this._spanContext.traceId}, spanId: ${this._spanContext.spanId}}`,
        e,
      );
    }
    return this._ended;
  }
  _truncateToLimitUtil(e, r) {
    return e.length <= r ? e : e.substring(0, r);
  }
  _truncateToSize(e) {
    const r = this._attributeValueLengthLimit;
    return r <= 0
      ? (c.warn(`Attribute value limit must be positive, got ${r}`), e)
      : typeof e == "string"
        ? this._truncateToLimitUtil(e, r)
        : Array.isArray(e)
          ? e.map((n) =>
              typeof n == "string" ? this._truncateToLimitUtil(n, r) : n,
            )
          : e;
  }
}
var k;
(function (t) {
  ((t[(t.NOT_RECORD = 0)] = "NOT_RECORD"),
    (t[(t.RECORD = 1)] = "RECORD"),
    (t[(t.RECORD_AND_SAMPLED = 2)] = "RECORD_AND_SAMPLED"));
})(k || (k = {}));
class Ue {
  shouldSample() {
    return { decision: k.NOT_RECORD };
  }
  toString() {
    return "AlwaysOffSampler";
  }
}
class $ {
  shouldSample() {
    return { decision: k.RECORD_AND_SAMPLED };
  }
  toString() {
    return "AlwaysOnSampler";
  }
}
class le {
  _root;
  _remoteParentSampled;
  _remoteParentNotSampled;
  _localParentSampled;
  _localParentNotSampled;
  constructor(e) {
    ((this._root = e.root),
      this._root ||
        (Lt(
          new Error("ParentBasedSampler must have a root sampler configured"),
        ),
        (this._root = new $())),
      (this._remoteParentSampled = e.remoteParentSampled ?? new $()),
      (this._remoteParentNotSampled = e.remoteParentNotSampled ?? new Ue()),
      (this._localParentSampled = e.localParentSampled ?? new $()),
      (this._localParentNotSampled = e.localParentNotSampled ?? new Ue()));
  }
  shouldSample(e, r, n, a, _, o) {
    const i = C.getSpanContext(e);
    return !i || !ue(i)
      ? this._root.shouldSample(e, r, n, a, _, o)
      : i.isRemote
        ? i.traceFlags & h.SAMPLED
          ? this._remoteParentSampled.shouldSample(e, r, n, a, _, o)
          : this._remoteParentNotSampled.shouldSample(e, r, n, a, _, o)
        : i.traceFlags & h.SAMPLED
          ? this._localParentSampled.shouldSample(e, r, n, a, _, o)
          : this._localParentNotSampled.shouldSample(e, r, n, a, _, o);
  }
  toString() {
    return `ParentBased{root=${this._root.toString()}, remoteParentSampled=${this._remoteParentSampled.toString()}, remoteParentNotSampled=${this._remoteParentNotSampled.toString()}, localParentSampled=${this._localParentSampled.toString()}, localParentNotSampled=${this._localParentNotSampled.toString()}}`;
  }
}
class Zt {
  _ratio;
  _upperBound;
  constructor(e = 0) {
    ((this._ratio = e),
      (this._ratio = this._normalize(e)),
      (this._upperBound = Math.floor(this._ratio * 4294967295)));
  }
  shouldSample(e, r) {
    return {
      decision:
        Pt(r) && this._accumulate(r) < this._upperBound
          ? k.RECORD_AND_SAMPLED
          : k.NOT_RECORD,
    };
  }
  toString() {
    return `TraceIdRatioBased{${this._ratio}}`;
  }
  _normalize(e) {
    return typeof e != "number" || isNaN(e) ? 0 : e >= 1 ? 1 : e <= 0 ? 0 : e;
  }
  _accumulate(e) {
    let r = 0;
    for (let n = 0; n < e.length / 8; n++) {
      const a = n * 8,
        _ = parseInt(e.slice(a, a + 8), 16);
      r = (r ^ _) >>> 0;
    }
    return r;
  }
}
var D;
(function (t) {
  ((t.AlwaysOff = "always_off"),
    (t.AlwaysOn = "always_on"),
    (t.ParentBasedAlwaysOff = "parentbased_always_off"),
    (t.ParentBasedAlwaysOn = "parentbased_always_on"),
    (t.ParentBasedTraceIdRatio = "parentbased_traceidratio"),
    (t.TraceIdRatio = "traceidratio"));
})(D || (D = {}));
const Ne = 1;
function Jr() {
  return {
    sampler: Zr(),
    forceFlushTimeoutMillis: 3e4,
    generalLimits: {
      attributeValueLengthLimit:
        p("OTEL_ATTRIBUTE_VALUE_LENGTH_LIMIT") ?? 1 / 0,
      attributeCountLimit: p("OTEL_ATTRIBUTE_COUNT_LIMIT") ?? 128,
    },
    spanLimits: {
      attributeValueLengthLimit:
        p("OTEL_SPAN_ATTRIBUTE_VALUE_LENGTH_LIMIT") ?? 1 / 0,
      attributeCountLimit: p("OTEL_SPAN_ATTRIBUTE_COUNT_LIMIT") ?? 128,
      linkCountLimit: p("OTEL_SPAN_LINK_COUNT_LIMIT") ?? 128,
      eventCountLimit: p("OTEL_SPAN_EVENT_COUNT_LIMIT") ?? 128,
      attributePerEventCountLimit:
        p("OTEL_SPAN_ATTRIBUTE_PER_EVENT_COUNT_LIMIT") ?? 128,
      attributePerLinkCountLimit:
        p("OTEL_SPAN_ATTRIBUTE_PER_LINK_COUNT_LIMIT") ?? 128,
    },
  };
}
function Zr() {
  const t = It("OTEL_TRACES_SAMPLER") ?? D.ParentBasedAlwaysOn;
  switch (t) {
    case D.AlwaysOn:
      return new $();
    case D.AlwaysOff:
      return new Ue();
    case D.ParentBasedAlwaysOn:
      return new le({ root: new $() });
    case D.ParentBasedAlwaysOff:
      return new le({ root: new Ue() });
    case D.TraceIdRatio:
      return new Zt(er());
    case D.ParentBasedTraceIdRatio:
      return new le({ root: new Zt(er()) });
    default:
      return (
        c.error(
          `OTEL_TRACES_SAMPLER value "${t}" invalid, defaulting to "${D.ParentBasedAlwaysOn}".`,
        ),
        new le({ root: new $() })
      );
  }
}
function er() {
  const t = p("OTEL_TRACES_SAMPLER_ARG");
  return t == null
    ? (c.error(`OTEL_TRACES_SAMPLER_ARG is blank, defaulting to ${Ne}.`), Ne)
    : t < 0 || t > 1
      ? (c.error(
          `OTEL_TRACES_SAMPLER_ARG=${t} was given, but it is out of range ([0..1]), defaulting to ${Ne}.`,
        ),
        Ne)
      : t;
}
const Ic = 128,
  Dc = 1 / 0;
function gc(t) {
  const e = { sampler: Zr() },
    r = Jr(),
    n = Object.assign({}, r, e, t);
  return (
    (n.generalLimits = Object.assign(
      {},
      r.generalLimits,
      t.generalLimits || {},
    )),
    (n.spanLimits = Object.assign({}, r.spanLimits, t.spanLimits || {})),
    n
  );
}
function Uc(t) {
  const e = Object.assign({}, t.spanLimits);
  return (
    (e.attributeCountLimit =
      t.spanLimits?.attributeCountLimit ??
      t.generalLimits?.attributeCountLimit ??
      p("OTEL_SPAN_ATTRIBUTE_COUNT_LIMIT") ??
      p("OTEL_ATTRIBUTE_COUNT_LIMIT") ??
      Ic),
    (e.attributeValueLengthLimit =
      t.spanLimits?.attributeValueLengthLimit ??
      t.generalLimits?.attributeValueLengthLimit ??
      p("OTEL_SPAN_ATTRIBUTE_VALUE_LENGTH_LIMIT") ??
      p("OTEL_ATTRIBUTE_VALUE_LENGTH_LIMIT") ??
      Dc),
    Object.assign({}, t, { spanLimits: e })
  );
}
const hc = 8,
  en = 16;
class mc {
  generateTraceId = tr(en);
  generateSpanId = tr(hc);
}
const Oe = Buffer.allocUnsafe(en);
function tr(t) {
  return function () {
    for (let r = 0; r < t / 4; r++)
      Oe.writeUInt32BE((Math.random() * 2 ** 32) >>> 0, r * 4);
    for (let r = 0; r < t && !(Oe[r] > 0); r++) r === t - 1 && (Oe[t - 1] = 1);
    return Oe.toString("hex", 0, t);
  };
}
class Vc {
  _sampler;
  _generalLimits;
  _spanLimits;
  _idGenerator;
  instrumentationScope;
  _resource;
  _spanProcessor;
  constructor(e, r, n, a) {
    const _ = gc(r);
    ((this._sampler = _.sampler),
      (this._generalLimits = _.generalLimits),
      (this._spanLimits = _.spanLimits),
      (this._idGenerator = r.idGenerator || new mc()),
      (this._resource = n),
      (this._spanProcessor = a),
      (this.instrumentationScope = e));
  }
  startSpan(e, r = {}, n = B.active()) {
    r.root && (n = C.deleteSpan(n));
    const a = C.getSpan(n);
    if (Be(n))
      return (
        c.debug("Instrumentation suppressed, returning Noop Span"),
        C.wrapSpanContext(Ot)
      );
    const _ = a?.spanContext(),
      o = this._idGenerator.generateSpanId();
    let i, s, T;
    !_ || !C.isSpanContextValid(_)
      ? (s = this._idGenerator.generateTraceId())
      : ((s = _.traceId), (T = _.traceState), (i = _));
    const E = r.kind ?? pe.INTERNAL,
      S = (r.links ?? []).map((P) => ({
        context: P.context,
        attributes: oe(P.attributes),
      })),
      A = oe(r.attributes),
      u = this._sampler.shouldSample(n, s, e, E, A, S);
    T = u.traceState ?? T;
    const M = u.decision === Ee.RECORD_AND_SAMPLED ? h.SAMPLED : h.NONE,
      I = { traceId: s, spanId: o, traceFlags: M, traceState: T };
    if (u.decision === Ee.NOT_RECORD)
      return (
        c.debug(
          "Recording is off, propagating context in a non-recording span",
        ),
        C.wrapSpanContext(I)
      );
    const R = oe(Object.assign(A, u.attributes));
    return new Lc({
      resource: this._resource,
      scope: this.instrumentationScope,
      context: n,
      spanContext: I,
      name: e,
      kind: E,
      links: S,
      parentSpanContext: i,
      attributes: R,
      startTime: r.startTime,
      spanProcessor: this._spanProcessor,
      spanLimits: this._spanLimits,
    });
  }
  startActiveSpan(e, r, n, a) {
    let _, o, i;
    if (arguments.length < 2) return;
    arguments.length === 2
      ? (i = r)
      : arguments.length === 3
        ? ((_ = r), (i = n))
        : ((_ = r), (o = n), (i = a));
    const s = o ?? B.active(),
      T = this.startSpan(e, _, s),
      E = C.setSpan(s, T);
    return B.with(E, i, void 0, T);
  }
  getGeneralLimits() {
    return this._generalLimits;
  }
  getSpanLimits() {
    return this._spanLimits;
  }
}
class yc {
  _spanProcessors;
  constructor(e) {
    this._spanProcessors = e;
  }
  forceFlush() {
    const e = [];
    for (const r of this._spanProcessors) e.push(r.forceFlush());
    return new Promise((r) => {
      Promise.all(e)
        .then(() => {
          r();
        })
        .catch((n) => {
          (Lt(n || new Error("MultiSpanProcessor: forceFlush failed")), r());
        });
    });
  }
  onStart(e, r) {
    for (const n of this._spanProcessors) n.onStart(e, r);
  }
  onEnd(e) {
    for (const r of this._spanProcessors) r.onEnd(e);
  }
  shutdown() {
    const e = [];
    for (const r of this._spanProcessors) e.push(r.shutdown());
    return new Promise((r, n) => {
      Promise.all(e).then(() => {
        r();
      }, n);
    });
  }
}
var b;
(function (t) {
  ((t[(t.resolved = 0)] = "resolved"),
    (t[(t.timeout = 1)] = "timeout"),
    (t[(t.error = 2)] = "error"),
    (t[(t.unresolved = 3)] = "unresolved"));
})(b || (b = {}));
class RC {
  _config;
  _tracers = new Map();
  _resource;
  _activeSpanProcessor;
  constructor(e = {}) {
    const r = Xr({}, Jr(), Uc(e));
    ((this._resource = r.resource ?? fc()),
      (this._config = Object.assign({}, r, { resource: this._resource })));
    const n = [];
    (e.spanProcessors?.length && n.push(...e.spanProcessors),
      (this._activeSpanProcessor = new yc(n)));
  }
  getTracer(e, r, n) {
    const a = `${e}@${r || ""}:${n?.schemaUrl || ""}`;
    return (
      this._tracers.has(a) ||
        this._tracers.set(
          a,
          new Vc(
            { name: e, version: r, schemaUrl: n?.schemaUrl },
            this._config,
            this._resource,
            this._activeSpanProcessor,
          ),
        ),
      this._tracers.get(a)
    );
  }
  forceFlush() {
    const e = this._config.forceFlushTimeoutMillis,
      r = this._activeSpanProcessor._spanProcessors.map(
        (n) =>
          new Promise((a) => {
            let _;
            const o = setTimeout(() => {
              (a(
                new Error(
                  `Span processor did not completed within timeout period of ${e} ms`,
                ),
              ),
                (_ = b.timeout));
            }, e);
            n.forceFlush()
              .then(() => {
                (clearTimeout(o), _ !== b.timeout && ((_ = b.resolved), a(_)));
              })
              .catch((i) => {
                (clearTimeout(o), (_ = b.error), a(i));
              });
          }),
      );
    return new Promise((n, a) => {
      Promise.all(r)
        .then((_) => {
          const o = _.filter((i) => i !== b.resolved);
          o.length > 0 ? a(o) : n();
        })
        .catch((_) => a([_]));
    });
  }
  shutdown() {
    return this._activeSpanProcessor.shutdown();
  }
}
var tt = {},
  X = {},
  q = {},
  rr;
function tn() {
  if (rr) return q;
  ((rr = 1),
    Object.defineProperty(q, "__esModule", { value: !0 }),
    (q.AbstractAsyncHooksContextManager = void 0));
  const t = IT,
    e = ["addListener", "on", "once", "prependListener", "prependOnceListener"];
  let r = class {
    bind(a, _) {
      return _ instanceof t.EventEmitter
        ? this._bindEventEmitter(a, _)
        : typeof _ == "function"
          ? this._bindFunction(a, _)
          : _;
    }
    _bindFunction(a, _) {
      const o = this,
        i = function (...s) {
          return o.with(a, () => _.apply(this, s));
        };
      return (
        Object.defineProperty(i, "length", {
          enumerable: !1,
          configurable: !0,
          writable: !1,
          value: _.length,
        }),
        i
      );
    }
    _bindEventEmitter(a, _) {
      return (
        this._getPatchMap(_) !== void 0 ||
          (this._createPatchMap(_),
          e.forEach((i) => {
            _[i] !== void 0 && (_[i] = this._patchAddListener(_, _[i], a));
          }),
          typeof _.removeListener == "function" &&
            (_.removeListener = this._patchRemoveListener(_, _.removeListener)),
          typeof _.off == "function" &&
            (_.off = this._patchRemoveListener(_, _.off)),
          typeof _.removeAllListeners == "function" &&
            (_.removeAllListeners = this._patchRemoveAllListeners(
              _,
              _.removeAllListeners,
            ))),
        _
      );
    }
    _patchRemoveListener(a, _) {
      const o = this;
      return function (i, s) {
        const T = o._getPatchMap(a)?.[i];
        if (T === void 0) return _.call(this, i, s);
        const E = T.get(s);
        return _.call(this, i, E || s);
      };
    }
    _patchRemoveAllListeners(a, _) {
      const o = this;
      return function (i) {
        const s = o._getPatchMap(a);
        return (
          s !== void 0 &&
            (arguments.length === 0
              ? o._createPatchMap(a)
              : s[i] !== void 0 && delete s[i]),
          _.apply(this, arguments)
        );
      };
    }
    _patchAddListener(a, _, o) {
      const i = this;
      return function (s, T) {
        if (i._wrapped) return _.call(this, s, T);
        let E = i._getPatchMap(a);
        E === void 0 && (E = i._createPatchMap(a));
        let S = E[s];
        S === void 0 && ((S = new WeakMap()), (E[s] = S));
        const A = i.bind(o, T);
        (S.set(T, A), (i._wrapped = !0));
        try {
          return _.call(this, s, A);
        } finally {
          i._wrapped = !1;
        }
      };
    }
    _createPatchMap(a) {
      const _ = Object.create(null);
      return ((a[this._kOtListeners] = _), _);
    }
    _getPatchMap(a) {
      return a[this._kOtListeners];
    }
    _kOtListeners = Symbol("OtListeners");
    _wrapped = !1;
  };
  return ((q.AbstractAsyncHooksContextManager = r), q);
}
var nr;
function bc() {
  if (nr) return X;
  ((nr = 1),
    Object.defineProperty(X, "__esModule", { value: !0 }),
    (X.AsyncHooksContextManager = void 0));
  const t = Re,
    e = Cr,
    r = tn();
  let n = class extends r.AbstractAsyncHooksContextManager {
    _asyncHook;
    _contexts = new Map();
    _stack = [];
    constructor() {
      (super(),
        (this._asyncHook = e.createHook({
          init: this._init.bind(this),
          before: this._before.bind(this),
          after: this._after.bind(this),
          destroy: this._destroy.bind(this),
          promiseResolve: this._destroy.bind(this),
        })));
    }
    active() {
      return this._stack[this._stack.length - 1] ?? t.ROOT_CONTEXT;
    }
    with(_, o, i, ...s) {
      this._enterContext(_);
      try {
        return o.call(i, ...s);
      } finally {
        this._exitContext();
      }
    }
    enable() {
      return (this._asyncHook.enable(), this);
    }
    disable() {
      return (
        this._asyncHook.disable(),
        this._contexts.clear(),
        (this._stack = []),
        this
      );
    }
    _init(_, o) {
      if (o === "TIMERWRAP") return;
      const i = this._stack[this._stack.length - 1];
      i !== void 0 && this._contexts.set(_, i);
    }
    _destroy(_) {
      this._contexts.delete(_);
    }
    _before(_) {
      const o = this._contexts.get(_);
      o !== void 0 && this._enterContext(o);
    }
    _after() {
      this._exitContext();
    }
    _enterContext(_) {
      this._stack.push(_);
    }
    _exitContext() {
      this._stack.pop();
    }
  };
  return ((X.AsyncHooksContextManager = n), X);
}
var z = {},
  ar;
function Gc() {
  if (ar) return z;
  ((ar = 1),
    Object.defineProperty(z, "__esModule", { value: !0 }),
    (z.AsyncLocalStorageContextManager = void 0));
  const t = Re,
    e = Cr,
    r = tn();
  let n = class extends r.AbstractAsyncHooksContextManager {
    _asyncLocalStorage;
    constructor() {
      (super(), (this._asyncLocalStorage = new e.AsyncLocalStorage()));
    }
    active() {
      return this._asyncLocalStorage.getStore() ?? t.ROOT_CONTEXT;
    }
    with(_, o, i, ...s) {
      const T = i == null ? o : o.bind(i);
      return this._asyncLocalStorage.run(_, T, ...s);
    }
    enable() {
      return this;
    }
    disable() {
      return (this._asyncLocalStorage.disable(), this);
    }
  };
  return ((z.AsyncLocalStorageContextManager = n), z);
}
var _r;
function Bc() {
  return (
    _r ||
      ((_r = 1),
      (function (t) {
        (Object.defineProperty(t, "__esModule", { value: !0 }),
          (t.AsyncLocalStorageContextManager = t.AsyncHooksContextManager =
            void 0));
        var e = bc();
        Object.defineProperty(t, "AsyncHooksContextManager", {
          enumerable: !0,
          get: function () {
            return e.AsyncHooksContextManager;
          },
        });
        var r = Gc();
        Object.defineProperty(t, "AsyncLocalStorageContextManager", {
          enumerable: !0,
          get: function () {
            return r.AsyncLocalStorageContextManager;
          },
        });
      })(tt)),
    tt
  );
}
var vC = Bc();
const wc = Ve(Nc);
function f(t) {
  for (var e = {}, r = t.length, n = 0; n < r; n++) {
    var a = t[n];
    a && (e[String(a).toUpperCase().replace(/[-.]/g, "_")] = a);
  }
  return e;
}
var rn = "aws.lambda.invoked_arn",
  nn = "db.system",
  an = "db.connection_string",
  _n = "db.user",
  on = "db.jdbc.driver_classname",
  sn = "db.name",
  En = "db.statement",
  Tn = "db.operation",
  Sn = "db.mssql.instance_name",
  An = "db.cassandra.keyspace",
  cn = "db.cassandra.page_size",
  un = "db.cassandra.consistency_level",
  Rn = "db.cassandra.table",
  ln = "db.cassandra.idempotence",
  Nn = "db.cassandra.speculative_execution_count",
  On = "db.cassandra.coordinator.id",
  vn = "db.cassandra.coordinator.dc",
  Mn = "db.hbase.namespace",
  fn = "db.redis.database_index",
  Pn = "db.mongodb.collection",
  dn = "db.sql.table",
  pn = "exception.type",
  Cn = "exception.message",
  Ln = "exception.stacktrace",
  In = "exception.escaped",
  Dn = "faas.trigger",
  gn = "faas.execution",
  Un = "faas.document.collection",
  hn = "faas.document.operation",
  mn = "faas.document.time",
  Vn = "faas.document.name",
  yn = "faas.time",
  bn = "faas.cron",
  Gn = "faas.coldstart",
  Bn = "faas.invoked_name",
  wn = "faas.invoked_provider",
  Yn = "faas.invoked_region",
  Hn = "net.transport",
  $n = "net.peer.ip",
  xn = "net.peer.port",
  kn = "net.peer.name",
  Fn = "net.host.ip",
  Kn = "net.host.port",
  jn = "net.host.name",
  Wn = "net.host.connection.type",
  Xn = "net.host.connection.subtype",
  qn = "net.host.carrier.name",
  zn = "net.host.carrier.mcc",
  Qn = "net.host.carrier.mnc",
  Jn = "net.host.carrier.icc",
  Zn = "peer.service",
  ea = "enduser.id",
  ta = "enduser.role",
  ra = "enduser.scope",
  na = "thread.id",
  aa = "thread.name",
  _a = "code.function",
  oa = "code.namespace",
  ia = "code.filepath",
  sa = "code.lineno",
  Ea = "http.method",
  Ta = "http.url",
  Sa = "http.target",
  Aa = "http.host",
  ca = "http.scheme",
  ua = "http.status_code",
  Ra = "http.flavor",
  la = "http.user_agent",
  Na = "http.request_content_length",
  Oa = "http.request_content_length_uncompressed",
  va = "http.response_content_length",
  Ma = "http.response_content_length_uncompressed",
  fa = "http.server_name",
  Pa = "http.route",
  da = "http.client_ip",
  pa = "aws.dynamodb.table_names",
  Ca = "aws.dynamodb.consumed_capacity",
  La = "aws.dynamodb.item_collection_metrics",
  Ia = "aws.dynamodb.provisioned_read_capacity",
  Da = "aws.dynamodb.provisioned_write_capacity",
  ga = "aws.dynamodb.consistent_read",
  Ua = "aws.dynamodb.projection",
  ha = "aws.dynamodb.limit",
  ma = "aws.dynamodb.attributes_to_get",
  Va = "aws.dynamodb.index_name",
  ya = "aws.dynamodb.select",
  ba = "aws.dynamodb.global_secondary_indexes",
  Ga = "aws.dynamodb.local_secondary_indexes",
  Ba = "aws.dynamodb.exclusive_start_table",
  wa = "aws.dynamodb.table_count",
  Ya = "aws.dynamodb.scan_forward",
  Ha = "aws.dynamodb.segment",
  $a = "aws.dynamodb.total_segments",
  xa = "aws.dynamodb.count",
  ka = "aws.dynamodb.scanned_count",
  Fa = "aws.dynamodb.attribute_definitions",
  Ka = "aws.dynamodb.global_secondary_index_updates",
  ja = "messaging.system",
  Wa = "messaging.destination",
  Xa = "messaging.destination_kind",
  qa = "messaging.temp_destination",
  za = "messaging.protocol",
  Qa = "messaging.protocol_version",
  Ja = "messaging.url",
  Za = "messaging.message_id",
  e_ = "messaging.conversation_id",
  t_ = "messaging.message_payload_size_bytes",
  r_ = "messaging.message_payload_compressed_size_bytes",
  n_ = "messaging.operation",
  a_ = "messaging.consumer_id",
  __ = "messaging.rabbitmq.routing_key",
  o_ = "messaging.kafka.message_key",
  i_ = "messaging.kafka.consumer_group",
  s_ = "messaging.kafka.client_id",
  E_ = "messaging.kafka.partition",
  T_ = "messaging.kafka.tombstone",
  S_ = "rpc.system",
  A_ = "rpc.service",
  c_ = "rpc.method",
  u_ = "rpc.grpc.status_code",
  R_ = "rpc.jsonrpc.version",
  l_ = "rpc.jsonrpc.request_id",
  N_ = "rpc.jsonrpc.error_code",
  O_ = "rpc.jsonrpc.error_message",
  v_ = "message.type",
  M_ = "message.id",
  f_ = "message.compressed_size",
  P_ = "message.uncompressed_size",
  Yc = rn,
  Hc = nn,
  $c = an,
  xc = _n,
  kc = on,
  Fc = sn,
  Kc = En,
  jc = Tn,
  Wc = Sn,
  Xc = An,
  qc = cn,
  zc = un,
  Qc = Rn,
  Jc = ln,
  Zc = Nn,
  eu = On,
  tu = vn,
  ru = Mn,
  nu = fn,
  au = Pn,
  _u = dn,
  ou = pn,
  iu = Cn,
  su = Ln,
  Eu = In,
  Tu = Dn,
  Su = gn,
  Au = Un,
  cu = hn,
  uu = mn,
  Ru = Vn,
  lu = yn,
  Nu = bn,
  Ou = Gn,
  vu = Bn,
  Mu = wn,
  fu = Yn,
  Pu = Hn,
  du = $n,
  pu = xn,
  Cu = kn,
  Lu = Fn,
  Iu = Kn,
  Du = jn,
  gu = Wn,
  Uu = Xn,
  hu = qn,
  mu = zn,
  Vu = Qn,
  yu = Jn,
  bu = Zn,
  Gu = ea,
  Bu = ta,
  wu = ra,
  Yu = na,
  Hu = aa,
  $u = _a,
  xu = oa,
  ku = ia,
  Fu = sa,
  Ku = Ea,
  ju = Ta,
  Wu = Sa,
  Xu = Aa,
  qu = ca,
  zu = ua,
  Qu = Ra,
  Ju = la,
  Zu = Na,
  eR = Oa,
  tR = va,
  rR = Ma,
  nR = fa,
  aR = Pa,
  _R = da,
  oR = pa,
  iR = Ca,
  sR = La,
  ER = Ia,
  TR = Da,
  SR = ga,
  AR = Ua,
  cR = ha,
  uR = ma,
  RR = Va,
  lR = ya,
  NR = ba,
  OR = Ga,
  vR = Ba,
  MR = wa,
  fR = Ya,
  PR = Ha,
  dR = $a,
  pR = xa,
  CR = ka,
  LR = Fa,
  IR = Ka,
  DR = ja,
  gR = Wa,
  UR = Xa,
  hR = qa,
  mR = za,
  VR = Qa,
  yR = Ja,
  bR = Za,
  GR = e_,
  BR = t_,
  wR = r_,
  YR = n_,
  HR = a_,
  $R = __,
  xR = o_,
  kR = i_,
  FR = s_,
  KR = E_,
  jR = T_,
  WR = S_,
  XR = A_,
  qR = c_,
  zR = u_,
  QR = R_,
  JR = l_,
  ZR = N_,
  el = O_,
  tl = v_,
  rl = M_,
  nl = f_,
  al = P_,
  _l = f([
    rn,
    nn,
    an,
    _n,
    on,
    sn,
    En,
    Tn,
    Sn,
    An,
    cn,
    un,
    Rn,
    ln,
    Nn,
    On,
    vn,
    Mn,
    fn,
    Pn,
    dn,
    pn,
    Cn,
    Ln,
    In,
    Dn,
    gn,
    Un,
    hn,
    mn,
    Vn,
    yn,
    bn,
    Gn,
    Bn,
    wn,
    Yn,
    Hn,
    $n,
    xn,
    kn,
    Fn,
    Kn,
    jn,
    Wn,
    Xn,
    qn,
    zn,
    Qn,
    Jn,
    Zn,
    ea,
    ta,
    ra,
    na,
    aa,
    _a,
    oa,
    ia,
    sa,
    Ea,
    Ta,
    Sa,
    Aa,
    ca,
    ua,
    Ra,
    la,
    Na,
    Oa,
    va,
    Ma,
    fa,
    Pa,
    da,
    pa,
    Ca,
    La,
    Ia,
    Da,
    ga,
    Ua,
    ha,
    ma,
    Va,
    ya,
    ba,
    Ga,
    Ba,
    wa,
    Ya,
    Ha,
    $a,
    xa,
    ka,
    Fa,
    Ka,
    ja,
    Wa,
    Xa,
    qa,
    za,
    Qa,
    Ja,
    Za,
    e_,
    t_,
    r_,
    n_,
    a_,
    __,
    o_,
    i_,
    s_,
    E_,
    T_,
    S_,
    A_,
    c_,
    u_,
    R_,
    l_,
    N_,
    O_,
    v_,
    M_,
    f_,
    P_,
  ]),
  d_ = "other_sql",
  p_ = "mssql",
  C_ = "mysql",
  L_ = "oracle",
  I_ = "db2",
  D_ = "postgresql",
  g_ = "redshift",
  U_ = "hive",
  h_ = "cloudscape",
  m_ = "hsqldb",
  V_ = "progress",
  y_ = "maxdb",
  b_ = "hanadb",
  G_ = "ingres",
  B_ = "firstsql",
  w_ = "edb",
  Y_ = "cache",
  H_ = "adabas",
  $_ = "firebird",
  x_ = "derby",
  k_ = "filemaker",
  F_ = "informix",
  K_ = "instantdb",
  j_ = "interbase",
  W_ = "mariadb",
  X_ = "netezza",
  q_ = "pervasive",
  z_ = "pointbase",
  Q_ = "sqlite",
  J_ = "sybase",
  Z_ = "teradata",
  eo = "vertica",
  to = "h2",
  ro = "coldfusion",
  no = "cassandra",
  ao = "hbase",
  _o = "mongodb",
  oo = "redis",
  io = "couchbase",
  so = "couchdb",
  Eo = "cosmosdb",
  To = "dynamodb",
  So = "neo4j",
  Ao = "geode",
  co = "elasticsearch",
  uo = "memcached",
  Ro = "cockroachdb",
  ol = d_,
  il = p_,
  sl = C_,
  El = L_,
  Tl = I_,
  Sl = D_,
  Al = g_,
  cl = U_,
  ul = h_,
  Rl = m_,
  ll = V_,
  Nl = y_,
  Ol = b_,
  vl = G_,
  Ml = B_,
  fl = w_,
  Pl = Y_,
  dl = H_,
  pl = $_,
  Cl = x_,
  Ll = k_,
  Il = F_,
  Dl = K_,
  gl = j_,
  Ul = W_,
  hl = X_,
  ml = q_,
  Vl = z_,
  yl = Q_,
  bl = J_,
  Gl = Z_,
  Bl = eo,
  wl = to,
  Yl = ro,
  Hl = no,
  $l = ao,
  xl = _o,
  kl = oo,
  Fl = io,
  Kl = so,
  jl = Eo,
  Wl = To,
  Xl = So,
  ql = Ao,
  zl = co,
  Ql = uo,
  Jl = Ro,
  Zl = f([
    d_,
    p_,
    C_,
    L_,
    I_,
    D_,
    g_,
    U_,
    h_,
    m_,
    V_,
    y_,
    b_,
    G_,
    B_,
    w_,
    Y_,
    H_,
    $_,
    x_,
    k_,
    F_,
    K_,
    j_,
    W_,
    X_,
    q_,
    z_,
    Q_,
    J_,
    Z_,
    eo,
    to,
    ro,
    no,
    ao,
    _o,
    oo,
    io,
    so,
    Eo,
    To,
    So,
    Ao,
    co,
    uo,
    Ro,
  ]),
  lo = "all",
  No = "each_quorum",
  Oo = "quorum",
  vo = "local_quorum",
  Mo = "one",
  fo = "two",
  Po = "three",
  po = "local_one",
  Co = "any",
  Lo = "serial",
  Io = "local_serial",
  eN = lo,
  tN = No,
  rN = Oo,
  nN = vo,
  aN = Mo,
  _N = fo,
  oN = Po,
  iN = po,
  sN = Co,
  EN = Lo,
  TN = Io,
  SN = f([lo, No, Oo, vo, Mo, fo, Po, po, Co, Lo, Io]),
  Do = "datasource",
  go = "http",
  Uo = "pubsub",
  ho = "timer",
  mo = "other",
  AN = Do,
  cN = go,
  uN = Uo,
  RN = ho,
  lN = mo,
  NN = f([Do, go, Uo, ho, mo]),
  Vo = "insert",
  yo = "edit",
  bo = "delete",
  ON = Vo,
  vN = yo,
  MN = bo,
  fN = f([Vo, yo, bo]),
  Go = "alibaba_cloud",
  Bo = "aws",
  wo = "azure",
  Yo = "gcp",
  PN = Go,
  dN = Bo,
  pN = wo,
  CN = Yo,
  LN = f([Go, Bo, wo, Yo]),
  Ho = "ip_tcp",
  $o = "ip_udp",
  xo = "ip",
  ko = "unix",
  Fo = "pipe",
  Ko = "inproc",
  jo = "other",
  IN = Ho,
  DN = $o,
  gN = xo,
  UN = ko,
  hN = Fo,
  mN = Ko,
  VN = jo,
  yN = f([Ho, $o, xo, ko, Fo, Ko, jo]),
  Wo = "wifi",
  Xo = "wired",
  qo = "cell",
  zo = "unavailable",
  Qo = "unknown",
  bN = Wo,
  GN = Xo,
  BN = qo,
  wN = zo,
  YN = Qo,
  HN = f([Wo, Xo, qo, zo, Qo]),
  Jo = "gprs",
  Zo = "edge",
  ei = "umts",
  ti = "cdma",
  ri = "evdo_0",
  ni = "evdo_a",
  ai = "cdma2000_1xrtt",
  _i = "hsdpa",
  oi = "hsupa",
  ii = "hspa",
  si = "iden",
  Ei = "evdo_b",
  Ti = "lte",
  Si = "ehrpd",
  Ai = "hspap",
  ci = "gsm",
  ui = "td_scdma",
  Ri = "iwlan",
  li = "nr",
  Ni = "nrnsa",
  Oi = "lte_ca",
  $N = Jo,
  xN = Zo,
  kN = ei,
  FN = ti,
  KN = ri,
  jN = ni,
  WN = ai,
  XN = _i,
  qN = oi,
  zN = ii,
  QN = si,
  JN = Ei,
  ZN = Ti,
  eO = Si,
  tO = Ai,
  rO = ci,
  nO = ui,
  aO = Ri,
  _O = li,
  oO = Ni,
  iO = Oi,
  sO = f([
    Jo,
    Zo,
    ei,
    ti,
    ri,
    ni,
    ai,
    _i,
    oi,
    ii,
    si,
    Ei,
    Ti,
    Si,
    Ai,
    ci,
    ui,
    Ri,
    li,
    Ni,
    Oi,
  ]),
  vi = "1.0",
  Mi = "1.1",
  fi = "2.0",
  Pi = "SPDY",
  di = "QUIC",
  EO = vi,
  TO = Mi,
  SO = fi,
  AO = Pi,
  cO = di,
  uO = { HTTP_1_0: vi, HTTP_1_1: Mi, HTTP_2_0: fi, SPDY: Pi, QUIC: di },
  pi = "queue",
  Ci = "topic",
  RO = pi,
  lO = Ci,
  NO = f([pi, Ci]),
  Li = "receive",
  Ii = "process",
  OO = Li,
  vO = Ii,
  MO = f([Li, Ii]),
  Di = 0,
  gi = 1,
  Ui = 2,
  hi = 3,
  mi = 4,
  Vi = 5,
  yi = 6,
  bi = 7,
  Gi = 8,
  Bi = 9,
  wi = 10,
  Yi = 11,
  Hi = 12,
  $i = 13,
  xi = 14,
  ki = 15,
  Fi = 16,
  fO = Di,
  PO = gi,
  dO = Ui,
  pO = hi,
  CO = mi,
  LO = Vi,
  IO = yi,
  DO = bi,
  gO = Gi,
  UO = Bi,
  hO = wi,
  mO = Yi,
  VO = Hi,
  yO = $i,
  bO = xi,
  GO = ki,
  BO = Fi,
  wO = {
    OK: Di,
    CANCELLED: gi,
    UNKNOWN: Ui,
    INVALID_ARGUMENT: hi,
    DEADLINE_EXCEEDED: mi,
    NOT_FOUND: Vi,
    ALREADY_EXISTS: yi,
    PERMISSION_DENIED: bi,
    RESOURCE_EXHAUSTED: Gi,
    FAILED_PRECONDITION: Bi,
    ABORTED: wi,
    OUT_OF_RANGE: Yi,
    UNIMPLEMENTED: Hi,
    INTERNAL: $i,
    UNAVAILABLE: xi,
    DATA_LOSS: ki,
    UNAUTHENTICATED: Fi,
  },
  Ki = "SENT",
  ji = "RECEIVED",
  YO = Ki,
  HO = ji,
  $O = f([Ki, ji]),
  Wi = "cloud.provider",
  Xi = "cloud.account.id",
  qi = "cloud.region",
  zi = "cloud.availability_zone",
  Qi = "cloud.platform",
  Ji = "aws.ecs.container.arn",
  Zi = "aws.ecs.cluster.arn",
  es = "aws.ecs.launchtype",
  ts = "aws.ecs.task.arn",
  rs = "aws.ecs.task.family",
  ns = "aws.ecs.task.revision",
  as = "aws.eks.cluster.arn",
  _s = "aws.log.group.names",
  os = "aws.log.group.arns",
  is = "aws.log.stream.names",
  ss = "aws.log.stream.arns",
  Es = "container.name",
  Ts = "container.id",
  Ss = "container.runtime",
  As = "container.image.name",
  cs = "container.image.tag",
  us = "deployment.environment",
  Rs = "device.id",
  ls = "device.model.identifier",
  Ns = "device.model.name",
  Os = "faas.name",
  vs = "faas.id",
  Ms = "faas.version",
  fs = "faas.instance",
  Ps = "faas.max_memory",
  ds = "host.id",
  ps = "host.name",
  Cs = "host.type",
  Ls = "host.arch",
  Is = "host.image.name",
  Ds = "host.image.id",
  gs = "host.image.version",
  Us = "k8s.cluster.name",
  hs = "k8s.node.name",
  ms = "k8s.node.uid",
  Vs = "k8s.namespace.name",
  ys = "k8s.pod.uid",
  bs = "k8s.pod.name",
  Gs = "k8s.container.name",
  Bs = "k8s.replicaset.uid",
  ws = "k8s.replicaset.name",
  Ys = "k8s.deployment.uid",
  Hs = "k8s.deployment.name",
  $s = "k8s.statefulset.uid",
  xs = "k8s.statefulset.name",
  ks = "k8s.daemonset.uid",
  Fs = "k8s.daemonset.name",
  Ks = "k8s.job.uid",
  js = "k8s.job.name",
  Ws = "k8s.cronjob.uid",
  Xs = "k8s.cronjob.name",
  qs = "os.type",
  zs = "os.description",
  Qs = "os.name",
  Js = "os.version",
  Zs = "process.pid",
  eE = "process.executable.name",
  tE = "process.executable.path",
  rE = "process.command",
  nE = "process.command_line",
  aE = "process.command_args",
  _E = "process.owner",
  oE = "process.runtime.name",
  iE = "process.runtime.version",
  sE = "process.runtime.description",
  EE = "service.name",
  TE = "service.namespace",
  SE = "service.instance.id",
  AE = "service.version",
  cE = "telemetry.sdk.name",
  uE = "telemetry.sdk.language",
  RE = "telemetry.sdk.version",
  lE = "telemetry.auto.version",
  NE = "webengine.name",
  OE = "webengine.version",
  vE = "webengine.description",
  xO = Wi,
  kO = Xi,
  FO = qi,
  KO = zi,
  jO = Qi,
  WO = Ji,
  XO = Zi,
  qO = es,
  zO = ts,
  QO = rs,
  JO = ns,
  ZO = as,
  ev = _s,
  tv = os,
  rv = is,
  nv = ss,
  av = Es,
  _v = Ts,
  ov = Ss,
  iv = As,
  sv = cs,
  Ev = us,
  Tv = Rs,
  Sv = ls,
  Av = Ns,
  cv = Os,
  uv = vs,
  Rv = Ms,
  lv = fs,
  Nv = Ps,
  Ov = ds,
  vv = ps,
  Mv = Cs,
  fv = Ls,
  Pv = Is,
  dv = Ds,
  pv = gs,
  Cv = Us,
  Lv = hs,
  Iv = ms,
  Dv = Vs,
  gv = ys,
  Uv = bs,
  hv = Gs,
  mv = Bs,
  Vv = ws,
  yv = Ys,
  bv = Hs,
  Gv = $s,
  Bv = xs,
  wv = ks,
  Yv = Fs,
  Hv = Ks,
  $v = js,
  xv = Ws,
  kv = Xs,
  Fv = qs,
  Kv = zs,
  jv = Qs,
  Wv = Js,
  Xv = Zs,
  qv = eE,
  zv = tE,
  Qv = rE,
  Jv = nE,
  Zv = aE,
  eM = _E,
  tM = oE,
  rM = iE,
  nM = sE,
  aM = EE,
  _M = TE,
  oM = SE,
  iM = AE,
  sM = cE,
  EM = uE,
  TM = RE,
  SM = lE,
  AM = NE,
  cM = OE,
  uM = vE,
  RM = f([
    Wi,
    Xi,
    qi,
    zi,
    Qi,
    Ji,
    Zi,
    es,
    ts,
    rs,
    ns,
    as,
    _s,
    os,
    is,
    ss,
    Es,
    Ts,
    Ss,
    As,
    cs,
    us,
    Rs,
    ls,
    Ns,
    Os,
    vs,
    Ms,
    fs,
    Ps,
    ds,
    ps,
    Cs,
    Ls,
    Is,
    Ds,
    gs,
    Us,
    hs,
    ms,
    Vs,
    ys,
    bs,
    Gs,
    Bs,
    ws,
    Ys,
    Hs,
    $s,
    xs,
    ks,
    Fs,
    Ks,
    js,
    Ws,
    Xs,
    qs,
    zs,
    Qs,
    Js,
    Zs,
    eE,
    tE,
    rE,
    nE,
    aE,
    _E,
    oE,
    iE,
    sE,
    EE,
    TE,
    SE,
    AE,
    cE,
    uE,
    RE,
    lE,
    NE,
    OE,
    vE,
  ]),
  ME = "alibaba_cloud",
  fE = "aws",
  PE = "azure",
  dE = "gcp",
  lM = ME,
  NM = fE,
  OM = PE,
  vM = dE,
  MM = f([ME, fE, PE, dE]),
  pE = "alibaba_cloud_ecs",
  CE = "alibaba_cloud_fc",
  LE = "aws_ec2",
  IE = "aws_ecs",
  DE = "aws_eks",
  gE = "aws_lambda",
  UE = "aws_elastic_beanstalk",
  hE = "azure_vm",
  mE = "azure_container_instances",
  VE = "azure_aks",
  yE = "azure_functions",
  bE = "azure_app_service",
  GE = "gcp_compute_engine",
  BE = "gcp_cloud_run",
  wE = "gcp_kubernetes_engine",
  YE = "gcp_cloud_functions",
  HE = "gcp_app_engine",
  fM = pE,
  PM = CE,
  dM = LE,
  pM = IE,
  CM = DE,
  LM = gE,
  IM = UE,
  DM = hE,
  gM = mE,
  UM = VE,
  hM = yE,
  mM = bE,
  VM = GE,
  yM = BE,
  bM = wE,
  GM = YE,
  BM = HE,
  wM = f([pE, CE, LE, IE, DE, gE, UE, hE, mE, VE, yE, bE, GE, BE, wE, YE, HE]),
  $E = "ec2",
  xE = "fargate",
  YM = $E,
  HM = xE,
  $M = f([$E, xE]),
  kE = "amd64",
  FE = "arm32",
  KE = "arm64",
  jE = "ia64",
  WE = "ppc32",
  XE = "ppc64",
  qE = "x86",
  xM = kE,
  kM = FE,
  FM = KE,
  KM = jE,
  jM = WE,
  WM = XE,
  XM = qE,
  qM = f([kE, FE, KE, jE, WE, XE, qE]),
  zE = "windows",
  QE = "linux",
  JE = "darwin",
  ZE = "freebsd",
  eT = "netbsd",
  tT = "openbsd",
  rT = "dragonflybsd",
  nT = "hpux",
  aT = "aix",
  _T = "solaris",
  oT = "z_os",
  zM = zE,
  QM = QE,
  JM = JE,
  ZM = ZE,
  ef = eT,
  tf = tT,
  rf = rT,
  nf = nT,
  af = aT,
  _f = _T,
  of = oT,
  sf = f([zE, QE, JE, ZE, eT, tT, rT, nT, aT, _T, oT]),
  iT = "cpp",
  sT = "dotnet",
  ET = "erlang",
  TT = "go",
  ST = "java",
  AT = "nodejs",
  cT = "php",
  uT = "python",
  RT = "ruby",
  lT = "webjs",
  Ef = iT,
  Tf = sT,
  Sf = ET,
  Af = TT,
  cf = ST,
  uf = AT,
  Rf = cT,
  lf = uT,
  Nf = RT,
  Of = lT,
  vf = f([iT, sT, ET, TT, ST, AT, cT, uT, RT, lT]),
  Mf = "aspnetcore.rate_limiting.result",
  ff = "acquired",
  Pf = "endpoint_limiter",
  df = "global_limiter",
  pf = "request_canceled",
  Cf = "telemetry.sdk.language",
  Lf = "cpp",
  If = "dotnet",
  Df = "erlang",
  gf = "go",
  Uf = "java",
  hf = "nodejs",
  mf = "php",
  Vf = "python",
  yf = "ruby",
  bf = "rust",
  Gf = "swift",
  Bf = "webjs",
  wf = "telemetry.sdk.name",
  Yf = "telemetry.sdk.version",
  Hf = "aspnetcore.diagnostics.handler.type",
  $f = "aspnetcore.diagnostics.exception.result",
  xf = "aborted",
  kf = "handled",
  Ff = "skipped",
  Kf = "unhandled",
  jf = "aspnetcore.rate_limiting.policy",
  Wf = "aspnetcore.request.is_unhandled",
  Xf = "aspnetcore.routing.is_fallback",
  qf = "aspnetcore.routing.match_status",
  zf = "failure",
  Qf = "success",
  Jf = "client.address",
  Zf = "client.port",
  eP = "error.type",
  tP = "_OTHER",
  rP = "exception.escaped",
  nP = "exception.message",
  aP = "exception.stacktrace",
  _P = "exception.type",
  oP = function (t) {
    return "http.request.header." + t;
  },
  iP = "http.request.method",
  sP = "_OTHER",
  EP = "CONNECT",
  TP = "DELETE",
  SP = "GET",
  AP = "HEAD",
  cP = "OPTIONS",
  uP = "PATCH",
  RP = "POST",
  lP = "PUT",
  NP = "TRACE",
  OP = "http.request.method_original",
  vP = "http.request.resend_count",
  MP = function (t) {
    return "http.response.header." + t;
  },
  fP = "http.response.status_code",
  PP = "http.route",
  dP = "jvm.gc.action",
  pP = "jvm.gc.name",
  CP = "jvm.memory.pool.name",
  LP = "jvm.memory.type",
  IP = "heap",
  DP = "non_heap",
  gP = "jvm.thread.daemon",
  UP = "jvm.thread.state",
  hP = "blocked",
  mP = "new",
  VP = "runnable",
  yP = "terminated",
  bP = "timed_waiting",
  GP = "waiting",
  BP = "network.local.address",
  wP = "network.local.port",
  YP = "network.peer.address",
  HP = "network.peer.port",
  $P = "network.protocol.name",
  xP = "network.protocol.version",
  kP = "network.transport",
  FP = "pipe",
  KP = "quic",
  jP = "tcp",
  WP = "udp",
  XP = "unix",
  qP = "network.type",
  zP = "ipv4",
  QP = "ipv6",
  JP = "otel.scope.name",
  ZP = "otel.scope.version",
  ed = "otel.status_code",
  td = "ERROR",
  rd = "OK",
  nd = "otel.status_description",
  ad = "server.address",
  _d = "server.port",
  od = "service.name",
  id = "service.version",
  sd = "signalr.connection.status",
  Ed = "app_shutdown",
  Td = "normal_closure",
  Sd = "timeout",
  Ad = "signalr.transport",
  cd = "long_polling",
  ud = "server_sent_events",
  Rd = "web_sockets",
  ld = "url.fragment",
  Nd = "url.full",
  Od = "url.path",
  vd = "url.query",
  Md = "url.scheme",
  fd = "user_agent.original",
  Pd = "aspnetcore.diagnostics.exceptions",
  dd = "aspnetcore.rate_limiting.active_request_leases",
  pd = "aspnetcore.rate_limiting.queued_requests",
  Cd = "aspnetcore.rate_limiting.request.time_in_queue",
  Ld = "aspnetcore.rate_limiting.request_lease.duration",
  Id = "aspnetcore.rate_limiting.requests",
  Dd = "aspnetcore.routing.match_attempts",
  gd = "http.client.request.duration",
  Ud = "http.server.request.duration",
  hd = "jvm.class.count",
  md = "jvm.class.loaded",
  Vd = "jvm.class.unloaded",
  yd = "jvm.cpu.count",
  bd = "jvm.cpu.recent_utilization",
  Gd = "jvm.cpu.time",
  Bd = "jvm.gc.duration",
  wd = "jvm.memory.committed",
  Yd = "jvm.memory.limit",
  Hd = "jvm.memory.used",
  $d = "jvm.memory.used_after_last_gc",
  xd = "jvm.thread.count",
  kd = "kestrel.active_connections",
  Fd = "kestrel.active_tls_handshakes",
  Kd = "kestrel.connection.duration",
  jd = "kestrel.queued_connections",
  Wd = "kestrel.queued_requests",
  Xd = "kestrel.rejected_connections",
  qd = "kestrel.tls_handshake.duration",
  zd = "kestrel.upgraded_connections",
  Qd = "signalr.server.active_connections",
  Jd = "signalr.server.connection.duration";
const Zd = Object.freeze(
    Object.defineProperty(
      {
        __proto__: null,
        ASPNETCORE_DIAGNOSTICS_EXCEPTION_RESULT_VALUE_ABORTED: xf,
        ASPNETCORE_DIAGNOSTICS_EXCEPTION_RESULT_VALUE_HANDLED: kf,
        ASPNETCORE_DIAGNOSTICS_EXCEPTION_RESULT_VALUE_SKIPPED: Ff,
        ASPNETCORE_DIAGNOSTICS_EXCEPTION_RESULT_VALUE_UNHANDLED: Kf,
        ASPNETCORE_RATE_LIMITING_RESULT_VALUE_ACQUIRED: ff,
        ASPNETCORE_RATE_LIMITING_RESULT_VALUE_ENDPOINT_LIMITER: Pf,
        ASPNETCORE_RATE_LIMITING_RESULT_VALUE_GLOBAL_LIMITER: df,
        ASPNETCORE_RATE_LIMITING_RESULT_VALUE_REQUEST_CANCELED: pf,
        ASPNETCORE_ROUTING_MATCH_STATUS_VALUE_FAILURE: zf,
        ASPNETCORE_ROUTING_MATCH_STATUS_VALUE_SUCCESS: Qf,
        ATTR_ASPNETCORE_DIAGNOSTICS_EXCEPTION_RESULT: $f,
        ATTR_ASPNETCORE_DIAGNOSTICS_HANDLER_TYPE: Hf,
        ATTR_ASPNETCORE_RATE_LIMITING_POLICY: jf,
        ATTR_ASPNETCORE_RATE_LIMITING_RESULT: Mf,
        ATTR_ASPNETCORE_REQUEST_IS_UNHANDLED: Wf,
        ATTR_ASPNETCORE_ROUTING_IS_FALLBACK: Xf,
        ATTR_ASPNETCORE_ROUTING_MATCH_STATUS: qf,
        ATTR_CLIENT_ADDRESS: Jf,
        ATTR_CLIENT_PORT: Zf,
        ATTR_ERROR_TYPE: eP,
        ATTR_EXCEPTION_ESCAPED: rP,
        ATTR_EXCEPTION_MESSAGE: nP,
        ATTR_EXCEPTION_STACKTRACE: aP,
        ATTR_EXCEPTION_TYPE: _P,
        ATTR_HTTP_REQUEST_HEADER: oP,
        ATTR_HTTP_REQUEST_METHOD: iP,
        ATTR_HTTP_REQUEST_METHOD_ORIGINAL: OP,
        ATTR_HTTP_REQUEST_RESEND_COUNT: vP,
        ATTR_HTTP_RESPONSE_HEADER: MP,
        ATTR_HTTP_RESPONSE_STATUS_CODE: fP,
        ATTR_HTTP_ROUTE: PP,
        ATTR_JVM_GC_ACTION: dP,
        ATTR_JVM_GC_NAME: pP,
        ATTR_JVM_MEMORY_POOL_NAME: CP,
        ATTR_JVM_MEMORY_TYPE: LP,
        ATTR_JVM_THREAD_DAEMON: gP,
        ATTR_JVM_THREAD_STATE: UP,
        ATTR_NETWORK_LOCAL_ADDRESS: BP,
        ATTR_NETWORK_LOCAL_PORT: wP,
        ATTR_NETWORK_PEER_ADDRESS: YP,
        ATTR_NETWORK_PEER_PORT: HP,
        ATTR_NETWORK_PROTOCOL_NAME: $P,
        ATTR_NETWORK_PROTOCOL_VERSION: xP,
        ATTR_NETWORK_TRANSPORT: kP,
        ATTR_NETWORK_TYPE: qP,
        ATTR_OTEL_SCOPE_NAME: JP,
        ATTR_OTEL_SCOPE_VERSION: ZP,
        ATTR_OTEL_STATUS_CODE: ed,
        ATTR_OTEL_STATUS_DESCRIPTION: nd,
        ATTR_SERVER_ADDRESS: ad,
        ATTR_SERVER_PORT: _d,
        ATTR_SERVICE_NAME: od,
        ATTR_SERVICE_VERSION: id,
        ATTR_SIGNALR_CONNECTION_STATUS: sd,
        ATTR_SIGNALR_TRANSPORT: Ad,
        ATTR_TELEMETRY_SDK_LANGUAGE: Cf,
        ATTR_TELEMETRY_SDK_NAME: wf,
        ATTR_TELEMETRY_SDK_VERSION: Yf,
        ATTR_URL_FRAGMENT: ld,
        ATTR_URL_FULL: Nd,
        ATTR_URL_PATH: Od,
        ATTR_URL_QUERY: vd,
        ATTR_URL_SCHEME: Md,
        ATTR_USER_AGENT_ORIGINAL: fd,
        AWSECSLAUNCHTYPEVALUES_EC2: YM,
        AWSECSLAUNCHTYPEVALUES_FARGATE: HM,
        AwsEcsLaunchtypeValues: $M,
        CLOUDPLATFORMVALUES_ALIBABA_CLOUD_ECS: fM,
        CLOUDPLATFORMVALUES_ALIBABA_CLOUD_FC: PM,
        CLOUDPLATFORMVALUES_AWS_EC2: dM,
        CLOUDPLATFORMVALUES_AWS_ECS: pM,
        CLOUDPLATFORMVALUES_AWS_EKS: CM,
        CLOUDPLATFORMVALUES_AWS_ELASTIC_BEANSTALK: IM,
        CLOUDPLATFORMVALUES_AWS_LAMBDA: LM,
        CLOUDPLATFORMVALUES_AZURE_AKS: UM,
        CLOUDPLATFORMVALUES_AZURE_APP_SERVICE: mM,
        CLOUDPLATFORMVALUES_AZURE_CONTAINER_INSTANCES: gM,
        CLOUDPLATFORMVALUES_AZURE_FUNCTIONS: hM,
        CLOUDPLATFORMVALUES_AZURE_VM: DM,
        CLOUDPLATFORMVALUES_GCP_APP_ENGINE: BM,
        CLOUDPLATFORMVALUES_GCP_CLOUD_FUNCTIONS: GM,
        CLOUDPLATFORMVALUES_GCP_CLOUD_RUN: yM,
        CLOUDPLATFORMVALUES_GCP_COMPUTE_ENGINE: VM,
        CLOUDPLATFORMVALUES_GCP_KUBERNETES_ENGINE: bM,
        CLOUDPROVIDERVALUES_ALIBABA_CLOUD: lM,
        CLOUDPROVIDERVALUES_AWS: NM,
        CLOUDPROVIDERVALUES_AZURE: OM,
        CLOUDPROVIDERVALUES_GCP: vM,
        CloudPlatformValues: wM,
        CloudProviderValues: MM,
        DBCASSANDRACONSISTENCYLEVELVALUES_ALL: eN,
        DBCASSANDRACONSISTENCYLEVELVALUES_ANY: sN,
        DBCASSANDRACONSISTENCYLEVELVALUES_EACH_QUORUM: tN,
        DBCASSANDRACONSISTENCYLEVELVALUES_LOCAL_ONE: iN,
        DBCASSANDRACONSISTENCYLEVELVALUES_LOCAL_QUORUM: nN,
        DBCASSANDRACONSISTENCYLEVELVALUES_LOCAL_SERIAL: TN,
        DBCASSANDRACONSISTENCYLEVELVALUES_ONE: aN,
        DBCASSANDRACONSISTENCYLEVELVALUES_QUORUM: rN,
        DBCASSANDRACONSISTENCYLEVELVALUES_SERIAL: EN,
        DBCASSANDRACONSISTENCYLEVELVALUES_THREE: oN,
        DBCASSANDRACONSISTENCYLEVELVALUES_TWO: _N,
        DBSYSTEMVALUES_ADABAS: dl,
        DBSYSTEMVALUES_CACHE: Pl,
        DBSYSTEMVALUES_CASSANDRA: Hl,
        DBSYSTEMVALUES_CLOUDSCAPE: ul,
        DBSYSTEMVALUES_COCKROACHDB: Jl,
        DBSYSTEMVALUES_COLDFUSION: Yl,
        DBSYSTEMVALUES_COSMOSDB: jl,
        DBSYSTEMVALUES_COUCHBASE: Fl,
        DBSYSTEMVALUES_COUCHDB: Kl,
        DBSYSTEMVALUES_DB2: Tl,
        DBSYSTEMVALUES_DERBY: Cl,
        DBSYSTEMVALUES_DYNAMODB: Wl,
        DBSYSTEMVALUES_EDB: fl,
        DBSYSTEMVALUES_ELASTICSEARCH: zl,
        DBSYSTEMVALUES_FILEMAKER: Ll,
        DBSYSTEMVALUES_FIREBIRD: pl,
        DBSYSTEMVALUES_FIRSTSQL: Ml,
        DBSYSTEMVALUES_GEODE: ql,
        DBSYSTEMVALUES_H2: wl,
        DBSYSTEMVALUES_HANADB: Ol,
        DBSYSTEMVALUES_HBASE: $l,
        DBSYSTEMVALUES_HIVE: cl,
        DBSYSTEMVALUES_HSQLDB: Rl,
        DBSYSTEMVALUES_INFORMIX: Il,
        DBSYSTEMVALUES_INGRES: vl,
        DBSYSTEMVALUES_INSTANTDB: Dl,
        DBSYSTEMVALUES_INTERBASE: gl,
        DBSYSTEMVALUES_MARIADB: Ul,
        DBSYSTEMVALUES_MAXDB: Nl,
        DBSYSTEMVALUES_MEMCACHED: Ql,
        DBSYSTEMVALUES_MONGODB: xl,
        DBSYSTEMVALUES_MSSQL: il,
        DBSYSTEMVALUES_MYSQL: sl,
        DBSYSTEMVALUES_NEO4J: Xl,
        DBSYSTEMVALUES_NETEZZA: hl,
        DBSYSTEMVALUES_ORACLE: El,
        DBSYSTEMVALUES_OTHER_SQL: ol,
        DBSYSTEMVALUES_PERVASIVE: ml,
        DBSYSTEMVALUES_POINTBASE: Vl,
        DBSYSTEMVALUES_POSTGRESQL: Sl,
        DBSYSTEMVALUES_PROGRESS: ll,
        DBSYSTEMVALUES_REDIS: kl,
        DBSYSTEMVALUES_REDSHIFT: Al,
        DBSYSTEMVALUES_SQLITE: yl,
        DBSYSTEMVALUES_SYBASE: bl,
        DBSYSTEMVALUES_TERADATA: Gl,
        DBSYSTEMVALUES_VERTICA: Bl,
        DbCassandraConsistencyLevelValues: SN,
        DbSystemValues: Zl,
        ERROR_TYPE_VALUE_OTHER: tP,
        FAASDOCUMENTOPERATIONVALUES_DELETE: MN,
        FAASDOCUMENTOPERATIONVALUES_EDIT: vN,
        FAASDOCUMENTOPERATIONVALUES_INSERT: ON,
        FAASINVOKEDPROVIDERVALUES_ALIBABA_CLOUD: PN,
        FAASINVOKEDPROVIDERVALUES_AWS: dN,
        FAASINVOKEDPROVIDERVALUES_AZURE: pN,
        FAASINVOKEDPROVIDERVALUES_GCP: CN,
        FAASTRIGGERVALUES_DATASOURCE: AN,
        FAASTRIGGERVALUES_HTTP: cN,
        FAASTRIGGERVALUES_OTHER: lN,
        FAASTRIGGERVALUES_PUBSUB: uN,
        FAASTRIGGERVALUES_TIMER: RN,
        FaasDocumentOperationValues: fN,
        FaasInvokedProviderValues: LN,
        FaasTriggerValues: NN,
        HOSTARCHVALUES_AMD64: xM,
        HOSTARCHVALUES_ARM32: kM,
        HOSTARCHVALUES_ARM64: FM,
        HOSTARCHVALUES_IA64: KM,
        HOSTARCHVALUES_PPC32: jM,
        HOSTARCHVALUES_PPC64: WM,
        HOSTARCHVALUES_X86: XM,
        HTTPFLAVORVALUES_HTTP_1_0: EO,
        HTTPFLAVORVALUES_HTTP_1_1: TO,
        HTTPFLAVORVALUES_HTTP_2_0: SO,
        HTTPFLAVORVALUES_QUIC: cO,
        HTTPFLAVORVALUES_SPDY: AO,
        HTTP_REQUEST_METHOD_VALUE_CONNECT: EP,
        HTTP_REQUEST_METHOD_VALUE_DELETE: TP,
        HTTP_REQUEST_METHOD_VALUE_GET: SP,
        HTTP_REQUEST_METHOD_VALUE_HEAD: AP,
        HTTP_REQUEST_METHOD_VALUE_OPTIONS: cP,
        HTTP_REQUEST_METHOD_VALUE_OTHER: sP,
        HTTP_REQUEST_METHOD_VALUE_PATCH: uP,
        HTTP_REQUEST_METHOD_VALUE_POST: RP,
        HTTP_REQUEST_METHOD_VALUE_PUT: lP,
        HTTP_REQUEST_METHOD_VALUE_TRACE: NP,
        HostArchValues: qM,
        HttpFlavorValues: uO,
        JVM_MEMORY_TYPE_VALUE_HEAP: IP,
        JVM_MEMORY_TYPE_VALUE_NON_HEAP: DP,
        JVM_THREAD_STATE_VALUE_BLOCKED: hP,
        JVM_THREAD_STATE_VALUE_NEW: mP,
        JVM_THREAD_STATE_VALUE_RUNNABLE: VP,
        JVM_THREAD_STATE_VALUE_TERMINATED: yP,
        JVM_THREAD_STATE_VALUE_TIMED_WAITING: bP,
        JVM_THREAD_STATE_VALUE_WAITING: GP,
        MESSAGETYPEVALUES_RECEIVED: HO,
        MESSAGETYPEVALUES_SENT: YO,
        MESSAGINGDESTINATIONKINDVALUES_QUEUE: RO,
        MESSAGINGDESTINATIONKINDVALUES_TOPIC: lO,
        MESSAGINGOPERATIONVALUES_PROCESS: vO,
        MESSAGINGOPERATIONVALUES_RECEIVE: OO,
        METRIC_ASPNETCORE_DIAGNOSTICS_EXCEPTIONS: Pd,
        METRIC_ASPNETCORE_RATE_LIMITING_ACTIVE_REQUEST_LEASES: dd,
        METRIC_ASPNETCORE_RATE_LIMITING_QUEUED_REQUESTS: pd,
        METRIC_ASPNETCORE_RATE_LIMITING_REQUESTS: Id,
        METRIC_ASPNETCORE_RATE_LIMITING_REQUEST_LEASE_DURATION: Ld,
        METRIC_ASPNETCORE_RATE_LIMITING_REQUEST_TIME_IN_QUEUE: Cd,
        METRIC_ASPNETCORE_ROUTING_MATCH_ATTEMPTS: Dd,
        METRIC_HTTP_CLIENT_REQUEST_DURATION: gd,
        METRIC_HTTP_SERVER_REQUEST_DURATION: Ud,
        METRIC_JVM_CLASS_COUNT: hd,
        METRIC_JVM_CLASS_LOADED: md,
        METRIC_JVM_CLASS_UNLOADED: Vd,
        METRIC_JVM_CPU_COUNT: yd,
        METRIC_JVM_CPU_RECENT_UTILIZATION: bd,
        METRIC_JVM_CPU_TIME: Gd,
        METRIC_JVM_GC_DURATION: Bd,
        METRIC_JVM_MEMORY_COMMITTED: wd,
        METRIC_JVM_MEMORY_LIMIT: Yd,
        METRIC_JVM_MEMORY_USED: Hd,
        METRIC_JVM_MEMORY_USED_AFTER_LAST_GC: $d,
        METRIC_JVM_THREAD_COUNT: xd,
        METRIC_KESTREL_ACTIVE_CONNECTIONS: kd,
        METRIC_KESTREL_ACTIVE_TLS_HANDSHAKES: Fd,
        METRIC_KESTREL_CONNECTION_DURATION: Kd,
        METRIC_KESTREL_QUEUED_CONNECTIONS: jd,
        METRIC_KESTREL_QUEUED_REQUESTS: Wd,
        METRIC_KESTREL_REJECTED_CONNECTIONS: Xd,
        METRIC_KESTREL_TLS_HANDSHAKE_DURATION: qd,
        METRIC_KESTREL_UPGRADED_CONNECTIONS: zd,
        METRIC_SIGNALR_SERVER_ACTIVE_CONNECTIONS: Qd,
        METRIC_SIGNALR_SERVER_CONNECTION_DURATION: Jd,
        MessageTypeValues: $O,
        MessagingDestinationKindValues: NO,
        MessagingOperationValues: MO,
        NETHOSTCONNECTIONSUBTYPEVALUES_CDMA: FN,
        NETHOSTCONNECTIONSUBTYPEVALUES_CDMA2000_1XRTT: WN,
        NETHOSTCONNECTIONSUBTYPEVALUES_EDGE: xN,
        NETHOSTCONNECTIONSUBTYPEVALUES_EHRPD: eO,
        NETHOSTCONNECTIONSUBTYPEVALUES_EVDO_0: KN,
        NETHOSTCONNECTIONSUBTYPEVALUES_EVDO_A: jN,
        NETHOSTCONNECTIONSUBTYPEVALUES_EVDO_B: JN,
        NETHOSTCONNECTIONSUBTYPEVALUES_GPRS: $N,
        NETHOSTCONNECTIONSUBTYPEVALUES_GSM: rO,
        NETHOSTCONNECTIONSUBTYPEVALUES_HSDPA: XN,
        NETHOSTCONNECTIONSUBTYPEVALUES_HSPA: zN,
        NETHOSTCONNECTIONSUBTYPEVALUES_HSPAP: tO,
        NETHOSTCONNECTIONSUBTYPEVALUES_HSUPA: qN,
        NETHOSTCONNECTIONSUBTYPEVALUES_IDEN: QN,
        NETHOSTCONNECTIONSUBTYPEVALUES_IWLAN: aO,
        NETHOSTCONNECTIONSUBTYPEVALUES_LTE: ZN,
        NETHOSTCONNECTIONSUBTYPEVALUES_LTE_CA: iO,
        NETHOSTCONNECTIONSUBTYPEVALUES_NR: _O,
        NETHOSTCONNECTIONSUBTYPEVALUES_NRNSA: oO,
        NETHOSTCONNECTIONSUBTYPEVALUES_TD_SCDMA: nO,
        NETHOSTCONNECTIONSUBTYPEVALUES_UMTS: kN,
        NETHOSTCONNECTIONTYPEVALUES_CELL: BN,
        NETHOSTCONNECTIONTYPEVALUES_UNAVAILABLE: wN,
        NETHOSTCONNECTIONTYPEVALUES_UNKNOWN: YN,
        NETHOSTCONNECTIONTYPEVALUES_WIFI: bN,
        NETHOSTCONNECTIONTYPEVALUES_WIRED: GN,
        NETTRANSPORTVALUES_INPROC: mN,
        NETTRANSPORTVALUES_IP: gN,
        NETTRANSPORTVALUES_IP_TCP: IN,
        NETTRANSPORTVALUES_IP_UDP: DN,
        NETTRANSPORTVALUES_OTHER: VN,
        NETTRANSPORTVALUES_PIPE: hN,
        NETTRANSPORTVALUES_UNIX: UN,
        NETWORK_TRANSPORT_VALUE_PIPE: FP,
        NETWORK_TRANSPORT_VALUE_QUIC: KP,
        NETWORK_TRANSPORT_VALUE_TCP: jP,
        NETWORK_TRANSPORT_VALUE_UDP: WP,
        NETWORK_TRANSPORT_VALUE_UNIX: XP,
        NETWORK_TYPE_VALUE_IPV4: zP,
        NETWORK_TYPE_VALUE_IPV6: QP,
        NetHostConnectionSubtypeValues: sO,
        NetHostConnectionTypeValues: HN,
        NetTransportValues: yN,
        OSTYPEVALUES_AIX: af,
        OSTYPEVALUES_DARWIN: JM,
        OSTYPEVALUES_DRAGONFLYBSD: rf,
        OSTYPEVALUES_FREEBSD: ZM,
        OSTYPEVALUES_HPUX: nf,
        OSTYPEVALUES_LINUX: QM,
        OSTYPEVALUES_NETBSD: ef,
        OSTYPEVALUES_OPENBSD: tf,
        OSTYPEVALUES_SOLARIS: _f,
        OSTYPEVALUES_WINDOWS: zM,
        OSTYPEVALUES_Z_OS: of,
        OTEL_STATUS_CODE_VALUE_ERROR: td,
        OTEL_STATUS_CODE_VALUE_OK: rd,
        OsTypeValues: sf,
        RPCGRPCSTATUSCODEVALUES_ABORTED: hO,
        RPCGRPCSTATUSCODEVALUES_ALREADY_EXISTS: IO,
        RPCGRPCSTATUSCODEVALUES_CANCELLED: PO,
        RPCGRPCSTATUSCODEVALUES_DATA_LOSS: GO,
        RPCGRPCSTATUSCODEVALUES_DEADLINE_EXCEEDED: CO,
        RPCGRPCSTATUSCODEVALUES_FAILED_PRECONDITION: UO,
        RPCGRPCSTATUSCODEVALUES_INTERNAL: yO,
        RPCGRPCSTATUSCODEVALUES_INVALID_ARGUMENT: pO,
        RPCGRPCSTATUSCODEVALUES_NOT_FOUND: LO,
        RPCGRPCSTATUSCODEVALUES_OK: fO,
        RPCGRPCSTATUSCODEVALUES_OUT_OF_RANGE: mO,
        RPCGRPCSTATUSCODEVALUES_PERMISSION_DENIED: DO,
        RPCGRPCSTATUSCODEVALUES_RESOURCE_EXHAUSTED: gO,
        RPCGRPCSTATUSCODEVALUES_UNAUTHENTICATED: BO,
        RPCGRPCSTATUSCODEVALUES_UNAVAILABLE: bO,
        RPCGRPCSTATUSCODEVALUES_UNIMPLEMENTED: VO,
        RPCGRPCSTATUSCODEVALUES_UNKNOWN: dO,
        RpcGrpcStatusCodeValues: wO,
        SEMATTRS_AWS_DYNAMODB_ATTRIBUTES_TO_GET: uR,
        SEMATTRS_AWS_DYNAMODB_ATTRIBUTE_DEFINITIONS: LR,
        SEMATTRS_AWS_DYNAMODB_CONSISTENT_READ: SR,
        SEMATTRS_AWS_DYNAMODB_CONSUMED_CAPACITY: iR,
        SEMATTRS_AWS_DYNAMODB_COUNT: pR,
        SEMATTRS_AWS_DYNAMODB_EXCLUSIVE_START_TABLE: vR,
        SEMATTRS_AWS_DYNAMODB_GLOBAL_SECONDARY_INDEXES: NR,
        SEMATTRS_AWS_DYNAMODB_GLOBAL_SECONDARY_INDEX_UPDATES: IR,
        SEMATTRS_AWS_DYNAMODB_INDEX_NAME: RR,
        SEMATTRS_AWS_DYNAMODB_ITEM_COLLECTION_METRICS: sR,
        SEMATTRS_AWS_DYNAMODB_LIMIT: cR,
        SEMATTRS_AWS_DYNAMODB_LOCAL_SECONDARY_INDEXES: OR,
        SEMATTRS_AWS_DYNAMODB_PROJECTION: AR,
        SEMATTRS_AWS_DYNAMODB_PROVISIONED_READ_CAPACITY: ER,
        SEMATTRS_AWS_DYNAMODB_PROVISIONED_WRITE_CAPACITY: TR,
        SEMATTRS_AWS_DYNAMODB_SCANNED_COUNT: CR,
        SEMATTRS_AWS_DYNAMODB_SCAN_FORWARD: fR,
        SEMATTRS_AWS_DYNAMODB_SEGMENT: PR,
        SEMATTRS_AWS_DYNAMODB_SELECT: lR,
        SEMATTRS_AWS_DYNAMODB_TABLE_COUNT: MR,
        SEMATTRS_AWS_DYNAMODB_TABLE_NAMES: oR,
        SEMATTRS_AWS_DYNAMODB_TOTAL_SEGMENTS: dR,
        SEMATTRS_AWS_LAMBDA_INVOKED_ARN: Yc,
        SEMATTRS_CODE_FILEPATH: ku,
        SEMATTRS_CODE_FUNCTION: $u,
        SEMATTRS_CODE_LINENO: Fu,
        SEMATTRS_CODE_NAMESPACE: xu,
        SEMATTRS_DB_CASSANDRA_CONSISTENCY_LEVEL: zc,
        SEMATTRS_DB_CASSANDRA_COORDINATOR_DC: tu,
        SEMATTRS_DB_CASSANDRA_COORDINATOR_ID: eu,
        SEMATTRS_DB_CASSANDRA_IDEMPOTENCE: Jc,
        SEMATTRS_DB_CASSANDRA_KEYSPACE: Xc,
        SEMATTRS_DB_CASSANDRA_PAGE_SIZE: qc,
        SEMATTRS_DB_CASSANDRA_SPECULATIVE_EXECUTION_COUNT: Zc,
        SEMATTRS_DB_CASSANDRA_TABLE: Qc,
        SEMATTRS_DB_CONNECTION_STRING: $c,
        SEMATTRS_DB_HBASE_NAMESPACE: ru,
        SEMATTRS_DB_JDBC_DRIVER_CLASSNAME: kc,
        SEMATTRS_DB_MONGODB_COLLECTION: au,
        SEMATTRS_DB_MSSQL_INSTANCE_NAME: Wc,
        SEMATTRS_DB_NAME: Fc,
        SEMATTRS_DB_OPERATION: jc,
        SEMATTRS_DB_REDIS_DATABASE_INDEX: nu,
        SEMATTRS_DB_SQL_TABLE: _u,
        SEMATTRS_DB_STATEMENT: Kc,
        SEMATTRS_DB_SYSTEM: Hc,
        SEMATTRS_DB_USER: xc,
        SEMATTRS_ENDUSER_ID: Gu,
        SEMATTRS_ENDUSER_ROLE: Bu,
        SEMATTRS_ENDUSER_SCOPE: wu,
        SEMATTRS_EXCEPTION_ESCAPED: Eu,
        SEMATTRS_EXCEPTION_MESSAGE: iu,
        SEMATTRS_EXCEPTION_STACKTRACE: su,
        SEMATTRS_EXCEPTION_TYPE: ou,
        SEMATTRS_FAAS_COLDSTART: Ou,
        SEMATTRS_FAAS_CRON: Nu,
        SEMATTRS_FAAS_DOCUMENT_COLLECTION: Au,
        SEMATTRS_FAAS_DOCUMENT_NAME: Ru,
        SEMATTRS_FAAS_DOCUMENT_OPERATION: cu,
        SEMATTRS_FAAS_DOCUMENT_TIME: uu,
        SEMATTRS_FAAS_EXECUTION: Su,
        SEMATTRS_FAAS_INVOKED_NAME: vu,
        SEMATTRS_FAAS_INVOKED_PROVIDER: Mu,
        SEMATTRS_FAAS_INVOKED_REGION: fu,
        SEMATTRS_FAAS_TIME: lu,
        SEMATTRS_FAAS_TRIGGER: Tu,
        SEMATTRS_HTTP_CLIENT_IP: _R,
        SEMATTRS_HTTP_FLAVOR: Qu,
        SEMATTRS_HTTP_HOST: Xu,
        SEMATTRS_HTTP_METHOD: Ku,
        SEMATTRS_HTTP_REQUEST_CONTENT_LENGTH: Zu,
        SEMATTRS_HTTP_REQUEST_CONTENT_LENGTH_UNCOMPRESSED: eR,
        SEMATTRS_HTTP_RESPONSE_CONTENT_LENGTH: tR,
        SEMATTRS_HTTP_RESPONSE_CONTENT_LENGTH_UNCOMPRESSED: rR,
        SEMATTRS_HTTP_ROUTE: aR,
        SEMATTRS_HTTP_SCHEME: qu,
        SEMATTRS_HTTP_SERVER_NAME: nR,
        SEMATTRS_HTTP_STATUS_CODE: zu,
        SEMATTRS_HTTP_TARGET: Wu,
        SEMATTRS_HTTP_URL: ju,
        SEMATTRS_HTTP_USER_AGENT: Ju,
        SEMATTRS_MESSAGE_COMPRESSED_SIZE: nl,
        SEMATTRS_MESSAGE_ID: rl,
        SEMATTRS_MESSAGE_TYPE: tl,
        SEMATTRS_MESSAGE_UNCOMPRESSED_SIZE: al,
        SEMATTRS_MESSAGING_CONSUMER_ID: HR,
        SEMATTRS_MESSAGING_CONVERSATION_ID: GR,
        SEMATTRS_MESSAGING_DESTINATION: gR,
        SEMATTRS_MESSAGING_DESTINATION_KIND: UR,
        SEMATTRS_MESSAGING_KAFKA_CLIENT_ID: FR,
        SEMATTRS_MESSAGING_KAFKA_CONSUMER_GROUP: kR,
        SEMATTRS_MESSAGING_KAFKA_MESSAGE_KEY: xR,
        SEMATTRS_MESSAGING_KAFKA_PARTITION: KR,
        SEMATTRS_MESSAGING_KAFKA_TOMBSTONE: jR,
        SEMATTRS_MESSAGING_MESSAGE_ID: bR,
        SEMATTRS_MESSAGING_MESSAGE_PAYLOAD_COMPRESSED_SIZE_BYTES: wR,
        SEMATTRS_MESSAGING_MESSAGE_PAYLOAD_SIZE_BYTES: BR,
        SEMATTRS_MESSAGING_OPERATION: YR,
        SEMATTRS_MESSAGING_PROTOCOL: mR,
        SEMATTRS_MESSAGING_PROTOCOL_VERSION: VR,
        SEMATTRS_MESSAGING_RABBITMQ_ROUTING_KEY: $R,
        SEMATTRS_MESSAGING_SYSTEM: DR,
        SEMATTRS_MESSAGING_TEMP_DESTINATION: hR,
        SEMATTRS_MESSAGING_URL: yR,
        SEMATTRS_NET_HOST_CARRIER_ICC: yu,
        SEMATTRS_NET_HOST_CARRIER_MCC: mu,
        SEMATTRS_NET_HOST_CARRIER_MNC: Vu,
        SEMATTRS_NET_HOST_CARRIER_NAME: hu,
        SEMATTRS_NET_HOST_CONNECTION_SUBTYPE: Uu,
        SEMATTRS_NET_HOST_CONNECTION_TYPE: gu,
        SEMATTRS_NET_HOST_IP: Lu,
        SEMATTRS_NET_HOST_NAME: Du,
        SEMATTRS_NET_HOST_PORT: Iu,
        SEMATTRS_NET_PEER_IP: du,
        SEMATTRS_NET_PEER_NAME: Cu,
        SEMATTRS_NET_PEER_PORT: pu,
        SEMATTRS_NET_TRANSPORT: Pu,
        SEMATTRS_PEER_SERVICE: bu,
        SEMATTRS_RPC_GRPC_STATUS_CODE: zR,
        SEMATTRS_RPC_JSONRPC_ERROR_CODE: ZR,
        SEMATTRS_RPC_JSONRPC_ERROR_MESSAGE: el,
        SEMATTRS_RPC_JSONRPC_REQUEST_ID: JR,
        SEMATTRS_RPC_JSONRPC_VERSION: QR,
        SEMATTRS_RPC_METHOD: qR,
        SEMATTRS_RPC_SERVICE: XR,
        SEMATTRS_RPC_SYSTEM: WR,
        SEMATTRS_THREAD_ID: Yu,
        SEMATTRS_THREAD_NAME: Hu,
        SEMRESATTRS_AWS_ECS_CLUSTER_ARN: XO,
        SEMRESATTRS_AWS_ECS_CONTAINER_ARN: WO,
        SEMRESATTRS_AWS_ECS_LAUNCHTYPE: qO,
        SEMRESATTRS_AWS_ECS_TASK_ARN: zO,
        SEMRESATTRS_AWS_ECS_TASK_FAMILY: QO,
        SEMRESATTRS_AWS_ECS_TASK_REVISION: JO,
        SEMRESATTRS_AWS_EKS_CLUSTER_ARN: ZO,
        SEMRESATTRS_AWS_LOG_GROUP_ARNS: tv,
        SEMRESATTRS_AWS_LOG_GROUP_NAMES: ev,
        SEMRESATTRS_AWS_LOG_STREAM_ARNS: nv,
        SEMRESATTRS_AWS_LOG_STREAM_NAMES: rv,
        SEMRESATTRS_CLOUD_ACCOUNT_ID: kO,
        SEMRESATTRS_CLOUD_AVAILABILITY_ZONE: KO,
        SEMRESATTRS_CLOUD_PLATFORM: jO,
        SEMRESATTRS_CLOUD_PROVIDER: xO,
        SEMRESATTRS_CLOUD_REGION: FO,
        SEMRESATTRS_CONTAINER_ID: _v,
        SEMRESATTRS_CONTAINER_IMAGE_NAME: iv,
        SEMRESATTRS_CONTAINER_IMAGE_TAG: sv,
        SEMRESATTRS_CONTAINER_NAME: av,
        SEMRESATTRS_CONTAINER_RUNTIME: ov,
        SEMRESATTRS_DEPLOYMENT_ENVIRONMENT: Ev,
        SEMRESATTRS_DEVICE_ID: Tv,
        SEMRESATTRS_DEVICE_MODEL_IDENTIFIER: Sv,
        SEMRESATTRS_DEVICE_MODEL_NAME: Av,
        SEMRESATTRS_FAAS_ID: uv,
        SEMRESATTRS_FAAS_INSTANCE: lv,
        SEMRESATTRS_FAAS_MAX_MEMORY: Nv,
        SEMRESATTRS_FAAS_NAME: cv,
        SEMRESATTRS_FAAS_VERSION: Rv,
        SEMRESATTRS_HOST_ARCH: fv,
        SEMRESATTRS_HOST_ID: Ov,
        SEMRESATTRS_HOST_IMAGE_ID: dv,
        SEMRESATTRS_HOST_IMAGE_NAME: Pv,
        SEMRESATTRS_HOST_IMAGE_VERSION: pv,
        SEMRESATTRS_HOST_NAME: vv,
        SEMRESATTRS_HOST_TYPE: Mv,
        SEMRESATTRS_K8S_CLUSTER_NAME: Cv,
        SEMRESATTRS_K8S_CONTAINER_NAME: hv,
        SEMRESATTRS_K8S_CRONJOB_NAME: kv,
        SEMRESATTRS_K8S_CRONJOB_UID: xv,
        SEMRESATTRS_K8S_DAEMONSET_NAME: Yv,
        SEMRESATTRS_K8S_DAEMONSET_UID: wv,
        SEMRESATTRS_K8S_DEPLOYMENT_NAME: bv,
        SEMRESATTRS_K8S_DEPLOYMENT_UID: yv,
        SEMRESATTRS_K8S_JOB_NAME: $v,
        SEMRESATTRS_K8S_JOB_UID: Hv,
        SEMRESATTRS_K8S_NAMESPACE_NAME: Dv,
        SEMRESATTRS_K8S_NODE_NAME: Lv,
        SEMRESATTRS_K8S_NODE_UID: Iv,
        SEMRESATTRS_K8S_POD_NAME: Uv,
        SEMRESATTRS_K8S_POD_UID: gv,
        SEMRESATTRS_K8S_REPLICASET_NAME: Vv,
        SEMRESATTRS_K8S_REPLICASET_UID: mv,
        SEMRESATTRS_K8S_STATEFULSET_NAME: Bv,
        SEMRESATTRS_K8S_STATEFULSET_UID: Gv,
        SEMRESATTRS_OS_DESCRIPTION: Kv,
        SEMRESATTRS_OS_NAME: jv,
        SEMRESATTRS_OS_TYPE: Fv,
        SEMRESATTRS_OS_VERSION: Wv,
        SEMRESATTRS_PROCESS_COMMAND: Qv,
        SEMRESATTRS_PROCESS_COMMAND_ARGS: Zv,
        SEMRESATTRS_PROCESS_COMMAND_LINE: Jv,
        SEMRESATTRS_PROCESS_EXECUTABLE_NAME: qv,
        SEMRESATTRS_PROCESS_EXECUTABLE_PATH: zv,
        SEMRESATTRS_PROCESS_OWNER: eM,
        SEMRESATTRS_PROCESS_PID: Xv,
        SEMRESATTRS_PROCESS_RUNTIME_DESCRIPTION: nM,
        SEMRESATTRS_PROCESS_RUNTIME_NAME: tM,
        SEMRESATTRS_PROCESS_RUNTIME_VERSION: rM,
        SEMRESATTRS_SERVICE_INSTANCE_ID: oM,
        SEMRESATTRS_SERVICE_NAME: aM,
        SEMRESATTRS_SERVICE_NAMESPACE: _M,
        SEMRESATTRS_SERVICE_VERSION: iM,
        SEMRESATTRS_TELEMETRY_AUTO_VERSION: SM,
        SEMRESATTRS_TELEMETRY_SDK_LANGUAGE: EM,
        SEMRESATTRS_TELEMETRY_SDK_NAME: sM,
        SEMRESATTRS_TELEMETRY_SDK_VERSION: TM,
        SEMRESATTRS_WEBENGINE_DESCRIPTION: uM,
        SEMRESATTRS_WEBENGINE_NAME: AM,
        SEMRESATTRS_WEBENGINE_VERSION: cM,
        SIGNALR_CONNECTION_STATUS_VALUE_APP_SHUTDOWN: Ed,
        SIGNALR_CONNECTION_STATUS_VALUE_NORMAL_CLOSURE: Td,
        SIGNALR_CONNECTION_STATUS_VALUE_TIMEOUT: Sd,
        SIGNALR_TRANSPORT_VALUE_LONG_POLLING: cd,
        SIGNALR_TRANSPORT_VALUE_SERVER_SENT_EVENTS: ud,
        SIGNALR_TRANSPORT_VALUE_WEB_SOCKETS: Rd,
        SemanticAttributes: _l,
        SemanticResourceAttributes: RM,
        TELEMETRYSDKLANGUAGEVALUES_CPP: Ef,
        TELEMETRYSDKLANGUAGEVALUES_DOTNET: Tf,
        TELEMETRYSDKLANGUAGEVALUES_ERLANG: Sf,
        TELEMETRYSDKLANGUAGEVALUES_GO: Af,
        TELEMETRYSDKLANGUAGEVALUES_JAVA: cf,
        TELEMETRYSDKLANGUAGEVALUES_NODEJS: uf,
        TELEMETRYSDKLANGUAGEVALUES_PHP: Rf,
        TELEMETRYSDKLANGUAGEVALUES_PYTHON: lf,
        TELEMETRYSDKLANGUAGEVALUES_RUBY: Nf,
        TELEMETRYSDKLANGUAGEVALUES_WEBJS: Of,
        TELEMETRY_SDK_LANGUAGE_VALUE_CPP: Lf,
        TELEMETRY_SDK_LANGUAGE_VALUE_DOTNET: If,
        TELEMETRY_SDK_LANGUAGE_VALUE_ERLANG: Df,
        TELEMETRY_SDK_LANGUAGE_VALUE_GO: gf,
        TELEMETRY_SDK_LANGUAGE_VALUE_JAVA: Uf,
        TELEMETRY_SDK_LANGUAGE_VALUE_NODEJS: hf,
        TELEMETRY_SDK_LANGUAGE_VALUE_PHP: mf,
        TELEMETRY_SDK_LANGUAGE_VALUE_PYTHON: Vf,
        TELEMETRY_SDK_LANGUAGE_VALUE_RUBY: yf,
        TELEMETRY_SDK_LANGUAGE_VALUE_RUST: bf,
        TELEMETRY_SDK_LANGUAGE_VALUE_SWIFT: Gf,
        TELEMETRY_SDK_LANGUAGE_VALUE_WEBJS: Bf,
        TelemetrySdkLanguageValues: vf,
      },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  ),
  ep = Ve(Zd);
var Q = {},
  or;
function MC() {
  if (or) return Q;
  ((or = 1),
    Object.defineProperty(Q, "__esModule", { value: !0 }),
    (Q.addSqlCommenterComment = void 0));
  const t = Re,
    e = wc;
  function r(_) {
    const o = _.indexOf("--");
    if (o >= 0) return !0;
    if (_.indexOf("/*") < 0) return !1;
    const s = _.indexOf("*/");
    return o < s;
  }
  function n(_) {
    return encodeURIComponent(_).replace(
      /[!'()*]/g,
      (o) => `%${o.charCodeAt(0).toString(16).toUpperCase()}`,
    );
  }
  function a(_, o) {
    if (typeof o != "string" || o.length === 0 || r(o)) return o;
    const i = new e.W3CTraceContextPropagator(),
      s = {};
    i.inject(t.trace.setSpan(t.ROOT_CONTEXT, _), s, t.defaultTextMapSetter);
    const T = Object.keys(s).sort();
    if (T.length === 0) return o;
    const E = T.map((S) => {
      const A = n(s[S]);
      return `${S}='${A}'`;
    }).join(",");
    return `${o} /*${E}*/`;
  }
  return ((Q.addSqlCommenterComment = a), Q);
}
var rt = {},
  J = {};
class NT {
  emit(e) {}
}
const tp = new NT();
class rp {
  getLogger(e, r, n) {
    return new NT();
  }
}
const OT = new rp();
class np {
  constructor(e, r, n, a) {
    ((this._provider = e),
      (this.name = r),
      (this.version = n),
      (this.options = a));
  }
  emit(e) {
    this._getLogger().emit(e);
  }
  _getLogger() {
    if (this._delegate) return this._delegate;
    const e = this._provider._getDelegateLogger(
      this.name,
      this.version,
      this.options,
    );
    return e ? ((this._delegate = e), this._delegate) : tp;
  }
}
class ir {
  getLogger(e, r, n) {
    var a;
    return (a = this._getDelegateLogger(e, r, n)) !== null && a !== void 0
      ? a
      : new np(this, e, r, n);
  }
  _getDelegate() {
    var e;
    return (e = this._delegate) !== null && e !== void 0 ? e : OT;
  }
  _setDelegate(e) {
    this._delegate = e;
  }
  _getDelegateLogger(e, r, n) {
    var a;
    return (a = this._delegate) === null || a === void 0
      ? void 0
      : a.getLogger(e, r, n);
  }
}
const ap = typeof globalThis == "object" ? globalThis : global,
  ve = Symbol.for("io.opentelemetry.js.api.logs"),
  Z = ap;
function _p(t, e, r) {
  return (n) => (n === t ? e : r);
}
const sr = 1;
class ht {
  constructor() {
    this._proxyLoggerProvider = new ir();
  }
  static getInstance() {
    return (this._instance || (this._instance = new ht()), this._instance);
  }
  setGlobalLoggerProvider(e) {
    return Z[ve]
      ? this.getLoggerProvider()
      : ((Z[ve] = _p(sr, e, OT)), this._proxyLoggerProvider._setDelegate(e), e);
  }
  getLoggerProvider() {
    var e, r;
    return (r =
      (e = Z[ve]) === null || e === void 0 ? void 0 : e.call(Z, sr)) !== null &&
      r !== void 0
      ? r
      : this._proxyLoggerProvider;
  }
  getLogger(e, r, n) {
    return this.getLoggerProvider().getLogger(e, r, n);
  }
  disable() {
    (delete Z[ve], (this._proxyLoggerProvider = new ir()));
  }
}
const vT = ht.getInstance();
function op(t, e, r, n) {
  for (let a = 0, _ = t.length; a < _; a++) {
    const o = t[a];
    (e && o.setTracerProvider(e),
      r && o.setMeterProvider(r),
      n && o.setLoggerProvider && o.setLoggerProvider(n),
      o.getConfig().enabled || o.enable());
  }
}
function ip(t) {
  t.forEach((e) => e.disable());
}
function sp(t) {
  const e = t.tracerProvider || C.getTracerProvider(),
    r = t.meterProvider || Ge.getMeterProvider(),
    n = t.loggerProvider || vT.getLoggerProvider(),
    a = t.instrumentations?.flat() ?? [];
  return (
    op(a, e, r, n),
    () => {
      ip(a);
    }
  );
}
const MT =
    /^(?:v)?(?<version>(?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)\.(?<patch>0|[1-9]\d*))(?:-(?<prerelease>(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+(?<build>[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$/,
  Ep =
    /^(?<op><|>|=|==|<=|>=|~|\^|~>)?\s*(?:v)?(?<version>(?<major>x|X|\*|0|[1-9]\d*)(?:\.(?<minor>x|X|\*|0|[1-9]\d*))?(?:\.(?<patch>x|X|\*|0|[1-9]\d*))?)(?:-(?<prerelease>(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+(?<build>[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$/,
  Tp = {
    ">": [1],
    ">=": [0, 1],
    "=": [0],
    "<=": [-1, 0],
    "<": [-1],
    "!=": [-1, 1],
  };
function Sp(t, e, r) {
  if (!Ap(t)) return (c.error(`Invalid version: ${t}`), !1);
  if (!e) return !0;
  e = e.replace(/([<>=~^]+)\s+/g, "$1");
  const n = lp(t);
  if (!n) return !1;
  const a = [],
    _ = fT(n, e, a, r);
  return _ && !r?.includePrerelease ? up(n, a) : _;
}
function Ap(t) {
  return typeof t == "string" && MT.test(t);
}
function fT(t, e, r, n) {
  if (e.includes("||")) {
    const a = e.trim().split("||");
    for (const _ of a) if (nt(t, _, r, n)) return !0;
    return !1;
  } else if (e.includes(" - ")) e = Bp(e, n);
  else if (e.includes(" ")) {
    const a = e
      .trim()
      .replace(/\s{2,}/g, " ")
      .split(" ");
    for (const _ of a) if (!nt(t, _, r, n)) return !1;
    return !0;
  }
  return nt(t, e, r, n);
}
function nt(t, e, r, n) {
  if (((e = Rp(e, n)), e.includes(" "))) return fT(t, e, r, n);
  {
    const a = Np(e);
    return (r.push(a), cp(t, a));
  }
}
function cp(t, e) {
  if (e.invalid) return !1;
  if (!e.version || ut(e.version)) return !0;
  let r = Tr(t.versionSegments || [], e.versionSegments || []);
  if (r === 0) {
    const n = t.prereleaseSegments || [],
      a = e.prereleaseSegments || [];
    !n.length && !a.length
      ? (r = 0)
      : !n.length && a.length
        ? (r = 1)
        : n.length && !a.length
          ? (r = -1)
          : (r = Tr(n, a));
  }
  return Tp[e.op]?.includes(r);
}
function up(t, e) {
  return t.prerelease
    ? e.some((r) => r.prerelease && r.version === t.version)
    : !0;
}
function Rp(t, e) {
  return (
    (t = t.trim()),
    (t = bp(t, e)),
    (t = yp(t)),
    (t = Gp(t, e)),
    (t = t.trim()),
    t
  );
}
function d(t) {
  return !t || t.toLowerCase() === "x" || t === "*";
}
function lp(t) {
  const e = t.match(MT);
  if (!e) {
    c.error(`Invalid version: ${t}`);
    return;
  }
  const r = e.groups.version,
    n = e.groups.prerelease,
    a = e.groups.build,
    _ = r.split("."),
    o = n?.split(".");
  return {
    op: void 0,
    version: r,
    versionSegments: _,
    versionSegmentCount: _.length,
    prerelease: n,
    prereleaseSegments: o,
    prereleaseSegmentCount: o ? o.length : 0,
    build: a,
  };
}
function Np(t) {
  if (!t) return {};
  const e = t.match(Ep);
  if (!e) return (c.error(`Invalid range: ${t}`), { invalid: !0 });
  let r = e.groups.op;
  const n = e.groups.version,
    a = e.groups.prerelease,
    _ = e.groups.build,
    o = n.split("."),
    i = a?.split(".");
  return (
    r === "==" && (r = "="),
    {
      op: r || "=",
      version: n,
      versionSegments: o,
      versionSegmentCount: o.length,
      prerelease: a,
      prereleaseSegments: i,
      prereleaseSegmentCount: i ? i.length : 0,
      build: _,
    }
  );
}
function ut(t) {
  return t === "*" || t === "x" || t === "X";
}
function Er(t) {
  const e = parseInt(t, 10);
  return isNaN(e) ? t : e;
}
function Op(t, e) {
  if (typeof t == typeof e) {
    if (typeof t == "number") return [t, e];
    if (typeof t == "string") return [t, e];
    throw new Error("Version segments can only be strings or numbers");
  } else return [String(t), String(e)];
}
function vp(t, e) {
  if (ut(t) || ut(e)) return 0;
  const [r, n] = Op(Er(t), Er(e));
  return r > n ? 1 : r < n ? -1 : 0;
}
function Tr(t, e) {
  for (let r = 0; r < Math.max(t.length, e.length); r++) {
    const n = vp(t[r] || "0", e[r] || "0");
    if (n !== 0) return n;
  }
  return 0;
}
const PT = "[a-zA-Z0-9-]",
  dT = "0|[1-9]\\d*",
  Mp = `\\d*[a-zA-Z-]${PT}*`,
  fp = "((?:<|>)?=?)",
  Sr = `(?:${dT}|${Mp})`,
  Pp = `(?:-(${Sr}(?:\\.${Sr})*))`,
  Ar = `${PT}+`,
  dp = `(?:\\+(${Ar}(?:\\.${Ar})*))`,
  at = `${dT}|x|X|\\*`,
  Te = `[v=\\s]*(${at})(?:\\.(${at})(?:\\.(${at})(?:${Pp})?${dp}?)?)?`,
  pp = `^${fp}\\s*${Te}$`,
  Cp = new RegExp(pp),
  Lp = `^\\s*(${Te})\\s+-\\s+(${Te})\\s*$`,
  Ip = new RegExp(Lp),
  Dp = "(?:~>?)",
  gp = `^${Dp}${Te}$`,
  Up = new RegExp(gp),
  hp = "(?:\\^)",
  mp = `^${hp}${Te}$`,
  Vp = new RegExp(mp);
function yp(t) {
  const e = Up;
  return t.replace(e, (r, n, a, _, o) => {
    let i;
    return (
      d(n)
        ? (i = "")
        : d(a)
          ? (i = `>=${n}.0.0 <${+n + 1}.0.0-0`)
          : d(_)
            ? (i = `>=${n}.${a}.0 <${n}.${+a + 1}.0-0`)
            : o
              ? (i = `>=${n}.${a}.${_}-${o} <${n}.${+a + 1}.0-0`)
              : (i = `>=${n}.${a}.${_} <${n}.${+a + 1}.0-0`),
      i
    );
  });
}
function bp(t, e) {
  const r = Vp,
    n = e?.includePrerelease ? "-0" : "";
  return t.replace(r, (a, _, o, i, s) => {
    let T;
    return (
      d(_)
        ? (T = "")
        : d(o)
          ? (T = `>=${_}.0.0${n} <${+_ + 1}.0.0-0`)
          : d(i)
            ? _ === "0"
              ? (T = `>=${_}.${o}.0${n} <${_}.${+o + 1}.0-0`)
              : (T = `>=${_}.${o}.0${n} <${+_ + 1}.0.0-0`)
            : s
              ? _ === "0"
                ? o === "0"
                  ? (T = `>=${_}.${o}.${i}-${s} <${_}.${o}.${+i + 1}-0`)
                  : (T = `>=${_}.${o}.${i}-${s} <${_}.${+o + 1}.0-0`)
                : (T = `>=${_}.${o}.${i}-${s} <${+_ + 1}.0.0-0`)
              : _ === "0"
                ? o === "0"
                  ? (T = `>=${_}.${o}.${i}${n} <${_}.${o}.${+i + 1}-0`)
                  : (T = `>=${_}.${o}.${i}${n} <${_}.${+o + 1}.0-0`)
                : (T = `>=${_}.${o}.${i} <${+_ + 1}.0.0-0`),
      T
    );
  });
}
function Gp(t, e) {
  const r = Cp;
  return t.replace(r, (n, a, _, o, i, s) => {
    const T = d(_),
      E = T || d(o),
      S = E || d(i),
      A = S;
    return (
      a === "=" && A && (a = ""),
      (s = e?.includePrerelease ? "-0" : ""),
      T
        ? a === ">" || a === "<"
          ? (n = "<0.0.0-0")
          : (n = "*")
        : a && A
          ? (E && (o = 0),
            (i = 0),
            a === ">"
              ? ((a = ">="),
                E ? ((_ = +_ + 1), (o = 0), (i = 0)) : ((o = +o + 1), (i = 0)))
              : a === "<=" && ((a = "<"), E ? (_ = +_ + 1) : (o = +o + 1)),
            a === "<" && (s = "-0"),
            (n = `${a + _}.${o}.${i}${s}`))
          : E
            ? (n = `>=${_}.0.0${s} <${+_ + 1}.0.0-0`)
            : S && (n = `>=${_}.${o}.0${s} <${_}.${+o + 1}.0-0`),
      n
    );
  });
}
function Bp(t, e) {
  const r = Ip;
  return t.replace(
    r,
    (n, a, _, o, i, s, T, E, S, A, u, M) => (
      d(_)
        ? (a = "")
        : d(o)
          ? (a = `>=${_}.0.0${e?.includePrerelease ? "-0" : ""}`)
          : d(i)
            ? (a = `>=${_}.${o}.0${e?.includePrerelease ? "-0" : ""}`)
            : s
              ? (a = `>=${a}`)
              : (a = `>=${a}${e?.includePrerelease ? "-0" : ""}`),
      d(S)
        ? (E = "")
        : d(A)
          ? (E = `<${+S + 1}.0.0-0`)
          : d(u)
            ? (E = `<${S}.${+A + 1}.0-0`)
            : M
              ? (E = `<=${S}.${A}.${u}-${M}`)
              : e?.includePrerelease
                ? (E = `<${S}.${A}.${+u + 1}-0`)
                : (E = `<=${E}`),
      `${a} ${E}`.trim()
    ),
  );
}
let L = console.error.bind(console);
function ee(t, e, r) {
  const n = !!t[e] && Object.prototype.propertyIsEnumerable.call(t, e);
  Object.defineProperty(t, e, {
    configurable: !0,
    enumerable: n,
    writable: !0,
    value: r,
  });
}
const he = (t, e, r) => {
    if (!t || !t[e]) {
      L("no original function " + String(e) + " to wrap");
      return;
    }
    if (!r) {
      (L("no wrapper function"), L(new Error().stack));
      return;
    }
    const n = t[e];
    if (typeof n != "function" || typeof r != "function") {
      L("original object and wrapper must be functions");
      return;
    }
    const a = r(n, e);
    return (
      ee(a, "__original", n),
      ee(a, "__unwrap", () => {
        t[e] === a && ee(t, e, n);
      }),
      ee(a, "__wrapped", !0),
      ee(t, e, a),
      a
    );
  },
  wp = (t, e, r) => {
    if (t) Array.isArray(t) || (t = [t]);
    else {
      (L("must provide one or more modules to patch"), L(new Error().stack));
      return;
    }
    if (!(e && Array.isArray(e))) {
      L("must provide one or more functions to wrap on modules");
      return;
    }
    t.forEach((n) => {
      e.forEach((a) => {
        he(n, a, r);
      });
    });
  },
  mt = (t, e) => {
    if (!t || !t[e]) {
      (L("no function to unwrap."), L(new Error().stack));
      return;
    }
    const r = t[e];
    if (!r.__unwrap)
      L(
        "no original to unwrap to -- has " +
          String(e) +
          " already been unwrapped?",
      );
    else {
      r.__unwrap();
      return;
    }
  },
  Yp = (t, e) => {
    if (t) Array.isArray(t) || (t = [t]);
    else {
      (L("must provide one or more modules to patch"), L(new Error().stack));
      return;
    }
    if (!(e && Array.isArray(e))) {
      L("must provide one or more functions to unwrap on modules");
      return;
    }
    t.forEach((r) => {
      e.forEach((n) => {
        mt(r, n);
      });
    });
  };
class Hp {
  instrumentationName;
  instrumentationVersion;
  _config = {};
  _tracer;
  _meter;
  _logger;
  _diag;
  constructor(e, r, n) {
    ((this.instrumentationName = e),
      (this.instrumentationVersion = r),
      this.setConfig(n),
      (this._diag = c.createComponentLogger({ namespace: e })),
      (this._tracer = C.getTracer(e, r)),
      (this._meter = Ge.getMeter(e, r)),
      (this._logger = vT.getLogger(e, r)),
      this._updateMetricInstruments());
  }
  _wrap = he;
  _unwrap = mt;
  _massWrap = wp;
  _massUnwrap = Yp;
  get meter() {
    return this._meter;
  }
  setMeterProvider(e) {
    ((this._meter = e.getMeter(
      this.instrumentationName,
      this.instrumentationVersion,
    )),
      this._updateMetricInstruments());
  }
  get logger() {
    return this._logger;
  }
  setLoggerProvider(e) {
    this._logger = e.getLogger(
      this.instrumentationName,
      this.instrumentationVersion,
    );
  }
  getModuleDefinitions() {
    const e = this.init() ?? [];
    return Array.isArray(e) ? e : [e];
  }
  _updateMetricInstruments() {}
  getConfig() {
    return this._config;
  }
  setConfig(e) {
    this._config = { enabled: !0, ...e };
  }
  setTracerProvider(e) {
    this._tracer = e.getTracer(
      this.instrumentationName,
      this.instrumentationVersion,
    );
  }
  get tracer() {
    return this._tracer;
  }
  _runSpanCustomizationHook(e, r, n, a) {
    if (e)
      try {
        e(n, a);
      } catch (_) {
        this._diag.error(
          "Error running span customization hook due to exception in handler",
          { triggerName: r },
          _,
        );
      }
  }
}
const cr = "/";
class ur {
  hooks = [];
  children = new Map();
}
class $p {
  _trie = new ur();
  _counter = 0;
  insert(e) {
    let r = this._trie;
    for (const n of e.moduleName.split(cr)) {
      let a = r.children.get(n);
      (a || ((a = new ur()), r.children.set(n, a)), (r = a));
    }
    r.hooks.push({ hook: e, insertedId: this._counter++ });
  }
  search(e, { maintainInsertionOrder: r, fullOnly: n } = {}) {
    let a = this._trie;
    const _ = [];
    let o = !0;
    for (const i of e.split(cr)) {
      const s = a.children.get(i);
      if (!s) {
        o = !1;
        break;
      }
      (n || _.push(...s.hooks), (a = s));
    }
    return (
      n && o && _.push(...a.hooks),
      _.length === 0
        ? []
        : _.length === 1
          ? [_[0].hook]
          : (r && _.sort((i, s) => i.insertedId - s.insertedId),
            _.map(({ hook: i }) => i))
    );
  }
}
const xp = [
  "afterEach",
  "after",
  "beforeEach",
  "before",
  "describe",
  "it",
].every((t) => typeof global[t] == "function");
class me {
  _moduleNameTrie = new $p();
  static _instance;
  constructor() {
    this._initialize();
  }
  _initialize() {}
  register(e, r) {
    const n = { moduleName: e, onRequire: r };
    return (this._moduleNameTrie.insert(n), n);
  }
  static getInstance() {
    return xp ? new me() : (this._instance = this._instance ?? new me());
  }
}
function kp(t, e, r) {
  let n, a;
  try {
    a = t();
  } catch (_) {
    n = _;
  } finally {
    if ((e(n, a), n && !r)) throw n;
    return a;
  }
}
async function Fp(t, e, r) {
  let n, a;
  try {
    a = await t();
  } catch (_) {
    n = _;
  } finally {
    if ((e(n, a), n && !r)) throw n;
    return a;
  }
}
function pT(t) {
  return (
    typeof t == "function" &&
    typeof t.__original == "function" &&
    typeof t.__unwrap == "function" &&
    t.__wrapped === !0
  );
}
class Kp extends Hp {
  _modules;
  _hooks = [];
  _requireInTheMiddleSingleton = me.getInstance();
  _enabled = !1;
  constructor(e, r, n) {
    super(e, r, n);
    let a = this.init();
    (a && !Array.isArray(a) && (a = [a]),
      (this._modules = a || []),
      this._config.enabled && this.enable());
  }
  _wrap = (e, r, n) => {
    if ((pT(e[r]) && this._unwrap(e, r), yt.isProxy(e))) {
      const a = he(Object.assign({}, e), r, n);
      return (Object.defineProperty(e, r, { value: a }), a);
    } else return he(e, r, n);
  };
  _unwrap = (e, r) =>
    yt.isProxy(e) ? Object.defineProperty(e, r, { value: e[r] }) : mt(e, r);
  _massWrap = (e, r, n) => {
    if (e) Array.isArray(e) || (e = [e]);
    else {
      c.error("must provide one or more modules to patch");
      return;
    }
    if (!(r && Array.isArray(r))) {
      c.error("must provide one or more functions to wrap on modules");
      return;
    }
    e.forEach((a) => {
      r.forEach((_) => {
        this._wrap(a, _, n);
      });
    });
  };
  _massUnwrap = (e, r) => {
    if (e) Array.isArray(e) || (e = [e]);
    else {
      c.error("must provide one or more modules to patch");
      return;
    }
    if (!(r && Array.isArray(r))) {
      c.error("must provide one or more functions to wrap on modules");
      return;
    }
    e.forEach((n) => {
      r.forEach((a) => {
        this._unwrap(n, a);
      });
    });
  };
  _warnOnPreloadedModules() {
    this._modules.forEach((e) => {
      const { name: r } = e;
      try {
        const n = bt.resolve(r);
        bt.cache[n] &&
          this._diag.warn(
            `Module ${r} has been loaded before ${this.instrumentationName} so it might not work, please initialize it before requiring ${r}`,
          );
      } catch {}
    });
  }
  _extractPackageVersion(e) {
    try {
      const r = UT(K.join(e, "package.json"), { encoding: "utf8" }),
        n = JSON.parse(r).version;
      return typeof n == "string" ? n : void 0;
    } catch {
      c.warn("Failed extracting version", e);
    }
  }
  _onRequire(e, r, n, a) {
    if (!a)
      return typeof e.patch == "function" &&
        ((e.moduleExports = r), this._enabled)
        ? (this._diag.debug(
            "Applying instrumentation patch for nodejs core module on require hook",
            { module: e.name },
          ),
          e.patch(r))
        : r;
    const _ = this._extractPackageVersion(a);
    if (((e.moduleVersion = _), e.name === n))
      return Rr(e.supportedVersions, _, e.includePrerelease) &&
        typeof e.patch == "function" &&
        ((e.moduleExports = r), this._enabled)
        ? (this._diag.debug(
            "Applying instrumentation patch for module on require hook",
            { module: e.name, version: e.moduleVersion, baseDir: a },
          ),
          e.patch(r, e.moduleVersion))
        : r;
    const o = e.files ?? [],
      i = K.normalize(n);
    return o
      .filter((T) => T.name === i)
      .filter((T) => Rr(T.supportedVersions, _, e.includePrerelease))
      .reduce(
        (T, E) => (
          (E.moduleExports = T),
          this._enabled
            ? (this._diag.debug(
                "Applying instrumentation patch for nodejs module file on require hook",
                {
                  module: e.name,
                  version: e.moduleVersion,
                  fileName: E.name,
                  baseDir: a,
                },
              ),
              E.patch(T, e.moduleVersion))
            : T
        ),
        r,
      );
  }
  enable() {
    if (!this._enabled) {
      if (((this._enabled = !0), this._hooks.length > 0)) {
        for (const e of this._modules) {
          typeof e.patch == "function" &&
            e.moduleExports &&
            (this._diag.debug(
              "Applying instrumentation patch for nodejs module on instrumentation enabled",
              { module: e.name, version: e.moduleVersion },
            ),
            e.patch(e.moduleExports, e.moduleVersion));
          for (const r of e.files)
            r.moduleExports &&
              (this._diag.debug(
                "Applying instrumentation patch for nodejs module file on instrumentation enabled",
                { module: e.name, version: e.moduleVersion, fileName: r.name },
              ),
              r.patch(r.moduleExports, e.moduleVersion));
        }
        return;
      }
      this._warnOnPreloadedModules();
      for (const e of this._modules) {
        const r = (o, i, s) => {
            if (!s && K.isAbsolute(i)) {
              const T = K.parse(i);
              ((i = T.name), (s = T.dir));
            }
            return this._onRequire(e, o, i, s);
          },
          n = (o, i, s) => this._onRequire(e, o, i, s),
          a = K.isAbsolute(e.name)
            ? new QS([e.name], { internals: !0 }, n)
            : this._requireInTheMiddleSingleton.register(e.name, n);
        this._hooks.push(a);
        const _ = new JS([e.name], { internals: !1 }, r);
        this._hooks.push(_);
      }
    }
  }
  disable() {
    if (this._enabled) {
      this._enabled = !1;
      for (const e of this._modules) {
        typeof e.unpatch == "function" &&
          e.moduleExports &&
          (this._diag.debug(
            "Removing instrumentation patch for nodejs module on instrumentation disabled",
            { module: e.name, version: e.moduleVersion },
          ),
          e.unpatch(e.moduleExports, e.moduleVersion));
        for (const r of e.files)
          r.moduleExports &&
            (this._diag.debug(
              "Removing instrumentation patch for nodejs module file on instrumentation disabled",
              { module: e.name, version: e.moduleVersion, fileName: r.name },
            ),
            r.unpatch(r.moduleExports, e.moduleVersion));
      }
    }
  }
  isEnabled() {
    return this._enabled;
  }
}
function Rr(t, e, r) {
  return typeof e > "u"
    ? t.includes("*")
    : t.some((n) => Sp(e, n, { includePrerelease: r }));
}
class jp {
  name;
  supportedVersions;
  patch;
  unpatch;
  files;
  constructor(e, r, n, a, _) {
    ((this.name = e),
      (this.supportedVersions = r),
      (this.patch = n),
      (this.unpatch = a),
      (this.files = _ || []));
  }
}
class Wp {
  supportedVersions;
  patch;
  unpatch;
  name;
  constructor(e, r, n, a) {
    ((this.supportedVersions = r),
      (this.patch = n),
      (this.unpatch = a),
      (this.name = gT(e)));
  }
}
var x;
(function (t) {
  ((t[(t.STABLE = 1)] = "STABLE"),
    (t[(t.OLD = 2)] = "OLD"),
    (t[(t.DUPLICATE = 3)] = "DUPLICATE"));
})(x || (x = {}));
function Xp(t, e) {
  let r = x.OLD;
  const n = e
    ?.split(",")
    .map((a) => a.trim())
    .filter((a) => a !== "");
  for (const a of n ?? [])
    if (a.toLowerCase() === t + "/dup") {
      r = x.DUPLICATE;
      break;
    } else a.toLowerCase() === t && (r = x.STABLE);
  return r;
}
const qp = Object.freeze(
    Object.defineProperty(
      {
        __proto__: null,
        InstrumentationBase: Kp,
        InstrumentationNodeModuleDefinition: jp,
        InstrumentationNodeModuleFile: Wp,
        get SemconvStability() {
          return x;
        },
        isWrapped: pT,
        registerInstrumentations: sp,
        safeExecuteInTheMiddle: kp,
        safeExecuteInTheMiddleAsync: Fp,
        semconvStabilityFromStr: Xp,
      },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  ),
  lr = Ve(qp);
var te = {},
  Nr;
function zp() {
  if (Nr) return te;
  ((Nr = 1),
    Object.defineProperty(te, "__esModule", { value: !0 }),
    (te.endSpan = void 0));
  const t = Re,
    e = (r, n) => {
      (n &&
        (r.recordException(n),
        r.setStatus({ code: t.SpanStatusCode.ERROR, message: n.message })),
        r.end());
    };
  return ((te.endSpan = e), te);
}
var re = {},
  Or;
function Qp() {
  if (Or) return re;
  ((Or = 1),
    Object.defineProperty(re, "__esModule", { value: !0 }),
    (re.defaultDbStatementSerializer = void 0));
  const t = [
      { regex: /^ECHO/i, args: 0 },
      {
        regex: /^(LPUSH|MSET|PFA|PUBLISH|RPUSH|SADD|SET|SPUBLISH|XADD|ZADD)/i,
        args: 1,
      },
      { regex: /^(HSET|HMSET|LSET|LINSERT)/i, args: 2 },
      {
        regex:
          /^(ACL|BIT|B[LRZ]|CLIENT|CLUSTER|CONFIG|COMMAND|DECR|DEL|EVAL|EX|FUNCTION|GEO|GET|HINCR|HMGET|HSCAN|INCR|L[TRLM]|MEMORY|P[EFISTU]|RPOP|S[CDIMORSU]|XACK|X[CDGILPRT]|Z[CDILMPRS])/i,
        args: -1,
      },
    ],
    e = (r, n) => {
      if (Array.isArray(n) && n.length) {
        const a = t.find(({ regex: o }) => o.test(r))?.args ?? 0,
          _ = a >= 0 ? n.slice(0, a) : n;
        return (
          n.length > _.length && _.push(`[${n.length - a} other arguments]`),
          `${r} ${_.join(" ")}`
        );
      }
      return r;
    };
  return ((re.defaultDbStatementSerializer = e), re);
}
var V = {},
  vr;
function Jp() {
  return (
    vr ||
      ((vr = 1),
      Object.defineProperty(V, "__esModule", { value: !0 }),
      (V.PACKAGE_NAME = V.PACKAGE_VERSION = void 0),
      (V.PACKAGE_VERSION = "0.52.0"),
      (V.PACKAGE_NAME = "@opentelemetry/instrumentation-ioredis")),
    V
  );
}
var Mr;
function Zp() {
  if (Mr) return J;
  ((Mr = 1),
    Object.defineProperty(J, "__esModule", { value: !0 }),
    (J.IORedisInstrumentation = void 0));
  const t = Re,
    e = lr,
    r = ep,
    n = lr,
    a = zp(),
    _ = Qp(),
    o = Jp(),
    i = { requireParentSpan: !0 };
  class s extends e.InstrumentationBase {
    constructor(E = {}) {
      super(o.PACKAGE_NAME, o.PACKAGE_VERSION, { ...i, ...E });
    }
    setConfig(E = {}) {
      super.setConfig({ ...i, ...E });
    }
    init() {
      return [
        new e.InstrumentationNodeModuleDefinition(
          "ioredis",
          [">=2.0.0 <6"],
          (E, S) => {
            const A = E[Symbol.toStringTag] === "Module" ? E.default : E;
            return (
              (0, e.isWrapped)(A.prototype.sendCommand) &&
                this._unwrap(A.prototype, "sendCommand"),
              this._wrap(A.prototype, "sendCommand", this._patchSendCommand(S)),
              (0, e.isWrapped)(A.prototype.connect) &&
                this._unwrap(A.prototype, "connect"),
              this._wrap(A.prototype, "connect", this._patchConnection()),
              E
            );
          },
          (E) => {
            if (E === void 0) return;
            const S = E[Symbol.toStringTag] === "Module" ? E.default : E;
            (this._unwrap(S.prototype, "sendCommand"),
              this._unwrap(S.prototype, "connect"));
          },
        ),
      ];
    }
    _patchSendCommand(E) {
      return (S) => this._traceSendCommand(S, E);
    }
    _patchConnection() {
      return (E) => this._traceConnection(E);
    }
    _traceSendCommand(E, S) {
      const A = this;
      return function (u) {
        if (arguments.length < 1 || typeof u != "object")
          return E.apply(this, arguments);
        const M = A.getConfig(),
          I = M.dbStatementSerializer || _.defaultDbStatementSerializer,
          R = t.trace.getSpan(t.context.active()) === void 0;
        if (M.requireParentSpan === !0 && R) return E.apply(this, arguments);
        const N = A.tracer.startSpan(u.name, {
            kind: t.SpanKind.CLIENT,
            attributes: {
              [r.SEMATTRS_DB_SYSTEM]: r.DBSYSTEMVALUES_REDIS,
              [r.SEMATTRS_DB_STATEMENT]: I(u.name, u.args),
            },
          }),
          { requestHook: P } = M;
        P &&
          (0, n.safeExecuteInTheMiddle)(
            () => P(N, { moduleVersion: S, cmdName: u.name, cmdArgs: u.args }),
            (m) => {
              m &&
                t.diag.error("ioredis instrumentation: request hook failed", m);
            },
            !0,
          );
        const { host: l, port: O } = this.options;
        N.setAttributes({
          [r.SEMATTRS_NET_PEER_NAME]: l,
          [r.SEMATTRS_NET_PEER_PORT]: O,
          [r.SEMATTRS_DB_CONNECTION_STRING]: `redis://${l}:${O}`,
        });
        try {
          const m = E.apply(this, arguments),
            CT = u.resolve;
          u.resolve = function (F) {
            ((0, n.safeExecuteInTheMiddle)(
              () => M.responseHook?.(N, u.name, u.args, F),
              (Vt) => {
                Vt &&
                  t.diag.error(
                    "ioredis instrumentation: response hook failed",
                    Vt,
                  );
              },
              !0,
            ),
              (0, a.endSpan)(N, null),
              CT(F));
          };
          const LT = u.reject;
          return (
            (u.reject = function (F) {
              ((0, a.endSpan)(N, F), LT(F));
            }),
            m
          );
        } catch (m) {
          throw ((0, a.endSpan)(N, m), m);
        }
      };
    }
    _traceConnection(E) {
      const S = this;
      return function () {
        const A = t.trace.getSpan(t.context.active()) === void 0;
        if (S.getConfig().requireParentSpan === !0 && A)
          return E.apply(this, arguments);
        const u = S.tracer.startSpan("connect", {
            kind: t.SpanKind.CLIENT,
            attributes: {
              [r.SEMATTRS_DB_SYSTEM]: r.DBSYSTEMVALUES_REDIS,
              [r.SEMATTRS_DB_STATEMENT]: "connect",
            },
          }),
          { host: M, port: I } = this.options;
        u.setAttributes({
          [r.SEMATTRS_NET_PEER_NAME]: M,
          [r.SEMATTRS_NET_PEER_PORT]: I,
          [r.SEMATTRS_DB_CONNECTION_STRING]: `redis://${M}:${I}`,
        });
        try {
          const R = E.apply(this, arguments);
          return ((0, a.endSpan)(u, null), R);
        } catch (R) {
          throw ((0, a.endSpan)(u, R), R);
        }
      };
    }
  }
  return ((J.IORedisInstrumentation = s), J);
}
var fr;
function eC() {
  return (
    fr ||
      ((fr = 1),
      (function (t) {
        (Object.defineProperty(t, "__esModule", { value: !0 }),
          (t.IORedisInstrumentation = void 0));
        var e = Zp();
        Object.defineProperty(t, "IORedisInstrumentation", {
          enumerable: !0,
          get: function () {
            return e.IORedisInstrumentation;
          },
        });
      })(rt)),
    rt
  );
}
var fC = eC(),
  _t,
  Pr;
function tC() {
  if (Pr) return _t;
  Pr = 1;
  function t(s) {
    return typeof s == "function";
  }
  var e = console.error.bind(console);
  function r(s, T, E) {
    var S = !!s[T] && s.propertyIsEnumerable(T);
    Object.defineProperty(s, T, {
      configurable: !0,
      enumerable: S,
      writable: !0,
      value: E,
    });
  }
  function n(s) {
    s &&
      s.logger &&
      (t(s.logger)
        ? (e = s.logger)
        : e("new logger isn't a function, not replacing"));
  }
  function a(s, T, E) {
    if (!s || !s[T]) {
      e("no original function " + T + " to wrap");
      return;
    }
    if (!E) {
      (e("no wrapper function"), e(new Error().stack));
      return;
    }
    if (!t(s[T]) || !t(E)) {
      e("original object and wrapper must be functions");
      return;
    }
    var S = s[T],
      A = E(S, T);
    return (
      r(A, "__original", S),
      r(A, "__unwrap", function () {
        s[T] === A && r(s, T, S);
      }),
      r(A, "__wrapped", !0),
      r(s, T, A),
      A
    );
  }
  function _(s, T, E) {
    if (s) Array.isArray(s) || (s = [s]);
    else {
      (e("must provide one or more modules to patch"), e(new Error().stack));
      return;
    }
    if (!(T && Array.isArray(T))) {
      e("must provide one or more functions to wrap on modules");
      return;
    }
    s.forEach(function (S) {
      T.forEach(function (A) {
        a(S, A, E);
      });
    });
  }
  function o(s, T) {
    if (!s || !s[T]) {
      (e("no function to unwrap."), e(new Error().stack));
      return;
    }
    if (!s[T].__unwrap)
      e("no original to unwrap to -- has " + T + " already been unwrapped?");
    else return s[T].__unwrap();
  }
  function i(s, T) {
    if (s) Array.isArray(s) || (s = [s]);
    else {
      (e("must provide one or more modules to patch"), e(new Error().stack));
      return;
    }
    if (!(T && Array.isArray(T))) {
      e("must provide one or more functions to unwrap on modules");
      return;
    }
    s.forEach(function (E) {
      T.forEach(function (S) {
        o(E, S);
      });
    });
  }
  return (
    (n.wrap = a),
    (n.massWrap = _),
    (n.unwrap = o),
    (n.massUnwrap = i),
    (_t = n),
    _t
  );
}
var PC = tC();
export {
  MC as A,
  RC as B,
  Qp as C,
  v as D,
  Mc as E,
  kp as F,
  qA as G,
  QS as H,
  Nt as I,
  PC as J,
  vC as K,
  fC as L,
  Gr as M,
  C as N,
  Ir as R,
  k as S,
  h as T,
  EA as W,
  JS as a,
  Kp as b,
  jp as c,
  Wp as d,
  ct as e,
  pe as f,
  Ce as g,
  He as h,
  Lr as i,
  B as j,
  cC as k,
  ce as l,
  fc as m,
  c as n,
  QA as o,
  ue as p,
  Be as q,
  pT as r,
  Ge as s,
  _e as t,
  sp as u,
  Re as v,
  wc as w,
  lr as x,
  ep as y,
  uC as z,
};
//# sourceMappingURL=index-ChOWHMSa.mjs.map
