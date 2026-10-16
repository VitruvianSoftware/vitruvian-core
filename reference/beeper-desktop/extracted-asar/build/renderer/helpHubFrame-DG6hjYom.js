import { A as C, H as R } from "./helpHubMessages-CXhGQ9cB.js";
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
      (e._sentryDebugIds[t] = "9e44fcd8-daab-4a29-9668-08ed7da1c784"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-9e44fcd8-daab-4a29-9668-08ed7da1c784"));
  } catch {}
})();
var Z = (function () {
    function e() {}
    return (
      (e.prototype.getApplicationContext = function () {
        return {
          versionName: this.versionName,
          language: B(),
          platform: "Web",
          os: void 0,
          deviceModel: void 0,
        };
      }),
      e
    );
  })(),
  B = function () {
    return (
      (typeof navigator < "u" &&
        ((navigator.languages && navigator.languages[0]) ||
          navigator.language)) ||
      ""
    );
  },
  z = (function () {
    function e() {
      this.queue = [];
    }
    return (
      (e.prototype.logEvent = function (t) {
        this.receiver
          ? this.receiver(t)
          : this.queue.length < 512 && this.queue.push(t);
      }),
      (e.prototype.setEventReceiver = function (t) {
        ((this.receiver = t),
          this.queue.length > 0 &&
            (this.queue.forEach(function (n) {
              t(n);
            }),
            (this.queue = [])));
      }),
      e
    );
  })(),
  S = function () {
    return (
      (S =
        Object.assign ||
        function (e) {
          for (var t, n = 1, i = arguments.length; n < i; n++) {
            t = arguments[n];
            for (var a in t)
              Object.prototype.hasOwnProperty.call(t, a) && (e[a] = t[a]);
          }
          return e;
        }),
      S.apply(this, arguments)
    );
  };
function x(e) {
  var t = typeof Symbol == "function" && Symbol.iterator,
    n = t && e[t],
    i = 0;
  if (n) return n.call(e);
  if (e && typeof e.length == "number")
    return {
      next: function () {
        return (
          e && i >= e.length && (e = void 0),
          { value: e && e[i++], done: !e }
        );
      },
    };
  throw new TypeError(
    t ? "Object is not iterable." : "Symbol.iterator is not defined.",
  );
}
function k(e, t) {
  var n = typeof Symbol == "function" && e[Symbol.iterator];
  if (!n) return e;
  var i = n.call(e),
    a,
    s = [],
    v;
  try {
    for (; (t === void 0 || t-- > 0) && !(a = i.next()).done;) s.push(a.value);
  } catch (p) {
    v = { error: p };
  } finally {
    try {
      a && !a.done && (n = i.return) && n.call(i);
    } finally {
      if (v) throw v.error;
    }
  }
  return s;
}
var A = function (e, t) {
    var n,
      i,
      a = ["string", "number", "boolean", "undefined"],
      s = typeof e,
      v = typeof t;
    if (s !== v) return !1;
    try {
      for (var p = x(a), w = p.next(); !w.done; w = p.next()) {
        var U = w.value;
        if (U === s) return e === t;
      }
    } catch (r) {
      n = { error: r };
    } finally {
      try {
        w && !w.done && (i = p.return) && i.call(p);
      } finally {
        if (n) throw n.error;
      }
    }
    if (e == null && t == null) return !0;
    if (e == null || t == null || e.length !== t.length) return !1;
    var P = Array.isArray(e),
      l = Array.isArray(t);
    if (P !== l) return !1;
    if (P && l) {
      for (var m = 0; m < e.length; m++) if (!A(e[m], t[m])) return !1;
    } else {
      var o = Object.keys(e).sort(),
        T = Object.keys(t).sort();
      if (!A(o, T)) return !1;
      var b = !0;
      return (
        Object.keys(e).forEach(function (r) {
          A(e[r], t[r]) || (b = !1);
        }),
        b
      );
    }
    return !0;
  },
  G = "$set",
  H = "$unset",
  F = "$clearAll";
Object.entries ||
  (Object.entries = function (e) {
    for (var t = Object.keys(e), n = t.length, i = new Array(n); n--;)
      i[n] = [t[n], e[t[n]]];
    return i;
  });
var Y = (function () {
    function e() {
      ((this.identity = { userProperties: {} }), (this.listeners = new Set()));
    }
    return (
      (e.prototype.editIdentity = function () {
        var t = this,
          n = S({}, this.identity.userProperties),
          i = S(S({}, this.identity), { userProperties: n });
        return {
          setUserId: function (a) {
            return ((i.userId = a), this);
          },
          setDeviceId: function (a) {
            return ((i.deviceId = a), this);
          },
          setUserProperties: function (a) {
            return ((i.userProperties = a), this);
          },
          setOptOut: function (a) {
            return ((i.optOut = a), this);
          },
          updateUserProperties: function (a) {
            var s,
              v,
              p,
              w,
              U,
              P,
              l = i.userProperties || {};
            try {
              for (
                var m = x(Object.entries(a)), o = m.next();
                !o.done;
                o = m.next()
              ) {
                var T = k(o.value, 2),
                  b = T[0],
                  r = T[1];
                switch (b) {
                  case G:
                    try {
                      for (
                        var u = ((p = void 0), x(Object.entries(r))),
                          d = u.next();
                        !d.done;
                        d = u.next()
                      ) {
                        var h = k(d.value, 2),
                          I = h[0],
                          _ = h[1];
                        l[I] = _;
                      }
                    } catch (E) {
                      p = { error: E };
                    } finally {
                      try {
                        d && !d.done && (w = u.return) && w.call(u);
                      } finally {
                        if (p) throw p.error;
                      }
                    }
                    break;
                  case H:
                    try {
                      for (
                        var y = ((U = void 0), x(Object.keys(r))), g = y.next();
                        !g.done;
                        g = y.next()
                      ) {
                        var I = g.value;
                        delete l[I];
                      }
                    } catch (E) {
                      U = { error: E };
                    } finally {
                      try {
                        g && !g.done && (P = y.return) && P.call(y);
                      } finally {
                        if (U) throw U.error;
                      }
                    }
                    break;
                  case F:
                    l = {};
                    break;
                }
              }
            } catch (E) {
              s = { error: E };
            } finally {
              try {
                o && !o.done && (v = m.return) && v.call(m);
              } finally {
                if (s) throw s.error;
              }
            }
            return ((i.userProperties = l), this);
          },
          commit: function () {
            return (t.setIdentity(i), this);
          },
        };
      }),
      (e.prototype.getIdentity = function () {
        return S({}, this.identity);
      }),
      (e.prototype.setIdentity = function (t) {
        var n = S({}, this.identity);
        ((this.identity = S({}, t)),
          A(n, this.identity) ||
            this.listeners.forEach(function (i) {
              i(t);
            }));
      }),
      (e.prototype.addIdentityListener = function (t) {
        this.listeners.add(t);
      }),
      (e.prototype.removeIdentityListener = function (t) {
        this.listeners.delete(t);
      }),
      e
    );
  })(),
  $ =
    typeof globalThis < "u" ? globalThis : typeof window < "u" ? window : self,
  V = (function () {
    function e() {
      ((this.identityStore = new Y()),
        (this.eventBridge = new z()),
        (this.applicationContextProvider = new Z()));
    }
    return (
      (e.getInstance = function (t) {
        return (
          $.analyticsConnectorInstances || ($.analyticsConnectorInstances = {}),
          $.analyticsConnectorInstances[t] ||
            ($.analyticsConnectorInstances[t] = new e()),
          $.analyticsConnectorInstances[t]
        );
      }),
      e
    );
  })(),
  D = ["boot"],
  W = "$default_instance",
  q = Symbol.for("amplitude-engagement-plugin-caller");
function Q(e) {
  var t, n, i, a, s, v, p, w, U, P;
  let l = typeof window < "u" ? window.engagement : void 0,
    m = !1,
    o = {
      _q: (t = l?._q) != null ? t : [],
      _configuration: {
        apiKey:
          (i = (n = l?._configuration) == null ? void 0 : n.apiKey) != null
            ? i
            : "",
        serverUrl: (a = l?._configuration) == null ? void 0 : a.serverUrl,
        chatUrl: (s = l?._configuration) == null ? void 0 : s.chatUrl,
        mediaUrl: (v = l?._configuration) == null ? void 0 : v.mediaUrl,
        serverZone:
          (w = (p = l?._configuration) == null ? void 0 : p.serverZone) != null
            ? w
            : "US",
        autoRefreshIntervalSeconds:
          (U = l?._configuration) == null
            ? void 0
            : U.autoRefreshIntervalSeconds,
        options: { ...((P = l?._configuration) == null ? void 0 : P.options) },
      },
      init(b, r) {
        var u, d, h, I;
        if (o._configuration.apiKey) {
          console.log(
            "Engagement SDK has already been initialized. Ignoring additional init call.",
          );
          return;
        }
        if (r != null && r.useEngagementDomain) {
          let c =
              ((u = r.serverZone) != null ? u : o._configuration.serverZone) ===
              "EU",
            f = "amplitudeengagement.com";
          (r.serverUrl ||
            (r.serverUrl = c ? `https://gs.eu.${f}` : `https://gs.${f}`),
            r.chatUrl ||
              (r.chatUrl = c
                ? `https://houston-chat.eu.${f}`
                : `https://houston-chat.${f}`),
            r.mediaUrl ||
              (r.mediaUrl = c
                ? `https://engagement-static.eu.${f}`
                : `https://engagement-static.${f}`),
            r.cdnUrl ||
              (r.cdnUrl = c ? `https://cdn.eu.${f}` : `https://cdn.${f}`));
        }
        ((o._configuration = {
          ...o._configuration,
          ...r,
          apiKey: b,
          options: {
            splitting: !0,
            ...o._configuration.options,
            ...r?.options,
          },
        }),
          (h = (d = o._configuration) == null ? void 0 : d.options) != null &&
            h.logger &&
            o._configuration.options.logger.enable(
              (I = o._configuration.options.logLevel) != null ? I : 2,
            ));
        let _;
        if (r != null && r.cdnUrl)
          o._configuration.options.splitting
            ? (_ = `${r.cdnUrl}/engagement-browser/prod/split/index.js`)
            : (_ = r.cdnUrl + "/engagement-browser/prod/index.min.js.gz");
        else {
          let c =
            o._configuration.serverZone === "EU"
              ? "https://cdn.eu.amplitude.com"
              : "https://cdn.amplitude.com";
          o._configuration.options.splitting
            ? (_ = `${c}/engagement-browser/prod/split/index.js`)
            : (_ = `${c}/engagement-browser/prod/index.min.js.gz`);
        }
        let y = null,
          g = () => {
            if (
              ((m = !0),
              y && (clearTimeout(y), (y = null)),
              o._q && o._q.length > 0)
            )
              for (
                console.warn(
                  `Engagement SDK failed to load within ${E}ms. Resolving pending calls gracefully.`,
                );
                o._q.length > 0;
              ) {
                let c = o._q.shift();
                if (!c) continue;
                let f = c[0],
                  O = D.includes(f);
                if (
                  (console.warn(
                    `Engagement SDK method '${f}' still in queue (isAsyncMethod=${O}); attempting to resolve as no-op.`,
                  ),
                  O && c[1] instanceof Function && c[2] instanceof Function)
                ) {
                  let j = c[1];
                  (console.warn(
                    `Engagement SDK method '${f}' resolved as no-op due to script loading failure`,
                  ),
                    j(void 0));
                }
              }
          };
        e(
          _,
          o._configuration.options.splitting ? "module" : void 0,
          r?.nonce,
          g,
        );
        let E = 1e4;
        y = setTimeout(() => {
          g();
        }, E);
      },
      plugin(b) {
        let r = o.init;
        return {
          name: "@amplitude/engagement-browser",
          type: "enrichment",
          async setup(u, d) {
            var h;
            let I = (h = u.instanceName) != null ? h : W,
              _ = V.getInstance(I).identityStore;
            ((o._configuration._installedViaPlugin = !0),
              r(u.apiKey, {
                serverZone: u.serverZone,
                ...b,
                options: {
                  logLevel: u.logLevel,
                  logger: u.loggerProvider,
                  ...b?.options,
                },
              }));
            let y = [
              {
                track: (g) => {
                  d.track(g);
                },
              },
            ];
            (await window.engagement.boot(
              {
                user: () => {
                  let g = _.getIdentity();
                  return {
                    user_id: d.getUserId(),
                    device_id: d.getDeviceId(),
                    user_properties: g.userProperties,
                    getSessionId: d.getSessionId,
                  };
                },
                integrations: y,
              },
              q,
            ),
              _.addIdentityListener((g) => {
                var E, c, f, O;
                if (
                  !((E = window.engagement) != null && E._.user) ||
                  !((c = window.engagement) != null && c._analytics.hasBooted)
                ) {
                  console.warn(
                    "Engagement SDK not booted. Ignoring identity change.",
                  );
                  return;
                }
                ((O = (f = window.engagement) == null ? void 0 : f._.user) ==
                null
                  ? void 0
                  : O.user_id) !== g.userId
                  ? (window.engagement.shutdown(q),
                    window.engagement.boot(
                      {
                        user: () => {
                          let j = _.getIdentity();
                          return {
                            user_id: d.getUserId(),
                            device_id: d.getDeviceId(),
                            user_properties: j.userProperties,
                            getSessionId: d.getSessionId,
                          };
                        },
                        integrations: y,
                      },
                      q,
                    ))
                  : window.engagement._setUserProperties(g.userProperties);
              }));
          },
          async execute(u) {
            return (window.engagement.forwardEvent(u), u);
          },
        };
      },
    },
    T = o;
  return new Proxy(o, {
    get: function (b, r) {
      if (r in T) return T[r];
      if (r !== "then")
        return r === "gs" || r === "rc"
          ? new Proxy(
              {},
              {
                get: function (u, d) {
                  return function () {
                    let h = Array.from(arguments),
                      I = `${r}.${d}`;
                    (h.unshift(I), o._q.push(h));
                  };
                },
              },
            )
          : D.includes(r)
            ? function () {
                let u = Array.prototype.slice.call(arguments);
                return new Promise((d, h) => {
                  (u.unshift(r, d, h), o._q.push(u), m && d(void 0));
                });
              }
            : function () {
                let u = Array.prototype.slice.call(arguments);
                (u.unshift(r), o._q.push(u));
              };
    },
  });
}
var N = ((e) => (
    (e.Local = "https://local.amplitude.com:3010/"),
    (e.Staging = "https://apps.stag2.amplitude.com/"),
    (e.Production = "https://app.amplitude.com/"),
    (e.ProductionEU = "https://app.eu.amplitude.com/"),
    e
  ))(N || {}),
  J = (e) => {
    if (typeof window < "u" && window.opener)
      for (let t of Object.values(N))
        window.opener.postMessage({ message: e }, t);
  };
function X(e, t, n, i) {
  for (let a of e) {
    let s = document.createElement("script");
    ((s.src = a),
      (s.id = "engagement-sdk-bundle"),
      n && s.setAttribute("nonce", n),
      t && s.setAttribute("type", t),
      i && (s.onerror = i),
      document.getElementsByTagName("head")[0].appendChild(s));
  }
}
var ee = () => (
    J("ENGAGEMENT_SNIPPET"),
    Q((e, t, n, i) =>
      X(
        [
          e ||
            "https://cdn.amplitude.com/engagement-browser/prod/index.min.js.gz",
        ],
        t,
        n,
        i,
      ),
    )
  ),
  L = ee(),
  te = (e, t) => {
    (typeof window < "u" && !window.engagement && (window.engagement = L),
      L.init(e, t));
  };
const ne = new URLSearchParams(location.search),
  re = ne.get("theme") === "lightMode" ? "lightMode" : "darkMode",
  M = (e) => parent.postMessage(e, "*"),
  K = (e) => M({ helphub: "error", message: String(e) });
async function ie() {
  let e,
    t = !1;
  try {
    te(C, {
      options: { mountElementId: "eng-mount", persistResourceCenter: !1 },
    });
    let n = !1;
    const i = () => {
        t ||
          (document.getElementById("resource-center-modal")
            ? n || ((n = !0), e && clearTimeout(e), M({ helphub: "ready" }))
            : n && (M({ helphub: "close" }), a.disconnect()));
      },
      a = new MutationObserver(i);
    if (
      (a.observe(document.body, { childList: !0, subtree: !0 }),
      i(),
      (e = setTimeout(() => {
        ((t = !0),
          a.disconnect(),
          window.engagement?.shutdown(),
          K(new Error("Help timed out while loading")));
      }, R)),
      await window.engagement.boot({
        user: { device_id: "anonymous" },
        integrations: [{ track: () => {} }],
      }),
      t)
    )
      return;
    (window.engagement.setThemeMode(re),
      window.engagement.rc.open(),
      i(),
      addEventListener("message", (s) => {
        if (!(s.source !== parent || !s.data)) {
          if (s.data.helphub === "shutdown") {
            window.engagement?.shutdown();
            return;
          }
          s.data.helphubTheme &&
            window.engagement?.setThemeMode(s.data.helphubTheme);
        }
      }));
  } catch (n) {
    if (t) return;
    ((t = !0), e && clearTimeout(e), window.engagement?.shutdown(), K(n));
  }
}
ie();
//# sourceMappingURL=helpHubFrame-DG6hjYom.js.map
