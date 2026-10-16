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
    var a = new s.Error().stack;
    a &&
      ((s._sentryDebugIds = s._sentryDebugIds || {}),
      (s._sentryDebugIds[a] = "2da27aaf-4001-4801-be72-cc7db474fed2"),
      (s._sentryDebugIdIdentifier =
        "sentry-dbid-2da27aaf-4001-4801-be72-cc7db474fed2"));
  } catch {}
})();
var d, o;
function g() {
  if (o) return d;
  o = 1;
  var s = 1e3,
    a = s * 60,
    t = a * 60,
    c = t * 24,
    f = c * 7,
    h = c * 365.25;
  d = function (e, r) {
    r = r || {};
    var n = typeof e;
    if (n === "string" && e.length > 0) return y(e);
    if (n === "number" && isFinite(e)) return r.long ? m(e) : l(e);
    throw new Error(
      "val is not a non-empty string or a valid number. val=" +
        JSON.stringify(e),
    );
  };
  function y(e) {
    if (((e = String(e)), !(e.length > 100))) {
      var r =
        /^(-?(?:\d+)?\.?\d+) *(milliseconds?|msecs?|ms|seconds?|secs?|s|minutes?|mins?|m|hours?|hrs?|h|days?|d|weeks?|w|years?|yrs?|y)?$/i.exec(
          e,
        );
      if (r) {
        var n = parseFloat(r[1]),
          i = (r[2] || "ms").toLowerCase();
        switch (i) {
          case "years":
          case "year":
          case "yrs":
          case "yr":
          case "y":
            return n * h;
          case "weeks":
          case "week":
          case "w":
            return n * f;
          case "days":
          case "day":
          case "d":
            return n * c;
          case "hours":
          case "hour":
          case "hrs":
          case "hr":
          case "h":
            return n * t;
          case "minutes":
          case "minute":
          case "mins":
          case "min":
          case "m":
            return n * a;
          case "seconds":
          case "second":
          case "secs":
          case "sec":
          case "s":
            return n * s;
          case "milliseconds":
          case "millisecond":
          case "msecs":
          case "msec":
          case "ms":
            return n;
          default:
            return;
        }
      }
    }
  }
  function l(e) {
    var r = Math.abs(e);
    return r >= c
      ? Math.round(e / c) + "d"
      : r >= t
        ? Math.round(e / t) + "h"
        : r >= a
          ? Math.round(e / a) + "m"
          : r >= s
            ? Math.round(e / s) + "s"
            : e + "ms";
  }
  function m(e) {
    var r = Math.abs(e);
    return r >= c
      ? u(e, r, c, "day")
      : r >= t
        ? u(e, r, t, "hour")
        : r >= a
          ? u(e, r, a, "minute")
          : r >= s
            ? u(e, r, s, "second")
            : e + " ms";
  }
  function u(e, r, n, i) {
    var b = r >= n * 1.5;
    return Math.round(e / n) + " " + i + (b ? "s" : "");
  }
  return d;
}
export { g as r };
//# sourceMappingURL=index-Bo2CLT1C.mjs.map
