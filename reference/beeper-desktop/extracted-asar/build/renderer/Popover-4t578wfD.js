import {
  dk as M,
  dj as xt,
  ba as Ot,
  ex as Et,
  aI as At,
  cK as ze,
  aG as Pe,
  bw as Pt,
} from "./App-CsJiApxN.js";
import { a4 as Rt } from "./sentry-common-BxRELKId.js";
import { cE as Ye } from "./matrix-util-Cr_UwXbj.js";
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
    var t = new e.Error().stack;
    t &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[t] = "c62e27a5-ba93-43cc-9e49-e88bbe2c4305"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-c62e27a5-ba93-43cc-9e49-e88bbe2c4305"));
  } catch {}
})();
var Xe = function (t) {
    return t.reduce(function (r, n) {
      var a = n[0],
        o = n[1];
      return ((r[a] = o), r);
    }, {});
  },
  Ge =
    typeof window < "u" && window.document && window.document.createElement
      ? M.useLayoutEffect
      : M.useEffect,
  S = "top",
  k = "bottom",
  W = "right",
  C = "left",
  Se = "auto",
  ce = [S, k, W, C],
  Z = "start",
  ue = "end",
  Dt = "clippingParents",
  it = "viewport",
  ae = "popper",
  jt = "reference",
  Ke = ce.reduce(function (e, t) {
    return e.concat([t + "-" + Z, t + "-" + ue]);
  }, []),
  st = [].concat(ce, [Se]).reduce(function (e, t) {
    return e.concat([t, t + "-" + Z, t + "-" + ue]);
  }, []),
  St = "beforeRead",
  Ct = "read",
  Bt = "afterRead",
  Mt = "beforeMain",
  $t = "main",
  Tt = "afterMain",
  kt = "beforeWrite",
  Wt = "write",
  Lt = "afterWrite",
  Ft = [St, Ct, Bt, Mt, $t, Tt, kt, Wt, Lt];
function H(e) {
  return e ? (e.nodeName || "").toLowerCase() : null;
}
function $(e) {
  if (e == null) return window;
  if (e.toString() !== "[object Window]") {
    var t = e.ownerDocument;
    return (t && t.defaultView) || window;
  }
  return e;
}
function J(e) {
  var t = $(e).Element;
  return e instanceof t || e instanceof Element;
}
function T(e) {
  var t = $(e).HTMLElement;
  return e instanceof t || e instanceof HTMLElement;
}
function Ce(e) {
  if (typeof ShadowRoot > "u") return !1;
  var t = $(e).ShadowRoot;
  return e instanceof t || e instanceof ShadowRoot;
}
function It(e) {
  var t = e.state;
  Object.keys(t.elements).forEach(function (r) {
    var n = t.styles[r] || {},
      a = t.attributes[r] || {},
      o = t.elements[r];
    !T(o) ||
      !H(o) ||
      (Object.assign(o.style, n),
      Object.keys(a).forEach(function (s) {
        var f = a[s];
        f === !1 ? o.removeAttribute(s) : o.setAttribute(s, f === !0 ? "" : f);
      }));
  });
}
function Ht(e) {
  var t = e.state,
    r = {
      popper: {
        position: t.options.strategy,
        left: "0",
        top: "0",
        margin: "0",
      },
      arrow: { position: "absolute" },
      reference: {},
    };
  return (
    Object.assign(t.elements.popper.style, r.popper),
    (t.styles = r),
    t.elements.arrow && Object.assign(t.elements.arrow.style, r.arrow),
    function () {
      Object.keys(t.elements).forEach(function (n) {
        var a = t.elements[n],
          o = t.attributes[n] || {},
          s = Object.keys(t.styles.hasOwnProperty(n) ? t.styles[n] : r[n]),
          f = s.reduce(function (i, c) {
            return ((i[c] = ""), i);
          }, {});
        !T(a) ||
          !H(a) ||
          (Object.assign(a.style, f),
          Object.keys(o).forEach(function (i) {
            a.removeAttribute(i);
          }));
      });
    }
  );
}
const Vt = {
  name: "applyStyles",
  enabled: !0,
  phase: "write",
  fn: It,
  effect: Ht,
  requires: ["computeStyles"],
};
function I(e) {
  return e.split("-")[0];
}
var K = Math.max,
  we = Math.min,
  _ = Math.round;
function De() {
  var e = navigator.userAgentData;
  return e != null && e.brands && Array.isArray(e.brands)
    ? e.brands
        .map(function (t) {
          return t.brand + "/" + t.version;
        })
        .join(" ")
    : navigator.userAgent;
}
function ft() {
  return !/^((?!chrome|android).)*safari/i.test(De());
}
function ee(e, t, r) {
  (t === void 0 && (t = !1), r === void 0 && (r = !1));
  var n = e.getBoundingClientRect(),
    a = 1,
    o = 1;
  t &&
    T(e) &&
    ((a = (e.offsetWidth > 0 && _(n.width) / e.offsetWidth) || 1),
    (o = (e.offsetHeight > 0 && _(n.height) / e.offsetHeight) || 1));
  var s = J(e) ? $(e) : window,
    f = s.visualViewport,
    i = !ft() && r,
    c = (n.left + (i && f ? f.offsetLeft : 0)) / a,
    u = (n.top + (i && f ? f.offsetTop : 0)) / o,
    l = n.width / a,
    d = n.height / o;
  return {
    width: l,
    height: d,
    top: u,
    right: c + l,
    bottom: u + d,
    left: c,
    x: c,
    y: u,
  };
}
function Be(e) {
  var t = ee(e),
    r = e.offsetWidth,
    n = e.offsetHeight;
  return (
    Math.abs(t.width - r) <= 1 && (r = t.width),
    Math.abs(t.height - n) <= 1 && (n = t.height),
    { x: e.offsetLeft, y: e.offsetTop, width: r, height: n }
  );
}
function ut(e, t) {
  var r = t.getRootNode && t.getRootNode();
  if (e.contains(t)) return !0;
  if (r && Ce(r)) {
    var n = t;
    do {
      if (n && e.isSameNode(n)) return !0;
      n = n.parentNode || n.host;
    } while (n);
  }
  return !1;
}
function V(e) {
  return $(e).getComputedStyle(e);
}
function qt(e) {
  return ["table", "td", "th"].indexOf(H(e)) >= 0;
}
function N(e) {
  return ((J(e) ? e.ownerDocument : e.document) || window.document)
    .documentElement;
}
function be(e) {
  return H(e) === "html"
    ? e
    : e.assignedSlot || e.parentNode || (Ce(e) ? e.host : null) || N(e);
}
function Je(e) {
  return !T(e) || V(e).position === "fixed" ? null : e.offsetParent;
}
function Nt(e) {
  var t = /firefox/i.test(De()),
    r = /Trident/i.test(De());
  if (r && T(e)) {
    var n = V(e);
    if (n.position === "fixed") return null;
  }
  var a = be(e);
  for (Ce(a) && (a = a.host); T(a) && ["html", "body"].indexOf(H(a)) < 0;) {
    var o = V(a);
    if (
      o.transform !== "none" ||
      o.perspective !== "none" ||
      o.contain === "paint" ||
      ["transform", "perspective"].indexOf(o.willChange) !== -1 ||
      (t && o.willChange === "filter") ||
      (t && o.filter && o.filter !== "none")
    )
      return a;
    a = a.parentNode;
  }
  return null;
}
function pe(e) {
  for (var t = $(e), r = Je(e); r && qt(r) && V(r).position === "static";)
    r = Je(r);
  return r &&
    (H(r) === "html" || (H(r) === "body" && V(r).position === "static"))
    ? t
    : r || Nt(e) || t;
}
function Me(e) {
  return ["top", "bottom"].indexOf(e) >= 0 ? "x" : "y";
}
function se(e, t, r) {
  return K(e, we(t, r));
}
function Ut(e, t, r) {
  var n = se(e, t, r);
  return n > r ? r : n;
}
function ct() {
  return { top: 0, right: 0, bottom: 0, left: 0 };
}
function pt(e) {
  return Object.assign({}, ct(), e);
}
function lt(e, t) {
  return t.reduce(function (r, n) {
    return ((r[n] = e), r);
  }, {});
}
var zt = function (t, r) {
  return (
    (t =
      typeof t == "function"
        ? t(Object.assign({}, r.rects, { placement: r.placement }))
        : t),
    pt(typeof t != "number" ? t : lt(t, ce))
  );
};
function Yt(e) {
  var t,
    r = e.state,
    n = e.name,
    a = e.options,
    o = r.elements.arrow,
    s = r.modifiersData.popperOffsets,
    f = I(r.placement),
    i = Me(f),
    c = [C, W].indexOf(f) >= 0,
    u = c ? "height" : "width";
  if (!(!o || !s)) {
    var l = zt(a.padding, r),
      d = Be(o),
      p = i === "y" ? S : C,
      y = i === "y" ? k : W,
      h =
        r.rects.reference[u] + r.rects.reference[i] - s[i] - r.rects.popper[u],
      v = s[i] - r.rects.reference[i],
      x = pe(o),
      O = x ? (i === "y" ? x.clientHeight || 0 : x.clientWidth || 0) : 0,
      E = h / 2 - v / 2,
      m = l[p],
      g = O - d[u] - l[y],
      w = O / 2 - d[u] / 2 + E,
      b = se(m, w, g),
      R = i;
    r.modifiersData[n] = ((t = {}), (t[R] = b), (t.centerOffset = b - w), t);
  }
}
function Xt(e) {
  var t = e.state,
    r = e.options,
    n = r.element,
    a = n === void 0 ? "[data-popper-arrow]" : n;
  a != null &&
    ((typeof a == "string" && ((a = t.elements.popper.querySelector(a)), !a)) ||
      (ut(t.elements.popper, a) && (t.elements.arrow = a)));
}
const Gt = {
  name: "arrow",
  enabled: !0,
  phase: "main",
  fn: Yt,
  effect: Xt,
  requires: ["popperOffsets"],
  requiresIfExists: ["preventOverflow"],
};
function te(e) {
  return e.split("-")[1];
}
var Kt = { top: "auto", right: "auto", bottom: "auto", left: "auto" };
function Jt(e, t) {
  var r = e.x,
    n = e.y,
    a = t.devicePixelRatio || 1;
  return { x: _(r * a) / a || 0, y: _(n * a) / a || 0 };
}
function Qe(e) {
  var t,
    r = e.popper,
    n = e.popperRect,
    a = e.placement,
    o = e.variation,
    s = e.offsets,
    f = e.position,
    i = e.gpuAcceleration,
    c = e.adaptive,
    u = e.roundOffsets,
    l = e.isFixed,
    d = s.x,
    p = d === void 0 ? 0 : d,
    y = s.y,
    h = y === void 0 ? 0 : y,
    v = typeof u == "function" ? u({ x: p, y: h }) : { x: p, y: h };
  ((p = v.x), (h = v.y));
  var x = s.hasOwnProperty("x"),
    O = s.hasOwnProperty("y"),
    E = C,
    m = S,
    g = window;
  if (c) {
    var w = pe(r),
      b = "clientHeight",
      R = "clientWidth";
    if (
      (w === $(r) &&
        ((w = N(r)),
        V(w).position !== "static" &&
          f === "absolute" &&
          ((b = "scrollHeight"), (R = "scrollWidth"))),
      (w = w),
      a === S || ((a === C || a === W) && o === ue))
    ) {
      m = k;
      var P = l && w === g && g.visualViewport ? g.visualViewport.height : w[b];
      ((h -= P - n.height), (h *= i ? 1 : -1));
    }
    if (a === C || ((a === S || a === k) && o === ue)) {
      E = W;
      var A = l && w === g && g.visualViewport ? g.visualViewport.width : w[R];
      ((p -= A - n.width), (p *= i ? 1 : -1));
    }
  }
  var D = Object.assign({ position: f }, c && Kt),
    L = u === !0 ? Jt({ x: p, y: h }, $(r)) : { x: p, y: h };
  if (((p = L.x), (h = L.y), i)) {
    var j;
    return Object.assign(
      {},
      D,
      ((j = {}),
      (j[m] = O ? "0" : ""),
      (j[E] = x ? "0" : ""),
      (j.transform =
        (g.devicePixelRatio || 1) <= 1
          ? "translate(" + p + "px, " + h + "px)"
          : "translate3d(" + p + "px, " + h + "px, 0)"),
      j),
    );
  }
  return Object.assign(
    {},
    D,
    ((t = {}),
    (t[m] = O ? h + "px" : ""),
    (t[E] = x ? p + "px" : ""),
    (t.transform = ""),
    t),
  );
}
function Qt(e) {
  var t = e.state,
    r = e.options,
    n = r.gpuAcceleration,
    a = n === void 0 ? !0 : n,
    o = r.adaptive,
    s = o === void 0 ? !0 : o,
    f = r.roundOffsets,
    i = f === void 0 ? !0 : f,
    c = {
      placement: I(t.placement),
      variation: te(t.placement),
      popper: t.elements.popper,
      popperRect: t.rects.popper,
      gpuAcceleration: a,
      isFixed: t.options.strategy === "fixed",
    };
  (t.modifiersData.popperOffsets != null &&
    (t.styles.popper = Object.assign(
      {},
      t.styles.popper,
      Qe(
        Object.assign({}, c, {
          offsets: t.modifiersData.popperOffsets,
          position: t.options.strategy,
          adaptive: s,
          roundOffsets: i,
        }),
      ),
    )),
    t.modifiersData.arrow != null &&
      (t.styles.arrow = Object.assign(
        {},
        t.styles.arrow,
        Qe(
          Object.assign({}, c, {
            offsets: t.modifiersData.arrow,
            position: "absolute",
            adaptive: !1,
            roundOffsets: i,
          }),
        ),
      )),
    (t.attributes.popper = Object.assign({}, t.attributes.popper, {
      "data-popper-placement": t.placement,
    })));
}
const Zt = {
  name: "computeStyles",
  enabled: !0,
  phase: "beforeWrite",
  fn: Qt,
  data: {},
};
var ye = { passive: !0 };
function _t(e) {
  var t = e.state,
    r = e.instance,
    n = e.options,
    a = n.scroll,
    o = a === void 0 ? !0 : a,
    s = n.resize,
    f = s === void 0 ? !0 : s,
    i = $(t.elements.popper),
    c = [].concat(t.scrollParents.reference, t.scrollParents.popper);
  return (
    o &&
      c.forEach(function (u) {
        u.addEventListener("scroll", r.update, ye);
      }),
    f && i.addEventListener("resize", r.update, ye),
    function () {
      (o &&
        c.forEach(function (u) {
          u.removeEventListener("scroll", r.update, ye);
        }),
        f && i.removeEventListener("resize", r.update, ye));
    }
  );
}
const er = {
  name: "eventListeners",
  enabled: !0,
  phase: "write",
  fn: function () {},
  effect: _t,
  data: {},
};
var tr = { left: "right", right: "left", bottom: "top", top: "bottom" };
function ge(e) {
  return e.replace(/left|right|bottom|top/g, function (t) {
    return tr[t];
  });
}
var rr = { start: "end", end: "start" };
function Ze(e) {
  return e.replace(/start|end/g, function (t) {
    return rr[t];
  });
}
function $e(e) {
  var t = $(e),
    r = t.pageXOffset,
    n = t.pageYOffset;
  return { scrollLeft: r, scrollTop: n };
}
function Te(e) {
  return ee(N(e)).left + $e(e).scrollLeft;
}
function nr(e, t) {
  var r = $(e),
    n = N(e),
    a = r.visualViewport,
    o = n.clientWidth,
    s = n.clientHeight,
    f = 0,
    i = 0;
  if (a) {
    ((o = a.width), (s = a.height));
    var c = ft();
    (c || (!c && t === "fixed")) && ((f = a.offsetLeft), (i = a.offsetTop));
  }
  return { width: o, height: s, x: f + Te(e), y: i };
}
function or(e) {
  var t,
    r = N(e),
    n = $e(e),
    a = (t = e.ownerDocument) == null ? void 0 : t.body,
    o = K(
      r.scrollWidth,
      r.clientWidth,
      a ? a.scrollWidth : 0,
      a ? a.clientWidth : 0,
    ),
    s = K(
      r.scrollHeight,
      r.clientHeight,
      a ? a.scrollHeight : 0,
      a ? a.clientHeight : 0,
    ),
    f = -n.scrollLeft + Te(e),
    i = -n.scrollTop;
  return (
    V(a || r).direction === "rtl" &&
      (f += K(r.clientWidth, a ? a.clientWidth : 0) - o),
    { width: o, height: s, x: f, y: i }
  );
}
function ke(e) {
  var t = V(e),
    r = t.overflow,
    n = t.overflowX,
    a = t.overflowY;
  return /auto|scroll|overlay|hidden/.test(r + a + n);
}
function vt(e) {
  return ["html", "body", "#document"].indexOf(H(e)) >= 0
    ? e.ownerDocument.body
    : T(e) && ke(e)
      ? e
      : vt(be(e));
}
function fe(e, t) {
  var r;
  t === void 0 && (t = []);
  var n = vt(e),
    a = n === ((r = e.ownerDocument) == null ? void 0 : r.body),
    o = $(n),
    s = a ? [o].concat(o.visualViewport || [], ke(n) ? n : []) : n,
    f = t.concat(s);
  return a ? f : f.concat(fe(be(s)));
}
function je(e) {
  return Object.assign({}, e, {
    left: e.x,
    top: e.y,
    right: e.x + e.width,
    bottom: e.y + e.height,
  });
}
function ar(e, t) {
  var r = ee(e, !1, t === "fixed");
  return (
    (r.top = r.top + e.clientTop),
    (r.left = r.left + e.clientLeft),
    (r.bottom = r.top + e.clientHeight),
    (r.right = r.left + e.clientWidth),
    (r.width = e.clientWidth),
    (r.height = e.clientHeight),
    (r.x = r.left),
    (r.y = r.top),
    r
  );
}
function _e(e, t, r) {
  return t === it ? je(nr(e, r)) : J(t) ? ar(t, r) : je(or(N(e)));
}
function ir(e) {
  var t = fe(be(e)),
    r = ["absolute", "fixed"].indexOf(V(e).position) >= 0,
    n = r && T(e) ? pe(e) : e;
  return J(n)
    ? t.filter(function (a) {
        return J(a) && ut(a, n) && H(a) !== "body";
      })
    : [];
}
function sr(e, t, r, n) {
  var a = t === "clippingParents" ? ir(e) : [].concat(t),
    o = [].concat(a, [r]),
    s = o[0],
    f = o.reduce(
      function (i, c) {
        var u = _e(e, c, n);
        return (
          (i.top = K(u.top, i.top)),
          (i.right = we(u.right, i.right)),
          (i.bottom = we(u.bottom, i.bottom)),
          (i.left = K(u.left, i.left)),
          i
        );
      },
      _e(e, s, n),
    );
  return (
    (f.width = f.right - f.left),
    (f.height = f.bottom - f.top),
    (f.x = f.left),
    (f.y = f.top),
    f
  );
}
function dt(e) {
  var t = e.reference,
    r = e.element,
    n = e.placement,
    a = n ? I(n) : null,
    o = n ? te(n) : null,
    s = t.x + t.width / 2 - r.width / 2,
    f = t.y + t.height / 2 - r.height / 2,
    i;
  switch (a) {
    case S:
      i = { x: s, y: t.y - r.height };
      break;
    case k:
      i = { x: s, y: t.y + t.height };
      break;
    case W:
      i = { x: t.x + t.width, y: f };
      break;
    case C:
      i = { x: t.x - r.width, y: f };
      break;
    default:
      i = { x: t.x, y: t.y };
  }
  var c = a ? Me(a) : null;
  if (c != null) {
    var u = c === "y" ? "height" : "width";
    switch (o) {
      case Z:
        i[c] = i[c] - (t[u] / 2 - r[u] / 2);
        break;
      case ue:
        i[c] = i[c] + (t[u] / 2 - r[u] / 2);
        break;
    }
  }
  return i;
}
function re(e, t) {
  t === void 0 && (t = {});
  var r = t,
    n = r.placement,
    a = n === void 0 ? e.placement : n,
    o = r.strategy,
    s = o === void 0 ? e.strategy : o,
    f = r.boundary,
    i = f === void 0 ? Dt : f,
    c = r.rootBoundary,
    u = c === void 0 ? it : c,
    l = r.elementContext,
    d = l === void 0 ? ae : l,
    p = r.altBoundary,
    y = p === void 0 ? !1 : p,
    h = r.padding,
    v = h === void 0 ? 0 : h,
    x = pt(typeof v != "number" ? v : lt(v, ce)),
    O = d === ae ? jt : ae,
    E = e.rects.popper,
    m = e.elements[y ? O : d],
    g = sr(J(m) ? m : m.contextElement || N(e.elements.popper), i, u, s),
    w = ee(e.elements.reference),
    b = dt({ reference: w, element: E, placement: a }),
    R = je(Object.assign({}, E, b)),
    P = d === ae ? R : w,
    A = {
      top: g.top - P.top + x.top,
      bottom: P.bottom - g.bottom + x.bottom,
      left: g.left - P.left + x.left,
      right: P.right - g.right + x.right,
    },
    D = e.modifiersData.offset;
  if (d === ae && D) {
    var L = D[a];
    Object.keys(A).forEach(function (j) {
      var U = [W, k].indexOf(j) >= 0 ? 1 : -1,
        z = [S, k].indexOf(j) >= 0 ? "y" : "x";
      A[j] += L[z] * U;
    });
  }
  return A;
}
function fr(e, t) {
  t === void 0 && (t = {});
  var r = t,
    n = r.placement,
    a = r.boundary,
    o = r.rootBoundary,
    s = r.padding,
    f = r.flipVariations,
    i = r.allowedAutoPlacements,
    c = i === void 0 ? st : i,
    u = te(n),
    l = u
      ? f
        ? Ke
        : Ke.filter(function (y) {
            return te(y) === u;
          })
      : ce,
    d = l.filter(function (y) {
      return c.indexOf(y) >= 0;
    });
  d.length === 0 && (d = l);
  var p = d.reduce(function (y, h) {
    return (
      (y[h] = re(e, { placement: h, boundary: a, rootBoundary: o, padding: s })[
        I(h)
      ]),
      y
    );
  }, {});
  return Object.keys(p).sort(function (y, h) {
    return p[y] - p[h];
  });
}
function ur(e) {
  if (I(e) === Se) return [];
  var t = ge(e);
  return [Ze(e), t, Ze(t)];
}
function cr(e) {
  var t = e.state,
    r = e.options,
    n = e.name;
  if (!t.modifiersData[n]._skip) {
    for (
      var a = r.mainAxis,
        o = a === void 0 ? !0 : a,
        s = r.altAxis,
        f = s === void 0 ? !0 : s,
        i = r.fallbackPlacements,
        c = r.padding,
        u = r.boundary,
        l = r.rootBoundary,
        d = r.altBoundary,
        p = r.flipVariations,
        y = p === void 0 ? !0 : p,
        h = r.allowedAutoPlacements,
        v = t.options.placement,
        x = I(v),
        O = x === v,
        E = i || (O || !y ? [ge(v)] : ur(v)),
        m = [v].concat(E).reduce(function (Q, q) {
          return Q.concat(
            I(q) === Se
              ? fr(t, {
                  placement: q,
                  boundary: u,
                  rootBoundary: l,
                  padding: c,
                  flipVariations: y,
                  allowedAutoPlacements: h,
                })
              : q,
          );
        }, []),
        g = t.rects.reference,
        w = t.rects.popper,
        b = new Map(),
        R = !0,
        P = m[0],
        A = 0;
      A < m.length;
      A++
    ) {
      var D = m[A],
        L = I(D),
        j = te(D) === Z,
        U = [S, k].indexOf(L) >= 0,
        z = U ? "width" : "height",
        B = re(t, {
          placement: D,
          boundary: u,
          rootBoundary: l,
          altBoundary: d,
          padding: c,
        }),
        F = U ? (j ? W : C) : j ? k : S;
      g[z] > w[z] && (F = ge(F));
      var le = ge(F),
        Y = [];
      if (
        (o && Y.push(B[L] <= 0),
        f && Y.push(B[F] <= 0, B[le] <= 0),
        Y.every(function (Q) {
          return Q;
        }))
      ) {
        ((P = D), (R = !1));
        break;
      }
      b.set(D, Y);
    }
    if (R)
      for (
        var ve = y ? 3 : 1,
          xe = function (q) {
            var oe = m.find(function (me) {
              var X = b.get(me);
              if (X)
                return X.slice(0, q).every(function (Oe) {
                  return Oe;
                });
            });
            if (oe) return ((P = oe), "break");
          },
          ne = ve;
        ne > 0;
        ne--
      ) {
        var de = xe(ne);
        if (de === "break") break;
      }
    t.placement !== P &&
      ((t.modifiersData[n]._skip = !0), (t.placement = P), (t.reset = !0));
  }
}
const pr = {
  name: "flip",
  enabled: !0,
  phase: "main",
  fn: cr,
  requiresIfExists: ["offset"],
  data: { _skip: !1 },
};
function et(e, t, r) {
  return (
    r === void 0 && (r = { x: 0, y: 0 }),
    {
      top: e.top - t.height - r.y,
      right: e.right - t.width + r.x,
      bottom: e.bottom - t.height + r.y,
      left: e.left - t.width - r.x,
    }
  );
}
function tt(e) {
  return [S, W, k, C].some(function (t) {
    return e[t] >= 0;
  });
}
function lr(e) {
  var t = e.state,
    r = e.name,
    n = t.rects.reference,
    a = t.rects.popper,
    o = t.modifiersData.preventOverflow,
    s = re(t, { elementContext: "reference" }),
    f = re(t, { altBoundary: !0 }),
    i = et(s, n),
    c = et(f, a, o),
    u = tt(i),
    l = tt(c);
  ((t.modifiersData[r] = {
    referenceClippingOffsets: i,
    popperEscapeOffsets: c,
    isReferenceHidden: u,
    hasPopperEscaped: l,
  }),
    (t.attributes.popper = Object.assign({}, t.attributes.popper, {
      "data-popper-reference-hidden": u,
      "data-popper-escaped": l,
    })));
}
const vr = {
  name: "hide",
  enabled: !0,
  phase: "main",
  requiresIfExists: ["preventOverflow"],
  fn: lr,
};
function dr(e, t, r) {
  var n = I(e),
    a = [C, S].indexOf(n) >= 0 ? -1 : 1,
    o = typeof r == "function" ? r(Object.assign({}, t, { placement: e })) : r,
    s = o[0],
    f = o[1];
  return (
    (s = s || 0),
    (f = (f || 0) * a),
    [C, W].indexOf(n) >= 0 ? { x: f, y: s } : { x: s, y: f }
  );
}
function mr(e) {
  var t = e.state,
    r = e.options,
    n = e.name,
    a = r.offset,
    o = a === void 0 ? [0, 0] : a,
    s = st.reduce(function (u, l) {
      return ((u[l] = dr(l, t.rects, o)), u);
    }, {}),
    f = s[t.placement],
    i = f.x,
    c = f.y;
  (t.modifiersData.popperOffsets != null &&
    ((t.modifiersData.popperOffsets.x += i),
    (t.modifiersData.popperOffsets.y += c)),
    (t.modifiersData[n] = s));
}
const hr = {
  name: "offset",
  enabled: !0,
  phase: "main",
  requires: ["popperOffsets"],
  fn: mr,
};
function yr(e) {
  var t = e.state,
    r = e.name;
  t.modifiersData[r] = dt({
    reference: t.rects.reference,
    element: t.rects.popper,
    placement: t.placement,
  });
}
const gr = {
  name: "popperOffsets",
  enabled: !0,
  phase: "read",
  fn: yr,
  data: {},
};
function wr(e) {
  return e === "x" ? "y" : "x";
}
function br(e) {
  var t = e.state,
    r = e.options,
    n = e.name,
    a = r.mainAxis,
    o = a === void 0 ? !0 : a,
    s = r.altAxis,
    f = s === void 0 ? !1 : s,
    i = r.boundary,
    c = r.rootBoundary,
    u = r.altBoundary,
    l = r.padding,
    d = r.tether,
    p = d === void 0 ? !0 : d,
    y = r.tetherOffset,
    h = y === void 0 ? 0 : y,
    v = re(t, { boundary: i, rootBoundary: c, padding: l, altBoundary: u }),
    x = I(t.placement),
    O = te(t.placement),
    E = !O,
    m = Me(x),
    g = wr(m),
    w = t.modifiersData.popperOffsets,
    b = t.rects.reference,
    R = t.rects.popper,
    P =
      typeof h == "function"
        ? h(Object.assign({}, t.rects, { placement: t.placement }))
        : h,
    A =
      typeof P == "number"
        ? { mainAxis: P, altAxis: P }
        : Object.assign({ mainAxis: 0, altAxis: 0 }, P),
    D = t.modifiersData.offset ? t.modifiersData.offset[t.placement] : null,
    L = { x: 0, y: 0 };
  if (w) {
    if (o) {
      var j,
        U = m === "y" ? S : C,
        z = m === "y" ? k : W,
        B = m === "y" ? "height" : "width",
        F = w[m],
        le = F + v[U],
        Y = F - v[z],
        ve = p ? -R[B] / 2 : 0,
        xe = O === Z ? b[B] : R[B],
        ne = O === Z ? -R[B] : -b[B],
        de = t.elements.arrow,
        Q = p && de ? Be(de) : { width: 0, height: 0 },
        q = t.modifiersData["arrow#persistent"]
          ? t.modifiersData["arrow#persistent"].padding
          : ct(),
        oe = q[U],
        me = q[z],
        X = se(0, b[B], Q[B]),
        Oe = E ? b[B] / 2 - ve - X - oe - A.mainAxis : xe - X - oe - A.mainAxis,
        mt = E
          ? -b[B] / 2 + ve + X + me + A.mainAxis
          : ne + X + me + A.mainAxis,
        Ee = t.elements.arrow && pe(t.elements.arrow),
        ht = Ee ? (m === "y" ? Ee.clientTop || 0 : Ee.clientLeft || 0) : 0,
        We = (j = D?.[m]) != null ? j : 0,
        yt = F + Oe - We - ht,
        gt = F + mt - We,
        Le = se(p ? we(le, yt) : le, F, p ? K(Y, gt) : Y);
      ((w[m] = Le), (L[m] = Le - F));
    }
    if (f) {
      var Fe,
        wt = m === "x" ? S : C,
        bt = m === "x" ? k : W,
        G = w[g],
        he = g === "y" ? "height" : "width",
        Ie = G + v[wt],
        He = G - v[bt],
        Ae = [S, C].indexOf(x) !== -1,
        Ve = (Fe = D?.[g]) != null ? Fe : 0,
        qe = Ae ? Ie : G - b[he] - R[he] - Ve + A.altAxis,
        Ne = Ae ? G + b[he] + R[he] - Ve - A.altAxis : He,
        Ue = p && Ae ? Ut(qe, G, Ne) : se(p ? qe : Ie, G, p ? Ne : He);
      ((w[g] = Ue), (L[g] = Ue - G));
    }
    t.modifiersData[n] = L;
  }
}
const xr = {
  name: "preventOverflow",
  enabled: !0,
  phase: "main",
  fn: br,
  requiresIfExists: ["offset"],
};
function Or(e) {
  return { scrollLeft: e.scrollLeft, scrollTop: e.scrollTop };
}
function Er(e) {
  return e === $(e) || !T(e) ? $e(e) : Or(e);
}
function Ar(e) {
  var t = e.getBoundingClientRect(),
    r = _(t.width) / e.offsetWidth || 1,
    n = _(t.height) / e.offsetHeight || 1;
  return r !== 1 || n !== 1;
}
function Pr(e, t, r) {
  r === void 0 && (r = !1);
  var n = T(t),
    a = T(t) && Ar(t),
    o = N(t),
    s = ee(e, a, r),
    f = { scrollLeft: 0, scrollTop: 0 },
    i = { x: 0, y: 0 };
  return (
    (n || (!n && !r)) &&
      ((H(t) !== "body" || ke(o)) && (f = Er(t)),
      T(t)
        ? ((i = ee(t, !0)), (i.x += t.clientLeft), (i.y += t.clientTop))
        : o && (i.x = Te(o))),
    {
      x: s.left + f.scrollLeft - i.x,
      y: s.top + f.scrollTop - i.y,
      width: s.width,
      height: s.height,
    }
  );
}
function Rr(e) {
  var t = new Map(),
    r = new Set(),
    n = [];
  e.forEach(function (o) {
    t.set(o.name, o);
  });
  function a(o) {
    r.add(o.name);
    var s = [].concat(o.requires || [], o.requiresIfExists || []);
    (s.forEach(function (f) {
      if (!r.has(f)) {
        var i = t.get(f);
        i && a(i);
      }
    }),
      n.push(o));
  }
  return (
    e.forEach(function (o) {
      r.has(o.name) || a(o);
    }),
    n
  );
}
function Dr(e) {
  var t = Rr(e);
  return Ft.reduce(function (r, n) {
    return r.concat(
      t.filter(function (a) {
        return a.phase === n;
      }),
    );
  }, []);
}
function jr(e) {
  var t;
  return function () {
    return (
      t ||
        (t = new Promise(function (r) {
          Promise.resolve().then(function () {
            ((t = void 0), r(e()));
          });
        })),
      t
    );
  };
}
function Sr(e) {
  var t = e.reduce(function (r, n) {
    var a = r[n.name];
    return (
      (r[n.name] = a
        ? Object.assign({}, a, n, {
            options: Object.assign({}, a.options, n.options),
            data: Object.assign({}, a.data, n.data),
          })
        : n),
      r
    );
  }, {});
  return Object.keys(t).map(function (r) {
    return t[r];
  });
}
var rt = { placement: "bottom", modifiers: [], strategy: "absolute" };
function nt() {
  for (var e = arguments.length, t = new Array(e), r = 0; r < e; r++)
    t[r] = arguments[r];
  return !t.some(function (n) {
    return !(n && typeof n.getBoundingClientRect == "function");
  });
}
function Cr(e) {
  e === void 0 && (e = {});
  var t = e,
    r = t.defaultModifiers,
    n = r === void 0 ? [] : r,
    a = t.defaultOptions,
    o = a === void 0 ? rt : a;
  return function (f, i, c) {
    c === void 0 && (c = o);
    var u = {
        placement: "bottom",
        orderedModifiers: [],
        options: Object.assign({}, rt, o),
        modifiersData: {},
        elements: { reference: f, popper: i },
        attributes: {},
        styles: {},
      },
      l = [],
      d = !1,
      p = {
        state: u,
        setOptions: function (x) {
          var O = typeof x == "function" ? x(u.options) : x;
          (h(),
            (u.options = Object.assign({}, o, u.options, O)),
            (u.scrollParents = {
              reference: J(f)
                ? fe(f)
                : f.contextElement
                  ? fe(f.contextElement)
                  : [],
              popper: fe(i),
            }));
          var E = Dr(Sr([].concat(n, u.options.modifiers)));
          return (
            (u.orderedModifiers = E.filter(function (m) {
              return m.enabled;
            })),
            y(),
            p.update()
          );
        },
        forceUpdate: function () {
          if (!d) {
            var x = u.elements,
              O = x.reference,
              E = x.popper;
            if (nt(O, E)) {
              ((u.rects = {
                reference: Pr(O, pe(E), u.options.strategy === "fixed"),
                popper: Be(E),
              }),
                (u.reset = !1),
                (u.placement = u.options.placement),
                u.orderedModifiers.forEach(function (A) {
                  return (u.modifiersData[A.name] = Object.assign({}, A.data));
                }));
              for (var m = 0; m < u.orderedModifiers.length; m++) {
                if (u.reset === !0) {
                  ((u.reset = !1), (m = -1));
                  continue;
                }
                var g = u.orderedModifiers[m],
                  w = g.fn,
                  b = g.options,
                  R = b === void 0 ? {} : b,
                  P = g.name;
                typeof w == "function" &&
                  (u = w({ state: u, options: R, name: P, instance: p }) || u);
              }
            }
          }
        },
        update: jr(function () {
          return new Promise(function (v) {
            (p.forceUpdate(), v(u));
          });
        }),
        destroy: function () {
          (h(), (d = !0));
        },
      };
    if (!nt(f, i)) return p;
    p.setOptions(c).then(function (v) {
      !d && c.onFirstUpdate && c.onFirstUpdate(v);
    });
    function y() {
      u.orderedModifiers.forEach(function (v) {
        var x = v.name,
          O = v.options,
          E = O === void 0 ? {} : O,
          m = v.effect;
        if (typeof m == "function") {
          var g = m({ state: u, name: x, instance: p, options: E }),
            w = function () {};
          l.push(g || w);
        }
      });
    }
    function h() {
      (l.forEach(function (v) {
        return v();
      }),
        (l = []));
    }
    return p;
  };
}
var Br = [er, gr, Zt, Vt, hr, pr, xr, Gt, vr],
  Mr = Cr({ defaultModifiers: Br }),
  Re,
  ot;
function $r() {
  if (ot) return Re;
  ot = 1;
  var e = typeof Element < "u",
    t = typeof Map == "function",
    r = typeof Set == "function",
    n = typeof ArrayBuffer == "function" && !!ArrayBuffer.isView;
  function a(o, s) {
    if (o === s) return !0;
    if (o && s && typeof o == "object" && typeof s == "object") {
      if (o.constructor !== s.constructor) return !1;
      var f, i, c;
      if (Array.isArray(o)) {
        if (((f = o.length), f != s.length)) return !1;
        for (i = f; i-- !== 0;) if (!a(o[i], s[i])) return !1;
        return !0;
      }
      var u;
      if (t && o instanceof Map && s instanceof Map) {
        if (o.size !== s.size) return !1;
        for (u = o.entries(); !(i = u.next()).done;)
          if (!s.has(i.value[0])) return !1;
        for (u = o.entries(); !(i = u.next()).done;)
          if (!a(i.value[1], s.get(i.value[0]))) return !1;
        return !0;
      }
      if (r && o instanceof Set && s instanceof Set) {
        if (o.size !== s.size) return !1;
        for (u = o.entries(); !(i = u.next()).done;)
          if (!s.has(i.value[0])) return !1;
        return !0;
      }
      if (n && ArrayBuffer.isView(o) && ArrayBuffer.isView(s)) {
        if (((f = o.length), f != s.length)) return !1;
        for (i = f; i-- !== 0;) if (o[i] !== s[i]) return !1;
        return !0;
      }
      if (o.constructor === RegExp)
        return o.source === s.source && o.flags === s.flags;
      if (
        o.valueOf !== Object.prototype.valueOf &&
        typeof o.valueOf == "function" &&
        typeof s.valueOf == "function"
      )
        return o.valueOf() === s.valueOf();
      if (
        o.toString !== Object.prototype.toString &&
        typeof o.toString == "function" &&
        typeof s.toString == "function"
      )
        return o.toString() === s.toString();
      if (((c = Object.keys(o)), (f = c.length), f !== Object.keys(s).length))
        return !1;
      for (i = f; i-- !== 0;)
        if (!Object.prototype.hasOwnProperty.call(s, c[i])) return !1;
      if (e && o instanceof Element) return !1;
      for (i = f; i-- !== 0;)
        if (
          !(
            (c[i] === "_owner" || c[i] === "__v" || c[i] === "__o") &&
            o.$$typeof
          ) &&
          !a(o[c[i]], s[c[i]])
        )
          return !1;
      return !0;
    }
    return o !== o && s !== s;
  }
  return (
    (Re = function (s, f) {
      try {
        return a(s, f);
      } catch (i) {
        if ((i.message || "").match(/stack|recursion/i))
          return (
            console.warn("react-fast-compare cannot handle circular refs"),
            !1
          );
        throw i;
      }
    }),
    Re
  );
}
var Tr = $r();
const kr = Rt(Tr);
var Wr = [],
  Lr = function (t, r, n) {
    n === void 0 && (n = {});
    var a = M.useRef(null),
      o = {
        onFirstUpdate: n.onFirstUpdate,
        placement: n.placement || "bottom",
        strategy: n.strategy || "absolute",
        modifiers: n.modifiers || Wr,
      },
      s = M.useState({
        styles: {
          popper: { position: o.strategy, left: "0", top: "0" },
          arrow: { position: "absolute" },
        },
        attributes: {},
      }),
      f = s[0],
      i = s[1],
      c = M.useMemo(function () {
        return {
          name: "updateState",
          enabled: !0,
          phase: "write",
          fn: function (p) {
            var y = p.state,
              h = Object.keys(y.elements);
            xt.flushSync(function () {
              i({
                styles: Xe(
                  h.map(function (v) {
                    return [v, y.styles[v] || {}];
                  }),
                ),
                attributes: Xe(
                  h.map(function (v) {
                    return [v, y.attributes[v]];
                  }),
                ),
              });
            });
          },
          requires: ["computeStyles"],
        };
      }, []),
      u = M.useMemo(
        function () {
          var d = {
            onFirstUpdate: o.onFirstUpdate,
            placement: o.placement,
            strategy: o.strategy,
            modifiers: [].concat(o.modifiers, [
              c,
              { name: "applyStyles", enabled: !1 },
            ]),
          };
          return kr(a.current, d) ? a.current || d : ((a.current = d), d);
        },
        [o.onFirstUpdate, o.placement, o.strategy, o.modifiers, c],
      ),
      l = M.useRef();
    return (
      Ge(
        function () {
          l.current && l.current.setOptions(u);
        },
        [u],
      ),
      Ge(
        function () {
          if (!(t == null || r == null)) {
            var d = n.createPopper || Mr,
              p = d(t, r, u);
            return (
              (l.current = p),
              function () {
                (p.destroy(), (l.current = null));
              }
            );
          }
        },
        [t, r, n.createPopper],
      ),
      {
        state: l.current ? l.current.state : null,
        styles: f.styles,
        attributes: f.attributes,
        update: l.current ? l.current.update : null,
        forceUpdate: l.current ? l.current.forceUpdate : null,
      }
    );
  };
const at = (e, t) => ({
    getBoundingClientRect() {
      return { top: e, left: t, width: 1, height: 1 };
    },
  }),
  ie = 10,
  Fr = (e, t = 1) => ({
    name: "overlapIfOverflowing",
    phase: "main",
    enabled: !0,
    requires: ["preventOverflow", "offset"],
    fn({ state: r }) {
      const n = re(r),
        { popperOffsets: a, preventOverflow: o } = r.modifiersData,
        s = e.innerHeight;
      return (
        a &&
          (t < 1 && ((n.bottom -= s / t - s), (n.top -= s / t - s)),
          o && n.left + o.x > 0 && (a.x += n.left - ie),
          o && n.right + o.x > 0 && (a.x -= n.right + ie),
          o && n.top + o.y > 0 && (a.y += n.top - ie),
          o && n.bottom + o.y > 0 && (a.y -= n.bottom + ie)),
        r
      );
    },
  }),
  Gr = ({
    top: e,
    left: t,
    onClose: r,
    placement: n = "right-start",
    nonblocking: a,
    children: o,
  }) => {
    const s = M.useContext(Ot),
      { window: f, zoomFactor: i, portalRoot: c, screenMeasurer: u } = s,
      l = u?.clientWidth ?? 0,
      d = !isFinite(i) || i === 0 ? (l > 0 ? f.innerWidth / l : 1) : i,
      p = e / d,
      y = t / d,
      [h, v] = M.useState(at(p, y)),
      [x, O] = M.useState(null);
    (M.useEffect(() => v(at(p, y)), [p, y]),
      M.useEffect(
        () => (
          Ye(() => {
            s.popoverOpen = !0;
          }),
          () => {
            Ye(() => {
              s.popoverOpen = !1;
            });
          }
        ),
        [s],
      ));
    const E = M.useMemo(() => Fr(f, d), [f, d]),
      m = [{ name: "preventOverflow", options: { padding: ie } }, E],
      { styles: g, attributes: w } = Lr(h, x, { placement: n, modifiers: m });
    return (
      Et("esc", () => r(), "popover-esc"),
      At.createPortal(
        ze.jsx("div", {
          className: Pt("portal", { nonblocking: a }),
          onClick: r,
          onContextMenu: r,
          children: ze.jsx("div", {
            ref: (b) => O(b),
            style: g.popper,
            ...w.popper,
            children: Pe.Children.map(o, (b) =>
              Pe.isValidElement(b) && typeof b.type != "string"
                ? Pe.cloneElement(b, { closeMenu: r })
                : b,
            ),
          }),
        }),
        c,
      )
    );
  };
export { Gr as default };
//# sourceMappingURL=Popover-4t578wfD.js.map
