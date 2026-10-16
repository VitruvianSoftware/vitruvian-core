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
    var t = new e.Error().stack;
    t &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[t] = "1d84d3bf-6452-4d17-aae7-1d034808ffbb"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-1d84d3bf-6452-4d17-aae7-1d034808ffbb"));
  } catch {}
})();
var d,
  l,
  P,
  y,
  s = function (e, t) {
    return {
      name: e,
      value: t === void 0 ? -1 : t,
      delta: 0,
      entries: [],
      id: "v2-"
        .concat(Date.now(), "-")
        .concat(Math.floor(8999999999999 * Math.random()) + 1e12),
    };
  },
  T = function (e, t) {
    try {
      if (PerformanceObserver.supportedEntryTypes.includes(e)) {
        if (e === "first-input" && !("PerformanceEventTiming" in self)) return;
        var i = new PerformanceObserver(function (a) {
          return a.getEntries().map(t);
        });
        return (i.observe({ type: e, buffered: !0 }), i);
      }
    } catch {}
  },
  h = function (e, t) {
    var i = function a(n) {
      (n.type !== "pagehide" && document.visibilityState !== "hidden") ||
        (e(n),
        t &&
          (removeEventListener("visibilitychange", a, !0),
          removeEventListener("pagehide", a, !0)));
    };
    (addEventListener("visibilitychange", i, !0),
      addEventListener("pagehide", i, !0));
  },
  g = function (e) {
    addEventListener(
      "pageshow",
      function (t) {
        t.persisted && e(t);
      },
      !0,
    );
  },
  m = function (e, t, i) {
    var a;
    return function (n) {
      t.value >= 0 &&
        (n || i) &&
        ((t.delta = t.value - (a || 0)),
        (t.delta || a === void 0) && ((a = t.value), e(t)));
    };
  },
  v = -1,
  S = function () {
    return document.visibilityState === "hidden" ? 0 : 1 / 0;
  },
  L = function () {
    h(function (e) {
      var t = e.timeStamp;
      v = t;
    }, !0);
  },
  w = function () {
    return (
      v < 0 &&
        ((v = S()),
        L(),
        g(function () {
          setTimeout(function () {
            ((v = S()), L());
          }, 0);
        })),
      {
        get firstHiddenTime() {
          return v;
        },
      }
    );
  },
  A = function (e, t) {
    var i,
      a = w(),
      n = s("FCP"),
      o = function (c) {
        c.name === "first-contentful-paint" &&
          (u && u.disconnect(),
          c.startTime < a.firstHiddenTime &&
            ((n.value = c.startTime), n.entries.push(c), i(!0)));
      },
      r =
        window.performance &&
        performance.getEntriesByName &&
        performance.getEntriesByName("first-contentful-paint")[0],
      u = r ? null : T("paint", o);
    (r || u) &&
      ((i = m(e, n, t)),
      r && o(r),
      g(function (c) {
        ((n = s("FCP")),
          (i = m(e, n, t)),
          requestAnimationFrame(function () {
            requestAnimationFrame(function () {
              ((n.value = performance.now() - c.timeStamp), i(!0));
            });
          }));
      }));
  },
  F = !1,
  E = -1,
  q = function (e, t) {
    F ||
      (A(function (f) {
        E = f.value;
      }),
      (F = !0));
    var i,
      a = function (f) {
        E > -1 && e(f);
      },
      n = s("CLS", 0),
      o = 0,
      r = [],
      u = function (f) {
        if (!f.hadRecentInput) {
          var k = r[0],
            R = r[r.length - 1];
          (o &&
          f.startTime - R.startTime < 1e3 &&
          f.startTime - k.startTime < 5e3
            ? ((o += f.value), r.push(f))
            : ((o = f.value), (r = [f])),
            o > n.value && ((n.value = o), (n.entries = r), i()));
        }
      },
      c = T("layout-shift", u);
    c &&
      ((i = m(a, n, t)),
      h(function () {
        (c.takeRecords().map(u), i(!0));
      }),
      g(function () {
        ((o = 0), (E = -1), (n = s("CLS", 0)), (i = m(a, n, t)));
      }));
  },
  p = { passive: !0, capture: !0 },
  B = new Date(),
  D = function (e, t) {
    d || ((d = t), (l = e), (P = new Date()), I(removeEventListener), C());
  },
  C = function () {
    if (l >= 0 && l < P - B) {
      var e = {
        entryType: "first-input",
        name: d.type,
        target: d.target,
        cancelable: d.cancelable,
        startTime: d.timeStamp,
        processingStart: d.timeStamp + l,
      };
      (y.forEach(function (t) {
        t(e);
      }),
        (y = []));
    }
  },
  _ = function (e) {
    if (e.cancelable) {
      var t =
        (e.timeStamp > 1e12 ? new Date() : performance.now()) - e.timeStamp;
      e.type == "pointerdown"
        ? (function (i, a) {
            var n = function () {
                (D(i, a), r());
              },
              o = function () {
                r();
              },
              r = function () {
                (removeEventListener("pointerup", n, p),
                  removeEventListener("pointercancel", o, p));
              };
            (addEventListener("pointerup", n, p),
              addEventListener("pointercancel", o, p));
          })(t, e)
        : D(t, e);
    }
  },
  I = function (e) {
    ["mousedown", "keydown", "touchstart", "pointerdown"].forEach(function (t) {
      return e(t, _, p);
    });
  },
  H = function (e, t) {
    var i,
      a = w(),
      n = s("FID"),
      o = function (u) {
        u.startTime < a.firstHiddenTime &&
          ((n.value = u.processingStart - u.startTime),
          n.entries.push(u),
          i(!0));
      },
      r = T("first-input", o);
    ((i = m(e, n, t)),
      r &&
        h(function () {
          (r.takeRecords().map(o), r.disconnect());
        }, !0),
      r &&
        g(function () {
          var u;
          ((n = s("FID")),
            (i = m(e, n, t)),
            (y = []),
            (l = -1),
            (d = null),
            I(addEventListener),
            (u = o),
            y.push(u),
            C());
        }));
  },
  b = {},
  N = function (e, t) {
    var i,
      a = w(),
      n = s("LCP"),
      o = function (c) {
        var f = c.startTime;
        f < a.firstHiddenTime && ((n.value = f), n.entries.push(c), i());
      },
      r = T("largest-contentful-paint", o);
    if (r) {
      i = m(e, n, t);
      var u = function () {
        b[n.id] ||
          (r.takeRecords().map(o), r.disconnect(), (b[n.id] = !0), i(!0));
      };
      (["keydown", "click"].forEach(function (c) {
        addEventListener(c, u, { once: !0, capture: !0 });
      }),
        h(u, !0),
        g(function (c) {
          ((n = s("LCP")),
            (i = m(e, n, t)),
            requestAnimationFrame(function () {
              requestAnimationFrame(function () {
                ((n.value = performance.now() - c.timeStamp),
                  (b[n.id] = !0),
                  i(!0));
              });
            }));
        }));
    }
  },
  M = function (e) {
    var t,
      i = s("TTFB");
    ((t = function () {
      try {
        var a =
          performance.getEntriesByType("navigation")[0] ||
          (function () {
            var n = performance.timing,
              o = { entryType: "navigation", startTime: 0 };
            for (var r in n)
              r !== "navigationStart" &&
                r !== "toJSON" &&
                (o[r] = Math.max(n[r] - n.navigationStart, 0));
            return o;
          })();
        if (
          ((i.value = i.delta = a.responseStart),
          i.value < 0 || i.value > performance.now())
        )
          return;
        ((i.entries = [a]), e(i));
      } catch {}
    }),
      document.readyState === "complete"
        ? setTimeout(t, 0)
        : addEventListener("load", function () {
            return setTimeout(t, 0);
          }));
  };
export { q as getCLS, A as getFCP, H as getFID, N as getLCP, M as getTTFB };
//# sourceMappingURL=web-vitals-Byxqmm75.js.map
