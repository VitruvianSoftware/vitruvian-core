(function () {
  try {
    var M =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    M.SENTRY_RELEASE = { id: "4.3.209" };
    var m = new M.Error().stack;
    m &&
      ((M._sentryDebugIds = M._sentryDebugIds || {}),
      (M._sentryDebugIds[m] = "8570f47d-27e5-4d8d-a849-4278966f1e42"),
      (M._sentryDebugIdIdentifier =
        "sentry-dbid-8570f47d-27e5-4d8d-a849-4278966f1e42"));
  } catch {}
})();
var W = {};
(function M(m, C, O, S) {
  var B = !!(
      m.Worker &&
      m.Blob &&
      m.Promise &&
      m.OffscreenCanvas &&
      m.OffscreenCanvasRenderingContext2D &&
      m.HTMLCanvasElement &&
      m.HTMLCanvasElement.prototype.transferControlToOffscreen &&
      m.URL &&
      m.URL.createObjectURL
    ),
    N = typeof Path2D == "function" && typeof DOMMatrix == "function",
    P = (function () {
      if (!m.OffscreenCanvas) return !1;
      var r = new OffscreenCanvas(1, 1),
        e = r.getContext("2d");
      e.fillRect(0, 0, 1, 1);
      var a = r.transferToImageBitmap();
      try {
        e.createPattern(a, "no-repeat");
      } catch {
        return !1;
      }
      return !0;
    })();
  function A() {}
  function R(r) {
    var e = C.exports.Promise,
      a = e !== void 0 ? e : m.Promise;
    return typeof a == "function" ? new a(r) : (r(A, A), null);
  }
  var x = (function (r, e) {
      return {
        transform: function (a) {
          if (r) return a;
          if (e.has(a)) return e.get(a);
          var t = new OffscreenCanvas(a.width, a.height),
            o = t.getContext("2d");
          return (o.drawImage(a, 0, 0), e.set(a, t), t);
        },
        clear: function () {
          e.clear();
        },
      };
    })(P, new Map()),
    I = (function () {
      var r = Math.floor(16.666666666666668),
        e,
        a,
        t = {},
        o = 0;
      return (
        typeof requestAnimationFrame == "function" &&
        typeof cancelAnimationFrame == "function"
          ? ((e = function (i) {
              var l = Math.random();
              return (
                (t[l] = requestAnimationFrame(function n(s) {
                  o === s || o + r - 1 < s
                    ? ((o = s), delete t[l], i())
                    : (t[l] = requestAnimationFrame(n));
                })),
                l
              );
            }),
            (a = function (i) {
              t[i] && cancelAnimationFrame(t[i]);
            }))
          : ((e = function (i) {
              return setTimeout(i, r);
            }),
            (a = function (i) {
              return clearTimeout(i);
            })),
        { frame: e, cancel: a }
      );
    })(),
    k = (function () {
      var r,
        e,
        a = {};
      function t(o) {
        function i(l, n) {
          o.postMessage({ options: l || {}, callback: n });
        }
        ((o.init = function (n) {
          var s = n.transferControlToOffscreen();
          o.postMessage({ canvas: s }, [s]);
        }),
          (o.fire = function (n, s, u) {
            if (e) return (i(n, null), e);
            var h = Math.random().toString(36).slice(2);
            return (
              (e = R(function (d) {
                function f(g) {
                  g.data.callback === h &&
                    (delete a[h],
                    o.removeEventListener("message", f),
                    (e = null),
                    x.clear(),
                    u(),
                    d());
                }
                (o.addEventListener("message", f),
                  i(n, h),
                  (a[h] = f.bind(null, { data: { callback: h } })));
              })),
              e
            );
          }),
          (o.reset = function () {
            o.postMessage({ reset: !0 });
            for (var n in a) (a[n](), delete a[n]);
          }));
      }
      return function () {
        if (r) return r;
        if (!O && B) {
          var o = [
            "var CONFETTI, SIZE = {}, module = {};",
            "(" + M.toString() + ")(this, module, true, SIZE);",
            "onmessage = function(msg) {",
            "  if (msg.data.options) {",
            "    CONFETTI(msg.data.options).then(function () {",
            "      if (msg.data.callback) {",
            "        postMessage({ callback: msg.data.callback });",
            "      }",
            "    });",
            "  } else if (msg.data.reset) {",
            "    CONFETTI && CONFETTI.reset();",
            "  } else if (msg.data.resize) {",
            "    SIZE.width = msg.data.resize.width;",
            "    SIZE.height = msg.data.resize.height;",
            "  } else if (msg.data.canvas) {",
            "    SIZE.width = msg.data.canvas.width;",
            "    SIZE.height = msg.data.canvas.height;",
            "    CONFETTI = module.exports.create(msg.data.canvas);",
            "  }",
            "}",
          ].join(`
`);
          try {
            r = new Worker(URL.createObjectURL(new Blob([o])));
          } catch (i) {
            return (
              typeof console !== void 0 &&
                typeof console.warn == "function" &&
                console.warn("🎊 Could not load worker", i),
              null
            );
          }
          t(r);
        }
        return r;
      };
    })(),
    T = {
      particleCount: 50,
      angle: 90,
      spread: 45,
      startVelocity: 45,
      decay: 0.9,
      gravity: 1,
      drift: 0,
      ticks: 200,
      x: 0.5,
      y: 0.5,
      shapes: ["square", "circle"],
      zIndex: 100,
      colors: [
        "#26ccff",
        "#a25afd",
        "#ff5e7e",
        "#88ff5a",
        "#fcff42",
        "#ffa62d",
        "#ff36ff",
      ],
      disableForReducedMotion: !1,
      scalar: 1,
    };
  function L(r, e) {
    return e ? e(r) : r;
  }
  function G(r) {
    return r != null;
  }
  function v(r, e, a) {
    return L(r && G(r[e]) ? r[e] : T[e], a);
  }
  function $(r) {
    return r < 0 ? 0 : Math.floor(r);
  }
  function J(r, e) {
    return Math.floor(Math.random() * (e - r)) + r;
  }
  function V(r) {
    return parseInt(r, 16);
  }
  function K(r) {
    return r.map(Q);
  }
  function Q(r) {
    var e = String(r).replace(/[^0-9a-f]/gi, "");
    return (
      e.length < 6 && (e = e[0] + e[0] + e[1] + e[1] + e[2] + e[2]),
      {
        r: V(e.substring(0, 2)),
        g: V(e.substring(2, 4)),
        b: V(e.substring(4, 6)),
      }
    );
  }
  function Y(r) {
    var e = v(r, "origin", Object);
    return ((e.x = v(e, "x", Number)), (e.y = v(e, "y", Number)), e);
  }
  function X(r) {
    ((r.width = document.documentElement.clientWidth),
      (r.height = document.documentElement.clientHeight));
  }
  function ee(r) {
    var e = r.getBoundingClientRect();
    ((r.width = e.width), (r.height = e.height));
  }
  function re(r) {
    var e = document.createElement("canvas");
    return (
      (e.style.position = "fixed"),
      (e.style.top = "0px"),
      (e.style.left = "0px"),
      (e.style.pointerEvents = "none"),
      (e.style.zIndex = r),
      e
    );
  }
  function ae(r, e, a, t, o, i, l, n, s) {
    (r.save(),
      r.translate(e, a),
      r.rotate(i),
      r.scale(t, o),
      r.arc(0, 0, 1, l, n, s),
      r.restore());
  }
  function ne(r) {
    var e = r.angle * (Math.PI / 180),
      a = r.spread * (Math.PI / 180);
    return {
      x: r.x,
      y: r.y,
      wobble: Math.random() * 10,
      wobbleSpeed: Math.min(0.11, Math.random() * 0.1 + 0.05),
      velocity: r.startVelocity * 0.5 + Math.random() * r.startVelocity,
      angle2D: -e + (0.5 * a - Math.random() * a),
      tiltAngle: (Math.random() * (0.75 - 0.25) + 0.25) * Math.PI,
      color: r.color,
      shape: r.shape,
      tick: 0,
      totalTicks: r.ticks,
      decay: r.decay,
      drift: r.drift,
      random: Math.random() + 2,
      tiltSin: 0,
      tiltCos: 0,
      wobbleX: 0,
      wobbleY: 0,
      gravity: r.gravity * 3,
      ovalScalar: 0.6,
      scalar: r.scalar,
      flat: r.flat,
    };
  }
  function te(r, e) {
    ((e.x += Math.cos(e.angle2D) * e.velocity + e.drift),
      (e.y += Math.sin(e.angle2D) * e.velocity + e.gravity),
      (e.velocity *= e.decay),
      e.flat
        ? ((e.wobble = 0),
          (e.wobbleX = e.x + 10 * e.scalar),
          (e.wobbleY = e.y + 10 * e.scalar),
          (e.tiltSin = 0),
          (e.tiltCos = 0),
          (e.random = 1))
        : ((e.wobble += e.wobbleSpeed),
          (e.wobbleX = e.x + 10 * e.scalar * Math.cos(e.wobble)),
          (e.wobbleY = e.y + 10 * e.scalar * Math.sin(e.wobble)),
          (e.tiltAngle += 0.1),
          (e.tiltSin = Math.sin(e.tiltAngle)),
          (e.tiltCos = Math.cos(e.tiltAngle)),
          (e.random = Math.random() + 2)));
    var a = e.tick++ / e.totalTicks,
      t = e.x + e.random * e.tiltCos,
      o = e.y + e.random * e.tiltSin,
      i = e.wobbleX + e.random * e.tiltCos,
      l = e.wobbleY + e.random * e.tiltSin;
    if (
      ((r.fillStyle =
        "rgba(" +
        e.color.r +
        ", " +
        e.color.g +
        ", " +
        e.color.b +
        ", " +
        (1 - a) +
        ")"),
      r.beginPath(),
      N &&
        e.shape.type === "path" &&
        typeof e.shape.path == "string" &&
        Array.isArray(e.shape.matrix))
    )
      r.fill(
        ie(
          e.shape.path,
          e.shape.matrix,
          e.x,
          e.y,
          Math.abs(i - t) * 0.1,
          Math.abs(l - o) * 0.1,
          (Math.PI / 10) * e.wobble,
        ),
      );
    else if (e.shape.type === "bitmap") {
      var n = (Math.PI / 10) * e.wobble,
        s = Math.abs(i - t) * 0.1,
        u = Math.abs(l - o) * 0.1,
        h = e.shape.bitmap.width * e.scalar,
        d = e.shape.bitmap.height * e.scalar,
        f = new DOMMatrix([
          Math.cos(n) * s,
          Math.sin(n) * s,
          -Math.sin(n) * u,
          Math.cos(n) * u,
          e.x,
          e.y,
        ]);
      f.multiplySelf(new DOMMatrix(e.shape.matrix));
      var g = r.createPattern(x.transform(e.shape.bitmap), "no-repeat");
      (g.setTransform(f),
        (r.globalAlpha = 1 - a),
        (r.fillStyle = g),
        r.fillRect(e.x - h / 2, e.y - d / 2, h, d),
        (r.globalAlpha = 1));
    } else if (e.shape === "circle")
      r.ellipse
        ? r.ellipse(
            e.x,
            e.y,
            Math.abs(i - t) * e.ovalScalar,
            Math.abs(l - o) * e.ovalScalar,
            (Math.PI / 10) * e.wobble,
            0,
            2 * Math.PI,
          )
        : ae(
            r,
            e.x,
            e.y,
            Math.abs(i - t) * e.ovalScalar,
            Math.abs(l - o) * e.ovalScalar,
            (Math.PI / 10) * e.wobble,
            0,
            2 * Math.PI,
          );
    else if (e.shape === "star")
      for (
        var c = (Math.PI / 2) * 3,
          y = 4 * e.scalar,
          p = 8 * e.scalar,
          b = e.x,
          E = e.y,
          F = 5,
          w = Math.PI / F;
        F--;
      )
        ((b = e.x + Math.cos(c) * p),
          (E = e.y + Math.sin(c) * p),
          r.lineTo(b, E),
          (c += w),
          (b = e.x + Math.cos(c) * y),
          (E = e.y + Math.sin(c) * y),
          r.lineTo(b, E),
          (c += w));
    else
      (r.moveTo(Math.floor(e.x), Math.floor(e.y)),
        r.lineTo(Math.floor(e.wobbleX), Math.floor(o)),
        r.lineTo(Math.floor(i), Math.floor(l)),
        r.lineTo(Math.floor(t), Math.floor(e.wobbleY)));
    return (r.closePath(), r.fill(), e.tick < e.totalTicks);
  }
  function oe(r, e, a, t, o) {
    var i = e.slice(),
      l = r.getContext("2d"),
      n,
      s,
      u = R(function (h) {
        function d() {
          ((n = s = null),
            l.clearRect(0, 0, t.width, t.height),
            x.clear(),
            o(),
            h());
        }
        function f() {
          (O &&
            !(t.width === S.width && t.height === S.height) &&
            ((t.width = r.width = S.width), (t.height = r.height = S.height)),
            !t.width &&
              !t.height &&
              (a(r), (t.width = r.width), (t.height = r.height)),
            l.clearRect(0, 0, t.width, t.height),
            (i = i.filter(function (g) {
              return te(l, g);
            })),
            i.length ? (n = I.frame(f)) : d());
        }
        ((n = I.frame(f)), (s = d));
      });
    return {
      addFettis: function (h) {
        return ((i = i.concat(h)), u);
      },
      canvas: r,
      promise: u,
      reset: function () {
        (n && I.cancel(n), s && s());
      },
    };
  }
  function U(r, e) {
    var a = !r,
      t = !!v(e || {}, "resize"),
      o = !1,
      i = v(e, "disableForReducedMotion", Boolean),
      l = B && !!v(e || {}, "useWorker"),
      n = l ? k() : null,
      s = a ? X : ee,
      u = r && n ? !!r.__confetti_initialized : !1,
      h =
        typeof matchMedia == "function" &&
        matchMedia("(prefers-reduced-motion)").matches,
      d;
    function f(c, y, p) {
      for (
        var b = v(c, "particleCount", $),
          E = v(c, "angle", Number),
          F = v(c, "spread", Number),
          w = v(c, "startVelocity", Number),
          ce = v(c, "decay", Number),
          ue = v(c, "gravity", Number),
          de = v(c, "drift", Number),
          z = v(c, "colors", K),
          he = v(c, "ticks", Number),
          Z = v(c, "shapes"),
          fe = v(c, "scalar"),
          ve = !!v(c, "flat"),
          q = Y(c),
          H = b,
          _ = [],
          me = r.width * q.x,
          ge = r.height * q.y;
        H--;
      )
        _.push(
          ne({
            x: me,
            y: ge,
            angle: E,
            spread: F,
            startVelocity: w,
            color: z[H % z.length],
            shape: Z[J(0, Z.length)],
            ticks: he,
            decay: ce,
            gravity: ue,
            drift: de,
            scalar: fe,
            flat: ve,
          }),
        );
      return d ? d.addFettis(_) : ((d = oe(r, _, s, y, p)), d.promise);
    }
    function g(c) {
      var y = i || v(c, "disableForReducedMotion", Boolean),
        p = v(c, "zIndex", Number);
      if (y && h)
        return R(function (w) {
          w();
        });
      (a && d
        ? (r = d.canvas)
        : a && !r && ((r = re(p)), document.body.appendChild(r)),
        t && !u && s(r));
      var b = { width: r.width, height: r.height };
      (n && !u && n.init(r), (u = !0), n && (r.__confetti_initialized = !0));
      function E() {
        if (n) {
          var w = {
            getBoundingClientRect: function () {
              if (!a) return r.getBoundingClientRect();
            },
          };
          (s(w),
            n.postMessage({ resize: { width: w.width, height: w.height } }));
          return;
        }
        b.width = b.height = null;
      }
      function F() {
        ((d = null),
          t && ((o = !1), m.removeEventListener("resize", E)),
          a &&
            r &&
            (document.body.contains(r) && document.body.removeChild(r),
            (r = null),
            (u = !1)));
      }
      return (
        t && !o && ((o = !0), m.addEventListener("resize", E, !1)),
        n ? n.fire(c, b, F) : f(c, b, F)
      );
    }
    return (
      (g.reset = function () {
        (n && n.reset(), d && d.reset());
      }),
      g
    );
  }
  var D;
  function j() {
    return (D || (D = U(null, { useWorker: !0, resize: !0 })), D);
  }
  function ie(r, e, a, t, o, i, l) {
    var n = new Path2D(r),
      s = new Path2D();
    s.addPath(n, new DOMMatrix(e));
    var u = new Path2D();
    return (
      u.addPath(
        s,
        new DOMMatrix([
          Math.cos(l) * o,
          Math.sin(l) * o,
          -Math.sin(l) * i,
          Math.cos(l) * i,
          a,
          t,
        ]),
      ),
      u
    );
  }
  function le(r) {
    if (!N) throw new Error("path confetti are not supported in this browser");
    var e, a;
    typeof r == "string" ? (e = r) : ((e = r.path), (a = r.matrix));
    var t = new Path2D(e),
      o = document.createElement("canvas"),
      i = o.getContext("2d");
    if (!a) {
      for (var l = 1e3, n = l, s = l, u = 0, h = 0, d, f, g = 0; g < l; g += 2)
        for (var c = 0; c < l; c += 2)
          i.isPointInPath(t, g, c, "nonzero") &&
            ((n = Math.min(n, g)),
            (s = Math.min(s, c)),
            (u = Math.max(u, g)),
            (h = Math.max(h, c)));
      ((d = u - n), (f = h - s));
      var y = 10,
        p = Math.min(y / d, y / f);
      a = [p, 0, 0, p, -Math.round(d / 2 + n) * p, -Math.round(f / 2 + s) * p];
    }
    return { type: "path", path: e, matrix: a };
  }
  function se(r) {
    var e,
      a = 1,
      t = "#000000",
      o =
        '"Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol", "Noto Color Emoji", "EmojiOne Color", "Android Emoji", "Twemoji Mozilla", "system emoji", sans-serif';
    typeof r == "string"
      ? (e = r)
      : ((e = r.text),
        (a = "scalar" in r ? r.scalar : a),
        (o = "fontFamily" in r ? r.fontFamily : o),
        (t = "color" in r ? r.color : t));
    var i = 10 * a,
      l = "" + i + "px " + o,
      n = new OffscreenCanvas(i, i),
      s = n.getContext("2d");
    s.font = l;
    var u = s.measureText(e),
      h = Math.ceil(u.actualBoundingBoxRight + u.actualBoundingBoxLeft),
      d = Math.ceil(u.actualBoundingBoxAscent + u.actualBoundingBoxDescent),
      f = 2,
      g = u.actualBoundingBoxLeft + f,
      c = u.actualBoundingBoxAscent + f;
    ((h += f + f),
      (d += f + f),
      (n = new OffscreenCanvas(h, d)),
      (s = n.getContext("2d")),
      (s.font = l),
      (s.fillStyle = t),
      s.fillText(e, g, c));
    var y = 1 / a;
    return {
      type: "bitmap",
      bitmap: n.transferToImageBitmap(),
      matrix: [y, 0, 0, y, (-h * y) / 2, (-d * y) / 2],
    };
  }
  ((C.exports = function () {
    return j().apply(this, arguments);
  }),
    (C.exports.reset = function () {
      j().reset();
    }),
    (C.exports.create = U),
    (C.exports.shapeFromPath = le),
    (C.exports.shapeFromText = se));
})(
  (function () {
    return typeof window < "u" ? window : typeof self < "u" ? self : this || {};
  })(),
  W,
  !1,
);
const ye = W.exports;
W.exports.create;
const Me = () => {
  const M = document.getElementById("confetti-canvas");
  if (!M) return;
  const m = ye.create(M, { resize: !0, disableForReducedMotion: !0 }),
    C = 100,
    O = { origin: { y: 1 }, ticks: 5e4, gravity: 2 },
    S = () => {
      const P = window.innerWidth;
      return P >= 2e3 ? 1.3 : P >= 1600 ? 1.2 : P >= 1280 ? 1.1 : 1;
    },
    B = (P) => {
      const A = { ...O.origin, x: P },
        R = S(),
        x = (k) => k * R,
        I = (k, T) => {
          const L = {
            ...T,
            spread: T.spread ? x(T.spread) : void 0,
            startVelocity: T.startVelocity ? x(T.startVelocity) : void 0,
            scalar: T.scalar ? x(T.scalar) : void 0,
          };
          m({ ...O, ...L, origin: A, particleCount: Math.floor(k * R * C) });
        };
      (I(10, { spread: 26, startVelocity: 80 }),
        I(12, { spread: 60, startVelocity: 50 }),
        I(15, { spread: 100, scalar: 0.8, startVelocity: 60 }),
        I(8, { spread: 120, startVelocity: 80, scalar: 1.2 }),
        I(9, { spread: 120, startVelocity: 45 }));
    };
  setTimeout(() => {
    try {
      (B(0), B(1));
    } finally {
      setTimeout(() => window.close(), 1e4);
    }
  }, 250);
};
Me();
//# sourceMappingURL=confetti-Nmr38teu.js.map
