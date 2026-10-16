import { a4 as ys } from "./sentry-common-BxRELKId.js";
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
    var e = new s.Error().stack;
    e &&
      ((s._sentryDebugIds = s._sentryDebugIds || {}),
      (s._sentryDebugIds[e] = "7118ae79-19e0-448d-9a86-16fcd773930e"),
      (s._sentryDebugIdIdentifier =
        "sentry-dbid-7118ae79-19e0-448d-9a86-16fcd773930e"));
  } catch {}
})();
var at = { exports: {} },
  Di = at.exports,
  jn;
function Ci() {
  return (
    jn ||
      ((jn = 1),
      (function (s, e) {
        (function (t, n) {
          s.exports = n();
        })(Di, function () {
          var t = "month",
            n = "quarter";
          return function (r, i) {
            var a = i.prototype;
            a.quarter = function (d) {
              return this.$utils().u(d)
                ? Math.ceil((this.month() + 1) / 3)
                : this.month((this.month() % 3) + 3 * (d - 1));
            };
            var o = a.add;
            a.add = function (d, l) {
              return (
                (d = Number(d)),
                this.$utils().p(l) === n
                  ? this.add(3 * d, t)
                  : o.bind(this)(d, l)
              );
            };
            var u = a.startOf;
            a.startOf = function (d, l) {
              var h = this.$utils(),
                z = !!h.u(l) || l;
              if (h.p(d) === n) {
                var k = this.quarter() - 1;
                return z
                  ? this.month(3 * k)
                      .startOf(t)
                      .startOf("day")
                  : this.month(3 * k + 2)
                      .endOf(t)
                      .endOf("day");
              }
              return u.bind(this)(d, l);
            };
          };
        });
      })(at)),
    at.exports
  );
}
var Ui = Ci();
const Ii = ys(Ui);
var ot = { exports: {} },
  bi = ot.exports,
  Yn;
function Si() {
  return (
    Yn ||
      ((Yn = 1),
      (function (s, e) {
        (function (t, n) {
          s.exports = n();
        })(bi, function () {
          var t = 1e3,
            n = 6e4,
            r = 36e5,
            i = "millisecond",
            a = "second",
            o = "minute",
            u = "hour",
            d = "day",
            l = "week",
            h = "month",
            z = "quarter",
            k = "year",
            j = "date",
            Te = "Invalid Date",
            b =
              /^(\d{4})[-/]?(\d{1,2})?[-/]?(\d{0,2})[Tt\s]*(\d{1,2})?:?(\d{1,2})?:?(\d{1,2})?[.:]?(\d+)?$/,
            Ce =
              /\[([^\]]+)]|Y{1,4}|M{1,4}|D{1,2}|d{1,4}|H{1,2}|h{1,2}|a|A|m{1,2}|s{1,2}|Z{1,2}|SSS/g,
            S = {
              name: "en",
              weekdays:
                "Sunday_Monday_Tuesday_Wednesday_Thursday_Friday_Saturday".split(
                  "_",
                ),
              months:
                "January_February_March_April_May_June_July_August_September_October_November_December".split(
                  "_",
                ),
              ordinal: function (R) {
                var y = ["th", "st", "nd", "rd"],
                  c = R % 100;
                return "[" + R + (y[(c - 20) % 10] || y[c] || y[0]) + "]";
              },
            },
            x = function (R, y, c) {
              var T = String(R);
              return !T || T.length >= y
                ? R
                : "" + Array(y + 1 - T.length).join(c) + R;
            },
            Fn = {
              s: x,
              z: function (R) {
                var y = -R.utcOffset(),
                  c = Math.abs(y),
                  T = Math.floor(c / 60),
                  m = c % 60;
                return (y <= 0 ? "+" : "-") + x(T, 2, "0") + ":" + x(m, 2, "0");
              },
              m: function R(y, c) {
                if (y.date() < c.date()) return -R(c, y);
                var T = 12 * (c.year() - y.year()) + (c.month() - y.month()),
                  m = y.clone().add(T, h),
                  w = c - m < 0,
                  O = y.clone().add(T + (w ? -1 : 1), h);
                return +(-(T + (c - m) / (w ? m - O : O - m)) || 0);
              },
              a: function (R) {
                return R < 0 ? Math.ceil(R) || 0 : Math.floor(R);
              },
              p: function (R) {
                return (
                  { M: h, y: k, w: l, d, D: j, h: u, m: o, s: a, ms: i, Q: z }[
                    R
                  ] ||
                  String(R || "")
                    .toLowerCase()
                    .replace(/s$/, "")
                );
              },
              u: function (R) {
                return R === void 0;
              },
            },
            Ue = "en",
            ye = {};
          ye[Ue] = S;
          var Gn = "$isDayjsObject",
            Dt = function (R) {
              return R instanceof Le || !(!R || !R[Gn]);
            },
            Ge = function R(y, c, T) {
              var m;
              if (!y) return Ue;
              if (typeof y == "string") {
                var w = y.toLowerCase();
                (ye[w] && (m = w), c && ((ye[w] = c), (m = w)));
                var O = y.split("-");
                if (!m && O.length > 1) return R(O[0]);
              } else {
                var M = y.name;
                ((ye[M] = y), (m = M));
              }
              return (!T && m && (Ue = m), m || (!T && Ue));
            },
            C = function (R, y) {
              if (Dt(R)) return R.clone();
              var c = typeof y == "object" ? y : {};
              return ((c.date = R), (c.args = arguments), new Le(c));
            },
            N = Fn;
          ((N.l = Ge),
            (N.i = Dt),
            (N.w = function (R, y) {
              return C(R, {
                locale: y.$L,
                utc: y.$u,
                x: y.$x,
                $offset: y.$offset,
              });
            }));
          var Le = (function () {
              function R(c) {
                ((this.$L = Ge(c.locale, null, !0)),
                  this.parse(c),
                  (this.$x = this.$x || c.x || {}),
                  (this[Gn] = !0));
              }
              var y = R.prototype;
              return (
                (y.parse = function (c) {
                  ((this.$d = (function (T) {
                    var m = T.date,
                      w = T.utc;
                    if (m === null) return new Date(NaN);
                    if (N.u(m)) return new Date();
                    if (m instanceof Date) return new Date(m);
                    if (typeof m == "string" && !/Z$/i.test(m)) {
                      var O = m.match(b);
                      if (O) {
                        var M = O[2] - 1 || 0,
                          A = (O[7] || "0").substring(0, 3);
                        return w
                          ? new Date(
                              Date.UTC(
                                O[1],
                                M,
                                O[3] || 1,
                                O[4] || 0,
                                O[5] || 0,
                                O[6] || 0,
                                A,
                              ),
                            )
                          : new Date(
                              O[1],
                              M,
                              O[3] || 1,
                              O[4] || 0,
                              O[5] || 0,
                              O[6] || 0,
                              A,
                            );
                      }
                    }
                    return new Date(m);
                  })(c)),
                    this.init());
                }),
                (y.init = function () {
                  var c = this.$d;
                  ((this.$y = c.getFullYear()),
                    (this.$M = c.getMonth()),
                    (this.$D = c.getDate()),
                    (this.$W = c.getDay()),
                    (this.$H = c.getHours()),
                    (this.$m = c.getMinutes()),
                    (this.$s = c.getSeconds()),
                    (this.$ms = c.getMilliseconds()));
                }),
                (y.$utils = function () {
                  return N;
                }),
                (y.isValid = function () {
                  return this.$d.toString() !== Te;
                }),
                (y.isSame = function (c, T) {
                  var m = C(c);
                  return this.startOf(T) <= m && m <= this.endOf(T);
                }),
                (y.isAfter = function (c, T) {
                  return C(c) < this.startOf(T);
                }),
                (y.isBefore = function (c, T) {
                  return this.endOf(T) < C(c);
                }),
                (y.$g = function (c, T, m) {
                  return N.u(c) ? this[T] : this.set(m, c);
                }),
                (y.unix = function () {
                  return Math.floor(this.valueOf() / 1e3);
                }),
                (y.valueOf = function () {
                  return this.$d.getTime();
                }),
                (y.startOf = function (c, T) {
                  var m = this,
                    w = !!N.u(T) || T,
                    O = N.p(c),
                    M = function (he, Y) {
                      var se = N.w(
                        m.$u ? Date.UTC(m.$y, Y, he) : new Date(m.$y, Y, he),
                        m,
                      );
                      return w ? se : se.endOf(d);
                    },
                    A = function (he, Y) {
                      return N.w(
                        m
                          .toDate()
                          [he].apply(
                            m.toDate("s"),
                            (w ? [0, 0, 0, 0] : [23, 59, 59, 999]).slice(Y),
                          ),
                        m,
                      );
                    },
                    U = this.$W,
                    v = this.$M,
                    B = this.$D,
                    Pe = "set" + (this.$u ? "UTC" : "");
                  switch (O) {
                    case k:
                      return w ? M(1, 0) : M(31, 11);
                    case h:
                      return w ? M(1, v) : M(0, v + 1);
                    case l:
                      var pe = this.$locale().weekStart || 0,
                        Ie = (U < pe ? U + 7 : U) - pe;
                      return M(w ? B - Ie : B + (6 - Ie), v);
                    case d:
                    case j:
                      return A(Pe + "Hours", 0);
                    case u:
                      return A(Pe + "Minutes", 1);
                    case o:
                      return A(Pe + "Seconds", 2);
                    case a:
                      return A(Pe + "Milliseconds", 3);
                    default:
                      return this.clone();
                  }
                }),
                (y.endOf = function (c) {
                  return this.startOf(c, !1);
                }),
                (y.$set = function (c, T) {
                  var m,
                    w = N.p(c),
                    O = "set" + (this.$u ? "UTC" : ""),
                    M = ((m = {}),
                    (m[d] = O + "Date"),
                    (m[j] = O + "Date"),
                    (m[h] = O + "Month"),
                    (m[k] = O + "FullYear"),
                    (m[u] = O + "Hours"),
                    (m[o] = O + "Minutes"),
                    (m[a] = O + "Seconds"),
                    (m[i] = O + "Milliseconds"),
                    m)[w],
                    A = w === d ? this.$D + (T - this.$W) : T;
                  if (w === h || w === k) {
                    var U = this.clone().set(j, 1);
                    (U.$d[M](A),
                      U.init(),
                      (this.$d = U.set(
                        j,
                        Math.min(this.$D, U.daysInMonth()),
                      ).$d));
                  } else M && this.$d[M](A);
                  return (this.init(), this);
                }),
                (y.set = function (c, T) {
                  return this.clone().$set(c, T);
                }),
                (y.get = function (c) {
                  return this[N.p(c)]();
                }),
                (y.add = function (c, T) {
                  var m,
                    w = this;
                  c = Number(c);
                  var O = N.p(T),
                    M = function (v) {
                      var B = C(w);
                      return N.w(B.date(B.date() + Math.round(v * c)), w);
                    };
                  if (O === h) return this.set(h, this.$M + c);
                  if (O === k) return this.set(k, this.$y + c);
                  if (O === d) return M(1);
                  if (O === l) return M(7);
                  var A =
                      ((m = {}), (m[o] = n), (m[u] = r), (m[a] = t), m)[O] || 1,
                    U = this.$d.getTime() + c * A;
                  return N.w(U, this);
                }),
                (y.subtract = function (c, T) {
                  return this.add(-1 * c, T);
                }),
                (y.format = function (c) {
                  var T = this,
                    m = this.$locale();
                  if (!this.isValid()) return m.invalidDate || Te;
                  var w = c || "YYYY-MM-DDTHH:mm:ssZ",
                    O = N.z(this),
                    M = this.$H,
                    A = this.$m,
                    U = this.$M,
                    v = m.weekdays,
                    B = m.months,
                    Pe = m.meridiem,
                    pe = function (Y, se, be, je) {
                      return (Y && (Y[se] || Y(T, w))) || be[se].slice(0, je);
                    },
                    Ie = function (Y) {
                      return N.s(M % 12 || 12, Y, "0");
                    },
                    he =
                      Pe ||
                      function (Y, se, be) {
                        var je = Y < 12 ? "AM" : "PM";
                        return be ? je.toLowerCase() : je;
                      };
                  return w.replace(Ce, function (Y, se) {
                    return (
                      se ||
                      (function (be) {
                        switch (be) {
                          case "YY":
                            return String(T.$y).slice(-2);
                          case "YYYY":
                            return N.s(T.$y, 4, "0");
                          case "M":
                            return U + 1;
                          case "MM":
                            return N.s(U + 1, 2, "0");
                          case "MMM":
                            return pe(m.monthsShort, U, B, 3);
                          case "MMMM":
                            return pe(B, U);
                          case "D":
                            return T.$D;
                          case "DD":
                            return N.s(T.$D, 2, "0");
                          case "d":
                            return String(T.$W);
                          case "dd":
                            return pe(m.weekdaysMin, T.$W, v, 2);
                          case "ddd":
                            return pe(m.weekdaysShort, T.$W, v, 3);
                          case "dddd":
                            return v[T.$W];
                          case "H":
                            return String(M);
                          case "HH":
                            return N.s(M, 2, "0");
                          case "h":
                            return Ie(1);
                          case "hh":
                            return Ie(2);
                          case "a":
                            return he(M, A, !0);
                          case "A":
                            return he(M, A, !1);
                          case "m":
                            return String(A);
                          case "mm":
                            return N.s(A, 2, "0");
                          case "s":
                            return String(T.$s);
                          case "ss":
                            return N.s(T.$s, 2, "0");
                          case "SSS":
                            return N.s(T.$ms, 3, "0");
                          case "Z":
                            return O;
                        }
                        return null;
                      })(Y) ||
                      O.replace(":", "")
                    );
                  });
                }),
                (y.utcOffset = function () {
                  return 15 * -Math.round(this.$d.getTimezoneOffset() / 15);
                }),
                (y.diff = function (c, T, m) {
                  var w,
                    O = this,
                    M = N.p(T),
                    A = C(c),
                    U = (A.utcOffset() - this.utcOffset()) * n,
                    v = this - A,
                    B = function () {
                      return N.m(O, A);
                    };
                  switch (M) {
                    case k:
                      w = B() / 12;
                      break;
                    case h:
                      w = B();
                      break;
                    case z:
                      w = B() / 3;
                      break;
                    case l:
                      w = (v - U) / 6048e5;
                      break;
                    case d:
                      w = (v - U) / 864e5;
                      break;
                    case u:
                      w = v / r;
                      break;
                    case o:
                      w = v / n;
                      break;
                    case a:
                      w = v / t;
                      break;
                    default:
                      w = v;
                  }
                  return m ? w : N.a(w);
                }),
                (y.daysInMonth = function () {
                  return this.endOf(h).$D;
                }),
                (y.$locale = function () {
                  return ye[this.$L];
                }),
                (y.locale = function (c, T) {
                  if (!c) return this.$L;
                  var m = this.clone(),
                    w = Ge(c, T, !0);
                  return (w && (m.$L = w), m);
                }),
                (y.clone = function () {
                  return N.w(this.$d, this);
                }),
                (y.toDate = function () {
                  return new Date(this.valueOf());
                }),
                (y.toJSON = function () {
                  return this.isValid() ? this.toISOString() : null;
                }),
                (y.toISOString = function () {
                  return this.$d.toISOString();
                }),
                (y.toString = function () {
                  return this.$d.toUTCString();
                }),
                R
              );
            })(),
            Ln = Le.prototype;
          return (
            (C.prototype = Ln),
            [
              ["$ms", i],
              ["$s", a],
              ["$m", o],
              ["$H", u],
              ["$W", d],
              ["$M", h],
              ["$y", k],
              ["$D", j],
            ].forEach(function (R) {
              Ln[R[1]] = function (y) {
                return this.$g(y, R[0], R[1]);
              };
            }),
            (C.extend = function (R, y) {
              return (R.$i || (R(y, Le, C), (R.$i = !0)), C);
            }),
            (C.locale = Ge),
            (C.isDayjs = Dt),
            (C.unix = function (R) {
              return C(1e3 * R);
            }),
            (C.en = ye[Ue]),
            (C.Ls = ye),
            (C.p = {}),
            C
          );
        });
      })(ot)),
    ot.exports
  );
}
var vi = Si();
const E = ys(vi);
var f;
(function (s) {
  ((s[(s.AM = 0)] = "AM"), (s[(s.PM = 1)] = "PM"));
})(f || (f = {}));
var _;
(function (s) {
  ((s[(s.SUNDAY = 0)] = "SUNDAY"),
    (s[(s.MONDAY = 1)] = "MONDAY"),
    (s[(s.TUESDAY = 2)] = "TUESDAY"),
    (s[(s.WEDNESDAY = 3)] = "WEDNESDAY"),
    (s[(s.THURSDAY = 4)] = "THURSDAY"),
    (s[(s.FRIDAY = 5)] = "FRIDAY"),
    (s[(s.SATURDAY = 6)] = "SATURDAY"));
})(_ || (_ = {}));
var K;
(function (s) {
  ((s[(s.JANUARY = 1)] = "JANUARY"),
    (s[(s.FEBRUARY = 2)] = "FEBRUARY"),
    (s[(s.MARCH = 3)] = "MARCH"),
    (s[(s.APRIL = 4)] = "APRIL"),
    (s[(s.MAY = 5)] = "MAY"),
    (s[(s.JUNE = 6)] = "JUNE"),
    (s[(s.JULY = 7)] = "JULY"),
    (s[(s.AUGUST = 8)] = "AUGUST"),
    (s[(s.SEPTEMBER = 9)] = "SEPTEMBER"),
    (s[(s.OCTOBER = 10)] = "OCTOBER"),
    (s[(s.NOVEMBER = 11)] = "NOVEMBER"),
    (s[(s.DECEMBER = 12)] = "DECEMBER"));
})(K || (K = {}));
function we(s, e) {
  ((e = e.add(1, "day")), D(s, e), ae(s, e));
}
function ki(s, e) {
  ((e = e.add(1, "day")), ve(s, e), ae(s, e));
}
function D(s, e) {
  (s.assign("day", e.date()),
    s.assign("month", e.month() + 1),
    s.assign("year", e.year()));
}
function ps(s, e) {
  (s.assign("hour", e.hour()),
    s.assign("minute", e.minute()),
    s.assign("second", e.second()),
    s.assign("millisecond", e.millisecond()),
    s.get("hour") < 12
      ? s.assign("meridiem", f.AM)
      : s.assign("meridiem", f.PM));
}
function ve(s, e) {
  (s.imply("day", e.date()),
    s.imply("month", e.month() + 1),
    s.imply("year", e.year()));
}
function ae(s, e) {
  (s.imply("hour", e.hour()),
    s.imply("minute", e.minute()),
    s.imply("second", e.second()),
    s.imply("millisecond", e.millisecond()));
}
const Wi = {
  ACDT: 630,
  ACST: 570,
  ADT: -180,
  AEDT: 660,
  AEST: 600,
  AFT: 270,
  AKDT: -480,
  AKST: -540,
  ALMT: 360,
  AMST: -180,
  AMT: -240,
  ANAST: 720,
  ANAT: 720,
  AQTT: 300,
  ART: -180,
  AST: -240,
  AWDT: 540,
  AWST: 480,
  AZOST: 0,
  AZOT: -60,
  AZST: 300,
  AZT: 240,
  BNT: 480,
  BOT: -240,
  BRST: -120,
  BRT: -180,
  BST: 60,
  BTT: 360,
  CAST: 480,
  CAT: 120,
  CCT: 390,
  CDT: -300,
  CEST: 120,
  CET: {
    timezoneOffsetDuringDst: 120,
    timezoneOffsetNonDst: 60,
    dstStart: (s) => zn(s, K.MARCH, _.SUNDAY, 2),
    dstEnd: (s) => zn(s, K.OCTOBER, _.SUNDAY, 3),
  },
  CHADT: 825,
  CHAST: 765,
  CKT: -600,
  CLST: -180,
  CLT: -240,
  COT: -300,
  CST: -360,
  CT: {
    timezoneOffsetDuringDst: -300,
    timezoneOffsetNonDst: -360,
    dstStart: (s) => ie(s, K.MARCH, _.SUNDAY, 2, 2),
    dstEnd: (s) => ie(s, K.NOVEMBER, _.SUNDAY, 1, 2),
  },
  CVT: -60,
  CXT: 420,
  ChST: 600,
  DAVT: 420,
  EASST: -300,
  EAST: -360,
  EAT: 180,
  ECT: -300,
  EDT: -240,
  EEST: 180,
  EET: 120,
  EGST: 0,
  EGT: -60,
  EST: -300,
  ET: {
    timezoneOffsetDuringDst: -240,
    timezoneOffsetNonDst: -300,
    dstStart: (s) => ie(s, K.MARCH, _.SUNDAY, 2, 2),
    dstEnd: (s) => ie(s, K.NOVEMBER, _.SUNDAY, 1, 2),
  },
  FJST: 780,
  FJT: 720,
  FKST: -180,
  FKT: -240,
  FNT: -120,
  GALT: -360,
  GAMT: -540,
  GET: 240,
  GFT: -180,
  GILT: 720,
  GMT: 0,
  GST: 240,
  GYT: -240,
  HAA: -180,
  HAC: -300,
  HADT: -540,
  HAE: -240,
  HAP: -420,
  HAR: -360,
  HAST: -600,
  HAT: -90,
  HAY: -480,
  HKT: 480,
  HLV: -210,
  HNA: -240,
  HNC: -360,
  HNE: -300,
  HNP: -480,
  HNR: -420,
  HNT: -150,
  HNY: -540,
  HOVT: 420,
  ICT: 420,
  IDT: 180,
  IOT: 360,
  IRDT: 270,
  IRKST: 540,
  IRKT: 540,
  IRST: 210,
  IST: 330,
  JST: 540,
  KGT: 360,
  KRAST: 480,
  KRAT: 480,
  KST: 540,
  KUYT: 240,
  LHDT: 660,
  LHST: 630,
  LINT: 840,
  MAGST: 720,
  MAGT: 720,
  MART: -510,
  MAWT: 300,
  MDT: -360,
  MESZ: 120,
  MEZ: 60,
  MHT: 720,
  MMT: 390,
  MSD: 240,
  MSK: 180,
  MST: -420,
  MT: {
    timezoneOffsetDuringDst: -360,
    timezoneOffsetNonDst: -420,
    dstStart: (s) => ie(s, K.MARCH, _.SUNDAY, 2, 2),
    dstEnd: (s) => ie(s, K.NOVEMBER, _.SUNDAY, 1, 2),
  },
  MUT: 240,
  MVT: 300,
  MYT: 480,
  NCT: 660,
  NDT: -90,
  NFT: 690,
  NOVST: 420,
  NOVT: 360,
  NPT: 345,
  NST: -150,
  NUT: -660,
  NZDT: 780,
  NZST: 720,
  OMSST: 420,
  OMST: 420,
  PDT: -420,
  PET: -300,
  PETST: 720,
  PETT: 720,
  PGT: 600,
  PHOT: 780,
  PHT: 480,
  PKT: 300,
  PMDT: -120,
  PMST: -180,
  PONT: 660,
  PST: -480,
  PT: {
    timezoneOffsetDuringDst: -420,
    timezoneOffsetNonDst: -480,
    dstStart: (s) => ie(s, K.MARCH, _.SUNDAY, 2, 2),
    dstEnd: (s) => ie(s, K.NOVEMBER, _.SUNDAY, 1, 2),
  },
  PWT: 540,
  PYST: -180,
  PYT: -240,
  RET: 240,
  SAMT: 240,
  SAST: 120,
  SBT: 660,
  SCT: 240,
  SGT: 480,
  SRT: -180,
  SST: -660,
  TAHT: -600,
  TFT: 300,
  TJT: 300,
  TKT: 780,
  TLT: 540,
  TMT: 300,
  TVT: 720,
  ULAT: 480,
  UTC: 0,
  UYST: -120,
  UYT: -180,
  UZT: 300,
  VET: -210,
  VLAST: 660,
  VLAT: 660,
  VUT: 660,
  WAST: 120,
  WAT: 60,
  WEST: 60,
  WESZ: 60,
  WET: 0,
  WEZ: 0,
  WFT: 720,
  WGST: -120,
  WGT: -180,
  WIB: 420,
  WIT: 540,
  WITA: 480,
  WST: 780,
  WT: 0,
  YAKST: 600,
  YAKT: 600,
  YAPT: 600,
  YEKST: 360,
  YEKT: 360,
};
function ie(s, e, t, n, r = 0) {
  let i = 0,
    a = 0;
  for (; a < n;) (i++, new Date(s, e - 1, i).getDay() === t && a++);
  return new Date(s, e - 1, i, r);
}
function zn(s, e, t, n = 0) {
  const r = t === 0 ? 7 : t,
    i = new Date(s, e - 1 + 1, 1, 12),
    a = i.getDay() === 0 ? 7 : i.getDay();
  let o;
  return (
    a === r ? (o = 7) : a < r ? (o = 7 + a - r) : (o = a - r),
    i.setDate(i.getDate() - o),
    new Date(s, e - 1, i.getDate(), n)
  );
}
function hs(s, e, t = {}) {
  if (s == null) return null;
  if (typeof s == "number") return s;
  const n = t[s] ?? Wi[s];
  return n == null
    ? null
    : typeof n == "number"
      ? n
      : e == null
        ? null
        : E(e).isAfter(n.dstStart(e.getFullYear())) &&
            !E(e).isAfter(n.dstEnd(e.getFullYear()))
          ? n.timezoneOffsetDuringDst
          : n.timezoneOffsetNonDst;
}
E.extend(Ii);
class G {
  constructor(e) {
    ((e = e ?? new Date()),
      e instanceof Date
        ? (this.instant = e)
        : ((this.instant = e.instant ?? new Date()),
          (this.timezoneOffset = hs(e.timezone, this.instant))));
  }
  getDateWithAdjustedTimezone() {
    return new Date(
      this.instant.getTime() +
        this.getSystemTimezoneAdjustmentMinute(this.instant) * 6e4,
    );
  }
  getSystemTimezoneAdjustmentMinute(e, t) {
    (!e || e.getTime() < 0) && (e = new Date());
    const n = -e.getTimezoneOffset(),
      r = t ?? this.timezoneOffset ?? n;
    return n - r;
  }
}
class p {
  constructor(e, t) {
    if (
      ((this._tags = new Set()),
      (this.reference = e),
      (this.knownValues = {}),
      (this.impliedValues = {}),
      t)
    )
      for (const r in t) this.knownValues[r] = t[r];
    const n = E(e.instant);
    (this.imply("day", n.date()),
      this.imply("month", n.month() + 1),
      this.imply("year", n.year()),
      this.imply("hour", 12),
      this.imply("minute", 0),
      this.imply("second", 0),
      this.imply("millisecond", 0));
  }
  get(e) {
    return e in this.knownValues
      ? this.knownValues[e]
      : e in this.impliedValues
        ? this.impliedValues[e]
        : null;
  }
  isCertain(e) {
    return e in this.knownValues;
  }
  getCertainComponents() {
    return Object.keys(this.knownValues);
  }
  imply(e, t) {
    return e in this.knownValues ? this : ((this.impliedValues[e] = t), this);
  }
  assign(e, t) {
    return ((this.knownValues[e] = t), delete this.impliedValues[e], this);
  }
  delete(e) {
    (delete this.knownValues[e], delete this.impliedValues[e]);
  }
  clone() {
    const e = new p(this.reference);
    ((e.knownValues = {}), (e.impliedValues = {}));
    for (const t in this.knownValues) e.knownValues[t] = this.knownValues[t];
    for (const t in this.impliedValues)
      e.impliedValues[t] = this.impliedValues[t];
    return e;
  }
  isOnlyDate() {
    return (
      !this.isCertain("hour") &&
      !this.isCertain("minute") &&
      !this.isCertain("second")
    );
  }
  isOnlyTime() {
    return (
      !this.isCertain("weekday") &&
      !this.isCertain("day") &&
      !this.isCertain("month")
    );
  }
  isOnlyWeekdayComponent() {
    return (
      this.isCertain("weekday") &&
      !this.isCertain("day") &&
      !this.isCertain("month")
    );
  }
  isDateWithUnknownYear() {
    return this.isCertain("month") && !this.isCertain("year");
  }
  isValidDate() {
    const e = this.dateWithoutTimezoneAdjustment();
    return !(
      e.getFullYear() !== this.get("year") ||
      e.getMonth() !== this.get("month") - 1 ||
      e.getDate() !== this.get("day") ||
      (this.get("hour") != null && e.getHours() != this.get("hour")) ||
      (this.get("minute") != null && e.getMinutes() != this.get("minute"))
    );
  }
  toString() {
    return `[ParsingComponents {
            tags: ${JSON.stringify(Array.from(this._tags).sort())}, 
            knownValues: ${JSON.stringify(this.knownValues)}, 
            impliedValues: ${JSON.stringify(this.impliedValues)}}, 
            reference: ${JSON.stringify(this.reference)}]`;
  }
  dayjs() {
    return E(this.date());
  }
  date() {
    const e = this.dateWithoutTimezoneAdjustment(),
      t = this.reference.getSystemTimezoneAdjustmentMinute(
        e,
        this.get("timezoneOffset"),
      );
    return new Date(e.getTime() + t * 6e4);
  }
  addTag(e) {
    return (this._tags.add(e), this);
  }
  addTags(e) {
    for (const t of e) this._tags.add(t);
    return this;
  }
  tags() {
    return new Set(this._tags);
  }
  dateWithoutTimezoneAdjustment() {
    const e = new Date(
      this.get("year"),
      this.get("month") - 1,
      this.get("day"),
      this.get("hour"),
      this.get("minute"),
      this.get("second"),
      this.get("millisecond"),
    );
    return (e.setFullYear(this.get("year")), e);
  }
  static createRelativeFromReference(e, t) {
    let n = E(e.instant);
    for (const i in t) n = n.add(t[i], i);
    const r = new p(e);
    return (
      t.hour || t.minute || t.second
        ? (ps(r, n),
          D(r, n),
          e.timezoneOffset !== null &&
            r.assign("timezoneOffset", -e.instant.getTimezoneOffset()))
        : (ae(r, n),
          e.timezoneOffset !== null &&
            r.imply("timezoneOffset", -e.instant.getTimezoneOffset()),
          t.d
            ? (r.assign("day", n.date()),
              r.assign("month", n.month() + 1),
              r.assign("year", n.year()))
            : (t.week && r.imply("weekday", n.day()),
              r.imply("day", n.date()),
              t.month
                ? (r.assign("month", n.month() + 1), r.assign("year", n.year()))
                : (r.imply("month", n.month() + 1),
                  t.year
                    ? r.assign("year", n.year())
                    : r.imply("year", n.year())))),
      r
    );
  }
}
class I {
  constructor(e, t, n, r, i) {
    ((this.reference = e),
      (this.refDate = e.instant),
      (this.index = t),
      (this.text = n),
      (this.start = r || new p(e)),
      (this.end = i));
  }
  clone() {
    const e = new I(this.reference, this.index, this.text);
    return (
      (e.start = this.start ? this.start.clone() : null),
      (e.end = this.end ? this.end.clone() : null),
      e
    );
  }
  date() {
    return this.start.date();
  }
  tags() {
    const e = new Set(this.start.tags());
    if (this.end) for (const t of this.end.tags()) e.add(t);
    return e;
  }
  toString() {
    const e = Array.from(this.tags()).sort();
    return `[ParsingResult {index: ${this.index}, text: '${this.text}', tags: ${JSON.stringify(e)} ...}]`;
  }
}
function oe(s, e, t = "\\s{0,5},?\\s{0,5}") {
  const n = e.replace(/\((?!\?)/g, "(?:");
  return `${s}${n}(?:${t}${n}){0,10}`;
}
function Fi(s) {
  let e;
  return (
    s instanceof Array
      ? (e = [...s])
      : s instanceof Map
        ? (e = Array.from(s.keys()))
        : (e = Object.keys(s)),
    e
  );
}
function P(s) {
  return `(?:${Fi(s)
    .sort((t, n) => n.length - t.length)
    .join("|")
    .replace(/\./g, "\\.")})`;
}
function xe(s) {
  return (s < 100 && (s > 50 ? (s = s + 1900) : (s = s + 2e3)), s);
}
function L(s, e, t) {
  const n = E(s);
  let r = n;
  ((r = r.month(t - 1)), (r = r.date(e)), (r = r.year(n.year())));
  const i = r.add(1, "y"),
    a = r.add(-1, "y");
  return (
    Math.abs(i.diff(n)) < Math.abs(r.diff(n))
      ? (r = i)
      : Math.abs(a.diff(n)) < Math.abs(r.diff(n)) && (r = a),
    r.year()
  );
}
const Ts = {
    sunday: 0,
    sun: 0,
    "sun.": 0,
    monday: 1,
    mon: 1,
    "mon.": 1,
    tuesday: 2,
    tue: 2,
    "tue.": 2,
    wednesday: 3,
    wed: 3,
    "wed.": 3,
    thursday: 4,
    thurs: 4,
    "thurs.": 4,
    thur: 4,
    "thur.": 4,
    thu: 4,
    "thu.": 4,
    friday: 5,
    fri: 5,
    "fri.": 5,
    saturday: 6,
    sat: 6,
    "sat.": 6,
  },
  Ps = {
    january: 1,
    february: 2,
    march: 3,
    april: 4,
    may: 5,
    june: 6,
    july: 7,
    august: 8,
    september: 9,
    october: 10,
    november: 11,
    december: 12,
  },
  ue = {
    ...Ps,
    jan: 1,
    "jan.": 1,
    feb: 2,
    "feb.": 2,
    mar: 3,
    "mar.": 3,
    apr: 4,
    "apr.": 4,
    jun: 6,
    "jun.": 6,
    jul: 7,
    "jul.": 7,
    aug: 8,
    "aug.": 8,
    sep: 9,
    "sep.": 9,
    sept: 9,
    "sept.": 9,
    oct: 10,
    "oct.": 10,
    nov: 11,
    "nov.": 11,
    dec: 12,
    "dec.": 12,
  },
  zt = {
    one: 1,
    two: 2,
    three: 3,
    four: 4,
    five: 5,
    six: 6,
    seven: 7,
    eight: 8,
    nine: 9,
    ten: 10,
    eleven: 11,
    twelve: 12,
  },
  Ht = {
    first: 1,
    second: 2,
    third: 3,
    fourth: 4,
    fifth: 5,
    sixth: 6,
    seventh: 7,
    eighth: 8,
    ninth: 9,
    tenth: 10,
    eleventh: 11,
    twelfth: 12,
    thirteenth: 13,
    fourteenth: 14,
    fifteenth: 15,
    sixteenth: 16,
    seventeenth: 17,
    eighteenth: 18,
    nineteenth: 19,
    twentieth: 20,
    "twenty first": 21,
    "twenty-first": 21,
    "twenty second": 22,
    "twenty-second": 22,
    "twenty third": 23,
    "twenty-third": 23,
    "twenty fourth": 24,
    "twenty-fourth": 24,
    "twenty fifth": 25,
    "twenty-fifth": 25,
    "twenty sixth": 26,
    "twenty-sixth": 26,
    "twenty seventh": 27,
    "twenty-seventh": 27,
    "twenty eighth": 28,
    "twenty-eighth": 28,
    "twenty ninth": 29,
    "twenty-ninth": 29,
    thirtieth: 30,
    "thirty first": 31,
    "thirty-first": 31,
  },
  Rs = {
    second: "second",
    seconds: "second",
    minute: "minute",
    minutes: "minute",
    hour: "hour",
    hours: "hour",
    day: "d",
    days: "d",
    week: "week",
    weeks: "week",
    month: "month",
    months: "month",
    quarter: "quarter",
    quarters: "quarter",
    year: "year",
    years: "year",
  },
  Rt = {
    s: "second",
    sec: "second",
    second: "second",
    seconds: "second",
    m: "minute",
    min: "minute",
    mins: "minute",
    minute: "minute",
    minutes: "minute",
    h: "hour",
    hr: "hour",
    hrs: "hour",
    hour: "hour",
    hours: "hour",
    d: "d",
    day: "d",
    days: "d",
    w: "w",
    week: "week",
    weeks: "week",
    mo: "month",
    mon: "month",
    mos: "month",
    month: "month",
    months: "month",
    qtr: "quarter",
    quarter: "quarter",
    quarters: "quarter",
    y: "year",
    yr: "year",
    year: "year",
    years: "year",
    ...Rs,
  },
  Es = `(?:${P(zt)}|[0-9]+|[0-9]+\\.[0-9]+|half(?:\\s{0,2}an?)?|an?\\b(?:\\s{0,2}few)?|few|several|the|a?\\s{0,2}couple\\s{0,2}(?:of)?)`;
function Gi(s) {
  const e = s.toLowerCase();
  return zt[e] !== void 0
    ? zt[e]
    : e === "a" || e === "an" || e == "the"
      ? 1
      : e.match(/few/)
        ? 3
        : e.match(/half/)
          ? 0.5
          : e.match(/couple/)
            ? 2
            : e.match(/several/)
              ? 7
              : parseFloat(e);
}
const dt = `(?:${P(Ht)}|[0-9]{1,2}(?:st|nd|rd|th)?)`;
function lt(s) {
  let e = s.toLowerCase();
  return Ht[e] !== void 0
    ? Ht[e]
    : ((e = e.replace(/(?:st|nd|rd|th)$/i, "")), parseInt(e));
}
const nn =
  "(?:[1-9][0-9]{0,3}\\s{0,2}(?:BE|AD|BC|BCE|CE)|[1-2][0-9]{3}|[5-9][0-9]|2[0-5])";
function rn(s) {
  if (/BE/i.test(s)) return ((s = s.replace(/BE/i, "")), parseInt(s) - 543);
  if (/BCE?/i.test(s)) return ((s = s.replace(/BCE?/i, "")), -parseInt(s));
  if (/(AD|CE)/i.test(s)) return ((s = s.replace(/(AD|CE)/i, "")), parseInt(s));
  const e = parseInt(s);
  return xe(e);
}
const $s = `(${Es})\\s{0,3}(${P(Rt)})`,
  Hn = new RegExp($s, "i"),
  Li = `(${Es})\\s{0,3}(${P(Rs)})`,
  ws = "\\s{0,5},?(?:\\s*and)?\\s{0,5}",
  We = oe("(?:(?:about|around)\\s{0,3})?", $s, ws),
  Et = oe("(?:(?:about|around)\\s{0,3})?", Li, ws);
function _e(s) {
  const e = {};
  let t = s,
    n = Hn.exec(t);
  for (; n;)
    (ji(e, n), (t = t.substring(n[0].length).trim()), (n = Hn.exec(t)));
  return e;
}
function ji(s, e) {
  const t = Gi(e[1]),
    n = Rt[e[2].toLowerCase()];
  s[n] = t;
}
class g {
  constructor() {
    ((this.cachedInnerPattern = null), (this.cachedPattern = null));
  }
  innerPatternHasChange(e, t) {
    return this.innerPattern(e) !== t;
  }
  patternLeftBoundary() {
    return "(\\W|^)";
  }
  pattern(e) {
    return this.cachedInnerPattern &&
      !this.innerPatternHasChange(e, this.cachedInnerPattern)
      ? this.cachedPattern
      : ((this.cachedInnerPattern = this.innerPattern(e)),
        (this.cachedPattern = new RegExp(
          `${this.patternLeftBoundary()}${this.cachedInnerPattern.source}`,
          this.cachedInnerPattern.flags,
        )),
        this.cachedPattern);
  }
  extract(e, t) {
    const n = t[1] ?? "";
    ((t.index = t.index + n.length), (t[0] = t[0].substring(n.length)));
    for (let r = 2; r < t.length; r++) t[r - 1] = t[r];
    return this.innerExtract(e, t);
  }
}
const Yi = new RegExp(
    `(?:(?:within|in|for)\\s*)?(?:(?:about|around|roughly|approximately|just)\\s*(?:~\\s*)?)?(${We})(?=\\W|$)`,
    "i",
  ),
  zi = new RegExp(
    `(?:within|in|for)\\s*(?:(?:about|around|roughly|approximately|just)\\s*(?:~\\s*)?)?(${We})(?=\\W|$)`,
    "i",
  ),
  Hi = new RegExp(
    `(?:within|in|for)\\s*(?:(?:about|around|roughly|approximately|just)\\s*(?:~\\s*)?)?(${Et})(?=\\W|$)`,
    "i",
  );
class Bi extends g {
  constructor(e) {
    (super(), (this.strictMode = e));
  }
  innerPattern(e) {
    return this.strictMode ? Hi : e.option.forwardDate ? Yi : zi;
  }
  innerExtract(e, t) {
    if (t[0].match(/^for\s*the\s*\w+/)) return null;
    const n = _e(t[1]);
    return p.createRelativeFromReference(e.reference, n);
  }
}
const Vi = new RegExp(
    `(?:on\\s{0,3})?(${dt})(?:\\s{0,3}(?:to|\\-|\\–|until|through|till)?\\s{0,3}(${dt}))?(?:-|/|\\s{0,3}(?:of)?\\s{0,3})(${P(ue)})(?:(?:-|/|,?\\s{0,3})(${nn}(?!\\w)))?(?=\\W|$)`,
    "i",
  ),
  Bn = 1,
  Vn = 2,
  qi = 3,
  qn = 4;
class Ki extends g {
  innerPattern() {
    return Vi;
  }
  innerExtract(e, t) {
    const n = e.createParsingResult(t.index, t[0]),
      r = ue[t[qi].toLowerCase()],
      i = lt(t[Bn]);
    if (i > 31) return ((t.index = t.index + t[Bn].length), null);
    if ((n.start.assign("month", r), n.start.assign("day", i), t[qn])) {
      const a = rn(t[qn]);
      n.start.assign("year", a);
    } else {
      const a = L(e.refDate, i, r);
      n.start.imply("year", a);
    }
    if (t[Vn]) {
      const a = lt(t[Vn]);
      ((n.end = n.start.clone()), n.end.assign("day", a));
    }
    return n;
  }
}
const Zi = new RegExp(
    `(${P(ue)})(?:-|/|\\s*,?\\s*)(${dt})(?!\\s*(?:am|pm))\\s*(?:(?:to|\\-)\\s*(${dt})\\s*)?(?:(?:-|/|\\s*,\\s*|\\s+)(${nn}))?(?=\\W|$)(?!\\:\\d)`,
    "i",
  ),
  Xi = 1,
  Kn = 2,
  Ct = 3,
  Ut = 4;
class Ji extends g {
  constructor(e) {
    (super(), (this.shouldSkipYearLikeDate = e));
  }
  innerPattern() {
    return Zi;
  }
  innerExtract(e, t) {
    const n = ue[t[Xi].toLowerCase()],
      r = lt(t[Kn]);
    if (
      r > 31 ||
      (this.shouldSkipYearLikeDate &&
        !t[Ct] &&
        !t[Ut] &&
        t[Kn].match(/^2[0-5]$/))
    )
      return null;
    const i = e
      .createParsingComponents({ day: r, month: n })
      .addTag("parser/ENMonthNameMiddleEndianParser");
    if (t[Ut]) {
      const u = rn(t[Ut]);
      i.assign("year", u);
    } else {
      const u = L(e.refDate, r, n);
      i.imply("year", u);
    }
    if (!t[Ct]) return i;
    const a = lt(t[Ct]),
      o = e.createParsingResult(t.index, t[0]);
    return ((o.start = i), (o.end = i.clone()), o.end.assign("day", a), o);
  }
}
const Qi = new RegExp(
    `((?:in)\\s*)?(${P(ue)})\\s*(?:[,-]?\\s*(${nn})?)?(?=[^\\s\\w]|\\s+[^0-9]|\\s+$|$)`,
    "i",
  ),
  ea = 1,
  ta = 2,
  Zn = 3;
class na extends g {
  innerPattern() {
    return Qi;
  }
  innerExtract(e, t) {
    const n = t[ta].toLowerCase();
    if (t[0].length <= 3 && !Ps[n]) return null;
    const r = e.createParsingResult(
      t.index + (t[ea] || "").length,
      t.index + t[0].length,
    );
    (r.start.imply("day", 1), r.start.addTag("parser/ENMonthNameParser"));
    const i = ue[n];
    if ((r.start.assign("month", i), t[Zn])) {
      const a = rn(t[Zn]);
      r.start.assign("year", a);
    } else {
      const a = L(e.refDate, 1, i);
      r.start.imply("year", a);
    }
    return r;
  }
}
const ra = new RegExp(
    `([0-9]{4})[\\.\\/\\s](?:(${P(ue)})|([0-9]{1,2}))[\\.\\/\\s]([0-9]{1,2})(?=\\W|$)`,
    "i",
  ),
  sa = 1,
  ia = 2,
  Xn = 3,
  aa = 4;
class oa extends g {
  innerPattern() {
    return ra;
  }
  innerExtract(e, t) {
    const n = t[Xn] ? parseInt(t[Xn]) : ue[t[ia].toLowerCase()];
    if (n < 1 || n > 12) return null;
    const r = parseInt(t[sa]);
    return { day: parseInt(t[aa]), month: n, year: r };
  }
}
const ua = new RegExp("([0-9]|0[1-9]|1[012])/([0-9]{4})", "i"),
  da = 1,
  la = 2;
class fa extends g {
  innerPattern() {
    return ua;
  }
  innerExtract(e, t) {
    const n = parseInt(t[la]),
      r = parseInt(t[da]);
    return e
      .createParsingComponents()
      .imply("day", 1)
      .assign("month", r)
      .assign("year", n);
  }
}
function ca(s, e, t, n) {
  return new RegExp(
    `${s}${e}(\\d{1,4})(?:(?:\\.|:|：)(\\d{1,2})(?:(?::|：)(\\d{2})(?:\\.(\\d{1,6}))?)?)?(?:\\s*(a\\.m\\.|p\\.m\\.|am?|pm?))?${t}`,
    n,
  );
}
function ma(s, e) {
  return new RegExp(
    `^(${s})(\\d{1,4})(?:(?:\\.|\\:|\\：)(\\d{1,2})(?:(?:\\.|\\:|\\：)(\\d{1,2})(?:\\.(\\d{1,6}))?)?)?(?:\\s*(a\\.m\\.|p\\.m\\.|am?|pm?))?${e}`,
    "i",
  );
}
const Jn = 2,
  Re = 3,
  Ye = 4,
  ze = 5,
  Se = 6;
class de {
  constructor(e = !1) {
    ((this.cachedPrimaryPrefix = null),
      (this.cachedPrimarySuffix = null),
      (this.cachedPrimaryTimePattern = null),
      (this.cachedFollowingPhase = null),
      (this.cachedFollowingSuffix = null),
      (this.cachedFollowingTimePatten = null),
      (this.strictMode = e));
  }
  patternFlags() {
    return "i";
  }
  primaryPatternLeftBoundary() {
    return "(^|\\s|T|\\b)";
  }
  primarySuffix() {
    return "(?!/)(?=\\W|$)";
  }
  followingSuffix() {
    return "(?!/)(?=\\W|$)";
  }
  pattern(e) {
    return this.getPrimaryTimePatternThroughCache();
  }
  extract(e, t) {
    const n = this.extractPrimaryTimeComponents(e, t);
    if (!n)
      return t[0].match(/^\d{4}/)
        ? ((t.index += 4), null)
        : ((t.index += t[0].length), null);
    const r = t.index + t[1].length,
      i = t[0].substring(t[1].length),
      a = e.createParsingResult(r, i, n);
    t.index += t[0].length;
    const o = e.text.substring(t.index),
      d = this.getFollowingTimePatternThroughCache().exec(o);
    return i.match(/^\d{3,4}/) &&
      d &&
      (d[0].match(/^\s*([+-])\s*\d{2,4}$/) ||
        d[0].match(/^\s*([+-])\s*\d{2}\W\d{2}/))
      ? null
      : !d || d[0].match(/^\s*([+-])\s*\d{3,4}$/)
        ? this.checkAndReturnWithoutFollowingPattern(a)
        : ((a.end = this.extractFollowingTimeComponents(e, d, a)),
          a.end && (a.text += d[0]),
          this.checkAndReturnWithFollowingPattern(a));
  }
  extractPrimaryTimeComponents(e, t, n = !1) {
    const r = e.createParsingComponents();
    let i = 0,
      a = null,
      o = parseInt(t[Jn]);
    if (o > 100) {
      if (this.strictMode || t[Re] != null) return null;
      ((i = o % 100), (o = Math.floor(o / 100)));
    }
    if (o > 24) return null;
    if (t[Re] != null) {
      if (t[Re].length == 1 && !t[Se]) return null;
      i = parseInt(t[Re]);
    }
    if (i >= 60) return null;
    if ((o > 12 && (a = f.PM), t[Se] != null)) {
      if (o > 12) return null;
      const u = t[Se][0].toLowerCase();
      (u == "a" && ((a = f.AM), o == 12 && (o = 0)),
        u == "p" && ((a = f.PM), o != 12 && (o += 12)));
    }
    if (
      (r.assign("hour", o),
      r.assign("minute", i),
      a !== null
        ? r.assign("meridiem", a)
        : o < 12
          ? r.imply("meridiem", f.AM)
          : r.imply("meridiem", f.PM),
      t[ze] != null)
    ) {
      const u = parseInt(t[ze].substring(0, 3));
      if (u >= 1e3) return null;
      r.assign("millisecond", u);
    }
    if (t[Ye] != null) {
      const u = parseInt(t[Ye]);
      if (u >= 60) return null;
      r.assign("second", u);
    }
    return r;
  }
  extractFollowingTimeComponents(e, t, n) {
    const r = e.createParsingComponents();
    if (t[ze] != null) {
      const u = parseInt(t[ze].substring(0, 3));
      if (u >= 1e3) return null;
      r.assign("millisecond", u);
    }
    if (t[Ye] != null) {
      const u = parseInt(t[Ye]);
      if (u >= 60) return null;
      r.assign("second", u);
    }
    let i = parseInt(t[Jn]),
      a = 0,
      o = -1;
    if (
      (t[Re] != null
        ? (a = parseInt(t[Re]))
        : i > 100 && ((a = i % 100), (i = Math.floor(i / 100))),
      a >= 60 || i > 24)
    )
      return null;
    if ((i >= 12 && (o = f.PM), t[Se] != null)) {
      if (i > 12) return null;
      const u = t[Se][0].toLowerCase();
      (u == "a" &&
        ((o = f.AM),
        i == 12 &&
          ((i = 0), r.isCertain("day") || r.imply("day", r.get("day") + 1))),
        u == "p" && ((o = f.PM), i != 12 && (i += 12)),
        n.start.isCertain("meridiem") ||
          (o == f.AM
            ? (n.start.imply("meridiem", f.AM),
              n.start.get("hour") == 12 && n.start.assign("hour", 0))
            : (n.start.imply("meridiem", f.PM),
              n.start.get("hour") != 12 &&
                n.start.assign("hour", n.start.get("hour") + 12))));
    }
    return (
      r.assign("hour", i),
      r.assign("minute", a),
      o >= 0
        ? r.assign("meridiem", o)
        : n.start.isCertain("meridiem") && n.start.get("hour") > 12
          ? n.start.get("hour") - 12 > i
            ? r.imply("meridiem", f.AM)
            : i <= 12 && (r.assign("hour", i + 12), r.assign("meridiem", f.PM))
          : i > 12
            ? r.imply("meridiem", f.PM)
            : i <= 12 && r.imply("meridiem", f.AM),
      r.date().getTime() < n.start.date().getTime() &&
        r.imply("day", r.get("day") + 1),
      r
    );
  }
  checkAndReturnWithoutFollowingPattern(e) {
    if (
      e.text.match(/^\d$/) ||
      e.text.match(/^\d\d\d+$/) ||
      e.text.match(/\d[apAP]$/)
    )
      return null;
    const t = e.text.match(/[^\d:.](\d[\d.]+)$/);
    if (t) {
      const n = t[1];
      if (
        this.strictMode ||
        (n.includes(".") && !n.match(/\d(\.\d{2})+$/)) ||
        parseInt(n) > 24
      )
        return null;
    }
    return e;
  }
  checkAndReturnWithFollowingPattern(e) {
    if (e.text.match(/^\d+-\d+$/)) return null;
    const t = e.text.match(/[^\d:.](\d[\d.]+)\s*-\s*(\d[\d.]+)$/);
    if (t) {
      if (this.strictMode) return null;
      const n = t[1],
        r = t[2];
      if (r.includes(".") && !r.match(/\d(\.\d{2})+$/)) return null;
      const i = parseInt(r),
        a = parseInt(n);
      if (i > 24 || a > 24) return null;
    }
    return e;
  }
  getPrimaryTimePatternThroughCache() {
    const e = this.primaryPrefix(),
      t = this.primarySuffix();
    return this.cachedPrimaryPrefix === e && this.cachedPrimarySuffix === t
      ? this.cachedPrimaryTimePattern
      : ((this.cachedPrimaryTimePattern = ca(
          this.primaryPatternLeftBoundary(),
          e,
          t,
          this.patternFlags(),
        )),
        (this.cachedPrimaryPrefix = e),
        (this.cachedPrimarySuffix = t),
        this.cachedPrimaryTimePattern);
  }
  getFollowingTimePatternThroughCache() {
    const e = this.followingPhase(),
      t = this.followingSuffix();
    return this.cachedFollowingPhase === e && this.cachedFollowingSuffix === t
      ? this.cachedFollowingTimePatten
      : ((this.cachedFollowingTimePatten = ma(e, t)),
        (this.cachedFollowingPhase = e),
        (this.cachedFollowingSuffix = t),
        this.cachedFollowingTimePatten);
  }
}
class ga extends de {
  constructor(e) {
    super(e);
  }
  followingPhase() {
    return "\\s*(?:\\-|\\–|\\~|\\〜|to|until|through|till|\\?)\\s*";
  }
  primaryPrefix() {
    return "(?:(?:at|from)\\s*)??";
  }
  primarySuffix() {
    return "(?:\\s*(?:o\\W*clock|at\\s*night|in\\s*the\\s*(?:morning|afternoon)))?(?!/)(?=\\W|$)";
  }
  extractPrimaryTimeComponents(e, t) {
    const n = super.extractPrimaryTimeComponents(e, t);
    if (!n) return n;
    if (t[0].endsWith("night")) {
      const r = n.get("hour");
      r >= 6 && r < 12
        ? (n.assign("hour", n.get("hour") + 12), n.assign("meridiem", f.PM))
        : r < 6 && n.assign("meridiem", f.AM);
    }
    if (t[0].endsWith("afternoon")) {
      n.assign("meridiem", f.PM);
      const r = n.get("hour");
      r >= 0 && r <= 6 && n.assign("hour", n.get("hour") + 12);
    }
    return (
      t[0].endsWith("morning") &&
        (n.assign("meridiem", f.AM),
        n.get("hour") < 12 && n.assign("hour", n.get("hour"))),
      n.addTag("parser/ENTimeExpressionParser")
    );
  }
}
function H(s) {
  const e = {};
  for (const t in s) e[t] = -s[t];
  return e;
}
function Os(s, e) {
  const t = s.clone();
  let n = s.dayjs();
  for (const r in e) n = n.add(e[r], r);
  return (
    ("day" in e || "d" in e || "week" in e || "month" in e || "year" in e) &&
      (t.imply("day", n.date()),
      t.imply("month", n.month() + 1),
      t.imply("year", n.year())),
    ("second" in e || "minute" in e || "hour" in e) &&
      (t.imply("second", n.second()),
      t.imply("minute", n.minute()),
      t.imply("hour", n.hour())),
    t
  );
}
const ya = new RegExp(`(${We})\\s{0,5}(?:ago|before|earlier)(?=\\W|$)`, "i"),
  pa = new RegExp(`(${Et})\\s{0,5}(?:ago|before|earlier)(?=\\W|$)`, "i");
class ha extends g {
  constructor(e) {
    (super(), (this.strictMode = e));
  }
  innerPattern() {
    return this.strictMode ? pa : ya;
  }
  innerExtract(e, t) {
    const n = _e(t[1]),
      r = H(n);
    return p.createRelativeFromReference(e.reference, r);
  }
}
const Ta = new RegExp(
    `(${We})\\s{0,5}(?:later|after|from now|henceforth|forward|out)(?=(?:\\W|$))`,
    "i",
  ),
  Pa = new RegExp(`(${Et})\\s{0,5}(later|after|from now)(?=\\W|$)`, "i"),
  Ra = 1;
class Ea extends g {
  constructor(e) {
    (super(), (this.strictMode = e));
  }
  innerPattern() {
    return this.strictMode ? Pa : Ta;
  }
  innerExtract(e, t) {
    const n = _e(t[Ra]);
    return p.createRelativeFromReference(e.reference, n);
  }
}
class $a {
  refine(e, t) {
    return t.filter((n) => this.isValid(e, n));
  }
}
class Fe {
  refine(e, t) {
    if (t.length < 2) return t;
    const n = [];
    let r = t[0],
      i = null;
    for (let a = 1; a < t.length; a++) {
      i = t[a];
      const o = e.text.substring(r.index + r.text.length, i.index);
      if (!this.shouldMergeResults(o, r, i, e)) (n.push(r), (r = i));
      else {
        const u = r,
          d = i,
          l = this.mergeResults(o, u, d, e);
        (e.debug(() => {
          console.log(
            `${this.constructor.name} merged ${u} and ${d} into ${l}`,
          );
        }),
          (r = l));
      }
    }
    return (r != null && n.push(r), n);
  }
}
class Z extends Fe {
  shouldMergeResults(e, t, n) {
    return !t.end && !n.end && e.match(this.patternBetween()) != null;
  }
  mergeResults(e, t, n) {
    if (
      (!t.start.isOnlyWeekdayComponent() &&
        !n.start.isOnlyWeekdayComponent() &&
        (n.start.getCertainComponents().forEach((i) => {
          t.start.isCertain(i) || t.start.imply(i, n.start.get(i));
        }),
        t.start.getCertainComponents().forEach((i) => {
          n.start.isCertain(i) || n.start.imply(i, t.start.get(i));
        })),
      t.start.date().getTime() > n.start.date().getTime())
    ) {
      let i = t.start.dayjs(),
        a = n.start.dayjs();
      n.start.isOnlyWeekdayComponent() && a.add(7, "days").isAfter(i)
        ? ((a = a.add(7, "days")),
          n.start.imply("day", a.date()),
          n.start.imply("month", a.month() + 1),
          n.start.imply("year", a.year()))
        : t.start.isOnlyWeekdayComponent() && i.add(-7, "days").isBefore(a)
          ? ((i = i.add(-7, "days")),
            t.start.imply("day", i.date()),
            t.start.imply("month", i.month() + 1),
            t.start.imply("year", i.year()))
          : n.start.isDateWithUnknownYear() && a.add(1, "years").isAfter(i)
            ? ((a = a.add(1, "years")), n.start.imply("year", a.year()))
            : t.start.isDateWithUnknownYear() && i.add(-1, "years").isBefore(a)
              ? ((i = i.add(-1, "years")), t.start.imply("year", i.year()))
              : ([n, t] = [t, n]);
    }
    const r = t.clone();
    return (
      (r.start = t.start),
      (r.end = n.start),
      (r.index = Math.min(t.index, n.index)),
      t.index < n.index
        ? (r.text = t.text + e + n.text)
        : (r.text = n.text + e + t.text),
      r
    );
  }
}
class wa extends Z {
  patternBetween() {
    return /^\s*(to|-|–|until|through|till)\s*$/i;
  }
}
function Qn(s, e) {
  const t = s.clone(),
    n = s.start,
    r = e.start;
  if (((t.start = er(n, r)), s.end != null || e.end != null)) {
    const i = s.end == null ? s.start : s.end,
      a = e.end == null ? e.start : e.end,
      o = er(i, a);
    if (s.end == null && o.date().getTime() < t.start.date().getTime()) {
      const u = o.dayjs().add(1, "day");
      o.isCertain("day") ? D(o, u) : ve(o, u);
    }
    t.end = o;
  }
  return t;
}
function er(s, e) {
  const t = s.clone();
  return (
    e.isCertain("hour")
      ? (t.assign("hour", e.get("hour")),
        t.assign("minute", e.get("minute")),
        e.isCertain("second")
          ? (t.assign("second", e.get("second")),
            e.isCertain("millisecond")
              ? t.assign("millisecond", e.get("millisecond"))
              : t.imply("millisecond", e.get("millisecond")))
          : (t.imply("second", e.get("second")),
            t.imply("millisecond", e.get("millisecond"))))
      : (t.imply("hour", e.get("hour")),
        t.imply("minute", e.get("minute")),
        t.imply("second", e.get("second")),
        t.imply("millisecond", e.get("millisecond"))),
    e.isCertain("timezoneOffset") &&
      t.assign("timezoneOffset", e.get("timezoneOffset")),
    e.isCertain("meridiem")
      ? t.assign("meridiem", e.get("meridiem"))
      : e.get("meridiem") != null &&
        t.get("meridiem") == null &&
        t.imply("meridiem", e.get("meridiem")),
    t.get("meridiem") == f.PM &&
      t.get("hour") < 12 &&
      (e.isCertain("hour")
        ? t.assign("hour", t.get("hour") + 12)
        : t.imply("hour", t.get("hour") + 12)),
    t.addTags(s.tags()),
    t.addTags(e.tags()),
    t
  );
}
class Q extends Fe {
  shouldMergeResults(e, t, n) {
    return (
      ((t.start.isOnlyDate() && n.start.isOnlyTime()) ||
        (n.start.isOnlyDate() && t.start.isOnlyTime())) &&
      e.match(this.patternBetween()) != null
    );
  }
  mergeResults(e, t, n) {
    const r = t.start.isOnlyDate() ? Qn(t, n) : Qn(n, t);
    return ((r.index = t.index), (r.text = t.text + e + n.text), r);
  }
}
class tr extends Q {
  patternBetween() {
    return new RegExp("^\\s*(T|at|after|before|on|of|,|-|\\.|:)?\\s*$");
  }
}
const Oa = new RegExp("^\\s*,?\\s*\\(?([A-Z]{2,4})\\)?(?=\\W|$)", "i");
class xa {
  constructor(e) {
    this.timezoneOverrides = e;
  }
  refine(e, t) {
    const n = e.option.timezones ?? {};
    return (
      t.forEach((r) => {
        const i = e.text.substring(r.index + r.text.length),
          a = Oa.exec(i);
        if (!a) return;
        const o = a[1].toUpperCase(),
          u = r.start.date() ?? r.refDate ?? new Date(),
          d = { ...this.timezoneOverrides, ...n },
          l = hs(o, u, d);
        if (l == null) return;
        e.debug(() => {
          console.log(`Extracting timezone: '${o}' into: ${l} for: ${r.start}`);
        });
        const h = r.start.get("timezoneOffset");
        (h !== null &&
          l != h &&
          (r.start.isCertain("timezoneOffset") || o != a[1])) ||
          (r.start.isOnlyDate() && o != a[1]) ||
          ((r.text += a[0]),
          r.start.isCertain("timezoneOffset") ||
            r.start.assign("timezoneOffset", l),
          r.end != null &&
            !r.end.isCertain("timezoneOffset") &&
            r.end.assign("timezoneOffset", l));
      }),
      t
    );
  }
}
const _a = new RegExp(
    "^\\s*(?:\\(?(?:GMT|UTC)\\s?)?([+-])(\\d{1,2})(?::?(\\d{2}))?\\)?",
    "i",
  ),
  Na = 1,
  Ma = 2,
  Aa = 3;
class $t {
  refine(e, t) {
    return (
      t.forEach(function (n) {
        if (n.start.isCertain("timezoneOffset")) return;
        const r = e.text.substring(n.index + n.text.length),
          i = _a.exec(r);
        if (!i) return;
        e.debug(() => {
          console.log(`Extracting timezone: '${i[0]}' into : ${n}`);
        });
        const a = parseInt(i[Ma]),
          o = parseInt(i[Aa] || "0");
        let u = a * 60 + o;
        u > 840 ||
          (i[Na] === "-" && (u = -u),
          n.end != null && n.end.assign("timezoneOffset", u),
          n.start.assign("timezoneOffset", u),
          (n.text += i[0]));
      }),
      t
    );
  }
}
class Bt {
  refine(e, t) {
    if (t.length < 2) return t;
    const n = [];
    let r = t[0];
    for (let i = 1; i < t.length; i++) {
      const a = t[i];
      if (a.index >= r.index + r.text.length) {
        (n.push(r), (r = a));
        continue;
      }
      let o = null,
        u = null;
      (a.text.length > r.text.length ? ((o = a), (u = r)) : ((o = r), (u = a)),
        e.debug(() => {
          console.log(`${this.constructor.name} remove ${u} by ${o}`);
        }),
        (r = o));
    }
    return (r != null && n.push(r), n);
  }
}
class Da {
  refine(e, t) {
    return (
      e.option.forwardDate &&
        t.forEach(function (n) {
          let r = E(e.refDate);
          if (
            (n.start.isOnlyTime() &&
              r.isAfter(n.start.dayjs()) &&
              ((r = r.add(1, "day")),
              ve(n.start, r),
              n.end &&
                n.end.isOnlyTime() &&
                (ve(n.end, r),
                n.start.dayjs().isAfter(n.end.dayjs()) &&
                  ((r = r.add(1, "day")), ve(n.end, r)))),
            n.start.isOnlyWeekdayComponent() &&
              r.isAfter(n.start.dayjs()) &&
              (r.day() >= n.start.get("weekday")
                ? (r = r.day(n.start.get("weekday") + 7))
                : (r = r.day(n.start.get("weekday"))),
              n.start.imply("day", r.date()),
              n.start.imply("month", r.month() + 1),
              n.start.imply("year", r.year()),
              e.debug(() => {
                console.log(`Forward weekly adjusted for ${n} (${n.start})`);
              }),
              n.end &&
                n.end.isOnlyWeekdayComponent() &&
                (r.day() > n.end.get("weekday")
                  ? (r = r.day(n.end.get("weekday") + 7))
                  : (r = r.day(n.end.get("weekday"))),
                n.end.imply("day", r.date()),
                n.end.imply("month", r.month() + 1),
                n.end.imply("year", r.year()),
                e.debug(() => {
                  console.log(`Forward weekly adjusted for ${n} (${n.end})`);
                }))),
            n.start.isDateWithUnknownYear() && r.isAfter(n.start.dayjs()))
          )
            for (let i = 0; i < 3 && r.isAfter(n.start.dayjs()); i++)
              (n.start.imply("year", n.start.get("year") + 1),
                e.debug(() => {
                  console.log(`Forward yearly adjusted for ${n} (${n.start})`);
                }),
                n.end &&
                  !n.end.isCertain("year") &&
                  (n.end.imply("year", n.end.get("year") + 1),
                  e.debug(() => {
                    console.log(`Forward yearly adjusted for ${n} (${n.end})`);
                  })));
        }),
      t
    );
  }
}
class Ca extends $a {
  constructor(e) {
    (super(), (this.strictMode = e));
  }
  isValid(e, t) {
    return t.text.replace(" ", "").match(/^\d*(\.\d*)?$/)
      ? (e.debug(() => {
          console.log(`Removing unlikely result '${t.text}'`);
        }),
        !1)
      : t.start.isValidDate()
        ? t.end && !t.end.isValidDate()
          ? (e.debug(() => {
              console.log(`Removing invalid result: ${t} (${t.end})`);
            }),
            !1)
          : this.strictMode
            ? this.isStrictModeValid(e, t)
            : !0
        : (e.debug(() => {
            console.log(`Removing invalid result: ${t} (${t.start})`);
          }),
          !1);
  }
  isStrictModeValid(e, t) {
    return t.start.isOnlyWeekdayComponent()
      ? (e.debug(() => {
          console.log(
            `(Strict) Removing weekday only component: ${t} (${t.end})`,
          );
        }),
        !1)
      : t.start.isOnlyTime() &&
          (!t.start.isCertain("hour") || !t.start.isCertain("minute"))
        ? (e.debug(() => {
            console.log(
              `(Strict) Removing uncertain time component: ${t} (${t.end})`,
            );
          }),
          !1)
        : !0;
  }
}
const Ua = new RegExp(
    "([0-9]{4})\\-([0-9]{1,2})\\-([0-9]{1,2})(?:T([0-9]{1,2}):([0-9]{1,2})(?::([0-9]{1,2})(?:\\.(\\d{1,4}))?)?(?:Z|([+-]\\d{2}):?(\\d{2})?)?)?(?=\\W|$)",
    "i",
  ),
  Ia = 1,
  ba = 2,
  Sa = 3,
  nr = 4,
  va = 5,
  rr = 6,
  sr = 7,
  ir = 8,
  ar = 9;
class sn extends g {
  innerPattern() {
    return Ua;
  }
  innerExtract(e, t) {
    const n = {};
    if (
      ((n.year = parseInt(t[Ia])),
      (n.month = parseInt(t[ba])),
      (n.day = parseInt(t[Sa])),
      t[nr] != null)
    )
      if (
        ((n.hour = parseInt(t[nr])),
        (n.minute = parseInt(t[va])),
        t[rr] != null && (n.second = parseInt(t[rr])),
        t[sr] != null && (n.millisecond = parseInt(t[sr])),
        t[ir] == null)
      )
        n.timezoneOffset = 0;
      else {
        const r = parseInt(t[ir]);
        let i = 0;
        t[ar] != null && (i = parseInt(t[ar]));
        let a = r * 60;
        (a < 0 ? (a -= i) : (a += i), (n.timezoneOffset = a));
      }
    return n;
  }
}
class ka extends Fe {
  mergeResults(e, t, n) {
    const r = n.clone();
    return (
      (r.index = t.index),
      (r.text = t.text + e + r.text),
      r.start.assign("weekday", t.start.get("weekday")),
      r.end && r.end.assign("weekday", t.start.get("weekday")),
      r
    );
  }
  shouldMergeResults(e, t, n) {
    return (
      t.start.isOnlyWeekdayComponent() &&
      !t.start.isCertain("hour") &&
      n.start.isCertain("day") &&
      e.match(/^,?\s*$/) != null
    );
  }
}
function X(s, e = !1) {
  return (
    s.parsers.unshift(new sn()),
    s.refiners.unshift(new ka()),
    s.refiners.unshift(new $t()),
    s.refiners.unshift(new Bt()),
    s.refiners.push(new xa()),
    s.refiners.push(new Bt()),
    s.refiners.push(new Da()),
    s.refiners.push(new Ca(e)),
    s
  );
}
function le(s) {
  const e = E(s.instant),
    t = new p(s, {});
  return (
    D(t, e),
    ps(t, e),
    s.timezoneOffset !== null && t.assign("timezoneOffset", e.utcOffset()),
    t.addTag("casualReference/now"),
    t
  );
}
function re(s) {
  const e = E(s.instant),
    t = new p(s, {});
  return (D(t, e), ae(t, e), t.addTag("casualReference/today"), t);
}
function fe(s) {
  return ke(s, 1).addTag("casualReference/yesterday");
}
function ke(s, e) {
  return Oe(s, -e);
}
function ce(s) {
  return Oe(s, 1).addTag("casualReference/tomorrow");
}
function Oe(s, e) {
  let t = E(s.instant);
  const n = new p(s, {});
  return ((t = t.add(e, "day")), D(n, t), ae(n, t), n);
}
function Wa(s, e = 22) {
  const t = E(s.instant),
    n = new p(s, {});
  return (
    D(n, t),
    n.imply("hour", e),
    n.imply("meridiem", f.PM),
    n.addTag("casualReference/tonight"),
    n
  );
}
function xs(s, e = 0) {
  let t = E(s.instant);
  const n = new p(s, {});
  return (
    t.hour() < 6 && (t = t.add(-1, "day")),
    D(n, t),
    n.imply("hour", e),
    n
  );
}
function an(s, e = 20) {
  const t = new p(s, {});
  return (
    t.imply("meridiem", f.PM),
    t.imply("hour", e),
    t.addTag("casualReference/evening"),
    t
  );
}
function _s(s, e = 20) {
  let t = E(s.instant);
  const n = new p(s, {});
  return (
    (t = t.add(-1, "day")),
    D(n, t),
    n.imply("hour", e),
    n.imply("meridiem", f.PM),
    n.addTag("casualReference/yesterday"),
    n.addTag("casualReference/evening"),
    n
  );
}
function ft(s) {
  const e = new p(s, {}),
    t = E(s.instant);
  return (
    t.hour() > 2 && ki(e, t),
    e.assign("hour", 0),
    e.imply("minute", 0),
    e.imply("second", 0),
    e.imply("millisecond", 0),
    e.addTag("casualReference/midnight"),
    e
  );
}
function on(s, e = 6) {
  const t = new p(s, {});
  return (
    t.imply("meridiem", f.AM),
    t.imply("hour", e),
    t.imply("minute", 0),
    t.imply("second", 0),
    t.imply("millisecond", 0),
    t.addTag("casualReference/morning"),
    t
  );
}
function Fa(s, e = 15) {
  const t = new p(s, {});
  return (
    t.imply("meridiem", f.PM),
    t.imply("hour", e),
    t.imply("minute", 0),
    t.imply("second", 0),
    t.imply("millisecond", 0),
    t.addTag("casualReference/afternoon"),
    t
  );
}
function un(s) {
  const e = new p(s, {});
  return (
    e.imply("meridiem", f.AM),
    e.imply("hour", 12),
    e.imply("minute", 0),
    e.imply("second", 0),
    e.imply("millisecond", 0),
    e.addTag("casualReference/noon"),
    e
  );
}
const Ga =
  /(now|today|tonight|tomorrow|tmr|tmrw|yesterday|last\s*night)(?=\W|$)/i;
class La extends g {
  innerPattern(e) {
    return Ga;
  }
  innerExtract(e, t) {
    let n = E(e.refDate);
    const r = t[0].toLowerCase();
    let i = e.createParsingComponents();
    switch (r) {
      case "now":
        i = le(e.reference);
        break;
      case "today":
        i = re(e.reference);
        break;
      case "yesterday":
        i = fe(e.reference);
        break;
      case "tomorrow":
      case "tmr":
      case "tmrw":
        i = ce(e.reference);
        break;
      case "tonight":
        i = Wa(e.reference);
        break;
      default:
        r.match(/last\s*night/) &&
          (n.hour() > 6 && (n = n.add(-1, "day")), D(i, n), i.imply("hour", 0));
        break;
    }
    return (i.addTag("parser/ENCasualDateParser"), i);
  }
}
const ja =
  /(?:this)?\s{0,3}(morning|afternoon|evening|night|midnight|midday|noon)(?=\W|$)/i;
class Ya extends g {
  innerPattern() {
    return ja;
  }
  innerExtract(e, t) {
    let n = null;
    switch (t[1].toLowerCase()) {
      case "afternoon":
        n = Fa(e.reference);
        break;
      case "evening":
      case "night":
        n = an(e.reference);
        break;
      case "midnight":
        n = ft(e.reference);
        break;
      case "morning":
        n = on(e.reference);
        break;
      case "noon":
      case "midday":
        n = un(e.reference);
        break;
    }
    return (n && n.addTag("parser/ENCasualTimeParser"), n);
  }
}
function me(s, e, t) {
  const n = s.getDateWithAdjustedTimezone(),
    r = za(n, e, t);
  let i = new p(s);
  return ((i = Os(i, { day: r })), i.assign("weekday", e), i);
}
function za(s, e, t) {
  const n = s.getDay();
  switch (t) {
    case "this":
      return ut(s, e);
    case "last":
      return Ns(s, e);
    case "next":
      return n == _.SUNDAY
        ? e == _.SUNDAY
          ? 7
          : e
        : n == _.SATURDAY
          ? e == _.SATURDAY
            ? 7
            : e == _.SUNDAY
              ? 8
              : 1 + e
          : e < n && e != _.SUNDAY
            ? ut(s, e)
            : ut(s, e) + 7;
  }
  return Ha(s, e);
}
function Ha(s, e) {
  const t = Ns(s, e),
    n = ut(s, e);
  return n < -t ? n : t;
}
function ut(s, e) {
  const t = s.getDay();
  let n = e - t;
  return (n < 0 && (n += 7), n);
}
function Ns(s, e) {
  const t = s.getDay();
  let n = e - t;
  return (n >= 0 && (n -= 7), n);
}
const Ba = new RegExp(
    `(?:(?:\\,|\\(|\\（)\\s*)?(?:on\\s*?)?(?:(this|last|past|next)\\s*)?(${P(Ts)})(?:\\s*(?:\\,|\\)|\\）))?(?:\\s*(this|last|past|next)\\s*week)?(?=\\W|$)`,
    "i",
  ),
  Va = 1,
  qa = 2,
  Ka = 3;
class Za extends g {
  innerPattern() {
    return Ba;
  }
  innerExtract(e, t) {
    const n = t[qa].toLowerCase(),
      r = Ts[n],
      i = t[Va],
      a = t[Ka];
    let o = i || a;
    ((o = o || ""), (o = o.toLowerCase()));
    let u = null;
    return (
      o == "last" || o == "past"
        ? (u = "last")
        : o == "next"
          ? (u = "next")
          : o == "this" && (u = "this"),
      me(e.reference, r, u)
    );
  }
}
const Xa = new RegExp(
    `(this|last|past|next|after\\s*this)\\s*(${P(Rt)})(?=\\s*)(?=\\W|$)`,
    "i",
  ),
  Ja = 1,
  Qa = 2;
class eo extends g {
  innerPattern() {
    return Xa;
  }
  innerExtract(e, t) {
    const n = t[Ja].toLowerCase(),
      r = t[Qa].toLowerCase(),
      i = Rt[r];
    if (n == "next" || n.startsWith("after")) {
      const u = {};
      return ((u[i] = 1), p.createRelativeFromReference(e.reference, u));
    }
    if (n == "last" || n == "past") {
      const u = {};
      return ((u[i] = -1), p.createRelativeFromReference(e.reference, u));
    }
    const a = e.createParsingComponents();
    let o = E(e.reference.instant);
    return (
      r.match(/week/i)
        ? ((o = o.add(-o.get("d"), "d")),
          a.imply("day", o.date()),
          a.imply("month", o.month() + 1),
          a.imply("year", o.year()))
        : r.match(/month/i)
          ? ((o = o.add(-o.date() + 1, "d")),
            a.imply("day", o.date()),
            a.assign("year", o.year()),
            a.assign("month", o.month() + 1))
          : r.match(/year/i) &&
            ((o = o.add(-o.date() + 1, "d")),
            (o = o.add(-o.month(), "month")),
            a.imply("day", o.date()),
            a.imply("month", o.month() + 1),
            a.assign("year", o.year())),
      a
    );
  }
}
const to = new RegExp(
    "([^\\d]|^)([0-3]{0,1}[0-9]{1})[\\/\\.\\-]([0-3]{0,1}[0-9]{1})(?:[\\/\\.\\-]([0-9]{4}|[0-9]{2}))?(\\W|$)",
    "i",
  ),
  He = 1,
  no = 5,
  or = 2,
  ur = 3,
  It = 4;
class ge {
  constructor(e) {
    ((this.groupNumberMonth = e ? ur : or),
      (this.groupNumberDay = e ? or : ur));
  }
  pattern() {
    return to;
  }
  extract(e, t) {
    if (t[He].length == 0 && t.index > 0 && t.index < e.text.length) {
      const u = e.text[t.index - 1];
      if (u >= "0" && u <= "9") return;
    }
    const n = t.index + t[He].length,
      r = t[0].substr(t[He].length, t[0].length - t[He].length - t[no].length);
    if (
      r.match(/^\d\.\d$/) ||
      r.match(/^\d\.\d{1,2}\.\d{1,2}\s*$/) ||
      (!t[It] && t[0].indexOf("/") < 0)
    )
      return;
    const i = e.createParsingResult(n, r);
    let a = parseInt(t[this.groupNumberMonth]),
      o = parseInt(t[this.groupNumberDay]);
    if ((a < 1 || a > 12) && a > 12)
      if (o >= 1 && o <= 12 && a <= 31) [o, a] = [a, o];
      else return null;
    if (o < 1 || o > 31) return null;
    if ((i.start.assign("day", o), i.start.assign("month", a), t[It])) {
      const u = parseInt(t[It]),
        d = xe(u);
      i.start.assign("year", d);
    } else {
      const u = L(e.refDate, o, a);
      i.start.imply("year", u);
    }
    return i;
  }
}
const ro = new RegExp(
    `(this|last|past|next|after|\\+|-)\\s*(${We})(?=\\W|$)`,
    "i",
  ),
  so = new RegExp(`(this|last|past|next|after|\\+|-)\\s*(${Et})(?=\\W|$)`, "i");
class io extends g {
  constructor(e = !0) {
    (super(), (this.allowAbbreviations = e));
  }
  innerPattern() {
    return this.allowAbbreviations ? ro : so;
  }
  innerExtract(e, t) {
    const n = t[1].toLowerCase();
    let r = _e(t[2]);
    switch (n) {
      case "last":
      case "past":
      case "-":
        r = H(r);
        break;
    }
    return p.createRelativeFromReference(e.reference, r);
  }
}
function ao(s) {
  return s.text.match(/^[+-]/i) != null;
}
function dr(s) {
  return s.text.match(/^-/i) != null;
}
class oo extends Fe {
  shouldMergeResults(e, t, n) {
    return e.match(/^\s*$/i) ? ao(n) || dr(n) : !1;
  }
  mergeResults(e, t, n, r) {
    let i = _e(n.text);
    dr(n) && (i = H(i));
    const a = p.createRelativeFromReference(new G(t.start.date()), i);
    return new I(t.reference, t.index, `${t.text}${e}${n.text}`, a);
  }
}
function lr(s) {
  return s.text.match(/\s+(before|from)$/i) != null;
}
function uo(s) {
  return s.text.match(/\s+(after|since)$/i) != null;
}
class lo extends Fe {
  patternBetween() {
    return /^\s*$/i;
  }
  shouldMergeResults(e, t, n) {
    return !e.match(this.patternBetween()) || (!lr(t) && !uo(t))
      ? !1
      : !!n.start.get("day") && !!n.start.get("month") && !!n.start.get("year");
  }
  mergeResults(e, t, n) {
    let r = _e(t.text);
    lr(t) && (r = H(r));
    const i = p.createRelativeFromReference(new G(n.start.date()), r);
    return new I(n.reference, t.index, `${t.text}${e}${n.text}`, i);
  }
}
class Ms {
  createCasualConfiguration(e = !1) {
    const t = this.createConfiguration(!1, e);
    return (
      t.parsers.push(new La()),
      t.parsers.push(new Ya()),
      t.parsers.push(new na()),
      t.parsers.push(new eo()),
      t.parsers.push(new io()),
      t
    );
  }
  createConfiguration(e = !0, t = !1) {
    const n = X(
      {
        parsers: [
          new ge(t),
          new Bi(e),
          new Ki(),
          new Ji(t),
          new Za(),
          new oa(),
          new fa(),
          new ga(e),
          new ha(e),
          new Ea(e),
        ],
        refiners: [new tr()],
      },
      e,
    );
    return (
      n.refiners.unshift(new lo()),
      n.refiners.unshift(new oo()),
      n.refiners.unshift(new Bt()),
      n.refiners.push(new tr()),
      n.refiners.push(new wa()),
      n
    );
  }
}
class $ {
  constructor(e) {
    ((this.defaultConfig = new Ms()),
      (e = e || this.defaultConfig.createCasualConfiguration()),
      (this.parsers = [...e.parsers]),
      (this.refiners = [...e.refiners]));
  }
  clone() {
    return new $({ parsers: [...this.parsers], refiners: [...this.refiners] });
  }
  parseDate(e, t, n) {
    const r = this.parse(e, t, n);
    return r.length > 0 ? r[0].start.date() : null;
  }
  parse(e, t, n) {
    const r = new fo(e, t, n);
    let i = [];
    return (
      this.parsers.forEach((a) => {
        const o = $.executeParser(r, a);
        i = i.concat(o);
      }),
      i.sort((a, o) => a.index - o.index),
      this.refiners.forEach(function (a) {
        i = a.refine(r, i);
      }),
      i
    );
  }
  static executeParser(e, t) {
    const n = [],
      r = t.pattern(e),
      i = e.text;
    let a = e.text,
      o = r.exec(a);
    for (; o;) {
      const u = o.index + i.length - a.length;
      o.index = u;
      const d = t.extract(e, o);
      if (!d) {
        ((a = i.substring(o.index + 1)), (o = r.exec(a)));
        continue;
      }
      let l = null;
      d instanceof I
        ? (l = d)
        : d instanceof p
          ? ((l = e.createParsingResult(o.index, o[0])), (l.start = d))
          : (l = e.createParsingResult(o.index, o[0], d));
      const h = l.index,
        z = l.text;
      (e.debug(() =>
        console.log(`${t.constructor.name} extracted (at index=${h}) '${z}'`),
      ),
        n.push(l),
        (a = i.substring(h + z.length)),
        (o = r.exec(a)));
    }
    return n;
  }
}
class fo {
  constructor(e, t, n) {
    ((this.text = e),
      (this.reference = new G(t)),
      (this.option = n ?? {}),
      (this.refDate = this.reference.instant));
  }
  createParsingComponents(e) {
    return e instanceof p ? e : new p(this.reference, e);
  }
  createParsingResult(e, t, n, r) {
    const i = typeof t == "string" ? t : this.text.substring(e, t),
      a = n ? this.createParsingComponents(n) : null,
      o = r ? this.createParsingComponents(r) : null;
    return new I(this.reference, e, i, a, o);
  }
  debug(e) {
    this.option.debug &&
      (this.option.debug instanceof Function
        ? this.option.debug(e)
        : this.option.debug.debug(e));
  }
}
const wt = new Ms(),
  Ot = new $(wt.createCasualConfiguration(!1)),
  As = new $(wt.createConfiguration(!0, !1)),
  co = new $(wt.createCasualConfiguration(!0));
function mo(s, e, t) {
  return Ot.parse(s, e, t);
}
function go(s, e, t) {
  return Ot.parseDate(s, e, t);
}
const Bf = Object.freeze(
  Object.defineProperty(
    {
      __proto__: null,
      Chrono: $,
      GB: co,
      get Meridiem() {
        return f;
      },
      ParsingComponents: p,
      ParsingResult: I,
      ReferenceWithTimezone: G,
      get Weekday() {
        return _;
      },
      casual: Ot,
      configuration: wt,
      parse: mo,
      parseDate: go,
      strict: As,
    },
    Symbol.toStringTag,
    { value: "Module" },
  ),
);
class yo extends de {
  primaryPrefix() {
    return "(?:(?:um|von)\\s*)?";
  }
  followingPhase() {
    return "\\s*(?:\\-|\\–|\\~|\\〜|bis)\\s*";
  }
  extractPrimaryTimeComponents(e, t) {
    return t[0].match(/^\s*\d{4}\s*$/)
      ? null
      : super.extractPrimaryTimeComponents(e, t);
  }
}
const Ds = {
    sonntag: 0,
    so: 0,
    montag: 1,
    mo: 1,
    dienstag: 2,
    di: 2,
    mittwoch: 3,
    mi: 3,
    donnerstag: 4,
    do: 4,
    freitag: 5,
    fr: 5,
    samstag: 6,
    sa: 6,
  },
  Cs = {
    januar: 1,
    jänner: 1,
    janner: 1,
    jan: 1,
    "jan.": 1,
    februar: 2,
    feber: 2,
    feb: 2,
    "feb.": 2,
    märz: 3,
    maerz: 3,
    mär: 3,
    "mär.": 3,
    mrz: 3,
    "mrz.": 3,
    april: 4,
    apr: 4,
    "apr.": 4,
    mai: 5,
    juni: 6,
    jun: 6,
    "jun.": 6,
    juli: 7,
    jul: 7,
    "jul.": 7,
    august: 8,
    aug: 8,
    "aug.": 8,
    september: 9,
    sep: 9,
    "sep.": 9,
    sept: 9,
    "sept.": 9,
    oktober: 10,
    okt: 10,
    "okt.": 10,
    november: 11,
    nov: 11,
    "nov.": 11,
    dezember: 12,
    dez: 12,
    "dez.": 12,
  },
  Vt = {
    eins: 1,
    eine: 1,
    einem: 1,
    einen: 1,
    einer: 1,
    zwei: 2,
    drei: 3,
    vier: 4,
    fünf: 5,
    fuenf: 5,
    sechs: 6,
    sieben: 7,
    acht: 8,
    neun: 9,
    zehn: 10,
    elf: 11,
    zwölf: 12,
    zwoelf: 12,
  },
  ct = {
    sek: "second",
    sekunde: "second",
    sekunden: "second",
    min: "minute",
    minute: "minute",
    minuten: "minute",
    h: "hour",
    std: "hour",
    stunde: "hour",
    stunden: "hour",
    tag: "d",
    tage: "d",
    tagen: "d",
    woche: "week",
    wochen: "week",
    monat: "month",
    monate: "month",
    monaten: "month",
    monats: "month",
    quartal: "quarter",
    quartals: "quarter",
    quartale: "quarter",
    quartalen: "quarter",
    a: "year",
    j: "year",
    jr: "year",
    jahr: "year",
    jahre: "year",
    jahren: "year",
    jahres: "year",
  },
  Us = `(?:${P(Vt)}|[0-9]+|[0-9]+\\.[0-9]+|halb?|halbe?|einigen?|wenigen?|mehreren?)`;
function Is(s) {
  const e = s.toLowerCase();
  return Vt[e] !== void 0
    ? Vt[e]
    : e === "ein" ||
        e === "einer" ||
        e === "einem" ||
        e === "einen" ||
        e === "eine"
      ? 1
      : e.match(/wenigen/)
        ? 2
        : e.match(/halb/) || e.match(/halben/)
          ? 0.5
          : e.match(/einigen/)
            ? 3
            : e.match(/mehreren/)
              ? 7
              : parseFloat(e);
}
const po =
  "(?:[0-9]{1,4}(?:\\s*[vn]\\.?\\s*(?:C(?:hr)?|(?:u\\.?|d\\.?(?:\\s*g\\.?)?)?\\s*Z)\\.?|\\s*(?:u\\.?|d\\.?(?:\\s*g\\.)?)\\s*Z\\.?)?)";
function ho(s) {
  if (/v/i.test(s)) return -parseInt(s.replace(/[^0-9]+/gi, ""));
  if (/n/i.test(s)) return parseInt(s.replace(/[^0-9]+/gi, ""));
  if (/z/i.test(s)) return parseInt(s.replace(/[^0-9]+/gi, ""));
  const e = parseInt(s);
  return xe(e);
}
const bs = `(${Us})\\s{0,5}(${P(ct)})\\s{0,5}`,
  fr = new RegExp(bs, "i"),
  To = oe("", bs);
function Po(s) {
  const e = {};
  let t = s,
    n = fr.exec(t);
  for (; n;) (Ro(e, n), (t = t.substring(n[0].length)), (n = fr.exec(t)));
  return e;
}
function Ro(s, e) {
  const t = Is(e[1]),
    n = ct[e[2].toLowerCase()];
  s[n] = t;
}
const Eo = new RegExp(
    `(?:(?:\\,|\\(|\\（)\\s*)?(?:a[mn]\\s*?)?(?:(diese[mn]|letzte[mn]|n(?:ä|ae)chste[mn])\\s*)?(${P(Ds)})(?:\\s*(?:\\,|\\)|\\）))?(?:\\s*(diese|letzte|n(?:ä|ae)chste)\\s*woche)?(?=\\W|$)`,
    "i",
  ),
  $o = 1,
  wo = 3,
  Oo = 2;
class xo extends g {
  innerPattern() {
    return Eo;
  }
  innerExtract(e, t) {
    const n = t[Oo].toLowerCase(),
      r = Ds[n],
      i = t[$o],
      a = t[wo];
    let o = i || a;
    ((o = o || ""), (o = o.toLowerCase()));
    let u = null;
    return (
      o.match(/letzte/)
        ? (u = "last")
        : o.match(/chste/)
          ? (u = "next")
          : o.match(/diese/) && (u = "this"),
      me(e.reference, r, u)
    );
  }
}
const _o = new RegExp(
    "(^|\\s|T)(?:(?:um|von)\\s*)?(\\d{1,2})(?:h|:)?(?:(\\d{1,2})(?:m|:)?)?(?:(\\d{1,2})(?:s)?)?(?:\\s*Uhr)?(?:\\s*(morgens|vormittags|nachmittags|abends|nachts|am\\s+(?:Morgen|Vormittag|Nachmittag|Abend)|in\\s+der\\s+Nacht))?(?=\\W|$)",
    "i",
  ),
  No = new RegExp(
    "^\\s*(\\-|\\–|\\~|\\〜|bis(?:\\s+um)?|\\?)\\s*(\\d{1,2})(?:h|:)?(?:(\\d{1,2})(?:m|:)?)?(?:(\\d{1,2})(?:s)?)?(?:\\s*Uhr)?(?:\\s*(morgens|vormittags|nachmittags|abends|nachts|am\\s+(?:Morgen|Vormittag|Nachmittag|Abend)|in\\s+der\\s+Nacht))?(?=\\W|$)",
    "i",
  ),
  Mo = 2,
  cr = 3,
  mr = 4,
  gr = 5;
class mt {
  pattern(e) {
    return _o;
  }
  extract(e, t) {
    const n = e.createParsingResult(
      t.index + t[1].length,
      t[0].substring(t[1].length),
    );
    if (
      n.text.match(/^\d{4}$/) ||
      ((n.start = mt.extractTimeComponent(n.start.clone(), t)), !n.start)
    )
      return ((t.index += t[0].length), null);
    const r = e.text.substring(t.index + t[0].length),
      i = No.exec(r);
    return (
      i &&
        ((n.end = mt.extractTimeComponent(n.start.clone(), i)),
        n.end && (n.text += i[0])),
      n
    );
  }
  static extractTimeComponent(e, t) {
    let n = 0,
      r = 0,
      i = null;
    if (
      ((n = parseInt(t[Mo])),
      t[cr] != null && (r = parseInt(t[cr])),
      r >= 60 || n > 24)
    )
      return null;
    if ((n >= 12 && (i = f.PM), t[gr] != null)) {
      if (n > 12) return null;
      const a = t[gr].toLowerCase();
      (a.match(/morgen|vormittag/) && ((i = f.AM), n == 12 && (n = 0)),
        a.match(/nachmittag|abend/) && ((i = f.PM), n != 12 && (n += 12)),
        a.match(/nacht/) &&
          (n == 12
            ? ((i = f.AM), (n = 0))
            : n < 6
              ? (i = f.AM)
              : ((i = f.PM), (n += 12))));
    }
    if (
      (e.assign("hour", n),
      e.assign("minute", r),
      i !== null
        ? e.assign("meridiem", i)
        : n < 12
          ? e.imply("meridiem", f.AM)
          : e.imply("meridiem", f.PM),
      t[mr] != null)
    ) {
      const a = parseInt(t[mr]);
      if (a >= 60) return null;
      e.assign("second", a);
    }
    return e;
  }
}
class Ao extends Z {
  patternBetween() {
    return /^\s*(bis(?:\s*(?:am|zum))?|-)\s*$/i;
  }
}
class Do extends Q {
  patternBetween() {
    return new RegExp("^\\s*(T|um|am|,|-)?\\s*$");
  }
}
class xt extends g {
  innerPattern(e) {
    return /(diesen)?\s*(morgen|vormittag|mittags?|nachmittag|abend|nacht|mitternacht)(?=\W|$)/i;
  }
  innerExtract(e, t) {
    const n = E(e.refDate),
      r = t[2].toLowerCase(),
      i = e.createParsingComponents();
    return (ae(i, n), xt.extractTimeComponents(i, r));
  }
  static extractTimeComponents(e, t) {
    switch (t) {
      case "morgen":
        (e.imply("hour", 6),
          e.imply("minute", 0),
          e.imply("second", 0),
          e.imply("meridiem", f.AM));
        break;
      case "vormittag":
        (e.imply("hour", 9),
          e.imply("minute", 0),
          e.imply("second", 0),
          e.imply("meridiem", f.AM));
        break;
      case "mittag":
      case "mittags":
        (e.imply("hour", 12),
          e.imply("minute", 0),
          e.imply("second", 0),
          e.imply("meridiem", f.AM));
        break;
      case "nachmittag":
        (e.imply("hour", 15),
          e.imply("minute", 0),
          e.imply("second", 0),
          e.imply("meridiem", f.PM));
        break;
      case "abend":
        (e.imply("hour", 18),
          e.imply("minute", 0),
          e.imply("second", 0),
          e.imply("meridiem", f.PM));
        break;
      case "nacht":
        (e.imply("hour", 22),
          e.imply("minute", 0),
          e.imply("second", 0),
          e.imply("meridiem", f.PM));
        break;
      case "mitternacht":
        (e.get("hour") > 1 && (e = Os(e, { day: 1 })),
          e.imply("hour", 0),
          e.imply("minute", 0),
          e.imply("second", 0),
          e.imply("meridiem", f.AM));
        break;
    }
    return e;
  }
}
const Co = new RegExp(
    "(jetzt|heute|morgen|übermorgen|uebermorgen|gestern|vorgestern|letzte\\s*nacht)(?:\\s*(morgen|vormittag|mittags?|nachmittag|abend|nacht|mitternacht))?(?=\\W|$)",
    "i",
  ),
  Uo = 1,
  Io = 2;
class bo extends g {
  innerPattern(e) {
    return Co;
  }
  innerExtract(e, t) {
    let n = E(e.refDate);
    const r = (t[Uo] || "").toLowerCase(),
      i = (t[Io] || "").toLowerCase();
    let a = e.createParsingComponents();
    switch (r) {
      case "jetzt":
        a = le(e.reference);
        break;
      case "heute":
        a = re(e.reference);
        break;
      case "morgen":
        we(a, n);
        break;
      case "übermorgen":
      case "uebermorgen":
        ((n = n.add(1, "day")), we(a, n));
        break;
      case "gestern":
        ((n = n.add(-1, "day")), D(a, n), ae(a, n));
        break;
      case "vorgestern":
        ((n = n.add(-2, "day")), D(a, n), ae(a, n));
        break;
      default:
        r.match(/letzte\s*nacht/) &&
          (n.hour() > 6 && (n = n.add(-1, "day")), D(a, n), a.imply("hour", 0));
        break;
    }
    return (i && (a = xt.extractTimeComponents(a, i)), a);
  }
}
const So = new RegExp(
    `(?:am\\s*?)?(?:den\\s*?)?([0-9]{1,2})\\.(?:\\s*(?:bis(?:\\s*(?:am|zum))?|\\-|\\–|\\s)\\s*([0-9]{1,2})\\.?)?\\s*(${P(Cs)})(?:(?:-|/|,?\\s*)(${po}(?![^\\s]\\d)))?(?=\\W|$)`,
    "i",
  ),
  yr = 1,
  pr = 2,
  vo = 3,
  hr = 4;
class ko extends g {
  innerPattern() {
    return So;
  }
  innerExtract(e, t) {
    const n = e.createParsingResult(t.index, t[0]),
      r = Cs[t[vo].toLowerCase()],
      i = parseInt(t[yr]);
    if (i > 31) return ((t.index = t.index + t[yr].length), null);
    if ((n.start.assign("month", r), n.start.assign("day", i), t[hr])) {
      const a = ho(t[hr]);
      n.start.assign("year", a);
    } else {
      const a = L(e.refDate, i, r);
      n.start.imply("year", a);
    }
    if (t[pr]) {
      const a = parseInt(t[pr]);
      ((n.end = n.start.clone()), n.end.assign("day", a));
    }
    return n;
  }
}
class Wo extends g {
  constructor() {
    super();
  }
  innerPattern() {
    return new RegExp(
      `(?:\\s*((?:nächste|kommende|folgende|letzte|vergangene|vorige|vor(?:her|an)gegangene)(?:s|n|m|r)?|vor|in)\\s*)?(${Us})?(?:\\s*(nächste|kommende|folgende|letzte|vergangene|vorige|vor(?:her|an)gegangene)(?:s|n|m|r)?)?\\s*(${P(ct)})`,
      "i",
    );
  }
  innerExtract(e, t) {
    const n = t[2] ? Is(t[2]) : 1,
      r = ct[t[4].toLowerCase()];
    let i = {};
    i[r] = n;
    let a = t[1] || t[3] || "";
    if (((a = a.toLowerCase()), !!a))
      return (
        (/vor/.test(a) || /letzte/.test(a) || /vergangen/.test(a)) &&
          (i = H(i)),
        p.createRelativeFromReference(e.reference, i)
      );
  }
}
class Fo extends g {
  innerPattern() {
    return new RegExp(`(?:in|für|während)\\s*(${To})(?=\\W|$)`, "i");
  }
  innerExtract(e, t) {
    const n = Po(t[1]);
    return p.createRelativeFromReference(e.reference, n);
  }
}
const dn = new $(Ss()),
  Go = new $(ln(!0));
function Lo(s, e, t) {
  return dn.parse(s, e, t);
}
function jo(s, e, t) {
  return dn.parseDate(s, e, t);
}
function Ss(s = !0) {
  const e = ln(!1, s);
  return (
    e.parsers.unshift(new xt()),
    e.parsers.unshift(new bo()),
    e.parsers.unshift(new Wo()),
    e
  );
}
function ln(s = !0, e = !0) {
  return X(
    {
      parsers: [
        new sn(),
        new ge(e),
        new yo(),
        new mt(),
        new ko(),
        new xo(),
        new Fo(),
      ],
      refiners: [new Ao(), new Do()],
    },
    s,
  );
}
const Vf = Object.freeze(
  Object.defineProperty(
    {
      __proto__: null,
      Chrono: $,
      get Meridiem() {
        return f;
      },
      ParsingComponents: p,
      ParsingResult: I,
      ReferenceWithTimezone: G,
      get Weekday() {
        return _;
      },
      casual: dn,
      createCasualConfiguration: Ss,
      createConfiguration: ln,
      parse: Lo,
      parseDate: jo,
      strict: Go,
    },
    Symbol.toStringTag,
    { value: "Module" },
  ),
);
class Yo extends g {
  innerPattern(e) {
    return /(maintenant|aujourd'hui|demain|hier|cette\s*nuit|la\s*veille)(?=\W|$)/i;
  }
  innerExtract(e, t) {
    let n = E(e.refDate);
    const r = t[0].toLowerCase(),
      i = e.createParsingComponents();
    switch (r) {
      case "maintenant":
        return le(e.reference);
      case "aujourd'hui":
        return re(e.reference);
      case "hier":
        return fe(e.reference);
      case "demain":
        return ce(e.reference);
      default:
        r.match(/cette\s*nuit/)
          ? (D(i, n), i.imply("hour", 22), i.imply("meridiem", f.PM))
          : r.match(/la\s*veille/) &&
            ((n = n.add(-1, "day")), D(i, n), i.imply("hour", 0));
    }
    return i;
  }
}
class zo extends g {
  innerPattern(e) {
    return /(cet?)?\s*(matin|soir|après-midi|aprem|a midi|à minuit)(?=\W|$)/i;
  }
  innerExtract(e, t) {
    const n = t[2].toLowerCase(),
      r = e.createParsingComponents();
    switch (n) {
      case "après-midi":
      case "aprem":
        (r.imply("hour", 14), r.imply("minute", 0), r.imply("meridiem", f.PM));
        break;
      case "soir":
        (r.imply("hour", 18), r.imply("minute", 0), r.imply("meridiem", f.PM));
        break;
      case "matin":
        (r.imply("hour", 8), r.imply("minute", 0), r.imply("meridiem", f.AM));
        break;
      case "a midi":
        (r.imply("hour", 12), r.imply("minute", 0), r.imply("meridiem", f.AM));
        break;
      case "à minuit":
        (r.imply("hour", 0), r.imply("meridiem", f.AM));
        break;
    }
    return r;
  }
}
class Ho extends de {
  primaryPrefix() {
    return "(?:(?:[àa])\\s*)?";
  }
  followingPhase() {
    return "\\s*(?:\\-|\\–|\\~|\\〜|[àa]|\\?)\\s*";
  }
  extractPrimaryTimeComponents(e, t) {
    return t[0].match(/^\s*\d{4}\s*$/)
      ? null
      : super.extractPrimaryTimeComponents(e, t);
  }
}
class Bo extends Q {
  patternBetween() {
    return new RegExp("^\\s*(T|à|a|au|vers|de|,|-)?\\s*$");
  }
}
class Vo extends Z {
  patternBetween() {
    return /^\s*(à|a|au|-)\s*$/i;
  }
}
const vs = {
    dimanche: 0,
    dim: 0,
    lundi: 1,
    lun: 1,
    mardi: 2,
    mar: 2,
    mercredi: 3,
    mer: 3,
    jeudi: 4,
    jeu: 4,
    vendredi: 5,
    ven: 5,
    samedi: 6,
    sam: 6,
  },
  ks = {
    janvier: 1,
    jan: 1,
    "jan.": 1,
    février: 2,
    fév: 2,
    "fév.": 2,
    fevrier: 2,
    fev: 2,
    "fev.": 2,
    mars: 3,
    mar: 3,
    "mar.": 3,
    avril: 4,
    avr: 4,
    "avr.": 4,
    mai: 5,
    juin: 6,
    jun: 6,
    juillet: 7,
    juil: 7,
    jul: 7,
    "jul.": 7,
    août: 8,
    aout: 8,
    septembre: 9,
    sep: 9,
    "sep.": 9,
    sept: 9,
    "sept.": 9,
    octobre: 10,
    oct: 10,
    "oct.": 10,
    novembre: 11,
    nov: 11,
    "nov.": 11,
    décembre: 12,
    decembre: 12,
    dec: 12,
    "dec.": 12,
  },
  qt = {
    un: 1,
    deux: 2,
    trois: 3,
    quatre: 4,
    cinq: 5,
    six: 6,
    sept: 7,
    huit: 8,
    neuf: 9,
    dix: 10,
    onze: 11,
    douze: 12,
    treize: 13,
  },
  gt = {
    sec: "second",
    seconde: "second",
    secondes: "second",
    min: "minute",
    mins: "minute",
    minute: "minute",
    minutes: "minute",
    h: "hour",
    hr: "hour",
    hrs: "hour",
    heure: "hour",
    heures: "hour",
    jour: "d",
    jours: "d",
    semaine: "week",
    semaines: "week",
    mois: "month",
    trimestre: "quarter",
    trimestres: "quarter",
    ans: "year",
    année: "year",
    années: "year",
  },
  Ws = `(?:${P(qt)}|[0-9]+|[0-9]+\\.[0-9]+|une?\\b|quelques?|demi-?)`;
function Fs(s) {
  const e = s.toLowerCase();
  return qt[e] !== void 0
    ? qt[e]
    : e === "une" || e === "un"
      ? 1
      : e.match(/quelques?/)
        ? 3
        : e.match(/demi-?/)
          ? 0.5
          : parseFloat(e);
}
const Tr = "(?:[0-9]{1,2}(?:er)?)";
function Pr(s) {
  let e = s.toLowerCase();
  return ((e = e.replace(/(?:er)$/i, "")), parseInt(e));
}
const qo =
  "(?:[1-9][0-9]{0,3}\\s*(?:AC|AD|p\\.\\s*C(?:hr?)?\\.\\s*n\\.)|[1-2][0-9]{3}|[5-9][0-9])";
function Ko(s) {
  if (/AC/i.test(s)) return ((s = s.replace(/BC/i, "")), -parseInt(s));
  if (/AD/i.test(s) || /C/i.test(s))
    return ((s = s.replace(/[^\d]+/i, "")), parseInt(s));
  let e = parseInt(s);
  return (e < 100 && (e > 50 ? (e = e + 1900) : (e = e + 2e3)), e);
}
const Gs = `(${Ws})\\s{0,5}(${P(gt)})\\s{0,5}`,
  Rr = new RegExp(Gs, "i"),
  Ls = oe("", Gs);
function js(s) {
  const e = {};
  let t = s,
    n = Rr.exec(t);
  for (; n;) (Zo(e, n), (t = t.substring(n[0].length)), (n = Rr.exec(t)));
  return e;
}
function Zo(s, e) {
  const t = Fs(e[1]),
    n = gt[e[2].toLowerCase()];
  s[n] = t;
}
const Xo = new RegExp(
    `(?:(?:\\,|\\(|\\（)\\s*)?(?:(?:ce)\\s*)?(${P(vs)})(?:\\s*(?:\\,|\\)|\\）))?(?:\\s*(dernier|prochain)\\s*)?(?=\\W|\\d|$)`,
    "i",
  ),
  Jo = 1,
  Qo = 2;
class eu extends g {
  innerPattern() {
    return Xo;
  }
  innerExtract(e, t) {
    const n = t[Jo].toLowerCase(),
      r = vs[n];
    if (r === void 0) return null;
    let i = t[Qo];
    ((i = i || ""), (i = i.toLowerCase()));
    let a = null;
    return (
      i == "dernier" ? (a = "last") : i == "prochain" && (a = "next"),
      me(e.reference, r, a)
    );
  }
}
const tu = new RegExp(
    "(^|\\s|T)(?:(?:[àa])\\s*)?(\\d{1,2})(?:h|:)?(?:(\\d{1,2})(?:m|:)?)?(?:(\\d{1,2})(?:s|:)?)?(?:\\s*(A\\.M\\.|P\\.M\\.|AM?|PM?))?(?=\\W|$)",
    "i",
  ),
  nu = new RegExp(
    "^\\s*(\\-|\\–|\\~|\\〜|[àa]|\\?)\\s*(\\d{1,2})(?:h|:)?(?:(\\d{1,2})(?:m|:)?)?(?:(\\d{1,2})(?:s|:)?)?(?:\\s*(A\\.M\\.|P\\.M\\.|AM?|PM?))?(?=\\W|$)",
    "i",
  ),
  ru = 2,
  Er = 3,
  $r = 4,
  wr = 5;
class yt {
  pattern(e) {
    return tu;
  }
  extract(e, t) {
    const n = e.createParsingResult(
      t.index + t[1].length,
      t[0].substring(t[1].length),
    );
    if (
      n.text.match(/^\d{4}$/) ||
      ((n.start = yt.extractTimeComponent(n.start.clone(), t)), !n.start)
    )
      return ((t.index += t[0].length), null);
    const r = e.text.substring(t.index + t[0].length),
      i = nu.exec(r);
    return (
      i &&
        ((n.end = yt.extractTimeComponent(n.start.clone(), i)),
        n.end && (n.text += i[0])),
      n
    );
  }
  static extractTimeComponent(e, t) {
    let n = 0,
      r = 0,
      i = null;
    if (
      ((n = parseInt(t[ru])),
      t[Er] != null && (r = parseInt(t[Er])),
      r >= 60 || n > 24)
    )
      return null;
    if ((n >= 12 && (i = f.PM), t[wr] != null)) {
      if (n > 12) return null;
      const a = t[wr][0].toLowerCase();
      (a == "a" && ((i = f.AM), n == 12 && (n = 0)),
        a == "p" && ((i = f.PM), n != 12 && (n += 12)));
    }
    if (
      (e.assign("hour", n),
      e.assign("minute", r),
      i !== null
        ? e.assign("meridiem", i)
        : n < 12
          ? e.imply("meridiem", f.AM)
          : e.imply("meridiem", f.PM),
      t[$r] != null)
    ) {
      const a = parseInt(t[$r]);
      if (a >= 60) return null;
      e.assign("second", a);
    }
    return e;
  }
}
const su = new RegExp(
    `(?:on\\s*?)?(${Tr})(?:\\s*(?:au|\\-|\\–|jusqu'au?|\\s)\\s*(${Tr}))?(?:-|/|\\s*(?:de)?\\s*)(${P(ks)})(?:(?:-|/|,?\\s*)(${qo}(?![^\\s]\\d)))?(?=\\W|$)`,
    "i",
  ),
  Or = 1,
  xr = 2,
  iu = 3,
  _r = 4;
class au extends g {
  innerPattern() {
    return su;
  }
  innerExtract(e, t) {
    const n = e.createParsingResult(t.index, t[0]),
      r = ks[t[iu].toLowerCase()],
      i = Pr(t[Or]);
    if (i > 31) return ((t.index = t.index + t[Or].length), null);
    if ((n.start.assign("month", r), n.start.assign("day", i), t[_r])) {
      const a = Ko(t[_r]);
      n.start.assign("year", a);
    } else {
      const a = L(e.refDate, i, r);
      n.start.imply("year", a);
    }
    if (t[xr]) {
      const a = Pr(t[xr]);
      ((n.end = n.start.clone()), n.end.assign("day", a));
    }
    return n;
  }
}
let ou = class extends g {
  constructor() {
    super();
  }
  innerPattern() {
    return new RegExp(`il y a\\s*(${Ls})(?=(?:\\W|$))`, "i");
  }
  innerExtract(e, t) {
    const n = js(t[1]),
      r = H(n);
    return p.createRelativeFromReference(e.reference, r);
  }
};
class uu extends g {
  innerPattern() {
    return new RegExp(`(?:dans|en|pour|pendant|de)\\s*(${Ls})(?=\\W|$)`, "i");
  }
  innerExtract(e, t) {
    const n = js(t[1]);
    return p.createRelativeFromReference(e.reference, n);
  }
}
class du extends g {
  constructor() {
    super();
  }
  innerPattern() {
    return new RegExp(
      `(?:les?|la|l'|du|des?)\\s*(${Ws})?(?:\\s*(prochaine?s?|derni[eè]re?s?|pass[ée]e?s?|pr[ée]c[ée]dents?|suivante?s?))?\\s*(${P(gt)})(?:\\s*(prochaine?s?|derni[eè]re?s?|pass[ée]e?s?|pr[ée]c[ée]dents?|suivante?s?))?`,
      "i",
    );
  }
  innerExtract(e, t) {
    const n = t[1] ? Fs(t[1]) : 1,
      r = gt[t[3].toLowerCase()];
    let i = {};
    i[r] = n;
    let a = t[2] || t[4] || "";
    if (((a = a.toLowerCase()), !!a))
      return (
        (/derni[eè]re?s?/.test(a) ||
          /pass[ée]e?s?/.test(a) ||
          /pr[ée]c[ée]dents?/.test(a)) &&
          (i = H(i)),
        p.createRelativeFromReference(e.reference, i)
      );
  }
}
const fn = new $(Ys()),
  lu = new $(cn(!0));
function fu(s, e, t) {
  return fn.parse(s, e, t);
}
function cu(s, e, t) {
  return fn.parseDate(s, e, t);
}
function Ys(s = !0) {
  const e = cn(!1, s);
  return (
    e.parsers.unshift(new Yo()),
    e.parsers.unshift(new zo()),
    e.parsers.unshift(new du()),
    e
  );
}
function cn(s = !0, e = !0) {
  return X(
    {
      parsers: [
        new ge(e),
        new au(),
        new Ho(),
        new yt(),
        new ou(),
        new uu(),
        new eu(),
      ],
      refiners: [new Bo(), new Vo()],
    },
    s,
  );
}
const Kf = Object.freeze(
  Object.defineProperty(
    {
      __proto__: null,
      Chrono: $,
      get Meridiem() {
        return f;
      },
      ParsingComponents: p,
      ParsingResult: I,
      ReferenceWithTimezone: G,
      get Weekday() {
        return _;
      },
      casual: fn,
      createCasualConfiguration: Ys,
      createConfiguration: cn,
      parse: fu,
      parseDate: cu,
      strict: lu,
    },
    Symbol.toStringTag,
    { value: "Module" },
  ),
);
function bt(s) {
  return String(s)
    .replace(/\u2019/g, "'")
    .replace(/\u201D/g, '"')
    .replace(/\u3000/g, " ")
    .replace(/\uFFE5/g, "¥")
    .replace(
      /[\uFF01\uFF03-\uFF06\uFF08\uFF09\uFF0C-\uFF19\uFF1C-\uFF1F\uFF21-\uFF3B\uFF3D\uFF3F\uFF41-\uFF5B\uFF5D\uFF5E]/g,
      mu,
    );
}
function mu(s) {
  return String.fromCharCode(s.charCodeAt(0) - 65248);
}
const gu =
    /(?:(?:([同今本])|((昭和|平成|令和)?([0-9０-９]{1,4}|元)))年\s*)?([0-9０-９]{1,2})月\s*([0-9０-９]{1,2})日/i,
  Nr = 1,
  yu = 2,
  St = 3,
  pu = 4,
  hu = 5,
  Tu = 6;
class Pu {
  pattern() {
    return gu;
  }
  extract(e, t) {
    const n = parseInt(bt(t[hu])),
      r = parseInt(bt(t[Tu])),
      i = e.createParsingComponents({ day: r, month: n });
    if (t[Nr] && t[Nr].match("同|今|本")) {
      const a = E(e.refDate);
      i.assign("year", a.year());
    }
    if (t[yu]) {
      const a = t[pu];
      let o = a == "元" ? 1 : parseInt(bt(a));
      (t[St] == "令和"
        ? (o += 2018)
        : t[St] == "平成"
          ? (o += 1988)
          : t[St] == "昭和" && (o += 1925),
        i.assign("year", o));
    } else {
      const a = L(e.refDate, r, n);
      i.imply("year", a);
    }
    return i;
  }
}
class Ru extends Z {
  patternBetween() {
    return /^\s*(から|ー|-)\s*$/i;
  }
}
const Eu =
  /今日|きょう|当日|とうじつ|昨日|きのう|明日|あした|今夜|こんや|今夕|こんゆう|今晩|こんばん|今朝|けさ/i;
function $u(s) {
  switch (s) {
    case "きょう":
      return "今日";
    case "とうじつ":
      return "当日";
    case "きのう":
      return "昨日";
    case "あした":
      return "明日";
    case "こんや":
      return "今夜";
    case "こんゆう":
      return "今夕";
    case "こんばん":
      return "今晩";
    case "けさ":
      return "今朝";
    default:
      return s;
  }
}
class wu {
  pattern() {
    return Eu;
  }
  extract(e, t) {
    const n = $u(t[0]),
      r = E(e.refDate),
      i = e.createParsingComponents();
    switch (n) {
      case "昨日":
        return fe(e.reference);
      case "明日":
        return ce(e.reference);
      case "今日":
      case "当日":
        return re(e.reference);
    }
    return (
      n == "今夜" || n == "今夕" || n == "今晩"
        ? (i.imply("hour", 22), i.assign("meridiem", f.PM))
        : n.match("今朝") && (i.imply("hour", 6), i.assign("meridiem", f.AM)),
      i.assign("day", r.date()),
      i.assign("month", r.month() + 1),
      i.assign("year", r.year()),
      i
    );
  }
}
const mn = new $(zs()),
  Ou = new $(gn());
function xu(s, e, t) {
  return mn.parse(s, e, t);
}
function _u(s, e, t) {
  return mn.parseDate(s, e, t);
}
function zs() {
  const s = gn();
  return (s.parsers.unshift(new wu()), s);
}
function gn() {
  return { parsers: [new Pu()], refiners: [new Ru()] };
}
const Zf = Object.freeze(
    Object.defineProperty(
      {
        __proto__: null,
        Chrono: $,
        get Meridiem() {
          return f;
        },
        ParsingComponents: p,
        ParsingResult: I,
        ReferenceWithTimezone: G,
        get Weekday() {
          return _;
        },
        casual: mn,
        createCasualConfiguration: zs,
        createConfiguration: gn,
        parse: xu,
        parseDate: _u,
        strict: Ou,
      },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  ),
  Hs = {
    domingo: 0,
    dom: 0,
    segunda: 1,
    "segunda-feira": 1,
    seg: 1,
    terça: 2,
    "terça-feira": 2,
    ter: 2,
    quarta: 3,
    "quarta-feira": 3,
    qua: 3,
    quinta: 4,
    "quinta-feira": 4,
    qui: 4,
    sexta: 5,
    "sexta-feira": 5,
    sex: 5,
    sábado: 6,
    sabado: 6,
    sab: 6,
  },
  Bs = {
    janeiro: 1,
    jan: 1,
    "jan.": 1,
    fevereiro: 2,
    fev: 2,
    "fev.": 2,
    março: 3,
    mar: 3,
    "mar.": 3,
    abril: 4,
    abr: 4,
    "abr.": 4,
    maio: 5,
    mai: 5,
    "mai.": 5,
    junho: 6,
    jun: 6,
    "jun.": 6,
    julho: 7,
    jul: 7,
    "jul.": 7,
    agosto: 8,
    ago: 8,
    "ago.": 8,
    setembro: 9,
    set: 9,
    "set.": 9,
    outubro: 10,
    out: 10,
    "out.": 10,
    novembro: 11,
    nov: 11,
    "nov.": 11,
    dezembro: 12,
    dez: 12,
    "dez.": 12,
  },
  Nu = "[0-9]{1,4}(?![^\\s]\\d)(?:\\s*[a|d]\\.?\\s*c\\.?|\\s*a\\.?\\s*d\\.?)?";
function Mu(s) {
  if (s.match(/^[0-9]{1,4}$/)) {
    let e = parseInt(s);
    return (e < 100 && (e > 50 ? (e = e + 1900) : (e = e + 2e3)), e);
  }
  return s.match(/a\.?\s*c\.?/i)
    ? ((s = s.replace(/a\.?\s*c\.?/i, "")), -parseInt(s))
    : parseInt(s);
}
const Au = new RegExp(
    `(?:(?:\\,|\\(|\\（)\\s*)?(?:(este|esta|passado|pr[oó]ximo)\\s*)?(${P(Hs)})(?:\\s*(?:\\,|\\)|\\）))?(?:\\s*(este|esta|passado|pr[óo]ximo)\\s*semana)?(?=\\W|\\d|$)`,
    "i",
  ),
  Du = 1,
  Cu = 2,
  Uu = 3;
class Iu extends g {
  innerPattern() {
    return Au;
  }
  innerExtract(e, t) {
    const n = t[Cu].toLowerCase(),
      r = Hs[n];
    if (r === void 0) return null;
    const i = t[Du],
      a = t[Uu];
    let o = i || a || "";
    o = o.toLowerCase();
    let u = null;
    return (
      o == "passado"
        ? (u = "this")
        : o == "próximo" || o == "proximo"
          ? (u = "next")
          : o == "este" && (u = "this"),
      me(e.reference, r, u)
    );
  }
}
class bu extends de {
  primaryPrefix() {
    return "(?:(?:ao?|às?|das|da|de|do)\\s*)?";
  }
  followingPhase() {
    return "\\s*(?:\\-|\\–|\\~|\\〜|a(?:o)?|\\?)\\s*";
  }
}
class Su extends Q {
  patternBetween() {
    return new RegExp("^\\s*(?:,|à)?\\s*$");
  }
}
class vu extends Z {
  patternBetween() {
    return /^\s*(?:-)\s*$/i;
  }
}
const ku = new RegExp(
    `([0-9]{1,2})(?:º|ª|°)?(?:\\s*(?:desde|de|\\-|\\–|ao?|\\s)\\s*([0-9]{1,2})(?:º|ª|°)?)?\\s*(?:de)?\\s*(?:-|/|\\s*(?:de|,)?\\s*)(${P(Bs)})(?:\\s*(?:de|,)?\\s*(${Nu}))?(?=\\W|$)`,
    "i",
  ),
  Mr = 1,
  Ar = 2,
  Wu = 3,
  Dr = 4;
class Fu extends g {
  innerPattern() {
    return ku;
  }
  innerExtract(e, t) {
    const n = e.createParsingResult(t.index, t[0]),
      r = Bs[t[Wu].toLowerCase()],
      i = parseInt(t[Mr]);
    if (i > 31) return ((t.index = t.index + t[Mr].length), null);
    if ((n.start.assign("month", r), n.start.assign("day", i), t[Dr])) {
      const a = Mu(t[Dr]);
      n.start.assign("year", a);
    } else {
      const a = L(e.refDate, i, r);
      n.start.imply("year", a);
    }
    if (t[Ar]) {
      const a = parseInt(t[Ar]);
      ((n.end = n.start.clone()), n.end.assign("day", a));
    }
    return n;
  }
}
class Gu extends g {
  innerPattern(e) {
    return /(agora|hoje|amanha|amanhã|ontem)(?=\W|$)/i;
  }
  innerExtract(e, t) {
    const n = t[0].toLowerCase(),
      r = e.createParsingComponents();
    switch (n) {
      case "agora":
        return le(e.reference);
      case "hoje":
        return re(e.reference);
      case "amanha":
      case "amanhã":
        return ce(e.reference);
      case "ontem":
        return fe(e.reference);
    }
    return r;
  }
}
class Lu extends g {
  innerPattern() {
    return /(?:esta\s*)?(manha|manhã|tarde|meia-noite|meio-dia|noite)(?=\W|$)/i;
  }
  innerExtract(e, t) {
    const n = E(e.refDate),
      r = e.createParsingComponents();
    switch (t[1].toLowerCase()) {
      case "tarde":
        (r.imply("meridiem", f.PM), r.imply("hour", 15));
        break;
      case "noite":
        (r.imply("meridiem", f.PM), r.imply("hour", 22));
        break;
      case "manha":
      case "manhã":
        (r.imply("meridiem", f.AM), r.imply("hour", 6));
        break;
      case "meia-noite":
        (we(r, n),
          r.imply("hour", 0),
          r.imply("minute", 0),
          r.imply("second", 0));
        break;
      case "meio-dia":
        (r.imply("meridiem", f.AM), r.imply("hour", 12));
        break;
    }
    return r;
  }
}
const yn = new $(Vs()),
  ju = new $(pn(!0));
function Yu(s, e, t) {
  return yn.parse(s, e, t);
}
function zu(s, e, t) {
  return yn.parseDate(s, e, t);
}
function Vs(s = !0) {
  const e = pn(!1, s);
  return (e.parsers.push(new Gu()), e.parsers.push(new Lu()), e);
}
function pn(s = !0, e = !0) {
  return X(
    {
      parsers: [new ge(e), new Iu(), new bu(), new Fu()],
      refiners: [new Su(), new vu()],
    },
    s,
  );
}
const Xf = Object.freeze(
  Object.defineProperty(
    {
      __proto__: null,
      Chrono: $,
      get Meridiem() {
        return f;
      },
      ParsingComponents: p,
      ParsingResult: I,
      ReferenceWithTimezone: G,
      get Weekday() {
        return _;
      },
      casual: yn,
      createCasualConfiguration: Vs,
      createConfiguration: pn,
      parse: Yu,
      parseDate: zu,
      strict: ju,
    },
    Symbol.toStringTag,
    { value: "Module" },
  ),
);
class Hu extends Z {
  patternBetween() {
    return /^\s*(tot|-)\s*$/i;
  }
}
class Bu extends Q {
  patternBetween() {
    return new RegExp("^\\s*(om|na|voor|in de|,|-)?\\s*$");
  }
}
class Vu extends g {
  innerPattern(e) {
    return /(nu|vandaag|morgen|morgend|gisteren)(?=\W|$)/i;
  }
  innerExtract(e, t) {
    const n = t[0].toLowerCase(),
      r = e.createParsingComponents();
    switch (n) {
      case "nu":
        return le(e.reference);
      case "vandaag":
        return re(e.reference);
      case "morgen":
      case "morgend":
        return ce(e.reference);
      case "gisteren":
        return fe(e.reference);
    }
    return r;
  }
}
const qu = 1,
  Ku = 2;
class Zu extends g {
  innerPattern() {
    return /(deze)?\s*(namiddag|avond|middernacht|ochtend|middag|'s middags|'s avonds|'s ochtends)(?=\W|$)/i;
  }
  innerExtract(e, t) {
    const n = E(e.refDate),
      r = e.createParsingComponents();
    switch (
      (t[qu] === "deze" &&
        (r.assign("day", e.refDate.getDate()),
        r.assign("month", e.refDate.getMonth() + 1),
        r.assign("year", e.refDate.getFullYear())),
      t[Ku].toLowerCase())
    ) {
      case "namiddag":
      case "'s namiddags":
        (r.imply("meridiem", f.PM), r.imply("hour", 15));
        break;
      case "avond":
      case "'s avonds'":
        (r.imply("meridiem", f.PM), r.imply("hour", 20));
        break;
      case "middernacht":
        (we(r, n),
          r.imply("hour", 0),
          r.imply("minute", 0),
          r.imply("second", 0));
        break;
      case "ochtend":
      case "'s ochtends":
        (r.imply("meridiem", f.AM), r.imply("hour", 6));
        break;
      case "middag":
      case "'s middags":
        (r.imply("meridiem", f.AM), r.imply("hour", 12));
        break;
    }
    return r;
  }
}
const qs = {
    zondag: 0,
    zon: 0,
    "zon.": 0,
    zo: 0,
    "zo.": 0,
    maandag: 1,
    ma: 1,
    "ma.": 1,
    dinsdag: 2,
    din: 2,
    "din.": 2,
    di: 2,
    "di.": 2,
    woensdag: 3,
    woe: 3,
    "woe.": 3,
    wo: 3,
    "wo.": 3,
    donderdag: 4,
    dond: 4,
    "dond.": 4,
    do: 4,
    "do.": 4,
    vrijdag: 5,
    vrij: 5,
    "vrij.": 5,
    vr: 5,
    "vr.": 5,
    zaterdag: 6,
    zat: 6,
    "zat.": 6,
    za: 6,
    "za.": 6,
  },
  Ne = {
    januari: 1,
    jan: 1,
    "jan.": 1,
    februari: 2,
    feb: 2,
    "feb.": 2,
    maart: 3,
    mar: 3,
    "mar.": 3,
    mrt: 3,
    "mrt.": 3,
    april: 4,
    apr: 4,
    "apr.": 4,
    mei: 5,
    juni: 6,
    jun: 6,
    "jun.": 6,
    juli: 7,
    jul: 7,
    "jul.": 7,
    augustus: 8,
    aug: 8,
    "aug.": 8,
    september: 9,
    sep: 9,
    "sep.": 9,
    sept: 9,
    "sept.": 9,
    oktober: 10,
    okt: 10,
    "okt.": 10,
    november: 11,
    nov: 11,
    "nov.": 11,
    december: 12,
    dec: 12,
    "dec.": 12,
  },
  Kt = {
    een: 1,
    twee: 2,
    drie: 3,
    vier: 4,
    vijf: 5,
    zes: 6,
    zeven: 7,
    acht: 8,
    negen: 9,
    tien: 10,
    elf: 11,
    twaalf: 12,
  },
  Zt = {
    eerste: 1,
    tweede: 2,
    derde: 3,
    vierde: 4,
    vijfde: 5,
    zesde: 6,
    zevende: 7,
    achtste: 8,
    negende: 9,
    tiende: 10,
    elfde: 11,
    twaalfde: 12,
    dertiende: 13,
    veertiende: 14,
    vijftiende: 15,
    zestiende: 16,
    zeventiende: 17,
    achttiende: 18,
    negentiende: 19,
    twintigste: 20,
    eenentwintigste: 21,
    tweeëntwintigste: 22,
    drieentwintigste: 23,
    vierentwintigste: 24,
    vijfentwintigste: 25,
    zesentwintigste: 26,
    zevenentwintigste: 27,
    achtentwintig: 28,
    negenentwintig: 29,
    dertigste: 30,
    eenendertigste: 31,
  },
  _t = {
    sec: "second",
    second: "second",
    seconden: "second",
    min: "minute",
    mins: "minute",
    minute: "minute",
    minuut: "minute",
    minuten: "minute",
    minuutje: "minute",
    h: "hour",
    hr: "hour",
    hrs: "hour",
    uur: "hour",
    u: "hour",
    uren: "hour",
    dag: "d",
    dagen: "d",
    week: "week",
    weken: "week",
    maand: "month",
    maanden: "month",
    jaar: "year",
    jr: "year",
    jaren: "year",
  },
  Xu = `(?:${P(Kt)}|[0-9]+|[0-9]+[\\.,][0-9]+|halve?|half|paar)`;
function Ju(s) {
  const e = s.toLowerCase();
  return Kt[e] !== void 0
    ? Kt[e]
    : e === "paar"
      ? 2
      : e === "half" || e.match(/halve?/)
        ? 0.5
        : parseFloat(e.replace(",", "."));
}
const Cr = `(?:${P(Zt)}|[0-9]{1,2}(?:ste|de)?)`;
function Ur(s) {
  let e = s.toLowerCase();
  return Zt[e] !== void 0
    ? Zt[e]
    : ((e = e.replace(/(?:ste|de)$/i, "")), parseInt(e));
}
const Ks =
  "(?:[1-9][0-9]{0,3}\\s*(?:voor Christus|na Christus)|[1-2][0-9]{3}|[5-9][0-9])";
function Zs(s) {
  if (/voor Christus/i.test(s))
    return ((s = s.replace(/voor Christus/i, "")), -parseInt(s));
  if (/na Christus/i.test(s))
    return ((s = s.replace(/na Christus/i, "")), parseInt(s));
  const e = parseInt(s);
  return xe(e);
}
const Xs = `(${Xu})\\s{0,5}(${P(_t)})\\s{0,5}`,
  Ir = new RegExp(Xs, "i"),
  Me = oe("(?:(?:binnen|in)\\s*)?", Xs);
function Nt(s) {
  const e = {};
  let t = s,
    n = Ir.exec(t);
  for (; n;) (Qu(e, n), (t = t.substring(n[0].length)), (n = Ir.exec(t)));
  return e;
}
function Qu(s, e) {
  const t = Ju(e[1]),
    n = _t[e[2].toLowerCase()];
  s[n] = t;
}
class ed extends g {
  innerPattern() {
    return new RegExp(
      "(?:binnen|in|binnen de|voor)\\s*(" + Me + ")(?=\\W|$)",
      "i",
    );
  }
  innerExtract(e, t) {
    const n = Nt(t[1]);
    return p.createRelativeFromReference(e.reference, n);
  }
}
const td = new RegExp(
    `(?:(?:\\,|\\(|\\（)\\s*)?(?:op\\s*?)?(?:(deze|vorige|volgende)\\s*(?:week\\s*)?)?(${P(qs)})(?=\\W|$)`,
    "i",
  ),
  nd = 1,
  rd = 2,
  sd = 3;
class id extends g {
  innerPattern() {
    return td;
  }
  innerExtract(e, t) {
    const n = t[rd].toLowerCase(),
      r = qs[n],
      i = t[nd],
      a = t[sd];
    let o = i || a;
    ((o = o || ""), (o = o.toLowerCase()));
    let u = null;
    return (
      o == "vorige"
        ? (u = "last")
        : o == "volgende"
          ? (u = "next")
          : o == "deze" && (u = "this"),
      me(e.reference, r, u)
    );
  }
}
const ad = new RegExp(
    `(?:on\\s*?)?(${Cr})(?:\\s*(?:tot|\\-|\\–|until|through|till|\\s)\\s*(${Cr}))?(?:-|/|\\s*(?:of)?\\s*)(` +
      P(Ne) +
      `)(?:(?:-|/|,?\\s*)(${Ks}(?![^\\s]\\d)))?(?=\\W|$)`,
    "i",
  ),
  od = 3,
  br = 1,
  Sr = 2,
  vr = 4;
class ud extends g {
  innerPattern() {
    return ad;
  }
  innerExtract(e, t) {
    const n = Ne[t[od].toLowerCase()],
      r = Ur(t[br]);
    if (r > 31) return ((t.index = t.index + t[br].length), null);
    const i = e.createParsingComponents({ day: r, month: n });
    if (t[vr]) {
      const u = Zs(t[vr]);
      i.assign("year", u);
    } else {
      const u = L(e.refDate, r, n);
      i.imply("year", u);
    }
    if (!t[Sr]) return i;
    const a = Ur(t[Sr]),
      o = e.createParsingResult(t.index, t[0]);
    return ((o.start = i), (o.end = i.clone()), o.end.assign("day", a), o);
  }
}
const dd = new RegExp(
    `(${P(Ne)})\\s*(?:[,-]?\\s*(${Ks})?)?(?=[^\\s\\w]|\\s+[^0-9]|\\s+$|$)`,
    "i",
  ),
  ld = 1,
  kr = 2;
class Js extends g {
  innerPattern() {
    return dd;
  }
  innerExtract(e, t) {
    const n = e.createParsingComponents();
    n.imply("day", 1);
    const r = t[ld],
      i = Ne[r.toLowerCase()];
    if ((n.assign("month", i), t[kr])) {
      const a = Zs(t[kr]);
      n.assign("year", a);
    } else {
      const a = L(e.refDate, 1, i);
      n.imply("year", a);
    }
    return n;
  }
}
const fd = new RegExp("([0-9]|0[1-9]|1[012])/([0-9]{4})", "i"),
  cd = 1,
  md = 2;
class gd extends g {
  innerPattern() {
    return fd;
  }
  innerExtract(e, t) {
    const n = parseInt(t[md]),
      r = parseInt(t[cd]);
    return e
      .createParsingComponents()
      .imply("day", 1)
      .assign("month", r)
      .assign("year", n);
  }
}
class yd extends de {
  primaryPrefix() {
    return "(?:(?:om)\\s*)?";
  }
  followingPhase() {
    return "\\s*(?:\\-|\\–|\\~|\\〜|om|\\?)\\s*";
  }
  primarySuffix() {
    return "(?:\\s*(?:uur))?(?!/)(?=\\W|$)";
  }
  extractPrimaryTimeComponents(e, t) {
    return t[0].match(/^\s*\d{4}\s*$/)
      ? null
      : super.extractPrimaryTimeComponents(e, t);
  }
}
const pd = new RegExp(
    `([0-9]{4})[\\.\\/\\s](?:(${P(Ne)})|([0-9]{1,2}))[\\.\\/\\s]([0-9]{1,2})(?=\\W|$)`,
    "i",
  ),
  hd = 1,
  Td = 2,
  Wr = 3,
  Pd = 4;
class Rd extends g {
  innerPattern() {
    return pd;
  }
  innerExtract(e, t) {
    const n = t[Wr] ? parseInt(t[Wr]) : Ne[t[Td].toLowerCase()];
    if (n < 1 || n > 12) return null;
    const r = parseInt(t[hd]);
    return { day: parseInt(t[Pd]), month: n, year: r };
  }
}
const Ed = 1,
  $d = 2;
class wd extends g {
  innerPattern(e) {
    return /(gisteren|morgen|van)(ochtend|middag|namiddag|avond|nacht)(?=\W|$)/i;
  }
  innerExtract(e, t) {
    const n = t[Ed].toLowerCase(),
      r = t[$d].toLowerCase(),
      i = e.createParsingComponents(),
      a = E(e.refDate);
    switch (n) {
      case "gisteren":
        D(i, a.add(-1, "day"));
        break;
      case "van":
        D(i, a);
        break;
      case "morgen":
        we(i, a);
        break;
    }
    switch (r) {
      case "ochtend":
        (i.imply("meridiem", f.AM), i.imply("hour", 6));
        break;
      case "middag":
        (i.imply("meridiem", f.AM), i.imply("hour", 12));
        break;
      case "namiddag":
        (i.imply("meridiem", f.PM), i.imply("hour", 15));
        break;
      case "avond":
        (i.imply("meridiem", f.PM), i.imply("hour", 20));
        break;
    }
    return i;
  }
}
const Od = new RegExp(
    `(dit|deze|vorig|afgelopen|(?:aan)?komend|over|\\+|-)e?\\s*(${Me})(?=\\W|$)`,
    "i",
  ),
  xd = 1,
  _d = 2;
class Nd extends g {
  innerPattern() {
    return Od;
  }
  innerExtract(e, t) {
    const n = t[xd].toLowerCase();
    let r = Nt(t[_d]);
    switch (n) {
      case "vorig":
      case "afgelopen":
      case "-":
        r = H(r);
        break;
    }
    return p.createRelativeFromReference(e.reference, r);
  }
}
const Md = new RegExp(
    `(dit|deze|(?:aan)?komend|volgend|afgelopen|vorig)e?\\s*(${P(_t)})(?=\\s*)(?=\\W|$)`,
    "i",
  ),
  Ad = 1,
  Dd = 2;
class Cd extends g {
  innerPattern() {
    return Md;
  }
  innerExtract(e, t) {
    const n = t[Ad].toLowerCase(),
      r = t[Dd].toLowerCase(),
      i = _t[r];
    if (n == "volgend" || n == "komend" || n == "aankomend") {
      const u = {};
      return ((u[i] = 1), p.createRelativeFromReference(e.reference, u));
    }
    if (n == "afgelopen" || n == "vorig") {
      const u = {};
      return ((u[i] = -1), p.createRelativeFromReference(e.reference, u));
    }
    const a = e.createParsingComponents();
    let o = E(e.reference.instant);
    return (
      r.match(/week/i)
        ? ((o = o.add(-o.get("d"), "d")),
          a.imply("day", o.date()),
          a.imply("month", o.month() + 1),
          a.imply("year", o.year()))
        : r.match(/maand/i)
          ? ((o = o.add(-o.date() + 1, "d")),
            a.imply("day", o.date()),
            a.assign("year", o.year()),
            a.assign("month", o.month() + 1))
          : r.match(/jaar/i) &&
            ((o = o.add(-o.date() + 1, "d")),
            (o = o.add(-o.month(), "month")),
            a.imply("day", o.date()),
            a.imply("month", o.month() + 1),
            a.assign("year", o.year())),
      a
    );
  }
}
const Ud = new RegExp("(" + Me + ")(?:geleden|voor|eerder)(?=(?:\\W|$))", "i"),
  Id = new RegExp("(" + Me + ")geleden(?=(?:\\W|$))", "i");
class bd extends g {
  constructor(e) {
    (super(), (this.strictMode = e));
  }
  innerPattern() {
    return this.strictMode ? Id : Ud;
  }
  innerExtract(e, t) {
    const n = Nt(t[1]),
      r = H(n);
    return p.createRelativeFromReference(e.reference, r);
  }
}
const Sd = new RegExp(
    "(" + Me + ")(later|na|vanaf nu|voortaan|vooruit|uit)(?=(?:\\W|$))",
    "i",
  ),
  vd = new RegExp("(" + Me + ")(later|vanaf nu)(?=(?:\\W|$))", "i"),
  kd = 1;
class Wd extends g {
  constructor(e) {
    (super(), (this.strictMode = e));
  }
  innerPattern() {
    return this.strictMode ? vd : Sd;
  }
  innerExtract(e, t) {
    const n = Nt(t[kd]);
    return p.createRelativeFromReference(e.reference, n);
  }
}
const hn = new $(Qs()),
  Fd = new $(Tn(!0));
function Gd(s, e, t) {
  return hn.parse(s, e, t);
}
function Ld(s, e, t) {
  return hn.parseDate(s, e, t);
}
function Qs(s = !0) {
  const e = Tn(!1, s);
  return (
    e.parsers.unshift(new Vu()),
    e.parsers.unshift(new Zu()),
    e.parsers.unshift(new wd()),
    e.parsers.unshift(new Js()),
    e.parsers.unshift(new Cd()),
    e.parsers.unshift(new Nd()),
    e
  );
}
function Tn(s = !0, e = !0) {
  return X(
    {
      parsers: [
        new ge(e),
        new ed(),
        new ud(),
        new Js(),
        new id(),
        new Rd(),
        new gd(),
        new yd(s),
        new bd(s),
        new Wd(s),
      ],
      refiners: [new Bu(), new Hu()],
    },
    s,
  );
}
const Jf = Object.freeze(
    Object.defineProperty(
      {
        __proto__: null,
        Chrono: $,
        get Meridiem() {
          return f;
        },
        ParsingComponents: p,
        ParsingResult: I,
        ReferenceWithTimezone: G,
        get Weekday() {
          return _;
        },
        casual: hn,
        createCasualConfiguration: Qs,
        createConfiguration: Tn,
        parse: Gd,
        parseDate: Ld,
        strict: Fd,
      },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  ),
  W = {
    零: 0,
    〇: 0,
    一: 1,
    二: 2,
    两: 2,
    三: 3,
    四: 4,
    五: 5,
    六: 6,
    七: 7,
    八: 8,
    九: 9,
    十: 10,
  },
  Mt = { 天: 0, 日: 0, 一: 1, 二: 2, 三: 3, 四: 4, 五: 5, 六: 6 };
function ee(s) {
  let e = 0;
  for (let t = 0; t < s.length; t++) {
    const n = s[t];
    n === "十" ? (e = e === 0 ? W[n] : e * W[n]) : (e += W[n]);
  }
  return e;
}
function jd(s) {
  let e = "";
  for (let t = 0; t < s.length; t++) {
    const n = s[t];
    e = e + W[n];
  }
  return parseInt(e);
}
const vt = 1,
  Fr = 2,
  kt = 3;
class ei extends g {
  innerPattern() {
    return new RegExp(
      "(\\d{2,4}|[" +
        Object.keys(W).join("") +
        "]{4}|[" +
        Object.keys(W).join("") +
        "]{2})?(?:\\s*)(?:年)?(?:[\\s|,|，]*)(\\d{1,2}|[" +
        Object.keys(W).join("") +
        "]{1,3})(?:\\s*)(?:月)(?:\\s*)(\\d{1,2}|[" +
        Object.keys(W).join("") +
        "]{1,3})?(?:\\s*)(?:日|号)?",
    );
  }
  innerExtract(e, t) {
    const n = E(e.refDate),
      r = e.createParsingResult(t.index, t[0]);
    let i = parseInt(t[Fr]);
    if ((isNaN(i) && (i = ee(t[Fr])), r.start.assign("month", i), t[kt])) {
      let a = parseInt(t[kt]);
      (isNaN(a) && (a = ee(t[kt])), r.start.assign("day", a));
    } else r.start.imply("day", n.date());
    if (t[vt]) {
      let a = parseInt(t[vt]);
      (isNaN(a) && (a = jd(t[vt])), r.start.assign("year", a));
    } else r.start.imply("year", n.year());
    return r;
  }
}
const Yd = new RegExp(
    "(\\d+|[" +
      Object.keys(W).join("") +
      "]+|半|几)(?:\\s*)(?:个)?(秒(?:钟)?|分钟|小时|钟|日|天|星期|礼拜|月|年)(?:(?:之|过)?后|(?:之)?内)",
    "i",
  ),
  Wt = 1,
  zd = 2;
class ti extends g {
  innerPattern() {
    return Yd;
  }
  innerExtract(e, t) {
    const n = e.createParsingResult(t.index, t[0]);
    let r = parseInt(t[Wt]);
    if ((isNaN(r) && (r = ee(t[Wt])), isNaN(r))) {
      const u = t[Wt];
      if (u === "几") r = 3;
      else if (u === "半") r = 0.5;
      else return null;
    }
    let i = E(e.refDate);
    const o = t[zd][0];
    return o.match(/[日天星礼月年]/)
      ? (o == "日" || o == "天"
          ? (i = i.add(r, "d"))
          : o == "星" || o == "礼"
            ? (i = i.add(r * 7, "d"))
            : o == "月"
              ? (i = i.add(r, "month"))
              : o == "年" && (i = i.add(r, "year")),
        n.start.assign("year", i.year()),
        n.start.assign("month", i.month() + 1),
        n.start.assign("day", i.date()),
        n)
      : (o == "秒"
          ? (i = i.add(r, "second"))
          : o == "分"
            ? (i = i.add(r, "minute"))
            : (o == "小" || o == "钟") && (i = i.add(r, "hour")),
        n.start.imply("year", i.year()),
        n.start.imply("month", i.month() + 1),
        n.start.imply("day", i.date()),
        n.start.assign("hour", i.hour()),
        n.start.assign("minute", i.minute()),
        n.start.assign("second", i.second()),
        n);
  }
}
const Hd = new RegExp(
  "(?<prefix>上|下|这)(?:个)?(?:星期|礼拜|周)(?<weekday>" +
    Object.keys(Mt).join("|") +
    ")",
);
class ni extends g {
  innerPattern() {
    return Hd;
  }
  innerExtract(e, t) {
    const n = e.createParsingResult(t.index, t[0]),
      r = t.groups.weekday,
      i = Mt[r];
    if (i === void 0) return null;
    let a = null;
    const o = t.groups.prefix;
    o == "上"
      ? (a = "last")
      : o == "下"
        ? (a = "next")
        : o == "这" && (a = "this");
    let u = E(e.refDate),
      d = !1;
    const l = u.day();
    return (
      a == "last" || a == "past"
        ? ((u = u.day(i - 7)), (d = !0))
        : a == "next"
          ? ((u = u.day(i + 7)), (d = !0))
          : a == "this"
            ? (u = u.day(i))
            : Math.abs(i - 7 - l) < Math.abs(i - l)
              ? (u = u.day(i - 7))
              : Math.abs(i + 7 - l) < Math.abs(i - l)
                ? (u = u.day(i + 7))
                : (u = u.day(i)),
      n.start.assign("weekday", i),
      d
        ? (n.start.assign("day", u.date()),
          n.start.assign("month", u.month() + 1),
          n.start.assign("year", u.year()))
        : (n.start.imply("day", u.date()),
          n.start.imply("month", u.month() + 1),
          n.start.imply("year", u.year())),
      n
    );
  }
}
const Bd = new RegExp(
    "(?:从|自)?(?:(今|明|前|大前|后|大后|昨)(早|朝|晚)|(上(?:午)|早(?:上)|下(?:午)|晚(?:上)|夜(?:晚)?|中(?:午)|凌(?:晨))|(今|明|前|大前|后|大后|昨)(?:日|天)(?:[\\s,，]*)(?:(上(?:午)|早(?:上)|下(?:午)|晚(?:上)|夜(?:晚)?|中(?:午)|凌(?:晨)))?)?(?:[\\s,，]*)(?:(\\d+|[" +
      Object.keys(W).join("") +
      "]+)(?:\\s*)(?:点|时|:|：)(?:\\s*)(\\d+|半|正|整|[" +
      Object.keys(W).join("") +
      "]+)?(?:\\s*)(?:分|:|：)?(?:\\s*)(\\d+|[" +
      Object.keys(W).join("") +
      "]+)?(?:\\s*)(?:秒)?)(?:\\s*(A.M.|P.M.|AM?|PM?))?",
    "i",
  ),
  Vd = new RegExp(
    "(?:^\\s*(?:到|至|\\-|\\–|\\~|\\〜)\\s*)(?:(今|明|前|大前|后|大后|昨)(早|朝|晚)|(上(?:午)|早(?:上)|下(?:午)|晚(?:上)|夜(?:晚)?|中(?:午)|凌(?:晨))|(今|明|前|大前|后|大后|昨)(?:日|天)(?:[\\s,，]*)(?:(上(?:午)|早(?:上)|下(?:午)|晚(?:上)|夜(?:晚)?|中(?:午)|凌(?:晨)))?)?(?:[\\s,，]*)(?:(\\d+|[" +
      Object.keys(W).join("") +
      "]+)(?:\\s*)(?:点|时|:|：)(?:\\s*)(\\d+|半|正|整|[" +
      Object.keys(W).join("") +
      "]+)?(?:\\s*)(?:分|:|：)?(?:\\s*)(\\d+|[" +
      Object.keys(W).join("") +
      "]+)?(?:\\s*)(?:秒)?)(?:\\s*(A.M.|P.M.|AM?|PM?))?",
    "i",
  ),
  Be = 1,
  Ve = 2,
  qe = 3,
  Ke = 4,
  Ze = 5,
  Xe = 6,
  V = 7,
  Ee = 8,
  Je = 9;
class ri extends g {
  innerPattern() {
    return Bd;
  }
  innerExtract(e, t) {
    if (t.index > 0 && e.text[t.index - 1].match(/\w/)) return null;
    const n = E(e.refDate),
      r = e.createParsingResult(t.index, t[0]);
    let i = n.clone();
    if (t[Be]) {
      const l = t[Be];
      (l == "明"
        ? n.hour() > 1 && (i = i.add(1, "day"))
        : l == "昨"
          ? (i = i.add(-1, "day"))
          : l == "前"
            ? (i = i.add(-2, "day"))
            : l == "大前"
              ? (i = i.add(-3, "day"))
              : l == "后"
                ? (i = i.add(2, "day"))
                : l == "大后" && (i = i.add(3, "day")),
        r.start.assign("day", i.date()),
        r.start.assign("month", i.month() + 1),
        r.start.assign("year", i.year()));
    } else if (t[Ke]) {
      const l = t[Ke];
      (l == "明"
        ? (i = i.add(1, "day"))
        : l == "昨"
          ? (i = i.add(-1, "day"))
          : l == "前"
            ? (i = i.add(-2, "day"))
            : l == "大前"
              ? (i = i.add(-3, "day"))
              : l == "后"
                ? (i = i.add(2, "day"))
                : l == "大后" && (i = i.add(3, "day")),
        r.start.assign("day", i.date()),
        r.start.assign("month", i.month() + 1),
        r.start.assign("year", i.year()));
    } else
      (r.start.imply("day", i.date()),
        r.start.imply("month", i.month() + 1),
        r.start.imply("year", i.year()));
    let a = 0,
      o = 0,
      u = -1;
    if (t[Ee]) {
      let l = parseInt(t[Ee]);
      if ((isNaN(l) && (l = ee(t[Ee])), l >= 60)) return null;
      r.start.assign("second", l);
    }
    if (
      ((a = parseInt(t[Xe])),
      isNaN(a) && (a = ee(t[Xe])),
      t[V]
        ? t[V] == "半"
          ? (o = 30)
          : t[V] == "正" || t[V] == "整"
            ? (o = 0)
            : ((o = parseInt(t[V])), isNaN(o) && (o = ee(t[V])))
        : a > 100 && ((o = a % 100), (a = Math.floor(a / 100))),
      o >= 60 || a > 24)
    )
      return null;
    if ((a >= 12 && (u = 1), t[Je])) {
      if (a > 12) return null;
      const l = t[Je][0].toLowerCase();
      (l == "a" && ((u = 0), a == 12 && (a = 0)),
        l == "p" && ((u = 1), a != 12 && (a += 12)));
    } else if (t[Ve]) {
      const h = t[Ve][0];
      h == "早"
        ? ((u = 0), a == 12 && (a = 0))
        : h == "晚" && ((u = 1), a != 12 && (a += 12));
    } else if (t[qe]) {
      const h = t[qe][0];
      h == "上" || h == "早" || h == "凌"
        ? ((u = 0), a == 12 && (a = 0))
        : (h == "下" || h == "晚") && ((u = 1), a != 12 && (a += 12));
    } else if (t[Ze]) {
      const h = t[Ze][0];
      h == "上" || h == "早" || h == "凌"
        ? ((u = 0), a == 12 && (a = 0))
        : (h == "下" || h == "晚") && ((u = 1), a != 12 && (a += 12));
    }
    if (
      (r.start.assign("hour", a),
      r.start.assign("minute", o),
      u >= 0
        ? r.start.assign("meridiem", u)
        : a < 12
          ? r.start.imply("meridiem", 0)
          : r.start.imply("meridiem", 1),
      (t = Vd.exec(e.text.substring(r.index + r.text.length))),
      !t)
    )
      return r.text.match(/^\d+$/) ? null : r;
    let d = i.clone();
    if (((r.end = e.createParsingComponents()), t[Be])) {
      const l = t[Be];
      (l == "明"
        ? n.hour() > 1 && (d = d.add(1, "day"))
        : l == "昨"
          ? (d = d.add(-1, "day"))
          : l == "前"
            ? (d = d.add(-2, "day"))
            : l == "大前"
              ? (d = d.add(-3, "day"))
              : l == "后"
                ? (d = d.add(2, "day"))
                : l == "大后" && (d = d.add(3, "day")),
        r.end.assign("day", d.date()),
        r.end.assign("month", d.month() + 1),
        r.end.assign("year", d.year()));
    } else if (t[Ke]) {
      const l = t[Ke];
      (l == "明"
        ? (d = d.add(1, "day"))
        : l == "昨"
          ? (d = d.add(-1, "day"))
          : l == "前"
            ? (d = d.add(-2, "day"))
            : l == "大前"
              ? (d = d.add(-3, "day"))
              : l == "后"
                ? (d = d.add(2, "day"))
                : l == "大后" && (d = d.add(3, "day")),
        r.end.assign("day", d.date()),
        r.end.assign("month", d.month() + 1),
        r.end.assign("year", d.year()));
    } else
      (r.end.imply("day", d.date()),
        r.end.imply("month", d.month() + 1),
        r.end.imply("year", d.year()));
    if (((a = 0), (o = 0), (u = -1), t[Ee])) {
      let l = parseInt(t[Ee]);
      if ((isNaN(l) && (l = ee(t[Ee])), l >= 60)) return null;
      r.end.assign("second", l);
    }
    if (
      ((a = parseInt(t[Xe])),
      isNaN(a) && (a = ee(t[Xe])),
      t[V]
        ? t[V] == "半"
          ? (o = 30)
          : t[V] == "正" || t[V] == "整"
            ? (o = 0)
            : ((o = parseInt(t[V])), isNaN(o) && (o = ee(t[V])))
        : a > 100 && ((o = a % 100), (a = Math.floor(a / 100))),
      o >= 60 || a > 24)
    )
      return null;
    if ((a >= 12 && (u = 1), t[Je])) {
      if (a > 12) return null;
      const l = t[Je][0].toLowerCase();
      (l == "a" && ((u = 0), a == 12 && (a = 0)),
        l == "p" && ((u = 1), a != 12 && (a += 12)),
        r.start.isCertain("meridiem") ||
          (u == 0
            ? (r.start.imply("meridiem", 0),
              r.start.get("hour") == 12 && r.start.assign("hour", 0))
            : (r.start.imply("meridiem", 1),
              r.start.get("hour") != 12 &&
                r.start.assign("hour", r.start.get("hour") + 12))));
    } else if (t[Ve]) {
      const h = t[Ve][0];
      h == "早"
        ? ((u = 0), a == 12 && (a = 0))
        : h == "晚" && ((u = 1), a != 12 && (a += 12));
    } else if (t[qe]) {
      const h = t[qe][0];
      h == "上" || h == "早" || h == "凌"
        ? ((u = 0), a == 12 && (a = 0))
        : (h == "下" || h == "晚") && ((u = 1), a != 12 && (a += 12));
    } else if (t[Ze]) {
      const h = t[Ze][0];
      h == "上" || h == "早" || h == "凌"
        ? ((u = 0), a == 12 && (a = 0))
        : (h == "下" || h == "晚") && ((u = 1), a != 12 && (a += 12));
    }
    return (
      (r.text = r.text + t[0]),
      r.end.assign("hour", a),
      r.end.assign("minute", o),
      u >= 0
        ? r.end.assign("meridiem", u)
        : r.start.isCertain("meridiem") &&
            r.start.get("meridiem") == 1 &&
            r.start.get("hour") > a
          ? r.end.imply("meridiem", 0)
          : a > 12 && r.end.imply("meridiem", 1),
      r.end.date().getTime() < r.start.date().getTime() &&
        r.end.imply("day", r.end.get("day") + 1),
      r
    );
  }
}
const qd = new RegExp(
  "(?:星期|礼拜|周)(?<weekday>" + Object.keys(Mt).join("|") + ")",
);
class si extends g {
  innerPattern() {
    return qd;
  }
  innerExtract(e, t) {
    const n = e.createParsingResult(t.index, t[0]),
      r = t.groups.weekday,
      i = Mt[r];
    if (i === void 0) return null;
    let a = E(e.refDate);
    const o = a.day();
    return (
      Math.abs(i - 7 - o) < Math.abs(i - o)
        ? (a = a.day(i - 7))
        : Math.abs(i + 7 - o) < Math.abs(i - o)
          ? (a = a.day(i + 7))
          : (a = a.day(i)),
      n.start.assign("weekday", i),
      n.start.imply("day", a.date()),
      n.start.imply("month", a.month() + 1),
      n.start.imply("year", a.year()),
      n
    );
  }
}
const Kd = 1,
  Gr = 2,
  Zd = 3,
  Lr = 4,
  jr = 5,
  Xd = 6;
class ii extends g {
  innerPattern(e) {
    return new RegExp(
      "(而家|立(?:刻|即)|即刻)|(今|明|前|大前|後|大後|聽|昨|尋|琴)(早|朝|晚)|(上(?:午|晝)|朝(?:早)|早(?:上)|下(?:午|晝)|晏(?:晝)|晚(?:上)|夜(?:晚)?|中(?:午)|凌(?:晨))|(今|明|前|大前|後|大後|聽|昨|尋|琴)(?:日|天)(?:[\\s|,|，]*)(?:(上(?:午|晝)|朝(?:早)|早(?:上)|下(?:午|晝)|晏(?:晝)|晚(?:上)|夜(?:晚)?|中(?:午)|凌(?:晨)))?",
      "i",
    );
  }
  innerExtract(e, t) {
    const n = t.index,
      r = e.createParsingResult(n, t[0]),
      i = E(e.refDate);
    let a = i;
    if (t[Kd])
      (r.start.imply("hour", i.hour()),
        r.start.imply("minute", i.minute()),
        r.start.imply("second", i.second()),
        r.start.imply("millisecond", i.millisecond()));
    else if (t[Gr]) {
      const o = t[Gr],
        u = t[Zd];
      (o == "明" || o == "聽"
        ? i.hour() > 1 && (a = a.add(1, "day"))
        : o == "昨" || o == "尋" || o == "琴"
          ? (a = a.add(-1, "day"))
          : o == "前"
            ? (a = a.add(-2, "day"))
            : o == "大前"
              ? (a = a.add(-3, "day"))
              : o == "後"
                ? (a = a.add(2, "day"))
                : o == "大後" && (a = a.add(3, "day")),
        u == "早" || u == "朝"
          ? r.start.imply("hour", 6)
          : u == "晚" &&
            (r.start.imply("hour", 22), r.start.imply("meridiem", 1)));
    } else if (t[Lr]) {
      const u = t[Lr][0];
      u == "早" || u == "朝" || u == "上"
        ? r.start.imply("hour", 6)
        : u == "下" || u == "晏"
          ? (r.start.imply("hour", 15), r.start.imply("meridiem", 1))
          : u == "中"
            ? (r.start.imply("hour", 12), r.start.imply("meridiem", 1))
            : u == "夜" || u == "晚"
              ? (r.start.imply("hour", 22), r.start.imply("meridiem", 1))
              : u == "凌" && r.start.imply("hour", 0);
    } else if (t[jr]) {
      const o = t[jr];
      o == "明" || o == "聽"
        ? i.hour() > 1 && (a = a.add(1, "day"))
        : o == "昨" || o == "尋" || o == "琴"
          ? (a = a.add(-1, "day"))
          : o == "前"
            ? (a = a.add(-2, "day"))
            : o == "大前"
              ? (a = a.add(-3, "day"))
              : o == "後"
                ? (a = a.add(2, "day"))
                : o == "大後" && (a = a.add(3, "day"));
      const u = t[Xd];
      if (u) {
        const d = u[0];
        d == "早" || d == "朝" || d == "上"
          ? r.start.imply("hour", 6)
          : d == "下" || d == "晏"
            ? (r.start.imply("hour", 15), r.start.imply("meridiem", 1))
            : d == "中"
              ? (r.start.imply("hour", 12), r.start.imply("meridiem", 1))
              : d == "夜" || d == "晚"
                ? (r.start.imply("hour", 22), r.start.imply("meridiem", 1))
                : d == "凌" && r.start.imply("hour", 0);
      }
    }
    return (
      r.start.assign("day", a.date()),
      r.start.assign("month", a.month() + 1),
      r.start.assign("year", a.year()),
      r
    );
  }
}
const F = {
    零: 0,
    一: 1,
    二: 2,
    兩: 2,
    三: 3,
    四: 4,
    五: 5,
    六: 6,
    七: 7,
    八: 8,
    九: 9,
    十: 10,
    廿: 20,
    卅: 30,
  },
  At = { 天: 0, 日: 0, 一: 1, 二: 2, 三: 3, 四: 4, 五: 5, 六: 6 };
function te(s) {
  let e = 0;
  for (let t = 0; t < s.length; t++) {
    const n = s[t];
    n === "十" ? (e = e === 0 ? F[n] : e * F[n]) : (e += F[n]);
  }
  return e;
}
function Jd(s) {
  let e = "";
  for (let t = 0; t < s.length; t++) {
    const n = s[t];
    e = e + F[n];
  }
  return parseInt(e);
}
const Ft = 1,
  Yr = 2,
  Gt = 3;
class ai extends g {
  innerPattern() {
    return new RegExp(
      "(\\d{2,4}|[" +
        Object.keys(F).join("") +
        "]{4}|[" +
        Object.keys(F).join("") +
        "]{2})?(?:\\s*)(?:年)?(?:[\\s|,|，]*)(\\d{1,2}|[" +
        Object.keys(F).join("") +
        "]{1,2})(?:\\s*)(?:月)(?:\\s*)(\\d{1,2}|[" +
        Object.keys(F).join("") +
        "]{1,2})?(?:\\s*)(?:日|號)?",
    );
  }
  innerExtract(e, t) {
    const n = E(e.refDate),
      r = e.createParsingResult(t.index, t[0]);
    let i = parseInt(t[Yr]);
    if ((isNaN(i) && (i = te(t[Yr])), r.start.assign("month", i), t[Gt])) {
      let a = parseInt(t[Gt]);
      (isNaN(a) && (a = te(t[Gt])), r.start.assign("day", a));
    } else r.start.imply("day", n.date());
    if (t[Ft]) {
      let a = parseInt(t[Ft]);
      (isNaN(a) && (a = Jd(t[Ft])), r.start.assign("year", a));
    } else r.start.imply("year", n.year());
    return r;
  }
}
const Qd = new RegExp(
    "(\\d+|[" +
      Object.keys(F).join("") +
      "]+|半|幾)(?:\\s*)(?:個)?(秒(?:鐘)?|分鐘|小時|鐘|日|天|星期|禮拜|月|年)(?:(?:之|過)?後|(?:之)?內)",
    "i",
  ),
  Lt = 1,
  el = 2;
class oi extends g {
  innerPattern() {
    return Qd;
  }
  innerExtract(e, t) {
    const n = e.createParsingResult(t.index, t[0]);
    let r = parseInt(t[Lt]);
    if ((isNaN(r) && (r = te(t[Lt])), isNaN(r))) {
      const u = t[Lt];
      if (u === "幾") r = 3;
      else if (u === "半") r = 0.5;
      else return null;
    }
    let i = E(e.refDate);
    const o = t[el][0];
    return o.match(/[日天星禮月年]/)
      ? (o == "日" || o == "天"
          ? (i = i.add(r, "d"))
          : o == "星" || o == "禮"
            ? (i = i.add(r * 7, "d"))
            : o == "月"
              ? (i = i.add(r, "month"))
              : o == "年" && (i = i.add(r, "year")),
        n.start.assign("year", i.year()),
        n.start.assign("month", i.month() + 1),
        n.start.assign("day", i.date()),
        n)
      : (o == "秒"
          ? (i = i.add(r, "second"))
          : o == "分"
            ? (i = i.add(r, "minute"))
            : (o == "小" || o == "鐘") && (i = i.add(r, "hour")),
        n.start.imply("year", i.year()),
        n.start.imply("month", i.month() + 1),
        n.start.imply("day", i.date()),
        n.start.assign("hour", i.hour()),
        n.start.assign("minute", i.minute()),
        n.start.assign("second", i.second()),
        n);
  }
}
const tl = new RegExp(
  "(?<prefix>上|今|下|這|呢)(?:個)?(?:星期|禮拜|週)(?<weekday>" +
    Object.keys(At).join("|") +
    ")",
);
class ui extends g {
  innerPattern() {
    return tl;
  }
  innerExtract(e, t) {
    const n = e.createParsingResult(t.index, t[0]),
      r = t.groups.weekday,
      i = At[r];
    if (i === void 0) return null;
    let a = null;
    const o = t.groups.prefix;
    o == "上"
      ? (a = "last")
      : o == "下"
        ? (a = "next")
        : (o == "今" || o == "這" || o == "呢") && (a = "this");
    let u = E(e.refDate),
      d = !1;
    const l = u.day();
    return (
      a == "last" || a == "past"
        ? ((u = u.day(i - 7)), (d = !0))
        : a == "next"
          ? ((u = u.day(i + 7)), (d = !0))
          : a == "this"
            ? (u = u.day(i))
            : Math.abs(i - 7 - l) < Math.abs(i - l)
              ? (u = u.day(i - 7))
              : Math.abs(i + 7 - l) < Math.abs(i - l)
                ? (u = u.day(i + 7))
                : (u = u.day(i)),
      n.start.assign("weekday", i),
      d
        ? (n.start.assign("day", u.date()),
          n.start.assign("month", u.month() + 1),
          n.start.assign("year", u.year()))
        : (n.start.imply("day", u.date()),
          n.start.imply("month", u.month() + 1),
          n.start.imply("year", u.year())),
      n
    );
  }
}
const nl = new RegExp(
    "(?:由|從|自)?(?:(今|明|前|大前|後|大後|聽|昨|尋|琴)(早|朝|晚)|(上(?:午|晝)|朝(?:早)|早(?:上)|下(?:午|晝)|晏(?:晝)|晚(?:上)|夜(?:晚)?|中(?:午)|凌(?:晨))|(今|明|前|大前|後|大後|聽|昨|尋|琴)(?:日|天)(?:[\\s,，]*)(?:(上(?:午|晝)|朝(?:早)|早(?:上)|下(?:午|晝)|晏(?:晝)|晚(?:上)|夜(?:晚)?|中(?:午)|凌(?:晨)))?)?(?:[\\s,，]*)(?:(\\d+|[" +
      Object.keys(F).join("") +
      "]+)(?:\\s*)(?:點|時|:|：)(?:\\s*)(\\d+|半|正|整|[" +
      Object.keys(F).join("") +
      "]+)?(?:\\s*)(?:分|:|：)?(?:\\s*)(\\d+|[" +
      Object.keys(F).join("") +
      "]+)?(?:\\s*)(?:秒)?)(?:\\s*(A.M.|P.M.|AM?|PM?))?",
    "i",
  ),
  rl = new RegExp(
    "(?:^\\s*(?:到|至|\\-|\\–|\\~|\\〜)\\s*)(?:(今|明|前|大前|後|大後|聽|昨|尋|琴)(早|朝|晚)|(上(?:午|晝)|朝(?:早)|早(?:上)|下(?:午|晝)|晏(?:晝)|晚(?:上)|夜(?:晚)?|中(?:午)|凌(?:晨))|(今|明|前|大前|後|大後|聽|昨|尋|琴)(?:日|天)(?:[\\s,，]*)(?:(上(?:午|晝)|朝(?:早)|早(?:上)|下(?:午|晝)|晏(?:晝)|晚(?:上)|夜(?:晚)?|中(?:午)|凌(?:晨)))?)?(?:[\\s,，]*)(?:(\\d+|[" +
      Object.keys(F).join("") +
      "]+)(?:\\s*)(?:點|時|:|：)(?:\\s*)(\\d+|半|正|整|[" +
      Object.keys(F).join("") +
      "]+)?(?:\\s*)(?:分|:|：)?(?:\\s*)(\\d+|[" +
      Object.keys(F).join("") +
      "]+)?(?:\\s*)(?:秒)?)(?:\\s*(A.M.|P.M.|AM?|PM?))?",
    "i",
  ),
  Qe = 1,
  et = 2,
  tt = 3,
  nt = 4,
  rt = 5,
  st = 6,
  q = 7,
  $e = 8,
  it = 9;
class di extends g {
  innerPattern() {
    return nl;
  }
  innerExtract(e, t) {
    if (t.index > 0 && e.text[t.index - 1].match(/\w/)) return null;
    const n = E(e.refDate),
      r = e.createParsingResult(t.index, t[0]);
    let i = n.clone();
    if (t[Qe]) {
      var a = t[Qe];
      (a == "明" || a == "聽"
        ? n.hour() > 1 && (i = i.add(1, "day"))
        : a == "昨" || a == "尋" || a == "琴"
          ? (i = i.add(-1, "day"))
          : a == "前"
            ? (i = i.add(-2, "day"))
            : a == "大前"
              ? (i = i.add(-3, "day"))
              : a == "後"
                ? (i = i.add(2, "day"))
                : a == "大後" && (i = i.add(3, "day")),
        r.start.assign("day", i.date()),
        r.start.assign("month", i.month() + 1),
        r.start.assign("year", i.year()));
    } else if (t[nt]) {
      var o = t[nt];
      (o == "明" || o == "聽"
        ? (i = i.add(1, "day"))
        : o == "昨" || o == "尋" || o == "琴"
          ? (i = i.add(-1, "day"))
          : o == "前"
            ? (i = i.add(-2, "day"))
            : o == "大前"
              ? (i = i.add(-3, "day"))
              : o == "後"
                ? (i = i.add(2, "day"))
                : o == "大後" && (i = i.add(3, "day")),
        r.start.assign("day", i.date()),
        r.start.assign("month", i.month() + 1),
        r.start.assign("year", i.year()));
    } else
      (r.start.imply("day", i.date()),
        r.start.imply("month", i.month() + 1),
        r.start.imply("year", i.year()));
    let u = 0,
      d = 0,
      l = -1;
    if (t[$e]) {
      var h = parseInt(t[$e]);
      if ((isNaN(h) && (h = te(t[$e])), h >= 60)) return null;
      r.start.assign("second", h);
    }
    if (
      ((u = parseInt(t[st])),
      isNaN(u) && (u = te(t[st])),
      t[q]
        ? t[q] == "半"
          ? (d = 30)
          : t[q] == "正" || t[q] == "整"
            ? (d = 0)
            : ((d = parseInt(t[q])), isNaN(d) && (d = te(t[q])))
        : u > 100 && ((d = u % 100), (u = Math.floor(u / 100))),
      d >= 60 || u > 24)
    )
      return null;
    if ((u >= 12 && (l = 1), t[it])) {
      if (u > 12) return null;
      var z = t[it][0].toLowerCase();
      (z == "a" && ((l = 0), u == 12 && (u = 0)),
        z == "p" && ((l = 1), u != 12 && (u += 12)));
    } else if (t[et]) {
      var k = t[et],
        j = k[0];
      j == "朝" || j == "早"
        ? ((l = 0), u == 12 && (u = 0))
        : j == "晚" && ((l = 1), u != 12 && (u += 12));
    } else if (t[tt]) {
      var Te = t[tt],
        b = Te[0];
      b == "上" || b == "朝" || b == "早" || b == "凌"
        ? ((l = 0), u == 12 && (u = 0))
        : (b == "下" || b == "晏" || b == "晚") &&
          ((l = 1), u != 12 && (u += 12));
    } else if (t[rt]) {
      var Ce = t[rt],
        S = Ce[0];
      S == "上" || S == "朝" || S == "早" || S == "凌"
        ? ((l = 0), u == 12 && (u = 0))
        : (S == "下" || S == "晏" || S == "晚") &&
          ((l = 1), u != 12 && (u += 12));
    }
    if (
      (r.start.assign("hour", u),
      r.start.assign("minute", d),
      l >= 0
        ? r.start.assign("meridiem", l)
        : u < 12
          ? r.start.imply("meridiem", 0)
          : r.start.imply("meridiem", 1),
      (t = rl.exec(e.text.substring(r.index + r.text.length))),
      !t)
    )
      return r.text.match(/^\d+$/) ? null : r;
    let x = i.clone();
    if (((r.end = e.createParsingComponents()), t[Qe])) {
      var a = t[Qe];
      (a == "明" || a == "聽"
        ? n.hour() > 1 && (x = x.add(1, "day"))
        : a == "昨" || a == "尋" || a == "琴"
          ? (x = x.add(-1, "day"))
          : a == "前"
            ? (x = x.add(-2, "day"))
            : a == "大前"
              ? (x = x.add(-3, "day"))
              : a == "後"
                ? (x = x.add(2, "day"))
                : a == "大後" && (x = x.add(3, "day")),
        r.end.assign("day", x.date()),
        r.end.assign("month", x.month() + 1),
        r.end.assign("year", x.year()));
    } else if (t[nt]) {
      var o = t[nt];
      (o == "明" || o == "聽"
        ? (x = x.add(1, "day"))
        : o == "昨" || o == "尋" || o == "琴"
          ? (x = x.add(-1, "day"))
          : o == "前"
            ? (x = x.add(-2, "day"))
            : o == "大前"
              ? (x = x.add(-3, "day"))
              : o == "後"
                ? (x = x.add(2, "day"))
                : o == "大後" && (x = x.add(3, "day")),
        r.end.assign("day", x.date()),
        r.end.assign("month", x.month() + 1),
        r.end.assign("year", x.year()));
    } else
      (r.end.imply("day", x.date()),
        r.end.imply("month", x.month() + 1),
        r.end.imply("year", x.year()));
    if (((u = 0), (d = 0), (l = -1), t[$e])) {
      var h = parseInt(t[$e]);
      if ((isNaN(h) && (h = te(t[$e])), h >= 60)) return null;
      r.end.assign("second", h);
    }
    if (
      ((u = parseInt(t[st])),
      isNaN(u) && (u = te(t[st])),
      t[q]
        ? t[q] == "半"
          ? (d = 30)
          : t[q] == "正" || t[q] == "整"
            ? (d = 0)
            : ((d = parseInt(t[q])), isNaN(d) && (d = te(t[q])))
        : u > 100 && ((d = u % 100), (u = Math.floor(u / 100))),
      d >= 60 || u > 24)
    )
      return null;
    if ((u >= 12 && (l = 1), t[it])) {
      if (u > 12) return null;
      var z = t[it][0].toLowerCase();
      (z == "a" && ((l = 0), u == 12 && (u = 0)),
        z == "p" && ((l = 1), u != 12 && (u += 12)),
        r.start.isCertain("meridiem") ||
          (l == 0
            ? (r.start.imply("meridiem", 0),
              r.start.get("hour") == 12 && r.start.assign("hour", 0))
            : (r.start.imply("meridiem", 1),
              r.start.get("hour") != 12 &&
                r.start.assign("hour", r.start.get("hour") + 12))));
    } else if (t[et]) {
      var k = t[et],
        j = k[0];
      j == "朝" || j == "早"
        ? ((l = 0), u == 12 && (u = 0))
        : j == "晚" && ((l = 1), u != 12 && (u += 12));
    } else if (t[tt]) {
      var Te = t[tt],
        b = Te[0];
      b == "上" || b == "朝" || b == "早" || b == "凌"
        ? ((l = 0), u == 12 && (u = 0))
        : (b == "下" || b == "晏" || b == "晚") &&
          ((l = 1), u != 12 && (u += 12));
    } else if (t[rt]) {
      var Ce = t[rt],
        S = Ce[0];
      S == "上" || S == "朝" || S == "早" || S == "凌"
        ? ((l = 0), u == 12 && (u = 0))
        : (S == "下" || S == "晏" || S == "晚") &&
          ((l = 1), u != 12 && (u += 12));
    }
    return (
      (r.text = r.text + t[0]),
      r.end.assign("hour", u),
      r.end.assign("minute", d),
      l >= 0
        ? r.end.assign("meridiem", l)
        : r.start.isCertain("meridiem") &&
            r.start.get("meridiem") == 1 &&
            r.start.get("hour") > u
          ? r.end.imply("meridiem", 0)
          : u > 12 && r.end.imply("meridiem", 1),
      r.end.date().getTime() < r.start.date().getTime() &&
        r.end.imply("day", r.end.get("day") + 1),
      r
    );
  }
}
const sl = new RegExp(
  "(?:星期|禮拜|週)(?<weekday>" + Object.keys(At).join("|") + ")",
);
class li extends g {
  innerPattern() {
    return sl;
  }
  innerExtract(e, t) {
    const n = e.createParsingResult(t.index, t[0]),
      r = t.groups.weekday,
      i = At[r];
    if (i === void 0) return null;
    let a = E(e.refDate);
    const o = a.day();
    return (
      Math.abs(i - 7 - o) < Math.abs(i - o)
        ? (a = a.day(i - 7))
        : Math.abs(i + 7 - o) < Math.abs(i - o)
          ? (a = a.day(i + 7))
          : (a = a.day(i)),
      n.start.assign("weekday", i),
      n.start.imply("day", a.date()),
      n.start.imply("month", a.month() + 1),
      n.start.imply("year", a.year()),
      n
    );
  }
}
class fi extends Z {
  patternBetween() {
    return /^\s*(至|到|\-|\~|～|－|ー)\s*$/i;
  }
}
class ci extends Q {
  patternBetween() {
    return /^\s*$/i;
  }
}
const il = new $(Rn()),
  Pn = new $(Rn()),
  al = new $(En());
function ol(s, e, t) {
  return Pn.parse(s, e, t);
}
function ul(s, e, t) {
  return Pn.parseDate(s, e, t);
}
function Rn() {
  const s = En();
  return (s.parsers.unshift(new ii()), s);
}
function En() {
  const s = X({
    parsers: [new ai(), new ui(), new li(), new di(), new oi()],
    refiners: [new fi(), new ci()],
  });
  return ((s.refiners = s.refiners.filter((e) => !(e instanceof $t))), s);
}
const dl = Object.freeze(
    Object.defineProperty(
      {
        __proto__: null,
        Chrono: $,
        get Meridiem() {
          return f;
        },
        ParsingComponents: p,
        ParsingResult: I,
        ReferenceWithTimezone: G,
        get Weekday() {
          return _;
        },
        casual: Pn,
        createCasualConfiguration: Rn,
        createConfiguration: En,
        hant: il,
        parse: ol,
        parseDate: ul,
        strict: al,
      },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  ),
  ll = 1,
  zr = 2,
  fl = 3,
  Hr = 4,
  Br = 5,
  cl = 6;
class ml extends g {
  innerPattern(e) {
    return new RegExp(
      "(现在|立(?:刻|即)|即刻)|(今|明|前|大前|后|大后|昨)(早|晚)|(上(?:午)|早(?:上)|下(?:午)|晚(?:上)|夜(?:晚)?|中(?:午)|凌(?:晨))|(今|明|前|大前|后|大后|昨)(?:日|天)(?:[\\s|,|，]*)(?:(上(?:午)|早(?:上)|下(?:午)|晚(?:上)|夜(?:晚)?|中(?:午)|凌(?:晨)))?",
      "i",
    );
  }
  innerExtract(e, t) {
    const n = t.index,
      r = e.createParsingResult(n, t[0]),
      i = E(e.refDate);
    let a = i;
    if (t[ll])
      (r.start.imply("hour", i.hour()),
        r.start.imply("minute", i.minute()),
        r.start.imply("second", i.second()),
        r.start.imply("millisecond", i.millisecond()));
    else if (t[zr]) {
      const o = t[zr],
        u = t[fl];
      (o == "明"
        ? i.hour() > 1 && (a = a.add(1, "day"))
        : o == "昨"
          ? (a = a.add(-1, "day"))
          : o == "前"
            ? (a = a.add(-2, "day"))
            : o == "大前"
              ? (a = a.add(-3, "day"))
              : o == "后"
                ? (a = a.add(2, "day"))
                : o == "大后" && (a = a.add(3, "day")),
        u == "早"
          ? r.start.imply("hour", 6)
          : u == "晚" &&
            (r.start.imply("hour", 22), r.start.imply("meridiem", 1)));
    } else if (t[Hr]) {
      const u = t[Hr][0];
      u == "早" || u == "上"
        ? r.start.imply("hour", 6)
        : u == "下"
          ? (r.start.imply("hour", 15), r.start.imply("meridiem", 1))
          : u == "中"
            ? (r.start.imply("hour", 12), r.start.imply("meridiem", 1))
            : u == "夜" || u == "晚"
              ? (r.start.imply("hour", 22), r.start.imply("meridiem", 1))
              : u == "凌" && r.start.imply("hour", 0);
    } else if (t[Br]) {
      const o = t[Br];
      o == "明"
        ? i.hour() > 1 && (a = a.add(1, "day"))
        : o == "昨"
          ? (a = a.add(-1, "day"))
          : o == "前"
            ? (a = a.add(-2, "day"))
            : o == "大前"
              ? (a = a.add(-3, "day"))
              : o == "后"
                ? (a = a.add(2, "day"))
                : o == "大后" && (a = a.add(3, "day"));
      const u = t[cl];
      if (u) {
        const d = u[0];
        d == "早" || d == "上"
          ? r.start.imply("hour", 6)
          : d == "下"
            ? (r.start.imply("hour", 15), r.start.imply("meridiem", 1))
            : d == "中"
              ? (r.start.imply("hour", 12), r.start.imply("meridiem", 1))
              : d == "夜" || d == "晚"
                ? (r.start.imply("hour", 22), r.start.imply("meridiem", 1))
                : d == "凌" && r.start.imply("hour", 0);
      }
    }
    return (
      r.start.assign("day", a.date()),
      r.start.assign("month", a.month() + 1),
      r.start.assign("year", a.year()),
      r
    );
  }
}
class gl extends Z {
  patternBetween() {
    return /^\s*(至|到|-|~|～|－|ー)\s*$/i;
  }
}
class yl extends Q {
  patternBetween() {
    return /^\s*$/i;
  }
}
const pl = new $(wn()),
  $n = new $(wn()),
  hl = new $(On());
function Tl(s, e, t) {
  return $n.parse(s, e, t);
}
function Pl(s, e, t) {
  return $n.parseDate(s, e, t);
}
function wn() {
  const s = On();
  return (s.parsers.unshift(new ml()), s);
}
function On() {
  const s = X({
    parsers: [new ei(), new ni(), new si(), new ri(), new ti()],
    refiners: [new gl(), new yl()],
  });
  return ((s.refiners = s.refiners.filter((e) => !(e instanceof $t))), s);
}
const Rl = Object.freeze(
    Object.defineProperty(
      {
        __proto__: null,
        Chrono: $,
        get Meridiem() {
          return f;
        },
        ParsingComponents: p,
        ParsingResult: I,
        ReferenceWithTimezone: G,
        get Weekday() {
          return _;
        },
        casual: $n,
        createCasualConfiguration: wn,
        createConfiguration: On,
        hans: pl,
        parse: Tl,
        parseDate: Pl,
        strict: hl,
      },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  ),
  xn = new $(mi()),
  El = new $(_n());
function $l(s, e, t) {
  return xn.parse(s, e, t);
}
function wl(s, e, t) {
  return xn.parseDate(s, e, t);
}
function mi() {
  const s = _n();
  return (s.parsers.unshift(new ii()), s);
}
function _n() {
  const s = X({
    parsers: [
      new ai(),
      new ei(),
      new ui(),
      new ni(),
      new li(),
      new si(),
      new di(),
      new ri(),
      new oi(),
      new ti(),
    ],
    refiners: [new fi(), new ci()],
  });
  return ((s.refiners = s.refiners.filter((e) => !(e instanceof $t))), s);
}
const Qf = Object.freeze(
    Object.defineProperty(
      {
        __proto__: null,
        Chrono: $,
        get Meridiem() {
          return f;
        },
        ParsingComponents: p,
        ParsingResult: I,
        ReferenceWithTimezone: G,
        get Weekday() {
          return _;
        },
        casual: xn,
        createCasualConfiguration: mi,
        createConfiguration: _n,
        hans: Rl,
        hant: dl,
        parse: $l,
        parseDate: wl,
        strict: El,
      },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  ),
  J = {
    leftBoundary: "([^\\p{L}\\p{N}_]|^)",
    rightBoundary: "(?=[^\\p{L}\\p{N}_]|$)",
    flags: "iu",
  },
  Vr = {
    воскресенье: 0,
    воскресенья: 0,
    вск: 0,
    "вск.": 0,
    понедельник: 1,
    понедельника: 1,
    пн: 1,
    "пн.": 1,
    вторник: 2,
    вторника: 2,
    вт: 2,
    "вт.": 2,
    среда: 3,
    среды: 3,
    среду: 3,
    ср: 3,
    "ср.": 3,
    четверг: 4,
    четверга: 4,
    чт: 4,
    "чт.": 4,
    пятница: 5,
    пятницу: 5,
    пятницы: 5,
    пт: 5,
    "пт.": 5,
    суббота: 6,
    субботу: 6,
    субботы: 6,
    сб: 6,
    "сб.": 6,
  },
  gi = {
    январь: 1,
    января: 1,
    январе: 1,
    февраль: 2,
    февраля: 2,
    феврале: 2,
    март: 3,
    марта: 3,
    марте: 3,
    апрель: 4,
    апреля: 4,
    апреле: 4,
    май: 5,
    мая: 5,
    мае: 5,
    июнь: 6,
    июня: 6,
    июне: 6,
    июль: 7,
    июля: 7,
    июле: 7,
    август: 8,
    августа: 8,
    августе: 8,
    сентябрь: 9,
    сентября: 9,
    сентябре: 9,
    октябрь: 10,
    октября: 10,
    октябре: 10,
    ноябрь: 11,
    ноября: 11,
    ноябре: 11,
    декабрь: 12,
    декабря: 12,
    декабре: 12,
  },
  pt = {
    ...gi,
    янв: 1,
    "янв.": 1,
    фев: 2,
    "фев.": 2,
    мар: 3,
    "мар.": 3,
    апр: 4,
    "апр.": 4,
    авг: 8,
    "авг.": 8,
    сен: 9,
    "сен.": 9,
    окт: 10,
    "окт.": 10,
    ноя: 11,
    "ноя.": 11,
    дек: 12,
    "дек.": 12,
  },
  Xt = {
    один: 1,
    одна: 1,
    одной: 1,
    одну: 1,
    две: 2,
    два: 2,
    двух: 2,
    три: 3,
    трех: 3,
    трёх: 3,
    четыре: 4,
    четырех: 4,
    четырёх: 4,
    пять: 5,
    пяти: 5,
    шесть: 6,
    шести: 6,
    семь: 7,
    семи: 7,
    восемь: 8,
    восьми: 8,
    девять: 9,
    девяти: 9,
    десять: 10,
    десяти: 10,
    одиннадцать: 11,
    одиннадцати: 11,
    двенадцать: 12,
    двенадцати: 12,
  },
  Jt = {
    первое: 1,
    первого: 1,
    второе: 2,
    второго: 2,
    третье: 3,
    третьего: 3,
    четвертое: 4,
    четвертого: 4,
    пятое: 5,
    пятого: 5,
    шестое: 6,
    шестого: 6,
    седьмое: 7,
    седьмого: 7,
    восьмое: 8,
    восьмого: 8,
    девятое: 9,
    девятого: 9,
    десятое: 10,
    десятого: 10,
    одиннадцатое: 11,
    одиннадцатого: 11,
    двенадцатое: 12,
    двенадцатого: 12,
    тринадцатое: 13,
    тринадцатого: 13,
    четырнадцатое: 14,
    четырнадцатого: 14,
    пятнадцатое: 15,
    пятнадцатого: 15,
    шестнадцатое: 16,
    шестнадцатого: 16,
    семнадцатое: 17,
    семнадцатого: 17,
    восемнадцатое: 18,
    восемнадцатого: 18,
    девятнадцатое: 19,
    девятнадцатого: 19,
    двадцатое: 20,
    двадцатого: 20,
    "двадцать первое": 21,
    "двадцать первого": 21,
    "двадцать второе": 22,
    "двадцать второго": 22,
    "двадцать третье": 23,
    "двадцать третьего": 23,
    "двадцать четвертое": 24,
    "двадцать четвертого": 24,
    "двадцать пятое": 25,
    "двадцать пятого": 25,
    "двадцать шестое": 26,
    "двадцать шестого": 26,
    "двадцать седьмое": 27,
    "двадцать седьмого": 27,
    "двадцать восьмое": 28,
    "двадцать восьмого": 28,
    "двадцать девятое": 29,
    "двадцать девятого": 29,
    тридцатое: 30,
    тридцатого: 30,
    "тридцать первое": 31,
    "тридцать первого": 31,
  },
  ht = {
    сек: "second",
    секунда: "second",
    секунд: "second",
    секунды: "second",
    секунду: "second",
    секундочка: "second",
    секундочки: "second",
    секундочек: "second",
    секундочку: "second",
    мин: "minute",
    минута: "minute",
    минут: "minute",
    минуты: "minute",
    минуту: "minute",
    минуток: "minute",
    минутки: "minute",
    минутку: "minute",
    минуточек: "minute",
    минуточки: "minute",
    минуточку: "minute",
    час: "hour",
    часов: "hour",
    часа: "hour",
    часу: "hour",
    часиков: "hour",
    часика: "hour",
    часике: "hour",
    часик: "hour",
    день: "d",
    дня: "d",
    дней: "d",
    суток: "d",
    сутки: "d",
    неделя: "week",
    неделе: "week",
    недели: "week",
    неделю: "week",
    недель: "week",
    недельке: "week",
    недельки: "week",
    неделек: "week",
    месяц: "month",
    месяце: "month",
    месяцев: "month",
    месяца: "month",
    квартал: "quarter",
    квартале: "quarter",
    кварталов: "quarter",
    год: "year",
    года: "year",
    году: "year",
    годов: "year",
    лет: "year",
    годик: "year",
    годика: "year",
    годиков: "year",
  },
  Ol = `(?:${P(Xt)}|[0-9]+|[0-9]+\\.[0-9]+|пол|несколько|пар(?:ы|у)|\\s{0,3})`;
function xl(s) {
  const e = s.toLowerCase();
  return Xt[e] !== void 0
    ? Xt[e]
    : e.match(/несколько/)
      ? 3
      : e.match(/пол/)
        ? 0.5
        : e.match(/пар/)
          ? 2
          : e === ""
            ? 1
            : parseFloat(e);
}
const qr = `(?:${P(Jt)}|[0-9]{1,2}(?:го|ого|е|ое)?)`;
function Kr(s) {
  const e = s.toLowerCase();
  return Jt[e] !== void 0 ? Jt[e] : parseInt(e);
}
const jt = "(?:\\s+(?:году|года|год|г|г.))?",
  yi = `(?:[1-9][0-9]{0,3}${jt}\\s*(?:н.э.|до н.э.|н. э.|до н. э.)|[1-2][0-9]{3}${jt}|[5-9][0-9]${jt})`;
function pi(s) {
  if (
    (/(год|года|г|г.)/i.test(s) && (s = s.replace(/(год|года|г|г.)/i, "")),
    /(до н.э.|до н. э.)/i.test(s))
  )
    return ((s = s.replace(/(до н.э.|до н. э.)/i, "")), -parseInt(s));
  if (/(н. э.|н.э.)/i.test(s))
    return ((s = s.replace(/(н. э.|н.э.)/i, "")), parseInt(s));
  const e = parseInt(s);
  return xe(e);
}
const hi = `(${Ol})\\s{0,3}(${P(ht)})`,
  Zr = new RegExp(hi, "i"),
  Nn = oe("(?:(?:около|примерно)\\s{0,3})?", hi);
function Mn(s) {
  const e = {};
  let t = s,
    n = Zr.exec(t);
  for (; n;)
    (_l(e, n), (t = t.substring(n[0].length).trim()), (n = Zr.exec(t)));
  return e;
}
function _l(s, e) {
  const t = xl(e[1]),
    n = ht[e[2].toLowerCase()];
  s[n] = t;
}
const Xr = `(?:(?:около|примерно)\\s*(?:~\\s*)?)?(${Nn})${J.rightBoundary}`;
class Nl extends g {
  patternLeftBoundary() {
    return J.leftBoundary;
  }
  innerPattern(e) {
    return e.option.forwardDate
      ? new RegExp(Xr, J.flags)
      : new RegExp(`(?:в течение|в течении)\\s*${Xr}`, J.flags);
  }
  innerExtract(e, t) {
    const n = Mn(t[1]);
    return p.createRelativeFromReference(e.reference, n);
  }
}
let An = class extends g {
    patternLeftBoundary() {
      return J.leftBoundary;
    }
    innerPattern(e) {
      return new RegExp(this.innerPatternString(e), J.flags);
    }
    innerPatternHasChange(e, t) {
      return !1;
    }
  },
  Ae = class extends An {
    innerPattern(e) {
      return new RegExp(
        `${this.innerPatternString(e)}${J.rightBoundary}`,
        J.flags,
      );
    }
  };
const Jr = 1,
  Qr = 2,
  Ml = 3,
  es = 4;
class Al extends Ae {
  innerPatternString(e) {
    return `(?:с)?\\s*(${qr})(?:\\s{0,3}(?:по|-|–|до)?\\s{0,3}(${qr}))?(?:-|\\/|\\s{0,3}(?:of)?\\s{0,3})(${P(pt)})(?:(?:-|\\/|,?\\s{0,3})(${yi}(?![^\\s]\\d)))?`;
  }
  innerExtract(e, t) {
    const n = e.createParsingResult(t.index, t[0]),
      r = pt[t[Ml].toLowerCase()],
      i = Kr(t[Jr]);
    if (i > 31) return ((t.index = t.index + t[Jr].length), null);
    if ((n.start.assign("month", r), n.start.assign("day", i), t[es])) {
      const a = pi(t[es]);
      n.start.assign("year", a);
    } else {
      const a = L(e.refDate, i, r);
      n.start.imply("year", a);
    }
    if (t[Qr]) {
      const a = Kr(t[Qr]);
      ((n.end = n.start.clone()), n.end.assign("day", a));
    }
    return n;
  }
}
const Dl = 2,
  ts = 3;
class Cl extends An {
  innerPatternString(e) {
    return `((?:в)\\s*)?(${P(pt)})\\s*(?:[,-]?\\s*(${yi})?)?(?=[^\\s\\w]|\\s+[^0-9]|\\s+$|$)`;
  }
  innerExtract(e, t) {
    const n = t[Dl].toLowerCase();
    if (t[0].length <= 3 && !gi[n]) return null;
    const r = e.createParsingResult(t.index, t.index + t[0].length);
    r.start.imply("day", 1);
    const i = pt[n];
    if ((r.start.assign("month", i), t[ts])) {
      const a = pi(t[ts]);
      r.start.assign("year", a);
    } else {
      const a = L(e.refDate, 1, i);
      r.start.imply("year", a);
    }
    return r;
  }
}
class Ul extends de {
  constructor(e) {
    super(e);
  }
  patternFlags() {
    return J.flags;
  }
  primaryPatternLeftBoundary() {
    return "(^|\\s|T|(?:[^\\p{L}\\p{N}_]))";
  }
  followingPhase() {
    return "\\s*(?:\\-|\\–|\\~|\\〜|до|и|по|\\?)\\s*";
  }
  primaryPrefix() {
    return "(?:(?:в|с)\\s*)??";
  }
  primarySuffix() {
    return `(?:\\s*(?:утра|вечера|после полудня))?(?!\\/)${J.rightBoundary}`;
  }
  extractPrimaryTimeComponents(e, t) {
    const n = super.extractPrimaryTimeComponents(e, t);
    if (n) {
      if (t[0].endsWith("вечера")) {
        const r = n.get("hour");
        r >= 6 && r < 12
          ? (n.assign("hour", n.get("hour") + 12), n.assign("meridiem", f.PM))
          : r < 6 && n.assign("meridiem", f.AM);
      }
      if (t[0].endsWith("после полудня")) {
        n.assign("meridiem", f.PM);
        const r = n.get("hour");
        r >= 0 && r <= 6 && n.assign("hour", n.get("hour") + 12);
      }
      t[0].endsWith("утра") &&
        (n.assign("meridiem", f.AM),
        n.get("hour") < 12 && n.assign("hour", n.get("hour")));
    }
    return n;
  }
}
class Il extends An {
  innerPatternString(e) {
    return `(${Nn})\\s{0,5}назад(?=(?:\\W|$))`;
  }
  innerExtract(e, t) {
    const n = Mn(t[1]),
      r = H(n);
    return p.createRelativeFromReference(e.reference, r);
  }
}
class bl extends Z {
  patternBetween() {
    return /^\s*(и до|и по|до|по|-)\s*$/i;
  }
}
class Sl extends Q {
  patternBetween() {
    return new RegExp("^\\s*(T|в|,|-)?\\s*$");
  }
}
class vl extends Ae {
  innerPatternString(e) {
    return "(?:с|со)?\\s*(сегодня|вчера|завтра|послезавтра|послепослезавтра|позапозавчера|позавчера)";
  }
  innerExtract(e, t) {
    const n = t[1].toLowerCase(),
      r = e.createParsingComponents();
    switch (n) {
      case "сегодня":
        return re(e.reference);
      case "вчера":
        return fe(e.reference);
      case "завтра":
        return ce(e.reference);
      case "послезавтра":
        return Oe(e.reference, 2);
      case "послепослезавтра":
        return Oe(e.reference, 3);
      case "позавчера":
        return ke(e.reference, 2);
      case "позапозавчера":
        return ke(e.reference, 3);
    }
    return r;
  }
}
class kl extends Ae {
  innerPatternString(e) {
    return "(сейчас|прошлым\\s*вечером|прошлой\\s*ночью|следующей\\s*ночью|сегодня\\s*ночью|этой\\s*ночью|ночью|этим утром|утром|утра|в\\s*полдень|вечером|вечера|в\\s*полночь)";
  }
  innerExtract(e, t) {
    let n = E(e.refDate);
    const r = t[0].toLowerCase(),
      i = e.createParsingComponents();
    if (r === "сейчас") return le(e.reference);
    if (r === "вечером" || r === "вечера") return an(e.reference);
    if (r.endsWith("утром") || r.endsWith("утра")) return on(e.reference);
    if (r.match(/в\s*полдень/)) return un(e.reference);
    if (r.match(/прошлой\s*ночью/)) return xs(e.reference);
    if (r.match(/прошлым\s*вечером/)) return _s(e.reference);
    if (r.match(/следующей\s*ночью/)) {
      const a = n.hour() < 22 ? 1 : 2;
      ((n = n.add(a, "day")), D(i, n), i.imply("hour", 0));
    }
    return r.match(/в\s*полночь/) || r.endsWith("ночью") ? ft(e.reference) : i;
  }
}
const Wl = 1,
  Fl = 2,
  Gl = 3;
class Ll extends Ae {
  innerPatternString(e) {
    return `(?:(?:,|\\(|（)\\s*)?(?:в\\s*?)?(?:(эту|этот|прошлый|прошлую|следующий|следующую|следующего)\\s*)?(${P(Vr)})(?:\\s*(?:,|\\)|）))?(?:\\s*на\\s*(этой|прошлой|следующей)\\s*неделе)?`;
  }
  innerExtract(e, t) {
    const n = t[Fl].toLowerCase(),
      r = Vr[n],
      i = t[Wl],
      a = t[Gl];
    let o = i || a;
    ((o = o || ""), (o = o.toLowerCase()));
    let u = null;
    return (
      o == "прошлый" || o == "прошлую" || o == "прошлой"
        ? (u = "last")
        : o == "следующий" ||
            o == "следующую" ||
            o == "следующей" ||
            o == "следующего"
          ? (u = "next")
          : (o == "этот" || o == "эту" || o == "этой") && (u = "this"),
      me(e.reference, r, u)
    );
  }
}
const jl = 1,
  Yl = 2;
class zl extends Ae {
  innerPatternString(e) {
    return `(в прошлом|на прошлой|на следующей|в следующем|на этой|в этом)\\s*(${P(ht)})`;
  }
  innerExtract(e, t) {
    const n = t[jl].toLowerCase(),
      r = t[Yl].toLowerCase(),
      i = ht[r];
    if (n == "на следующей" || n == "в следующем") {
      const u = {};
      return ((u[i] = 1), p.createRelativeFromReference(e.reference, u));
    }
    if (n == "в прошлом" || n == "на прошлой") {
      const u = {};
      return ((u[i] = -1), p.createRelativeFromReference(e.reference, u));
    }
    const a = e.createParsingComponents();
    let o = E(e.reference.instant);
    return (
      i.match(/week/i)
        ? ((o = o.add(-o.get("d"), "d")),
          a.imply("day", o.date()),
          a.imply("month", o.month() + 1),
          a.imply("year", o.year()))
        : i.match(/month/i)
          ? ((o = o.add(-o.date() + 1, "d")),
            a.imply("day", o.date()),
            a.assign("year", o.year()),
            a.assign("month", o.month() + 1))
          : i.match(/year/i) &&
            ((o = o.add(-o.date() + 1, "d")),
            (o = o.add(-o.month(), "month")),
            a.imply("day", o.date()),
            a.imply("month", o.month() + 1),
            a.assign("year", o.year())),
      a
    );
  }
}
class Hl extends Ae {
  innerPatternString(e) {
    return `(эти|последние|прошлые|следующие|после|спустя|через|\\+|-)\\s*(${Nn})`;
  }
  innerExtract(e, t) {
    const n = t[1].toLowerCase();
    let r = Mn(t[2]);
    switch (n) {
      case "последние":
      case "прошлые":
      case "-":
        r = H(r);
        break;
    }
    return p.createRelativeFromReference(e.reference, r);
  }
}
const Dn = new $(Ti()),
  Bl = new $(Cn(!0));
function Vl(s, e, t) {
  return Dn.parse(s, e, t);
}
function ql(s, e, t) {
  return Dn.parseDate(s, e, t);
}
function Ti() {
  const s = Cn(!1);
  return (
    s.parsers.unshift(new vl()),
    s.parsers.unshift(new kl()),
    s.parsers.unshift(new Cl()),
    s.parsers.unshift(new zl()),
    s.parsers.unshift(new Hl()),
    s
  );
}
function Cn(s = !0) {
  return X(
    {
      parsers: [new ge(!0), new Nl(), new Al(), new Ll(), new Ul(s), new Il()],
      refiners: [new Sl(), new bl()],
    },
    s,
  );
}
const nc = Object.freeze(
    Object.defineProperty(
      {
        __proto__: null,
        Chrono: $,
        get Meridiem() {
          return f;
        },
        ParsingComponents: p,
        ParsingResult: I,
        ReferenceWithTimezone: G,
        get Weekday() {
          return _;
        },
        casual: Dn,
        createCasualConfiguration: Ti,
        createConfiguration: Cn,
        parse: Vl,
        parseDate: ql,
        strict: Bl,
      },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  ),
  Pi = {
    domingo: 0,
    dom: 0,
    lunes: 1,
    lun: 1,
    martes: 2,
    mar: 2,
    miércoles: 3,
    miercoles: 3,
    mié: 3,
    mie: 3,
    jueves: 4,
    jue: 4,
    viernes: 5,
    vie: 5,
    sábado: 6,
    sabado: 6,
    sáb: 6,
    sab: 6,
  },
  Ri = {
    enero: 1,
    ene: 1,
    "ene.": 1,
    febrero: 2,
    feb: 2,
    "feb.": 2,
    marzo: 3,
    mar: 3,
    "mar.": 3,
    abril: 4,
    abr: 4,
    "abr.": 4,
    mayo: 5,
    may: 5,
    "may.": 5,
    junio: 6,
    jun: 6,
    "jun.": 6,
    julio: 7,
    jul: 7,
    "jul.": 7,
    agosto: 8,
    ago: 8,
    "ago.": 8,
    septiembre: 9,
    setiembre: 9,
    sep: 9,
    "sep.": 9,
    octubre: 10,
    oct: 10,
    "oct.": 10,
    noviembre: 11,
    nov: 11,
    "nov.": 11,
    diciembre: 12,
    dic: 12,
    "dic.": 12,
  },
  Qt = {
    uno: 1,
    dos: 2,
    tres: 3,
    cuatro: 4,
    cinco: 5,
    seis: 6,
    siete: 7,
    ocho: 8,
    nueve: 9,
    diez: 10,
    once: 11,
    doce: 12,
    trece: 13,
  },
  Ei = {
    sec: "second",
    segundo: "second",
    segundos: "second",
    min: "minute",
    mins: "minute",
    minuto: "minute",
    minutos: "minute",
    h: "hour",
    hr: "hour",
    hrs: "hour",
    hora: "hour",
    horas: "hour",
    día: "d",
    días: "d",
    semana: "week",
    semanas: "week",
    mes: "month",
    meses: "month",
    cuarto: "quarter",
    cuartos: "quarter",
    año: "year",
    años: "year",
  },
  Kl = `(?:${P(Qt)}|[0-9]+|[0-9]+\\.[0-9]+|un?|uno?|una?|algunos?|unos?|demi-?)`;
function Zl(s) {
  const e = s.toLowerCase();
  return Qt[e] !== void 0
    ? Qt[e]
    : e === "un" || e === "una" || e === "uno"
      ? 1
      : e.match(/algunos?/) || e.match(/unos?/)
        ? 3
        : e.match(/media?/)
          ? 0.5
          : parseFloat(e);
}
const Xl =
  "[0-9]{1,4}(?![^\\s]\\d)(?:\\s*[a|d]\\.?\\s*c\\.?|\\s*a\\.?\\s*d\\.?)?";
function Jl(s) {
  if (s.match(/^[0-9]{1,4}$/)) {
    let e = parseInt(s);
    return (e < 100 && (e > 50 ? (e = e + 1900) : (e = e + 2e3)), e);
  }
  return s.match(/a\.?\s*c\.?/i)
    ? ((s = s.replace(/a\.?\s*c\.?/i, "")), -parseInt(s))
    : parseInt(s);
}
const $i = `(${Kl})\\s{0,5}(${P(Ei)})\\s{0,5}`,
  ns = new RegExp($i, "i"),
  Ql = oe("", $i);
function ef(s) {
  const e = {};
  let t = s,
    n = ns.exec(t);
  for (; n;) (tf(e, n), (t = t.substring(n[0].length)), (n = ns.exec(t)));
  return e;
}
function tf(s, e) {
  const t = Zl(e[1]),
    n = Ei[e[2].toLowerCase()];
  s[n] = t;
}
const nf = new RegExp(
    `(?:(?:\\,|\\(|\\（)\\s*)?(?:(este|esta|pasado|pr[oó]ximo)\\s*)?(${P(Pi)})(?:\\s*(?:\\,|\\)|\\）))?(?:\\s*(este|esta|pasado|pr[óo]ximo)\\s*semana)?(?=\\W|\\d|$)`,
    "i",
  ),
  rf = 1,
  sf = 2,
  af = 3;
class of extends g {
  innerPattern() {
    return nf;
  }
  innerExtract(e, t) {
    const n = t[sf].toLowerCase(),
      r = Pi[n];
    if (r === void 0) return null;
    const i = t[rf],
      a = t[af];
    let o = i || a || "";
    o = o.toLowerCase();
    let u = null;
    return (
      o == "pasado"
        ? (u = "this")
        : o == "próximo" || o == "proximo"
          ? (u = "next")
          : o == "este" && (u = "this"),
      me(e.reference, r, u)
    );
  }
}
class uf extends de {
  primaryPrefix() {
    return "(?:(?:aslas|deslas|las?|al?|de|del)\\s*)?";
  }
  followingPhase() {
    return "\\s*(?:\\-|\\–|\\~|\\〜|a(?:l)?|\\?)\\s*";
  }
}
class df extends Q {
  patternBetween() {
    return new RegExp("^\\s*(?:,|de|aslas|a)?\\s*$");
  }
}
class lf extends Z {
  patternBetween() {
    return /^\s*(?:-)\s*$/i;
  }
}
const ff = new RegExp(
    `([0-9]{1,2})(?:º|ª|°)?(?:\\s*(?:desde|de|\\-|\\–|ao?|\\s)\\s*([0-9]{1,2})(?:º|ª|°)?)?\\s*(?:de)?\\s*(?:-|/|\\s*(?:de|,)?\\s*)(${P(Ri)})(?:\\s*(?:de|,)?\\s*(${Xl}))?(?=\\W|$)`,
    "i",
  ),
  rs = 1,
  ss = 2,
  cf = 3,
  is = 4;
class mf extends g {
  innerPattern() {
    return ff;
  }
  innerExtract(e, t) {
    const n = e.createParsingResult(t.index, t[0]),
      r = Ri[t[cf].toLowerCase()],
      i = parseInt(t[rs]);
    if (i > 31) return ((t.index = t.index + t[rs].length), null);
    if ((n.start.assign("month", r), n.start.assign("day", i), t[is])) {
      const a = Jl(t[is]);
      n.start.assign("year", a);
    } else {
      const a = L(e.refDate, i, r);
      n.start.imply("year", a);
    }
    if (t[ss]) {
      const a = parseInt(t[ss]);
      ((n.end = n.start.clone()), n.end.assign("day", a));
    }
    return n;
  }
}
class gf extends g {
  innerPattern(e) {
    return /(ahora|hoy|mañana|ayer)(?=\W|$)/i;
  }
  innerExtract(e, t) {
    const n = t[0].toLowerCase(),
      r = e.createParsingComponents();
    switch (n) {
      case "ahora":
        return le(e.reference);
      case "hoy":
        return re(e.reference);
      case "mañana":
        return ce(e.reference);
      case "ayer":
        return fe(e.reference);
    }
    return r;
  }
}
class yf extends g {
  innerPattern() {
    return /(?:esta\s*)?(mañana|tarde|medianoche|mediodia|mediodía|noche)(?=\W|$)/i;
  }
  innerExtract(e, t) {
    const n = E(e.refDate),
      r = e.createParsingComponents();
    switch (t[1].toLowerCase()) {
      case "tarde":
        (r.imply("meridiem", f.PM), r.imply("hour", 15));
        break;
      case "noche":
        (r.imply("meridiem", f.PM), r.imply("hour", 22));
        break;
      case "mañana":
        (r.imply("meridiem", f.AM), r.imply("hour", 6));
        break;
      case "medianoche":
        (we(r, n),
          r.imply("hour", 0),
          r.imply("minute", 0),
          r.imply("second", 0));
        break;
      case "mediodia":
      case "mediodía":
        (r.imply("meridiem", f.AM), r.imply("hour", 12));
        break;
    }
    return r;
  }
}
class pf extends g {
  innerPattern() {
    return new RegExp(
      `(?:en|por|durante|de|dentro de)\\s*(${Ql})(?=\\W|$)`,
      "i",
    );
  }
  innerExtract(e, t) {
    const n = ef(t[1]);
    return p.createRelativeFromReference(e.reference, n);
  }
}
const Un = new $(wi()),
  hf = new $(In(!0));
function Tf(s, e, t) {
  return Un.parse(s, e, t);
}
function Pf(s, e, t) {
  return Un.parseDate(s, e, t);
}
function wi(s = !0) {
  const e = In(!1, s);
  return (e.parsers.push(new gf()), e.parsers.push(new yf()), e);
}
function In(s = !0, e = !0) {
  return X(
    {
      parsers: [new ge(e), new of(), new uf(), new mf(), new pf()],
      refiners: [new df(), new lf()],
    },
    s,
  );
}
const rc = Object.freeze(
    Object.defineProperty(
      {
        __proto__: null,
        Chrono: $,
        get Meridiem() {
          return f;
        },
        ParsingComponents: p,
        ParsingResult: I,
        ReferenceWithTimezone: G,
        get Weekday() {
          return _;
        },
        casual: Un,
        createCasualConfiguration: wi,
        createConfiguration: In,
        parse: Tf,
        parseDate: Pf,
        strict: hf,
      },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  ),
  ne = {
    leftBoundary: "([^\\p{L}\\p{N}_]|^)",
    rightBoundary: "(?=[^\\p{L}\\p{N}_]|$)",
    flags: "iu",
  },
  as = {
    неділя: 0,
    неділі: 0,
    неділю: 0,
    нд: 0,
    "нд.": 0,
    понеділок: 1,
    понеділка: 1,
    пн: 1,
    "пн.": 1,
    вівторок: 2,
    вівторка: 2,
    вт: 2,
    "вт.": 2,
    середа: 3,
    середи: 3,
    середу: 3,
    ср: 3,
    "ср.": 3,
    четвер: 4,
    четверга: 4,
    четвергу: 4,
    чт: 4,
    "чт.": 4,
    "п'ятниця": 5,
    "п'ятниці": 5,
    "п'ятницю": 5,
    пт: 5,
    "пт.": 5,
    субота: 6,
    суботи: 6,
    суботу: 6,
    сб: 6,
    "сб.": 6,
  },
  Oi = {
    січень: 1,
    січня: 1,
    січні: 1,
    лютий: 2,
    лютого: 2,
    лютому: 2,
    березень: 3,
    березня: 3,
    березні: 3,
    квітень: 4,
    квітня: 4,
    квітні: 4,
    травень: 5,
    травня: 5,
    травні: 5,
    червень: 6,
    червня: 6,
    червні: 6,
    липень: 7,
    липня: 7,
    липні: 7,
    серпень: 8,
    серпня: 8,
    серпні: 8,
    вересень: 9,
    вересня: 9,
    вересні: 9,
    жовтень: 10,
    жовтня: 10,
    жовтні: 10,
    листопад: 11,
    листопада: 11,
    листопаду: 11,
    грудень: 12,
    грудня: 12,
    грудні: 12,
  },
  Tt = {
    ...Oi,
    січ: 1,
    "січ.": 1,
    лют: 2,
    "лют.": 2,
    бер: 3,
    "бер.": 3,
    квіт: 4,
    "квіт.": 4,
    трав: 5,
    "трав.": 5,
    черв: 6,
    "черв.": 6,
    лип: 7,
    "лип.": 7,
    серп: 8,
    "серп.": 8,
    сер: 8,
    "cер.": 8,
    вер: 9,
    "вер.": 9,
    верес: 9,
    "верес.": 9,
    жовт: 10,
    "жовт.": 10,
    листоп: 11,
    "листоп.": 11,
    груд: 12,
    "груд.": 12,
  },
  en = {
    один: 1,
    одна: 1,
    одної: 1,
    одну: 1,
    дві: 2,
    два: 2,
    двох: 2,
    три: 3,
    трьох: 3,
    чотири: 4,
    чотирьох: 4,
    "п'ять": 5,
    "п'яти": 5,
    шість: 6,
    шести: 6,
    сім: 7,
    семи: 7,
    вісім: 8,
    восьми: 8,
    "дев'ять": 9,
    "дев'яти": 9,
    десять: 10,
    десяти: 10,
    одинадцять: 11,
    одинадцяти: 11,
    дванадцять: 12,
    дванадцяти: 12,
  },
  tn = {
    перше: 1,
    першого: 1,
    друге: 2,
    другого: 2,
    третє: 3,
    третього: 3,
    четверте: 4,
    четвертого: 4,
    "п'яте": 5,
    "п'ятого": 5,
    шосте: 6,
    шостого: 6,
    сьоме: 7,
    сьомого: 7,
    восьме: 8,
    восьмого: 8,
    "дев'яте": 9,
    "дев'ятого": 9,
    десяте: 10,
    десятого: 10,
    одинадцяте: 11,
    одинадцятого: 11,
    дванадцяте: 12,
    дванадцятого: 12,
    тринадцяте: 13,
    тринадцятого: 13,
    чотирнадцяте: 14,
    чотинрнадцятого: 14,
    "п'ятнадцяте": 15,
    "п'ятнадцятого": 15,
    шістнадцяте: 16,
    шістнадцятого: 16,
    сімнадцяте: 17,
    сімнадцятого: 17,
    вісімнадцяте: 18,
    вісімнадцятого: 18,
    "дев'ятнадцяте": 19,
    "дев'ятнадцятого": 19,
    двадцяте: 20,
    двадцятого: 20,
    "двадцять перше": 21,
    "двадцять першого": 21,
    "двадцять друге": 22,
    "двадцять другого": 22,
    "двадцять третє": 23,
    "двадцять третього": 23,
    "двадцять четверте": 24,
    "двадцять четвертого": 24,
    "двадцять п'яте": 25,
    "двадцять п'ятого": 25,
    "двадцять шосте": 26,
    "двадцять шостого": 26,
    "двадцять сьоме": 27,
    "двадцять сьомого": 27,
    "двадцять восьме": 28,
    "двадцять восьмого": 28,
    "двадцять дев'яте": 29,
    "двадцять дев'ятого": 29,
    тридцяте: 30,
    тридцятого: 30,
    "тридцять перше": 31,
    "тридцять першого": 31,
  },
  Pt = {
    сек: "second",
    секунда: "second",
    секунд: "second",
    секунди: "second",
    секунду: "second",
    секундочок: "second",
    секундочки: "second",
    секундочку: "second",
    хв: "minute",
    хвилина: "minute",
    хвилин: "minute",
    хвилини: "minute",
    хвилину: "minute",
    хвилинок: "minute",
    хвилинки: "minute",
    хвилинку: "minute",
    хвилиночок: "minute",
    хвилиночки: "minute",
    хвилиночку: "minute",
    год: "hour",
    година: "hour",
    годин: "hour",
    години: "hour",
    годину: "hour",
    годинка: "hour",
    годинок: "hour",
    годинки: "hour",
    годинку: "hour",
    день: "d",
    дня: "d",
    днів: "d",
    дні: "d",
    доба: "d",
    добу: "d",
    тиждень: "week",
    тижню: "week",
    тижня: "week",
    тижні: "week",
    тижнів: "week",
    місяць: "month",
    місяців: "month",
    місяці: "month",
    місяця: "month",
    квартал: "quarter",
    кварталу: "quarter",
    квартала: "quarter",
    кварталів: "quarter",
    кварталі: "quarter",
    рік: "year",
    року: "year",
    році: "year",
    років: "year",
    роки: "year",
  },
  Rf = `(?:${P(en)}|[0-9]+|[0-9]+\\.[0-9]+|пів|декілька|пар(?:у)|\\s{0,3})`;
function Ef(s) {
  const e = s.toLowerCase();
  return en[e] !== void 0
    ? en[e]
    : e.match(/декілька/)
      ? 2
      : e.match(/пів/)
        ? 0.5
        : e.match(/пар/)
          ? 2
          : e === ""
            ? 1
            : parseFloat(e);
}
const os = `(?:${P(tn)}|[0-9]{1,2}(?:го|ого|е)?)`;
function us(s) {
  const e = s.toLowerCase();
  return tn[e] !== void 0 ? tn[e] : parseInt(e);
}
const Yt = "(?:\\s+(?:року|рік|р|р.))?",
  xi = `(?:[1-9][0-9]{0,3}${Yt}\\s*(?:н.е.|до н.е.|н. е.|до н. е.)|[1-2][0-9]{3}${Yt}|[5-9][0-9]${Yt})`;
function _i(s) {
  if (
    (/(рік|року|р|р.)/i.test(s) && (s = s.replace(/(рік|року|р|р.)/i, "")),
    /(до н.е.|до н. е.)/i.test(s))
  )
    return ((s = s.replace(/(до н.е.|до н. е.)/i, "")), -parseInt(s));
  if (/(н. е.|н.е.)/i.test(s))
    return ((s = s.replace(/(н. е.|н.е.)/i, "")), parseInt(s));
  const e = parseInt(s);
  return xe(e);
}
const Ni = `(${Rf})\\s{0,3}(${P(Pt)})`,
  ds = new RegExp(Ni, "i"),
  bn = oe("(?:(?:близько|приблизно)\\s{0,3})?", Ni);
function Sn(s) {
  const e = {};
  let t = s,
    n = ds.exec(t);
  for (; n;)
    ($f(e, n), (t = t.substring(n[0].length).trim()), (n = ds.exec(t)));
  return e;
}
function $f(s, e) {
  const t = Ef(e[1]),
    n = Pt[e[2].toLowerCase()];
  s[n] = t;
}
const ls = `(?:(?:приблизно|орієнтовно)\\s*(?:~\\s*)?)?(${bn})${ne.rightBoundary}`;
class wf extends g {
  patternLeftBoundary() {
    return ne.leftBoundary;
  }
  innerPattern(e) {
    return e.option.forwardDate
      ? new RegExp(ls, "i")
      : new RegExp(
          `(?:протягом|на протязі|протягом|упродовж|впродовж)\\s*${ls}`,
          ne.flags,
        );
  }
  innerExtract(e, t) {
    const n = Sn(t[1]);
    return p.createRelativeFromReference(e.reference, n);
  }
}
class vn extends g {
  patternLeftBoundary() {
    return ne.leftBoundary;
  }
  innerPattern(e) {
    return new RegExp(this.innerPatternString(e), ne.flags);
  }
  innerPatternHasChange(e, t) {
    return !1;
  }
}
class De extends vn {
  innerPattern(e) {
    return new RegExp(
      `${this.innerPatternString(e)}${ne.rightBoundary}`,
      ne.flags,
    );
  }
}
const fs = 1,
  cs = 2,
  Of = 3,
  ms = 4;
class xf extends De {
  innerPatternString(e) {
    return `(?:з|із)?\\s*(${os})(?:\\s{0,3}(?:по|-|–|до)?\\s{0,3}(${os}))?(?:-|\\/|\\s{0,3}(?:of)?\\s{0,3})(${P(Tt)})(?:(?:-|\\/|,?\\s{0,3})(${xi}(?![^\\s]\\d)))?`;
  }
  innerExtract(e, t) {
    const n = e.createParsingResult(t.index, t[0]),
      r = Tt[t[Of].toLowerCase()],
      i = us(t[fs]);
    if (i > 31) return ((t.index = t.index + t[fs].length), null);
    if ((n.start.assign("month", r), n.start.assign("day", i), t[ms])) {
      const a = _i(t[ms]);
      n.start.assign("year", a);
    } else {
      const a = L(e.reference.instant, i, r);
      n.start.imply("year", a);
    }
    if (t[cs]) {
      const a = us(t[cs]);
      ((n.end = n.start.clone()), n.end.assign("day", a));
    }
    return n;
  }
}
const _f = 2,
  gs = 3;
class Nf extends vn {
  innerPatternString(e) {
    return `((?:в|у)\\s*)?(${P(Tt)})\\s*(?:[,-]?\\s*(${xi})?)?(?=[^\\s\\w]|\\s+[^0-9]|\\s+$|$)`;
  }
  innerExtract(e, t) {
    const n = t[_f].toLowerCase();
    if (t[0].length <= 3 && !Oi[n]) return null;
    const r = e.createParsingResult(t.index, t.index + t[0].length);
    r.start.imply("day", 1);
    const i = Tt[n];
    if ((r.start.assign("month", i), t[gs])) {
      const a = _i(t[gs]);
      r.start.assign("year", a);
    } else {
      const a = L(e.reference.instant, 1, i);
      r.start.imply("year", a);
    }
    return r;
  }
}
class Mf extends de {
  constructor(e) {
    super(e);
  }
  patternFlags() {
    return ne.flags;
  }
  primaryPatternLeftBoundary() {
    return "(^|\\s|T|(?:[^\\p{L}\\p{N}_]))";
  }
  followingPhase() {
    return "\\s*(?:\\-|\\–|\\~|\\〜|до|і|по|\\?)\\s*";
  }
  primaryPrefix() {
    return "(?:(?:в|у|о|об|з|із|від)\\s*)??";
  }
  primarySuffix() {
    return `(?:\\s*(?:ранку|вечора|по обіді|після обіду))?(?!\\/)${ne.rightBoundary}`;
  }
  extractPrimaryTimeComponents(e, t) {
    const n = super.extractPrimaryTimeComponents(e, t);
    if (n) {
      if (t[0].endsWith("вечора")) {
        const r = n.get("hour");
        r >= 6 && r < 12
          ? (n.assign("hour", n.get("hour") + 12), n.assign("meridiem", f.PM))
          : r < 6 && n.assign("meridiem", f.AM);
      }
      if (t[0].endsWith("по обіді") || t[0].endsWith("після обіду")) {
        n.assign("meridiem", f.PM);
        const r = n.get("hour");
        r >= 0 && r <= 6 && n.assign("hour", n.get("hour") + 12);
      }
      t[0].endsWith("ранку") &&
        (n.assign("meridiem", f.AM),
        n.get("hour") < 12 && n.assign("hour", n.get("hour")));
    }
    return n;
  }
}
class Af extends vn {
  innerPatternString(e) {
    return `(${bn})\\s{0,5}тому(?=(?:\\W|$))`;
  }
  innerExtract(e, t) {
    const n = Sn(t[1]),
      r = H(n);
    return p.createRelativeFromReference(e.reference, r);
  }
}
class Df extends Z {
  patternBetween() {
    return /^\s*(і до|і по|до|по|-)\s*$/i;
  }
}
class Cf extends Q {
  patternBetween() {
    return new RegExp("^\\s*(T|в|у|о|,|-)?\\s*$");
  }
}
class Uf extends De {
  innerPatternString(e) {
    return "(?:з|із|від)?\\s*(сьогодні|вчора|завтра|післязавтра|післяпіслязавтра|позапозавчора|позавчора)";
  }
  innerExtract(e, t) {
    const n = t[1].toLowerCase(),
      r = e.createParsingComponents();
    switch (n) {
      case "сьогодні":
        return re(e.reference);
      case "вчора":
        return fe(e.reference);
      case "завтра":
        return ce(e.reference);
      case "післязавтра":
        return Oe(e.reference, 2);
      case "післяпіслязавтра":
        return Oe(e.reference, 3);
      case "позавчора":
        return ke(e.reference, 2);
      case "позапозавчора":
        return ke(e.reference, 3);
    }
    return r;
  }
}
class If extends De {
  innerPatternString(e) {
    return "(зараз|минулого\\s*вечора|минулої\\s*ночі|наступної\\s*ночі|сьогодні\\s*вночі|цієї\\s*ночі|цього ранку|вранці|ранку|зранку|опівдні|ввечері|вечора|опівночі|вночі)";
  }
  innerExtract(e, t) {
    let n = E(e.reference.instant);
    const r = t[0].toLowerCase(),
      i = e.createParsingComponents();
    if (r === "зараз") return le(e.reference);
    if (r === "ввечері" || r === "вечора") return an(e.reference);
    if (r.endsWith("вранці") || r.endsWith("ранку") || r.endsWith("зранку"))
      return on(e.reference);
    if (r.endsWith("опівдні")) return un(e.reference);
    if (r.match(/минулої\s*ночі/)) return xs(e.reference);
    if (r.match(/минулого\s*вечора/)) return _s(e.reference);
    if (r.match(/наступної\s*ночі/)) {
      const a = n.hour() < 22 ? 1 : 2;
      ((n = n.add(a, "day")), D(i, n), i.imply("hour", 1));
    }
    return r.match(/цієї\s*ночі/) ||
      r.endsWith("опівночі") ||
      r.endsWith("вночі")
      ? ft(e.reference)
      : i;
  }
}
const bf = 1,
  Sf = 2,
  vf = 3;
class kf extends De {
  innerPatternString(e) {
    return `(?:(?:,|\\(|（)\\s*)?(?:в\\s*?)?(?:у\\s*?)?(?:(цей|минулого|минулий|попередній|попереднього|наступного|наступний|наступному)\\s*)?(${P(as)})(?:\\s*(?:,|\\)|）))?(?:\\s*(на|у|в)\\s*(цьому|минулому|наступному)\\s*тижні)?`;
  }
  innerExtract(e, t) {
    const n = t[Sf].toLocaleLowerCase(),
      r = as[n],
      i = t[bf],
      a = t[vf];
    let o = i || a;
    ((o = o || ""), (o = o.toLocaleLowerCase()));
    let u = null;
    return (
      o == "минулого" ||
      o == "минулий" ||
      o == "попередній" ||
      o == "попереднього"
        ? (u = "last")
        : o == "наступного" || o == "наступний"
          ? (u = "next")
          : (o == "цей" || o == "цього" || o == "цьому") && (u = "this"),
      me(e.reference, r, u)
    );
  }
}
const Wf = 1,
  Ff = 2;
class Gf extends De {
  innerPatternString(e) {
    return `(в минулому|у минулому|на минулому|минулого|на наступному|в наступному|у наступному|наступного|на цьому|в цьому|у цьому|цього)\\s*(${P(Pt)})(?=\\s*)`;
  }
  innerExtract(e, t) {
    const n = t[Wf].toLowerCase(),
      r = t[Ff].toLowerCase(),
      i = Pt[r];
    if (
      n == "на наступному" ||
      n == "в наступному" ||
      n == "у наступному" ||
      n == "наступного"
    ) {
      const u = {};
      return ((u[i] = 1), p.createRelativeFromReference(e.reference, u));
    }
    if (
      n == "на минулому" ||
      n == "в минулому" ||
      n == "у минулому" ||
      n == "минулого"
    ) {
      const u = {};
      return ((u[i] = -1), p.createRelativeFromReference(e.reference, u));
    }
    const a = e.createParsingComponents();
    let o = E(e.reference.instant);
    return (
      i.match(/week/i)
        ? ((o = o.add(-o.get("d"), "d")),
          a.imply("day", o.date()),
          a.imply("month", o.month() + 1),
          a.imply("year", o.year()))
        : i.match(/month/i)
          ? ((o = o.add(-o.date() + 1, "d")),
            a.imply("day", o.date()),
            a.assign("year", o.year()),
            a.assign("month", o.month() + 1))
          : i.match(/year/i) &&
            ((o = o.add(-o.date() + 1, "d")),
            (o = o.add(-o.month(), "month")),
            a.imply("day", o.date()),
            a.imply("month", o.month() + 1),
            a.assign("year", o.year())),
      a
    );
  }
}
class Lf extends De {
  innerPatternString(e) {
    return `(ці|останні|минулі|майбутні|наступні|після|через|\\+|-)\\s*(${bn})`;
  }
  innerExtract(e, t) {
    const n = t[1].toLowerCase();
    let r = Sn(t[3]);
    switch (n) {
      case "останні":
      case "минулі":
      case "-":
        r = H(r);
        break;
    }
    return p.createRelativeFromReference(e.reference, r);
  }
}
const kn = new $(Mi()),
  jf = new $(Wn(!0));
function Mi() {
  const s = Wn(!1);
  return (
    s.parsers.unshift(new Uf()),
    s.parsers.unshift(new If()),
    s.parsers.unshift(new Nf()),
    s.parsers.unshift(new Gf()),
    s.parsers.unshift(new Lf()),
    s
  );
}
function Wn(s) {
  return X(
    {
      parsers: [
        new sn(),
        new ge(!0),
        new wf(),
        new xf(),
        new kf(),
        new Mf(s),
        new Af(),
      ],
      refiners: [new Cf(), new Df()],
    },
    s,
  );
}
function Yf(s, e, t) {
  return kn.parse(s, e, t);
}
function zf(s, e, t) {
  return kn.parseDate(s, e, t);
}
const sc = Object.freeze(
    Object.defineProperty(
      {
        __proto__: null,
        Chrono: $,
        get Meridiem() {
          return f;
        },
        ParsingComponents: p,
        ParsingResult: I,
        ReferenceWithTimezone: G,
        get Weekday() {
          return _;
        },
        casual: kn,
        createCasualConfiguration: Mi,
        createConfiguration: Wn,
        parse: Yf,
        parseDate: zf,
        strict: jf,
      },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  ),
  ic = As,
  Ai = Ot;
function ac(s, e, t) {
  return Ai.parse(s, e, t);
}
function oc(s, e, t) {
  return Ai.parseDate(s, e, t);
}
export {
  $ as Chrono,
  f as Meridiem,
  p as ParsingComponents,
  I as ParsingResult,
  G as ReferenceWithTimezone,
  _ as Weekday,
  Ai as casual,
  Vf as de,
  Bf as en,
  rc as es,
  Kf as fr,
  Zf as ja,
  Jf as nl,
  ac as parse,
  oc as parseDate,
  Xf as pt,
  nc as ru,
  ic as strict,
  sc as uk,
  Qf as zh,
};
//# sourceMappingURL=index-DoBZ56Sp.js.map
