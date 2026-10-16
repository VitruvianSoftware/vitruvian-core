import {
  aG as $,
  dk as C,
  cK as m,
  as as di,
  c4 as Ge,
  G as ke,
  cY as Ee,
  ba as De,
  et as ci,
  ev as We,
  dH as Me,
  ex as R,
  w as V,
  aT as H,
  aI as fi,
  X as mi,
  aX as pi,
  cn as vi,
  co as hi,
  aw as gi,
  aj as bi,
  cZ as je,
  cd as wi,
  aN as Oe,
  ak as Si,
  g as Pi,
  ab as Ci,
  U as yi,
  b8 as Ti,
  ck as Ai,
  dq as Yi,
  cy as Xi,
  N as Be,
} from "./App-CsJiApxN.js";
import {
  cP as Ei,
  a2 as j,
  cD as Z,
  c as K,
  a6 as N,
  m as qe,
  d as Di,
  cN as Ni,
  bD as _i,
} from "./matrix-util-Cr_UwXbj.js";
import "./sentry-common-BxRELKId.js";
import "./index-Cw3pknxT.js";
import "./index-Dhe7xemD.js";
import "./index-CcYzEQCb.js";
import "./main-process-state-wkFhis-C.js";
import "./report-dialog-7bETf2vU.js";
import "./helpHubMessages-CXhGQ9cB.js";
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
    var n = new e.Error().stack;
    n &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[n] = "41111994-a2f5-4091-a53f-80646355bc97"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-41111994-a2f5-4091-a53f-80646355bc97"));
  } catch {}
})();
var O = function (e, n) {
    return Number(e.toFixed(n));
  },
  zi = function (e, n) {
    return typeof e == "number" ? e : n;
  },
  A = function (e, n, i) {
    i && typeof i == "function" && i(e, n);
  },
  ki = function (e) {
    return -Math.cos(e * Math.PI) / 2 + 0.5;
  },
  Wi = function (e) {
    return e;
  },
  Mi = function (e) {
    return e * e;
  },
  ji = function (e) {
    return e * (2 - e);
  },
  Oi = function (e) {
    return e < 0.5 ? 2 * e * e : -1 + (4 - 2 * e) * e;
  },
  Bi = function (e) {
    return e * e * e;
  },
  Ri = function (e) {
    return --e * e * e + 1;
  },
  Zi = function (e) {
    return e < 0.5 ? 4 * e * e * e : (e - 1) * (2 * e - 2) * (2 * e - 2) + 1;
  },
  Li = function (e) {
    return e * e * e * e;
  },
  Fi = function (e) {
    return 1 - --e * e * e * e;
  },
  Vi = function (e) {
    return e < 0.5 ? 8 * e * e * e * e : 1 - 8 * --e * e * e * e;
  },
  Hi = function (e) {
    return e * e * e * e * e;
  },
  Ki = function (e) {
    return 1 + --e * e * e * e * e;
  },
  Qi = function (e) {
    return e < 0.5 ? 16 * e * e * e * e * e : 1 + 16 * --e * e * e * e * e;
  },
  Ue = {
    easeOut: ki,
    linear: Wi,
    easeInQuad: Mi,
    easeOutQuad: ji,
    easeInOutQuad: Oi,
    easeInCubic: Bi,
    easeOutCubic: Ri,
    easeInOutCubic: Zi,
    easeInQuart: Li,
    easeOutQuart: Fi,
    easeInOutQuart: Vi,
    easeInQuint: Hi,
    easeOutQuint: Ki,
    easeInOutQuint: Qi,
  },
  xe = function (e) {
    typeof e == "number" && cancelAnimationFrame(e);
  },
  B = function (e) {
    e.mounted &&
      (xe(e.animation),
      (e.animate = !1),
      (e.animation = null),
      (e.velocity = null));
  };
function $e(e, n, i, t) {
  if (e.mounted) {
    var o = new Date().getTime(),
      a = 1;
    (B(e),
      (e.animation = function () {
        if (!e.mounted) return xe(e.animation);
        var r = new Date().getTime() - o,
          s = r / i,
          l = Ue[n],
          d = l(s);
        r >= i
          ? (t(a), (e.animation = null))
          : e.animation && (t(d), requestAnimationFrame(e.animation));
      }),
      requestAnimationFrame(e.animation));
  }
}
function Gi(e) {
  var n = e.scale,
    i = e.positionX,
    t = e.positionY;
  return !(Number.isNaN(n) || Number.isNaN(i) || Number.isNaN(t));
}
function q(e, n, i, t) {
  var o = Gi(n);
  if (!(!e.mounted || !o)) {
    var a = e.setTransformState,
      r = e.transformState,
      s = r.scale,
      l = r.positionX,
      d = r.positionY,
      u = n.scale - s,
      c = n.positionX - l,
      f = n.positionY - d;
    i === 0
      ? a(n.scale, n.positionX, n.positionY)
      : $e(e, t, i, function (p) {
          var v = s + u * p,
            h = l + c * p,
            w = d + f * p;
          a(v, h, w);
        });
  }
}
function qi(e, n, i) {
  var t = e.offsetWidth,
    o = e.offsetHeight,
    a = n.offsetWidth,
    r = n.offsetHeight,
    s = a * i,
    l = r * i,
    d = t - s,
    u = o - l;
  return {
    wrapperWidth: t,
    wrapperHeight: o,
    newContentWidth: s,
    newDiffWidth: d,
    newContentHeight: l,
    newDiffHeight: u,
  };
}
var Ui = function (e, n, i, t, o, a, r) {
    var s = e > n ? i * (r ? 1 : 0.5) : 0,
      l = t > o ? a * (r ? 1 : 0.5) : 0,
      d = e - n - s,
      u = s,
      c = t - o - l,
      f = l;
    return {
      minPositionX: d,
      maxPositionX: u,
      minPositionY: c,
      maxPositionY: f,
    };
  },
  Ne = function (e, n) {
    var i = e.wrapperComponent,
      t = e.contentComponent,
      o = e.setup.centerZoomedOut;
    if (!i || !t) throw new Error("Components are not mounted");
    var a = qi(i, t, n),
      r = a.wrapperWidth,
      s = a.wrapperHeight,
      l = a.newContentWidth,
      d = a.newDiffWidth,
      u = a.newContentHeight,
      c = a.newDiffHeight,
      f = Ui(r, l, d, s, u, c, !!o);
    return f;
  },
  Te = function (e, n, i, t) {
    return t ? (e < n ? O(n, 2) : e > i ? O(i, 2) : O(e, 2)) : O(e, 2);
  },
  ie = function (e, n) {
    var i = Ne(e, n);
    return ((e.bounds = i), i);
  };
function re(e, n, i, t, o, a, r) {
  var s = i.minPositionX,
    l = i.minPositionY,
    d = i.maxPositionX,
    u = i.maxPositionY,
    c = 0,
    f = 0;
  r && ((c = o), (f = a));
  var p = Te(e, s - c, d + c, t),
    v = Te(n, l - f, u + f, t);
  return { x: p, y: v };
}
function ve(e, n, i, t, o, a) {
  var r = e.transformState,
    s = r.scale,
    l = r.positionX,
    d = r.positionY,
    u = t - s;
  if (typeof n != "number" || typeof i != "number")
    return (
      console.error("Mouse X and Y position were not provided!"),
      { x: l, y: d }
    );
  var c = l - n * u,
    f = d - i * u,
    p = re(c, f, o, a, 0, 0, null);
  return p;
}
function se(e, n, i, t, o) {
  var a = o ? t : 0,
    r = n - a;
  return !Number.isNaN(i) && e >= i ? i : !Number.isNaN(n) && e <= r ? r : e;
}
var Re = function (e, n) {
    var i = e.setup.panning.excluded,
      t = e.isInitialized,
      o = e.wrapperComponent,
      a = n.target,
      r = "shadowRoot" in a && "composedPath" in n,
      s = r
        ? n.composedPath().some(function (u) {
            return u instanceof Element ? o?.contains(u) : !1;
          })
        : o?.contains(a),
      l = t && a && s;
    if (!l) return !1;
    var d = he(a, i);
    return !d;
  },
  Ze = function (e) {
    var n = e.isInitialized,
      i = e.isPanning,
      t = e.setup,
      o = t.panning.disabled,
      a = n && i && !o;
    return !!a;
  },
  xi = function (e, n) {
    var i = e.transformState,
      t = i.positionX,
      o = i.positionY;
    e.isPanning = !0;
    var a = n.clientX,
      r = n.clientY;
    e.startCoords = { x: a - t, y: r - o };
  },
  $i = function (e, n) {
    var i = n.touches,
      t = e.transformState,
      o = t.positionX,
      a = t.positionY;
    e.isPanning = !0;
    var r = i.length === 1;
    if (r) {
      var s = i[0].clientX,
        l = i[0].clientY;
      e.startCoords = { x: s - o, y: l - a };
    }
  };
function Ji(e) {
  var n = e.transformState,
    i = n.positionX,
    t = n.positionY,
    o = n.scale,
    a = e.setup,
    r = a.disabled,
    s = a.limitToBounds,
    l = a.centerZoomedOut,
    d = e.wrapperComponent;
  if (!(r || !d || !e.bounds)) {
    var u = e.bounds,
      c = u.maxPositionX,
      f = u.minPositionX,
      p = u.maxPositionY,
      v = u.minPositionY,
      h = i > c || i < f,
      w = t > p || t < v,
      b = i > c ? d.offsetWidth : e.setup.minPositionX || 0,
      S = t > p ? d.offsetHeight : e.setup.minPositionY || 0,
      g = ve(e, b, S, o, e.bounds, s || l),
      Y = g.x,
      X = g.y;
    return { scale: o, positionX: h ? Y : i, positionY: w ? X : t };
  }
}
function Je(e, n, i, t, o) {
  var a = e.setup.limitToBounds,
    r = e.wrapperComponent,
    s = e.bounds,
    l = e.transformState,
    d = l.scale,
    u = l.positionX,
    c = l.positionY;
  if (!(r === null || s === null || (n === u && i === c))) {
    var f = re(n, i, s, a, t, o, r),
      p = f.x,
      v = f.y;
    e.setTransformState(d, p, v);
  }
}
var Ii = function (e, n, i) {
    var t = e.startCoords,
      o = e.transformState,
      a = e.setup.panning,
      r = a.lockAxisX,
      s = a.lockAxisY,
      l = o.positionX,
      d = o.positionY;
    if (!t) return { x: l, y: d };
    var u = n - t.x,
      c = i - t.y,
      f = r ? l : u,
      p = s ? d : c;
    return { x: f, y: p };
  },
  G = function (e, n) {
    var i = e.setup,
      t = e.transformState,
      o = t.scale,
      a = i.minScale,
      r = i.disablePadding;
    return n > 0 && o >= a && !r ? n : 0;
  },
  et = function (e) {
    var n = e.mounted,
      i = e.setup,
      t = i.disabled,
      o = i.velocityAnimation,
      a = e.transformState.scale,
      r = o.disabled,
      s = !r || a > 1 || !t || n;
    return !!s;
  },
  it = function (e) {
    var n = e.mounted,
      i = e.velocity,
      t = e.bounds,
      o = e.setup,
      a = o.disabled,
      r = o.velocityAnimation,
      s = e.transformState.scale,
      l = r.disabled,
      d = !l || s > 1 || !a || n;
    return !(!d || !i || !t);
  };
function tt(e, n) {
  var i = e.setup.velocityAnimation,
    t = i.equalToMove,
    o = i.animationTime,
    a = i.sensitivity;
  return t ? o * n * a : o;
}
function Le(e, n, i, t, o, a, r, s, l, d) {
  if (o) {
    if (n > r && i > r) {
      var u = r + (e - r) * d;
      return u > l ? l : u < r ? r : u;
    }
    if (n < a && i < a) {
      var u = a + (e - a) * d;
      return u < s ? s : u > a ? a : u;
    }
  }
  return t ? n : Te(e, a, r, o);
}
function nt(e, n) {
  var i = 1;
  return n ? Math.min(i, e.offsetWidth / window.innerWidth) : i;
}
function at(e, n) {
  var i = et(e);
  if (i) {
    var t = e.lastMousePosition,
      o = e.velocityTime,
      a = e.setup,
      r = e.wrapperComponent,
      s = a.velocityAnimation.equalToMove,
      l = Date.now();
    if (t && o && r) {
      var d = nt(r, s),
        u = n.x - t.x,
        c = n.y - t.y,
        f = u / d,
        p = c / d,
        v = l - o,
        h = u * u + c * c,
        w = Math.sqrt(h) / v;
      e.velocity = { velocityX: f, velocityY: p, total: w };
    }
    ((e.lastMousePosition = n), (e.velocityTime = l));
  }
}
function ot(e) {
  var n = e.velocity,
    i = e.bounds,
    t = e.setup,
    o = e.wrapperComponent,
    a = it(e);
  if (!(!a || !n || !i || !o)) {
    var r = n.velocityX,
      s = n.velocityY,
      l = n.total,
      d = i.maxPositionX,
      u = i.minPositionX,
      c = i.maxPositionY,
      f = i.minPositionY,
      p = t.limitToBounds,
      v = t.alignmentAnimation,
      h = t.zoomAnimation,
      w = t.panning,
      b = w.lockAxisY,
      S = w.lockAxisX,
      g = h.animationType,
      Y = v.sizeX,
      X = v.sizeY,
      k = v.velocityAlignmentTime,
      z = k,
      W = tt(e, l),
      P = Math.max(W, z),
      E = G(e, Y),
      M = G(e, X),
      L = (E * o.offsetWidth) / 100,
      J = (M * o.offsetHeight) / 100,
      U = d + L,
      x = u - L,
      I = c + J,
      ee = f - J,
      te = e.transformState,
      le = new Date().getTime();
    $e(e, g, P, function (ue) {
      var ne = e.transformState,
        ge = ne.scale,
        D = ne.positionX,
        F = ne.positionY,
        de = new Date().getTime() - le,
        be = de / z,
        we = Ue[v.animationType],
        ce = 1 - we(Math.min(1, be)),
        T = 1 - ue,
        _ = D + r * T,
        ae = F + s * T,
        fe = Le(_, te.positionX, D, S, p, u, d, x, U, ce),
        Se = Le(ae, te.positionY, F, b, p, f, c, ee, I, ce);
      (D !== _ || F !== ae) && e.setTransformState(ge, fe, Se);
    });
  }
}
function Fe(e, n) {
  var i = e.transformState.scale;
  (B(e),
    ie(e, i),
    window.TouchEvent !== void 0 && n instanceof TouchEvent
      ? $i(e, n)
      : xi(e, n));
}
function Ie(e) {
  var n = e.transformState.scale,
    i = e.setup,
    t = i.minScale,
    o = i.alignmentAnimation,
    a = o.disabled,
    r = o.sizeX,
    s = o.sizeY,
    l = o.animationTime,
    d = o.animationType,
    u = a || n < t || (!r && !s);
  if (!u) {
    var c = Ji(e);
    c && q(e, c, l, d);
  }
}
function Ve(e, n, i) {
  var t = e.startCoords,
    o = e.setup,
    a = o.alignmentAnimation,
    r = a.sizeX,
    s = a.sizeY;
  if (t) {
    var l = Ii(e, n, i),
      d = l.x,
      u = l.y,
      c = G(e, r),
      f = G(e, s);
    (at(e, { x: d, y: u }), Je(e, d, u, c, f));
  }
}
function rt(e) {
  if (e.isPanning) {
    var n = e.setup.panning.velocityDisabled,
      i = e.velocity,
      t = e.wrapperComponent,
      o = e.contentComponent;
    ((e.isPanning = !1), (e.animate = !1), (e.animation = null));
    var a = t?.getBoundingClientRect(),
      r = o?.getBoundingClientRect(),
      s = a?.width || 0,
      l = a?.height || 0,
      d = r?.width || 0,
      u = r?.height || 0,
      c = s < d || l < u,
      f = !n && i && i?.total > 0.1 && c;
    f ? ot(e) : Ie(e);
  }
}
function _e(e, n, i, t) {
  var o = e.setup,
    a = o.minScale,
    r = o.maxScale,
    s = o.limitToBounds,
    l = se(O(n, 2), a, r, 0, !1),
    d = ie(e, l),
    u = ve(e, i, t, l, d, s),
    c = u.x,
    f = u.y;
  return { scale: l, positionX: c, positionY: f };
}
function ei(e, n, i) {
  var t = e.transformState.scale,
    o = e.wrapperComponent,
    a = e.setup,
    r = a.minScale,
    s = a.limitToBounds,
    l = a.zoomAnimation,
    d = l.disabled,
    u = l.animationTime,
    c = l.animationType,
    f = d || t >= r;
  if (((t >= 1 || s) && Ie(e), !(f || !o || !e.mounted))) {
    var p = n || o.offsetWidth / 2,
      v = i || o.offsetHeight / 2,
      h = _e(e, r, p, v);
    h && q(e, h, u, c);
  }
}
var Q = function () {
  return (
    (Q =
      Object.assign ||
      function (n) {
        for (var i, t = 1, o = arguments.length; t < o; t++) {
          i = arguments[t];
          for (var a in i)
            Object.prototype.hasOwnProperty.call(i, a) && (n[a] = i[a]);
        }
        return n;
      }),
    Q.apply(this, arguments)
  );
};
function He(e, n, i) {
  for (var t = 0, o = n.length, a; t < o; t++)
    (a || !(t in n)) &&
      (a || (a = Array.prototype.slice.call(n, 0, t)), (a[t] = n[t]));
  return e.concat(a || Array.prototype.slice.call(n));
}
var me = { scale: 1, positionX: 0, positionY: 0 },
  oe = {
    disabled: !1,
    minPositionX: null,
    maxPositionX: null,
    minPositionY: null,
    maxPositionY: null,
    minScale: 1,
    maxScale: 8,
    limitToBounds: !0,
    centerZoomedOut: !1,
    centerOnInit: !1,
    disablePadding: !1,
    smooth: !0,
    wheel: {
      step: 0.2,
      disabled: !1,
      smoothStep: 0.001,
      wheelDisabled: !1,
      touchPadDisabled: !1,
      activationKeys: [],
      excluded: [],
    },
    panning: {
      disabled: !1,
      velocityDisabled: !1,
      lockAxisX: !1,
      lockAxisY: !1,
      allowLeftClickPan: !0,
      allowMiddleClickPan: !0,
      allowRightClickPan: !0,
      wheelPanning: !1,
      activationKeys: [],
      excluded: [],
    },
    pinch: { step: 5, disabled: !1, excluded: [] },
    doubleClick: {
      disabled: !1,
      step: 0.7,
      mode: "zoomIn",
      animationType: "easeOut",
      animationTime: 200,
      excluded: [],
    },
    zoomAnimation: {
      disabled: !1,
      size: 0.4,
      animationTime: 200,
      animationType: "easeOut",
    },
    alignmentAnimation: {
      disabled: !1,
      sizeX: 100,
      sizeY: 100,
      animationTime: 200,
      velocityAlignmentTime: 400,
      animationType: "easeOut",
    },
    velocityAnimation: {
      disabled: !1,
      sensitivity: 1,
      animationTime: 400,
      animationType: "easeOut",
      equalToMove: !0,
    },
  },
  Ae = {
    wrapperClass: "react-transform-wrapper",
    contentClass: "react-transform-component",
  },
  ii = function (e) {
    var n, i, t, o;
    return {
      previousScale:
        (n = e.initialScale) !== null && n !== void 0 ? n : me.scale,
      scale: (i = e.initialScale) !== null && i !== void 0 ? i : me.scale,
      positionX:
        (t = e.initialPositionX) !== null && t !== void 0 ? t : me.positionX,
      positionY:
        (o = e.initialPositionY) !== null && o !== void 0 ? o : me.positionY,
    };
  },
  Ke = function (e) {
    var n = Q({}, oe);
    return (
      Object.keys(e).forEach(function (i) {
        var t = typeof e[i] < "u",
          o = typeof oe[i] < "u";
        if (o && t) {
          var a = Object.prototype.toString.call(oe[i]),
            r = a === "[object Object]",
            s = a === "[object Array]";
          r
            ? (n[i] = Q(Q({}, oe[i]), e[i]))
            : s
              ? (n[i] = He(He([], oe[i], !0), e[i]))
              : (n[i] = e[i]);
        }
      }),
      n
    );
  },
  ti = function (e, n, i) {
    var t = e.transformState.scale,
      o = e.wrapperComponent,
      a = e.setup,
      r = a.maxScale,
      s = a.minScale,
      l = a.zoomAnimation,
      d = a.smooth,
      u = l.size;
    if (!o) throw new Error("Wrapper is not mounted");
    var c = d ? t * Math.exp(n * i) : t + n * i,
      f = se(O(c, 3), s, r, u, !1);
    return f;
  };
function ni(e, n, i, t, o) {
  var a = e.wrapperComponent,
    r = e.transformState,
    s = r.scale,
    l = r.positionX,
    d = r.positionY;
  if (!a) return console.error("No WrapperComponent found");
  var u = a.offsetWidth,
    c = a.offsetHeight,
    f = (u / 2 - l) / s,
    p = (c / 2 - d) / s,
    v = ti(e, n, i),
    h = _e(e, v, f, p);
  if (!h)
    return console.error(
      "Error during zoom event. New transformation state was not calculated.",
    );
  q(e, h, t, o);
}
function ai(e, n, i, t) {
  var o = e.setup,
    a = e.wrapperComponent,
    r = o.limitToBounds,
    s = ii(e.props),
    l = e.transformState,
    d = l.scale,
    u = l.positionX,
    c = l.positionY;
  if (a) {
    var f = Ne(e, s.scale),
      p = re(s.positionX, s.positionY, f, r, 0, 0, a),
      v = { scale: s.scale, positionX: p.x, positionY: p.y };
    (d === s.scale && u === s.positionX && c === s.positionY) ||
      (t?.(), q(e, v, n, i));
  }
}
function st(e, n, i, t) {
  var o = e.getBoundingClientRect(),
    a = n.getBoundingClientRect(),
    r = i.getBoundingClientRect(),
    s = a.x * t.scale,
    l = a.y * t.scale;
  return { x: (o.x - r.x + s) / t.scale, y: (o.y - r.y + l) / t.scale };
}
function lt(e, n, i) {
  var t = e.wrapperComponent,
    o = e.contentComponent,
    a = e.transformState,
    r = e.setup,
    s = r.limitToBounds,
    l = r.minScale,
    d = r.maxScale;
  if (!t || !o) return a;
  var u = t.getBoundingClientRect(),
    c = n.getBoundingClientRect(),
    f = st(n, t, o, a),
    p = f.x,
    v = f.y,
    h = c.width / a.scale,
    w = c.height / a.scale,
    b = t.offsetWidth / h,
    S = t.offsetHeight / w,
    g = se(i || Math.min(b, S), l, d, 0, !1),
    Y = (u.width - h * g) / 2,
    X = (u.height - w * g) / 2,
    k = (u.left - p) * g + Y,
    z = (u.top - v) * g + X,
    W = Ne(e, g),
    P = re(k, z, W, s, 0, 0, t),
    E = P.x,
    M = P.y;
  return { positionX: E, positionY: M, scale: g };
}
var ut = function (e) {
    return function (n, i, t) {
      (n === void 0 && (n = 0.5),
        i === void 0 && (i = 300),
        t === void 0 && (t = "easeOut"),
        ni(e, 1, n, i, t));
    };
  },
  dt = function (e) {
    return function (n, i, t) {
      (n === void 0 && (n = 0.5),
        i === void 0 && (i = 300),
        t === void 0 && (t = "easeOut"),
        ni(e, -1, n, i, t));
    };
  },
  ct = function (e) {
    return function (n, i, t, o, a) {
      (o === void 0 && (o = 300), a === void 0 && (a = "easeOut"));
      var r = e.transformState,
        s = r.positionX,
        l = r.positionY,
        d = r.scale,
        u = e.wrapperComponent,
        c = e.contentComponent,
        f = e.setup.disabled;
      if (!(f || !u || !c)) {
        var p = {
          positionX: Number.isNaN(n) ? s : n,
          positionY: Number.isNaN(i) ? l : i,
          scale: Number.isNaN(t) ? d : t,
        };
        q(e, p, o, a);
      }
    };
  },
  ft = function (e) {
    return function (n, i) {
      (n === void 0 && (n = 200), i === void 0 && (i = "easeOut"), ai(e, n, i));
    };
  },
  mt = function (e) {
    return function (n, i, t) {
      (i === void 0 && (i = 200), t === void 0 && (t = "easeOut"));
      var o = e.transformState,
        a = e.wrapperComponent,
        r = e.contentComponent;
      if (a && r) {
        var s = oi(n || o.scale, a, r);
        q(e, s, i, t);
      }
    };
  },
  pt = function (e) {
    return function (n, i, t, o) {
      (t === void 0 && (t = 600), o === void 0 && (o = "easeOut"), B(e));
      var a = e.wrapperComponent,
        r = typeof n == "string" ? document.getElementById(n) : n;
      if (a && r && a.contains(r)) {
        var s = lt(e, r, i);
        q(e, s, t, o);
      }
    };
  },
  Ye = function (e) {
    return {
      instance: e,
      zoomIn: ut(e),
      zoomOut: dt(e),
      setTransform: ct(e),
      resetTransform: ft(e),
      centerView: mt(e),
      zoomToElement: pt(e),
    };
  },
  vt = function (e) {
    return { instance: e, state: e.transformState };
  },
  y = function (e) {
    var n = {};
    return (Object.assign(n, vt(e)), Object.assign(n, Ye(e)), n);
  },
  Pe = !1;
function Ce() {
  try {
    var e = {
      get passive() {
        return ((Pe = !0), !1);
      },
    };
    return e;
  } catch {
    return ((Pe = !1), Pe);
  }
}
var pe = ".".concat(Ae.wrapperClass),
  he = function (e, n) {
    return n.some(function (i) {
      return e.matches(
        ""
          .concat(pe, " ")
          .concat(i, ", ")
          .concat(pe, " .")
          .concat(i, ", ")
          .concat(pe, " ")
          .concat(i, " *, ")
          .concat(pe, " .")
          .concat(i, " *"),
      );
    });
  },
  Xe = function (e) {
    e && clearTimeout(e);
  },
  ht = function (e, n, i) {
    return "translate("
      .concat(e, "px, ")
      .concat(n, "px) scale(")
      .concat(i, ")");
  },
  oi = function (e, n, i) {
    var t = i.offsetWidth * e,
      o = i.offsetHeight * e,
      a = (n.offsetWidth - t) / 2,
      r = (n.offsetHeight - o) / 2;
    return { scale: e, positionX: a, positionY: r };
  };
function gt(e) {
  return function (n) {
    e.forEach(function (i) {
      typeof i == "function" ? i(n) : i != null && (i.current = n);
    });
  };
}
var bt = function (e, n) {
    var i = e.setup.wheel,
      t = i.disabled,
      o = i.wheelDisabled,
      a = i.touchPadDisabled,
      r = i.excluded,
      s = e.isInitialized,
      l = e.isPanning,
      d = n.target,
      u = s && !l && !t && d;
    if (!u || (o && !n.ctrlKey) || (a && n.ctrlKey)) return !1;
    var c = he(d, r);
    return !c;
  },
  wt = function (e) {
    return e ? (e.deltaY < 0 ? 1 : -1) : 0;
  };
function St(e, n) {
  var i = wt(e),
    t = zi(n, i);
  return t;
}
function ri(e, n, i) {
  var t = n.getBoundingClientRect(),
    o = 0,
    a = 0;
  if ("clientX" in e)
    ((o = (e.clientX - t.left) / i), (a = (e.clientY - t.top) / i));
  else {
    var r = e.touches[0];
    ((o = (r.clientX - t.left) / i), (a = (r.clientY - t.top) / i));
  }
  return (
    (Number.isNaN(o) || Number.isNaN(a)) &&
      console.error("No mouse or touch offset found"),
    { x: o, y: a }
  );
}
var Pt = function (e, n, i, t, o) {
    var a = e.transformState.scale,
      r = e.wrapperComponent,
      s = e.setup,
      l = s.maxScale,
      d = s.minScale,
      u = s.zoomAnimation,
      c = s.disablePadding,
      f = u.size,
      p = u.disabled;
    if (!r) throw new Error("Wrapper is not mounted");
    var v = a + n * i,
      h = t ? !1 : !p,
      w = se(O(v, 3), d, l, f, h && !c);
    return w;
  },
  Ct = function (e, n) {
    var i = e.previousWheelEvent,
      t = e.transformState.scale,
      o = e.setup,
      a = o.maxScale,
      r = o.minScale;
    return i
      ? t < a ||
          t > r ||
          Math.sign(i.deltaY) !== Math.sign(n.deltaY) ||
          (i.deltaY > 0 && i.deltaY < n.deltaY) ||
          (i.deltaY < 0 && i.deltaY > n.deltaY) ||
          Math.sign(i.deltaY) !== Math.sign(n.deltaY)
      : !1;
  },
  yt = function (e, n) {
    var i = e.setup.pinch,
      t = i.disabled,
      o = i.excluded,
      a = e.isInitialized,
      r = n.target,
      s = a && !t && r;
    if (!s) return !1;
    var l = he(r, o);
    return !l;
  },
  Tt = function (e) {
    var n = e.setup.pinch.disabled,
      i = e.isInitialized,
      t = e.pinchStartDistance,
      o = i && !n && t;
    return !!o;
  },
  At = function (e, n, i) {
    var t = i.getBoundingClientRect(),
      o = e.touches,
      a = O(o[0].clientX - t.left, 5),
      r = O(o[0].clientY - t.top, 5),
      s = O(o[1].clientX - t.left, 5),
      l = O(o[1].clientY - t.top, 5);
    return { x: (a + s) / 2 / n, y: (r + l) / 2 / n };
  },
  si = function (e) {
    return Math.sqrt(
      Math.pow(e.touches[0].pageX - e.touches[1].pageX, 2) +
        Math.pow(e.touches[0].pageY - e.touches[1].pageY, 2),
    );
  },
  Yt = function (e, n) {
    var i = e.pinchStartScale,
      t = e.pinchStartDistance,
      o = e.setup,
      a = o.maxScale,
      r = o.minScale,
      s = o.zoomAnimation,
      l = o.disablePadding,
      d = s.size,
      u = s.disabled;
    if (!i || t === null || !n)
      throw new Error("Pinch touches distance was not provided");
    if (n < 0) return e.transformState.scale;
    var c = n / t,
      f = c * i;
    return se(O(f, 2), r, a, d, !u && !l);
  },
  Xt = 160,
  Et = 100,
  Dt = function (e, n) {
    var i = e.props,
      t = i.onWheelStart,
      o = i.onZoomStart;
    e.wheelStopEventTimer || (B(e), A(y(e), n, t), A(y(e), n, o));
  },
  Nt = function (e, n) {
    var i = e.props,
      t = i.onWheel,
      o = i.onZoom,
      a = e.contentComponent,
      r = e.setup,
      s = e.transformState,
      l = s.scale,
      d = r.limitToBounds,
      u = r.centerZoomedOut,
      c = r.zoomAnimation,
      f = r.wheel,
      p = r.disablePadding,
      v = r.smooth,
      h = c.size,
      w = c.disabled,
      b = f.step,
      S = f.smoothStep;
    if (!a) throw new Error("Component not mounted");
    (n.preventDefault(), n.stopPropagation());
    var g = St(n, null),
      Y = v ? S * Math.abs(n.deltaY) : b,
      X = Pt(e, g, Y, !n.ctrlKey);
    if (l !== X) {
      var k = ie(e, X),
        z = ri(n, a, l),
        W = w || h === 0 || u || p,
        P = d && W,
        E = ve(e, z.x, z.y, X, k, P),
        M = E.x,
        L = E.y;
      ((e.previousWheelEvent = n),
        e.setTransformState(X, M, L),
        A(y(e), n, t),
        A(y(e), n, o));
    }
  },
  _t = function (e, n) {
    var i = e.props,
      t = i.onWheelStop,
      o = i.onZoomStop;
    (Xe(e.wheelAnimationTimer),
      (e.wheelAnimationTimer = setTimeout(function () {
        e.mounted && (ei(e, n.x, n.y), (e.wheelAnimationTimer = null));
      }, Et)));
    var a = Ct(e, n);
    a &&
      (Xe(e.wheelStopEventTimer),
      (e.wheelStopEventTimer = setTimeout(function () {
        e.mounted &&
          ((e.wheelStopEventTimer = null), A(y(e), n, t), A(y(e), n, o));
      }, Xt)));
  },
  li = function (e) {
    for (var n = 0, i = 0, t = 0; t < 2; t += 1)
      ((n += e.touches[t].clientX), (i += e.touches[t].clientY));
    var o = n / 2,
      a = i / 2;
    return { x: o, y: a };
  },
  zt = function (e, n) {
    var i = si(n);
    ((e.pinchStartDistance = i),
      (e.lastDistance = i),
      (e.pinchStartScale = e.transformState.scale),
      (e.isPanning = !1));
    var t = li(n);
    ((e.pinchLastCenterX = t.x), (e.pinchLastCenterY = t.y), B(e));
  },
  kt = function (e, n) {
    var i = e.contentComponent,
      t = e.pinchStartDistance,
      o = e.wrapperComponent,
      a = e.transformState.scale,
      r = e.setup,
      s = r.limitToBounds,
      l = r.centerZoomedOut,
      d = r.zoomAnimation,
      u = r.alignmentAnimation,
      c = d.disabled,
      f = d.size;
    if (!(t === null || !i)) {
      var p = At(n, a, i);
      if (!(!Number.isFinite(p.x) || !Number.isFinite(p.y))) {
        var v = si(n),
          h = Yt(e, v),
          w = li(n),
          b = w.x - (e.pinchLastCenterX || 0),
          S = w.y - (e.pinchLastCenterY || 0);
        if (!(h === a && b === 0 && S === 0)) {
          ((e.pinchLastCenterX = w.x), (e.pinchLastCenterY = w.y));
          var g = ie(e, h),
            Y = c || f === 0 || l,
            X = s && Y,
            k = ve(e, p.x, p.y, h, g, X),
            z = k.x,
            W = k.y;
          ((e.pinchMidpoint = p), (e.lastDistance = v));
          var P = u.sizeX,
            E = u.sizeY,
            M = G(e, P),
            L = G(e, E),
            J = z + b,
            U = W + S,
            x = re(J, U, g, s, M, L, o),
            I = x.x,
            ee = x.y;
          e.setTransformState(h, I, ee);
        }
      }
    }
  },
  Wt = function (e) {
    var n = e.pinchMidpoint;
    ((e.velocity = null),
      (e.lastDistance = null),
      (e.pinchMidpoint = null),
      (e.pinchStartScale = null),
      (e.pinchStartDistance = null),
      ei(e, n?.x, n?.y));
  },
  ui = function (e, n) {
    var i = e.props.onZoomStop,
      t = e.setup.doubleClick.animationTime;
    (Xe(e.doubleClickStopEventTimer),
      (e.doubleClickStopEventTimer = setTimeout(function () {
        ((e.doubleClickStopEventTimer = null), A(y(e), n, i));
      }, t)));
  },
  Mt = function (e, n) {
    var i = e.props,
      t = i.onZoomStart,
      o = i.onZoom,
      a = e.setup.doubleClick,
      r = a.animationTime,
      s = a.animationType;
    (A(y(e), n, t),
      ai(e, r, s, function () {
        return A(y(e), n, o);
      }),
      ui(e, n));
  };
function jt(e, n) {
  return e === "toggle" ? (n === 1 ? 1 : -1) : e === "zoomOut" ? -1 : 1;
}
function Ot(e, n) {
  var i = e.setup,
    t = e.doubleClickStopEventTimer,
    o = e.transformState,
    a = e.contentComponent,
    r = o.scale,
    s = e.props,
    l = s.onZoomStart,
    d = s.onZoom,
    u = i.doubleClick,
    c = u.disabled,
    f = u.mode,
    p = u.step,
    v = u.animationTime,
    h = u.animationType;
  if (!c && !t) {
    if (f === "reset") return Mt(e, n);
    if (!a) return console.error("No ContentComponent found");
    var w = jt(f, e.transformState.scale),
      b = ti(e, w, p);
    if (r !== b) {
      A(y(e), n, l);
      var S = ri(n, a, r),
        g = _e(e, b, S.x, S.y);
      if (!g)
        return console.error(
          "Error during zoom event. New transformation state was not calculated.",
        );
      (A(y(e), n, d), q(e, g, v, h), ui(e, n));
    }
  }
}
var Bt = function (e, n) {
    var i = e.isInitialized,
      t = e.setup,
      o = e.wrapperComponent,
      a = t.doubleClick,
      r = a.disabled,
      s = a.excluded,
      l = n.target,
      d = o?.contains(l),
      u = i && l && d && !r;
    if (!u) return !1;
    var c = he(l, s);
    return !c;
  },
  Rt = (function () {
    function e(n) {
      var i = this;
      ((this.mounted = !0),
        (this.pinchLastCenterX = null),
        (this.pinchLastCenterY = null),
        (this.onChangeCallbacks = new Set()),
        (this.onInitCallbacks = new Set()),
        (this.wrapperComponent = null),
        (this.contentComponent = null),
        (this.isInitialized = !1),
        (this.bounds = null),
        (this.previousWheelEvent = null),
        (this.wheelStopEventTimer = null),
        (this.wheelAnimationTimer = null),
        (this.isPanning = !1),
        (this.isWheelPanning = !1),
        (this.startCoords = null),
        (this.lastTouch = null),
        (this.distance = null),
        (this.lastDistance = null),
        (this.pinchStartDistance = null),
        (this.pinchStartScale = null),
        (this.pinchMidpoint = null),
        (this.doubleClickStopEventTimer = null),
        (this.velocity = null),
        (this.velocityTime = null),
        (this.lastMousePosition = null),
        (this.animate = !1),
        (this.animation = null),
        (this.maxBounds = null),
        (this.pressedKeys = {}),
        (this.mount = function () {
          i.initializeWindowEvents();
        }),
        (this.unmount = function () {
          i.cleanupWindowEvents();
        }),
        (this.update = function (t) {
          ((i.props = t), ie(i, i.transformState.scale), (i.setup = Ke(t)));
        }),
        (this.initializeWindowEvents = function () {
          var t,
            o,
            a = Ce(),
            r =
              (t = i.wrapperComponent) === null || t === void 0
                ? void 0
                : t.ownerDocument,
            s = r?.defaultView;
          ((o = i.wrapperComponent) === null ||
            o === void 0 ||
            o.addEventListener("wheel", i.onWheelPanning, a),
            s?.addEventListener("mousedown", i.onPanningStart, a),
            s?.addEventListener("mousemove", i.onPanning, a),
            s?.addEventListener("mouseup", i.onPanningStop, a),
            r?.addEventListener("mouseleave", i.clearPanning, a),
            s?.addEventListener("keyup", i.setKeyUnPressed, a),
            s?.addEventListener("keydown", i.setKeyPressed, a));
        }),
        (this.cleanupWindowEvents = function () {
          var t,
            o,
            a = Ce(),
            r =
              (t = i.wrapperComponent) === null || t === void 0
                ? void 0
                : t.ownerDocument,
            s = r?.defaultView;
          (s?.removeEventListener("mousedown", i.onPanningStart, a),
            s?.removeEventListener("mousemove", i.onPanning, a),
            s?.removeEventListener("mouseup", i.onPanningStop, a),
            r?.removeEventListener("mouseleave", i.clearPanning, a),
            s?.removeEventListener("keyup", i.setKeyUnPressed, a),
            s?.removeEventListener("keydown", i.setKeyPressed, a),
            document.removeEventListener("mouseleave", i.clearPanning, a),
            B(i),
            (o = i.observer) === null || o === void 0 || o.disconnect());
        }),
        (this.handleInitializeWrapperEvents = function (t) {
          var o = Ce();
          (t.addEventListener("wheel", i.onWheelZoom, o),
            t.addEventListener("dblclick", i.onDoubleClick, o),
            t.addEventListener("touchstart", i.onTouchPanningStart, o),
            t.addEventListener("touchmove", i.onTouchPanning, o),
            t.addEventListener("touchend", i.onTouchPanningStop, o));
        }),
        (this.handleInitialize = function (t) {
          var o = i.setup.centerOnInit;
          (i.applyTransformation(),
            i.onInitCallbacks.forEach(function (a) {
              return a(y(i));
            }),
            o &&
              (i.setCenter(),
              (i.observer = new ResizeObserver(function () {
                var a,
                  r = t.offsetWidth,
                  s = t.offsetHeight;
                (r > 0 || s > 0) &&
                  (i.onInitCallbacks.forEach(function (l) {
                    return l(y(i));
                  }),
                  i.setCenter(),
                  (a = i.observer) === null || a === void 0 || a.disconnect());
              })),
              setTimeout(function () {
                var a;
                (a = i.observer) === null || a === void 0 || a.disconnect();
              }, 5e3),
              i.observer.observe(t)));
        }),
        (this.onWheelZoom = function (t) {
          var o = i.setup.disabled;
          if (!o) {
            var a = bt(i, t);
            if (a) {
              var r = i.isPressingKeys(i.setup.wheel.activationKeys);
              r && (Dt(i, t), Nt(i, t), _t(i, t));
            }
          }
        }),
        (this.onWheelPanning = function (t) {
          var o = i.setup,
            a = o.disabled,
            r = o.wheel,
            s = o.panning;
          if (!(
            !i.wrapperComponent ||
            !i.contentComponent ||
            a ||
            !r.wheelDisabled ||
            s.disabled ||
            !s.wheelPanning ||
            t.ctrlKey
          )) {
            (t.preventDefault(), t.stopPropagation());
            var l = i.transformState,
              d = l.positionX,
              u = l.positionY,
              c = d - t.deltaX,
              f = u - t.deltaY,
              p = s.lockAxisX ? d : c,
              v = s.lockAxisY ? u : f,
              h = i.setup.alignmentAnimation,
              w = h.sizeX,
              b = h.sizeY,
              S = G(i, w),
              g = G(i, b);
            (p === d && v === u) || Je(i, p, v, S, g);
          }
        }),
        (this.onPanningStart = function (t) {
          var o = i.setup.disabled,
            a = i.props.onPanningStart;
          if (!o) {
            var r = Re(i, t);
            if (r) {
              var s = i.isPressingKeys(i.setup.panning.activationKeys);
              s &&
                ((t.button === 0 && !i.setup.panning.allowLeftClickPan) ||
                  (t.button === 1 && !i.setup.panning.allowMiddleClickPan) ||
                  (t.button === 2 && !i.setup.panning.allowRightClickPan) ||
                  (t.preventDefault(),
                  t.stopPropagation(),
                  B(i),
                  Fe(i, t),
                  A(y(i), t, a)));
            }
          }
        }),
        (this.onPanning = function (t) {
          var o = i.setup.disabled,
            a = i.props.onPanning;
          if (!o) {
            var r = Ze(i);
            if (r) {
              var s = i.isPressingKeys(i.setup.panning.activationKeys);
              s &&
                (t.preventDefault(),
                t.stopPropagation(),
                Ve(i, t.clientX, t.clientY),
                A(y(i), t, a));
            }
          }
        }),
        (this.onPanningStop = function (t) {
          var o = i.props.onPanningStop;
          i.isPanning && (rt(i), A(y(i), t, o));
        }),
        (this.onPinchStart = function (t) {
          var o = i.setup.disabled,
            a = i.props,
            r = a.onPinchingStart,
            s = a.onZoomStart;
          if (!o) {
            var l = yt(i, t);
            l && (zt(i, t), B(i), A(y(i), t, r), A(y(i), t, s));
          }
        }),
        (this.onPinch = function (t) {
          var o = i.setup.disabled,
            a = i.props,
            r = a.onPinching,
            s = a.onZoom;
          if (!o) {
            var l = Tt(i);
            l &&
              (t.preventDefault(),
              t.stopPropagation(),
              kt(i, t),
              A(y(i), t, r),
              A(y(i), t, s));
          }
        }),
        (this.onPinchStop = function (t) {
          var o = i.props,
            a = o.onPinchingStop,
            r = o.onZoomStop;
          i.pinchStartScale && (Wt(i), A(y(i), t, a), A(y(i), t, r));
        }),
        (this.onTouchPanningStart = function (t) {
          var o = i.setup.disabled,
            a = i.props.onPanningStart;
          if (!o) {
            var r = Re(i, t);
            if (r) {
              var s = i.lastTouch && +new Date() - i.lastTouch < 200;
              if (!s) {
                ((i.lastTouch = +new Date()), B(i));
                var l = t.touches,
                  d = l.length === 1,
                  u = l.length === 2;
                (d && (B(i), Fe(i, t), A(y(i), t, a)), u && i.onPinchStart(t));
              }
            }
          }
        }),
        (this.onTouchPanning = function (t) {
          var o = i.setup.disabled,
            a = i.props.onPanning;
          if (i.isPanning && t.touches.length === 1) {
            if (o) return;
            var r = Ze(i);
            if (!r) return;
            (t.preventDefault(), t.stopPropagation());
            var s = t.touches[0];
            (Ve(i, s.clientX, s.clientY), A(y(i), t, a));
          } else t.touches.length > 1 && i.onPinch(t);
        }),
        (this.onTouchPanningStop = function (t) {
          (i.onPanningStop(t), i.onPinchStop(t));
        }),
        (this.onDoubleClick = function (t) {
          var o = i.setup.disabled;
          if (!o) {
            var a = Bt(i, t);
            a && Ot(i, t);
          }
        }),
        (this.clearPanning = function (t) {
          i.isPanning && i.onPanningStop(t);
        }),
        (this.setKeyPressed = function (t) {
          i.pressedKeys[t.key] = !0;
        }),
        (this.setKeyUnPressed = function (t) {
          i.pressedKeys[t.key] = !1;
        }),
        (this.isPressingKeys = function (t) {
          return t.length
            ? !!t.find(function (o) {
                return i.pressedKeys[o];
              })
            : !0;
        }),
        (this.setTransformState = function (t, o, a) {
          var r = i.props.onTransformed;
          if (!Number.isNaN(t) && !Number.isNaN(o) && !Number.isNaN(a)) {
            (t !== i.transformState.scale &&
              ((i.transformState.previousScale = i.transformState.scale),
              (i.transformState.scale = t)),
              (i.transformState.positionX = o),
              (i.transformState.positionY = a),
              i.applyTransformation());
            var s = y(i);
            (i.onChangeCallbacks.forEach(function (l) {
              return l(s);
            }),
              A(s, { scale: t, positionX: o, positionY: a }, r));
          } else console.error("Detected NaN set state values");
        }),
        (this.setCenter = function () {
          if (i.wrapperComponent && i.contentComponent) {
            var t = oi(
              i.transformState.scale,
              i.wrapperComponent,
              i.contentComponent,
            );
            i.setTransformState(t.scale, t.positionX, t.positionY);
          }
        }),
        (this.handleTransformStyles = function (t, o, a) {
          return i.props.customTransform
            ? i.props.customTransform(t, o, a)
            : ht(t, o, a);
        }),
        (this.applyTransformation = function () {
          if (!(!i.mounted || !i.contentComponent)) {
            var t = i.transformState,
              o = t.scale,
              a = t.positionX,
              r = t.positionY,
              s = i.handleTransformStyles(a, r, o);
            i.contentComponent.style.transform = s;
          }
        }),
        (this.getContext = function () {
          return y(i);
        }),
        (this.onChange = function (t) {
          return (
            i.onChangeCallbacks.has(t) || i.onChangeCallbacks.add(t),
            function () {
              i.onChangeCallbacks.delete(t);
            }
          );
        }),
        (this.onInit = function (t) {
          return (
            i.onInitCallbacks.has(t) || i.onInitCallbacks.add(t),
            function () {
              i.onInitCallbacks.delete(t);
            }
          );
        }),
        (this.init = function (t, o) {
          (i.cleanupWindowEvents(),
            (i.wrapperComponent = t),
            (i.contentComponent = o),
            ie(i, i.transformState.scale),
            i.handleInitializeWrapperEvents(t),
            i.handleInitialize(o),
            i.initializeWindowEvents(),
            (i.isInitialized = !0));
          var a = y(i);
          A(a, void 0, i.props.onInit);
        }),
        (this.props = n),
        (this.setup = Ke(this.props)),
        (this.transformState = ii(this.props)));
    }
    return e;
  })(),
  ze = $.createContext(null),
  Zt = function (e, n) {
    return typeof e == "function" ? e(n) : e;
  },
  Lt = $.forwardRef(function (e, n) {
    var i = C.useRef(new Rt(e)).current,
      t = Zt(e.children, Ye(i));
    return (
      C.useImperativeHandle(
        n,
        function () {
          return Ye(i);
        },
        [i],
      ),
      C.useEffect(
        function () {
          i.update(e);
        },
        [i, e],
      ),
      $.createElement(ze.Provider, { value: i }, t)
    );
  });
$.forwardRef(function (e, n) {
  var i = C.useRef(null),
    t = C.useContext(ze);
  return (
    C.useEffect(
      function () {
        return t.onChange(function (o) {
          if (i.current) {
            var a = 0,
              r = 0;
            i.current.style.transform = t.handleTransformStyles(
              a,
              r,
              1 / o.instance.transformState.scale,
            );
          }
        });
      },
      [t],
    ),
    $.createElement("div", Q({}, e, { ref: gt([i, n]) }))
  );
});
function Ft(e, n) {
  n === void 0 && (n = {});
  var i = n.insertAt;
  if (!(typeof document > "u")) {
    var t = document.head || document.getElementsByTagName("head")[0],
      o = document.createElement("style");
    ((o.type = "text/css"),
      i === "top" && t.firstChild
        ? t.insertBefore(o, t.firstChild)
        : t.appendChild(o),
      o.styleSheet
        ? (o.styleSheet.cssText = e)
        : o.appendChild(document.createTextNode(e)));
  }
}
var Vt = `.transform-component-module_wrapper__SPB86 {
  position: relative;
  width: -moz-fit-content;
  width: fit-content;
  height: -moz-fit-content;
  height: fit-content;
  overflow: hidden;
  -webkit-touch-callout: none; /* iOS Safari */
  -webkit-user-select: none; /* Safari */
  -khtml-user-select: none; /* Konqueror HTML */
  -moz-user-select: none; /* Firefox */
  -ms-user-select: none; /* Internet Explorer/Edge */
  user-select: none;
  margin: 0;
  padding: 0;
}
.transform-component-module_content__FBWxo {
  display: flex;
  flex-wrap: wrap;
  width: -moz-fit-content;
  width: fit-content;
  height: -moz-fit-content;
  height: fit-content;
  margin: 0;
  padding: 0;
  transform-origin: 0% 0%;
}
.transform-component-module_content__FBWxo img {
  pointer-events: none;
}
`,
  Qe = {
    wrapper: "transform-component-module_wrapper__SPB86",
    content: "transform-component-module_content__FBWxo",
  };
Ft(Vt);
var Ht = function (e) {
  var n = e.children,
    i = e.wrapperClass,
    t = i === void 0 ? "" : i,
    o = e.contentClass,
    a = o === void 0 ? "" : o,
    r = e.wrapperStyle,
    s = e.contentStyle,
    l = e.wrapperProps,
    d = l === void 0 ? {} : l,
    u = e.contentProps,
    c = u === void 0 ? {} : u,
    f = C.useContext(ze),
    p = f.init,
    v = f.cleanupWindowEvents,
    h = C.useRef(null),
    w = C.useRef(null);
  return (
    C.useEffect(function () {
      var b = h.current,
        S = w.current;
      return (
        b !== null && S !== null && p && p?.(b, S),
        function () {
          v?.();
        }
      );
    }, []),
    $.createElement(
      "div",
      Q({}, d, {
        ref: h,
        className: ""
          .concat(Ae.wrapperClass, " ")
          .concat(Qe.wrapper, " ")
          .concat(t),
        style: r,
      }),
      $.createElement(
        "div",
        Q({}, c, {
          ref: w,
          className: ""
            .concat(Ae.contentClass, " ")
            .concat(Qe.content, " ")
            .concat(a),
          style: s,
        }),
        n,
      ),
    )
  );
};
const Kt = ({ attachment: e }) => {
    const [n, i] = C.useState(!1),
      [t, o] = C.useState(null),
      [a, r] = C.useState(1);
    function s(l) {
      o(l.numPages);
    }
    return m.jsxs("div", {
      className: "pdf-carousel",
      onClick: Ei,
      "data-sentry-component": "PDFAttachmentCarousel",
      "data-sentry-source-file": "PDFAttachment.tsx",
      children: [
        n
          ? m.jsx("span", {
              children: j("Unable to load PDF. Download the file to view."),
            })
          : m.jsx(C.Suspense, {
              fallback: j("Loading..."),
              children: m.jsx(di, {
                docProps: {
                  file: Ge(e),
                  onLoadSuccess: s,
                  onLoadError: () => i(!0),
                },
                pageProps: { pageNumber: a },
              }),
            }),
        m.jsxs("div", {
          className: "pdf-carousel-controls",
          children: [
            m.jsx("button", {
              "aria-label": j("Previous Page"),
              type: "button",
              style: { transform: "scaleX(-1)" },
              onClick: (l) => {
                (l.stopPropagation(), r(a - 1));
              },
              disabled: a === 1,
              children: ke,
            }),
            m.jsxs("span", { children: [a, "/", t] }),
            m.jsx("button", {
              "aria-label": j("Next Page"),
              type: "button",
              onClick: (l) => {
                (l.stopPropagation(), r(a + 1));
              },
              disabled: a === t,
              children: ke,
            }),
          ],
        }),
      ],
    });
  },
  Qt = 8,
  Gt = 4,
  qt = ({ contentRef: e, render: n, containerStyle: i }) => (
    R("+", () => e.zoomIn(), "carousel"),
    R("=", () => e.zoomIn(), "carousel"),
    R("-", () => e.zoomOut(), "carousel"),
    m.jsx("div", {
      onClick: (t) => t.stopPropagation(),
      style: i,
      "data-sentry-component": "ZoomComponent",
      "data-sentry-source-file": "AttachmentCarousel.tsx",
      children: n(),
    })
  ),
  Ut = ({
    attachment: e,
    messageIdentifier: n,
    thread: i,
    preview: t = !1,
    containerStyle: o,
    zoomable: a,
    contentRef: r,
    hideControls: s,
    initialVideoState: l,
  }) => {
    const d = () => {
      if (!e) return null;
      const u = Ge(e),
        c = j("Attachment");
      if (n && Z.mediaDownloadStore.needsUserDownload(e))
        return m.jsx(Pi, { attachment: e, messageID: n.id, thread: i });
      if (e.loading)
        return i && n
          ? m.jsx(Ci, { attachment: e, messageID: n.id, thread: i })
          : m.jsx("div", {
              children: Ni(j("%s has not loaded yet"), e.fileName || c),
            });
      const f = { src: u };
      if (e.type === K.IMG || _i(e.mimeType))
        return m.jsx(yi, {
          uniqueID: e.id,
          mimeType: e.mimeType,
          fileName: e.fileName,
          ...f,
        });
      if (e.type === K.VIDEO)
        return m.jsx(Ti, {
          ...f,
          preload: "metadata",
          autoPlay: e.isGif,
          loop: e.isGif,
          controls: !e.isGif && !t,
          muted: e.isGif,
          isGif: e.isGif,
          poster: e.posterImg ? Ai(e.posterImg) : void 0,
          fullscreenable: !0,
          attachment: e,
          style: { filter: "blur(0px)" },
          isInCarousel: !t,
          hideControls: s,
          initialVideoState: l,
        });
      const p = Yi(e, u, n);
      return (
        p ||
        (Xi(e)
          ? m.jsx(Kt, { attachment: e })
          : e.type === K.UNKNOWN
            ? m.jsx("a", {
                className: "binary",
                download: e.fileName,
                href: u,
                children: e.fileName,
              })
            : null)
      );
    };
    return r
      ? e.type === K.VIDEO
        ? m.jsx("div", {
            onClick: (u) => u.stopPropagation(),
            style: o,
            "data-sentry-component": "renderAttachment",
            "data-sentry-source-file": "AttachmentCarousel.tsx",
            children: d(),
          })
        : m.jsx(qt, {
            contentRef: r,
            render: d,
            containerStyle: o,
            "data-sentry-element": "ZoomComponent",
            "data-sentry-component": "renderAttachment",
            "data-sentry-source-file": "AttachmentCarousel.tsx",
          })
      : d();
  },
  xt = Ee(
    ({
      attachments: e,
      index: n,
      setIndex: i,
      selectNextMessage: t,
      selectPreviousMessage: o,
      thread: a,
      message: r,
      initialVideoState: s,
      header: l,
      extraToolbarButtons: d,
      extraMenuItems: u,
      bottomBar: c,
    }) => {
      const [f, p] = C.useState(0),
        [v, h] = C.useState(1),
        [w, b] = C.useState(!1),
        S = C.useRef(null),
        g = C.useRef(null),
        Y = C.useRef(null),
        X = C.useContext(De),
        { zoomFactor: k } = X,
        { CustomContextMenu: z, onCustomContextMenu: W } = ci(),
        { width: P } = We(g, 0, 0),
        { width: E } = We(Y, 0, 0);
      C.useEffect(() => {
        Z.pipState && Z.setPipState(null);
      }, []);
      const { cssVars: M } = Z.layoutStore,
        L = X.isFullScreened ? 0 : M.macTrafficLightsWidth + 14,
        J = Math.max(P, E),
        U = () => {
          (X.document.dispatchEvent(
            new CustomEvent(qe.CarouselClosed, { detail: e }),
          ),
            i(null));
        },
        x = (T) => {
          T.stopPropagation();
          const _ = e[n];
          Z.downloadAttachment(_, a?.computedTitle);
        },
        I = (T) => {
          (T.stopPropagation(),
            requestAnimationFrame(() => {
              const _ = f - 90;
              if (
                (_ === -360
                  ? (p(_),
                    setTimeout(() => {
                      (b(!0),
                        p(0),
                        setTimeout(() => {
                          b(!1);
                        }, 33));
                    }, 200))
                  : p(_),
                !S.current)
              )
                return;
              const { clientWidth: ae, clientHeight: fe } = S.current;
              if (ae > fe && [90, 270].includes(_)) {
                const Se = fe / ae;
                h(Se);
              } else h(1);
            }));
        },
        ee = n + 1 === e.length,
        te = n === 0,
        le = () => {
          const T = n + 1;
          ee ? t?.() : i(T);
        },
        ue = () => {
          const T = n - 1;
          te ? o?.() : i(T);
        },
        ne = !ee || t,
        ge = !te || o,
        D = e[n],
        F = D?.type === K.VIDEO && !D?.isGif,
        de = C.useCallback(() => {
          if (!F || !Me.isEnabled) return;
          const T = S.current?.querySelector("video");
          T && Me.toggle(T);
        }, [F]);
      (R(
        "esc",
        (T) => {
          (T.stopPropagation(), U());
        },
        "attachment-carousel-esc",
      ),
        R("right", le),
        R("left", ue),
        R("d", x),
        R("r", I),
        R("f", de));
      const be = m.jsx("div", {
          className: "carousel-control prev-button",
          children: m.jsx(V, {
            content: j("Previous Attachment"),
            hotkey: "←",
            position: "bottom",
            containerClassName: "prev-tooltip",
            children: m.jsx("button", {
              "aria-label": j("Previous Attachment"),
              type: "button",
              onClick: (T) => {
                (T.stopPropagation(), ue());
              },
              children: m.jsx(H, { name: "arrow-back", width: 20, height: 20 }),
            }),
          }),
        }),
        we = m.jsx("div", {
          className: "carousel-control next-button",
          children: m.jsx(V, {
            content: j("Next Attachment"),
            hotkey: "→",
            children: m.jsx("button", {
              "aria-label": j("Next Attachment"),
              type: "button",
              onClick: (T) => {
                (T.stopPropagation(), le());
              },
              children: m.jsx(H, {
                name: "arrow-back",
                width: 20,
                height: 20,
                style: { transform: "rotate(180deg)" },
              }),
            }),
          }),
        }),
        ce = C.useCallback(
          (T) => {
            T.preventDefault();
            const _ = [];
            (_.push({
              label: N("Download", "attachment carousel context menu action"),
              action: () => Z.downloadAttachment(D, a?.computedTitle),
            }),
              D.type === K.IMG &&
                _.push({
                  label: N("Copy", "attachment carousel context menu action"),
                  action: () => Z.copyImage(D),
                }),
              _.push(...(u?.() ?? [])),
              W(T, _));
          },
          [D, W, a?.computedTitle, u],
        );
      return D
        ? fi.createPortal(
            m.jsx(mi, {
              className: "portal fullscreen-viewer",
              children: m.jsxs("div", {
                className: "attachment-carousel",
                onClick: U,
                children: [
                  m.jsxs("header", {
                    children: [
                      m.jsx("div", {
                        ref: Y,
                        className: "carousel-header-lhs",
                        style: { paddingLeft: L || Qt },
                      }),
                      m.jsx("div", {
                        className: "carousel-header-center",
                        style: { padding: `0 ${J + Gt}px` },
                        children:
                          l ??
                          (a &&
                            m.jsxs(m.Fragment, {
                              children: [
                                m.jsx(pi, { thread: a, size: 28 }),
                                m.jsx("span", {
                                  className: "carousel-thread-title",
                                  children: a.computedTitle,
                                }),
                                m.jsx("span", {
                                  className: "carousel-timestamp",
                                  children: vi(r.timestamp),
                                }),
                              ],
                            })),
                      }),
                      m.jsxs("div", {
                        ref: g,
                        className: "carousel-header-controls",
                        children: [
                          d,
                          F &&
                            m.jsx(V, {
                              content: j("Fullscreen"),
                              hotkey: "F",
                              children: m.jsx("button", {
                                type: "button",
                                className: "carousel-control",
                                onClick: (T) => {
                                  (T.stopPropagation(), de());
                                },
                                "aria-label": j("Fullscreen"),
                                children: m.jsx(H, {
                                  name: "full-screen",
                                  width: 20,
                                  height: 20,
                                }),
                              }),
                            }),
                          !F &&
                            m.jsx(V, {
                              content: N(
                                "Rotate",
                                "attachment carousel action",
                              ),
                              hotkey: "R",
                              children: m.jsx("button", {
                                type: "button",
                                className: "carousel-control",
                                onClick: I,
                                "aria-label": N(
                                  "Rotate",
                                  "attachment carousel action",
                                ),
                                children: m.jsx(H, {
                                  name: "rotate",
                                  width: 20,
                                  height: 20,
                                }),
                              }),
                            }),
                          m.jsx(V, {
                            content: N(
                              "Download",
                              "attachment carousel action",
                            ),
                            hotkey: "D",
                            children: m.jsx("button", {
                              type: "button",
                              className: "carousel-control",
                              onClick: x,
                              "aria-label": N(
                                "Download",
                                "attachment carousel action",
                              ),
                              children: m.jsx(H, {
                                name: "download",
                                width: 20,
                                height: 20,
                              }),
                            }),
                          }),
                          m.jsx(V, {
                            content: N("Close", "attachment carousel action"),
                            hotkey: "Escape",
                            children: m.jsx("button", {
                              type: "button",
                              className: "carousel-control",
                              onClick: U,
                              "aria-label": N(
                                "Close",
                                "attachment carousel action",
                              ),
                              children: m.jsx(H, {
                                name: "close",
                                width: 20,
                                height: 20,
                              }),
                            }),
                          }),
                        ],
                      }),
                    ],
                  }),
                  m.jsx("main", {
                    children: m.jsx(
                      Lt,
                      {
                        wheel: { wheelDisabled: !0, smoothStep: 0.02 },
                        centerZoomedOut: !0,
                        pinch: { step: 0.2 },
                        doubleClick: { mode: "toggle" },
                        disabled: D.type === K.VIDEO,
                        children: (T) =>
                          m.jsx(Ht, {
                            children: m.jsx(
                              "div",
                              {
                                className: "attachment",
                                ref: S,
                                style: {
                                  zoom: 1 / k,
                                  transition: w ? "none" : ".2s transform",
                                  width: "100%",
                                  height: "100%",
                                  display: "flex",
                                  alignItems: "center",
                                  justifyContent: "center",
                                },
                                onContextMenu: ce,
                                children: Ut({
                                  attachment: D,
                                  messageIdentifier: a?.messageIdentifier(r),
                                  thread: a,
                                  preview: !1,
                                  contentRef: T,
                                  zoomable: !0,
                                  containerStyle: {
                                    transform: `rotate(${f}deg) scale(${v})`,
                                    transition: w ? "none" : ".2s transform",
                                  },
                                  hideControls: !1,
                                  initialVideoState: s,
                                }),
                              },
                              D.id || D.fileName,
                            ),
                          }),
                      },
                      D.id || D.fileName,
                    ),
                  }),
                  ge ? be : null,
                  ne ? we : null,
                  c,
                  z,
                ],
              }),
            }),
            X.portalRoot,
          )
        : (logger.warn(
            `[AttachmentCarousel] Bad state - missing attachment at index ${n}`,
          ),
          null);
    },
  ),
  ye = (e) => {
    if (hi(e)) return [];
    const n =
        e.tweets?.flatMap((t, o) =>
          t.attachments?.map((a) => ({ ...a, id: `${a.id}_${o}` })),
        ) || [],
      i = e.attachments || [];
    return (n ? [...i, ...n] : i).filter((t) => t && t.type !== K.AUDIO);
  },
  $t = Ee((e) => {
    const { thread: n, message: i, attachments: t, setIndex: o } = e,
      a = C.useContext(De),
      r = C.useRef(null),
      [s, l] = C.useState(null);
    C.useEffect(() => {
      l(null);
    }, [i.id]);
    const d = n.threadForMessage(i),
      u = i.accountID || d.accountID,
      c = Z.accountsStore.getAccount(u),
      f = !i.isAction && !i.isDeleted && !n.pendingMessages.has(i.id),
      p =
        f &&
        d.canReact &&
        !d.computedIsReadonly &&
        c?.platform.extra?.canReact?.(i) !== !1 &&
        !i.extra?.callAction,
      v =
        f &&
        d.canReply(i) &&
        !!c?.platform.attributes.has(Di.SUPPORTS_QUOTED_MESSAGES),
      h = !i.isAction && !a.selectedThread?.editingMessageID,
      w = !!(i.reactions?.length && !i.isDeleted),
      b = () => {
        (a.document.dispatchEvent(
          new CustomEvent(qe.CarouselClosed, { detail: t }),
        ),
          o(null));
      },
      S = () => {
        const P = r.current;
        if (!P) return;
        a.selectOnlyMessage(i.id);
        const E = P.getBoundingClientRect();
        (P.focus(), l({ top: E.bottom + 4, left: E.right }));
      },
      g = (P) => {
        (P?.stopPropagation(), je(() => l(null)));
      },
      Y = () => {
        (Z.quoteAndReply(a, n, [i]), b(), je(() => a.focusMessageInput()));
      },
      X = () => {
        (a.selectOnlyMessage(i.id),
          Be.FORWARD_MESSAGES.canOpen?.() &&
            (b(), a.cmdBarViewStore.showWithSubMenu(Be.FORWARD_MESSAGES)));
      },
      k = m.jsxs(m.Fragment, {
        children: [
          p &&
            m.jsx(V, {
              content: N("React", "attachment carousel action"),
              children: m.jsx("button", {
                ref: r,
                type: "button",
                className: "carousel-control",
                "aria-label": N("React", "attachment carousel action"),
                onClick: (P) => {
                  (P.stopPropagation(), S());
                },
                onKeyDown: (P) => {
                  P.key !== "Escape" || !s || (P.stopPropagation(), g());
                },
                children: m.jsx(H, { name: "emoji", width: 20, height: 20 }),
              }),
            }),
          v &&
            m.jsx(V, {
              content: N("Reply", "attachment carousel action"),
              children: m.jsx("button", {
                type: "button",
                className: "carousel-control",
                "aria-label": N("Reply", "attachment carousel action"),
                onClick: (P) => {
                  (P.stopPropagation(), Y());
                },
                children: m.jsx(H, { name: "reply", width: 20, height: 20 }),
              }),
            }),
          p &&
            s &&
            m.jsx(gi, {
              top: s.top,
              left: s.left,
              placement: "bottom-end",
              onClose: g,
              children: m.jsx(bi, {
                thread: n,
                message: i,
                accountID: u,
                closeMenu: g,
              }),
            }),
        ],
      }),
      z = () => {
        const P = [
            v && { label: N("Reply…", "message menu action"), action: Y },
            p && { label: N("React…", "message menu action"), action: S },
            h && { label: N("Forward…", "message menu action"), action: X },
          ].filter(Boolean),
          E = f
            ? wi(n, [i], i, n.editingMessageID === i.id).map((M) => ({
                ...M,
                action: () => {
                  (b(), M.action?.());
                },
              }))
            : [];
        return [...P, ...E].length > 0
          ? [Oe, ...P, ...(P.length && E.length ? [Oe] : []), ...E]
          : [];
      },
      W = w
        ? m.jsx("div", {
            className: "carousel-reactions",
            onClick: (P) => P.stopPropagation(),
            children: m.jsx(Si, { message: i, thread: n, accountID: u }),
          })
        : void 0;
    return m.jsx(xt, {
      ...e,
      extraToolbarButtons: k,
      extraMenuItems: z,
      bottomBar: W,
    });
  }),
  ln = Ee(({ thread: e }) => {
    const n = C.useContext(De),
      { carouselState: i, setCarouselState: t } = n;
    if (!i) return null;
    const { messageID: o, attID: a, videoState: r } = i,
      s = e.messages.get(o);
    if (!s) return null;
    const l = ye(s).filter(Boolean);
    if (!l?.length) return null;
    const d = l.findIndex((b) => b.id.startsWith(a));
    if (d === -1) return null;
    const u = (b) => t(l[b]?.id ?? null, o),
      c = () => {
        let b = e.messages.getIndexOf(o) ?? 0;
        for (; b < e.messages.length;) {
          const S = ++b,
            g = e.messages.getAt(S);
          if (g) {
            const Y = ye(g).filter(Boolean);
            if (Y.length > 0) return [Y[0].id, g.id];
          }
        }
      },
      f = () => {
        let b = e.messages.getIndexOf(o) ?? 0;
        for (; b > 0;) {
          const S = --b,
            g = e.messages.getAt(S);
          if (g) {
            const Y = ye(g);
            if (Y.length > 0) return [Y.at(-1).id, g.id];
          }
        }
      },
      p = c(),
      v = f(),
      h = p ? () => t(...p) : void 0,
      w = v ? () => t(...v) : void 0;
    return m.jsx($t, {
      attachments: l,
      index: d,
      setIndex: u,
      selectNextMessage: h,
      selectPreviousMessage: w,
      message: s,
      thread: e,
      initialVideoState: r,
    });
  });
export { xt as CarouselView, ln as default };
//# sourceMappingURL=AttachmentCarousel-CgGBWyXo.js.map
