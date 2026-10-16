import { a7 as se } from "./sentry-common-BNqrY_yc.js";
(function () {
  try {
    var F =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    F.SENTRY_RELEASE = { id: "4.3.209" };
    var Y = new F.Error().stack;
    Y &&
      ((F._sentryDebugIds = F._sentryDebugIds || {}),
      (F._sentryDebugIds[Y] = "3f1efd1c-bb06-4014-8b18-15c90d277843"),
      (F._sentryDebugIdIdentifier =
        "sentry-dbid-3f1efd1c-bb06-4014-8b18-15c90d277843"));
  } catch {}
})();
function oe(F, Y) {
  for (var U = 0; U < Y.length; U++) {
    const G = Y[U];
    if (typeof G != "string" && !Array.isArray(G)) {
      for (const q in G)
        if (q !== "default" && !(q in F)) {
          const X = Object.getOwnPropertyDescriptor(G, q);
          X &&
            Object.defineProperty(
              F,
              q,
              X.get ? X : { enumerable: !0, get: () => G[q] },
            );
        }
    }
  }
  return Object.freeze(
    Object.defineProperty(F, Symbol.toStringTag, { value: "Module" }),
  );
}
var Z = { exports: {} };
var te;
function ue() {
  return (
    te ||
      ((te = 1),
      (function (F, Y) {
        (function (G, q) {
          F.exports = q();
        })(self, () =>
          (() => {
            var U = {
                "./src/drawer.canvasentry.js": (V, c, w) => {
                  (Object.defineProperty(c, "__esModule", { value: !0 }),
                    (c.default = void 0));
                  var k = C(w("./src/util/style.js")),
                    R = C(w("./src/util/get-id.js"));
                  function C(v) {
                    return v && v.__esModule ? v : { default: v };
                  }
                  function _(v, p) {
                    if (!(v instanceof p))
                      throw new TypeError("Cannot call a class as a function");
                  }
                  function E(v, p) {
                    for (var f = 0; f < p.length; f++) {
                      var d = p[f];
                      ((d.enumerable = d.enumerable || !1),
                        (d.configurable = !0),
                        "value" in d && (d.writable = !0),
                        Object.defineProperty(v, d.key, d));
                    }
                  }
                  function W(v, p, f) {
                    return (
                      p && E(v.prototype, p),
                      Object.defineProperty(v, "prototype", { writable: !1 }),
                      v
                    );
                  }
                  var A = (function () {
                    function v() {
                      (_(this, v),
                        (this.wave = null),
                        (this.waveCtx = null),
                        (this.progress = null),
                        (this.progressCtx = null),
                        (this.start = 0),
                        (this.end = 1),
                        (this.id = (0, R.default)(
                          typeof this.constructor.name < "u"
                            ? this.constructor.name.toLowerCase() + "_"
                            : "canvasentry_",
                        )),
                        (this.canvasContextAttributes = {}));
                    }
                    return (
                      W(v, [
                        {
                          key: "initWave",
                          value: function (f) {
                            ((this.wave = f),
                              (this.waveCtx = this.wave.getContext(
                                "2d",
                                this.canvasContextAttributes,
                              )));
                          },
                        },
                        {
                          key: "initProgress",
                          value: function (f) {
                            ((this.progress = f),
                              (this.progressCtx = this.progress.getContext(
                                "2d",
                                this.canvasContextAttributes,
                              )));
                          },
                        },
                        {
                          key: "updateDimensions",
                          value: function (f, d, P, M) {
                            ((this.start = this.wave.offsetLeft / d || 0),
                              (this.end = this.start + f / d),
                              (this.wave.width = P),
                              (this.wave.height = M));
                            var g = { width: f + "px" };
                            ((0, k.default)(this.wave, g),
                              this.hasProgressCanvas &&
                                ((this.progress.width = P),
                                (this.progress.height = M),
                                (0, k.default)(this.progress, g)));
                          },
                        },
                        {
                          key: "clearWave",
                          value: function () {
                            (this.waveCtx.clearRect(
                              0,
                              0,
                              this.waveCtx.canvas.width,
                              this.waveCtx.canvas.height,
                            ),
                              this.hasProgressCanvas &&
                                this.progressCtx.clearRect(
                                  0,
                                  0,
                                  this.progressCtx.canvas.width,
                                  this.progressCtx.canvas.height,
                                ));
                          },
                        },
                        {
                          key: "setFillStyles",
                          value: function (f, d) {
                            ((this.waveCtx.fillStyle = this.getFillStyle(
                              this.waveCtx,
                              f,
                            )),
                              this.hasProgressCanvas &&
                                (this.progressCtx.fillStyle = this.getFillStyle(
                                  this.progressCtx,
                                  d,
                                )));
                          },
                        },
                        {
                          key: "getFillStyle",
                          value: function (f, d) {
                            if (
                              typeof d == "string" ||
                              d instanceof CanvasGradient
                            )
                              return d;
                            var P = f.createLinearGradient(
                              0,
                              0,
                              0,
                              f.canvas.height,
                            );
                            return (
                              d.forEach(function (M, g) {
                                return P.addColorStop(g / d.length, M);
                              }),
                              P
                            );
                          },
                        },
                        {
                          key: "applyCanvasTransforms",
                          value: function (f) {
                            f &&
                              (this.waveCtx.setTransform(0, 1, 1, 0, 0, 0),
                              this.hasProgressCanvas &&
                                this.progressCtx.setTransform(
                                  0,
                                  1,
                                  1,
                                  0,
                                  0,
                                  0,
                                ));
                          },
                        },
                        {
                          key: "fillRects",
                          value: function (f, d, P, M, g) {
                            (this.fillRectToContext(
                              this.waveCtx,
                              f,
                              d,
                              P,
                              M,
                              g,
                            ),
                              this.hasProgressCanvas &&
                                this.fillRectToContext(
                                  this.progressCtx,
                                  f,
                                  d,
                                  P,
                                  M,
                                  g,
                                ));
                          },
                        },
                        {
                          key: "fillRectToContext",
                          value: function (f, d, P, M, g, O) {
                            f &&
                              (O
                                ? this.drawRoundedRect(f, d, P, M, g, O)
                                : f.fillRect(d, P, M, g));
                          },
                        },
                        {
                          key: "drawRoundedRect",
                          value: function (f, d, P, M, g, O) {
                            g !== 0 &&
                              (g < 0 && ((g *= -1), (P -= g)),
                              f.beginPath(),
                              f.moveTo(d + O, P),
                              f.lineTo(d + M - O, P),
                              f.quadraticCurveTo(d + M, P, d + M, P + O),
                              f.lineTo(d + M, P + g - O),
                              f.quadraticCurveTo(
                                d + M,
                                P + g,
                                d + M - O,
                                P + g,
                              ),
                              f.lineTo(d + O, P + g),
                              f.quadraticCurveTo(d, P + g, d, P + g - O),
                              f.lineTo(d, P + O),
                              f.quadraticCurveTo(d, P, d + O, P),
                              f.closePath(),
                              f.fill());
                          },
                        },
                        {
                          key: "drawLines",
                          value: function (f, d, P, M, g, O) {
                            (this.drawLineToContext(
                              this.waveCtx,
                              f,
                              d,
                              P,
                              M,
                              g,
                              O,
                            ),
                              this.hasProgressCanvas &&
                                this.drawLineToContext(
                                  this.progressCtx,
                                  f,
                                  d,
                                  P,
                                  M,
                                  g,
                                  O,
                                ));
                          },
                        },
                        {
                          key: "drawLineToContext",
                          value: function (f, d, P, M, g, O, m) {
                            if (f) {
                              var h = d.length / 2,
                                y = Math.round(h * this.start),
                                l = Math.round(h * this.end) + 1,
                                n = y,
                                a = l,
                                o = this.wave.width / (a - n - 1),
                                r = M + g,
                                t = P / M;
                              (f.beginPath(),
                                f.moveTo((n - y) * o, r),
                                f.lineTo(
                                  (n - y) * o,
                                  r - Math.round((d[2 * n] || 0) / t),
                                ));
                              var s, i, e;
                              for (s = n; s < a; s++)
                                ((i = d[2 * s] || 0),
                                  (e = Math.round(i / t)),
                                  f.lineTo(
                                    (s - y) * o + this.halfPixel,
                                    r - e,
                                  ));
                              var u = a - 1;
                              for (u; u >= n; u--)
                                ((i = d[2 * u + 1] || 0),
                                  (e = Math.round(i / t)),
                                  f.lineTo(
                                    (u - y) * o + this.halfPixel,
                                    r - e,
                                  ));
                              (f.lineTo(
                                (n - y) * o,
                                r - Math.round((d[2 * n + 1] || 0) / t),
                              ),
                                f.closePath(),
                                f.fill());
                            }
                          },
                        },
                        {
                          key: "destroy",
                          value: function () {
                            ((this.waveCtx = null),
                              (this.wave = null),
                              (this.progressCtx = null),
                              (this.progress = null));
                          },
                        },
                        {
                          key: "getImage",
                          value: function (f, d, P) {
                            var M = this;
                            if (P === "blob")
                              return new Promise(function (g) {
                                M.wave.toBlob(g, f, d);
                              });
                            if (P === "dataURL")
                              return this.wave.toDataURL(f, d);
                          },
                        },
                      ]),
                      v
                    );
                  })();
                  ((c.default = A), (V.exports = c.default));
                },
                "./src/drawer.js": (V, c, w) => {
                  function k(m) {
                    "@babel/helpers - typeof";
                    return (
                      (k =
                        typeof Symbol == "function" &&
                        typeof Symbol.iterator == "symbol"
                          ? function (h) {
                              return typeof h;
                            }
                          : function (h) {
                              return h &&
                                typeof Symbol == "function" &&
                                h.constructor === Symbol &&
                                h !== Symbol.prototype
                                ? "symbol"
                                : typeof h;
                            }),
                      k(m)
                    );
                  }
                  (Object.defineProperty(c, "__esModule", { value: !0 }),
                    (c.default = void 0));
                  var R = _(w("./src/util/index.js"));
                  function C(m) {
                    if (typeof WeakMap != "function") return null;
                    var h = new WeakMap(),
                      y = new WeakMap();
                    return (C = function (n) {
                      return n ? y : h;
                    })(m);
                  }
                  function _(m, h) {
                    if (m && m.__esModule) return m;
                    if (
                      m === null ||
                      (k(m) !== "object" && typeof m != "function")
                    )
                      return { default: m };
                    var y = C(h);
                    if (y && y.has(m)) return y.get(m);
                    var l = {},
                      n =
                        Object.defineProperty &&
                        Object.getOwnPropertyDescriptor;
                    for (var a in m)
                      if (
                        a !== "default" &&
                        Object.prototype.hasOwnProperty.call(m, a)
                      ) {
                        var o = n
                          ? Object.getOwnPropertyDescriptor(m, a)
                          : null;
                        o && (o.get || o.set)
                          ? Object.defineProperty(l, a, o)
                          : (l[a] = m[a]);
                      }
                    return ((l.default = m), y && y.set(m, l), l);
                  }
                  function E(m, h) {
                    if (!(m instanceof h))
                      throw new TypeError("Cannot call a class as a function");
                  }
                  function W(m, h) {
                    for (var y = 0; y < h.length; y++) {
                      var l = h[y];
                      ((l.enumerable = l.enumerable || !1),
                        (l.configurable = !0),
                        "value" in l && (l.writable = !0),
                        Object.defineProperty(m, l.key, l));
                    }
                  }
                  function A(m, h, y) {
                    return (
                      h && W(m.prototype, h),
                      Object.defineProperty(m, "prototype", { writable: !1 }),
                      m
                    );
                  }
                  function v(m, h) {
                    if (typeof h != "function" && h !== null)
                      throw new TypeError(
                        "Super expression must either be null or a function",
                      );
                    ((m.prototype = Object.create(h && h.prototype, {
                      constructor: { value: m, writable: !0, configurable: !0 },
                    })),
                      Object.defineProperty(m, "prototype", { writable: !1 }),
                      h && p(m, h));
                  }
                  function p(m, h) {
                    return (
                      (p =
                        Object.setPrototypeOf ||
                        function (l, n) {
                          return ((l.__proto__ = n), l);
                        }),
                      p(m, h)
                    );
                  }
                  function f(m) {
                    var h = M();
                    return function () {
                      var l = g(m),
                        n;
                      if (h) {
                        var a = g(this).constructor;
                        n = Reflect.construct(l, arguments, a);
                      } else n = l.apply(this, arguments);
                      return d(this, n);
                    };
                  }
                  function d(m, h) {
                    if (h && (k(h) === "object" || typeof h == "function"))
                      return h;
                    if (h !== void 0)
                      throw new TypeError(
                        "Derived constructors may only return object or undefined",
                      );
                    return P(m);
                  }
                  function P(m) {
                    if (m === void 0)
                      throw new ReferenceError(
                        "this hasn't been initialised - super() hasn't been called",
                      );
                    return m;
                  }
                  function M() {
                    if (
                      typeof Reflect > "u" ||
                      !Reflect.construct ||
                      Reflect.construct.sham
                    )
                      return !1;
                    if (typeof Proxy == "function") return !0;
                    try {
                      return (
                        Boolean.prototype.valueOf.call(
                          Reflect.construct(Boolean, [], function () {}),
                        ),
                        !0
                      );
                    } catch {
                      return !1;
                    }
                  }
                  function g(m) {
                    return (
                      (g = Object.setPrototypeOf
                        ? Object.getPrototypeOf
                        : function (y) {
                            return y.__proto__ || Object.getPrototypeOf(y);
                          }),
                      g(m)
                    );
                  }
                  var O = (function (m) {
                    v(y, m);
                    var h = f(y);
                    function y(l, n) {
                      var a;
                      return (
                        E(this, y),
                        (a = h.call(this)),
                        (a.container = R.withOrientation(l, n.vertical)),
                        (a.params = n),
                        (a.width = 0),
                        (a.height = n.height * a.params.pixelRatio),
                        (a.lastPos = 0),
                        (a.wrapper = null),
                        a
                      );
                    }
                    return (
                      A(y, [
                        {
                          key: "style",
                          value: function (n, a) {
                            return R.style(n, a);
                          },
                        },
                        {
                          key: "createWrapper",
                          value: function () {
                            ((this.wrapper = R.withOrientation(
                              this.container.appendChild(
                                document.createElement("wave"),
                              ),
                              this.params.vertical,
                            )),
                              this.style(this.wrapper, {
                                display: "block",
                                position: "relative",
                                userSelect: "none",
                                webkitUserSelect: "none",
                                height: this.params.height + "px",
                              }),
                              (this.params.fillParent ||
                                this.params.scrollParent) &&
                                this.style(this.wrapper, {
                                  width: "100%",
                                  cursor: this.params.hideCursor
                                    ? "none"
                                    : "auto",
                                  overflowX: this.params.hideScrollbar
                                    ? "hidden"
                                    : "auto",
                                  overflowY: "hidden",
                                }),
                              this.setupWrapperEvents());
                          },
                        },
                        {
                          key: "handleEvent",
                          value: function (n, a) {
                            !a && n.preventDefault();
                            var o = R.withOrientation(
                                n.targetTouches ? n.targetTouches[0] : n,
                                this.params.vertical,
                              ).clientX,
                              r = this.wrapper.getBoundingClientRect(),
                              t = this.width,
                              s = this.getWidth(),
                              i = this.getProgressPixels(r, o),
                              e;
                            return (
                              !this.params.fillParent && t < s
                                ? (e = i * (this.params.pixelRatio / t) || 0)
                                : (e =
                                    (i + this.wrapper.scrollLeft) /
                                      this.wrapper.scrollWidth || 0),
                              R.clamp(e, 0, 1)
                            );
                          },
                        },
                        {
                          key: "getProgressPixels",
                          value: function (n, a) {
                            return this.params.rtl ? n.right - a : a - n.left;
                          },
                        },
                        {
                          key: "setupWrapperEvents",
                          value: function () {
                            var n = this;
                            (this.wrapper.addEventListener(
                              "click",
                              function (a) {
                                var o = R.withOrientation(a, n.params.vertical),
                                  r =
                                    n.wrapper.offsetHeight -
                                    n.wrapper.clientHeight;
                                if (r !== 0) {
                                  var t = n.wrapper.getBoundingClientRect();
                                  if (o.clientY >= t.bottom - r) return;
                                }
                                n.params.interact &&
                                  n.fireEvent("click", a, n.handleEvent(a));
                              },
                            ),
                              this.wrapper.addEventListener(
                                "dblclick",
                                function (a) {
                                  n.params.interact &&
                                    n.fireEvent(
                                      "dblclick",
                                      a,
                                      n.handleEvent(a),
                                    );
                                },
                              ),
                              this.wrapper.addEventListener(
                                "scroll",
                                function (a) {
                                  return n.fireEvent("scroll", a);
                                },
                              ));
                          },
                        },
                        {
                          key: "drawPeaks",
                          value: function (n, a, o, r) {
                            (this.setWidth(a) || this.clearWave(),
                              this.params.barWidth
                                ? this.drawBars(n, 0, o, r)
                                : this.drawWave(n, 0, o, r));
                          },
                        },
                        {
                          key: "resetScroll",
                          value: function () {
                            this.wrapper !== null &&
                              (this.wrapper.scrollLeft = 0);
                          },
                        },
                        {
                          key: "recenter",
                          value: function (n) {
                            var a = this.wrapper.scrollWidth * n;
                            this.recenterOnPosition(a, !0);
                          },
                        },
                        {
                          key: "recenterOnPosition",
                          value: function (n, a) {
                            var o = this.wrapper.scrollLeft,
                              r = ~~(this.wrapper.clientWidth / 2),
                              t =
                                this.wrapper.scrollWidth -
                                this.wrapper.clientWidth,
                              s = n - r,
                              i = s - o;
                            if (t != 0) {
                              if (!a && -r <= i && i < r) {
                                var e = this.params.autoCenterRate;
                                ((e /= r),
                                  (e *= t),
                                  (i = Math.max(-e, Math.min(e, i))),
                                  (s = o + i));
                              }
                              ((s = Math.max(0, Math.min(t, s))),
                                s != o && (this.wrapper.scrollLeft = s));
                            }
                          },
                        },
                        {
                          key: "getScrollX",
                          value: function () {
                            var n = 0;
                            if (this.wrapper) {
                              var a = this.params.pixelRatio;
                              if (
                                ((n = Math.round(this.wrapper.scrollLeft * a)),
                                this.params.scrollParent)
                              ) {
                                var o = ~~(
                                  this.wrapper.scrollWidth * a -
                                  this.getWidth()
                                );
                                n = Math.min(o, Math.max(0, n));
                              }
                            }
                            return n;
                          },
                        },
                        {
                          key: "getWidth",
                          value: function () {
                            return Math.round(
                              this.container.clientWidth *
                                this.params.pixelRatio,
                            );
                          },
                        },
                        {
                          key: "setWidth",
                          value: function (n) {
                            if (this.width == n) return !1;
                            if (
                              ((this.width = n),
                              this.params.fillParent ||
                                this.params.scrollParent)
                            )
                              this.style(this.wrapper, { width: "" });
                            else {
                              var a =
                                ~~(this.width / this.params.pixelRatio) + "px";
                              this.style(this.wrapper, { width: a });
                            }
                            return (this.updateSize(), !0);
                          },
                        },
                        {
                          key: "setHeight",
                          value: function (n) {
                            return n == this.height
                              ? !1
                              : ((this.height = n),
                                this.style(this.wrapper, {
                                  height:
                                    ~~(this.height / this.params.pixelRatio) +
                                    "px",
                                }),
                                this.updateSize(),
                                !0);
                          },
                        },
                        {
                          key: "progress",
                          value: function (n) {
                            var a = 1 / this.params.pixelRatio,
                              o = Math.round(n * this.width) * a;
                            if (o < this.lastPos || o - this.lastPos >= a) {
                              if (
                                ((this.lastPos = o),
                                this.params.scrollParent &&
                                  this.params.autoCenter)
                              ) {
                                var r = ~~(this.wrapper.scrollWidth * n);
                                this.recenterOnPosition(
                                  r,
                                  this.params.autoCenterImmediately,
                                );
                              }
                              this.updateProgress(o);
                            }
                          },
                        },
                        {
                          key: "destroy",
                          value: function () {
                            (this.unAll(),
                              this.wrapper &&
                                (this.wrapper.parentNode ==
                                  this.container.domElement &&
                                  this.container.removeChild(
                                    this.wrapper.domElement,
                                  ),
                                (this.wrapper = null)));
                          },
                        },
                        { key: "updateCursor", value: function () {} },
                        { key: "updateSize", value: function () {} },
                        { key: "drawBars", value: function (n, a, o, r) {} },
                        { key: "drawWave", value: function (n, a, o, r) {} },
                        { key: "clearWave", value: function () {} },
                        { key: "updateProgress", value: function (n) {} },
                      ]),
                      y
                    );
                  })(R.Observer);
                  ((c.default = O), (V.exports = c.default));
                },
                "./src/drawer.multicanvas.js": (V, c, w) => {
                  function k(l) {
                    "@babel/helpers - typeof";
                    return (
                      (k =
                        typeof Symbol == "function" &&
                        typeof Symbol.iterator == "symbol"
                          ? function (n) {
                              return typeof n;
                            }
                          : function (n) {
                              return n &&
                                typeof Symbol == "function" &&
                                n.constructor === Symbol &&
                                n !== Symbol.prototype
                                ? "symbol"
                                : typeof n;
                            }),
                      k(l)
                    );
                  }
                  (Object.defineProperty(c, "__esModule", { value: !0 }),
                    (c.default = void 0));
                  var R = A(w("./src/drawer.js")),
                    C = W(w("./src/util/index.js")),
                    _ = A(w("./src/drawer.canvasentry.js"));
                  function E(l) {
                    if (typeof WeakMap != "function") return null;
                    var n = new WeakMap(),
                      a = new WeakMap();
                    return (E = function (r) {
                      return r ? a : n;
                    })(l);
                  }
                  function W(l, n) {
                    if (l && l.__esModule) return l;
                    if (
                      l === null ||
                      (k(l) !== "object" && typeof l != "function")
                    )
                      return { default: l };
                    var a = E(n);
                    if (a && a.has(l)) return a.get(l);
                    var o = {},
                      r =
                        Object.defineProperty &&
                        Object.getOwnPropertyDescriptor;
                    for (var t in l)
                      if (
                        t !== "default" &&
                        Object.prototype.hasOwnProperty.call(l, t)
                      ) {
                        var s = r
                          ? Object.getOwnPropertyDescriptor(l, t)
                          : null;
                        s && (s.get || s.set)
                          ? Object.defineProperty(o, t, s)
                          : (o[t] = l[t]);
                      }
                    return ((o.default = l), a && a.set(l, o), o);
                  }
                  function A(l) {
                    return l && l.__esModule ? l : { default: l };
                  }
                  function v(l, n) {
                    if (!(l instanceof n))
                      throw new TypeError("Cannot call a class as a function");
                  }
                  function p(l, n) {
                    for (var a = 0; a < n.length; a++) {
                      var o = n[a];
                      ((o.enumerable = o.enumerable || !1),
                        (o.configurable = !0),
                        "value" in o && (o.writable = !0),
                        Object.defineProperty(l, o.key, o));
                    }
                  }
                  function f(l, n, a) {
                    return (
                      n && p(l.prototype, n),
                      Object.defineProperty(l, "prototype", { writable: !1 }),
                      l
                    );
                  }
                  function d(l, n) {
                    if (typeof n != "function" && n !== null)
                      throw new TypeError(
                        "Super expression must either be null or a function",
                      );
                    ((l.prototype = Object.create(n && n.prototype, {
                      constructor: { value: l, writable: !0, configurable: !0 },
                    })),
                      Object.defineProperty(l, "prototype", { writable: !1 }),
                      n && P(l, n));
                  }
                  function P(l, n) {
                    return (
                      (P =
                        Object.setPrototypeOf ||
                        function (o, r) {
                          return ((o.__proto__ = r), o);
                        }),
                      P(l, n)
                    );
                  }
                  function M(l) {
                    var n = m();
                    return function () {
                      var o = h(l),
                        r;
                      if (n) {
                        var t = h(this).constructor;
                        r = Reflect.construct(o, arguments, t);
                      } else r = o.apply(this, arguments);
                      return g(this, r);
                    };
                  }
                  function g(l, n) {
                    if (n && (k(n) === "object" || typeof n == "function"))
                      return n;
                    if (n !== void 0)
                      throw new TypeError(
                        "Derived constructors may only return object or undefined",
                      );
                    return O(l);
                  }
                  function O(l) {
                    if (l === void 0)
                      throw new ReferenceError(
                        "this hasn't been initialised - super() hasn't been called",
                      );
                    return l;
                  }
                  function m() {
                    if (
                      typeof Reflect > "u" ||
                      !Reflect.construct ||
                      Reflect.construct.sham
                    )
                      return !1;
                    if (typeof Proxy == "function") return !0;
                    try {
                      return (
                        Boolean.prototype.valueOf.call(
                          Reflect.construct(Boolean, [], function () {}),
                        ),
                        !0
                      );
                    } catch {
                      return !1;
                    }
                  }
                  function h(l) {
                    return (
                      (h = Object.setPrototypeOf
                        ? Object.getPrototypeOf
                        : function (a) {
                            return a.__proto__ || Object.getPrototypeOf(a);
                          }),
                      h(l)
                    );
                  }
                  var y = (function (l) {
                    d(a, l);
                    var n = M(a);
                    function a(o, r) {
                      var t;
                      return (
                        v(this, a),
                        (t = n.call(this, o, r)),
                        (t.maxCanvasWidth = r.maxCanvasWidth),
                        (t.maxCanvasElementWidth = Math.round(
                          r.maxCanvasWidth / r.pixelRatio,
                        )),
                        (t.hasProgressCanvas = r.waveColor != r.progressColor),
                        (t.halfPixel = 0.5 / r.pixelRatio),
                        (t.canvases = []),
                        (t.progressWave = null),
                        (t.EntryClass = _.default),
                        (t.canvasContextAttributes =
                          r.drawingContextAttributes),
                        (t.overlap = 2 * Math.ceil(r.pixelRatio / 2)),
                        (t.barRadius = r.barRadius || 0),
                        (t.vertical = r.vertical),
                        t
                      );
                    }
                    return (
                      f(a, [
                        {
                          key: "init",
                          value: function () {
                            (this.createWrapper(), this.createElements());
                          },
                        },
                        {
                          key: "createElements",
                          value: function () {
                            ((this.progressWave = C.withOrientation(
                              this.wrapper.appendChild(
                                document.createElement("wave"),
                              ),
                              this.params.vertical,
                            )),
                              this.style(this.progressWave, {
                                position: "absolute",
                                zIndex: 3,
                                left: 0,
                                top: 0,
                                bottom: 0,
                                overflow: "hidden",
                                width: "0",
                                display: "none",
                                boxSizing: "border-box",
                                borderRightStyle: "solid",
                                pointerEvents: "none",
                              }),
                              this.addCanvas(),
                              this.updateCursor());
                          },
                        },
                        {
                          key: "updateCursor",
                          value: function () {
                            this.style(this.progressWave, {
                              borderRightWidth: this.params.cursorWidth + "px",
                              borderRightColor: this.params.cursorColor,
                            });
                          },
                        },
                        {
                          key: "updateSize",
                          value: function () {
                            for (
                              var r = this,
                                t = Math.round(
                                  this.width / this.params.pixelRatio,
                                ),
                                s = Math.ceil(
                                  t /
                                    (this.maxCanvasElementWidth + this.overlap),
                                );
                              this.canvases.length < s;
                            )
                              this.addCanvas();
                            for (; this.canvases.length > s;)
                              this.removeCanvas();
                            var i = this.maxCanvasWidth + this.overlap,
                              e = this.canvases.length - 1;
                            this.canvases.forEach(function (u, b) {
                              (b == e && (i = r.width - r.maxCanvasWidth * e),
                                r.updateDimensions(u, i, r.height),
                                u.clearWave());
                            });
                          },
                        },
                        {
                          key: "addCanvas",
                          value: function () {
                            var r = new this.EntryClass();
                            ((r.canvasContextAttributes =
                              this.canvasContextAttributes),
                              (r.hasProgressCanvas = this.hasProgressCanvas),
                              (r.halfPixel = this.halfPixel));
                            var t =
                                this.maxCanvasElementWidth *
                                this.canvases.length,
                              s = C.withOrientation(
                                this.wrapper.appendChild(
                                  document.createElement("canvas"),
                                ),
                                this.params.vertical,
                              );
                            if (
                              (this.style(s, {
                                position: "absolute",
                                zIndex: 2,
                                left: t + "px",
                                top: 0,
                                bottom: 0,
                                height: "100%",
                                pointerEvents: "none",
                              }),
                              r.initWave(s),
                              this.hasProgressCanvas)
                            ) {
                              var i = C.withOrientation(
                                this.progressWave.appendChild(
                                  document.createElement("canvas"),
                                ),
                                this.params.vertical,
                              );
                              (this.style(i, {
                                position: "absolute",
                                left: t + "px",
                                top: 0,
                                bottom: 0,
                                height: "100%",
                              }),
                                r.initProgress(i));
                            }
                            this.canvases.push(r);
                          },
                        },
                        {
                          key: "removeCanvas",
                          value: function () {
                            var r = this.canvases[this.canvases.length - 1];
                            (r.wave.parentElement.removeChild(
                              r.wave.domElement,
                            ),
                              this.hasProgressCanvas &&
                                r.progress.parentElement.removeChild(
                                  r.progress.domElement,
                                ),
                              r && (r.destroy(), (r = null)),
                              this.canvases.pop());
                          },
                        },
                        {
                          key: "updateDimensions",
                          value: function (r, t, s) {
                            var i = Math.round(t / this.params.pixelRatio),
                              e = Math.round(
                                this.width / this.params.pixelRatio,
                              );
                            (r.updateDimensions(i, e, t, s),
                              this.style(this.progressWave, {
                                display: "block",
                              }));
                          },
                        },
                        {
                          key: "clearWave",
                          value: function () {
                            var r = this;
                            C.frame(function () {
                              r.canvases.forEach(function (t) {
                                return t.clearWave();
                              });
                            })();
                          },
                        },
                        {
                          key: "drawBars",
                          value: function (r, t, s, i) {
                            var e = this;
                            return this.prepareDraw(r, t, s, i, function (u) {
                              var b = u.absmax,
                                T = u.hasMinVals;
                              u.height;
                              var S = u.offsetY,
                                D = u.halfH,
                                j = u.peaks,
                                x = u.channelIndex;
                              if (s !== void 0) {
                                var I = T ? 2 : 1,
                                  N = j.length / I,
                                  B = e.params.barWidth * e.params.pixelRatio,
                                  z =
                                    e.params.barGap === null
                                      ? Math.max(e.params.pixelRatio, ~~(B / 2))
                                      : Math.max(
                                          e.params.pixelRatio,
                                          e.params.barGap * e.params.pixelRatio,
                                        ),
                                  L = B + z,
                                  H = N / e.width,
                                  ne = s,
                                  ie = i,
                                  Q = ne;
                                for (Q; Q < ie; Q += L) {
                                  var $ = 0,
                                    K = Math.floor(Q * H) * I,
                                    ae = Math.floor((Q + L) * H) * I;
                                  do {
                                    var ee = Math.abs(j[K]);
                                    (ee > $ && ($ = ee), (K += I));
                                  } while (K < ae);
                                  var J = Math.round(($ / b) * D);
                                  (J == 0 &&
                                    e.params.barMinHeight &&
                                    (J = e.params.barMinHeight),
                                    e.fillRect(
                                      Q + e.halfPixel,
                                      D - J + S,
                                      B + e.halfPixel,
                                      J * 2,
                                      e.barRadius,
                                      x,
                                    ));
                                }
                              }
                            });
                          },
                        },
                        {
                          key: "drawWave",
                          value: function (r, t, s, i) {
                            var e = this;
                            return this.prepareDraw(r, t, s, i, function (u) {
                              var b = u.absmax,
                                T = u.hasMinVals;
                              u.height;
                              var S = u.offsetY,
                                D = u.halfH,
                                j = u.peaks,
                                x = u.channelIndex;
                              if (!T) {
                                var I = [],
                                  N = j.length,
                                  B = 0;
                                for (B; B < N; B++)
                                  ((I[2 * B] = j[B]), (I[2 * B + 1] = -j[B]));
                                j = I;
                              }
                              (s !== void 0 && e.drawLine(j, b, D, S, s, i, x),
                                e.fillRect(
                                  0,
                                  D + S - e.halfPixel,
                                  e.width,
                                  e.halfPixel,
                                  e.barRadius,
                                  x,
                                ));
                            });
                          },
                        },
                        {
                          key: "drawLine",
                          value: function (r, t, s, i, e, u, b) {
                            var T = this,
                              S =
                                this.params.splitChannelsOptions.channelColors[
                                  b
                                ] || {},
                              D = S.waveColor,
                              j = S.progressColor;
                            this.canvases.forEach(function (x, I) {
                              (T.setFillStyles(x, D, j),
                                T.applyCanvasTransforms(x, T.params.vertical),
                                x.drawLines(r, t, s, i, e, u));
                            });
                          },
                        },
                        {
                          key: "fillRect",
                          value: function (r, t, s, i, e, u) {
                            var b = Math.floor(r / this.maxCanvasWidth),
                              T = Math.min(
                                Math.ceil((r + s) / this.maxCanvasWidth) + 1,
                                this.canvases.length,
                              ),
                              S = b;
                            for (S; S < T; S++) {
                              var D = this.canvases[S],
                                j = S * this.maxCanvasWidth,
                                x = {
                                  x1: Math.max(r, S * this.maxCanvasWidth),
                                  y1: t,
                                  x2: Math.min(
                                    r + s,
                                    S * this.maxCanvasWidth + D.wave.width,
                                  ),
                                  y2: t + i,
                                };
                              if (x.x1 < x.x2) {
                                var I =
                                    this.params.splitChannelsOptions
                                      .channelColors[u] || {},
                                  N = I.waveColor,
                                  B = I.progressColor;
                                (this.setFillStyles(D, N, B),
                                  this.applyCanvasTransforms(
                                    D,
                                    this.params.vertical,
                                  ),
                                  D.fillRects(
                                    x.x1 - j,
                                    x.y1,
                                    x.x2 - x.x1,
                                    x.y2 - x.y1,
                                    e,
                                  ));
                              }
                            }
                          },
                        },
                        {
                          key: "hideChannel",
                          value: function (r) {
                            return (
                              this.params.splitChannels &&
                              this.params.splitChannelsOptions.filterChannels.includes(
                                r,
                              )
                            );
                          },
                        },
                        {
                          key: "prepareDraw",
                          value: function (r, t, s, i, e, u, b) {
                            var T = this;
                            return C.frame(function () {
                              if (r[0] instanceof Array) {
                                var S = r;
                                if (T.params.splitChannels) {
                                  var D = S.filter(function (L, H) {
                                    return !T.hideChannel(H);
                                  });
                                  T.params.splitChannelsOptions.overlay ||
                                    T.setHeight(
                                      Math.max(D.length, 1) *
                                        T.params.height *
                                        T.params.pixelRatio,
                                    );
                                  var j;
                                  return (
                                    T.params.splitChannelsOptions &&
                                      T.params.splitChannelsOptions
                                        .relativeNormalization &&
                                      (j = C.max(
                                        S.map(function (L) {
                                          return C.absMax(L);
                                        }),
                                      )),
                                    S.forEach(function (L, H) {
                                      return T.prepareDraw(
                                        L,
                                        H,
                                        s,
                                        i,
                                        e,
                                        D.indexOf(L),
                                        j,
                                      );
                                    })
                                  );
                                }
                                r = S[0];
                              }
                              if (!T.hideChannel(t)) {
                                var x = 1 / T.params.barHeight;
                                T.params.normalize &&
                                  (x = b === void 0 ? C.absMax(r) : b);
                                var I = [].some.call(r, function (L) {
                                    return L < 0;
                                  }),
                                  N = T.params.height * T.params.pixelRatio,
                                  B = N / 2,
                                  z = N * u || 0;
                                return (
                                  T.params.splitChannelsOptions &&
                                    T.params.splitChannelsOptions.overlay &&
                                    (z = 0),
                                  e({
                                    absmax: x,
                                    hasMinVals: I,
                                    height: N,
                                    offsetY: z,
                                    halfH: B,
                                    peaks: r,
                                    channelIndex: t,
                                  })
                                );
                              }
                            })();
                          },
                        },
                        {
                          key: "setFillStyles",
                          value: function (r) {
                            var t =
                                arguments.length > 1 && arguments[1] !== void 0
                                  ? arguments[1]
                                  : this.params.waveColor,
                              s =
                                arguments.length > 2 && arguments[2] !== void 0
                                  ? arguments[2]
                                  : this.params.progressColor;
                            r.setFillStyles(t, s);
                          },
                        },
                        {
                          key: "applyCanvasTransforms",
                          value: function (r) {
                            var t =
                              arguments.length > 1 && arguments[1] !== void 0
                                ? arguments[1]
                                : !1;
                            r.applyCanvasTransforms(t);
                          },
                        },
                        {
                          key: "getImage",
                          value: function (r, t, s) {
                            if (s === "blob")
                              return Promise.all(
                                this.canvases.map(function (e) {
                                  return e.getImage(r, t, s);
                                }),
                              );
                            if (s === "dataURL") {
                              var i = this.canvases.map(function (e) {
                                return e.getImage(r, t, s);
                              });
                              return i.length > 1 ? i : i[0];
                            }
                          },
                        },
                        {
                          key: "updateProgress",
                          value: function (r) {
                            this.style(this.progressWave, { width: r + "px" });
                          },
                        },
                      ]),
                      a
                    );
                  })(R.default);
                  ((c.default = y), (V.exports = c.default));
                },
                "./src/mediaelement-webaudio.js": (V, c, w) => {
                  function k(h) {
                    "@babel/helpers - typeof";
                    return (
                      (k =
                        typeof Symbol == "function" &&
                        typeof Symbol.iterator == "symbol"
                          ? function (y) {
                              return typeof y;
                            }
                          : function (y) {
                              return y &&
                                typeof Symbol == "function" &&
                                y.constructor === Symbol &&
                                y !== Symbol.prototype
                                ? "symbol"
                                : typeof y;
                            }),
                      k(h)
                    );
                  }
                  (Object.defineProperty(c, "__esModule", { value: !0 }),
                    (c.default = void 0));
                  var R = C(w("./src/mediaelement.js"));
                  function C(h) {
                    return h && h.__esModule ? h : { default: h };
                  }
                  function _(h, y) {
                    if (!(h instanceof y))
                      throw new TypeError("Cannot call a class as a function");
                  }
                  function E(h, y) {
                    for (var l = 0; l < y.length; l++) {
                      var n = y[l];
                      ((n.enumerable = n.enumerable || !1),
                        (n.configurable = !0),
                        "value" in n && (n.writable = !0),
                        Object.defineProperty(h, n.key, n));
                    }
                  }
                  function W(h, y, l) {
                    return (
                      y && E(h.prototype, y),
                      Object.defineProperty(h, "prototype", { writable: !1 }),
                      h
                    );
                  }
                  function A() {
                    return (
                      typeof Reflect < "u" && Reflect.get
                        ? (A = Reflect.get)
                        : (A = function (y, l, n) {
                            var a = v(y, l);
                            if (a) {
                              var o = Object.getOwnPropertyDescriptor(a, l);
                              return o.get
                                ? o.get.call(arguments.length < 3 ? y : n)
                                : o.value;
                            }
                          }),
                      A.apply(this, arguments)
                    );
                  }
                  function v(h, y) {
                    for (
                      ;
                      !Object.prototype.hasOwnProperty.call(h, y) &&
                      ((h = O(h)), h !== null);
                    );
                    return h;
                  }
                  function p(h, y) {
                    if (typeof y != "function" && y !== null)
                      throw new TypeError(
                        "Super expression must either be null or a function",
                      );
                    ((h.prototype = Object.create(y && y.prototype, {
                      constructor: { value: h, writable: !0, configurable: !0 },
                    })),
                      Object.defineProperty(h, "prototype", { writable: !1 }),
                      y && f(h, y));
                  }
                  function f(h, y) {
                    return (
                      (f =
                        Object.setPrototypeOf ||
                        function (n, a) {
                          return ((n.__proto__ = a), n);
                        }),
                      f(h, y)
                    );
                  }
                  function d(h) {
                    var y = g();
                    return function () {
                      var n = O(h),
                        a;
                      if (y) {
                        var o = O(this).constructor;
                        a = Reflect.construct(n, arguments, o);
                      } else a = n.apply(this, arguments);
                      return P(this, a);
                    };
                  }
                  function P(h, y) {
                    if (y && (k(y) === "object" || typeof y == "function"))
                      return y;
                    if (y !== void 0)
                      throw new TypeError(
                        "Derived constructors may only return object or undefined",
                      );
                    return M(h);
                  }
                  function M(h) {
                    if (h === void 0)
                      throw new ReferenceError(
                        "this hasn't been initialised - super() hasn't been called",
                      );
                    return h;
                  }
                  function g() {
                    if (
                      typeof Reflect > "u" ||
                      !Reflect.construct ||
                      Reflect.construct.sham
                    )
                      return !1;
                    if (typeof Proxy == "function") return !0;
                    try {
                      return (
                        Boolean.prototype.valueOf.call(
                          Reflect.construct(Boolean, [], function () {}),
                        ),
                        !0
                      );
                    } catch {
                      return !1;
                    }
                  }
                  function O(h) {
                    return (
                      (O = Object.setPrototypeOf
                        ? Object.getPrototypeOf
                        : function (l) {
                            return l.__proto__ || Object.getPrototypeOf(l);
                          }),
                      O(h)
                    );
                  }
                  var m = (function (h) {
                    p(l, h);
                    var y = d(l);
                    function l(n) {
                      var a;
                      return (
                        _(this, l),
                        (a = y.call(this, n)),
                        (a.params = n),
                        (a.sourceMediaElement = null),
                        a
                      );
                    }
                    return (
                      W(l, [
                        {
                          key: "init",
                          value: function () {
                            (this.setPlaybackRate(this.params.audioRate),
                              this.createTimer(),
                              this.createVolumeNode(),
                              this.createScriptNode(),
                              this.createAnalyserNode());
                          },
                        },
                        {
                          key: "_load",
                          value: function (a, o, r) {
                            (A(O(l.prototype), "_load", this).call(
                              this,
                              a,
                              o,
                              r,
                            ),
                              a.constructor.name !== "OGVPlayer" &&
                                this.createMediaElementSource(a));
                          },
                        },
                        {
                          key: "createMediaElementSource",
                          value: function (a) {
                            ((this.sourceMediaElement =
                              this.ac.createMediaElementSource(a)),
                              this.sourceMediaElement.connect(this.analyser));
                          },
                        },
                        {
                          key: "play",
                          value: function (a, o) {
                            return (
                              this.resumeAudioContext(),
                              A(O(l.prototype), "play", this).call(this, a, o)
                            );
                          },
                        },
                        {
                          key: "destroy",
                          value: function () {
                            (A(O(l.prototype), "destroy", this).call(this),
                              this.destroyWebAudio());
                          },
                        },
                      ]),
                      l
                    );
                  })(R.default);
                  ((c.default = m), (V.exports = c.default));
                },
                "./src/mediaelement.js": (V, c, w) => {
                  function k(n) {
                    "@babel/helpers - typeof";
                    return (
                      (k =
                        typeof Symbol == "function" &&
                        typeof Symbol.iterator == "symbol"
                          ? function (a) {
                              return typeof a;
                            }
                          : function (a) {
                              return a &&
                                typeof Symbol == "function" &&
                                a.constructor === Symbol &&
                                a !== Symbol.prototype
                                ? "symbol"
                                : typeof a;
                            }),
                      k(n)
                    );
                  }
                  (Object.defineProperty(c, "__esModule", { value: !0 }),
                    (c.default = void 0));
                  var R = W(w("./src/webaudio.js")),
                    C = E(w("./src/util/index.js"));
                  function _(n) {
                    if (typeof WeakMap != "function") return null;
                    var a = new WeakMap(),
                      o = new WeakMap();
                    return (_ = function (t) {
                      return t ? o : a;
                    })(n);
                  }
                  function E(n, a) {
                    if (n && n.__esModule) return n;
                    if (
                      n === null ||
                      (k(n) !== "object" && typeof n != "function")
                    )
                      return { default: n };
                    var o = _(a);
                    if (o && o.has(n)) return o.get(n);
                    var r = {},
                      t =
                        Object.defineProperty &&
                        Object.getOwnPropertyDescriptor;
                    for (var s in n)
                      if (
                        s !== "default" &&
                        Object.prototype.hasOwnProperty.call(n, s)
                      ) {
                        var i = t
                          ? Object.getOwnPropertyDescriptor(n, s)
                          : null;
                        i && (i.get || i.set)
                          ? Object.defineProperty(r, s, i)
                          : (r[s] = n[s]);
                      }
                    return ((r.default = n), o && o.set(n, r), r);
                  }
                  function W(n) {
                    return n && n.__esModule ? n : { default: n };
                  }
                  function A(n, a) {
                    if (!(n instanceof a))
                      throw new TypeError("Cannot call a class as a function");
                  }
                  function v(n, a) {
                    for (var o = 0; o < a.length; o++) {
                      var r = a[o];
                      ((r.enumerable = r.enumerable || !1),
                        (r.configurable = !0),
                        "value" in r && (r.writable = !0),
                        Object.defineProperty(n, r.key, r));
                    }
                  }
                  function p(n, a, o) {
                    return (
                      a && v(n.prototype, a),
                      Object.defineProperty(n, "prototype", { writable: !1 }),
                      n
                    );
                  }
                  function f() {
                    return (
                      typeof Reflect < "u" && Reflect.get
                        ? (f = Reflect.get)
                        : (f = function (a, o, r) {
                            var t = d(a, o);
                            if (t) {
                              var s = Object.getOwnPropertyDescriptor(t, o);
                              return s.get
                                ? s.get.call(arguments.length < 3 ? a : r)
                                : s.value;
                            }
                          }),
                      f.apply(this, arguments)
                    );
                  }
                  function d(n, a) {
                    for (
                      ;
                      !Object.prototype.hasOwnProperty.call(n, a) &&
                      ((n = y(n)), n !== null);
                    );
                    return n;
                  }
                  function P(n, a) {
                    if (typeof a != "function" && a !== null)
                      throw new TypeError(
                        "Super expression must either be null or a function",
                      );
                    ((n.prototype = Object.create(a && a.prototype, {
                      constructor: { value: n, writable: !0, configurable: !0 },
                    })),
                      Object.defineProperty(n, "prototype", { writable: !1 }),
                      a && M(n, a));
                  }
                  function M(n, a) {
                    return (
                      (M =
                        Object.setPrototypeOf ||
                        function (r, t) {
                          return ((r.__proto__ = t), r);
                        }),
                      M(n, a)
                    );
                  }
                  function g(n) {
                    var a = h();
                    return function () {
                      var r = y(n),
                        t;
                      if (a) {
                        var s = y(this).constructor;
                        t = Reflect.construct(r, arguments, s);
                      } else t = r.apply(this, arguments);
                      return O(this, t);
                    };
                  }
                  function O(n, a) {
                    if (a && (k(a) === "object" || typeof a == "function"))
                      return a;
                    if (a !== void 0)
                      throw new TypeError(
                        "Derived constructors may only return object or undefined",
                      );
                    return m(n);
                  }
                  function m(n) {
                    if (n === void 0)
                      throw new ReferenceError(
                        "this hasn't been initialised - super() hasn't been called",
                      );
                    return n;
                  }
                  function h() {
                    if (
                      typeof Reflect > "u" ||
                      !Reflect.construct ||
                      Reflect.construct.sham
                    )
                      return !1;
                    if (typeof Proxy == "function") return !0;
                    try {
                      return (
                        Boolean.prototype.valueOf.call(
                          Reflect.construct(Boolean, [], function () {}),
                        ),
                        !0
                      );
                    } catch {
                      return !1;
                    }
                  }
                  function y(n) {
                    return (
                      (y = Object.setPrototypeOf
                        ? Object.getPrototypeOf
                        : function (o) {
                            return o.__proto__ || Object.getPrototypeOf(o);
                          }),
                      y(n)
                    );
                  }
                  var l = (function (n) {
                    P(o, n);
                    var a = g(o);
                    function o(r) {
                      var t;
                      return (
                        A(this, o),
                        (t = a.call(this, r)),
                        (t.params = r),
                        (t.media = {
                          currentTime: 0,
                          duration: 0,
                          paused: !0,
                          playbackRate: 1,
                          play: function () {},
                          pause: function () {},
                          volume: 0,
                        }),
                        (t.mediaType = r.mediaType.toLowerCase()),
                        (t.elementPosition = r.elementPosition),
                        (t.peaks = null),
                        (t.playbackRate = 1),
                        (t.volume = 1),
                        (t.isMuted = !1),
                        (t.buffer = null),
                        (t.onPlayEnd = null),
                        (t.mediaListeners = {}),
                        t
                      );
                    }
                    return (
                      p(o, [
                        {
                          key: "init",
                          value: function () {
                            (this.setPlaybackRate(this.params.audioRate),
                              this.createTimer());
                          },
                        },
                        {
                          key: "_setupMediaListeners",
                          value: function () {
                            var t = this;
                            ((this.mediaListeners.error = function () {
                              t.fireEvent(
                                "error",
                                "Error loading media element",
                              );
                            }),
                              (this.mediaListeners.canplay = function () {
                                t.fireEvent("canplay");
                              }),
                              (this.mediaListeners.ended = function () {
                                t.fireEvent("finish");
                              }),
                              (this.mediaListeners.play = function () {
                                t.fireEvent("play");
                              }),
                              (this.mediaListeners.pause = function () {
                                t.fireEvent("pause");
                              }),
                              (this.mediaListeners.seeked = function (s) {
                                t.fireEvent("seek");
                              }),
                              (this.mediaListeners.volumechange = function (s) {
                                ((t.isMuted = t.media.muted),
                                  t.isMuted
                                    ? (t.volume = 0)
                                    : (t.volume = t.media.volume),
                                  t.fireEvent("volume"));
                              }),
                              Object.keys(this.mediaListeners).forEach(
                                function (s) {
                                  (t.media.removeEventListener(
                                    s,
                                    t.mediaListeners[s],
                                  ),
                                    t.media.addEventListener(
                                      s,
                                      t.mediaListeners[s],
                                    ));
                                },
                              ));
                          },
                        },
                        {
                          key: "createTimer",
                          value: function () {
                            var t = this,
                              s = function i() {
                                t.isPaused() ||
                                  (t.fireEvent(
                                    "audioprocess",
                                    t.getCurrentTime(),
                                  ),
                                  C.frame(i)());
                              };
                            (this.on("play", s),
                              this.on("pause", function () {
                                t.fireEvent("audioprocess", t.getCurrentTime());
                              }));
                          },
                        },
                        {
                          key: "load",
                          value: function (t, s, i, e) {
                            var u = document.createElement(this.mediaType);
                            ((u.controls = this.params.mediaControls),
                              (u.autoplay = this.params.autoplay || !1),
                              (u.preload = e ?? "auto"),
                              (u.src = t),
                              (u.style.width = "100%"));
                            var b = s.querySelector(this.mediaType);
                            (b && s.removeChild(b),
                              s.appendChild(u),
                              this._load(u, i, e));
                          },
                        },
                        {
                          key: "loadElt",
                          value: function (t, s) {
                            ((t.controls = this.params.mediaControls),
                              (t.autoplay = this.params.autoplay || !1),
                              this._load(t, s, t.preload));
                          },
                        },
                        {
                          key: "_load",
                          value: function (t, s, i) {
                            (typeof t.load == "function" &&
                              !(s && i == "none") &&
                              t.load(),
                              (this.media = t),
                              this._setupMediaListeners(),
                              (this.peaks = s),
                              (this.onPlayEnd = null),
                              (this.buffer = null),
                              (this.isMuted = t.muted),
                              this.setPlaybackRate(this.playbackRate),
                              this.setVolume(this.volume));
                          },
                        },
                        {
                          key: "isPaused",
                          value: function () {
                            return !this.media || this.media.paused;
                          },
                        },
                        {
                          key: "getDuration",
                          value: function () {
                            if (this.explicitDuration)
                              return this.explicitDuration;
                            var t = (this.buffer || this.media).duration;
                            return (
                              t >= 1 / 0 && (t = this.media.seekable.end(0)),
                              t
                            );
                          },
                        },
                        {
                          key: "getCurrentTime",
                          value: function () {
                            return this.media && this.media.currentTime;
                          },
                        },
                        {
                          key: "getPlayedPercents",
                          value: function () {
                            return (
                              this.getCurrentTime() / this.getDuration() || 0
                            );
                          },
                        },
                        {
                          key: "getPlaybackRate",
                          value: function () {
                            return this.playbackRate || this.media.playbackRate;
                          },
                        },
                        {
                          key: "setPlaybackRate",
                          value: function (t) {
                            ((this.playbackRate = t || 1),
                              (this.media.playbackRate = this.playbackRate));
                          },
                        },
                        {
                          key: "seekTo",
                          value: function (t) {
                            (t != null &&
                              !isNaN(t) &&
                              (this.media.currentTime = t),
                              this.clearPlayEnd());
                          },
                        },
                        {
                          key: "play",
                          value: function (t, s) {
                            this.seekTo(t);
                            var i = this.media.play();
                            return (s && this.setPlayEnd(s), i);
                          },
                        },
                        {
                          key: "pause",
                          value: function () {
                            var t;
                            return (
                              this.media && (t = this.media.pause()),
                              this.clearPlayEnd(),
                              t
                            );
                          },
                        },
                        {
                          key: "setPlayEnd",
                          value: function (t) {
                            var s = this;
                            (this.clearPlayEnd(),
                              (this._onPlayEnd = function (i) {
                                i >= t && (s.pause(), s.seekTo(t));
                              }),
                              this.on("audioprocess", this._onPlayEnd));
                          },
                        },
                        {
                          key: "clearPlayEnd",
                          value: function () {
                            this._onPlayEnd &&
                              (this.un("audioprocess", this._onPlayEnd),
                              (this._onPlayEnd = null));
                          },
                        },
                        {
                          key: "getPeaks",
                          value: function (t, s, i) {
                            return this.buffer
                              ? f(y(o.prototype), "getPeaks", this).call(
                                  this,
                                  t,
                                  s,
                                  i,
                                )
                              : this.peaks || [];
                          },
                        },
                        {
                          key: "setSinkId",
                          value: function (t) {
                            return t
                              ? this.media.setSinkId
                                ? this.media.setSinkId(t)
                                : Promise.reject(
                                    new Error(
                                      "setSinkId is not supported in your browser",
                                    ),
                                  )
                              : Promise.reject(
                                  new Error("Invalid deviceId: " + t),
                                );
                          },
                        },
                        {
                          key: "getVolume",
                          value: function () {
                            return this.volume;
                          },
                        },
                        {
                          key: "setVolume",
                          value: function (t) {
                            ((this.volume = t),
                              this.media.volume !== this.volume &&
                                (this.media.volume = this.volume));
                          },
                        },
                        {
                          key: "setMute",
                          value: function (t) {
                            this.isMuted = this.media.muted = t;
                          },
                        },
                        {
                          key: "destroy",
                          value: function () {
                            var t = this;
                            (this.pause(),
                              this.unAll(),
                              (this.destroyed = !0),
                              Object.keys(this.mediaListeners).forEach(
                                function (s) {
                                  t.media &&
                                    t.media.removeEventListener(
                                      s,
                                      t.mediaListeners[s],
                                    );
                                },
                              ),
                              this.params.removeMediaElementOnDestroy &&
                                this.media &&
                                this.media.parentNode &&
                                this.media.parentNode.removeChild(this.media),
                              (this.media = null));
                          },
                        },
                      ]),
                      o
                    );
                  })(R.default);
                  ((c.default = l), (V.exports = c.default));
                },
                "./src/peakcache.js": (V, c) => {
                  (Object.defineProperty(c, "__esModule", { value: !0 }),
                    (c.default = void 0));
                  function w(_, E) {
                    if (!(_ instanceof E))
                      throw new TypeError("Cannot call a class as a function");
                  }
                  function k(_, E) {
                    for (var W = 0; W < E.length; W++) {
                      var A = E[W];
                      ((A.enumerable = A.enumerable || !1),
                        (A.configurable = !0),
                        "value" in A && (A.writable = !0),
                        Object.defineProperty(_, A.key, A));
                    }
                  }
                  function R(_, E, W) {
                    return (
                      E && k(_.prototype, E),
                      Object.defineProperty(_, "prototype", { writable: !1 }),
                      _
                    );
                  }
                  var C = (function () {
                    function _() {
                      (w(this, _), this.clearPeakCache());
                    }
                    return (
                      R(_, [
                        {
                          key: "clearPeakCache",
                          value: function () {
                            ((this.peakCacheRanges = []),
                              (this.peakCacheLength = -1));
                          },
                        },
                        {
                          key: "addRangeToPeakCache",
                          value: function (W, A, v) {
                            W != this.peakCacheLength &&
                              (this.clearPeakCache(),
                              (this.peakCacheLength = W));
                            for (
                              var p = [], f = 0;
                              f < this.peakCacheRanges.length &&
                              this.peakCacheRanges[f] < A;
                            )
                              f++;
                            for (
                              f % 2 == 0 && p.push(A);
                              f < this.peakCacheRanges.length &&
                              this.peakCacheRanges[f] <= v;
                            )
                              (p.push(this.peakCacheRanges[f]), f++);
                            (f % 2 == 0 && p.push(v),
                              (p = p.filter(function (P, M, g) {
                                return M == 0
                                  ? P != g[M + 1]
                                  : M == g.length - 1
                                    ? P != g[M - 1]
                                    : P != g[M - 1] && P != g[M + 1];
                              })),
                              (this.peakCacheRanges =
                                this.peakCacheRanges.concat(p)),
                              (this.peakCacheRanges = this.peakCacheRanges
                                .sort(function (P, M) {
                                  return P - M;
                                })
                                .filter(function (P, M, g) {
                                  return M == 0
                                    ? P != g[M + 1]
                                    : M == g.length - 1
                                      ? P != g[M - 1]
                                      : P != g[M - 1] && P != g[M + 1];
                                })));
                            var d = [];
                            for (f = 0; f < p.length; f += 2)
                              d.push([p[f], p[f + 1]]);
                            return d;
                          },
                        },
                        {
                          key: "getCacheRanges",
                          value: function () {
                            var W = [],
                              A;
                            for (A = 0; A < this.peakCacheRanges.length; A += 2)
                              W.push([
                                this.peakCacheRanges[A],
                                this.peakCacheRanges[A + 1],
                              ]);
                            return W;
                          },
                        },
                      ]),
                      _
                    );
                  })();
                  ((c.default = C), (V.exports = c.default));
                },
                "./src/util/absMax.js": (V, c, w) => {
                  (Object.defineProperty(c, "__esModule", { value: !0 }),
                    (c.default = _));
                  var k = C(w("./src/util/max.js")),
                    R = C(w("./src/util/min.js"));
                  function C(E) {
                    return E && E.__esModule ? E : { default: E };
                  }
                  function _(E) {
                    var W = (0, k.default)(E),
                      A = (0, R.default)(E);
                    return -A > W ? -A : W;
                  }
                  V.exports = c.default;
                },
                "./src/util/clamp.js": (V, c) => {
                  (Object.defineProperty(c, "__esModule", { value: !0 }),
                    (c.default = w));
                  function w(k, R, C) {
                    return Math.min(Math.max(R, k), C);
                  }
                  V.exports = c.default;
                },
                "./src/util/fetch.js": (V, c, w) => {
                  (Object.defineProperty(c, "__esModule", { value: !0 }),
                    (c.default = A));
                  var k = R(w("./src/util/observer.js"));
                  function R(v) {
                    return v && v.__esModule ? v : { default: v };
                  }
                  function C(v, p) {
                    if (!(v instanceof p))
                      throw new TypeError("Cannot call a class as a function");
                  }
                  function _(v, p) {
                    for (var f = 0; f < p.length; f++) {
                      var d = p[f];
                      ((d.enumerable = d.enumerable || !1),
                        (d.configurable = !0),
                        "value" in d && (d.writable = !0),
                        Object.defineProperty(v, d.key, d));
                    }
                  }
                  function E(v, p, f) {
                    return (
                      p && _(v.prototype, p),
                      Object.defineProperty(v, "prototype", { writable: !1 }),
                      v
                    );
                  }
                  var W = (function () {
                    function v(p, f, d) {
                      (C(this, v),
                        (this.instance = p),
                        (this.instance._reader = d.body.getReader()),
                        (this.total = parseInt(f, 10)),
                        (this.loaded = 0));
                    }
                    return (
                      E(v, [
                        {
                          key: "start",
                          value: function (f) {
                            var d = this,
                              P = function M() {
                                d.instance._reader
                                  .read()
                                  .then(function (g) {
                                    var O = g.done,
                                      m = g.value;
                                    if (O) {
                                      (d.total === 0 &&
                                        d.instance.onProgress.call(d.instance, {
                                          loaded: d.loaded,
                                          total: d.total,
                                          lengthComputable: !1,
                                        }),
                                        f.close());
                                      return;
                                    }
                                    ((d.loaded += m.byteLength),
                                      d.instance.onProgress.call(d.instance, {
                                        loaded: d.loaded,
                                        total: d.total,
                                        lengthComputable: d.total !== 0,
                                      }),
                                      f.enqueue(m),
                                      M());
                                  })
                                  .catch(function (g) {
                                    f.error(g);
                                  });
                              };
                            P();
                          },
                        },
                      ]),
                      v
                    );
                  })();
                  function A(v) {
                    if (v) {
                      if (!v.url) throw new Error("fetch url missing");
                    } else throw new Error("fetch options missing");
                    var p = new k.default(),
                      f = new Headers(),
                      d = new Request(v.url);
                    ((p.controller = new AbortController()),
                      v &&
                        v.requestHeaders &&
                        v.requestHeaders.forEach(function (g) {
                          f.append(g.key, g.value);
                        }));
                    var P = v.responseType || "json",
                      M = {
                        method: v.method || "GET",
                        headers: f,
                        mode: v.mode || "cors",
                        credentials: v.credentials || "same-origin",
                        cache: v.cache || "default",
                        redirect: v.redirect || "follow",
                        referrer: v.referrer || "client",
                        signal: p.controller.signal,
                      };
                    return (
                      fetch(d, M)
                        .then(function (g) {
                          p.response = g;
                          var O = !0;
                          g.body || (O = !1);
                          var m = g.headers.get("content-length");
                          return (
                            m === null && (O = !1),
                            O
                              ? ((p.onProgress = function (h) {
                                  p.fireEvent("progress", h);
                                }),
                                new Response(
                                  new ReadableStream(new W(p, m, g)),
                                  M,
                                ))
                              : g
                          );
                        })
                        .then(function (g) {
                          var O;
                          if (g.ok)
                            switch (P) {
                              case "arraybuffer":
                                return g.arrayBuffer();
                              case "json":
                                return g.json();
                              case "blob":
                                return g.blob();
                              case "text":
                                return g.text();
                              default:
                                O = "Unknown responseType: " + P;
                                break;
                            }
                          throw (
                            O || (O = "HTTP error status: " + g.status),
                            new Error(O)
                          );
                        })
                        .then(function (g) {
                          p.fireEvent("success", g);
                        })
                        .catch(function (g) {
                          p.fireEvent("error", g);
                        }),
                      (p.fetchRequest = d),
                      p
                    );
                  }
                  V.exports = c.default;
                },
                "./src/util/frame.js": (V, c, w) => {
                  (Object.defineProperty(c, "__esModule", { value: !0 }),
                    (c.default = C));
                  var k = R(w("./src/util/request-animation-frame.js"));
                  function R(_) {
                    return _ && _.__esModule ? _ : { default: _ };
                  }
                  function C(_) {
                    return function () {
                      for (
                        var E = arguments.length, W = new Array(E), A = 0;
                        A < E;
                        A++
                      )
                        W[A] = arguments[A];
                      return (0, k.default)(function () {
                        return _.apply(void 0, W);
                      });
                    };
                  }
                  V.exports = c.default;
                },
                "./src/util/get-id.js": (V, c) => {
                  (Object.defineProperty(c, "__esModule", { value: !0 }),
                    (c.default = w));
                  function w(k) {
                    return (
                      k === void 0 && (k = "wavesurfer_"),
                      k + Math.random().toString(32).substring(2)
                    );
                  }
                  V.exports = c.default;
                },
                "./src/util/index.js": (V, c, w) => {
                  (Object.defineProperty(c, "__esModule", { value: !0 }),
                    Object.defineProperty(c, "Observer", {
                      enumerable: !0,
                      get: function () {
                        return E.default;
                      },
                    }),
                    Object.defineProperty(c, "absMax", {
                      enumerable: !0,
                      get: function () {
                        return _.default;
                      },
                    }),
                    Object.defineProperty(c, "clamp", {
                      enumerable: !0,
                      get: function () {
                        return P.default;
                      },
                    }),
                    Object.defineProperty(c, "debounce", {
                      enumerable: !0,
                      get: function () {
                        return p.default;
                      },
                    }),
                    Object.defineProperty(c, "fetchFile", {
                      enumerable: !0,
                      get: function () {
                        return d.default;
                      },
                    }),
                    Object.defineProperty(c, "frame", {
                      enumerable: !0,
                      get: function () {
                        return v.default;
                      },
                    }),
                    Object.defineProperty(c, "getId", {
                      enumerable: !0,
                      get: function () {
                        return k.default;
                      },
                    }),
                    Object.defineProperty(c, "ignoreSilenceMode", {
                      enumerable: !0,
                      get: function () {
                        return g.default;
                      },
                    }),
                    Object.defineProperty(c, "max", {
                      enumerable: !0,
                      get: function () {
                        return R.default;
                      },
                    }),
                    Object.defineProperty(c, "min", {
                      enumerable: !0,
                      get: function () {
                        return C.default;
                      },
                    }),
                    Object.defineProperty(c, "preventClick", {
                      enumerable: !0,
                      get: function () {
                        return f.default;
                      },
                    }),
                    Object.defineProperty(c, "requestAnimationFrame", {
                      enumerable: !0,
                      get: function () {
                        return A.default;
                      },
                    }),
                    Object.defineProperty(c, "style", {
                      enumerable: !0,
                      get: function () {
                        return W.default;
                      },
                    }),
                    Object.defineProperty(c, "withOrientation", {
                      enumerable: !0,
                      get: function () {
                        return M.default;
                      },
                    }));
                  var k = O(w("./src/util/get-id.js")),
                    R = O(w("./src/util/max.js")),
                    C = O(w("./src/util/min.js")),
                    _ = O(w("./src/util/absMax.js")),
                    E = O(w("./src/util/observer.js")),
                    W = O(w("./src/util/style.js")),
                    A = O(w("./src/util/request-animation-frame.js")),
                    v = O(w("./src/util/frame.js")),
                    p = O(w("./node_modules/debounce/index.js")),
                    f = O(w("./src/util/prevent-click.js")),
                    d = O(w("./src/util/fetch.js")),
                    P = O(w("./src/util/clamp.js")),
                    M = O(w("./src/util/orientation.js")),
                    g = O(w("./src/util/silence-mode.js"));
                  function O(m) {
                    return m && m.__esModule ? m : { default: m };
                  }
                },
                "./src/util/max.js": (V, c) => {
                  (Object.defineProperty(c, "__esModule", { value: !0 }),
                    (c.default = w));
                  function w(k) {
                    var R = -1 / 0;
                    return (
                      Object.keys(k).forEach(function (C) {
                        k[C] > R && (R = k[C]);
                      }),
                      R
                    );
                  }
                  V.exports = c.default;
                },
                "./src/util/min.js": (V, c) => {
                  (Object.defineProperty(c, "__esModule", { value: !0 }),
                    (c.default = w));
                  function w(k) {
                    var R = 1 / 0;
                    return (
                      Object.keys(k).forEach(function (C) {
                        k[C] < R && (R = k[C]);
                      }),
                      R
                    );
                  }
                  V.exports = c.default;
                },
                "./src/util/observer.js": (V, c) => {
                  (Object.defineProperty(c, "__esModule", { value: !0 }),
                    (c.default = void 0));
                  function w(_, E) {
                    if (!(_ instanceof E))
                      throw new TypeError("Cannot call a class as a function");
                  }
                  function k(_, E) {
                    for (var W = 0; W < E.length; W++) {
                      var A = E[W];
                      ((A.enumerable = A.enumerable || !1),
                        (A.configurable = !0),
                        "value" in A && (A.writable = !0),
                        Object.defineProperty(_, A.key, A));
                    }
                  }
                  function R(_, E, W) {
                    return (
                      E && k(_.prototype, E),
                      Object.defineProperty(_, "prototype", { writable: !1 }),
                      _
                    );
                  }
                  var C = (function () {
                    function _() {
                      (w(this, _),
                        (this._disabledEventEmissions = []),
                        (this.handlers = null));
                    }
                    return (
                      R(_, [
                        {
                          key: "on",
                          value: function (W, A) {
                            var v = this;
                            this.handlers || (this.handlers = {});
                            var p = this.handlers[W];
                            return (
                              p || (p = this.handlers[W] = []),
                              p.push(A),
                              {
                                name: W,
                                callback: A,
                                un: function (d, P) {
                                  return v.un(d, P);
                                },
                              }
                            );
                          },
                        },
                        {
                          key: "un",
                          value: function (W, A) {
                            if (this.handlers) {
                              var v = this.handlers[W],
                                p;
                              if (v)
                                if (A)
                                  for (p = v.length - 1; p >= 0; p--)
                                    v[p] == A && v.splice(p, 1);
                                else v.length = 0;
                            }
                          },
                        },
                        {
                          key: "unAll",
                          value: function () {
                            this.handlers = null;
                          },
                        },
                        {
                          key: "once",
                          value: function (W, A) {
                            var v = this,
                              p = function f() {
                                for (
                                  var d = arguments.length,
                                    P = new Array(d),
                                    M = 0;
                                  M < d;
                                  M++
                                )
                                  P[M] = arguments[M];
                                (A.apply(v, P),
                                  setTimeout(function () {
                                    v.un(W, f);
                                  }, 0));
                              };
                            return this.on(W, p);
                          },
                        },
                        {
                          key: "setDisabledEventEmissions",
                          value: function (W) {
                            this._disabledEventEmissions = W;
                          },
                        },
                        {
                          key: "_isDisabledEventEmission",
                          value: function (W) {
                            return (
                              this._disabledEventEmissions &&
                              this._disabledEventEmissions.includes(W)
                            );
                          },
                        },
                        {
                          key: "fireEvent",
                          value: function (W) {
                            for (
                              var A = arguments.length,
                                v = new Array(A > 1 ? A - 1 : 0),
                                p = 1;
                              p < A;
                              p++
                            )
                              v[p - 1] = arguments[p];
                            if (!(
                              !this.handlers || this._isDisabledEventEmission(W)
                            )) {
                              var f = this.handlers[W];
                              f &&
                                f.forEach(function (d) {
                                  d.apply(void 0, v);
                                });
                            }
                          },
                        },
                      ]),
                      _
                    );
                  })();
                  ((c.default = C), (V.exports = c.default));
                },
                "./src/util/orientation.js": (V, c) => {
                  (Object.defineProperty(c, "__esModule", { value: !0 }),
                    (c.default = C));
                  var w = {
                    width: "height",
                    height: "width",
                    overflowX: "overflowY",
                    overflowY: "overflowX",
                    clientWidth: "clientHeight",
                    clientHeight: "clientWidth",
                    clientX: "clientY",
                    clientY: "clientX",
                    scrollWidth: "scrollHeight",
                    scrollLeft: "scrollTop",
                    offsetLeft: "offsetTop",
                    offsetTop: "offsetLeft",
                    offsetHeight: "offsetWidth",
                    offsetWidth: "offsetHeight",
                    left: "top",
                    right: "bottom",
                    top: "left",
                    bottom: "right",
                    borderRightStyle: "borderBottomStyle",
                    borderRightWidth: "borderBottomWidth",
                    borderRightColor: "borderBottomColor",
                  };
                  function k(_, E) {
                    return Object.prototype.hasOwnProperty.call(w, _) && E
                      ? w[_]
                      : _;
                  }
                  var R = Symbol("isProxy");
                  function C(_, E) {
                    return _[R]
                      ? _
                      : new Proxy(_, {
                          get: function (A, v, p) {
                            if (v === R) return !0;
                            if (v === "domElement") return A;
                            if (v === "style") return C(A.style, E);
                            if (v === "canvas") return C(A.canvas, E);
                            if (v === "getBoundingClientRect")
                              return function () {
                                return C(
                                  A.getBoundingClientRect.apply(A, arguments),
                                  E,
                                );
                              };
                            if (v === "getContext")
                              return function () {
                                return C(A.getContext.apply(A, arguments), E);
                              };
                            var f = A[k(v, E)];
                            return typeof f == "function" ? f.bind(A) : f;
                          },
                          set: function (A, v, p) {
                            return ((A[k(v, E)] = p), !0);
                          },
                        });
                  }
                  V.exports = c.default;
                },
                "./src/util/prevent-click.js": (V, c) => {
                  (Object.defineProperty(c, "__esModule", { value: !0 }),
                    (c.default = k));
                  function w(R) {
                    (R.stopPropagation(),
                      document.body.removeEventListener("click", w, !0));
                  }
                  function k(R) {
                    document.body.addEventListener("click", w, !0);
                  }
                  V.exports = c.default;
                },
                "./src/util/request-animation-frame.js": (V, c) => {
                  (Object.defineProperty(c, "__esModule", { value: !0 }),
                    (c.default = void 0));
                  var w = (
                    window.requestAnimationFrame ||
                    window.webkitRequestAnimationFrame ||
                    window.mozRequestAnimationFrame ||
                    window.oRequestAnimationFrame ||
                    window.msRequestAnimationFrame ||
                    function (k, R) {
                      return setTimeout(k, 1e3 / 60);
                    }
                  ).bind(window);
                  ((c.default = w), (V.exports = c.default));
                },
                "./src/util/silence-mode.js": (V, c) => {
                  (Object.defineProperty(c, "__esModule", { value: !0 }),
                    (c.default = w));
                  function w() {
                    var k =
                        "data:audio/mpeg;base64,//uQxAAAAAAAAAAAAAAAAAAAAAAAWGluZwAAAA8AAAACAAACcQCAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA//////////////////////////////////////////////////////////////////8AAABhTEFNRTMuMTAwA8MAAAAAAAAAABQgJAUHQQAB9AAAAnGMHkkIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//sQxAADgnABGiAAQBCqgCRMAAgEAH///////////////7+n/9FTuQsQH//////2NG0jWUGlio5gLQTOtIoeR2WX////X4s9Atb/JRVCbBUpeRUq//////////////////9RUi0f2jn/+xDECgPCjAEQAABN4AAANIAAAAQVTEFNRTMuMTAwVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVQ==",
                      R = document.createElement("div");
                    R.innerHTML = '<audio x-webkit-airplay="deny"></audio>';
                    var C = R.children.item(0);
                    ((C.src = k),
                      (C.preload = "auto"),
                      (C.type = "audio/mpeg"),
                      (C.disableRemotePlayback = !0),
                      C.play(),
                      C.remove(),
                      R.remove());
                  }
                  V.exports = c.default;
                },
                "./src/util/style.js": (V, c) => {
                  (Object.defineProperty(c, "__esModule", { value: !0 }),
                    (c.default = w));
                  function w(k, R) {
                    return (
                      Object.keys(R).forEach(function (C) {
                        k.style[C] !== R[C] && (k.style[C] = R[C]);
                      }),
                      k
                    );
                  }
                  V.exports = c.default;
                },
                "./src/wavesurfer.js": (V, c, w) => {
                  function k(r) {
                    "@babel/helpers - typeof";
                    return (
                      (k =
                        typeof Symbol == "function" &&
                        typeof Symbol.iterator == "symbol"
                          ? function (t) {
                              return typeof t;
                            }
                          : function (t) {
                              return t &&
                                typeof Symbol == "function" &&
                                t.constructor === Symbol &&
                                t !== Symbol.prototype
                                ? "symbol"
                                : typeof t;
                            }),
                      k(r)
                    );
                  }
                  (Object.defineProperty(c, "__esModule", { value: !0 }),
                    (c.default = void 0));
                  var R = f(w("./src/util/index.js")),
                    C = v(w("./src/drawer.multicanvas.js")),
                    _ = v(w("./src/webaudio.js")),
                    E = v(w("./src/mediaelement.js")),
                    W = v(w("./src/peakcache.js")),
                    A = v(w("./src/mediaelement-webaudio.js"));
                  function v(r) {
                    return r && r.__esModule ? r : { default: r };
                  }
                  function p(r) {
                    if (typeof WeakMap != "function") return null;
                    var t = new WeakMap(),
                      s = new WeakMap();
                    return (p = function (e) {
                      return e ? s : t;
                    })(r);
                  }
                  function f(r, t) {
                    if (r && r.__esModule) return r;
                    if (
                      r === null ||
                      (k(r) !== "object" && typeof r != "function")
                    )
                      return { default: r };
                    var s = p(t);
                    if (s && s.has(r)) return s.get(r);
                    var i = {},
                      e =
                        Object.defineProperty &&
                        Object.getOwnPropertyDescriptor;
                    for (var u in r)
                      if (
                        u !== "default" &&
                        Object.prototype.hasOwnProperty.call(r, u)
                      ) {
                        var b = e
                          ? Object.getOwnPropertyDescriptor(r, u)
                          : null;
                        b && (b.get || b.set)
                          ? Object.defineProperty(i, u, b)
                          : (i[u] = r[u]);
                      }
                    return ((i.default = r), s && s.set(r, i), i);
                  }
                  function d(r, t) {
                    if (typeof t != "function" && t !== null)
                      throw new TypeError(
                        "Super expression must either be null or a function",
                      );
                    ((r.prototype = Object.create(t && t.prototype, {
                      constructor: { value: r, writable: !0, configurable: !0 },
                    })),
                      Object.defineProperty(r, "prototype", { writable: !1 }),
                      t && P(r, t));
                  }
                  function P(r, t) {
                    return (
                      (P =
                        Object.setPrototypeOf ||
                        function (i, e) {
                          return ((i.__proto__ = e), i);
                        }),
                      P(r, t)
                    );
                  }
                  function M(r) {
                    var t = m();
                    return function () {
                      var i = h(r),
                        e;
                      if (t) {
                        var u = h(this).constructor;
                        e = Reflect.construct(i, arguments, u);
                      } else e = i.apply(this, arguments);
                      return g(this, e);
                    };
                  }
                  function g(r, t) {
                    if (t && (k(t) === "object" || typeof t == "function"))
                      return t;
                    if (t !== void 0)
                      throw new TypeError(
                        "Derived constructors may only return object or undefined",
                      );
                    return O(r);
                  }
                  function O(r) {
                    if (r === void 0)
                      throw new ReferenceError(
                        "this hasn't been initialised - super() hasn't been called",
                      );
                    return r;
                  }
                  function m() {
                    if (
                      typeof Reflect > "u" ||
                      !Reflect.construct ||
                      Reflect.construct.sham
                    )
                      return !1;
                    if (typeof Proxy == "function") return !0;
                    try {
                      return (
                        Boolean.prototype.valueOf.call(
                          Reflect.construct(Boolean, [], function () {}),
                        ),
                        !0
                      );
                    } catch {
                      return !1;
                    }
                  }
                  function h(r) {
                    return (
                      (h = Object.setPrototypeOf
                        ? Object.getPrototypeOf
                        : function (s) {
                            return s.__proto__ || Object.getPrototypeOf(s);
                          }),
                      h(r)
                    );
                  }
                  function y(r, t, s) {
                    return (
                      t in r
                        ? Object.defineProperty(r, t, {
                            value: s,
                            enumerable: !0,
                            configurable: !0,
                            writable: !0,
                          })
                        : (r[t] = s),
                      r
                    );
                  }
                  function l(r, t) {
                    if (!(r instanceof t))
                      throw new TypeError("Cannot call a class as a function");
                  }
                  function n(r, t) {
                    for (var s = 0; s < t.length; s++) {
                      var i = t[s];
                      ((i.enumerable = i.enumerable || !1),
                        (i.configurable = !0),
                        "value" in i && (i.writable = !0),
                        Object.defineProperty(r, i.key, i));
                    }
                  }
                  function a(r, t, s) {
                    return (
                      t && n(r.prototype, t),
                      s && n(r, s),
                      Object.defineProperty(r, "prototype", { writable: !1 }),
                      r
                    );
                  }
                  var o = (function (r) {
                    d(s, r);
                    var t = M(s);
                    function s(i) {
                      var e;
                      if (
                        (l(this, s),
                        (e = t.call(this)),
                        y(O(e), "defaultParams", {
                          audioContext: null,
                          audioScriptProcessor: null,
                          audioRate: 1,
                          autoCenter: !0,
                          autoCenterRate: 5,
                          autoCenterImmediately: !1,
                          backend: "WebAudio",
                          backgroundColor: null,
                          barHeight: 1,
                          barRadius: 0,
                          barGap: null,
                          barMinHeight: null,
                          container: null,
                          cursorColor: "#333",
                          cursorWidth: 1,
                          dragSelection: !0,
                          drawingContextAttributes: { desynchronized: !1 },
                          duration: null,
                          fillParent: !0,
                          forceDecode: !1,
                          height: 128,
                          hideScrollbar: !1,
                          hideCursor: !1,
                          ignoreSilenceMode: !1,
                          interact: !0,
                          loopSelection: !0,
                          maxCanvasWidth: 4e3,
                          mediaContainer: null,
                          mediaControls: !1,
                          mediaType: "audio",
                          minPxPerSec: 20,
                          normalize: !1,
                          partialRender: !1,
                          pixelRatio:
                            window.devicePixelRatio ||
                            screen.deviceXDPI / screen.logicalXDPI,
                          plugins: [],
                          progressColor: "#555",
                          removeMediaElementOnDestroy: !0,
                          renderer: C.default,
                          responsive: !1,
                          rtl: !1,
                          scrollParent: !1,
                          skipLength: 2,
                          splitChannels: !1,
                          splitChannelsOptions: {
                            overlay: !1,
                            channelColors: {},
                            filterChannels: [],
                            relativeNormalization: !1,
                          },
                          vertical: !1,
                          waveColor: "#999",
                          xhr: {},
                        }),
                        y(O(e), "backends", {
                          MediaElement: E.default,
                          WebAudio: _.default,
                          MediaElementWebAudio: A.default,
                        }),
                        y(O(e), "util", R),
                        (e.params = Object.assign({}, e.defaultParams, i)),
                        (e.params.splitChannelsOptions = Object.assign(
                          {},
                          e.defaultParams.splitChannelsOptions,
                          i.splitChannelsOptions,
                        )),
                        (e.container =
                          typeof i.container == "string"
                            ? document.querySelector(e.params.container)
                            : e.params.container),
                        !e.container)
                      )
                        throw new Error("Container element not found");
                      if (
                        (e.params.mediaContainer == null
                          ? (e.mediaContainer = e.container)
                          : typeof e.params.mediaContainer == "string"
                            ? (e.mediaContainer = document.querySelector(
                                e.params.mediaContainer,
                              ))
                            : (e.mediaContainer = e.params.mediaContainer),
                        !e.mediaContainer)
                      )
                        throw new Error("Media Container element not found");
                      if (e.params.maxCanvasWidth <= 1)
                        throw new Error(
                          "maxCanvasWidth must be greater than 1",
                        );
                      if (e.params.maxCanvasWidth % 2 == 1)
                        throw new Error(
                          "maxCanvasWidth must be an even number",
                        );
                      if (
                        (e.params.rtl === !0 &&
                          (e.params.vertical === !0
                            ? R.style(e.container, {
                                transform: "rotateX(180deg)",
                              })
                            : R.style(e.container, {
                                transform: "rotateY(180deg)",
                              })),
                        e.params.backgroundColor &&
                          e.setBackgroundColor(e.params.backgroundColor),
                        (e.savedVolume = 0),
                        (e.isMuted = !1),
                        (e.tmpEvents = []),
                        (e.currentRequest = null),
                        (e.arraybuffer = null),
                        (e.drawer = null),
                        (e.backend = null),
                        (e.peakCache = null),
                        typeof e.params.renderer != "function")
                      )
                        throw new Error("Renderer parameter is invalid");
                      ((e.Drawer = e.params.renderer),
                        e.params.backend == "AudioElement" &&
                          (e.params.backend = "MediaElement"),
                        (e.params.backend == "WebAudio" ||
                          e.params.backend === "MediaElementWebAudio") &&
                          !_.default.prototype.supportsWebAudio.call(null) &&
                          (e.params.backend = "MediaElement"),
                        (e.Backend = e.backends[e.params.backend]),
                        (e.initialisedPluginList = {}),
                        (e.isDestroyed = !1),
                        (e.isReady = !1));
                      var u = 0;
                      return (
                        (e._onResize = R.debounce(
                          function () {
                            u != e.drawer.wrapper.clientWidth &&
                              !e.params.scrollParent &&
                              ((u = e.drawer.wrapper.clientWidth),
                              u && e.drawer.fireEvent("redraw"));
                          },
                          typeof e.params.responsive == "number"
                            ? e.params.responsive
                            : 100,
                        )),
                        g(e, O(e))
                      );
                    }
                    return (
                      a(
                        s,
                        [
                          {
                            key: "init",
                            value: function () {
                              return (
                                this.registerPlugins(this.params.plugins),
                                this.createDrawer(),
                                this.createBackend(),
                                this.createPeakCache(),
                                this
                              );
                            },
                          },
                          {
                            key: "registerPlugins",
                            value: function (e) {
                              var u = this;
                              return (
                                e.forEach(function (b) {
                                  return u.addPlugin(b);
                                }),
                                e.forEach(function (b) {
                                  b.deferInit || u.initPlugin(b.name);
                                }),
                                this.fireEvent("plugins-registered", e),
                                this
                              );
                            },
                          },
                          {
                            key: "getActivePlugins",
                            value: function () {
                              return this.initialisedPluginList;
                            },
                          },
                          {
                            key: "addPlugin",
                            value: function (e) {
                              var u = this;
                              if (!e.name)
                                throw new Error("Plugin does not have a name!");
                              if (!e.instance)
                                throw new Error(
                                  "Plugin ".concat(
                                    e.name,
                                    " does not have an instance property!",
                                  ),
                                );
                              e.staticProps &&
                                Object.keys(e.staticProps).forEach(
                                  function (S) {
                                    u[S] = e.staticProps[S];
                                  },
                                );
                              var b = e.instance,
                                T = Object.getOwnPropertyNames(
                                  R.Observer.prototype,
                                );
                              return (
                                T.forEach(function (S) {
                                  b.prototype[S] = R.Observer.prototype[S];
                                }),
                                (this[e.name] = new b(e.params || {}, this)),
                                this.fireEvent("plugin-added", e.name),
                                this
                              );
                            },
                          },
                          {
                            key: "initPlugin",
                            value: function (e) {
                              if (!this[e])
                                throw new Error(
                                  "Plugin ".concat(
                                    e,
                                    " has not been added yet!",
                                  ),
                                );
                              return (
                                this.initialisedPluginList[e] &&
                                  this.destroyPlugin(e),
                                this[e].init(),
                                (this.initialisedPluginList[e] = !0),
                                this.fireEvent("plugin-initialised", e),
                                this
                              );
                            },
                          },
                          {
                            key: "destroyPlugin",
                            value: function (e) {
                              if (!this[e])
                                throw new Error(
                                  "Plugin ".concat(
                                    e,
                                    " has not been added yet and cannot be destroyed!",
                                  ),
                                );
                              if (!this.initialisedPluginList[e])
                                throw new Error(
                                  "Plugin ".concat(
                                    e,
                                    " is not active and cannot be destroyed!",
                                  ),
                                );
                              if (typeof this[e].destroy != "function")
                                throw new Error(
                                  "Plugin ".concat(
                                    e,
                                    " does not have a destroy function!",
                                  ),
                                );
                              return (
                                this[e].destroy(),
                                delete this.initialisedPluginList[e],
                                this.fireEvent("plugin-destroyed", e),
                                this
                              );
                            },
                          },
                          {
                            key: "destroyAllPlugins",
                            value: function () {
                              var e = this;
                              Object.keys(this.initialisedPluginList).forEach(
                                function (u) {
                                  return e.destroyPlugin(u);
                                },
                              );
                            },
                          },
                          {
                            key: "createDrawer",
                            value: function () {
                              var e = this;
                              ((this.drawer = new this.Drawer(
                                this.container,
                                this.params,
                              )),
                                this.drawer.init(),
                                this.fireEvent("drawer-created", this.drawer),
                                this.params.responsive !== !1 &&
                                  (window.addEventListener(
                                    "resize",
                                    this._onResize,
                                    !0,
                                  ),
                                  window.addEventListener(
                                    "orientationchange",
                                    this._onResize,
                                    !0,
                                  )),
                                this.drawer.on("redraw", function () {
                                  (e.drawBuffer(),
                                    e.drawer.progress(
                                      e.backend.getPlayedPercents(),
                                    ));
                                }),
                                this.drawer.on("click", function (u, b) {
                                  setTimeout(function () {
                                    return e.seekTo(b);
                                  }, 0);
                                }),
                                this.drawer.on("scroll", function (u) {
                                  (e.params.partialRender && e.drawBuffer(),
                                    e.fireEvent("scroll", u));
                                }));
                            },
                          },
                          {
                            key: "createBackend",
                            value: function () {
                              var e = this;
                              (this.backend && this.backend.destroy(),
                                (this.backend = new this.Backend(this.params)),
                                this.backend.init(),
                                this.fireEvent("backend-created", this.backend),
                                this.backend.on("finish", function () {
                                  (e.drawer.progress(
                                    e.backend.getPlayedPercents(),
                                  ),
                                    e.fireEvent("finish"));
                                }),
                                this.backend.on("play", function () {
                                  return e.fireEvent("play");
                                }),
                                this.backend.on("pause", function () {
                                  return e.fireEvent("pause");
                                }),
                                this.backend.on("audioprocess", function (u) {
                                  (e.drawer.progress(
                                    e.backend.getPlayedPercents(),
                                  ),
                                    e.fireEvent("audioprocess", u));
                                }),
                                (this.params.backend === "MediaElement" ||
                                  this.params.backend ===
                                    "MediaElementWebAudio") &&
                                  (this.backend.on("seek", function () {
                                    e.drawer.progress(
                                      e.backend.getPlayedPercents(),
                                    );
                                  }),
                                  this.backend.on("volume", function () {
                                    var u = e.getVolume();
                                    (e.fireEvent("volume", u),
                                      e.backend.isMuted !== e.isMuted &&
                                        ((e.isMuted = e.backend.isMuted),
                                        e.fireEvent("mute", e.isMuted)));
                                  })));
                            },
                          },
                          {
                            key: "createPeakCache",
                            value: function () {
                              this.params.partialRender &&
                                (this.peakCache = new W.default());
                            },
                          },
                          {
                            key: "getDuration",
                            value: function () {
                              return this.backend.getDuration();
                            },
                          },
                          {
                            key: "getCurrentTime",
                            value: function () {
                              return this.backend.getCurrentTime();
                            },
                          },
                          {
                            key: "setCurrentTime",
                            value: function (e) {
                              e >= this.getDuration()
                                ? this.seekTo(1)
                                : this.seekTo(e / this.getDuration());
                            },
                          },
                          {
                            key: "play",
                            value: function (e, u) {
                              var b = this;
                              return (
                                this.params.ignoreSilenceMode &&
                                  R.ignoreSilenceMode(),
                                this.fireEvent("interaction", function () {
                                  return b.play(e, u);
                                }),
                                this.backend.play(e, u)
                              );
                            },
                          },
                          {
                            key: "setPlayEnd",
                            value: function (e) {
                              this.backend.setPlayEnd(e);
                            },
                          },
                          {
                            key: "pause",
                            value: function () {
                              if (!this.backend.isPaused())
                                return this.backend.pause();
                            },
                          },
                          {
                            key: "playPause",
                            value: function () {
                              return this.backend.isPaused()
                                ? this.play()
                                : this.pause();
                            },
                          },
                          {
                            key: "isPlaying",
                            value: function () {
                              return !this.backend.isPaused();
                            },
                          },
                          {
                            key: "skipBackward",
                            value: function (e) {
                              this.skip(-e || -this.params.skipLength);
                            },
                          },
                          {
                            key: "skipForward",
                            value: function (e) {
                              this.skip(e || this.params.skipLength);
                            },
                          },
                          {
                            key: "skip",
                            value: function (e) {
                              var u = this.getDuration() || 1,
                                b = this.getCurrentTime() || 0;
                              ((b = Math.max(0, Math.min(u, b + (e || 0)))),
                                this.seekAndCenter(b / u));
                            },
                          },
                          {
                            key: "seekAndCenter",
                            value: function (e) {
                              (this.seekTo(e), this.drawer.recenter(e));
                            },
                          },
                          {
                            key: "seekTo",
                            value: function (e) {
                              var u = this;
                              if (
                                typeof e != "number" ||
                                !isFinite(e) ||
                                e < 0 ||
                                e > 1
                              )
                                throw new Error(
                                  "Error calling wavesurfer.seekTo, parameter must be a number between 0 and 1!",
                                );
                              this.fireEvent("interaction", function () {
                                return u.seekTo(e);
                              });
                              var b = this.params.backend === "WebAudio",
                                T = this.backend.isPaused();
                              b && !T && this.backend.pause();
                              var S = this.params.scrollParent;
                              ((this.params.scrollParent = !1),
                                this.backend.seekTo(e * this.getDuration()),
                                this.drawer.progress(e),
                                b && !T && this.backend.play(),
                                (this.params.scrollParent = S),
                                this.fireEvent("seek", e));
                            },
                          },
                          {
                            key: "stop",
                            value: function () {
                              (this.pause(),
                                this.seekTo(0),
                                this.drawer.progress(0));
                            },
                          },
                          {
                            key: "setSinkId",
                            value: function (e) {
                              return this.backend.setSinkId(e);
                            },
                          },
                          {
                            key: "setVolume",
                            value: function (e) {
                              (this.backend.setVolume(e),
                                this.fireEvent("volume", e));
                            },
                          },
                          {
                            key: "getVolume",
                            value: function () {
                              return this.backend.getVolume();
                            },
                          },
                          {
                            key: "setPlaybackRate",
                            value: function (e) {
                              this.backend.setPlaybackRate(e);
                            },
                          },
                          {
                            key: "getPlaybackRate",
                            value: function () {
                              return this.backend.getPlaybackRate();
                            },
                          },
                          {
                            key: "toggleMute",
                            value: function () {
                              this.setMute(!this.isMuted);
                            },
                          },
                          {
                            key: "setMute",
                            value: function (e) {
                              if (e === this.isMuted) {
                                this.fireEvent("mute", this.isMuted);
                                return;
                              }
                              (this.backend.setMute
                                ? (this.backend.setMute(e), (this.isMuted = e))
                                : e
                                  ? ((this.savedVolume =
                                      this.backend.getVolume()),
                                    this.backend.setVolume(0),
                                    (this.isMuted = !0),
                                    this.fireEvent("volume", 0))
                                  : (this.backend.setVolume(this.savedVolume),
                                    (this.isMuted = !1),
                                    this.fireEvent("volume", this.savedVolume)),
                                this.fireEvent("mute", this.isMuted));
                            },
                          },
                          {
                            key: "getMute",
                            value: function () {
                              return this.isMuted;
                            },
                          },
                          {
                            key: "getFilters",
                            value: function () {
                              return this.backend.filters || [];
                            },
                          },
                          {
                            key: "toggleScroll",
                            value: function () {
                              ((this.params.scrollParent =
                                !this.params.scrollParent),
                                this.drawBuffer());
                            },
                          },
                          {
                            key: "toggleInteraction",
                            value: function () {
                              this.params.interact = !this.params.interact;
                            },
                          },
                          {
                            key: "getWaveColor",
                            value: function () {
                              var e =
                                arguments.length > 0 && arguments[0] !== void 0
                                  ? arguments[0]
                                  : null;
                              return this.params.splitChannelsOptions
                                .channelColors[e]
                                ? this.params.splitChannelsOptions
                                    .channelColors[e].waveColor
                                : this.params.waveColor;
                            },
                          },
                          {
                            key: "setWaveColor",
                            value: function (e) {
                              var u =
                                arguments.length > 1 && arguments[1] !== void 0
                                  ? arguments[1]
                                  : null;
                              (this.params.splitChannelsOptions.channelColors[u]
                                ? (this.params.splitChannelsOptions.channelColors[
                                    u
                                  ].waveColor = e)
                                : (this.params.waveColor = e),
                                this.drawBuffer());
                            },
                          },
                          {
                            key: "getProgressColor",
                            value: function () {
                              var e =
                                arguments.length > 0 && arguments[0] !== void 0
                                  ? arguments[0]
                                  : null;
                              return this.params.splitChannelsOptions
                                .channelColors[e]
                                ? this.params.splitChannelsOptions
                                    .channelColors[e].progressColor
                                : this.params.progressColor;
                            },
                          },
                          {
                            key: "setProgressColor",
                            value: function (e, u) {
                              (this.params.splitChannelsOptions.channelColors[u]
                                ? (this.params.splitChannelsOptions.channelColors[
                                    u
                                  ].progressColor = e)
                                : (this.params.progressColor = e),
                                this.drawBuffer());
                            },
                          },
                          {
                            key: "getBackgroundColor",
                            value: function () {
                              return this.params.backgroundColor;
                            },
                          },
                          {
                            key: "setBackgroundColor",
                            value: function (e) {
                              ((this.params.backgroundColor = e),
                                R.style(this.container, {
                                  background: this.params.backgroundColor,
                                }));
                            },
                          },
                          {
                            key: "getCursorColor",
                            value: function () {
                              return this.params.cursorColor;
                            },
                          },
                          {
                            key: "setCursorColor",
                            value: function (e) {
                              ((this.params.cursorColor = e),
                                this.drawer.updateCursor());
                            },
                          },
                          {
                            key: "getHeight",
                            value: function () {
                              return this.params.height;
                            },
                          },
                          {
                            key: "setHeight",
                            value: function (e) {
                              ((this.params.height = e),
                                this.drawer.setHeight(
                                  e * this.params.pixelRatio,
                                ),
                                this.drawBuffer());
                            },
                          },
                          {
                            key: "setFilteredChannels",
                            value: function (e) {
                              ((this.params.splitChannelsOptions.filterChannels =
                                e),
                                this.drawBuffer());
                            },
                          },
                          {
                            key: "drawBuffer",
                            value: function () {
                              var e = Math.round(
                                  this.getDuration() *
                                    this.params.minPxPerSec *
                                    this.params.pixelRatio,
                                ),
                                u = this.drawer.getWidth(),
                                b = e,
                                T = 0,
                                S = Math.max(T + u, b);
                              this.params.fillParent &&
                                (!this.params.scrollParent || e < u) &&
                                ((b = u), (T = 0), (S = b));
                              var D;
                              if (this.params.partialRender) {
                                var j = this.peakCache.addRangeToPeakCache(
                                    b,
                                    T,
                                    S,
                                  ),
                                  x;
                                for (x = 0; x < j.length; x++)
                                  ((D = this.backend.getPeaks(
                                    b,
                                    j[x][0],
                                    j[x][1],
                                  )),
                                    this.drawer.drawPeaks(
                                      D,
                                      b,
                                      j[x][0],
                                      j[x][1],
                                    ));
                              } else
                                ((D = this.backend.getPeaks(b, T, S)),
                                  this.drawer.drawPeaks(D, b, T, S));
                              this.fireEvent("redraw", D, b);
                            },
                          },
                          {
                            key: "zoom",
                            value: function (e) {
                              (e
                                ? ((this.params.minPxPerSec = e),
                                  (this.params.scrollParent = !0))
                                : ((this.params.minPxPerSec =
                                    this.defaultParams.minPxPerSec),
                                  (this.params.scrollParent = !1)),
                                this.drawBuffer(),
                                this.drawer.progress(
                                  this.backend.getPlayedPercents(),
                                ),
                                this.drawer.recenter(
                                  this.getCurrentTime() / this.getDuration(),
                                ),
                                this.fireEvent("zoom", e));
                            },
                          },
                          {
                            key: "loadArrayBuffer",
                            value: function (e) {
                              var u = this;
                              this.decodeArrayBuffer(e, function (b) {
                                u.isDestroyed || u.loadDecodedBuffer(b);
                              });
                            },
                          },
                          {
                            key: "loadDecodedBuffer",
                            value: function (e) {
                              (this.backend.load(e),
                                this.drawBuffer(),
                                (this.isReady = !0),
                                this.fireEvent("ready"));
                            },
                          },
                          {
                            key: "loadBlob",
                            value: function (e) {
                              var u = this,
                                b = new FileReader();
                              (b.addEventListener("progress", function (T) {
                                return u.onProgress(T);
                              }),
                                b.addEventListener("load", function (T) {
                                  return u.loadArrayBuffer(T.target.result);
                                }),
                                b.addEventListener("error", function () {
                                  return u.fireEvent(
                                    "error",
                                    "Error reading file",
                                  );
                                }),
                                b.readAsArrayBuffer(e),
                                this.empty());
                            },
                          },
                          {
                            key: "load",
                            value: function (e, u, b, T) {
                              if (!e)
                                throw new Error(
                                  "url parameter cannot be empty",
                                );
                              if ((this.empty(), b)) {
                                var S = {
                                    "Preload is not 'auto', 'none' or 'metadata'":
                                      ["auto", "metadata", "none"].indexOf(
                                        b,
                                      ) === -1,
                                    "Peaks are not provided": !u,
                                    "Backend is not of type 'MediaElement' or 'MediaElementWebAudio'":
                                      [
                                        "MediaElement",
                                        "MediaElementWebAudio",
                                      ].indexOf(this.params.backend) === -1,
                                    "Url is not of type string":
                                      typeof e != "string",
                                  },
                                  D = Object.keys(S).filter(function (j) {
                                    return S[j];
                                  });
                                D.length &&
                                  (console.warn(
                                    `Preload parameter of wavesurfer.load will be ignored because:
	- ` +
                                      D.join(`
	- `),
                                  ),
                                  (b = null));
                              }
                              switch (
                                (this.params.backend === "WebAudio" &&
                                  e instanceof HTMLMediaElement &&
                                  (e = e.src),
                                this.params.backend)
                              ) {
                                case "WebAudio":
                                  return this.loadBuffer(e, u, T);
                                case "MediaElement":
                                case "MediaElementWebAudio":
                                  return this.loadMediaElement(e, u, b, T);
                              }
                            },
                          },
                          {
                            key: "loadBuffer",
                            value: function (e, u, b) {
                              var T = this,
                                S = function (j) {
                                  return (
                                    j && T.tmpEvents.push(T.once("ready", j)),
                                    T.getArrayBuffer(e, function (x) {
                                      return T.loadArrayBuffer(x);
                                    })
                                  );
                                };
                              if (u)
                                (this.backend.setPeaks(u, b),
                                  this.drawBuffer(),
                                  this.fireEvent("waveform-ready"),
                                  this.tmpEvents.push(
                                    this.once("interaction", S),
                                  ));
                              else return S();
                            },
                          },
                          {
                            key: "loadMediaElement",
                            value: function (e, u, b, T) {
                              var S = this,
                                D = e;
                              if (typeof e == "string")
                                this.backend.load(D, this.mediaContainer, u, b);
                              else {
                                var j = e;
                                (this.backend.loadElt(j, u), (D = j.src));
                              }
                              (this.tmpEvents.push(
                                this.backend.once("canplay", function () {
                                  S.backend.destroyed ||
                                    (S.drawBuffer(),
                                    (S.isReady = !0),
                                    S.fireEvent("ready"));
                                }),
                                this.backend.once("error", function (x) {
                                  return S.fireEvent("error", x);
                                }),
                              ),
                                u &&
                                  (this.backend.setPeaks(u, T),
                                  this.drawBuffer(),
                                  this.fireEvent("waveform-ready")),
                                (!u || this.params.forceDecode) &&
                                  this.backend.supportsWebAudio() &&
                                  this.getArrayBuffer(D, function (x) {
                                    S.decodeArrayBuffer(x, function (I) {
                                      ((S.backend.buffer = I),
                                        S.backend.setPeaks(null),
                                        S.drawBuffer(),
                                        S.fireEvent("waveform-ready"));
                                    });
                                  }));
                            },
                          },
                          {
                            key: "decodeArrayBuffer",
                            value: function (e, u) {
                              var b = this;
                              this.isDestroyed ||
                                ((this.arraybuffer = e),
                                this.backend.decodeArrayBuffer(
                                  e,
                                  function (T) {
                                    !b.isDestroyed &&
                                      b.arraybuffer == e &&
                                      (u(T), (b.arraybuffer = null));
                                  },
                                  function () {
                                    return b.fireEvent(
                                      "error",
                                      "Error decoding audiobuffer",
                                    );
                                  },
                                ));
                            },
                          },
                          {
                            key: "getArrayBuffer",
                            value: function (e, u) {
                              var b = this,
                                T = Object.assign(
                                  { url: e, responseType: "arraybuffer" },
                                  this.params.xhr,
                                ),
                                S = R.fetchFile(T);
                              return (
                                (this.currentRequest = S),
                                this.tmpEvents.push(
                                  S.on("progress", function (D) {
                                    b.onProgress(D);
                                  }),
                                  S.on("success", function (D) {
                                    (u(D), (b.currentRequest = null));
                                  }),
                                  S.on("error", function (D) {
                                    (b.fireEvent("error", D),
                                      (b.currentRequest = null));
                                  }),
                                ),
                                S
                              );
                            },
                          },
                          {
                            key: "onProgress",
                            value: function (e) {
                              var u;
                              (e.lengthComputable
                                ? (u = e.loaded / e.total)
                                : (u = e.loaded / (e.loaded + 1e6)),
                                this.fireEvent(
                                  "loading",
                                  Math.round(u * 100),
                                  e.target,
                                ));
                            },
                          },
                          {
                            key: "exportPCM",
                            value: function (e, u, b, T, S) {
                              ((e = e || 1024),
                                (T = T || 0),
                                (u = u || 1e4),
                                (b = b || !1));
                              var D = this.backend.getPeaks(e, T, S),
                                j = [].map.call(D, function (x) {
                                  return Math.round(x * u) / u;
                                });
                              return new Promise(function (x, I) {
                                if (!b) {
                                  var N = new Blob([JSON.stringify(j)], {
                                      type: "application/json;charset=utf-8",
                                    }),
                                    B = URL.createObjectURL(N);
                                  (window.open(B), URL.revokeObjectURL(B));
                                }
                                x(j);
                              });
                            },
                          },
                          {
                            key: "exportImage",
                            value: function (e, u, b) {
                              return (
                                e || (e = "image/png"),
                                u || (u = 1),
                                b || (b = "dataURL"),
                                this.drawer.getImage(e, u, b)
                              );
                            },
                          },
                          {
                            key: "cancelAjax",
                            value: function () {
                              this.currentRequest &&
                                this.currentRequest.controller &&
                                (this.currentRequest._reader &&
                                  this.currentRequest._reader
                                    .cancel()
                                    .catch(function (e) {}),
                                this.currentRequest.controller.abort(),
                                (this.currentRequest = null));
                            },
                          },
                          {
                            key: "clearTmpEvents",
                            value: function () {
                              this.tmpEvents.forEach(function (e) {
                                return e.un();
                              });
                            },
                          },
                          {
                            key: "empty",
                            value: function () {
                              (this.backend.isPaused() ||
                                (this.stop(), this.backend.disconnectSource()),
                                (this.isReady = !1),
                                this.cancelAjax(),
                                this.clearTmpEvents(),
                                this.drawer.progress(0),
                                this.drawer.setWidth(0),
                                this.drawer.drawPeaks(
                                  { length: this.drawer.getWidth() },
                                  0,
                                ));
                            },
                          },
                          {
                            key: "destroy",
                            value: function () {
                              (this.destroyAllPlugins(),
                                this.fireEvent("destroy"),
                                this.cancelAjax(),
                                this.clearTmpEvents(),
                                this.unAll(),
                                this.params.responsive !== !1 &&
                                  (window.removeEventListener(
                                    "resize",
                                    this._onResize,
                                    !0,
                                  ),
                                  window.removeEventListener(
                                    "orientationchange",
                                    this._onResize,
                                    !0,
                                  )),
                                this.backend &&
                                  (this.backend.destroy(),
                                  (this.backend = null)),
                                this.drawer && this.drawer.destroy(),
                                (this.isDestroyed = !0),
                                (this.isReady = !1),
                                (this.arraybuffer = null));
                            },
                          },
                        ],
                        [
                          {
                            key: "create",
                            value: function (e) {
                              var u = new s(e);
                              return u.init();
                            },
                          },
                        ],
                      ),
                      s
                    );
                  })(R.Observer);
                  ((c.default = o),
                    y(o, "VERSION", "6.1.0"),
                    y(o, "util", R),
                    (V.exports = c.default));
                },
                "./src/webaudio.js": (V, c, w) => {
                  function k(n) {
                    "@babel/helpers - typeof";
                    return (
                      (k =
                        typeof Symbol == "function" &&
                        typeof Symbol.iterator == "symbol"
                          ? function (a) {
                              return typeof a;
                            }
                          : function (a) {
                              return a &&
                                typeof Symbol == "function" &&
                                a.constructor === Symbol &&
                                a !== Symbol.prototype
                                ? "symbol"
                                : typeof a;
                            }),
                      k(n)
                    );
                  }
                  (Object.defineProperty(c, "__esModule", { value: !0 }),
                    (c.default = void 0));
                  var R = _(w("./src/util/index.js"));
                  function C(n) {
                    if (typeof WeakMap != "function") return null;
                    var a = new WeakMap(),
                      o = new WeakMap();
                    return (C = function (t) {
                      return t ? o : a;
                    })(n);
                  }
                  function _(n, a) {
                    if (n && n.__esModule) return n;
                    if (
                      n === null ||
                      (k(n) !== "object" && typeof n != "function")
                    )
                      return { default: n };
                    var o = C(a);
                    if (o && o.has(n)) return o.get(n);
                    var r = {},
                      t =
                        Object.defineProperty &&
                        Object.getOwnPropertyDescriptor;
                    for (var s in n)
                      if (
                        s !== "default" &&
                        Object.prototype.hasOwnProperty.call(n, s)
                      ) {
                        var i = t
                          ? Object.getOwnPropertyDescriptor(n, s)
                          : null;
                        i && (i.get || i.set)
                          ? Object.defineProperty(r, s, i)
                          : (r[s] = n[s]);
                      }
                    return ((r.default = n), o && o.set(n, r), r);
                  }
                  function E(n, a) {
                    if (!(n instanceof a))
                      throw new TypeError("Cannot call a class as a function");
                  }
                  function W(n, a) {
                    for (var o = 0; o < a.length; o++) {
                      var r = a[o];
                      ((r.enumerable = r.enumerable || !1),
                        (r.configurable = !0),
                        "value" in r && (r.writable = !0),
                        Object.defineProperty(n, r.key, r));
                    }
                  }
                  function A(n, a, o) {
                    return (
                      a && W(n.prototype, a),
                      Object.defineProperty(n, "prototype", { writable: !1 }),
                      n
                    );
                  }
                  function v(n, a) {
                    if (typeof a != "function" && a !== null)
                      throw new TypeError(
                        "Super expression must either be null or a function",
                      );
                    ((n.prototype = Object.create(a && a.prototype, {
                      constructor: { value: n, writable: !0, configurable: !0 },
                    })),
                      Object.defineProperty(n, "prototype", { writable: !1 }),
                      a && p(n, a));
                  }
                  function p(n, a) {
                    return (
                      (p =
                        Object.setPrototypeOf ||
                        function (r, t) {
                          return ((r.__proto__ = t), r);
                        }),
                      p(n, a)
                    );
                  }
                  function f(n) {
                    var a = M();
                    return function () {
                      var r = g(n),
                        t;
                      if (a) {
                        var s = g(this).constructor;
                        t = Reflect.construct(r, arguments, s);
                      } else t = r.apply(this, arguments);
                      return d(this, t);
                    };
                  }
                  function d(n, a) {
                    if (a && (k(a) === "object" || typeof a == "function"))
                      return a;
                    if (a !== void 0)
                      throw new TypeError(
                        "Derived constructors may only return object or undefined",
                      );
                    return P(n);
                  }
                  function P(n) {
                    if (n === void 0)
                      throw new ReferenceError(
                        "this hasn't been initialised - super() hasn't been called",
                      );
                    return n;
                  }
                  function M() {
                    if (
                      typeof Reflect > "u" ||
                      !Reflect.construct ||
                      Reflect.construct.sham
                    )
                      return !1;
                    if (typeof Proxy == "function") return !0;
                    try {
                      return (
                        Boolean.prototype.valueOf.call(
                          Reflect.construct(Boolean, [], function () {}),
                        ),
                        !0
                      );
                    } catch {
                      return !1;
                    }
                  }
                  function g(n) {
                    return (
                      (g = Object.setPrototypeOf
                        ? Object.getPrototypeOf
                        : function (o) {
                            return o.__proto__ || Object.getPrototypeOf(o);
                          }),
                      g(n)
                    );
                  }
                  function O(n, a, o) {
                    return (
                      a in n
                        ? Object.defineProperty(n, a, {
                            value: o,
                            enumerable: !0,
                            configurable: !0,
                            writable: !0,
                          })
                        : (n[a] = o),
                      n
                    );
                  }
                  var m = "playing",
                    h = "paused",
                    y = "finished",
                    l = (function (n) {
                      v(o, n);
                      var a = f(o);
                      function o(r) {
                        var t, s, i;
                        return (
                          E(this, o),
                          (i = a.call(this)),
                          O(P(i), "audioContext", null),
                          O(P(i), "offlineAudioContext", null),
                          O(
                            P(i),
                            "stateBehaviors",
                            ((t = {}),
                            O(t, m, {
                              init: function () {
                                this.addOnAudioProcess();
                              },
                              getPlayedPercents: function () {
                                var u = this.getDuration();
                                return this.getCurrentTime() / u || 0;
                              },
                              getCurrentTime: function () {
                                return (
                                  this.startPosition + this.getPlayedTime()
                                );
                              },
                            }),
                            O(t, h, {
                              init: function () {
                                this.removeOnAudioProcess();
                              },
                              getPlayedPercents: function () {
                                var u = this.getDuration();
                                return this.getCurrentTime() / u || 0;
                              },
                              getCurrentTime: function () {
                                return this.startPosition;
                              },
                            }),
                            O(t, y, {
                              init: function () {
                                (this.removeOnAudioProcess(),
                                  this.fireEvent("finish"));
                              },
                              getPlayedPercents: function () {
                                return 1;
                              },
                              getCurrentTime: function () {
                                return this.getDuration();
                              },
                            }),
                            t),
                          ),
                          (i.params = r),
                          (i.ac =
                            r.audioContext ||
                            (i.supportsWebAudio() ? i.getAudioContext() : {})),
                          (i.lastPlay = i.ac.currentTime),
                          (i.startPosition = 0),
                          (i.scheduledPause = null),
                          (i.states =
                            ((s = {}),
                            O(s, m, Object.create(i.stateBehaviors[m])),
                            O(s, h, Object.create(i.stateBehaviors[h])),
                            O(s, y, Object.create(i.stateBehaviors[y])),
                            s)),
                          (i.buffer = null),
                          (i.filters = []),
                          (i.gainNode = null),
                          (i.mergedPeaks = null),
                          (i.offlineAc = null),
                          (i.peaks = null),
                          (i.playbackRate = 1),
                          (i.analyser = null),
                          (i.scriptNode = null),
                          (i.source = null),
                          (i.splitPeaks = []),
                          (i.state = null),
                          (i.explicitDuration = r.duration),
                          (i.sinkStreamDestination = null),
                          (i.sinkAudioElement = null),
                          (i.destroyed = !1),
                          i
                        );
                      }
                      return (
                        A(o, [
                          {
                            key: "supportsWebAudio",
                            value: function () {
                              return !!(
                                window.AudioContext || window.webkitAudioContext
                              );
                            },
                          },
                          {
                            key: "getAudioContext",
                            value: function () {
                              return (
                                window.WaveSurferAudioContext ||
                                  (window.WaveSurferAudioContext = new (
                                    window.AudioContext ||
                                    window.webkitAudioContext
                                  )()),
                                window.WaveSurferAudioContext
                              );
                            },
                          },
                          {
                            key: "getOfflineAudioContext",
                            value: function (t) {
                              return (
                                window.WaveSurferOfflineAudioContext ||
                                  (window.WaveSurferOfflineAudioContext = new (
                                    window.OfflineAudioContext ||
                                    window.webkitOfflineAudioContext
                                  )(1, 2, t)),
                                window.WaveSurferOfflineAudioContext
                              );
                            },
                          },
                          {
                            key: "init",
                            value: function () {
                              (this.createVolumeNode(),
                                this.createScriptNode(),
                                this.createAnalyserNode(),
                                this.setState(h),
                                this.setPlaybackRate(this.params.audioRate),
                                this.setLength(0));
                            },
                          },
                          {
                            key: "disconnectFilters",
                            value: function () {
                              this.filters &&
                                (this.filters.forEach(function (t) {
                                  t && t.disconnect();
                                }),
                                (this.filters = null),
                                this.analyser.connect(this.gainNode));
                            },
                          },
                          {
                            key: "setState",
                            value: function (t) {
                              this.state !== this.states[t] &&
                                ((this.state = this.states[t]),
                                this.state.init.call(this));
                            },
                          },
                          {
                            key: "setFilter",
                            value: function () {
                              for (
                                var t = arguments.length,
                                  s = new Array(t),
                                  i = 0;
                                i < t;
                                i++
                              )
                                s[i] = arguments[i];
                              this.setFilters(s);
                            },
                          },
                          {
                            key: "setFilters",
                            value: function (t) {
                              (this.disconnectFilters(),
                                t &&
                                  t.length &&
                                  ((this.filters = t),
                                  this.analyser.disconnect(),
                                  t
                                    .reduce(function (s, i) {
                                      return (s.connect(i), i);
                                    }, this.analyser)
                                    .connect(this.gainNode)));
                            },
                          },
                          {
                            key: "createScriptNode",
                            value: function () {
                              (this.params.audioScriptProcessor
                                ? (this.scriptNode =
                                    this.params.audioScriptProcessor)
                                : this.ac.createScriptProcessor
                                  ? (this.scriptNode =
                                      this.ac.createScriptProcessor(
                                        o.scriptBufferSize,
                                      ))
                                  : (this.scriptNode =
                                      this.ac.createJavaScriptNode(
                                        o.scriptBufferSize,
                                      )),
                                this.scriptNode.connect(this.ac.destination));
                            },
                          },
                          {
                            key: "addOnAudioProcess",
                            value: function () {
                              var t = this;
                              this.scriptNode.onaudioprocess = function () {
                                var s = t.getCurrentTime();
                                s >= t.getDuration()
                                  ? (t.setState(y), t.fireEvent("pause"))
                                  : s >= t.scheduledPause
                                    ? t.pause()
                                    : t.state === t.states[m] &&
                                      t.fireEvent("audioprocess", s);
                              };
                            },
                          },
                          {
                            key: "removeOnAudioProcess",
                            value: function () {
                              this.scriptNode.onaudioprocess = null;
                            },
                          },
                          {
                            key: "createAnalyserNode",
                            value: function () {
                              ((this.analyser = this.ac.createAnalyser()),
                                this.analyser.connect(this.gainNode));
                            },
                          },
                          {
                            key: "createVolumeNode",
                            value: function () {
                              (this.ac.createGain
                                ? (this.gainNode = this.ac.createGain())
                                : (this.gainNode = this.ac.createGainNode()),
                                this.gainNode.connect(this.ac.destination));
                            },
                          },
                          {
                            key: "setSinkId",
                            value: function (t) {
                              return t
                                ? (this.sinkAudioElement ||
                                    ((this.sinkAudioElement =
                                      new window.Audio()),
                                    (this.sinkAudioElement.autoplay = !0)),
                                  this.sinkAudioElement.setSinkId
                                    ? (this.sinkStreamDestination ||
                                        (this.sinkStreamDestination =
                                          this.ac.createMediaStreamDestination()),
                                      this.gainNode.disconnect(),
                                      this.gainNode.connect(
                                        this.sinkStreamDestination,
                                      ),
                                      (this.sinkAudioElement.srcObject =
                                        this.sinkStreamDestination.stream),
                                      this.sinkAudioElement.setSinkId(t))
                                    : Promise.reject(
                                        new Error(
                                          "setSinkId is not supported in your browser",
                                        ),
                                      ))
                                : Promise.reject(
                                    new Error("Invalid deviceId: " + t),
                                  );
                            },
                          },
                          {
                            key: "setVolume",
                            value: function (t) {
                              this.gainNode.gain.setValueAtTime(
                                t,
                                this.ac.currentTime,
                              );
                            },
                          },
                          {
                            key: "getVolume",
                            value: function () {
                              return this.gainNode.gain.value;
                            },
                          },
                          {
                            key: "decodeArrayBuffer",
                            value: function (t, s, i) {
                              (this.offlineAc ||
                                (this.offlineAc = this.getOfflineAudioContext(
                                  this.ac && this.ac.sampleRate
                                    ? this.ac.sampleRate
                                    : 44100,
                                )),
                                "webkitAudioContext" in window
                                  ? this.offlineAc.decodeAudioData(
                                      t,
                                      function (e) {
                                        return s(e);
                                      },
                                      i,
                                    )
                                  : this.offlineAc
                                      .decodeAudioData(t)
                                      .then(function (e) {
                                        return s(e);
                                      })
                                      .catch(function (e) {
                                        return i(e);
                                      }));
                            },
                          },
                          {
                            key: "setPeaks",
                            value: function (t, s) {
                              (s != null && (this.explicitDuration = s),
                                (this.peaks = t));
                            },
                          },
                          {
                            key: "setLength",
                            value: function (t) {
                              if (!(
                                this.mergedPeaks &&
                                t == 2 * this.mergedPeaks.length - 1 + 2
                              )) {
                                ((this.splitPeaks = []),
                                  (this.mergedPeaks = []));
                                var s = this.buffer
                                    ? this.buffer.numberOfChannels
                                    : 1,
                                  i;
                                for (i = 0; i < s; i++)
                                  ((this.splitPeaks[i] = []),
                                    (this.splitPeaks[i][2 * (t - 1)] = 0),
                                    (this.splitPeaks[i][2 * (t - 1) + 1] = 0));
                                ((this.mergedPeaks[2 * (t - 1)] = 0),
                                  (this.mergedPeaks[2 * (t - 1) + 1] = 0));
                              }
                            },
                          },
                          {
                            key: "getPeaks",
                            value: function (t, s, i) {
                              if (this.peaks) return this.peaks;
                              if (!this.buffer) return [];
                              if (
                                ((s = s || 0),
                                (i = i || t - 1),
                                this.setLength(t),
                                !this.buffer)
                              )
                                return this.params.splitChannels
                                  ? this.splitPeaks
                                  : this.mergedPeaks;
                              if (!this.buffer.length) {
                                var e = this.createBuffer(
                                  1,
                                  4096,
                                  this.sampleRate,
                                );
                                this.buffer = e.buffer;
                              }
                              var u = this.buffer.length / t,
                                b = ~~(u / 10) || 1,
                                T = this.buffer.numberOfChannels,
                                S;
                              for (S = 0; S < T; S++) {
                                var D = this.splitPeaks[S],
                                  j = this.buffer.getChannelData(S),
                                  x = void 0;
                                for (x = s; x <= i; x++) {
                                  var I = ~~(x * u),
                                    N = ~~(I + u),
                                    B = j[I],
                                    z = B,
                                    L = void 0;
                                  for (L = I; L < N; L += b) {
                                    var H = j[L];
                                    (H > z && (z = H), H < B && (B = H));
                                  }
                                  ((D[2 * x] = z),
                                    (D[2 * x + 1] = B),
                                    (S == 0 || z > this.mergedPeaks[2 * x]) &&
                                      (this.mergedPeaks[2 * x] = z),
                                    (S == 0 ||
                                      B < this.mergedPeaks[2 * x + 1]) &&
                                      (this.mergedPeaks[2 * x + 1] = B));
                                }
                              }
                              return this.params.splitChannels
                                ? this.splitPeaks
                                : this.mergedPeaks;
                            },
                          },
                          {
                            key: "getPlayedPercents",
                            value: function () {
                              return this.state.getPlayedPercents.call(this);
                            },
                          },
                          {
                            key: "disconnectSource",
                            value: function () {
                              this.source && this.source.disconnect();
                            },
                          },
                          {
                            key: "destroyWebAudio",
                            value: function () {
                              (this.disconnectFilters(),
                                this.disconnectSource(),
                                this.gainNode.disconnect(),
                                this.scriptNode.disconnect(),
                                this.analyser.disconnect(),
                                this.params.closeAudioContext &&
                                  (typeof this.ac.close == "function" &&
                                    this.ac.state != "closed" &&
                                    this.ac.close(),
                                  (this.ac = null),
                                  this.params.audioContext
                                    ? (this.params.audioContext = null)
                                    : (window.WaveSurferAudioContext = null),
                                  (window.WaveSurferOfflineAudioContext =
                                    null)),
                                this.sinkStreamDestination &&
                                  (this.sinkAudioElement.pause(),
                                  (this.sinkAudioElement.srcObject = null),
                                  this.sinkStreamDestination.disconnect(),
                                  (this.sinkStreamDestination = null)));
                            },
                          },
                          {
                            key: "destroy",
                            value: function () {
                              (this.isPaused() || this.pause(),
                                this.unAll(),
                                (this.buffer = null),
                                (this.destroyed = !0),
                                this.destroyWebAudio());
                            },
                          },
                          {
                            key: "load",
                            value: function (t) {
                              ((this.startPosition = 0),
                                (this.lastPlay = this.ac.currentTime),
                                (this.buffer = t),
                                this.createSource());
                            },
                          },
                          {
                            key: "createSource",
                            value: function () {
                              (this.disconnectSource(),
                                (this.source = this.ac.createBufferSource()),
                                (this.source.start =
                                  this.source.start || this.source.noteGrainOn),
                                (this.source.stop =
                                  this.source.stop || this.source.noteOff),
                                this.setPlaybackRate(this.playbackRate),
                                (this.source.buffer = this.buffer),
                                this.source.connect(this.analyser));
                            },
                          },
                          {
                            key: "resumeAudioContext",
                            value: function () {
                              this.ac.state == "suspended" &&
                                this.ac.resume &&
                                this.ac.resume();
                            },
                          },
                          {
                            key: "isPaused",
                            value: function () {
                              return this.state !== this.states[m];
                            },
                          },
                          {
                            key: "getDuration",
                            value: function () {
                              return this.explicitDuration
                                ? this.explicitDuration
                                : this.buffer
                                  ? this.buffer.duration
                                  : 0;
                            },
                          },
                          {
                            key: "seekTo",
                            value: function (t, s) {
                              if (this.buffer)
                                return (
                                  (this.scheduledPause = null),
                                  t == null &&
                                    ((t = this.getCurrentTime()),
                                    t >= this.getDuration() && (t = 0)),
                                  s == null && (s = this.getDuration()),
                                  (this.startPosition = t),
                                  (this.lastPlay = this.ac.currentTime),
                                  this.state === this.states[y] &&
                                    this.setState(h),
                                  { start: t, end: s }
                                );
                            },
                          },
                          {
                            key: "getPlayedTime",
                            value: function () {
                              return (
                                (this.ac.currentTime - this.lastPlay) *
                                this.playbackRate
                              );
                            },
                          },
                          {
                            key: "play",
                            value: function (t, s) {
                              if (this.buffer) {
                                this.createSource();
                                var i = this.seekTo(t, s);
                                ((t = i.start),
                                  (s = i.end),
                                  (this.scheduledPause = s),
                                  this.source.start(0, t),
                                  this.resumeAudioContext(),
                                  this.setState(m),
                                  this.fireEvent("play"));
                              }
                            },
                          },
                          {
                            key: "pause",
                            value: function () {
                              ((this.scheduledPause = null),
                                (this.startPosition += this.getPlayedTime()));
                              try {
                                this.source && this.source.stop(0);
                              } catch {}
                              (this.setState(h), this.fireEvent("pause"));
                            },
                          },
                          {
                            key: "getCurrentTime",
                            value: function () {
                              return this.state.getCurrentTime.call(this);
                            },
                          },
                          {
                            key: "getPlaybackRate",
                            value: function () {
                              return this.playbackRate;
                            },
                          },
                          {
                            key: "setPlaybackRate",
                            value: function (t) {
                              ((this.playbackRate = t || 1),
                                this.source &&
                                  this.source.playbackRate.setValueAtTime(
                                    this.playbackRate,
                                    this.ac.currentTime,
                                  ));
                            },
                          },
                          {
                            key: "setPlayEnd",
                            value: function (t) {
                              this.scheduledPause = t;
                            },
                          },
                        ]),
                        o
                      );
                    })(R.Observer);
                  ((c.default = l),
                    O(l, "scriptBufferSize", 256),
                    (V.exports = c.default));
                },
                "./node_modules/debounce/index.js": (V) => {
                  function c(w, k, R) {
                    var C, _, E, W, A;
                    k == null && (k = 100);
                    function v() {
                      var f = Date.now() - W;
                      f < k && f >= 0
                        ? (C = setTimeout(v, k - f))
                        : ((C = null),
                          R || ((A = w.apply(E, _)), (E = _ = null)));
                    }
                    var p = function () {
                      ((E = this), (_ = arguments), (W = Date.now()));
                      var f = R && !C;
                      return (
                        C || (C = setTimeout(v, k)),
                        f && ((A = w.apply(E, _)), (E = _ = null)),
                        A
                      );
                    };
                    return (
                      (p.clear = function () {
                        C && (clearTimeout(C), (C = null));
                      }),
                      (p.flush = function () {
                        C &&
                          ((A = w.apply(E, _)),
                          (E = _ = null),
                          clearTimeout(C),
                          (C = null));
                      }),
                      p
                    );
                  }
                  ((c.debounce = c), (V.exports = c));
                },
              },
              G = {};
            function q(V) {
              var c = G[V];
              if (c !== void 0) return c.exports;
              var w = (G[V] = { exports: {} });
              return (U[V](w, w.exports, q), w.exports);
            }
            var X = q("./src/wavesurfer.js");
            return X;
          })(),
        );
      })(Z)),
    Z.exports
  );
}
var re = ue();
const le = se(re),
  ce = oe({ __proto__: null, default: le }, [re]);
export { le as W, ce as w };
//# sourceMappingURL=wavesurfer-C3DYPLwL.js.map
