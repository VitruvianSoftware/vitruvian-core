const Ur = Symbol("Comlink.proxy"),
  st = Symbol("Comlink.endpoint"),
  dt = Symbol("Comlink.releaseProxy"),
  _r = Symbol("Comlink.finalizer"),
  or = Symbol("Comlink.thrown"),
  qr = (p) => (typeof p == "object" && p !== null) || typeof p == "function",
  _t = {
    canHandle: (p) => qr(p) && p[Ur],
    serialize(p) {
      const { port1: L, port2: Y } = new MessageChannel();
      return (Rr(p, L), [Y, [Y]]);
    },
    deserialize(p) {
      return (p.start(), gt(p));
    },
  },
  ct = {
    canHandle: (p) => qr(p) && or in p,
    serialize({ value: p }) {
      let L;
      return (
        p instanceof Error
          ? (L = {
              isError: !0,
              value: { message: p.message, name: p.name, stack: p.stack },
            })
          : (L = { isError: !1, value: p }),
        [L, []]
      );
    },
    deserialize(p) {
      throw p.isError
        ? Object.assign(new Error(p.value.message), p.value)
        : p.value;
    },
  },
  Qr = new Map([
    ["proxy", _t],
    ["throw", ct],
  ]);
function vt(p, L) {
  for (const Y of p)
    if (L === Y || Y === "*" || (Y instanceof RegExp && Y.test(L))) return !0;
  return !1;
}
function Rr(p, L = globalThis, Y = ["*"]) {
  (L.addEventListener("message", function P(E) {
    if (!E || !E.data) return;
    if (!vt(Y, E.origin)) {
      console.warn(`Invalid origin '${E.origin}' for comlink proxy`);
      return;
    }
    const { id: G, type: i, path: r } = Object.assign({ path: [] }, E.data),
      t = (E.data.argumentList || []).map(Ue);
    let w;
    try {
      const d = r.slice(0, -1).reduce((l, _) => l[_], p),
        u = r.reduce((l, _) => l[_], p);
      switch (i) {
        case "GET":
          w = u;
          break;
        case "SET":
          ((d[r.slice(-1)[0]] = Ue(E.data.value)), (w = !0));
          break;
        case "APPLY":
          w = u.apply(d, t);
          break;
        case "CONSTRUCT":
          {
            const l = new u(...t);
            w = Et(l);
          }
          break;
        case "ENDPOINT":
          {
            const { port1: l, port2: _ } = new MessageChannel();
            (Rr(p, _), (w = xt(l, [l])));
          }
          break;
        case "RELEASE":
          w = void 0;
          break;
        default:
          return;
      }
    } catch (d) {
      w = { value: d, [or]: 0 };
    }
    Promise.resolve(w)
      .catch((d) => ({ value: d, [or]: 0 }))
      .then((d) => {
        const [u, l] = dr(d);
        (L.postMessage(Object.assign(Object.assign({}, u), { id: G }), l),
          i === "RELEASE" &&
            (L.removeEventListener("message", P),
            Fr(L),
            _r in p && typeof p[_r] == "function" && p[_r]()));
      })
      .catch((d) => {
        const [u, l] = dr({
          value: new TypeError("Unserializable return value"),
          [or]: 0,
        });
        L.postMessage(Object.assign(Object.assign({}, u), { id: G }), l);
      });
  }),
    L.start && L.start());
}
function wt(p) {
  return p.constructor.name === "MessagePort";
}
function Fr(p) {
  wt(p) && p.close();
}
function gt(p, L) {
  const Y = new Map();
  return (
    p.addEventListener("message", function (E) {
      const { data: G } = E;
      if (!G || !G.id) return;
      const i = Y.get(G.id);
      if (i)
        try {
          i(G);
        } finally {
          Y.delete(G.id);
        }
    }),
    Dr(p, Y, [], L)
  );
}
function lr(p) {
  if (p) throw new Error("Proxy has been released and is not useable");
}
function et(p) {
  return ar(p, new Map(), { type: "RELEASE" }).then(() => {
    Fr(p);
  });
}
const ur = new WeakMap(),
  sr =
    "FinalizationRegistry" in globalThis &&
    new FinalizationRegistry((p) => {
      const L = (ur.get(p) || 0) - 1;
      (ur.set(p, L), L === 0 && et(p));
    });
function bt(p, L) {
  const Y = (ur.get(L) || 0) + 1;
  (ur.set(L, Y), sr && sr.register(p, L, p));
}
function pt(p) {
  sr && sr.unregister(p);
}
function Dr(p, L, Y = [], P = function () {}) {
  let E = !1;
  const G = new Proxy(P, {
    get(i, r) {
      if ((lr(E), r === dt))
        return () => {
          (pt(G), et(p), L.clear(), (E = !0));
        };
      if (r === "then") {
        if (Y.length === 0) return { then: () => G };
        const t = ar(p, L, {
          type: "GET",
          path: Y.map((w) => w.toString()),
        }).then(Ue);
        return t.then.bind(t);
      }
      return Dr(p, L, [...Y, r]);
    },
    set(i, r, t) {
      lr(E);
      const [w, d] = dr(t);
      return ar(
        p,
        L,
        { type: "SET", path: [...Y, r].map((u) => u.toString()), value: w },
        d,
      ).then(Ue);
    },
    apply(i, r, t) {
      lr(E);
      const w = Y[Y.length - 1];
      if (w === st) return ar(p, L, { type: "ENDPOINT" }).then(Ue);
      if (w === "bind") return Dr(p, L, Y.slice(0, -1));
      const [d, u] = Nr(t);
      return ar(
        p,
        L,
        { type: "APPLY", path: Y.map((l) => l.toString()), argumentList: d },
        u,
      ).then(Ue);
    },
    construct(i, r) {
      lr(E);
      const [t, w] = Nr(r);
      return ar(
        p,
        L,
        {
          type: "CONSTRUCT",
          path: Y.map((d) => d.toString()),
          argumentList: t,
        },
        w,
      ).then(Ue);
    },
  });
  return (bt(G, p), G);
}
function kt(p) {
  return Array.prototype.concat.apply([], p);
}
function Nr(p) {
  const L = p.map(dr);
  return [L.map((Y) => Y[0]), kt(L.map((Y) => Y[1]))];
}
const rt = new WeakMap();
function xt(p, L) {
  return (rt.set(p, L), p);
}
function Et(p) {
  return Object.assign(p, { [Ur]: !0 });
}
function dr(p) {
  for (const [L, Y] of Qr)
    if (Y.canHandle(p)) {
      const [P, E] = Y.serialize(p);
      return [{ type: "HANDLER", name: L, value: P }, E];
    }
  return [{ type: "RAW", value: p }, rt.get(p) || []];
}
function Ue(p) {
  switch (p.type) {
    case "HANDLER":
      return Qr.get(p.name).deserialize(p.value);
    case "RAW":
      return p.value;
  }
}
function ar(p, L, Y, P) {
  return new Promise((E) => {
    const G = yt();
    (L.set(G, E),
      p.start && p.start(),
      p.postMessage(Object.assign({ id: G }, Y), P));
  });
}
function yt() {
  return new Array(4)
    .fill(0)
    .map(() => Math.floor(Math.random() * Number.MAX_SAFE_INTEGER).toString(16))
    .join("-");
}
function St(p) {
  return p && p.__esModule && Object.prototype.hasOwnProperty.call(p, "default")
    ? p.default
    : p;
}
function At(p) {
  return p && p.__esModule && Object.prototype.hasOwnProperty.call(p, "default")
    ? p.default
    : p;
}
var tt = { exports: {} },
  xe = (tt.exports = {}),
  Ge,
  Ie;
function mr() {
  throw new Error("setTimeout has not been defined");
}
function zr() {
  throw new Error("clearTimeout has not been defined");
}
(function () {
  try {
    typeof setTimeout == "function" ? (Ge = setTimeout) : (Ge = mr);
  } catch {
    Ge = mr;
  }
  try {
    typeof clearTimeout == "function" ? (Ie = clearTimeout) : (Ie = zr);
  } catch {
    Ie = zr;
  }
})();
function at(p) {
  if (Ge === setTimeout) return setTimeout(p, 0);
  if ((Ge === mr || !Ge) && setTimeout)
    return ((Ge = setTimeout), setTimeout(p, 0));
  try {
    return Ge(p, 0);
  } catch {
    try {
      return Ge.call(null, p, 0);
    } catch {
      return Ge.call(this, p, 0);
    }
  }
}
function Dt(p) {
  if (Ie === clearTimeout) return clearTimeout(p);
  if ((Ie === zr || !Ie) && clearTimeout)
    return ((Ie = clearTimeout), clearTimeout(p));
  try {
    return Ie(p);
  } catch {
    try {
      return Ie.call(null, p);
    } catch {
      return Ie.call(this, p);
    }
  }
}
var Je = [],
  ir = !1,
  qe,
  hr = -1;
function mt() {
  !ir ||
    !qe ||
    ((ir = !1),
    qe.length ? (Je = qe.concat(Je)) : (hr = -1),
    Je.length && it());
}
function it() {
  if (!ir) {
    var p = at(mt);
    ir = !0;
    for (var L = Je.length; L;) {
      for (qe = Je, Je = []; ++hr < L;) qe && qe[hr].run();
      ((hr = -1), (L = Je.length));
    }
    ((qe = null), (ir = !1), Dt(p));
  }
}
xe.nextTick = function (p) {
  var L = new Array(arguments.length - 1);
  if (arguments.length > 1)
    for (var Y = 1; Y < arguments.length; Y++) L[Y - 1] = arguments[Y];
  (Je.push(new nt(p, L)), Je.length === 1 && !ir && at(it));
};
function nt(p, L) {
  ((this.fun = p), (this.array = L));
}
nt.prototype.run = function () {
  this.fun.apply(null, this.array);
};
xe.title = "browser";
xe.browser = !0;
xe.env = {};
xe.argv = [];
xe.version = "";
xe.versions = {};
function Ke() {}
xe.on = Ke;
xe.addListener = Ke;
xe.once = Ke;
xe.off = Ke;
xe.removeListener = Ke;
xe.removeAllListeners = Ke;
xe.emit = Ke;
xe.prependListener = Ke;
xe.prependOnceListener = Ke;
xe.listeners = function (p) {
  return [];
};
xe.binding = function (p) {
  throw new Error("process.binding is not supported");
};
xe.cwd = function () {
  return "/";
};
xe.chdir = function (p) {
  throw new Error("process.chdir is not supported");
};
xe.umask = function () {
  return 0;
};
var zt = tt.exports;
const Rt = At(zt);
function Ot(p) {
  throw new Error(
    'Could not dynamically require "' +
      p +
      '". Please configure the dynamicRequireTargets or/and ignoreDynamicRequires option of @rollup/plugin-commonjs appropriately for this require call to work.',
  );
}
var cr = { exports: {} },
  vr = {},
  Mr;
function $e() {
  return (
    Mr ||
      ((Mr = 1),
      (function (p) {
        var L =
          typeof Uint8Array < "u" &&
          typeof Uint16Array < "u" &&
          typeof Int32Array < "u";
        function Y(G, i) {
          return Object.prototype.hasOwnProperty.call(G, i);
        }
        ((p.assign = function (G) {
          for (var i = Array.prototype.slice.call(arguments, 1); i.length;) {
            var r = i.shift();
            if (r) {
              if (typeof r != "object")
                throw new TypeError(r + "must be non-object");
              for (var t in r) Y(r, t) && (G[t] = r[t]);
            }
          }
          return G;
        }),
          (p.shrinkBuf = function (G, i) {
            return G.length === i
              ? G
              : G.subarray
                ? G.subarray(0, i)
                : ((G.length = i), G);
          }));
        var P = {
            arraySet: function (G, i, r, t, w) {
              if (i.subarray && G.subarray) {
                G.set(i.subarray(r, r + t), w);
                return;
              }
              for (var d = 0; d < t; d++) G[w + d] = i[r + d];
            },
            flattenChunks: function (G) {
              var i, r, t, w, d, u;
              for (t = 0, i = 0, r = G.length; i < r; i++) t += G[i].length;
              for (
                u = new Uint8Array(t), w = 0, i = 0, r = G.length;
                i < r;
                i++
              )
                ((d = G[i]), u.set(d, w), (w += d.length));
              return u;
            },
          },
          E = {
            arraySet: function (G, i, r, t, w) {
              for (var d = 0; d < t; d++) G[w + d] = i[r + d];
            },
            flattenChunks: function (G) {
              return [].concat.apply([], G);
            },
          };
        ((p.setTyped = function (G) {
          G
            ? ((p.Buf8 = Uint8Array),
              (p.Buf16 = Uint16Array),
              (p.Buf32 = Int32Array),
              p.assign(p, P))
            : ((p.Buf8 = Array),
              (p.Buf16 = Array),
              (p.Buf32 = Array),
              p.assign(p, E));
        }),
          p.setTyped(L));
      })(vr)),
    vr
  );
}
var rr = {},
  Le = {},
  Xe = {},
  Cr;
function Bt() {
  if (Cr) return Xe;
  Cr = 1;
  var p = $e(),
    L = 4,
    Y = 0,
    P = 1,
    E = 2;
  function G(o) {
    for (var J = o.length; --J >= 0;) o[J] = 0;
  }
  var i = 0,
    r = 1,
    t = 2,
    w = 3,
    d = 258,
    u = 29,
    l = 256,
    _ = l + 1 + u,
    y = 30,
    s = 19,
    c = 2 * _ + 1,
    v = 15,
    h = 16,
    n = 7,
    g = 256,
    b = 16,
    k = 17,
    S = 18,
    D = [
      0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5,
      5, 5, 5, 0,
    ],
    B = [
      0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10,
      11, 11, 12, 12, 13, 13,
    ],
    m = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 3, 7],
    z = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15],
    T = 512,
    C = new Array((_ + 2) * 2);
  G(C);
  var I = new Array(y * 2);
  G(I);
  var j = new Array(T);
  G(j);
  var V = new Array(d - w + 1);
  G(V);
  var $ = new Array(u);
  G($);
  var Z = new Array(y);
  G(Z);
  function H(o, J, W, ee, A) {
    ((this.static_tree = o),
      (this.extra_bits = J),
      (this.extra_base = W),
      (this.elems = ee),
      (this.max_length = A),
      (this.has_stree = o && o.length));
  }
  var ie, X, re;
  function U(o, J) {
    ((this.dyn_tree = o), (this.max_code = 0), (this.stat_desc = J));
  }
  function _e(o) {
    return o < 256 ? j[o] : j[256 + (o >>> 7)];
  }
  function fe(o, J) {
    ((o.pending_buf[o.pending++] = J & 255),
      (o.pending_buf[o.pending++] = (J >>> 8) & 255));
  }
  function le(o, J, W) {
    o.bi_valid > h - W
      ? ((o.bi_buf |= (J << o.bi_valid) & 65535),
        fe(o, o.bi_buf),
        (o.bi_buf = J >> (h - o.bi_valid)),
        (o.bi_valid += W - h))
      : ((o.bi_buf |= (J << o.bi_valid) & 65535), (o.bi_valid += W));
  }
  function oe(o, J, W) {
    le(o, W[J * 2], W[J * 2 + 1]);
  }
  function se(o, J) {
    var W = 0;
    do ((W |= o & 1), (o >>>= 1), (W <<= 1));
    while (--J > 0);
    return W >>> 1;
  }
  function be(o) {
    o.bi_valid === 16
      ? (fe(o, o.bi_buf), (o.bi_buf = 0), (o.bi_valid = 0))
      : o.bi_valid >= 8 &&
        ((o.pending_buf[o.pending++] = o.bi_buf & 255),
        (o.bi_buf >>= 8),
        (o.bi_valid -= 8));
  }
  function Re(o, J) {
    var W = J.dyn_tree,
      ee = J.max_code,
      A = J.stat_desc.static_tree,
      M = J.stat_desc.has_stree,
      a = J.stat_desc.extra_bits,
      K = J.stat_desc.extra_base,
      ne = J.stat_desc.max_length,
      e,
      O,
      N,
      f,
      x,
      R,
      ae = 0;
    for (f = 0; f <= v; f++) o.bl_count[f] = 0;
    for (W[o.heap[o.heap_max] * 2 + 1] = 0, e = o.heap_max + 1; e < c; e++)
      ((O = o.heap[e]),
        (f = W[W[O * 2 + 1] * 2 + 1] + 1),
        f > ne && ((f = ne), ae++),
        (W[O * 2 + 1] = f),
        !(O > ee) &&
          (o.bl_count[f]++,
          (x = 0),
          O >= K && (x = a[O - K]),
          (R = W[O * 2]),
          (o.opt_len += R * (f + x)),
          M && (o.static_len += R * (A[O * 2 + 1] + x))));
    if (ae !== 0) {
      do {
        for (f = ne - 1; o.bl_count[f] === 0;) f--;
        (o.bl_count[f]--,
          (o.bl_count[f + 1] += 2),
          o.bl_count[ne]--,
          (ae -= 2));
      } while (ae > 0);
      for (f = ne; f !== 0; f--)
        for (O = o.bl_count[f]; O !== 0;)
          ((N = o.heap[--e]),
            !(N > ee) &&
              (W[N * 2 + 1] !== f &&
                ((o.opt_len += (f - W[N * 2 + 1]) * W[N * 2]),
                (W[N * 2 + 1] = f)),
              O--));
    }
  }
  function ke(o, J, W) {
    var ee = new Array(v + 1),
      A = 0,
      M,
      a;
    for (M = 1; M <= v; M++) ee[M] = A = (A + W[M - 1]) << 1;
    for (a = 0; a <= J; a++) {
      var K = o[a * 2 + 1];
      K !== 0 && (o[a * 2] = se(ee[K]++, K));
    }
  }
  function ve() {
    var o,
      J,
      W,
      ee,
      A,
      M = new Array(v + 1);
    for (W = 0, ee = 0; ee < u - 1; ee++)
      for ($[ee] = W, o = 0; o < 1 << D[ee]; o++) V[W++] = ee;
    for (V[W - 1] = ee, A = 0, ee = 0; ee < 16; ee++)
      for (Z[ee] = A, o = 0; o < 1 << B[ee]; o++) j[A++] = ee;
    for (A >>= 7; ee < y; ee++)
      for (Z[ee] = A << 7, o = 0; o < 1 << (B[ee] - 7); o++) j[256 + A++] = ee;
    for (J = 0; J <= v; J++) M[J] = 0;
    for (o = 0; o <= 143;) ((C[o * 2 + 1] = 8), o++, M[8]++);
    for (; o <= 255;) ((C[o * 2 + 1] = 9), o++, M[9]++);
    for (; o <= 279;) ((C[o * 2 + 1] = 7), o++, M[7]++);
    for (; o <= 287;) ((C[o * 2 + 1] = 8), o++, M[8]++);
    for (ke(C, _ + 1, M), o = 0; o < y; o++)
      ((I[o * 2 + 1] = 5), (I[o * 2] = se(o, 5)));
    ((ie = new H(C, D, l + 1, _, v)),
      (X = new H(I, B, 0, y, v)),
      (re = new H(new Array(0), m, 0, s, n)));
  }
  function Se(o) {
    var J;
    for (J = 0; J < _; J++) o.dyn_ltree[J * 2] = 0;
    for (J = 0; J < y; J++) o.dyn_dtree[J * 2] = 0;
    for (J = 0; J < s; J++) o.bl_tree[J * 2] = 0;
    ((o.dyn_ltree[g * 2] = 1),
      (o.opt_len = o.static_len = 0),
      (o.last_lit = o.matches = 0));
  }
  function Pe(o) {
    (o.bi_valid > 8
      ? fe(o, o.bi_buf)
      : o.bi_valid > 0 && (o.pending_buf[o.pending++] = o.bi_buf),
      (o.bi_buf = 0),
      (o.bi_valid = 0));
  }
  function Oe(o, J, W, ee) {
    (Pe(o),
      fe(o, W),
      fe(o, ~W),
      p.arraySet(o.pending_buf, o.window, J, W, o.pending),
      (o.pending += W));
  }
  function he(o, J, W, ee) {
    var A = J * 2,
      M = W * 2;
    return o[A] < o[M] || (o[A] === o[M] && ee[J] <= ee[W]);
  }
  function Q(o, J, W) {
    for (
      var ee = o.heap[W], A = W << 1;
      A <= o.heap_len &&
      (A < o.heap_len && he(J, o.heap[A + 1], o.heap[A], o.depth) && A++,
      !he(J, ee, o.heap[A], o.depth));
    )
      ((o.heap[W] = o.heap[A]), (W = A), (A <<= 1));
    o.heap[W] = ee;
  }
  function te(o, J, W) {
    var ee,
      A,
      M = 0,
      a,
      K;
    if (o.last_lit !== 0)
      do
        ((ee =
          (o.pending_buf[o.d_buf + M * 2] << 8) |
          o.pending_buf[o.d_buf + M * 2 + 1]),
          (A = o.pending_buf[o.l_buf + M]),
          M++,
          ee === 0
            ? oe(o, A, J)
            : ((a = V[A]),
              oe(o, a + l + 1, J),
              (K = D[a]),
              K !== 0 && ((A -= $[a]), le(o, A, K)),
              ee--,
              (a = _e(ee)),
              oe(o, a, W),
              (K = B[a]),
              K !== 0 && ((ee -= Z[a]), le(o, ee, K))));
      while (M < o.last_lit);
    oe(o, g, J);
  }
  function ue(o, J) {
    var W = J.dyn_tree,
      ee = J.stat_desc.static_tree,
      A = J.stat_desc.has_stree,
      M = J.stat_desc.elems,
      a,
      K,
      ne = -1,
      e;
    for (o.heap_len = 0, o.heap_max = c, a = 0; a < M; a++)
      W[a * 2] !== 0
        ? ((o.heap[++o.heap_len] = ne = a), (o.depth[a] = 0))
        : (W[a * 2 + 1] = 0);
    for (; o.heap_len < 2;)
      ((e = o.heap[++o.heap_len] = ne < 2 ? ++ne : 0),
        (W[e * 2] = 1),
        (o.depth[e] = 0),
        o.opt_len--,
        A && (o.static_len -= ee[e * 2 + 1]));
    for (J.max_code = ne, a = o.heap_len >> 1; a >= 1; a--) Q(o, W, a);
    e = M;
    do
      ((a = o.heap[1]),
        (o.heap[1] = o.heap[o.heap_len--]),
        Q(o, W, 1),
        (K = o.heap[1]),
        (o.heap[--o.heap_max] = a),
        (o.heap[--o.heap_max] = K),
        (W[e * 2] = W[a * 2] + W[K * 2]),
        (o.depth[e] = (o.depth[a] >= o.depth[K] ? o.depth[a] : o.depth[K]) + 1),
        (W[a * 2 + 1] = W[K * 2 + 1] = e),
        (o.heap[1] = e++),
        Q(o, W, 1));
    while (o.heap_len >= 2);
    ((o.heap[--o.heap_max] = o.heap[1]), Re(o, J), ke(W, ne, o.bl_count));
  }
  function we(o, J, W) {
    var ee,
      A = -1,
      M,
      a = J[1],
      K = 0,
      ne = 7,
      e = 4;
    for (
      a === 0 && ((ne = 138), (e = 3)), J[(W + 1) * 2 + 1] = 65535, ee = 0;
      ee <= W;
      ee++
    )
      ((M = a),
        (a = J[(ee + 1) * 2 + 1]),
        !(++K < ne && M === a) &&
          (K < e
            ? (o.bl_tree[M * 2] += K)
            : M !== 0
              ? (M !== A && o.bl_tree[M * 2]++, o.bl_tree[b * 2]++)
              : K <= 10
                ? o.bl_tree[k * 2]++
                : o.bl_tree[S * 2]++,
          (K = 0),
          (A = M),
          a === 0
            ? ((ne = 138), (e = 3))
            : M === a
              ? ((ne = 6), (e = 3))
              : ((ne = 7), (e = 4))));
  }
  function ge(o, J, W) {
    var ee,
      A = -1,
      M,
      a = J[1],
      K = 0,
      ne = 7,
      e = 4;
    for (a === 0 && ((ne = 138), (e = 3)), ee = 0; ee <= W; ee++)
      if (((M = a), (a = J[(ee + 1) * 2 + 1]), !(++K < ne && M === a))) {
        if (K < e)
          do oe(o, M, o.bl_tree);
          while (--K !== 0);
        else
          M !== 0
            ? (M !== A && (oe(o, M, o.bl_tree), K--),
              oe(o, b, o.bl_tree),
              le(o, K - 3, 2))
            : K <= 10
              ? (oe(o, k, o.bl_tree), le(o, K - 3, 3))
              : (oe(o, S, o.bl_tree), le(o, K - 11, 7));
        ((K = 0),
          (A = M),
          a === 0
            ? ((ne = 138), (e = 3))
            : M === a
              ? ((ne = 6), (e = 3))
              : ((ne = 7), (e = 4)));
      }
  }
  function De(o) {
    var J;
    for (
      we(o, o.dyn_ltree, o.l_desc.max_code),
        we(o, o.dyn_dtree, o.d_desc.max_code),
        ue(o, o.bl_desc),
        J = s - 1;
      J >= 3 && o.bl_tree[z[J] * 2 + 1] === 0;
      J--
    );
    return ((o.opt_len += 3 * (J + 1) + 5 + 5 + 4), J);
  }
  function Qe(o, J, W, ee) {
    var A;
    for (
      le(o, J - 257, 5), le(o, W - 1, 5), le(o, ee - 4, 4), A = 0;
      A < ee;
      A++
    )
      le(o, o.bl_tree[z[A] * 2 + 1], 3);
    (ge(o, o.dyn_ltree, J - 1), ge(o, o.dyn_dtree, W - 1));
  }
  function Ye(o) {
    var J = 4093624447,
      W;
    for (W = 0; W <= 31; W++, J >>>= 1)
      if (J & 1 && o.dyn_ltree[W * 2] !== 0) return Y;
    if (o.dyn_ltree[18] !== 0 || o.dyn_ltree[20] !== 0 || o.dyn_ltree[26] !== 0)
      return P;
    for (W = 32; W < l; W++) if (o.dyn_ltree[W * 2] !== 0) return P;
    return Y;
  }
  var Ce = !1;
  function Fe(o) {
    (Ce || (ve(), (Ce = !0)),
      (o.l_desc = new U(o.dyn_ltree, ie)),
      (o.d_desc = new U(o.dyn_dtree, X)),
      (o.bl_desc = new U(o.bl_tree, re)),
      (o.bi_buf = 0),
      (o.bi_valid = 0),
      Se(o));
  }
  function We(o, J, W, ee) {
    (le(o, (i << 1) + (ee ? 1 : 0), 3), Oe(o, J, W));
  }
  function me(o) {
    (le(o, r << 1, 3), oe(o, g, C), be(o));
  }
  function Ze(o, J, W, ee) {
    var A,
      M,
      a = 0;
    (o.level > 0
      ? (o.strm.data_type === E && (o.strm.data_type = Ye(o)),
        ue(o, o.l_desc),
        ue(o, o.d_desc),
        (a = De(o)),
        (A = (o.opt_len + 3 + 7) >>> 3),
        (M = (o.static_len + 3 + 7) >>> 3),
        M <= A && (A = M))
      : (A = M = W + 5),
      W + 4 <= A && J !== -1
        ? We(o, J, W, ee)
        : o.strategy === L || M === A
          ? (le(o, (r << 1) + (ee ? 1 : 0), 3), te(o, C, I))
          : (le(o, (t << 1) + (ee ? 1 : 0), 3),
            Qe(o, o.l_desc.max_code + 1, o.d_desc.max_code + 1, a + 1),
            te(o, o.dyn_ltree, o.dyn_dtree)),
      Se(o),
      ee && Pe(o));
  }
  function er(o, J, W) {
    return (
      (o.pending_buf[o.d_buf + o.last_lit * 2] = (J >>> 8) & 255),
      (o.pending_buf[o.d_buf + o.last_lit * 2 + 1] = J & 255),
      (o.pending_buf[o.l_buf + o.last_lit] = W & 255),
      o.last_lit++,
      J === 0
        ? o.dyn_ltree[W * 2]++
        : (o.matches++,
          J--,
          o.dyn_ltree[(V[W] + l + 1) * 2]++,
          o.dyn_dtree[_e(J) * 2]++),
      o.last_lit === o.lit_bufsize - 1
    );
  }
  return (
    (Xe._tr_init = Fe),
    (Xe._tr_stored_block = We),
    (Xe._tr_flush_block = Ze),
    (Xe._tr_tally = er),
    (Xe._tr_align = me),
    Xe
  );
}
var wr, Lr;
function ft() {
  if (Lr) return wr;
  Lr = 1;
  function p(L, Y, P, E) {
    for (
      var G = (L & 65535) | 0, i = ((L >>> 16) & 65535) | 0, r = 0;
      P !== 0;
    ) {
      ((r = P > 2e3 ? 2e3 : P), (P -= r));
      do ((G = (G + Y[E++]) | 0), (i = (i + G) | 0));
      while (--r);
      ((G %= 65521), (i %= 65521));
    }
    return G | (i << 16) | 0;
  }
  return ((wr = p), wr);
}
var gr, Pr;
function lt() {
  if (Pr) return gr;
  Pr = 1;
  function p() {
    for (var P, E = [], G = 0; G < 256; G++) {
      P = G;
      for (var i = 0; i < 8; i++) P = P & 1 ? 3988292384 ^ (P >>> 1) : P >>> 1;
      E[G] = P;
    }
    return E;
  }
  var L = p();
  function Y(P, E, G, i) {
    var r = L,
      t = i + G;
    P ^= -1;
    for (var w = i; w < t; w++) P = (P >>> 8) ^ r[(P ^ E[w]) & 255];
    return P ^ -1;
  }
  return ((gr = Y), gr);
}
var br, Zr;
function Or() {
  return (
    Zr ||
      ((Zr = 1),
      (br = {
        2: "need dictionary",
        1: "stream end",
        0: "",
        "-1": "file error",
        "-2": "stream error",
        "-3": "data error",
        "-4": "insufficient memory",
        "-5": "buffer error",
        "-6": "incompatible version",
      })),
    br
  );
}
var Hr;
function Nt() {
  if (Hr) return Le;
  Hr = 1;
  var p = $e(),
    L = Bt(),
    Y = ft(),
    P = lt(),
    E = Or(),
    G = 0,
    i = 1,
    r = 3,
    t = 4,
    w = 5,
    d = 0,
    u = 1,
    l = -2,
    _ = -3,
    y = -5,
    s = -1,
    c = 1,
    v = 2,
    h = 3,
    n = 4,
    g = 0,
    b = 2,
    k = 8,
    S = 9,
    D = 15,
    B = 8,
    m = 29,
    z = 256,
    T = z + 1 + m,
    C = 30,
    I = 19,
    j = 2 * T + 1,
    V = 15,
    $ = 3,
    Z = 258,
    H = Z + $ + 1,
    ie = 32,
    X = 42,
    re = 69,
    U = 73,
    _e = 91,
    fe = 103,
    le = 113,
    oe = 666,
    se = 1,
    be = 2,
    Re = 3,
    ke = 4,
    ve = 3;
  function Se(e, O) {
    return ((e.msg = E[O]), O);
  }
  function Pe(e) {
    return (e << 1) - (e > 4 ? 9 : 0);
  }
  function Oe(e) {
    for (var O = e.length; --O >= 0;) e[O] = 0;
  }
  function he(e) {
    var O = e.state,
      N = O.pending;
    (N > e.avail_out && (N = e.avail_out),
      N !== 0 &&
        (p.arraySet(e.output, O.pending_buf, O.pending_out, N, e.next_out),
        (e.next_out += N),
        (O.pending_out += N),
        (e.total_out += N),
        (e.avail_out -= N),
        (O.pending -= N),
        O.pending === 0 && (O.pending_out = 0)));
  }
  function Q(e, O) {
    (L._tr_flush_block(
      e,
      e.block_start >= 0 ? e.block_start : -1,
      e.strstart - e.block_start,
      O,
    ),
      (e.block_start = e.strstart),
      he(e.strm));
  }
  function te(e, O) {
    e.pending_buf[e.pending++] = O;
  }
  function ue(e, O) {
    ((e.pending_buf[e.pending++] = (O >>> 8) & 255),
      (e.pending_buf[e.pending++] = O & 255));
  }
  function we(e, O, N, f) {
    var x = e.avail_in;
    return (
      x > f && (x = f),
      x === 0
        ? 0
        : ((e.avail_in -= x),
          p.arraySet(O, e.input, e.next_in, x, N),
          e.state.wrap === 1
            ? (e.adler = Y(e.adler, O, x, N))
            : e.state.wrap === 2 && (e.adler = P(e.adler, O, x, N)),
          (e.next_in += x),
          (e.total_in += x),
          x)
    );
  }
  function ge(e, O) {
    var N = e.max_chain_length,
      f = e.strstart,
      x,
      R,
      ae = e.prev_length,
      q = e.nice_match,
      F = e.strstart > e.w_size - H ? e.strstart - (e.w_size - H) : 0,
      de = e.window,
      Te = e.w_mask,
      pe = e.prev,
      ce = e.strstart + Z,
      ye = de[f + ae - 1],
      ze = de[f + ae];
    (e.prev_length >= e.good_match && (N >>= 2),
      q > e.lookahead && (q = e.lookahead));
    do
      if (
        ((x = O),
        !(
          de[x + ae] !== ze ||
          de[x + ae - 1] !== ye ||
          de[x] !== de[f] ||
          de[++x] !== de[f + 1]
        ))
      ) {
        ((f += 2), x++);
        do;
        while (
          de[++f] === de[++x] &&
          de[++f] === de[++x] &&
          de[++f] === de[++x] &&
          de[++f] === de[++x] &&
          de[++f] === de[++x] &&
          de[++f] === de[++x] &&
          de[++f] === de[++x] &&
          de[++f] === de[++x] &&
          f < ce
        );
        if (((R = Z - (ce - f)), (f = ce - Z), R > ae)) {
          if (((e.match_start = O), (ae = R), R >= q)) break;
          ((ye = de[f + ae - 1]), (ze = de[f + ae]));
        }
      }
    while ((O = pe[O & Te]) > F && --N !== 0);
    return ae <= e.lookahead ? ae : e.lookahead;
  }
  function De(e) {
    var O = e.w_size,
      N,
      f,
      x,
      R,
      ae;
    do {
      if (
        ((R = e.window_size - e.lookahead - e.strstart),
        e.strstart >= O + (O - H))
      ) {
        (p.arraySet(e.window, e.window, O, O, 0),
          (e.match_start -= O),
          (e.strstart -= O),
          (e.block_start -= O),
          (f = e.hash_size),
          (N = f));
        do ((x = e.head[--N]), (e.head[N] = x >= O ? x - O : 0));
        while (--f);
        ((f = O), (N = f));
        do ((x = e.prev[--N]), (e.prev[N] = x >= O ? x - O : 0));
        while (--f);
        R += O;
      }
      if (e.strm.avail_in === 0) break;
      if (
        ((f = we(e.strm, e.window, e.strstart + e.lookahead, R)),
        (e.lookahead += f),
        e.lookahead + e.insert >= $)
      )
        for (
          ae = e.strstart - e.insert,
            e.ins_h = e.window[ae],
            e.ins_h =
              ((e.ins_h << e.hash_shift) ^ e.window[ae + 1]) & e.hash_mask;
          e.insert &&
          ((e.ins_h =
            ((e.ins_h << e.hash_shift) ^ e.window[ae + $ - 1]) & e.hash_mask),
          (e.prev[ae & e.w_mask] = e.head[e.ins_h]),
          (e.head[e.ins_h] = ae),
          ae++,
          e.insert--,
          !(e.lookahead + e.insert < $));
        );
    } while (e.lookahead < H && e.strm.avail_in !== 0);
  }
  function Qe(e, O) {
    var N = 65535;
    for (N > e.pending_buf_size - 5 && (N = e.pending_buf_size - 5); ;) {
      if (e.lookahead <= 1) {
        if ((De(e), e.lookahead === 0 && O === G)) return se;
        if (e.lookahead === 0) break;
      }
      ((e.strstart += e.lookahead), (e.lookahead = 0));
      var f = e.block_start + N;
      if (
        ((e.strstart === 0 || e.strstart >= f) &&
          ((e.lookahead = e.strstart - f),
          (e.strstart = f),
          Q(e, !1),
          e.strm.avail_out === 0)) ||
        (e.strstart - e.block_start >= e.w_size - H &&
          (Q(e, !1), e.strm.avail_out === 0))
      )
        return se;
    }
    return (
      (e.insert = 0),
      O === t
        ? (Q(e, !0), e.strm.avail_out === 0 ? Re : ke)
        : (e.strstart > e.block_start && (Q(e, !1), e.strm.avail_out === 0), se)
    );
  }
  function Ye(e, O) {
    for (var N, f; ;) {
      if (e.lookahead < H) {
        if ((De(e), e.lookahead < H && O === G)) return se;
        if (e.lookahead === 0) break;
      }
      if (
        ((N = 0),
        e.lookahead >= $ &&
          ((e.ins_h =
            ((e.ins_h << e.hash_shift) ^ e.window[e.strstart + $ - 1]) &
            e.hash_mask),
          (N = e.prev[e.strstart & e.w_mask] = e.head[e.ins_h]),
          (e.head[e.ins_h] = e.strstart)),
        N !== 0 &&
          e.strstart - N <= e.w_size - H &&
          (e.match_length = ge(e, N)),
        e.match_length >= $)
      )
        if (
          ((f = L._tr_tally(e, e.strstart - e.match_start, e.match_length - $)),
          (e.lookahead -= e.match_length),
          e.match_length <= e.max_lazy_match && e.lookahead >= $)
        ) {
          e.match_length--;
          do
            (e.strstart++,
              (e.ins_h =
                ((e.ins_h << e.hash_shift) ^ e.window[e.strstart + $ - 1]) &
                e.hash_mask),
              (N = e.prev[e.strstart & e.w_mask] = e.head[e.ins_h]),
              (e.head[e.ins_h] = e.strstart));
          while (--e.match_length !== 0);
          e.strstart++;
        } else
          ((e.strstart += e.match_length),
            (e.match_length = 0),
            (e.ins_h = e.window[e.strstart]),
            (e.ins_h =
              ((e.ins_h << e.hash_shift) ^ e.window[e.strstart + 1]) &
              e.hash_mask));
      else
        ((f = L._tr_tally(e, 0, e.window[e.strstart])),
          e.lookahead--,
          e.strstart++);
      if (f && (Q(e, !1), e.strm.avail_out === 0)) return se;
    }
    return (
      (e.insert = e.strstart < $ - 1 ? e.strstart : $ - 1),
      O === t
        ? (Q(e, !0), e.strm.avail_out === 0 ? Re : ke)
        : e.last_lit && (Q(e, !1), e.strm.avail_out === 0)
          ? se
          : be
    );
  }
  function Ce(e, O) {
    for (var N, f, x; ;) {
      if (e.lookahead < H) {
        if ((De(e), e.lookahead < H && O === G)) return se;
        if (e.lookahead === 0) break;
      }
      if (
        ((N = 0),
        e.lookahead >= $ &&
          ((e.ins_h =
            ((e.ins_h << e.hash_shift) ^ e.window[e.strstart + $ - 1]) &
            e.hash_mask),
          (N = e.prev[e.strstart & e.w_mask] = e.head[e.ins_h]),
          (e.head[e.ins_h] = e.strstart)),
        (e.prev_length = e.match_length),
        (e.prev_match = e.match_start),
        (e.match_length = $ - 1),
        N !== 0 &&
          e.prev_length < e.max_lazy_match &&
          e.strstart - N <= e.w_size - H &&
          ((e.match_length = ge(e, N)),
          e.match_length <= 5 &&
            (e.strategy === c ||
              (e.match_length === $ && e.strstart - e.match_start > 4096)) &&
            (e.match_length = $ - 1)),
        e.prev_length >= $ && e.match_length <= e.prev_length)
      ) {
        ((x = e.strstart + e.lookahead - $),
          (f = L._tr_tally(
            e,
            e.strstart - 1 - e.prev_match,
            e.prev_length - $,
          )),
          (e.lookahead -= e.prev_length - 1),
          (e.prev_length -= 2));
        do
          ++e.strstart <= x &&
            ((e.ins_h =
              ((e.ins_h << e.hash_shift) ^ e.window[e.strstart + $ - 1]) &
              e.hash_mask),
            (N = e.prev[e.strstart & e.w_mask] = e.head[e.ins_h]),
            (e.head[e.ins_h] = e.strstart));
        while (--e.prev_length !== 0);
        if (
          ((e.match_available = 0),
          (e.match_length = $ - 1),
          e.strstart++,
          f && (Q(e, !1), e.strm.avail_out === 0))
        )
          return se;
      } else if (e.match_available) {
        if (
          ((f = L._tr_tally(e, 0, e.window[e.strstart - 1])),
          f && Q(e, !1),
          e.strstart++,
          e.lookahead--,
          e.strm.avail_out === 0)
        )
          return se;
      } else ((e.match_available = 1), e.strstart++, e.lookahead--);
    }
    return (
      e.match_available &&
        ((f = L._tr_tally(e, 0, e.window[e.strstart - 1])),
        (e.match_available = 0)),
      (e.insert = e.strstart < $ - 1 ? e.strstart : $ - 1),
      O === t
        ? (Q(e, !0), e.strm.avail_out === 0 ? Re : ke)
        : e.last_lit && (Q(e, !1), e.strm.avail_out === 0)
          ? se
          : be
    );
  }
  function Fe(e, O) {
    for (var N, f, x, R, ae = e.window; ;) {
      if (e.lookahead <= Z) {
        if ((De(e), e.lookahead <= Z && O === G)) return se;
        if (e.lookahead === 0) break;
      }
      if (
        ((e.match_length = 0),
        e.lookahead >= $ &&
          e.strstart > 0 &&
          ((x = e.strstart - 1),
          (f = ae[x]),
          f === ae[++x] && f === ae[++x] && f === ae[++x]))
      ) {
        R = e.strstart + Z;
        do;
        while (
          f === ae[++x] &&
          f === ae[++x] &&
          f === ae[++x] &&
          f === ae[++x] &&
          f === ae[++x] &&
          f === ae[++x] &&
          f === ae[++x] &&
          f === ae[++x] &&
          x < R
        );
        ((e.match_length = Z - (R - x)),
          e.match_length > e.lookahead && (e.match_length = e.lookahead));
      }
      if (
        (e.match_length >= $
          ? ((N = L._tr_tally(e, 1, e.match_length - $)),
            (e.lookahead -= e.match_length),
            (e.strstart += e.match_length),
            (e.match_length = 0))
          : ((N = L._tr_tally(e, 0, e.window[e.strstart])),
            e.lookahead--,
            e.strstart++),
        N && (Q(e, !1), e.strm.avail_out === 0))
      )
        return se;
    }
    return (
      (e.insert = 0),
      O === t
        ? (Q(e, !0), e.strm.avail_out === 0 ? Re : ke)
        : e.last_lit && (Q(e, !1), e.strm.avail_out === 0)
          ? se
          : be
    );
  }
  function We(e, O) {
    for (var N; ;) {
      if (e.lookahead === 0 && (De(e), e.lookahead === 0)) {
        if (O === G) return se;
        break;
      }
      if (
        ((e.match_length = 0),
        (N = L._tr_tally(e, 0, e.window[e.strstart])),
        e.lookahead--,
        e.strstart++,
        N && (Q(e, !1), e.strm.avail_out === 0))
      )
        return se;
    }
    return (
      (e.insert = 0),
      O === t
        ? (Q(e, !0), e.strm.avail_out === 0 ? Re : ke)
        : e.last_lit && (Q(e, !1), e.strm.avail_out === 0)
          ? se
          : be
    );
  }
  function me(e, O, N, f, x) {
    ((this.good_length = e),
      (this.max_lazy = O),
      (this.nice_length = N),
      (this.max_chain = f),
      (this.func = x));
  }
  var Ze;
  Ze = [
    new me(0, 0, 0, 0, Qe),
    new me(4, 4, 8, 4, Ye),
    new me(4, 5, 16, 8, Ye),
    new me(4, 6, 32, 32, Ye),
    new me(4, 4, 16, 16, Ce),
    new me(8, 16, 32, 32, Ce),
    new me(8, 16, 128, 128, Ce),
    new me(8, 32, 128, 256, Ce),
    new me(32, 128, 258, 1024, Ce),
    new me(32, 258, 258, 4096, Ce),
  ];
  function er(e) {
    ((e.window_size = 2 * e.w_size),
      Oe(e.head),
      (e.max_lazy_match = Ze[e.level].max_lazy),
      (e.good_match = Ze[e.level].good_length),
      (e.nice_match = Ze[e.level].nice_length),
      (e.max_chain_length = Ze[e.level].max_chain),
      (e.strstart = 0),
      (e.block_start = 0),
      (e.lookahead = 0),
      (e.insert = 0),
      (e.match_length = e.prev_length = $ - 1),
      (e.match_available = 0),
      (e.ins_h = 0));
  }
  function o() {
    ((this.strm = null),
      (this.status = 0),
      (this.pending_buf = null),
      (this.pending_buf_size = 0),
      (this.pending_out = 0),
      (this.pending = 0),
      (this.wrap = 0),
      (this.gzhead = null),
      (this.gzindex = 0),
      (this.method = k),
      (this.last_flush = -1),
      (this.w_size = 0),
      (this.w_bits = 0),
      (this.w_mask = 0),
      (this.window = null),
      (this.window_size = 0),
      (this.prev = null),
      (this.head = null),
      (this.ins_h = 0),
      (this.hash_size = 0),
      (this.hash_bits = 0),
      (this.hash_mask = 0),
      (this.hash_shift = 0),
      (this.block_start = 0),
      (this.match_length = 0),
      (this.prev_match = 0),
      (this.match_available = 0),
      (this.strstart = 0),
      (this.match_start = 0),
      (this.lookahead = 0),
      (this.prev_length = 0),
      (this.max_chain_length = 0),
      (this.max_lazy_match = 0),
      (this.level = 0),
      (this.strategy = 0),
      (this.good_match = 0),
      (this.nice_match = 0),
      (this.dyn_ltree = new p.Buf16(j * 2)),
      (this.dyn_dtree = new p.Buf16((2 * C + 1) * 2)),
      (this.bl_tree = new p.Buf16((2 * I + 1) * 2)),
      Oe(this.dyn_ltree),
      Oe(this.dyn_dtree),
      Oe(this.bl_tree),
      (this.l_desc = null),
      (this.d_desc = null),
      (this.bl_desc = null),
      (this.bl_count = new p.Buf16(V + 1)),
      (this.heap = new p.Buf16(2 * T + 1)),
      Oe(this.heap),
      (this.heap_len = 0),
      (this.heap_max = 0),
      (this.depth = new p.Buf16(2 * T + 1)),
      Oe(this.depth),
      (this.l_buf = 0),
      (this.lit_bufsize = 0),
      (this.last_lit = 0),
      (this.d_buf = 0),
      (this.opt_len = 0),
      (this.static_len = 0),
      (this.matches = 0),
      (this.insert = 0),
      (this.bi_buf = 0),
      (this.bi_valid = 0));
  }
  function J(e) {
    var O;
    return !e || !e.state
      ? Se(e, l)
      : ((e.total_in = e.total_out = 0),
        (e.data_type = b),
        (O = e.state),
        (O.pending = 0),
        (O.pending_out = 0),
        O.wrap < 0 && (O.wrap = -O.wrap),
        (O.status = O.wrap ? X : le),
        (e.adler = O.wrap === 2 ? 0 : 1),
        (O.last_flush = G),
        L._tr_init(O),
        d);
  }
  function W(e) {
    var O = J(e);
    return (O === d && er(e.state), O);
  }
  function ee(e, O) {
    return !e || !e.state || e.state.wrap !== 2 ? l : ((e.state.gzhead = O), d);
  }
  function A(e, O, N, f, x, R) {
    if (!e) return l;
    var ae = 1;
    if (
      (O === s && (O = 6),
      f < 0 ? ((ae = 0), (f = -f)) : f > 15 && ((ae = 2), (f -= 16)),
      x < 1 ||
        x > S ||
        N !== k ||
        f < 8 ||
        f > 15 ||
        O < 0 ||
        O > 9 ||
        R < 0 ||
        R > n)
    )
      return Se(e, l);
    f === 8 && (f = 9);
    var q = new o();
    return (
      (e.state = q),
      (q.strm = e),
      (q.wrap = ae),
      (q.gzhead = null),
      (q.w_bits = f),
      (q.w_size = 1 << q.w_bits),
      (q.w_mask = q.w_size - 1),
      (q.hash_bits = x + 7),
      (q.hash_size = 1 << q.hash_bits),
      (q.hash_mask = q.hash_size - 1),
      (q.hash_shift = ~~((q.hash_bits + $ - 1) / $)),
      (q.window = new p.Buf8(q.w_size * 2)),
      (q.head = new p.Buf16(q.hash_size)),
      (q.prev = new p.Buf16(q.w_size)),
      (q.lit_bufsize = 1 << (x + 6)),
      (q.pending_buf_size = q.lit_bufsize * 4),
      (q.pending_buf = new p.Buf8(q.pending_buf_size)),
      (q.d_buf = 1 * q.lit_bufsize),
      (q.l_buf = 3 * q.lit_bufsize),
      (q.level = O),
      (q.strategy = R),
      (q.method = N),
      W(e)
    );
  }
  function M(e, O) {
    return A(e, O, k, D, B, g);
  }
  function a(e, O) {
    var N, f, x, R;
    if (!e || !e.state || O > w || O < 0) return e ? Se(e, l) : l;
    if (
      ((f = e.state),
      !e.output ||
        (!e.input && e.avail_in !== 0) ||
        (f.status === oe && O !== t))
    )
      return Se(e, e.avail_out === 0 ? y : l);
    if (((f.strm = e), (N = f.last_flush), (f.last_flush = O), f.status === X))
      if (f.wrap === 2)
        ((e.adler = 0),
          te(f, 31),
          te(f, 139),
          te(f, 8),
          f.gzhead
            ? (te(
                f,
                (f.gzhead.text ? 1 : 0) +
                  (f.gzhead.hcrc ? 2 : 0) +
                  (f.gzhead.extra ? 4 : 0) +
                  (f.gzhead.name ? 8 : 0) +
                  (f.gzhead.comment ? 16 : 0),
              ),
              te(f, f.gzhead.time & 255),
              te(f, (f.gzhead.time >> 8) & 255),
              te(f, (f.gzhead.time >> 16) & 255),
              te(f, (f.gzhead.time >> 24) & 255),
              te(f, f.level === 9 ? 2 : f.strategy >= v || f.level < 2 ? 4 : 0),
              te(f, f.gzhead.os & 255),
              f.gzhead.extra &&
                f.gzhead.extra.length &&
                (te(f, f.gzhead.extra.length & 255),
                te(f, (f.gzhead.extra.length >> 8) & 255)),
              f.gzhead.hcrc &&
                (e.adler = P(e.adler, f.pending_buf, f.pending, 0)),
              (f.gzindex = 0),
              (f.status = re))
            : (te(f, 0),
              te(f, 0),
              te(f, 0),
              te(f, 0),
              te(f, 0),
              te(f, f.level === 9 ? 2 : f.strategy >= v || f.level < 2 ? 4 : 0),
              te(f, ve),
              (f.status = le)));
      else {
        var ae = (k + ((f.w_bits - 8) << 4)) << 8,
          q = -1;
        (f.strategy >= v || f.level < 2
          ? (q = 0)
          : f.level < 6
            ? (q = 1)
            : f.level === 6
              ? (q = 2)
              : (q = 3),
          (ae |= q << 6),
          f.strstart !== 0 && (ae |= ie),
          (ae += 31 - (ae % 31)),
          (f.status = le),
          ue(f, ae),
          f.strstart !== 0 && (ue(f, e.adler >>> 16), ue(f, e.adler & 65535)),
          (e.adler = 1));
      }
    if (f.status === re)
      if (f.gzhead.extra) {
        for (
          x = f.pending;
          f.gzindex < (f.gzhead.extra.length & 65535) &&
          !(
            f.pending === f.pending_buf_size &&
            (f.gzhead.hcrc &&
              f.pending > x &&
              (e.adler = P(e.adler, f.pending_buf, f.pending - x, x)),
            he(e),
            (x = f.pending),
            f.pending === f.pending_buf_size)
          );
        )
          (te(f, f.gzhead.extra[f.gzindex] & 255), f.gzindex++);
        (f.gzhead.hcrc &&
          f.pending > x &&
          (e.adler = P(e.adler, f.pending_buf, f.pending - x, x)),
          f.gzindex === f.gzhead.extra.length &&
            ((f.gzindex = 0), (f.status = U)));
      } else f.status = U;
    if (f.status === U)
      if (f.gzhead.name) {
        x = f.pending;
        do {
          if (
            f.pending === f.pending_buf_size &&
            (f.gzhead.hcrc &&
              f.pending > x &&
              (e.adler = P(e.adler, f.pending_buf, f.pending - x, x)),
            he(e),
            (x = f.pending),
            f.pending === f.pending_buf_size)
          ) {
            R = 1;
            break;
          }
          (f.gzindex < f.gzhead.name.length
            ? (R = f.gzhead.name.charCodeAt(f.gzindex++) & 255)
            : (R = 0),
            te(f, R));
        } while (R !== 0);
        (f.gzhead.hcrc &&
          f.pending > x &&
          (e.adler = P(e.adler, f.pending_buf, f.pending - x, x)),
          R === 0 && ((f.gzindex = 0), (f.status = _e)));
      } else f.status = _e;
    if (f.status === _e)
      if (f.gzhead.comment) {
        x = f.pending;
        do {
          if (
            f.pending === f.pending_buf_size &&
            (f.gzhead.hcrc &&
              f.pending > x &&
              (e.adler = P(e.adler, f.pending_buf, f.pending - x, x)),
            he(e),
            (x = f.pending),
            f.pending === f.pending_buf_size)
          ) {
            R = 1;
            break;
          }
          (f.gzindex < f.gzhead.comment.length
            ? (R = f.gzhead.comment.charCodeAt(f.gzindex++) & 255)
            : (R = 0),
            te(f, R));
        } while (R !== 0);
        (f.gzhead.hcrc &&
          f.pending > x &&
          (e.adler = P(e.adler, f.pending_buf, f.pending - x, x)),
          R === 0 && (f.status = fe));
      } else f.status = fe;
    if (
      (f.status === fe &&
        (f.gzhead.hcrc
          ? (f.pending + 2 > f.pending_buf_size && he(e),
            f.pending + 2 <= f.pending_buf_size &&
              (te(f, e.adler & 255),
              te(f, (e.adler >> 8) & 255),
              (e.adler = 0),
              (f.status = le)))
          : (f.status = le)),
      f.pending !== 0)
    ) {
      if ((he(e), e.avail_out === 0)) return ((f.last_flush = -1), d);
    } else if (e.avail_in === 0 && Pe(O) <= Pe(N) && O !== t) return Se(e, y);
    if (f.status === oe && e.avail_in !== 0) return Se(e, y);
    if (e.avail_in !== 0 || f.lookahead !== 0 || (O !== G && f.status !== oe)) {
      var F =
        f.strategy === v
          ? We(f, O)
          : f.strategy === h
            ? Fe(f, O)
            : Ze[f.level].func(f, O);
      if (((F === Re || F === ke) && (f.status = oe), F === se || F === Re))
        return (e.avail_out === 0 && (f.last_flush = -1), d);
      if (
        F === be &&
        (O === i
          ? L._tr_align(f)
          : O !== w &&
            (L._tr_stored_block(f, 0, 0, !1),
            O === r &&
              (Oe(f.head),
              f.lookahead === 0 &&
                ((f.strstart = 0), (f.block_start = 0), (f.insert = 0)))),
        he(e),
        e.avail_out === 0)
      )
        return ((f.last_flush = -1), d);
    }
    return O !== t
      ? d
      : f.wrap <= 0
        ? u
        : (f.wrap === 2
            ? (te(f, e.adler & 255),
              te(f, (e.adler >> 8) & 255),
              te(f, (e.adler >> 16) & 255),
              te(f, (e.adler >> 24) & 255),
              te(f, e.total_in & 255),
              te(f, (e.total_in >> 8) & 255),
              te(f, (e.total_in >> 16) & 255),
              te(f, (e.total_in >> 24) & 255))
            : (ue(f, e.adler >>> 16), ue(f, e.adler & 65535)),
          he(e),
          f.wrap > 0 && (f.wrap = -f.wrap),
          f.pending !== 0 ? d : u);
  }
  function K(e) {
    var O;
    return !e || !e.state
      ? l
      : ((O = e.state.status),
        O !== X &&
        O !== re &&
        O !== U &&
        O !== _e &&
        O !== fe &&
        O !== le &&
        O !== oe
          ? Se(e, l)
          : ((e.state = null), O === le ? Se(e, _) : d));
  }
  function ne(e, O) {
    var N = O.length,
      f,
      x,
      R,
      ae,
      q,
      F,
      de,
      Te;
    if (
      !e ||
      !e.state ||
      ((f = e.state),
      (ae = f.wrap),
      ae === 2 || (ae === 1 && f.status !== X) || f.lookahead)
    )
      return l;
    for (
      ae === 1 && (e.adler = Y(e.adler, O, N, 0)),
        f.wrap = 0,
        N >= f.w_size &&
          (ae === 0 &&
            (Oe(f.head), (f.strstart = 0), (f.block_start = 0), (f.insert = 0)),
          (Te = new p.Buf8(f.w_size)),
          p.arraySet(Te, O, N - f.w_size, f.w_size, 0),
          (O = Te),
          (N = f.w_size)),
        q = e.avail_in,
        F = e.next_in,
        de = e.input,
        e.avail_in = N,
        e.next_in = 0,
        e.input = O,
        De(f);
      f.lookahead >= $;
    ) {
      ((x = f.strstart), (R = f.lookahead - ($ - 1)));
      do
        ((f.ins_h =
          ((f.ins_h << f.hash_shift) ^ f.window[x + $ - 1]) & f.hash_mask),
          (f.prev[x & f.w_mask] = f.head[f.ins_h]),
          (f.head[f.ins_h] = x),
          x++);
      while (--R);
      ((f.strstart = x), (f.lookahead = $ - 1), De(f));
    }
    return (
      (f.strstart += f.lookahead),
      (f.block_start = f.strstart),
      (f.insert = f.lookahead),
      (f.lookahead = 0),
      (f.match_length = f.prev_length = $ - 1),
      (f.match_available = 0),
      (e.next_in = F),
      (e.input = de),
      (e.avail_in = q),
      (f.wrap = ae),
      d
    );
  }
  return (
    (Le.deflateInit = M),
    (Le.deflateInit2 = A),
    (Le.deflateReset = W),
    (Le.deflateResetKeep = J),
    (Le.deflateSetHeader = ee),
    (Le.deflate = a),
    (Le.deflateEnd = K),
    (Le.deflateSetDictionary = ne),
    (Le.deflateInfo = "pako deflate (from Nodeca project)"),
    Le
  );
}
var Ve = {},
  Gr;
function ot() {
  if (Gr) return Ve;
  Gr = 1;
  var p = $e(),
    L = !0,
    Y = !0;
  try {
    String.fromCharCode.apply(null, [0]);
  } catch {
    L = !1;
  }
  try {
    String.fromCharCode.apply(null, new Uint8Array(1));
  } catch {
    Y = !1;
  }
  for (var P = new p.Buf8(256), E = 0; E < 256; E++)
    P[E] =
      E >= 252
        ? 6
        : E >= 248
          ? 5
          : E >= 240
            ? 4
            : E >= 224
              ? 3
              : E >= 192
                ? 2
                : 1;
  ((P[254] = P[254] = 1),
    (Ve.string2buf = function (i) {
      var r,
        t,
        w,
        d,
        u,
        l = i.length,
        _ = 0;
      for (d = 0; d < l; d++)
        ((t = i.charCodeAt(d)),
          (t & 64512) === 55296 &&
            d + 1 < l &&
            ((w = i.charCodeAt(d + 1)),
            (w & 64512) === 56320 &&
              ((t = 65536 + ((t - 55296) << 10) + (w - 56320)), d++)),
          (_ += t < 128 ? 1 : t < 2048 ? 2 : t < 65536 ? 3 : 4));
      for (r = new p.Buf8(_), u = 0, d = 0; u < _; d++)
        ((t = i.charCodeAt(d)),
          (t & 64512) === 55296 &&
            d + 1 < l &&
            ((w = i.charCodeAt(d + 1)),
            (w & 64512) === 56320 &&
              ((t = 65536 + ((t - 55296) << 10) + (w - 56320)), d++)),
          t < 128
            ? (r[u++] = t)
            : t < 2048
              ? ((r[u++] = 192 | (t >>> 6)), (r[u++] = 128 | (t & 63)))
              : t < 65536
                ? ((r[u++] = 224 | (t >>> 12)),
                  (r[u++] = 128 | ((t >>> 6) & 63)),
                  (r[u++] = 128 | (t & 63)))
                : ((r[u++] = 240 | (t >>> 18)),
                  (r[u++] = 128 | ((t >>> 12) & 63)),
                  (r[u++] = 128 | ((t >>> 6) & 63)),
                  (r[u++] = 128 | (t & 63))));
      return r;
    }));
  function G(i, r) {
    if (r < 65534 && ((i.subarray && Y) || (!i.subarray && L)))
      return String.fromCharCode.apply(null, p.shrinkBuf(i, r));
    for (var t = "", w = 0; w < r; w++) t += String.fromCharCode(i[w]);
    return t;
  }
  return (
    (Ve.buf2binstring = function (i) {
      return G(i, i.length);
    }),
    (Ve.binstring2buf = function (i) {
      for (var r = new p.Buf8(i.length), t = 0, w = r.length; t < w; t++)
        r[t] = i.charCodeAt(t);
      return r;
    }),
    (Ve.buf2string = function (i, r) {
      var t,
        w,
        d,
        u,
        l = r || i.length,
        _ = new Array(l * 2);
      for (w = 0, t = 0; t < l;) {
        if (((d = i[t++]), d < 128)) {
          _[w++] = d;
          continue;
        }
        if (((u = P[d]), u > 4)) {
          ((_[w++] = 65533), (t += u - 1));
          continue;
        }
        for (d &= u === 2 ? 31 : u === 3 ? 15 : 7; u > 1 && t < l;)
          ((d = (d << 6) | (i[t++] & 63)), u--);
        if (u > 1) {
          _[w++] = 65533;
          continue;
        }
        d < 65536
          ? (_[w++] = d)
          : ((d -= 65536),
            (_[w++] = 55296 | ((d >> 10) & 1023)),
            (_[w++] = 56320 | (d & 1023)));
      }
      return G(_, w);
    }),
    (Ve.utf8border = function (i, r) {
      var t;
      for (
        r = r || i.length, r > i.length && (r = i.length), t = r - 1;
        t >= 0 && (i[t] & 192) === 128;
      )
        t--;
      return t < 0 || t === 0 ? r : t + P[i[t]] > r ? t : r;
    }),
    Ve
  );
}
var pr, Ir;
function ht() {
  if (Ir) return pr;
  Ir = 1;
  function p() {
    ((this.input = null),
      (this.next_in = 0),
      (this.avail_in = 0),
      (this.total_in = 0),
      (this.output = null),
      (this.next_out = 0),
      (this.avail_out = 0),
      (this.total_out = 0),
      (this.msg = ""),
      (this.state = null),
      (this.data_type = 2),
      (this.adler = 0));
  }
  return ((pr = p), pr);
}
var Tr;
function Mt() {
  if (Tr) return rr;
  Tr = 1;
  var p = Nt(),
    L = $e(),
    Y = ot(),
    P = Or(),
    E = ht(),
    G = Object.prototype.toString,
    i = 0,
    r = 4,
    t = 0,
    w = 1,
    d = 2,
    u = -1,
    l = 0,
    _ = 8;
  function y(h) {
    if (!(this instanceof y)) return new y(h);
    this.options = L.assign(
      {
        level: u,
        method: _,
        chunkSize: 16384,
        windowBits: 15,
        memLevel: 8,
        strategy: l,
        to: "",
      },
      h || {},
    );
    var n = this.options;
    (n.raw && n.windowBits > 0
      ? (n.windowBits = -n.windowBits)
      : n.gzip && n.windowBits > 0 && n.windowBits < 16 && (n.windowBits += 16),
      (this.err = 0),
      (this.msg = ""),
      (this.ended = !1),
      (this.chunks = []),
      (this.strm = new E()),
      (this.strm.avail_out = 0));
    var g = p.deflateInit2(
      this.strm,
      n.level,
      n.method,
      n.windowBits,
      n.memLevel,
      n.strategy,
    );
    if (g !== t) throw new Error(P[g]);
    if ((n.header && p.deflateSetHeader(this.strm, n.header), n.dictionary)) {
      var b;
      if (
        (typeof n.dictionary == "string"
          ? (b = Y.string2buf(n.dictionary))
          : G.call(n.dictionary) === "[object ArrayBuffer]"
            ? (b = new Uint8Array(n.dictionary))
            : (b = n.dictionary),
        (g = p.deflateSetDictionary(this.strm, b)),
        g !== t)
      )
        throw new Error(P[g]);
      this._dict_set = !0;
    }
  }
  ((y.prototype.push = function (h, n) {
    var g = this.strm,
      b = this.options.chunkSize,
      k,
      S;
    if (this.ended) return !1;
    ((S = n === ~~n ? n : n === !0 ? r : i),
      typeof h == "string"
        ? (g.input = Y.string2buf(h))
        : G.call(h) === "[object ArrayBuffer]"
          ? (g.input = new Uint8Array(h))
          : (g.input = h),
      (g.next_in = 0),
      (g.avail_in = g.input.length));
    do {
      if (
        (g.avail_out === 0 &&
          ((g.output = new L.Buf8(b)), (g.next_out = 0), (g.avail_out = b)),
        (k = p.deflate(g, S)),
        k !== w && k !== t)
      )
        return (this.onEnd(k), (this.ended = !0), !1);
      (g.avail_out === 0 || (g.avail_in === 0 && (S === r || S === d))) &&
        (this.options.to === "string"
          ? this.onData(Y.buf2binstring(L.shrinkBuf(g.output, g.next_out)))
          : this.onData(L.shrinkBuf(g.output, g.next_out)));
    } while ((g.avail_in > 0 || g.avail_out === 0) && k !== w);
    return S === r
      ? ((k = p.deflateEnd(this.strm)),
        this.onEnd(k),
        (this.ended = !0),
        k === t)
      : (S === d && (this.onEnd(t), (g.avail_out = 0)), !0);
  }),
    (y.prototype.onData = function (h) {
      this.chunks.push(h);
    }),
    (y.prototype.onEnd = function (h) {
      (h === t &&
        (this.options.to === "string"
          ? (this.result = this.chunks.join(""))
          : (this.result = L.flattenChunks(this.chunks))),
        (this.chunks = []),
        (this.err = h),
        (this.msg = this.strm.msg));
    }));
  function s(h, n) {
    var g = new y(n);
    if ((g.push(h, !0), g.err)) throw g.msg || P[g.err];
    return g.result;
  }
  function c(h, n) {
    return ((n = n || {}), (n.raw = !0), s(h, n));
  }
  function v(h, n) {
    return ((n = n || {}), (n.gzip = !0), s(h, n));
  }
  return (
    (rr.Deflate = y),
    (rr.deflate = s),
    (rr.deflateRaw = c),
    (rr.gzip = v),
    rr
  );
}
var tr = {},
  Me = {},
  kr,
  jr;
function Ct() {
  if (jr) return kr;
  jr = 1;
  var p = 30,
    L = 12;
  return (
    (kr = function (P, E) {
      var G,
        i,
        r,
        t,
        w,
        d,
        u,
        l,
        _,
        y,
        s,
        c,
        v,
        h,
        n,
        g,
        b,
        k,
        S,
        D,
        B,
        m,
        z,
        T,
        C;
      ((G = P.state),
        (i = P.next_in),
        (T = P.input),
        (r = i + (P.avail_in - 5)),
        (t = P.next_out),
        (C = P.output),
        (w = t - (E - P.avail_out)),
        (d = t + (P.avail_out - 257)),
        (u = G.dmax),
        (l = G.wsize),
        (_ = G.whave),
        (y = G.wnext),
        (s = G.window),
        (c = G.hold),
        (v = G.bits),
        (h = G.lencode),
        (n = G.distcode),
        (g = (1 << G.lenbits) - 1),
        (b = (1 << G.distbits) - 1));
      e: do {
        (v < 15 && ((c += T[i++] << v), (v += 8), (c += T[i++] << v), (v += 8)),
          (k = h[c & g]));
        r: for (;;) {
          if (
            ((S = k >>> 24),
            (c >>>= S),
            (v -= S),
            (S = (k >>> 16) & 255),
            S === 0)
          )
            C[t++] = k & 65535;
          else if (S & 16) {
            ((D = k & 65535),
              (S &= 15),
              S &&
                (v < S && ((c += T[i++] << v), (v += 8)),
                (D += c & ((1 << S) - 1)),
                (c >>>= S),
                (v -= S)),
              v < 15 &&
                ((c += T[i++] << v), (v += 8), (c += T[i++] << v), (v += 8)),
              (k = n[c & b]));
            t: for (;;) {
              if (
                ((S = k >>> 24),
                (c >>>= S),
                (v -= S),
                (S = (k >>> 16) & 255),
                S & 16)
              ) {
                if (
                  ((B = k & 65535),
                  (S &= 15),
                  v < S &&
                    ((c += T[i++] << v),
                    (v += 8),
                    v < S && ((c += T[i++] << v), (v += 8))),
                  (B += c & ((1 << S) - 1)),
                  B > u)
                ) {
                  ((P.msg = "invalid distance too far back"), (G.mode = p));
                  break e;
                }
                if (((c >>>= S), (v -= S), (S = t - w), B > S)) {
                  if (((S = B - S), S > _ && G.sane)) {
                    ((P.msg = "invalid distance too far back"), (G.mode = p));
                    break e;
                  }
                  if (((m = 0), (z = s), y === 0)) {
                    if (((m += l - S), S < D)) {
                      D -= S;
                      do C[t++] = s[m++];
                      while (--S);
                      ((m = t - B), (z = C));
                    }
                  } else if (y < S) {
                    if (((m += l + y - S), (S -= y), S < D)) {
                      D -= S;
                      do C[t++] = s[m++];
                      while (--S);
                      if (((m = 0), y < D)) {
                        ((S = y), (D -= S));
                        do C[t++] = s[m++];
                        while (--S);
                        ((m = t - B), (z = C));
                      }
                    }
                  } else if (((m += y - S), S < D)) {
                    D -= S;
                    do C[t++] = s[m++];
                    while (--S);
                    ((m = t - B), (z = C));
                  }
                  for (; D > 2;)
                    ((C[t++] = z[m++]),
                      (C[t++] = z[m++]),
                      (C[t++] = z[m++]),
                      (D -= 3));
                  D && ((C[t++] = z[m++]), D > 1 && (C[t++] = z[m++]));
                } else {
                  m = t - B;
                  do
                    ((C[t++] = C[m++]),
                      (C[t++] = C[m++]),
                      (C[t++] = C[m++]),
                      (D -= 3));
                  while (D > 2);
                  D && ((C[t++] = C[m++]), D > 1 && (C[t++] = C[m++]));
                }
              } else if ((S & 64) === 0) {
                k = n[(k & 65535) + (c & ((1 << S) - 1))];
                continue t;
              } else {
                ((P.msg = "invalid distance code"), (G.mode = p));
                break e;
              }
              break;
            }
          } else if ((S & 64) === 0) {
            k = h[(k & 65535) + (c & ((1 << S) - 1))];
            continue r;
          } else if (S & 32) {
            G.mode = L;
            break e;
          } else {
            ((P.msg = "invalid literal/length code"), (G.mode = p));
            break e;
          }
          break;
        }
      } while (i < r && t < d);
      ((D = v >> 3),
        (i -= D),
        (v -= D << 3),
        (c &= (1 << v) - 1),
        (P.next_in = i),
        (P.next_out = t),
        (P.avail_in = i < r ? 5 + (r - i) : 5 - (i - r)),
        (P.avail_out = t < d ? 257 + (d - t) : 257 - (t - d)),
        (G.hold = c),
        (G.bits = v));
    }),
    kr
  );
}
var xr, Jr;
function Lt() {
  if (Jr) return xr;
  Jr = 1;
  var p = $e(),
    L = 15,
    Y = 852,
    P = 592,
    E = 0,
    G = 1,
    i = 2,
    r = [
      3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59,
      67, 83, 99, 115, 131, 163, 195, 227, 258, 0, 0,
    ],
    t = [
      16, 16, 16, 16, 16, 16, 16, 16, 17, 17, 17, 17, 18, 18, 18, 18, 19, 19,
      19, 19, 20, 20, 20, 20, 21, 21, 21, 21, 16, 72, 78,
    ],
    w = [
      1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513,
      769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577, 0, 0,
    ],
    d = [
      16, 16, 16, 16, 17, 17, 18, 18, 19, 19, 20, 20, 21, 21, 22, 22, 23, 23,
      24, 24, 25, 25, 26, 26, 27, 27, 28, 28, 29, 29, 64, 64,
    ];
  return (
    (xr = function (l, _, y, s, c, v, h, n) {
      var g = n.bits,
        b = 0,
        k = 0,
        S = 0,
        D = 0,
        B = 0,
        m = 0,
        z = 0,
        T = 0,
        C = 0,
        I = 0,
        j,
        V,
        $,
        Z,
        H,
        ie = null,
        X = 0,
        re,
        U = new p.Buf16(L + 1),
        _e = new p.Buf16(L + 1),
        fe = null,
        le = 0,
        oe,
        se,
        be;
      for (b = 0; b <= L; b++) U[b] = 0;
      for (k = 0; k < s; k++) U[_[y + k]]++;
      for (B = g, D = L; D >= 1 && U[D] === 0; D--);
      if ((B > D && (B = D), D === 0))
        return (
          (c[v++] = (1 << 24) | (64 << 16) | 0),
          (c[v++] = (1 << 24) | (64 << 16) | 0),
          (n.bits = 1),
          0
        );
      for (S = 1; S < D && U[S] === 0; S++);
      for (B < S && (B = S), T = 1, b = 1; b <= L; b++)
        if (((T <<= 1), (T -= U[b]), T < 0)) return -1;
      if (T > 0 && (l === E || D !== 1)) return -1;
      for (_e[1] = 0, b = 1; b < L; b++) _e[b + 1] = _e[b] + U[b];
      for (k = 0; k < s; k++) _[y + k] !== 0 && (h[_e[_[y + k]]++] = k);
      if (
        (l === E
          ? ((ie = fe = h), (re = 19))
          : l === G
            ? ((ie = r), (X -= 257), (fe = t), (le -= 257), (re = 256))
            : ((ie = w), (fe = d), (re = -1)),
        (I = 0),
        (k = 0),
        (b = S),
        (H = v),
        (m = B),
        (z = 0),
        ($ = -1),
        (C = 1 << B),
        (Z = C - 1),
        (l === G && C > Y) || (l === i && C > P))
      )
        return 1;
      for (;;) {
        ((oe = b - z),
          h[k] < re
            ? ((se = 0), (be = h[k]))
            : h[k] > re
              ? ((se = fe[le + h[k]]), (be = ie[X + h[k]]))
              : ((se = 96), (be = 0)),
          (j = 1 << (b - z)),
          (V = 1 << m),
          (S = V));
        do ((V -= j), (c[H + (I >> z) + V] = (oe << 24) | (se << 16) | be | 0));
        while (V !== 0);
        for (j = 1 << (b - 1); I & j;) j >>= 1;
        if ((j !== 0 ? ((I &= j - 1), (I += j)) : (I = 0), k++, --U[b] === 0)) {
          if (b === D) break;
          b = _[y + h[k]];
        }
        if (b > B && (I & Z) !== $) {
          for (
            z === 0 && (z = B), H += S, m = b - z, T = 1 << m;
            m + z < D && ((T -= U[m + z]), !(T <= 0));
          )
            (m++, (T <<= 1));
          if (((C += 1 << m), (l === G && C > Y) || (l === i && C > P)))
            return 1;
          (($ = I & Z), (c[$] = (B << 24) | (m << 16) | (H - v) | 0));
        }
      }
      return (
        I !== 0 && (c[H + I] = ((b - z) << 24) | (64 << 16) | 0),
        (n.bits = B),
        0
      );
    }),
    xr
  );
}
var Kr;
function Pt() {
  if (Kr) return Me;
  Kr = 1;
  var p = $e(),
    L = ft(),
    Y = lt(),
    P = Ct(),
    E = Lt(),
    G = 0,
    i = 1,
    r = 2,
    t = 4,
    w = 5,
    d = 6,
    u = 0,
    l = 1,
    _ = 2,
    y = -2,
    s = -3,
    c = -4,
    v = -5,
    h = 8,
    n = 1,
    g = 2,
    b = 3,
    k = 4,
    S = 5,
    D = 6,
    B = 7,
    m = 8,
    z = 9,
    T = 10,
    C = 11,
    I = 12,
    j = 13,
    V = 14,
    $ = 15,
    Z = 16,
    H = 17,
    ie = 18,
    X = 19,
    re = 20,
    U = 21,
    _e = 22,
    fe = 23,
    le = 24,
    oe = 25,
    se = 26,
    be = 27,
    Re = 28,
    ke = 29,
    ve = 30,
    Se = 31,
    Pe = 32,
    Oe = 852,
    he = 592,
    Q = 15,
    te = Q;
  function ue(A) {
    return (
      ((A >>> 24) & 255) +
      ((A >>> 8) & 65280) +
      ((A & 65280) << 8) +
      ((A & 255) << 24)
    );
  }
  function we() {
    ((this.mode = 0),
      (this.last = !1),
      (this.wrap = 0),
      (this.havedict = !1),
      (this.flags = 0),
      (this.dmax = 0),
      (this.check = 0),
      (this.total = 0),
      (this.head = null),
      (this.wbits = 0),
      (this.wsize = 0),
      (this.whave = 0),
      (this.wnext = 0),
      (this.window = null),
      (this.hold = 0),
      (this.bits = 0),
      (this.length = 0),
      (this.offset = 0),
      (this.extra = 0),
      (this.lencode = null),
      (this.distcode = null),
      (this.lenbits = 0),
      (this.distbits = 0),
      (this.ncode = 0),
      (this.nlen = 0),
      (this.ndist = 0),
      (this.have = 0),
      (this.next = null),
      (this.lens = new p.Buf16(320)),
      (this.work = new p.Buf16(288)),
      (this.lendyn = null),
      (this.distdyn = null),
      (this.sane = 0),
      (this.back = 0),
      (this.was = 0));
  }
  function ge(A) {
    var M;
    return !A || !A.state
      ? y
      : ((M = A.state),
        (A.total_in = A.total_out = M.total = 0),
        (A.msg = ""),
        M.wrap && (A.adler = M.wrap & 1),
        (M.mode = n),
        (M.last = 0),
        (M.havedict = 0),
        (M.dmax = 32768),
        (M.head = null),
        (M.hold = 0),
        (M.bits = 0),
        (M.lencode = M.lendyn = new p.Buf32(Oe)),
        (M.distcode = M.distdyn = new p.Buf32(he)),
        (M.sane = 1),
        (M.back = -1),
        u);
  }
  function De(A) {
    var M;
    return !A || !A.state
      ? y
      : ((M = A.state), (M.wsize = 0), (M.whave = 0), (M.wnext = 0), ge(A));
  }
  function Qe(A, M) {
    var a, K;
    return !A ||
      !A.state ||
      ((K = A.state),
      M < 0 ? ((a = 0), (M = -M)) : ((a = (M >> 4) + 1), M < 48 && (M &= 15)),
      M && (M < 8 || M > 15))
      ? y
      : (K.window !== null && K.wbits !== M && (K.window = null),
        (K.wrap = a),
        (K.wbits = M),
        De(A));
  }
  function Ye(A, M) {
    var a, K;
    return A
      ? ((K = new we()),
        (A.state = K),
        (K.window = null),
        (a = Qe(A, M)),
        a !== u && (A.state = null),
        a)
      : y;
  }
  function Ce(A) {
    return Ye(A, te);
  }
  var Fe = !0,
    We,
    me;
  function Ze(A) {
    if (Fe) {
      var M;
      for (We = new p.Buf32(512), me = new p.Buf32(32), M = 0; M < 144;)
        A.lens[M++] = 8;
      for (; M < 256;) A.lens[M++] = 9;
      for (; M < 280;) A.lens[M++] = 7;
      for (; M < 288;) A.lens[M++] = 8;
      for (E(i, A.lens, 0, 288, We, 0, A.work, { bits: 9 }), M = 0; M < 32;)
        A.lens[M++] = 5;
      (E(r, A.lens, 0, 32, me, 0, A.work, { bits: 5 }), (Fe = !1));
    }
    ((A.lencode = We), (A.lenbits = 9), (A.distcode = me), (A.distbits = 5));
  }
  function er(A, M, a, K) {
    var ne,
      e = A.state;
    return (
      e.window === null &&
        ((e.wsize = 1 << e.wbits),
        (e.wnext = 0),
        (e.whave = 0),
        (e.window = new p.Buf8(e.wsize))),
      K >= e.wsize
        ? (p.arraySet(e.window, M, a - e.wsize, e.wsize, 0),
          (e.wnext = 0),
          (e.whave = e.wsize))
        : ((ne = e.wsize - e.wnext),
          ne > K && (ne = K),
          p.arraySet(e.window, M, a - K, ne, e.wnext),
          (K -= ne),
          K
            ? (p.arraySet(e.window, M, a - K, K, 0),
              (e.wnext = K),
              (e.whave = e.wsize))
            : ((e.wnext += ne),
              e.wnext === e.wsize && (e.wnext = 0),
              e.whave < e.wsize && (e.whave += ne))),
      0
    );
  }
  function o(A, M) {
    var a,
      K,
      ne,
      e,
      O,
      N,
      f,
      x,
      R,
      ae,
      q,
      F,
      de,
      Te,
      pe = 0,
      ce,
      ye,
      ze,
      Be,
      nr,
      fr,
      Ee,
      Ne,
      Ae = new p.Buf8(4),
      je,
      He,
      Br = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];
    if (!A || !A.state || !A.output || (!A.input && A.avail_in !== 0)) return y;
    ((a = A.state),
      a.mode === I && (a.mode = j),
      (O = A.next_out),
      (ne = A.output),
      (f = A.avail_out),
      (e = A.next_in),
      (K = A.input),
      (N = A.avail_in),
      (x = a.hold),
      (R = a.bits),
      (ae = N),
      (q = f),
      (Ne = u));
    e: for (;;)
      switch (a.mode) {
        case n:
          if (a.wrap === 0) {
            a.mode = j;
            break;
          }
          for (; R < 16;) {
            if (N === 0) break e;
            (N--, (x += K[e++] << R), (R += 8));
          }
          if (a.wrap & 2 && x === 35615) {
            ((a.check = 0),
              (Ae[0] = x & 255),
              (Ae[1] = (x >>> 8) & 255),
              (a.check = Y(a.check, Ae, 2, 0)),
              (x = 0),
              (R = 0),
              (a.mode = g));
            break;
          }
          if (
            ((a.flags = 0),
            a.head && (a.head.done = !1),
            !(a.wrap & 1) || (((x & 255) << 8) + (x >> 8)) % 31)
          ) {
            ((A.msg = "incorrect header check"), (a.mode = ve));
            break;
          }
          if ((x & 15) !== h) {
            ((A.msg = "unknown compression method"), (a.mode = ve));
            break;
          }
          if (((x >>>= 4), (R -= 4), (Ee = (x & 15) + 8), a.wbits === 0))
            a.wbits = Ee;
          else if (Ee > a.wbits) {
            ((A.msg = "invalid window size"), (a.mode = ve));
            break;
          }
          ((a.dmax = 1 << Ee),
            (A.adler = a.check = 1),
            (a.mode = x & 512 ? T : I),
            (x = 0),
            (R = 0));
          break;
        case g:
          for (; R < 16;) {
            if (N === 0) break e;
            (N--, (x += K[e++] << R), (R += 8));
          }
          if (((a.flags = x), (a.flags & 255) !== h)) {
            ((A.msg = "unknown compression method"), (a.mode = ve));
            break;
          }
          if (a.flags & 57344) {
            ((A.msg = "unknown header flags set"), (a.mode = ve));
            break;
          }
          (a.head && (a.head.text = (x >> 8) & 1),
            a.flags & 512 &&
              ((Ae[0] = x & 255),
              (Ae[1] = (x >>> 8) & 255),
              (a.check = Y(a.check, Ae, 2, 0))),
            (x = 0),
            (R = 0),
            (a.mode = b));
        case b:
          for (; R < 32;) {
            if (N === 0) break e;
            (N--, (x += K[e++] << R), (R += 8));
          }
          (a.head && (a.head.time = x),
            a.flags & 512 &&
              ((Ae[0] = x & 255),
              (Ae[1] = (x >>> 8) & 255),
              (Ae[2] = (x >>> 16) & 255),
              (Ae[3] = (x >>> 24) & 255),
              (a.check = Y(a.check, Ae, 4, 0))),
            (x = 0),
            (R = 0),
            (a.mode = k));
        case k:
          for (; R < 16;) {
            if (N === 0) break e;
            (N--, (x += K[e++] << R), (R += 8));
          }
          (a.head && ((a.head.xflags = x & 255), (a.head.os = x >> 8)),
            a.flags & 512 &&
              ((Ae[0] = x & 255),
              (Ae[1] = (x >>> 8) & 255),
              (a.check = Y(a.check, Ae, 2, 0))),
            (x = 0),
            (R = 0),
            (a.mode = S));
        case S:
          if (a.flags & 1024) {
            for (; R < 16;) {
              if (N === 0) break e;
              (N--, (x += K[e++] << R), (R += 8));
            }
            ((a.length = x),
              a.head && (a.head.extra_len = x),
              a.flags & 512 &&
                ((Ae[0] = x & 255),
                (Ae[1] = (x >>> 8) & 255),
                (a.check = Y(a.check, Ae, 2, 0))),
              (x = 0),
              (R = 0));
          } else a.head && (a.head.extra = null);
          a.mode = D;
        case D:
          if (
            a.flags & 1024 &&
            ((F = a.length),
            F > N && (F = N),
            F &&
              (a.head &&
                ((Ee = a.head.extra_len - a.length),
                a.head.extra || (a.head.extra = new Array(a.head.extra_len)),
                p.arraySet(a.head.extra, K, e, F, Ee)),
              a.flags & 512 && (a.check = Y(a.check, K, F, e)),
              (N -= F),
              (e += F),
              (a.length -= F)),
            a.length)
          )
            break e;
          ((a.length = 0), (a.mode = B));
        case B:
          if (a.flags & 2048) {
            if (N === 0) break e;
            F = 0;
            do
              ((Ee = K[e + F++]),
                a.head &&
                  Ee &&
                  a.length < 65536 &&
                  (a.head.name += String.fromCharCode(Ee)));
            while (Ee && F < N);
            if (
              (a.flags & 512 && (a.check = Y(a.check, K, F, e)),
              (N -= F),
              (e += F),
              Ee)
            )
              break e;
          } else a.head && (a.head.name = null);
          ((a.length = 0), (a.mode = m));
        case m:
          if (a.flags & 4096) {
            if (N === 0) break e;
            F = 0;
            do
              ((Ee = K[e + F++]),
                a.head &&
                  Ee &&
                  a.length < 65536 &&
                  (a.head.comment += String.fromCharCode(Ee)));
            while (Ee && F < N);
            if (
              (a.flags & 512 && (a.check = Y(a.check, K, F, e)),
              (N -= F),
              (e += F),
              Ee)
            )
              break e;
          } else a.head && (a.head.comment = null);
          a.mode = z;
        case z:
          if (a.flags & 512) {
            for (; R < 16;) {
              if (N === 0) break e;
              (N--, (x += K[e++] << R), (R += 8));
            }
            if (x !== (a.check & 65535)) {
              ((A.msg = "header crc mismatch"), (a.mode = ve));
              break;
            }
            ((x = 0), (R = 0));
          }
          (a.head && ((a.head.hcrc = (a.flags >> 9) & 1), (a.head.done = !0)),
            (A.adler = a.check = 0),
            (a.mode = I));
          break;
        case T:
          for (; R < 32;) {
            if (N === 0) break e;
            (N--, (x += K[e++] << R), (R += 8));
          }
          ((A.adler = a.check = ue(x)), (x = 0), (R = 0), (a.mode = C));
        case C:
          if (a.havedict === 0)
            return (
              (A.next_out = O),
              (A.avail_out = f),
              (A.next_in = e),
              (A.avail_in = N),
              (a.hold = x),
              (a.bits = R),
              _
            );
          ((A.adler = a.check = 1), (a.mode = I));
        case I:
          if (M === w || M === d) break e;
        case j:
          if (a.last) {
            ((x >>>= R & 7), (R -= R & 7), (a.mode = be));
            break;
          }
          for (; R < 3;) {
            if (N === 0) break e;
            (N--, (x += K[e++] << R), (R += 8));
          }
          switch (((a.last = x & 1), (x >>>= 1), (R -= 1), x & 3)) {
            case 0:
              a.mode = V;
              break;
            case 1:
              if ((Ze(a), (a.mode = re), M === d)) {
                ((x >>>= 2), (R -= 2));
                break e;
              }
              break;
            case 2:
              a.mode = H;
              break;
            case 3:
              ((A.msg = "invalid block type"), (a.mode = ve));
          }
          ((x >>>= 2), (R -= 2));
          break;
        case V:
          for (x >>>= R & 7, R -= R & 7; R < 32;) {
            if (N === 0) break e;
            (N--, (x += K[e++] << R), (R += 8));
          }
          if ((x & 65535) !== ((x >>> 16) ^ 65535)) {
            ((A.msg = "invalid stored block lengths"), (a.mode = ve));
            break;
          }
          if (((a.length = x & 65535), (x = 0), (R = 0), (a.mode = $), M === d))
            break e;
        case $:
          a.mode = Z;
        case Z:
          if (((F = a.length), F)) {
            if ((F > N && (F = N), F > f && (F = f), F === 0)) break e;
            (p.arraySet(ne, K, e, F, O),
              (N -= F),
              (e += F),
              (f -= F),
              (O += F),
              (a.length -= F));
            break;
          }
          a.mode = I;
          break;
        case H:
          for (; R < 14;) {
            if (N === 0) break e;
            (N--, (x += K[e++] << R), (R += 8));
          }
          if (
            ((a.nlen = (x & 31) + 257),
            (x >>>= 5),
            (R -= 5),
            (a.ndist = (x & 31) + 1),
            (x >>>= 5),
            (R -= 5),
            (a.ncode = (x & 15) + 4),
            (x >>>= 4),
            (R -= 4),
            a.nlen > 286 || a.ndist > 30)
          ) {
            ((A.msg = "too many length or distance symbols"), (a.mode = ve));
            break;
          }
          ((a.have = 0), (a.mode = ie));
        case ie:
          for (; a.have < a.ncode;) {
            for (; R < 3;) {
              if (N === 0) break e;
              (N--, (x += K[e++] << R), (R += 8));
            }
            ((a.lens[Br[a.have++]] = x & 7), (x >>>= 3), (R -= 3));
          }
          for (; a.have < 19;) a.lens[Br[a.have++]] = 0;
          if (
            ((a.lencode = a.lendyn),
            (a.lenbits = 7),
            (je = { bits: a.lenbits }),
            (Ne = E(G, a.lens, 0, 19, a.lencode, 0, a.work, je)),
            (a.lenbits = je.bits),
            Ne)
          ) {
            ((A.msg = "invalid code lengths set"), (a.mode = ve));
            break;
          }
          ((a.have = 0), (a.mode = X));
        case X:
          for (; a.have < a.nlen + a.ndist;) {
            for (
              ;
              (pe = a.lencode[x & ((1 << a.lenbits) - 1)]),
                (ce = pe >>> 24),
                (ye = (pe >>> 16) & 255),
                (ze = pe & 65535),
                !(ce <= R);
            ) {
              if (N === 0) break e;
              (N--, (x += K[e++] << R), (R += 8));
            }
            if (ze < 16) ((x >>>= ce), (R -= ce), (a.lens[a.have++] = ze));
            else {
              if (ze === 16) {
                for (He = ce + 2; R < He;) {
                  if (N === 0) break e;
                  (N--, (x += K[e++] << R), (R += 8));
                }
                if (((x >>>= ce), (R -= ce), a.have === 0)) {
                  ((A.msg = "invalid bit length repeat"), (a.mode = ve));
                  break;
                }
                ((Ee = a.lens[a.have - 1]),
                  (F = 3 + (x & 3)),
                  (x >>>= 2),
                  (R -= 2));
              } else if (ze === 17) {
                for (He = ce + 3; R < He;) {
                  if (N === 0) break e;
                  (N--, (x += K[e++] << R), (R += 8));
                }
                ((x >>>= ce),
                  (R -= ce),
                  (Ee = 0),
                  (F = 3 + (x & 7)),
                  (x >>>= 3),
                  (R -= 3));
              } else {
                for (He = ce + 7; R < He;) {
                  if (N === 0) break e;
                  (N--, (x += K[e++] << R), (R += 8));
                }
                ((x >>>= ce),
                  (R -= ce),
                  (Ee = 0),
                  (F = 11 + (x & 127)),
                  (x >>>= 7),
                  (R -= 7));
              }
              if (a.have + F > a.nlen + a.ndist) {
                ((A.msg = "invalid bit length repeat"), (a.mode = ve));
                break;
              }
              for (; F--;) a.lens[a.have++] = Ee;
            }
          }
          if (a.mode === ve) break;
          if (a.lens[256] === 0) {
            ((A.msg = "invalid code -- missing end-of-block"), (a.mode = ve));
            break;
          }
          if (
            ((a.lenbits = 9),
            (je = { bits: a.lenbits }),
            (Ne = E(i, a.lens, 0, a.nlen, a.lencode, 0, a.work, je)),
            (a.lenbits = je.bits),
            Ne)
          ) {
            ((A.msg = "invalid literal/lengths set"), (a.mode = ve));
            break;
          }
          if (
            ((a.distbits = 6),
            (a.distcode = a.distdyn),
            (je = { bits: a.distbits }),
            (Ne = E(r, a.lens, a.nlen, a.ndist, a.distcode, 0, a.work, je)),
            (a.distbits = je.bits),
            Ne)
          ) {
            ((A.msg = "invalid distances set"), (a.mode = ve));
            break;
          }
          if (((a.mode = re), M === d)) break e;
        case re:
          a.mode = U;
        case U:
          if (N >= 6 && f >= 258) {
            ((A.next_out = O),
              (A.avail_out = f),
              (A.next_in = e),
              (A.avail_in = N),
              (a.hold = x),
              (a.bits = R),
              P(A, q),
              (O = A.next_out),
              (ne = A.output),
              (f = A.avail_out),
              (e = A.next_in),
              (K = A.input),
              (N = A.avail_in),
              (x = a.hold),
              (R = a.bits),
              a.mode === I && (a.back = -1));
            break;
          }
          for (
            a.back = 0;
            (pe = a.lencode[x & ((1 << a.lenbits) - 1)]),
              (ce = pe >>> 24),
              (ye = (pe >>> 16) & 255),
              (ze = pe & 65535),
              !(ce <= R);
          ) {
            if (N === 0) break e;
            (N--, (x += K[e++] << R), (R += 8));
          }
          if (ye && (ye & 240) === 0) {
            for (
              Be = ce, nr = ye, fr = ze;
              (pe = a.lencode[fr + ((x & ((1 << (Be + nr)) - 1)) >> Be)]),
                (ce = pe >>> 24),
                (ye = (pe >>> 16) & 255),
                (ze = pe & 65535),
                !(Be + ce <= R);
            ) {
              if (N === 0) break e;
              (N--, (x += K[e++] << R), (R += 8));
            }
            ((x >>>= Be), (R -= Be), (a.back += Be));
          }
          if (
            ((x >>>= ce), (R -= ce), (a.back += ce), (a.length = ze), ye === 0)
          ) {
            a.mode = se;
            break;
          }
          if (ye & 32) {
            ((a.back = -1), (a.mode = I));
            break;
          }
          if (ye & 64) {
            ((A.msg = "invalid literal/length code"), (a.mode = ve));
            break;
          }
          ((a.extra = ye & 15), (a.mode = _e));
        case _e:
          if (a.extra) {
            for (He = a.extra; R < He;) {
              if (N === 0) break e;
              (N--, (x += K[e++] << R), (R += 8));
            }
            ((a.length += x & ((1 << a.extra) - 1)),
              (x >>>= a.extra),
              (R -= a.extra),
              (a.back += a.extra));
          }
          ((a.was = a.length), (a.mode = fe));
        case fe:
          for (
            ;
            (pe = a.distcode[x & ((1 << a.distbits) - 1)]),
              (ce = pe >>> 24),
              (ye = (pe >>> 16) & 255),
              (ze = pe & 65535),
              !(ce <= R);
          ) {
            if (N === 0) break e;
            (N--, (x += K[e++] << R), (R += 8));
          }
          if ((ye & 240) === 0) {
            for (
              Be = ce, nr = ye, fr = ze;
              (pe = a.distcode[fr + ((x & ((1 << (Be + nr)) - 1)) >> Be)]),
                (ce = pe >>> 24),
                (ye = (pe >>> 16) & 255),
                (ze = pe & 65535),
                !(Be + ce <= R);
            ) {
              if (N === 0) break e;
              (N--, (x += K[e++] << R), (R += 8));
            }
            ((x >>>= Be), (R -= Be), (a.back += Be));
          }
          if (((x >>>= ce), (R -= ce), (a.back += ce), ye & 64)) {
            ((A.msg = "invalid distance code"), (a.mode = ve));
            break;
          }
          ((a.offset = ze), (a.extra = ye & 15), (a.mode = le));
        case le:
          if (a.extra) {
            for (He = a.extra; R < He;) {
              if (N === 0) break e;
              (N--, (x += K[e++] << R), (R += 8));
            }
            ((a.offset += x & ((1 << a.extra) - 1)),
              (x >>>= a.extra),
              (R -= a.extra),
              (a.back += a.extra));
          }
          if (a.offset > a.dmax) {
            ((A.msg = "invalid distance too far back"), (a.mode = ve));
            break;
          }
          a.mode = oe;
        case oe:
          if (f === 0) break e;
          if (((F = q - f), a.offset > F)) {
            if (((F = a.offset - F), F > a.whave && a.sane)) {
              ((A.msg = "invalid distance too far back"), (a.mode = ve));
              break;
            }
            (F > a.wnext
              ? ((F -= a.wnext), (de = a.wsize - F))
              : (de = a.wnext - F),
              F > a.length && (F = a.length),
              (Te = a.window));
          } else ((Te = ne), (de = O - a.offset), (F = a.length));
          (F > f && (F = f), (f -= F), (a.length -= F));
          do ne[O++] = Te[de++];
          while (--F);
          a.length === 0 && (a.mode = U);
          break;
        case se:
          if (f === 0) break e;
          ((ne[O++] = a.length), f--, (a.mode = U));
          break;
        case be:
          if (a.wrap) {
            for (; R < 32;) {
              if (N === 0) break e;
              (N--, (x |= K[e++] << R), (R += 8));
            }
            if (
              ((q -= f),
              (A.total_out += q),
              (a.total += q),
              q &&
                (A.adler = a.check =
                  a.flags
                    ? Y(a.check, ne, q, O - q)
                    : L(a.check, ne, q, O - q)),
              (q = f),
              (a.flags ? x : ue(x)) !== a.check)
            ) {
              ((A.msg = "incorrect data check"), (a.mode = ve));
              break;
            }
            ((x = 0), (R = 0));
          }
          a.mode = Re;
        case Re:
          if (a.wrap && a.flags) {
            for (; R < 32;) {
              if (N === 0) break e;
              (N--, (x += K[e++] << R), (R += 8));
            }
            if (x !== (a.total & 4294967295)) {
              ((A.msg = "incorrect length check"), (a.mode = ve));
              break;
            }
            ((x = 0), (R = 0));
          }
          a.mode = ke;
        case ke:
          Ne = l;
          break e;
        case ve:
          Ne = s;
          break e;
        case Se:
          return c;
        case Pe:
        default:
          return y;
      }
    return (
      (A.next_out = O),
      (A.avail_out = f),
      (A.next_in = e),
      (A.avail_in = N),
      (a.hold = x),
      (a.bits = R),
      (a.wsize ||
        (q !== A.avail_out && a.mode < ve && (a.mode < be || M !== t))) &&
        er(A, A.output, A.next_out, q - A.avail_out),
      (ae -= A.avail_in),
      (q -= A.avail_out),
      (A.total_in += ae),
      (A.total_out += q),
      (a.total += q),
      a.wrap &&
        q &&
        (A.adler = a.check =
          a.flags
            ? Y(a.check, ne, q, A.next_out - q)
            : L(a.check, ne, q, A.next_out - q)),
      (A.data_type =
        a.bits +
        (a.last ? 64 : 0) +
        (a.mode === I ? 128 : 0) +
        (a.mode === re || a.mode === $ ? 256 : 0)),
      ((ae === 0 && q === 0) || M === t) && Ne === u && (Ne = v),
      Ne
    );
  }
  function J(A) {
    if (!A || !A.state) return y;
    var M = A.state;
    return (M.window && (M.window = null), (A.state = null), u);
  }
  function W(A, M) {
    var a;
    return !A || !A.state || ((a = A.state), (a.wrap & 2) === 0)
      ? y
      : ((a.head = M), (M.done = !1), u);
  }
  function ee(A, M) {
    var a = M.length,
      K,
      ne,
      e;
    return !A || !A.state || ((K = A.state), K.wrap !== 0 && K.mode !== C)
      ? y
      : K.mode === C && ((ne = 1), (ne = L(ne, M, a, 0)), ne !== K.check)
        ? s
        : ((e = er(A, M, a, a)),
          e ? ((K.mode = Se), c) : ((K.havedict = 1), u));
  }
  return (
    (Me.inflateReset = De),
    (Me.inflateReset2 = Qe),
    (Me.inflateResetKeep = ge),
    (Me.inflateInit = Ce),
    (Me.inflateInit2 = Ye),
    (Me.inflate = o),
    (Me.inflateEnd = J),
    (Me.inflateGetHeader = W),
    (Me.inflateSetDictionary = ee),
    (Me.inflateInfo = "pako inflate (from Nodeca project)"),
    Me
  );
}
var Er, Yr;
function ut() {
  return (
    Yr ||
      ((Yr = 1),
      (Er = {
        Z_NO_FLUSH: 0,
        Z_PARTIAL_FLUSH: 1,
        Z_SYNC_FLUSH: 2,
        Z_FULL_FLUSH: 3,
        Z_FINISH: 4,
        Z_BLOCK: 5,
        Z_TREES: 6,
        Z_OK: 0,
        Z_STREAM_END: 1,
        Z_NEED_DICT: 2,
        Z_ERRNO: -1,
        Z_STREAM_ERROR: -2,
        Z_DATA_ERROR: -3,
        Z_BUF_ERROR: -5,
        Z_NO_COMPRESSION: 0,
        Z_BEST_SPEED: 1,
        Z_BEST_COMPRESSION: 9,
        Z_DEFAULT_COMPRESSION: -1,
        Z_FILTERED: 1,
        Z_HUFFMAN_ONLY: 2,
        Z_RLE: 3,
        Z_FIXED: 4,
        Z_DEFAULT_STRATEGY: 0,
        Z_BINARY: 0,
        Z_TEXT: 1,
        Z_UNKNOWN: 2,
        Z_DEFLATED: 8,
      })),
    Er
  );
}
var yr, Wr;
function Zt() {
  if (Wr) return yr;
  Wr = 1;
  function p() {
    ((this.text = 0),
      (this.time = 0),
      (this.xflags = 0),
      (this.os = 0),
      (this.extra = null),
      (this.extra_len = 0),
      (this.name = ""),
      (this.comment = ""),
      (this.hcrc = 0),
      (this.done = !1));
  }
  return ((yr = p), yr);
}
var $r;
function Ht() {
  if ($r) return tr;
  $r = 1;
  var p = Pt(),
    L = $e(),
    Y = ot(),
    P = ut(),
    E = Or(),
    G = ht(),
    i = Zt(),
    r = Object.prototype.toString;
  function t(u) {
    if (!(this instanceof t)) return new t(u);
    this.options = L.assign(
      { chunkSize: 16384, windowBits: 0, to: "" },
      u || {},
    );
    var l = this.options;
    (l.raw &&
      l.windowBits >= 0 &&
      l.windowBits < 16 &&
      ((l.windowBits = -l.windowBits),
      l.windowBits === 0 && (l.windowBits = -15)),
      l.windowBits >= 0 &&
        l.windowBits < 16 &&
        !(u && u.windowBits) &&
        (l.windowBits += 32),
      l.windowBits > 15 &&
        l.windowBits < 48 &&
        (l.windowBits & 15) === 0 &&
        (l.windowBits |= 15),
      (this.err = 0),
      (this.msg = ""),
      (this.ended = !1),
      (this.chunks = []),
      (this.strm = new G()),
      (this.strm.avail_out = 0));
    var _ = p.inflateInit2(this.strm, l.windowBits);
    if (_ !== P.Z_OK) throw new Error(E[_]);
    if (
      ((this.header = new i()),
      p.inflateGetHeader(this.strm, this.header),
      l.dictionary &&
        (typeof l.dictionary == "string"
          ? (l.dictionary = Y.string2buf(l.dictionary))
          : r.call(l.dictionary) === "[object ArrayBuffer]" &&
            (l.dictionary = new Uint8Array(l.dictionary)),
        l.raw &&
          ((_ = p.inflateSetDictionary(this.strm, l.dictionary)),
          _ !== P.Z_OK)))
    )
      throw new Error(E[_]);
  }
  ((t.prototype.push = function (u, l) {
    var _ = this.strm,
      y = this.options.chunkSize,
      s = this.options.dictionary,
      c,
      v,
      h,
      n,
      g,
      b = !1;
    if (this.ended) return !1;
    ((v = l === ~~l ? l : l === !0 ? P.Z_FINISH : P.Z_NO_FLUSH),
      typeof u == "string"
        ? (_.input = Y.binstring2buf(u))
        : r.call(u) === "[object ArrayBuffer]"
          ? (_.input = new Uint8Array(u))
          : (_.input = u),
      (_.next_in = 0),
      (_.avail_in = _.input.length));
    do {
      if (
        (_.avail_out === 0 &&
          ((_.output = new L.Buf8(y)), (_.next_out = 0), (_.avail_out = y)),
        (c = p.inflate(_, P.Z_NO_FLUSH)),
        c === P.Z_NEED_DICT && s && (c = p.inflateSetDictionary(this.strm, s)),
        c === P.Z_BUF_ERROR && b === !0 && ((c = P.Z_OK), (b = !1)),
        c !== P.Z_STREAM_END && c !== P.Z_OK)
      )
        return (this.onEnd(c), (this.ended = !0), !1);
      (_.next_out &&
        (_.avail_out === 0 ||
          c === P.Z_STREAM_END ||
          (_.avail_in === 0 && (v === P.Z_FINISH || v === P.Z_SYNC_FLUSH))) &&
        (this.options.to === "string"
          ? ((h = Y.utf8border(_.output, _.next_out)),
            (n = _.next_out - h),
            (g = Y.buf2string(_.output, h)),
            (_.next_out = n),
            (_.avail_out = y - n),
            n && L.arraySet(_.output, _.output, h, n, 0),
            this.onData(g))
          : this.onData(L.shrinkBuf(_.output, _.next_out))),
        _.avail_in === 0 && _.avail_out === 0 && (b = !0));
    } while ((_.avail_in > 0 || _.avail_out === 0) && c !== P.Z_STREAM_END);
    return (
      c === P.Z_STREAM_END && (v = P.Z_FINISH),
      v === P.Z_FINISH
        ? ((c = p.inflateEnd(this.strm)),
          this.onEnd(c),
          (this.ended = !0),
          c === P.Z_OK)
        : (v === P.Z_SYNC_FLUSH && (this.onEnd(P.Z_OK), (_.avail_out = 0)), !0)
    );
  }),
    (t.prototype.onData = function (u) {
      this.chunks.push(u);
    }),
    (t.prototype.onEnd = function (u) {
      (u === P.Z_OK &&
        (this.options.to === "string"
          ? (this.result = this.chunks.join(""))
          : (this.result = L.flattenChunks(this.chunks))),
        (this.chunks = []),
        (this.err = u),
        (this.msg = this.strm.msg));
    }));
  function w(u, l) {
    var _ = new t(l);
    if ((_.push(u, !0), _.err)) throw _.msg || E[_.err];
    return _.result;
  }
  function d(u, l) {
    return ((l = l || {}), (l.raw = !0), w(u, l));
  }
  return (
    (tr.Inflate = t),
    (tr.inflate = w),
    (tr.inflateRaw = d),
    (tr.ungzip = w),
    tr
  );
}
var Sr, Xr;
function Gt() {
  if (Xr) return Sr;
  Xr = 1;
  var p = $e().assign,
    L = Mt(),
    Y = Ht(),
    P = ut(),
    E = {};
  return (p(E, L, Y, P), (Sr = E), Sr);
}
var Vr;
function It() {
  return (
    Vr ||
      ((Vr = 1),
      (function (p) {
        (function () {
          var L = {};
          p.exports = L;
          var Y;
          typeof Ot == "function" ? (Y = Gt()) : (Y = self.pako);
          function P() {
            typeof Rt > "u" && console.log.apply(console, arguments);
          }
          (function (E, G) {
            ((function () {
              var i =
                  typeof Symbol == "function" &&
                  typeof Symbol.iterator == "symbol"
                    ? function (w) {
                        return typeof w;
                      }
                    : function (w) {
                        return w &&
                          typeof Symbol == "function" &&
                          w.constructor === Symbol &&
                          w !== Symbol.prototype
                          ? "symbol"
                          : typeof w;
                      },
                r = (function () {
                  function w(d) {
                    this.message = "JPEG error: " + d;
                  }
                  return (
                    (w.prototype = Error()),
                    (w.prototype.name = "JpegError"),
                    (w.constructor = w)
                  );
                })(),
                t = (function () {
                  function w(d, u) {
                    ((this.message = d), (this.g = u));
                  }
                  return (
                    (w.prototype = Error()),
                    (w.prototype.name = "DNLMarkerError"),
                    (w.constructor = w)
                  );
                })();
              (function () {
                function w() {
                  ((this.M = null), (this.B = -1));
                }
                function d(s, c) {
                  for (var v = 0, h = [], n, g, b = 16; 0 < b && !s[b - 1];)
                    b--;
                  h.push({ children: [], index: 0 });
                  var k = h[0],
                    S;
                  for (n = 0; n < b; n++) {
                    for (g = 0; g < s[n]; g++) {
                      for (
                        k = h.pop(), k.children[k.index] = c[v];
                        0 < k.index;
                      )
                        k = h.pop();
                      for (k.index++, h.push(k); h.length <= n;)
                        (h.push((S = { children: [], index: 0 })),
                          (k.children[k.index] = S.children),
                          (k = S));
                      v++;
                    }
                    n + 1 < b &&
                      (h.push((S = { children: [], index: 0 })),
                      (k.children[k.index] = S.children),
                      (k = S));
                  }
                  return h[0].children;
                }
                function u(s, c, v, h, n, g, b, k, S) {
                  function D() {
                    if (0 < X) return (X--, (ie >> X) & 1);
                    if (((ie = s[c++]), ie === 255)) {
                      var Q = s[c++];
                      if (Q) {
                        if (Q === 220 && $) {
                          c += 2;
                          var te = (s[c++] << 8) | s[c++];
                          if (0 < te && te !== v.g)
                            throw new t(
                              "Found DNL marker (0xFFDC) while parsing scan data",
                              te,
                            );
                        }
                        throw new r(
                          "unexpected marker " + ((ie << 8) | Q).toString(16),
                        );
                      }
                    }
                    return ((X = 7), ie >>> 7);
                  }
                  function B(Q) {
                    for (;;) {
                      if (((Q = Q[D()]), typeof Q == "number")) return Q;
                      if ((typeof Q > "u" ? "undefined" : i(Q)) !== "object")
                        throw new r("invalid huffman sequence");
                    }
                  }
                  function m(Q) {
                    for (var te = 0; 0 < Q;) ((te = (te << 1) | D()), Q--);
                    return te;
                  }
                  function z(Q) {
                    if (Q === 1) return D() === 1 ? 1 : -1;
                    var te = m(Q);
                    return te >= 1 << (Q - 1) ? te : te + (-1 << Q) + 1;
                  }
                  function T(Q, te) {
                    var ue = B(Q.D);
                    for (
                      ue = ue === 0 ? 0 : z(ue), Q.a[te] = Q.m += ue, ue = 1;
                      64 > ue;
                    ) {
                      var we = B(Q.o),
                        ge = we & 15;
                      if (((we >>= 4), ge === 0)) {
                        if (15 > we) break;
                        ue += 16;
                      } else ((ue += we), (Q.a[te + y[ue]] = z(ge)), ue++);
                    }
                  }
                  function C(Q, te) {
                    var ue = B(Q.D);
                    ((ue = ue === 0 ? 0 : z(ue) << S), (Q.a[te] = Q.m += ue));
                  }
                  function I(Q, te) {
                    Q.a[te] |= D() << S;
                  }
                  function j(Q, te) {
                    if (0 < re) re--;
                    else
                      for (var ue = g; ue <= b;) {
                        var we = B(Q.o),
                          ge = we & 15;
                        if (((we >>= 4), ge === 0)) {
                          if (15 > we) {
                            re = m(we) + (1 << we) - 1;
                            break;
                          }
                          ue += 16;
                        } else
                          ((ue += we),
                            (Q.a[te + y[ue]] = z(ge) * (1 << S)),
                            ue++);
                      }
                  }
                  function V(Q, te) {
                    for (var ue = g, we = 0, ge; ue <= b;) {
                      ge = te + y[ue];
                      var De = 0 > Q.a[ge] ? -1 : 1;
                      switch (U) {
                        case 0:
                          if (
                            ((we = B(Q.o)),
                            (ge = we & 15),
                            (we >>= 4),
                            ge === 0)
                          )
                            15 > we
                              ? ((re = m(we) + (1 << we)), (U = 4))
                              : ((we = 16), (U = 1));
                          else {
                            if (ge !== 1) throw new r("invalid ACn encoding");
                            ((_e = z(ge)), (U = we ? 2 : 3));
                          }
                          continue;
                        case 1:
                        case 2:
                          Q.a[ge]
                            ? (Q.a[ge] += De * (D() << S))
                            : (we--, we === 0 && (U = U === 2 ? 3 : 0));
                          break;
                        case 3:
                          Q.a[ge]
                            ? (Q.a[ge] += De * (D() << S))
                            : ((Q.a[ge] = _e << S), (U = 0));
                          break;
                        case 4:
                          Q.a[ge] && (Q.a[ge] += De * (D() << S));
                      }
                      ue++;
                    }
                    U === 4 && (re--, re === 0 && (U = 0));
                  }
                  for (
                    var $ =
                        9 < arguments.length && arguments[9] !== void 0
                          ? arguments[9]
                          : !1,
                      Z = v.P,
                      H = c,
                      ie = 0,
                      X = 0,
                      re = 0,
                      U = 0,
                      _e,
                      fe = h.length,
                      le,
                      oe,
                      se,
                      be,
                      Re = v.S
                        ? g === 0
                          ? k === 0
                            ? C
                            : I
                          : k === 0
                            ? j
                            : V
                        : T,
                      ke = 0,
                      ve = fe === 1 ? h[0].c * h[0].l : Z * v.O,
                      Se,
                      Pe;
                    ke < ve;
                  ) {
                    var Oe = n ? Math.min(ve - ke, n) : ve;
                    for (le = 0; le < fe; le++) h[le].m = 0;
                    if (((re = 0), fe === 1)) {
                      var he = h[0];
                      for (be = 0; be < Oe; be++)
                        (Re(
                          he,
                          64 * ((he.c + 1) * ((ke / he.c) | 0) + (ke % he.c)),
                        ),
                          ke++);
                    } else
                      for (be = 0; be < Oe; be++) {
                        for (le = 0; le < fe; le++)
                          for (
                            he = h[le], Se = he.h, Pe = he.j, oe = 0;
                            oe < Pe;
                            oe++
                          )
                            for (se = 0; se < Se; se++)
                              Re(
                                he,
                                64 *
                                  ((he.c + 1) * (((ke / Z) | 0) * he.j + oe) +
                                    ((ke % Z) * he.h + se)),
                              );
                        ke++;
                      }
                    if (
                      ((X = 0),
                      (he = _(s, c)) &&
                        he.f &&
                        ((0, _util.warn)(
                          "decodeScan - unexpected MCU data, current marker is: " +
                            he.f,
                        ),
                        (c = he.offset)),
                      (he = he && he.F),
                      !he || 65280 >= he)
                    )
                      throw new r("marker was not found");
                    if (65488 <= he && 65495 >= he) c += 2;
                    else break;
                  }
                  return (
                    (he = _(s, c)) &&
                      he.f &&
                      ((0, _util.warn)(
                        "decodeScan - unexpected Scan data, current marker is: " +
                          he.f,
                      ),
                      (c = he.offset)),
                    c - H
                  );
                }
                function l(s, c) {
                  for (
                    var v = c.c, h = c.l, n = new Int16Array(64), g = 0;
                    g < h;
                    g++
                  )
                    for (var b = 0; b < v; b++) {
                      var k = 64 * ((c.c + 1) * g + b),
                        S = n,
                        D = c.G,
                        B = c.a;
                      if (!D)
                        throw new r("missing required Quantization Table.");
                      for (var m = 0; 64 > m; m += 8) {
                        var z = B[k + m],
                          T = B[k + m + 1],
                          C = B[k + m + 2],
                          I = B[k + m + 3],
                          j = B[k + m + 4],
                          V = B[k + m + 5],
                          $ = B[k + m + 6],
                          Z = B[k + m + 7];
                        if (((z *= D[m]), (T | C | I | j | V | $ | Z) === 0))
                          ((z = (5793 * z + 512) >> 10),
                            (S[m] = z),
                            (S[m + 1] = z),
                            (S[m + 2] = z),
                            (S[m + 3] = z),
                            (S[m + 4] = z),
                            (S[m + 5] = z),
                            (S[m + 6] = z),
                            (S[m + 7] = z));
                        else {
                          ((T *= D[m + 1]),
                            (C *= D[m + 2]),
                            (I *= D[m + 3]),
                            (j *= D[m + 4]),
                            (V *= D[m + 5]),
                            ($ *= D[m + 6]),
                            (Z *= D[m + 7]));
                          var H = (5793 * z + 128) >> 8,
                            ie = (5793 * j + 128) >> 8,
                            X = C,
                            re = $;
                          ((j = (2896 * (T - Z) + 128) >> 8),
                            (Z = (2896 * (T + Z) + 128) >> 8),
                            (I <<= 4),
                            (V <<= 4),
                            (H = (H + ie + 1) >> 1),
                            (ie = H - ie),
                            (z = (3784 * X + 1567 * re + 128) >> 8),
                            (X = (1567 * X - 3784 * re + 128) >> 8),
                            (re = z),
                            (j = (j + V + 1) >> 1),
                            (V = j - V),
                            (Z = (Z + I + 1) >> 1),
                            (I = Z - I),
                            (H = (H + re + 1) >> 1),
                            (re = H - re),
                            (ie = (ie + X + 1) >> 1),
                            (X = ie - X),
                            (z = (2276 * j + 3406 * Z + 2048) >> 12),
                            (j = (3406 * j - 2276 * Z + 2048) >> 12),
                            (Z = z),
                            (z = (799 * I + 4017 * V + 2048) >> 12),
                            (I = (4017 * I - 799 * V + 2048) >> 12),
                            (V = z),
                            (S[m] = H + Z),
                            (S[m + 7] = H - Z),
                            (S[m + 1] = ie + V),
                            (S[m + 6] = ie - V),
                            (S[m + 2] = X + I),
                            (S[m + 5] = X - I),
                            (S[m + 3] = re + j),
                            (S[m + 4] = re - j));
                        }
                      }
                      for (D = 0; 8 > D; ++D)
                        ((z = S[D]),
                          (T = S[D + 8]),
                          (C = S[D + 16]),
                          (I = S[D + 24]),
                          (j = S[D + 32]),
                          (V = S[D + 40]),
                          ($ = S[D + 48]),
                          (Z = S[D + 56]),
                          (T | C | I | j | V | $ | Z) === 0
                            ? ((z = (5793 * z + 8192) >> 14),
                              (z =
                                -2040 > z
                                  ? 0
                                  : 2024 <= z
                                    ? 255
                                    : (z + 2056) >> 4),
                              (B[k + D] = z),
                              (B[k + D + 8] = z),
                              (B[k + D + 16] = z),
                              (B[k + D + 24] = z),
                              (B[k + D + 32] = z),
                              (B[k + D + 40] = z),
                              (B[k + D + 48] = z),
                              (B[k + D + 56] = z))
                            : ((H = (5793 * z + 2048) >> 12),
                              (ie = (5793 * j + 2048) >> 12),
                              (X = C),
                              (re = $),
                              (j = (2896 * (T - Z) + 2048) >> 12),
                              (Z = (2896 * (T + Z) + 2048) >> 12),
                              (H = ((H + ie + 1) >> 1) + 4112),
                              (ie = H - ie),
                              (z = (3784 * X + 1567 * re + 2048) >> 12),
                              (X = (1567 * X - 3784 * re + 2048) >> 12),
                              (re = z),
                              (j = (j + V + 1) >> 1),
                              (V = j - V),
                              (Z = (Z + I + 1) >> 1),
                              (I = Z - I),
                              (H = (H + re + 1) >> 1),
                              (re = H - re),
                              (ie = (ie + X + 1) >> 1),
                              (X = ie - X),
                              (z = (2276 * j + 3406 * Z + 2048) >> 12),
                              (j = (3406 * j - 2276 * Z + 2048) >> 12),
                              (Z = z),
                              (z = (799 * I + 4017 * V + 2048) >> 12),
                              (I = (4017 * I - 799 * V + 2048) >> 12),
                              (V = z),
                              (z = H + Z),
                              (Z = H - Z),
                              (T = ie + V),
                              ($ = ie - V),
                              (C = X + I),
                              (V = X - I),
                              (I = re + j),
                              (j = re - j),
                              (z = 16 > z ? 0 : 4080 <= z ? 255 : z >> 4),
                              (T = 16 > T ? 0 : 4080 <= T ? 255 : T >> 4),
                              (C = 16 > C ? 0 : 4080 <= C ? 255 : C >> 4),
                              (I = 16 > I ? 0 : 4080 <= I ? 255 : I >> 4),
                              (j = 16 > j ? 0 : 4080 <= j ? 255 : j >> 4),
                              (V = 16 > V ? 0 : 4080 <= V ? 255 : V >> 4),
                              ($ = 16 > $ ? 0 : 4080 <= $ ? 255 : $ >> 4),
                              (Z = 16 > Z ? 0 : 4080 <= Z ? 255 : Z >> 4),
                              (B[k + D] = z),
                              (B[k + D + 8] = T),
                              (B[k + D + 16] = C),
                              (B[k + D + 24] = I),
                              (B[k + D + 32] = j),
                              (B[k + D + 40] = V),
                              (B[k + D + 48] = $),
                              (B[k + D + 56] = Z)));
                    }
                  return c.a;
                }
                function _(s, c) {
                  var v =
                      2 < arguments.length && arguments[2] !== void 0
                        ? arguments[2]
                        : c,
                    h = s.length - 1;
                  if (((v = v < c ? v : c), c >= h)) return null;
                  var n = (s[c] << 8) | s[c + 1];
                  if (65472 <= n && 65534 >= n)
                    return { f: null, F: n, offset: c };
                  for (
                    var g = (s[v] << 8) | s[v + 1];
                    !(65472 <= g && 65534 >= g);
                  ) {
                    if (++v >= h) return null;
                    g = (s[v] << 8) | s[v + 1];
                  }
                  return { f: n.toString(16), F: g, offset: v };
                }
                var y = new Uint8Array([
                  0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12,
                  19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28, 35,
                  42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
                  58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62,
                  63,
                ]);
                ((w.prototype = {
                  parse: function (s) {
                    function c() {
                      var X = (s[b] << 8) | s[b + 1];
                      return ((b += 2), X);
                    }
                    function v() {
                      var X = c();
                      X = b + X - 2;
                      var re = _(s, X, b);
                      return (
                        re &&
                          re.f &&
                          ((0, _util.warn)(
                            "readDataBlock - incorrect length, current marker is: " +
                              re.f,
                          ),
                          (X = re.offset)),
                        (X = s.subarray(b, X)),
                        (b += X.length),
                        X
                      );
                    }
                    function h(X) {
                      for (
                        var re = Math.ceil(X.v / 8 / X.s),
                          U = Math.ceil(X.g / 8 / X.u),
                          _e = 0;
                        _e < X.b.length;
                        _e++
                      ) {
                        H = X.b[_e];
                        var fe = Math.ceil((Math.ceil(X.v / 8) * H.h) / X.s),
                          le = Math.ceil((Math.ceil(X.g / 8) * H.j) / X.u);
                        ((H.a = new Int16Array(64 * U * H.j * (re * H.h + 1))),
                          (H.c = fe),
                          (H.l = le));
                      }
                      ((X.P = re), (X.O = U));
                    }
                    var n = (
                        1 < arguments.length && arguments[1] !== void 0
                          ? arguments[1]
                          : {}
                      ).N,
                      g = n === void 0 ? null : n,
                      b = 0,
                      k = null,
                      S = 0;
                    n = [];
                    var D = [],
                      B = [],
                      m = c();
                    if (m !== 65496) throw new r("SOI not found");
                    for (m = c(); m !== 65497;) {
                      switch (m) {
                        case 65504:
                        case 65505:
                        case 65506:
                        case 65507:
                        case 65508:
                        case 65509:
                        case 65510:
                        case 65511:
                        case 65512:
                        case 65513:
                        case 65514:
                        case 65515:
                        case 65516:
                        case 65517:
                        case 65518:
                        case 65519:
                        case 65534:
                          var z = v();
                          m === 65518 &&
                            z[0] === 65 &&
                            z[1] === 100 &&
                            z[2] === 111 &&
                            z[3] === 98 &&
                            z[4] === 101 &&
                            (k = {
                              version: (z[5] << 8) | z[6],
                              Y: (z[7] << 8) | z[8],
                              Z: (z[9] << 8) | z[10],
                              W: z[11],
                            });
                          break;
                        case 65499:
                          m = c() + b - 2;
                          for (var T; b < m;) {
                            var C = s[b++],
                              I = new Uint16Array(64);
                            if (C >> 4 === 0)
                              for (z = 0; 64 > z; z++)
                                ((T = y[z]), (I[T] = s[b++]));
                            else if (C >> 4 === 1)
                              for (z = 0; 64 > z; z++)
                                ((T = y[z]), (I[T] = c()));
                            else throw new r("DQT - invalid table spec");
                            n[C & 15] = I;
                          }
                          break;
                        case 65472:
                        case 65473:
                        case 65474:
                          if (j)
                            throw new r("Only single frame JPEGs supported");
                          c();
                          var j = {};
                          for (
                            j.X = m === 65473,
                              j.S = m === 65474,
                              j.precision = s[b++],
                              m = c(),
                              j.g = g || m,
                              j.v = c(),
                              j.b = [],
                              j.C = {},
                              z = s[b++],
                              m = I = C = 0;
                            m < z;
                            m++
                          ) {
                            T = s[b];
                            var V = s[b + 1] >> 4,
                              $ = s[b + 1] & 15;
                            (C < V && (C = V),
                              I < $ && (I = $),
                              (V = j.b.push({
                                h: V,
                                j: $,
                                T: s[b + 2],
                                G: null,
                              })),
                              (j.C[T] = V - 1),
                              (b += 3));
                          }
                          ((j.s = C), (j.u = I), h(j));
                          break;
                        case 65476:
                          for (T = c(), m = 2; m < T;) {
                            for (
                              C = s[b++], I = new Uint8Array(16), z = V = 0;
                              16 > z;
                              z++, b++
                            )
                              V += I[z] = s[b];
                            for ($ = new Uint8Array(V), z = 0; z < V; z++, b++)
                              $[z] = s[b];
                            ((m += 17 + V),
                              ((C >> 4 === 0 ? B : D)[C & 15] = d(I, $)));
                          }
                          break;
                        case 65501:
                          c();
                          var Z = c();
                          break;
                        case 65498:
                          for (
                            z = ++S === 1 && !g, c(), C = s[b++], T = [], m = 0;
                            m < C;
                            m++
                          ) {
                            I = j.C[s[b++]];
                            var H = j.b[I];
                            ((I = s[b++]),
                              (H.D = B[I >> 4]),
                              (H.o = D[I & 15]),
                              T.push(H));
                          }
                          ((m = s[b++]), (C = s[b++]), (I = s[b++]));
                          try {
                            var ie = u(s, b, j, T, Z, m, C, I >> 4, I & 15, z);
                            b += ie;
                          } catch (X) {
                            if (X instanceof t)
                              return (
                                (0, _util.warn)(
                                  'Attempting to re-parse JPEG image using "scanLines" parameter found in DNL marker (0xFFDC) segment.',
                                ),
                                this.parse(s, { N: X.g })
                              );
                            throw X;
                          }
                          break;
                        case 65500:
                          b += 4;
                          break;
                        case 65535:
                          s[b] !== 255 && b--;
                          break;
                        default:
                          if (
                            s[b - 3] === 255 &&
                            192 <= s[b - 2] &&
                            254 >= s[b - 2]
                          )
                            b -= 3;
                          else if ((z = _(s, b - 2)) && z.f)
                            ((0, _util.warn)(
                              "JpegImage.parse - unexpected data, current marker is: " +
                                z.f,
                            ),
                              (b = z.offset));
                          else throw new r("unknown marker " + m.toString(16));
                      }
                      m = c();
                    }
                    for (
                      this.width = j.v,
                        this.height = j.g,
                        this.A = k,
                        this.b = [],
                        m = 0;
                      m < j.b.length;
                      m++
                    )
                      ((H = j.b[m]),
                        (Z = n[H.T]) && (H.G = Z),
                        this.b.push({
                          R: l(j, H),
                          U: H.h / j.s,
                          V: H.j / j.u,
                          c: H.c,
                          l: H.l,
                        }));
                    this.i = this.b.length;
                  },
                  L: function (s, c) {
                    var v = this.width / s,
                      h = this.height / c,
                      n,
                      g,
                      b = this.b.length,
                      k = s * c * b,
                      S = new Uint8ClampedArray(k),
                      D = new Uint32Array(s);
                    for (g = 0; g < b; g++) {
                      var B = this.b[g],
                        m = B.U * v,
                        z = B.V * h,
                        T = g,
                        C = B.R,
                        I = (B.c + 1) << 3;
                      for (n = 0; n < s; n++)
                        ((B = 0 | (n * m)),
                          (D[n] = ((B & 4294967288) << 3) | (B & 7)));
                      for (m = 0; m < c; m++)
                        for (
                          B = 0 | (m * z),
                            B = (I * (B & 4294967288)) | ((B & 7) << 3),
                            n = 0;
                          n < s;
                          n++
                        )
                          ((S[T] = C[B + D[n]]), (T += b));
                    }
                    if ((h = this.M))
                      for (g = 0; g < k;)
                        for (v = B = 0; B < b; B++, g++, v += 2)
                          S[g] = ((S[g] * h[v]) >> 8) + h[v + 1];
                    return S;
                  },
                  w: function () {
                    return this.A
                      ? !!this.A.W
                      : this.i === 3
                        ? this.B !== 0
                        : this.B === 1;
                  },
                  I: function (s) {
                    for (var c, v, h, n = 0, g = s.length; n < g; n += 3)
                      ((c = s[n]),
                        (v = s[n + 1]),
                        (h = s[n + 2]),
                        (s[n] = c - 179.456 + 1.402 * h),
                        (s[n + 1] = c + 135.459 - 0.344 * v - 0.714 * h),
                        (s[n + 2] = c - 226.816 + 1.772 * v));
                    return s;
                  },
                  K: function (s) {
                    for (
                      var c, v, h, n, g = 0, b = 0, k = s.length;
                      b < k;
                      b += 4
                    )
                      ((c = s[b]),
                        (v = s[b + 1]),
                        (h = s[b + 2]),
                        (n = s[b + 3]),
                        (s[g++] =
                          -122.67195406894 +
                          v *
                            (-660635669420364e-19 * v +
                              0.000437130475926232 * h -
                              54080610064599e-18 * c +
                              0.00048449797120281 * n -
                              0.154362151871126) +
                          h *
                            (-0.000957964378445773 * h +
                              0.000817076911346625 * c -
                              0.00477271405408747 * n +
                              1.53380253221734) +
                          c *
                            (0.000961250184130688 * c -
                              0.00266257332283933 * n +
                              0.48357088451265) +
                          n * (-0.000336197177618394 * n + 0.484791561490776)),
                        (s[g++] =
                          107.268039397724 +
                          v *
                            (219927104525741e-19 * v -
                              0.000640992018297945 * h +
                              0.000659397001245577 * c +
                              0.000426105652938837 * n -
                              0.176491792462875) +
                          h *
                            (-0.000778269941513683 * h +
                              0.00130872261408275 * c +
                              0.000770482631801132 * n -
                              0.151051492775562) +
                          c *
                            (0.00126935368114843 * c -
                              0.00265090189010898 * n +
                              0.25802910206845) +
                          n * (-0.000318913117588328 * n - 0.213742400323665)),
                        (s[g++] =
                          -20.810012546947 +
                          v *
                            (-0.000570115196973677 * v -
                              263409051004589e-19 * h +
                              0.0020741088115012 * c -
                              0.00288260236853442 * n +
                              0.814272968359295) +
                          h *
                            (-153496057440975e-19 * h -
                              0.000132689043961446 * c +
                              0.000560833691242812 * n -
                              0.195152027534049) +
                          c *
                            (0.00174418132927582 * c -
                              0.00255243321439347 * n +
                              0.116935020465145) +
                          n * (-0.000343531996510555 * n + 0.24165260232407)));
                    return s.subarray(0, g);
                  },
                  J: function (s) {
                    for (var c, v, h, n = 0, g = s.length; n < g; n += 4)
                      ((c = s[n]),
                        (v = s[n + 1]),
                        (h = s[n + 2]),
                        (s[n] = 434.456 - c - 1.402 * h),
                        (s[n + 1] = 119.541 - c + 0.344 * v + 0.714 * h),
                        (s[n + 2] = 481.816 - c - 1.772 * v));
                    return s;
                  },
                  H: function (s) {
                    for (
                      var c, v, h, n, g = 0, b = 1 / 255, k = 0, S = s.length;
                      k < S;
                      k += 4
                    )
                      ((c = s[k] * b),
                        (v = s[k + 1] * b),
                        (h = s[k + 2] * b),
                        (n = s[k + 3] * b),
                        (s[g++] =
                          255 +
                          c *
                            (-4.387332384609988 * c +
                              54.48615194189176 * v +
                              18.82290502165302 * h +
                              212.25662451639585 * n -
                              285.2331026137004) +
                          v *
                            (1.7149763477362134 * v -
                              5.6096736904047315 * h -
                              17.873870861415444 * n -
                              5.497006427196366) +
                          h *
                            (-2.5217340131683033 * h -
                              21.248923337353073 * n +
                              17.5119270841813) -
                          n * (21.86122147463605 * n + 189.48180835922747)),
                        (s[g++] =
                          255 +
                          c *
                            (8.841041422036149 * c +
                              60.118027045597366 * v +
                              6.871425592049007 * h +
                              31.159100130055922 * n -
                              79.2970844816548) +
                          v *
                            (-15.310361306967817 * v +
                              17.575251261109482 * h +
                              131.35250912493976 * n -
                              190.9453302588951) +
                          h *
                            (4.444339102852739 * h +
                              9.8632861493405 * n -
                              24.86741582555878) -
                          n * (20.737325471181034 * n + 187.80453709719578)),
                        (s[g++] =
                          255 +
                          c *
                            (0.8842522430003296 * c +
                              8.078677503112928 * v +
                              30.89978309703729 * h -
                              0.23883238689178934 * n -
                              14.183576799673286) +
                          v *
                            (10.49593273432072 * v +
                              63.02378494754052 * h +
                              50.606957656360734 * n -
                              112.23884253719248) +
                          h *
                            (0.03296041114873217 * h +
                              115.60384449646641 * n -
                              193.58209356861505) -
                          n * (22.33816807309886 * n + 180.12613974708367)));
                    return s.subarray(0, g);
                  },
                  getData: function (s, c, v) {
                    if (4 < this.i) throw new r("Unsupported color mode");
                    if (((s = this.L(s, c)), this.i === 1 && v)) {
                      ((v = s.length), (c = new Uint8ClampedArray(3 * v)));
                      for (var h = 0, n = 0; n < v; n++) {
                        var g = s[n];
                        ((c[h++] = g), (c[h++] = g), (c[h++] = g));
                      }
                      return c;
                    }
                    if (this.i === 3 && this.w()) return this.I(s);
                    if (this.i === 4) {
                      if (this.w()) return v ? this.K(s) : this.J(s);
                      if (v) return this.H(s);
                    }
                    return s;
                  },
                }),
                  (E.JpegDecoder = w));
              })();
            })(),
              (E.encodeImage = function (i, r, t, w) {
                var d = {
                  t256: [r],
                  t257: [t],
                  t258: [8, 8, 8, 8],
                  t259: [1],
                  t262: [2],
                  t273: [1e3],
                  t277: [4],
                  t278: [t],
                  t279: [r * t * 4],
                  t282: [1],
                  t283: [1],
                  t284: [1],
                  t286: [0],
                  t287: [0],
                  t296: [1],
                  t305: ["Photopea (UTIF.js)"],
                  t338: [1],
                };
                if (w) for (var u in w) d[u] = w[u];
                for (
                  var l = new Uint8Array(E.encode([d])),
                    _ = new Uint8Array(i),
                    y = new Uint8Array(1e3 + r * t * 4),
                    u = 0;
                  u < l.length;
                  u++
                )
                  y[u] = l[u];
                for (var u = 0; u < _.length; u++) y[1e3 + u] = _[u];
                return y.buffer;
              }),
              (E.encode = function (i) {
                var r = new Uint8Array(2e4),
                  t = 4,
                  w = E._binBE;
                ((r[0] = 77), (r[1] = 77), (r[3] = 42));
                var d = 8;
                (w.writeUint(r, t, d), (t += 4));
                for (var u = 0; u < i.length; u++) {
                  var l = E._writeIFD(w, r, d, i[u]);
                  ((d = l[1]), u < i.length - 1 && w.writeUint(r, l[0], d));
                }
                return r.slice(0, d).buffer;
              }),
              (E.decode = function (i) {
                E.decode._decodeG3.allow2D = null;
                var r = new Uint8Array(i),
                  t = 0,
                  w = E._binBE.readASCII(r, t, 2);
                t += 2;
                var d = w == "II" ? E._binLE : E._binBE;
                (d.readUshort(r, t), (t += 2));
                var u = d.readUint(r, t);
                t += 4;
                for (var l = []; ;) {
                  var _ = E._readIFD(d, r, u, l, 0, !1);
                  if (((u = d.readUint(r, _)), u == 0)) break;
                }
                return l;
              }),
              (E.decodeImage = function (i, r, t) {
                var w = new Uint8Array(i),
                  d = E._binBE.readASCII(w, 0, 2);
                if (r.t256 != null) {
                  ((r.isLE = d == "II"),
                    (r.width = r.t256[0]),
                    (r.height = r.t257[0]));
                  var u = r.t259 ? r.t259[0] : 1,
                    l = r.t266 ? r.t266[0] : 1;
                  r.t284 &&
                    r.t284[0] == 2 &&
                    P("PlanarConfiguration 2 should not be used!");
                  var _;
                  (r.t258
                    ? (_ = Math.min(32, r.t258[0]) * r.t258.length)
                    : (_ = r.t277 ? r.t277[0] : 1),
                    u == 1 &&
                      r.t279 != null &&
                      r.t278 &&
                      r.t262[0] == 32803 &&
                      (_ = Math.round(
                        (r.t279[0] * 8) / (r.width * r.t278[0]),
                      )));
                  var y = Math.ceil((r.width * _) / 8) * 8,
                    s = r.t273;
                  s == null && (s = r.t324);
                  var c = r.t279;
                  (u == 1 && s.length == 1 && (c = [r.height * (y >>> 3)]),
                    c == null && (c = r.t325));
                  var v = new Uint8Array(r.height * (y >>> 3)),
                    h = 0;
                  if (r.t322 != null) {
                    for (
                      var n = r.t322[0],
                        g = r.t323[0],
                        b = Math.floor((r.width + n - 1) / n),
                        k = Math.floor((r.height + g - 1) / g),
                        S = new Uint8Array(Math.ceil((n * g * _) / 8) | 0),
                        D = 0;
                      D < k;
                      D++
                    )
                      for (var B = 0; B < b; B++) {
                        for (var m = D * b + B, z = 0; z < S.length; z++)
                          S[z] = 0;
                        (E.decode._decompress(r, t, w, s[m], c[m], u, S, 0, l),
                          u == 6
                            ? (v = S)
                            : E._copyTile(
                                S,
                                Math.ceil((n * _) / 8) | 0,
                                g,
                                v,
                                Math.ceil((r.width * _) / 8) | 0,
                                r.height,
                                Math.ceil((B * n * _) / 8) | 0,
                                D * g,
                              ));
                      }
                    h = v.length * 8;
                  } else {
                    var T = r.t278 ? r.t278[0] : r.height;
                    T = Math.min(T, r.height);
                    for (var m = 0; m < s.length; m++)
                      (E.decode._decompress(
                        r,
                        t,
                        w,
                        s[m],
                        c[m],
                        u,
                        v,
                        Math.ceil(h / 8) | 0,
                        l,
                      ),
                        (h += y * T));
                    h = Math.min(h, v.length * 8);
                  }
                  r.data = new Uint8Array(v.buffer, 0, Math.ceil(h / 8) | 0);
                }
              }),
              (E.decode._decompress = function (i, r, t, w, d, u, l, _, y) {
                if (u == 1 || (d == l.length && u != 32767))
                  for (var s = 0; s < d; s++) l[_ + s] = t[w + s];
                else if (u == 3) E.decode._decodeG3(t, w, d, l, _, i.width, y);
                else if (u == 4) E.decode._decodeG4(t, w, d, l, _, i.width, y);
                else if (u == 5) E.decode._decodeLZW(t, w, l, _);
                else if (u == 6) E.decode._decodeOldJPEG(i, t, w, d, l, _);
                else if (u == 7) E.decode._decodeNewJPEG(i, t, w, d, l, _);
                else if (u == 8)
                  for (
                    var c = new Uint8Array(t.buffer, w, d),
                      v = G.inflate(c),
                      h = 0;
                    h < v.length;
                    h++
                  )
                    l[_ + h] = v[h];
                else
                  u == 32767
                    ? E.decode._decodeARW(i, t, w, d, l, _)
                    : u == 32773
                      ? E.decode._decodePackBits(t, w, d, l, _)
                      : u == 32809
                        ? E.decode._decodeThunder(t, w, d, l, _)
                        : u == 34713
                          ? E.decode._decodeNikon(i, r, t, w, d, l, _)
                          : P("Unknown compression", u);
                var n = i.t258 ? Math.min(32, i.t258[0]) : 1,
                  g = i.t277 ? i.t277[0] : 1,
                  b = (n * g) >>> 3,
                  k = i.t278 ? i.t278[0] : i.height,
                  S = Math.ceil((n * g * i.width) / 8);
                if (n == 16 && !i.isLE && i.t33422 == null)
                  for (var D = 0; D < k; D++)
                    for (var B = _ + D * S, m = 1; m < S; m += 2) {
                      var z = l[B + m];
                      ((l[B + m] = l[B + m - 1]), (l[B + m - 1] = z));
                    }
                if (i.t317 && i.t317[0] == 2)
                  for (var D = 0; D < k; D++) {
                    var T = _ + D * S;
                    if (n == 16)
                      for (var s = b; s < S; s += 2) {
                        var C =
                          ((l[T + s + 1] << 8) | l[T + s]) +
                          ((l[T + s - b + 1] << 8) | l[T + s - b]);
                        ((l[T + s] = C & 255),
                          (l[T + s + 1] = (C >>> 8) & 255));
                      }
                    else if (g == 3)
                      for (var s = 3; s < S; s += 3)
                        ((l[T + s] = (l[T + s] + l[T + s - 3]) & 255),
                          (l[T + s + 1] = (l[T + s + 1] + l[T + s - 2]) & 255),
                          (l[T + s + 2] = (l[T + s + 2] + l[T + s - 1]) & 255));
                    else
                      for (var s = b; s < S; s++)
                        l[T + s] = (l[T + s] + l[T + s - b]) & 255;
                  }
              }),
              (E.decode._ljpeg_diff = function (i, r, t) {
                var w = E.decode._getbithuff,
                  d,
                  u;
                return (
                  (d = w(i, r, t[0], t)),
                  (u = w(i, r, d, 0)),
                  (u & (1 << (d - 1))) == 0 && (u -= (1 << d) - 1),
                  u
                );
              }),
              (E.decode._decodeARW = function (i, r, t, w, d, u) {
                var l = i.t256[0],
                  _ = i.t257[0],
                  y = i.t258[0],
                  s = i.isLE ? E._binLE : E._binBE,
                  c = l * _ == w || l * _ * 1.5 == w;
                if (!c) {
                  _ += 8;
                  var v = [t, 0, 0, 0],
                    h = new Uint16Array(32770),
                    n = [
                      3857, 3856, 3599, 3342, 3085, 2828, 2571, 2314, 2057,
                      1800, 1543, 1286, 1029, 772, 771, 768, 514, 513,
                    ],
                    U,
                    g,
                    b,
                    j,
                    I,
                    k = 0,
                    S = E.decode._ljpeg_diff;
                  for (h[0] = 15, b = U = 0; U < 18; U++)
                    for (var D = 32768 >>> (n[U] >>> 8), g = 0; g < D; g++)
                      h[++b] = n[U];
                  for (j = l; j--;)
                    for (I = 0; I < _ + 1; I += 2)
                      if ((I == _ && (I = 1), (k += S(r, v, h)), I < _)) {
                        var B = k & 4095;
                        E.decode._putsF(d, (I * l + j) * y, B << (16 - y));
                      }
                  return;
                }
                if (l * _ * 1.5 == w) {
                  for (var U = 0; U < w; U += 3) {
                    var m = r[t + U + 0],
                      z = r[t + U + 1],
                      T = r[t + U + 2];
                    ((d[u + U] = (z << 4) | (m >>> 4)),
                      (d[u + U + 1] = (m << 4) | (T >>> 4)),
                      (d[u + U + 2] = (T << 4) | (z >>> 4)));
                  }
                  return;
                }
                var C = new Uint16Array(16),
                  I,
                  j,
                  V,
                  $,
                  Z,
                  H,
                  ie,
                  X,
                  re,
                  U,
                  _e,
                  fe = new Uint8Array(l + 1);
                for (I = 0; I < _; I++) {
                  for (var le = 0; le < l; le++) fe[le] = r[t++];
                  for (_e = 0, j = 0; j < l - 30; _e += 16) {
                    for (
                      $ = 2047 & (V = s.readUint(fe, _e)),
                        Z = 2047 & (V >>> 11),
                        H = 15 & (V >>> 22),
                        ie = 15 & (V >>> 26),
                        X = 0;
                      X < 4 && 128 << X <= $ - Z;
                      X++
                    );
                    for (re = 30, U = 0; U < 16; U++)
                      U == H
                        ? (C[U] = $)
                        : U == ie
                          ? (C[U] = Z)
                          : ((C[U] =
                              (((s.readUshort(fe, _e + (re >> 3)) >>>
                                (re & 7)) &
                                127) <<
                                X) +
                              Z),
                            C[U] > 2047 && (C[U] = 2047),
                            (re += 7));
                    for (U = 0; U < 16; U++, j += 2) {
                      var B = C[U] << 1;
                      E.decode._putsF(d, (I * l + j) * y, B << (16 - y));
                    }
                    j -= j & 1 ? 1 : 31;
                  }
                }
              }),
              (E.decode._decodeNikon = function (i, r, t, w, d, u, l) {
                var _ = [
                    [
                      0, 0, 1, 5, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0, 0, 0, 0, 5, 4,
                      3, 6, 2, 7, 1, 0, 8, 9, 11, 10, 12,
                    ],
                    [
                      0, 0, 1, 5, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0, 0, 0, 0, 57, 90,
                      56, 39, 22, 5, 4, 3, 2, 1, 0, 11, 12, 12,
                    ],
                    [
                      0, 0, 1, 4, 2, 3, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 4,
                      6, 3, 7, 2, 8, 1, 9, 0, 10, 11, 12,
                    ],
                    [
                      0, 0, 1, 4, 3, 1, 1, 1, 1, 1, 2, 0, 0, 0, 0, 0, 0, 5, 6,
                      4, 7, 8, 3, 9, 2, 1, 0, 10, 11, 12, 13, 14,
                    ],
                    [
                      0, 0, 1, 5, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0, 0, 0, 8, 92,
                      75, 58, 41, 7, 6, 5, 4, 3, 2, 1, 0, 13, 14,
                    ],
                    [
                      0, 0, 1, 4, 2, 2, 3, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 7, 6,
                      8, 5, 9, 4, 10, 3, 11, 12, 2, 0, 1, 13, 14,
                    ],
                  ],
                  y = i.t256[0],
                  s = i.t257[0],
                  c = i.t258[0],
                  v = 0,
                  h = 0,
                  n = E.decode._make_decoder,
                  g = E.decode._getbithuff,
                  b = r[0].exifIFD.makerNote,
                  k = b.t150 ? b.t150 : b.t140,
                  S = 0,
                  D = k[S++],
                  B = k[S++];
                ((D == 73 || B == 88) && (S += 2110),
                  D == 70 && (v = 2),
                  c == 14 && (v += 3));
                for (
                  var m = [
                      [0, 0],
                      [0, 0],
                    ],
                    z = i.isLE ? E._binLE : E._binBE,
                    V = 0;
                  V < 2;
                  V++
                )
                  for (var T = 0; T < 2; T++)
                    ((m[V][T] = z.readShort(k, S)), (S += 2));
                var C = (1 << c) & 32767,
                  I = 0,
                  j = z.readShort(k, S);
                ((S += 2),
                  j > 1 && (I = Math.floor(C / (j - 1))),
                  D == 68 && B == 32 && I > 0 && (h = z.readShort(k, 562)));
                var V,
                  $,
                  Z,
                  H,
                  ie,
                  X,
                  re = [0, 0],
                  U = n(_[v]),
                  _e = [w, 0, 0, 0];
                for ($ = 0; $ < s; $++)
                  for (h && $ == h && (U = n(_[v + 1])), Z = 0; Z < y; Z++) {
                    ((V = g(t, _e, U[0], U)),
                      (H = V & 15),
                      (ie = V >>> 4),
                      (X = (((g(t, _e, H - ie, 0) << 1) + 1) << ie) >>> 1),
                      (X & (1 << (H - 1))) == 0 &&
                        (X -= (1 << H) - (ie == 0 ? 1 : 0)),
                      Z < 2 ? (re[Z] = m[$ & 1][Z] += X) : (re[Z & 1] += X));
                    var fe = Math.min(Math.max(re[Z & 1], 0), (1 << c) - 1),
                      le = ($ * y + Z) * c;
                    E.decode._putsF(u, le, fe << (16 - c));
                  }
              }),
              (E.decode._putsF = function (i, r, t) {
                t = t << (8 - (r & 7));
                var w = r >>> 3;
                ((i[w] |= t >>> 16), (i[w + 1] |= t >>> 8), (i[w + 2] |= t));
              }),
              (E.decode._getbithuff = function (i, r, t, w) {
                var d = 0;
                E.decode._get_byte;
                var u,
                  l = r[0],
                  _ = r[1],
                  y = r[2],
                  s = r[3];
                if (t == 0 || y < 0) return 0;
                for (; !s && y < t && (u = i[l++]) != -1 && !(s = d);)
                  ((_ = (_ << 8) + u), (y += 8));
                if (
                  ((u = (_ << (32 - y)) >>> (32 - t)),
                  w ? ((y -= w[u + 1] >>> 8), (u = w[u + 1] & 255)) : (y -= t),
                  y < 0)
                )
                  throw "e";
                return ((r[0] = l), (r[1] = _), (r[2] = y), (r[3] = s), u);
              }),
              (E.decode._make_decoder = function (i) {
                var r,
                  t,
                  w,
                  d,
                  u,
                  l = [];
                for (r = 16; r != 0 && !i[r]; r--);
                var _ = 17;
                for (l[0] = r, w = t = 1; t <= r; t++)
                  for (d = 0; d < i[t]; d++, ++_)
                    for (u = 0; u < 1 << (r - t); u++)
                      w <= 1 << r && (l[w++] = (t << 8) | i[_]);
                return l;
              }),
              (E.decode._decodeNewJPEG = function (i, r, t, w, d, u) {
                var l = i.t347,
                  _ = l ? l.length : 0,
                  y = new Uint8Array(_ + w);
                if (l) {
                  for (
                    var s = 216, c = 217, v = 0, h = 0;
                    h < _ - 1 && !(l[h] == 255 && l[h + 1] == c);
                    h++
                  )
                    y[v++] = l[h];
                  var n = r[t],
                    g = r[t + 1];
                  (n != 255 || g != s) && ((y[v++] = n), (y[v++] = g));
                  for (var h = 2; h < w; h++) y[v++] = r[t + h];
                } else for (var h = 0; h < w; h++) y[h] = r[t + h];
                if (i.t262[0] == 32803 || i.t262[0] == 34892) {
                  var b = i.t258[0],
                    k = E.LosslessJpegDecode(y),
                    S = k.length;
                  if (b == 16)
                    if (i.isLE)
                      for (var h = 0; h < S; h++)
                        ((d[u + (h << 1)] = k[h] & 255),
                          (d[u + (h << 1) + 1] = k[h] >>> 8));
                    else
                      for (var h = 0; h < S; h++)
                        ((d[u + (h << 1)] = k[h] >>> 8),
                          (d[u + (h << 1) + 1] = k[h] & 255));
                  else if (b == 14 || b == 12)
                    for (var D = 16 - b, h = 0; h < S; h++)
                      E.decode._putsF(d, h * b, k[h] << D);
                  else throw new Error("unsupported bit depth " + b);
                } else {
                  var B = new E.JpegDecoder();
                  B.parse(y);
                  for (
                    var m = B.getData(B.width, B.height), h = 0;
                    h < m.length;
                    h++
                  )
                    d[u + h] = m[h];
                }
                i.t262[0] == 6 && (i.t262[0] = 2);
              }),
              (E.decode._decodeOldJPEGInit = function (i, r, t, w) {
                var d = 216,
                  u = 219,
                  l = 196,
                  _ = 221,
                  y = 192,
                  s = 218,
                  c = 0,
                  v = 0,
                  h,
                  n,
                  g = !1,
                  b,
                  k,
                  S,
                  D = i.t513,
                  B = D ? D[0] : 0,
                  m = i.t514,
                  z = m ? m[0] : 0,
                  T = i.t324 || i.t273 || D,
                  C = i.t530,
                  I = 0,
                  j = 0,
                  V = i.t277 ? i.t277[0] : 1,
                  $ = i.t515;
                if ((T && ((v = T[0]), (g = T.length > 1)), !g)) {
                  if (r[t] == 255 && r[t + 1] == d) return { jpegOffset: t };
                  if (
                    D != null &&
                    (r[t + B] == 255 && r[t + B + 1] == d
                      ? (c = t + B)
                      : P("JPEGInterchangeFormat does not point to SOI"),
                    m == null
                      ? P("JPEGInterchangeFormatLength field is missing")
                      : (B >= v || B + z <= v) &&
                        P("JPEGInterchangeFormatLength field value is invalid"),
                    c != null)
                  )
                    return { jpegOffset: c };
                }
                if (
                  (C != null && ((I = C[0]), (j = C[1])),
                  D != null && m != null)
                )
                  if (z >= 2 && B + z <= v) {
                    for (
                      r[t + B + z - 2] == 255 && r[t + B + z - 1] == d
                        ? (h = new Uint8Array(z - 2))
                        : (h = new Uint8Array(z)),
                        b = 0;
                      b < h.length;
                      b++
                    )
                      h[b] = r[t + B + b];
                    P(
                      "Incorrect JPEG interchange format: using JPEGInterchangeFormat offset to derive tables",
                    );
                  } else
                    P(
                      "JPEGInterchangeFormat+JPEGInterchangeFormatLength > offset to first strip or tile",
                    );
                if (h == null) {
                  var Z = 0,
                    H = [];
                  ((H[Z++] = 255), (H[Z++] = d));
                  var ie = i.t519;
                  if (ie == null) throw new Error("JPEGQTables tag is missing");
                  for (b = 0; b < ie.length; b++)
                    for (
                      H[Z++] = 255,
                        H[Z++] = u,
                        H[Z++] = 0,
                        H[Z++] = 67,
                        H[Z++] = b,
                        k = 0;
                      k < 64;
                      k++
                    )
                      H[Z++] = r[t + ie[b] + k];
                  for (S = 0; S < 2; S++) {
                    var X = i[S == 0 ? "t520" : "t521"];
                    if (X == null)
                      throw new Error(
                        (S == 0 ? "JPEGDCTables" : "JPEGACTables") +
                          " tag is missing",
                      );
                    for (b = 0; b < X.length; b++) {
                      ((H[Z++] = 255), (H[Z++] = l));
                      var re = 19;
                      for (k = 0; k < 16; k++) re += r[t + X[b] + k];
                      for (
                        H[Z++] = re >>> 8,
                          H[Z++] = re & 255,
                          H[Z++] = b | (S << 4),
                          k = 0;
                        k < 16;
                        k++
                      )
                        H[Z++] = r[t + X[b] + k];
                      for (k = 0; k < re; k++) H[Z++] = r[t + X[b] + 16 + k];
                    }
                  }
                  if (
                    ((H[Z++] = 255),
                    (H[Z++] = y),
                    (H[Z++] = 0),
                    (H[Z++] = 8 + 3 * V),
                    (H[Z++] = 8),
                    (H[Z++] = (i.height >>> 8) & 255),
                    (H[Z++] = i.height & 255),
                    (H[Z++] = (i.width >>> 8) & 255),
                    (H[Z++] = i.width & 255),
                    (H[Z++] = V),
                    V == 1)
                  )
                    ((H[Z++] = 1), (H[Z++] = 17), (H[Z++] = 0));
                  else
                    for (b = 0; b < 3; b++)
                      ((H[Z++] = b + 1),
                        (H[Z++] = b != 0 ? 17 : ((I & 15) << 4) | (j & 15)),
                        (H[Z++] = b));
                  ($ != null &&
                    $[0] != 0 &&
                    ((H[Z++] = 255),
                    (H[Z++] = _),
                    (H[Z++] = 0),
                    (H[Z++] = 4),
                    (H[Z++] = ($[0] >>> 8) & 255),
                    (H[Z++] = $[0] & 255)),
                    (h = new Uint8Array(H)));
                }
                var U = -1;
                for (b = 0; b < h.length - 1;) {
                  if (h[b] == 255 && h[b + 1] == y) {
                    U = b;
                    break;
                  }
                  b++;
                }
                if (U == -1) {
                  var _e = new Uint8Array(h.length + 10 + 3 * V);
                  _e.set(h);
                  var fe = h.length;
                  if (
                    ((U = h.length),
                    (h = _e),
                    (h[fe++] = 255),
                    (h[fe++] = y),
                    (h[fe++] = 0),
                    (h[fe++] = 8 + 3 * V),
                    (h[fe++] = 8),
                    (h[fe++] = (i.height >>> 8) & 255),
                    (h[fe++] = i.height & 255),
                    (h[fe++] = (i.width >>> 8) & 255),
                    (h[fe++] = i.width & 255),
                    (h[fe++] = V),
                    V == 1)
                  )
                    ((h[fe++] = 1), (h[fe++] = 17), (h[fe++] = 0));
                  else
                    for (b = 0; b < 3; b++)
                      ((h[fe++] = b + 1),
                        (h[fe++] = b != 0 ? 17 : ((I & 15) << 4) | (j & 15)),
                        (h[fe++] = b));
                }
                if (r[v] == 255 && r[v + 1] == s) {
                  var le = (r[v + 2] << 8) | r[v + 3];
                  for (
                    n = new Uint8Array(le + 2),
                      n[0] = r[v],
                      n[1] = r[v + 1],
                      n[2] = r[v + 2],
                      n[3] = r[v + 3],
                      b = 0;
                    b < le - 2;
                    b++
                  )
                    n[b + 4] = r[v + b + 4];
                } else {
                  n = new Uint8Array(8 + 2 * V);
                  var oe = 0;
                  if (
                    ((n[oe++] = 255),
                    (n[oe++] = s),
                    (n[oe++] = 0),
                    (n[oe++] = 6 + 2 * V),
                    (n[oe++] = V),
                    V == 1)
                  )
                    ((n[oe++] = 1), (n[oe++] = 0));
                  else
                    for (b = 0; b < 3; b++)
                      ((n[oe++] = b + 1), (n[oe++] = (b << 4) | b));
                  ((n[oe++] = 0), (n[oe++] = 63), (n[oe++] = 0));
                }
                return {
                  jpegOffset: t,
                  tables: h,
                  sosMarker: n,
                  sofPosition: U,
                };
              }),
              (E.decode._decodeOldJPEG = function (i, r, t, w, d, u) {
                var l,
                  _,
                  y,
                  s,
                  c,
                  v = E.decode._decodeOldJPEGInit(i, r, t, w);
                if (v.jpegOffset != null)
                  for (
                    _ = t + w - v.jpegOffset, s = new Uint8Array(_), l = 0;
                    l < _;
                    l++
                  )
                    s[l] = r[v.jpegOffset + l];
                else {
                  for (
                    y = v.tables.length,
                      s = new Uint8Array(y + v.sosMarker.length + w + 2),
                      s.set(v.tables),
                      c = y,
                      s[v.sofPosition + 5] = (i.height >>> 8) & 255,
                      s[v.sofPosition + 6] = i.height & 255,
                      s[v.sofPosition + 7] = (i.width >>> 8) & 255,
                      s[v.sofPosition + 8] = i.width & 255,
                      (r[t] != 255 || r[t + 1] != SOS) &&
                        (s.set(v.sosMarker, c), (c += sosMarker.length)),
                      l = 0;
                    l < w;
                    l++
                  )
                    s[c++] = r[t + l];
                  ((s[c++] = 255), (s[c++] = EOI));
                }
                var h = new E.JpegDecoder();
                h.parse(s);
                for (
                  var n = h.getData(h.width, h.height), l = 0;
                  l < n.length;
                  l++
                )
                  d[u + l] = n[l];
                i.t262 && i.t262[0] == 6 && (i.t262[0] = 2);
              }),
              (E.decode._decodePackBits = function (i, r, t, w, d) {
                for (
                  var u = new Int8Array(i.buffer),
                    l = new Int8Array(w.buffer),
                    _ = r + t;
                  r < _;
                ) {
                  var y = u[r];
                  if ((r++, y >= 0 && y < 128))
                    for (var s = 0; s < y + 1; s++) ((l[d] = u[r]), d++, r++);
                  if (y >= -127 && y < 0) {
                    for (var s = 0; s < -y + 1; s++) ((l[d] = u[r]), d++);
                    r++;
                  }
                }
              }),
              (E.decode._decodeThunder = function (i, r, t, w, d) {
                for (
                  var u = [0, 1, 0, -1],
                    l = [0, 1, 2, 3, 0, -3, -2, -1],
                    _ = r + t,
                    y = d * 2,
                    s = 0;
                  r < _;
                ) {
                  var c = i[r],
                    v = c >>> 6,
                    h = c & 63;
                  if (
                    (r++,
                    v == 3 &&
                      ((s = h & 15),
                      (w[y >>> 1] |= s << (4 * ((1 - y) & 1))),
                      y++),
                    v == 0)
                  )
                    for (var n = 0; n < h; n++)
                      ((w[y >>> 1] |= s << (4 * ((1 - y) & 1))), y++);
                  if (v == 2)
                    for (var n = 0; n < 2; n++) {
                      var g = (h >>> (3 * (1 - n))) & 7;
                      g != 4 &&
                        ((s += l[g]),
                        (w[y >>> 1] |= s << (4 * ((1 - y) & 1))),
                        y++);
                    }
                  if (v == 1)
                    for (var n = 0; n < 3; n++) {
                      var g = (h >>> (2 * (2 - n))) & 3;
                      g != 2 &&
                        ((s += u[g]),
                        (w[y >>> 1] |= s << (4 * ((1 - y) & 1))),
                        y++);
                    }
                }
              }),
              (E.decode._dmap = {
                1: 0,
                "011": 1,
                "000011": 2,
                "0000011": 3,
                "010": -1,
                "000010": -2,
                "0000010": -3,
              }),
              (E.decode._lens = (function () {
                var i = function (y, s, c, v) {
                    for (var h = 0; h < s.length; h++) y[s[h]] = c + h * v;
                  },
                  r =
                    "00110101,000111,0111,1000,1011,1100,1110,1111,10011,10100,00111,01000,001000,000011,110100,110101,101010,101011,0100111,0001100,0001000,0010111,0000011,0000100,0101000,0101011,0010011,0100100,0011000,00000010,00000011,00011010,00011011,00010010,00010011,00010100,00010101,00010110,00010111,00101000,00101001,00101010,00101011,00101100,00101101,00000100,00000101,00001010,00001011,01010010,01010011,01010100,01010101,00100100,00100101,01011000,01011001,01011010,01011011,01001010,01001011,00110010,00110011,00110100",
                  t =
                    "0000110111,010,11,10,011,0011,0010,00011,000101,000100,0000100,0000101,0000111,00000100,00000111,000011000,0000010111,0000011000,0000001000,00001100111,00001101000,00001101100,00000110111,00000101000,00000010111,00000011000,000011001010,000011001011,000011001100,000011001101,000001101000,000001101001,000001101010,000001101011,000011010010,000011010011,000011010100,000011010101,000011010110,000011010111,000001101100,000001101101,000011011010,000011011011,000001010100,000001010101,000001010110,000001010111,000001100100,000001100101,000001010010,000001010011,000000100100,000000110111,000000111000,000000100111,000000101000,000001011000,000001011001,000000101011,000000101100,000001011010,000001100110,000001100111",
                  w =
                    "11011,10010,010111,0110111,00110110,00110111,01100100,01100101,01101000,01100111,011001100,011001101,011010010,011010011,011010100,011010101,011010110,011010111,011011000,011011001,011011010,011011011,010011000,010011001,010011010,011000,010011011",
                  d =
                    "0000001111,000011001000,000011001001,000001011011,000000110011,000000110100,000000110101,0000001101100,0000001101101,0000001001010,0000001001011,0000001001100,0000001001101,0000001110010,0000001110011,0000001110100,0000001110101,0000001110110,0000001110111,0000001010010,0000001010011,0000001010100,0000001010101,0000001011010,0000001011011,0000001100100,0000001100101",
                  u =
                    "00000001000,00000001100,00000001101,000000010010,000000010011,000000010100,000000010101,000000010110,000000010111,000000011100,000000011101,000000011110,000000011111";
                ((r = r.split(",")),
                  (t = t.split(",")),
                  (w = w.split(",")),
                  (d = d.split(",")),
                  (u = u.split(",")));
                var l = {},
                  _ = {};
                return (
                  i(l, r, 0, 1),
                  i(l, w, 64, 64),
                  i(l, u, 1792, 64),
                  i(_, t, 0, 1),
                  i(_, d, 64, 64),
                  i(_, u, 1792, 64),
                  [l, _]
                );
              })()),
              (E.decode._decodeG4 = function (i, r, t, w, d, u, l) {
                for (
                  var _ = E.decode,
                    y = r << 3,
                    s = 0,
                    c = "",
                    v = [],
                    h = [],
                    n = 0;
                  n < u;
                  n++
                )
                  h.push(0);
                h = _._makeDiff(h);
                for (
                  var g = 0,
                    b = 0,
                    k = 0,
                    S = 0,
                    D = 0,
                    B = 0,
                    m = "",
                    z = 0,
                    T = Math.ceil(u / 8) * 8;
                  y >>> 3 < r + t;
                ) {
                  ((k = _._findDiff(h, g + (g == 0 ? 0 : 1), 1 - D)),
                    (S = _._findDiff(h, k, D)));
                  var C = 0;
                  if (
                    (l == 1 && (C = (i[y >>> 3] >>> (7 - (y & 7))) & 1),
                    l == 2 && (C = (i[y >>> 3] >>> (y & 7)) & 1),
                    y++,
                    (c += C),
                    m == "H")
                  ) {
                    if (_._lens[D][c] != null) {
                      var I = _._lens[D][c];
                      ((c = ""),
                        (s += I),
                        I < 64 &&
                          (_._addNtimes(v, s, D),
                          (g += s),
                          (D = 1 - D),
                          (s = 0),
                          z--,
                          z == 0 && (m = "")));
                    }
                  } else
                    (c == "0001" &&
                      ((c = ""), _._addNtimes(v, S - g, D), (g = S)),
                      c == "001" && ((c = ""), (m = "H"), (z = 2)),
                      _._dmap[c] != null &&
                        ((b = k + _._dmap[c]),
                        _._addNtimes(v, b - g, D),
                        (g = b),
                        (c = ""),
                        (D = 1 - D)));
                  v.length == u &&
                    m == "" &&
                    (_._writeBits(v, w, d * 8 + B * T),
                    (D = 0),
                    B++,
                    (g = 0),
                    (h = _._makeDiff(v)),
                    (v = []));
                }
              }),
              (E.decode._findDiff = function (i, r, t) {
                for (var w = 0; w < i.length; w += 2)
                  if (i[w] >= r && i[w + 1] == t) return i[w];
              }),
              (E.decode._makeDiff = function (i) {
                var r = [];
                i[0] == 1 && r.push(0, 1);
                for (var t = 1; t < i.length; t++)
                  i[t - 1] != i[t] && r.push(t, i[t]);
                return (r.push(i.length, 0, i.length, 1), r);
              }),
              (E.decode._decodeG3 = function (i, r, t, w, d, u, l) {
                for (
                  var _ = E.decode,
                    y = r << 3,
                    s = 0,
                    c = "",
                    v = [],
                    h = [],
                    n = 0;
                  n < u;
                  n++
                )
                  v.push(0);
                for (
                  var g = 0,
                    b = 0,
                    k = 0,
                    S = 0,
                    D = 0,
                    B = -1,
                    m = "",
                    z = 0,
                    T = !1,
                    C = Math.ceil(u / 8) * 8;
                  y >>> 3 < r + t;
                ) {
                  ((k = _._findDiff(h, g + (g == 0 ? 0 : 1), 1 - D)),
                    (S = _._findDiff(h, k, D)));
                  var I = 0;
                  if (
                    (l == 1 && (I = (i[y >>> 3] >>> (7 - (y & 7))) & 1),
                    l == 2 && (I = (i[y >>> 3] >>> (y & 7)) & 1),
                    y++,
                    (c += I),
                    T)
                  ) {
                    if (_._lens[D][c] != null) {
                      var j = _._lens[D][c];
                      ((c = ""),
                        (s += j),
                        j < 64 &&
                          (_._addNtimes(v, s, D), (D = 1 - D), (s = 0)));
                    }
                  } else if (m == "H") {
                    if (_._lens[D][c] != null) {
                      var j = _._lens[D][c];
                      ((c = ""),
                        (s += j),
                        j < 64 &&
                          (_._addNtimes(v, s, D),
                          (g += s),
                          (D = 1 - D),
                          (s = 0),
                          z--,
                          z == 0 && (m = "")));
                    }
                  } else
                    (c == "0001" &&
                      ((c = ""), _._addNtimes(v, S - g, D), (g = S)),
                      c == "001" && ((c = ""), (m = "H"), (z = 2)),
                      _._dmap[c] != null &&
                        ((b = k + _._dmap[c]),
                        _._addNtimes(v, b - g, D),
                        (g = b),
                        (c = ""),
                        (D = 1 - D)));
                  c.endsWith("000000000001") &&
                    (B >= 0 && _._writeBits(v, w, d * 8 + B * C),
                    l == 1 && (T = ((i[y >>> 3] >>> (7 - (y & 7))) & 1) == 1),
                    l == 2 && (T = ((i[y >>> 3] >>> (y & 7)) & 1) == 1),
                    y++,
                    _._decodeG3.allow2D == null && (_._decodeG3.allow2D = T),
                    _._decodeG3.allow2D || ((T = !0), y--),
                    (c = ""),
                    (D = 0),
                    B++,
                    (g = 0),
                    (h = _._makeDiff(v)),
                    (v = []));
                }
                v.length == u && _._writeBits(v, w, d * 8 + B * C);
              }),
              (E.decode._addNtimes = function (i, r, t) {
                for (var w = 0; w < r; w++) i.push(t);
              }),
              (E.decode._writeBits = function (i, r, t) {
                for (var w = 0; w < i.length; w++)
                  r[(t + w) >>> 3] |= i[w] << (7 - ((t + w) & 7));
              }),
              (E.decode._decodeLZW = function (i, r, t, w) {
                if (E.decode._lzwTab == null) {
                  for (
                    var d = new Uint32Array(65535),
                      u = new Uint16Array(65535),
                      c = new Uint8Array(2e6),
                      l = 0;
                    l < 256;
                    l++
                  )
                    ((c[l << 2] = l), (d[l] = l << 2), (u[l] = 1));
                  E.decode._lzwTab = [d, u, c];
                }
                for (
                  var _ = E.decode._copyData,
                    y = E.decode._lzwTab[0],
                    s = E.decode._lzwTab[1],
                    c = E.decode._lzwTab[2],
                    v = 258,
                    h = 1032,
                    n = 9,
                    g = r << 3,
                    b = 256,
                    k = 257,
                    S = 0,
                    D = 0,
                    B = 0;
                  (S =
                    (i[g >>> 3] << 16) |
                    (i[(g + 8) >>> 3] << 8) |
                    i[(g + 16) >>> 3]),
                    (D = (S >> (24 - (g & 7) - n)) & ((1 << n) - 1)),
                    (g += n),
                    D != k;
                ) {
                  if (D == b) {
                    if (
                      ((n = 9),
                      (v = 258),
                      (h = 1032),
                      (S =
                        (i[g >>> 3] << 16) |
                        (i[(g + 8) >>> 3] << 8) |
                        i[(g + 16) >>> 3]),
                      (D = (S >> (24 - (g & 7) - n)) & ((1 << n) - 1)),
                      (g += n),
                      D == k)
                    )
                      break;
                    ((t[w] = D), w++);
                  } else if (D < v) {
                    var m = y[D],
                      z = s[D];
                    if ((_(c, m, t, w, z), (w += z), B >= v))
                      ((y[v] = h),
                        (c[y[v]] = m[0]),
                        (s[v] = 1),
                        (h = (h + 1 + 3) & -4),
                        v++);
                    else {
                      y[v] = h;
                      var T = y[B],
                        C = s[B];
                      (_(c, T, c, h, C),
                        (c[h + C] = c[m]),
                        C++,
                        (s[v] = C),
                        v++,
                        (h = (h + C + 3) & -4));
                    }
                    v + 1 == 1 << n && n++;
                  } else {
                    if (B >= v) ((y[v] = h), (s[v] = 0), v++);
                    else {
                      y[v] = h;
                      var T = y[B],
                        C = s[B];
                      (_(c, T, c, h, C),
                        (c[h + C] = c[h]),
                        C++,
                        (s[v] = C),
                        v++,
                        _(c, h, t, w, C),
                        (w += C),
                        (h = (h + C + 3) & -4));
                    }
                    v + 1 == 1 << n && n++;
                  }
                  B = D;
                }
              }),
              (E.decode._copyData = function (i, r, t, w, d) {
                for (var u = 0; u < d; u += 4)
                  ((t[w + u] = i[r + u]),
                    (t[w + u + 1] = i[r + u + 1]),
                    (t[w + u + 2] = i[r + u + 2]),
                    (t[w + u + 3] = i[r + u + 3]));
              }),
              (E.tags = {}),
              (E.ttypes = {
                256: 3,
                257: 3,
                258: 3,
                259: 3,
                262: 3,
                273: 4,
                274: 3,
                277: 3,
                278: 4,
                279: 4,
                282: 5,
                283: 5,
                284: 3,
                286: 5,
                287: 5,
                296: 3,
                305: 2,
                306: 2,
                338: 3,
                513: 4,
                514: 4,
                34665: 4,
              }),
              (E._readIFD = function (i, r, t, w, d, u) {
                var l = i.readUshort(r, t);
                t += 2;
                var _ = {};
                (w.push(_),
                  u && P("   ".repeat(d), w.length - 1, ">>>----------------"));
                for (var y = 0; y < l; y++) {
                  var s = i.readUshort(r, t);
                  t += 2;
                  var c = i.readUshort(r, t);
                  t += 2;
                  var v = i.readUint(r, t);
                  t += 4;
                  var h = i.readUint(r, t);
                  t += 4;
                  var n = [];
                  if (
                    ((c == 1 || c == 7) &&
                      (n = new Uint8Array(r.buffer, v < 5 ? t - 4 : h, v)),
                    c == 2)
                  ) {
                    var g = v < 5 ? t - 4 : h,
                      b = r[g];
                    b < 128
                      ? n.push(i.readASCII(r, g, v - 1))
                      : (n = new Uint8Array(r.buffer, g, v - 1));
                  }
                  if (c == 3)
                    for (var k = 0; k < v; k++)
                      n.push(i.readUshort(r, (v < 3 ? t - 4 : h) + 2 * k));
                  if (c == 4)
                    for (var k = 0; k < v; k++)
                      n.push(i.readUint(r, (v < 2 ? t - 4 : h) + 4 * k));
                  if (c == 5)
                    for (var k = 0; k < v; k++)
                      n.push(
                        i.readUint(r, h + k * 8) / i.readUint(r, h + k * 8 + 4),
                      );
                  if (c == 8)
                    for (var k = 0; k < v; k++)
                      n.push(i.readShort(r, (v < 3 ? t - 4 : h) + 2 * k));
                  if (c == 9)
                    for (var k = 0; k < v; k++)
                      n.push(i.readInt(r, (v < 2 ? t - 4 : h) + 4 * k));
                  if (c == 10)
                    for (var k = 0; k < v; k++)
                      n.push(
                        i.readInt(r, h + k * 8) / i.readInt(r, h + k * 8 + 4),
                      );
                  if (c == 11)
                    for (var k = 0; k < v; k++)
                      n.push(i.readFloat(r, h + k * 4));
                  if (c == 12)
                    for (var k = 0; k < v; k++)
                      n.push(i.readDouble(r, h + k * 8));
                  if (
                    ((_["t" + s] = n),
                    v != 0 &&
                      n.length == 0 &&
                      P("unknown TIFF tag type: ", c, "num:", v),
                    u && P("   ".repeat(d), s, c, E.tags[s], n),
                    !(s == 330 && _.t272 && _.t272[0] == "DSLR-A100"))
                  ) {
                    if (
                      s == 330 ||
                      s == 34665 ||
                      (s == 50740 && i.readUshort(r, i.readUint(n, 0)) < 300)
                    ) {
                      for (
                        var S = s == 50740 ? [i.readUint(n, 0)] : n,
                          D = [],
                          k = 0;
                        k < S.length;
                        k++
                      )
                        E._readIFD(i, r, S[k], D, d + 1, u);
                      (s == 330 && (_.subIFD = D),
                        s == 34665 && (_.exifIFD = D[0]),
                        s == 50740 && (_.dngPrvt = D[0]));
                    }
                  }
                  if (s == 37500) {
                    var B = n;
                    if (i.readASCII(B, 0, 5) == "Nikon")
                      _.makerNote = E.decode(B.slice(10).buffer)[0];
                    else if (i.readUshort(r, h) < 300) {
                      var m = [];
                      (E._readIFD(i, r, h, m, d + 1, u), (_.makerNote = m[0]));
                    }
                  }
                }
                return (u && P("   ".repeat(d), "<<<---------------"), t);
              }),
              (E._writeIFD = function (i, r, t, w) {
                var d = Object.keys(w);
                (i.writeUshort(r, t, d.length), (t += 2));
                for (var u = t + d.length * 12 + 4, l = 0; l < d.length; l++) {
                  var _ = d[l],
                    y = parseInt(_.slice(1)),
                    s = E.ttypes[y];
                  if (s == null) throw new Error("unknown type of tag: " + y);
                  var c = w[_];
                  s == 2 && (c = c[0] + "\0");
                  var v = c.length;
                  (i.writeUshort(r, t, y),
                    (t += 2),
                    i.writeUshort(r, t, s),
                    (t += 2),
                    i.writeUint(r, t, v),
                    (t += 4));
                  var h = [-1, 1, 1, 2, 4, 8, 0, 0, 0, 0, 0, 0, 8][s] * v,
                    n = t;
                  if (
                    (h > 4 && (i.writeUint(r, t, u), (n = u)),
                    s == 2 && i.writeASCII(r, n, c),
                    s == 3)
                  )
                    for (var g = 0; g < v; g++)
                      i.writeUshort(r, n + 2 * g, c[g]);
                  if (s == 4)
                    for (var g = 0; g < v; g++) i.writeUint(r, n + 4 * g, c[g]);
                  if (s == 5)
                    for (var g = 0; g < v; g++)
                      (i.writeUint(r, n + 8 * g, Math.round(c[g] * 1e4)),
                        i.writeUint(r, n + 8 * g + 4, 1e4));
                  if (s == 12)
                    for (var g = 0; g < v; g++)
                      i.writeDouble(r, n + 8 * g, c[g]);
                  (h > 4 && ((h += h & 1), (u += h)), (t += 4));
                }
                return [t, u];
              }),
              (E.toRGBA8 = function (i) {
                var r = i.width,
                  t = i.height,
                  w = r * t,
                  d = w * 4,
                  u = i.data,
                  l = new Uint8Array(w * 4),
                  _ = i.t262 ? i.t262[0] : 2,
                  y = i.t258 ? Math.min(32, i.t258[0]) : 1;
                if (_ == 0)
                  for (var s = Math.ceil((y * r) / 8), c = 0; c < t; c++) {
                    var v = c * s,
                      h = c * r;
                    if (y == 1)
                      for (var n = 0; n < r; n++) {
                        var g = (h + n) << 2,
                          b = (u[v + (n >> 3)] >> (7 - (n & 7))) & 1;
                        ((l[g] = l[g + 1] = l[g + 2] = (1 - b) * 255),
                          (l[g + 3] = 255));
                      }
                    if (y == 4)
                      for (var n = 0; n < r; n++) {
                        var g = (h + n) << 2,
                          b = (u[v + (n >> 1)] >> (4 - 4 * (n & 1))) & 15;
                        ((l[g] = l[g + 1] = l[g + 2] = (15 - b) * 17),
                          (l[g + 3] = 255));
                      }
                    if (y == 8)
                      for (var n = 0; n < r; n++) {
                        var g = (h + n) << 2,
                          b = u[v + n];
                        ((l[g] = l[g + 1] = l[g + 2] = 255 - b),
                          (l[g + 3] = 255));
                      }
                  }
                else if (_ == 1)
                  for (var s = Math.ceil((y * r) / 8), c = 0; c < t; c++) {
                    var v = c * s,
                      h = c * r;
                    if (y == 1)
                      for (var n = 0; n < r; n++) {
                        var g = (h + n) << 2,
                          b = (u[v + (n >> 3)] >> (7 - (n & 7))) & 1;
                        ((l[g] = l[g + 1] = l[g + 2] = b * 255),
                          (l[g + 3] = 255));
                      }
                    if (y == 2)
                      for (var n = 0; n < r; n++) {
                        var g = (h + n) << 2,
                          b = (u[v + (n >> 2)] >> (6 - 2 * (n & 3))) & 3;
                        ((l[g] = l[g + 1] = l[g + 2] = b * 85),
                          (l[g + 3] = 255));
                      }
                    if (y == 8)
                      for (var n = 0; n < r; n++) {
                        var g = (h + n) << 2,
                          b = u[v + n];
                        ((l[g] = l[g + 1] = l[g + 2] = b), (l[g + 3] = 255));
                      }
                    if (y == 16)
                      for (var n = 0; n < r; n++) {
                        var g = (h + n) << 2,
                          b = u[v + (2 * n + 1)];
                        ((l[g] = l[g + 1] = l[g + 2] = Math.min(255, b)),
                          (l[g + 3] = 255));
                      }
                  }
                else if (_ == 2) {
                  var k = i.t258 ? i.t258.length : 3;
                  if (y == 8) {
                    if (k == 4) for (var n = 0; n < d; n++) l[n] = u[n];
                    if (k == 3)
                      for (var n = 0; n < w; n++) {
                        var g = n << 2,
                          S = n * 3;
                        ((l[g] = u[S]),
                          (l[g + 1] = u[S + 1]),
                          (l[g + 2] = u[S + 2]),
                          (l[g + 3] = 255));
                      }
                  } else {
                    if (k == 4)
                      for (var n = 0; n < w; n++) {
                        var g = n << 2,
                          S = n * 8 + 1;
                        ((l[g] = u[S]),
                          (l[g + 1] = u[S + 2]),
                          (l[g + 2] = u[S + 4]),
                          (l[g + 3] = u[S + 6]));
                      }
                    if (k == 3)
                      for (var n = 0; n < w; n++) {
                        var g = n << 2,
                          S = n * 6 + 1;
                        ((l[g] = u[S]),
                          (l[g + 1] = u[S + 2]),
                          (l[g + 2] = u[S + 4]),
                          (l[g + 3] = 255));
                      }
                  }
                } else if (_ == 3)
                  for (var D = i.t320, n = 0; n < w; n++) {
                    var g = n << 2,
                      B = u[n];
                    ((l[g] = D[B] >> 8),
                      (l[g + 1] = D[256 + B] >> 8),
                      (l[g + 2] = D[512 + B] >> 8),
                      (l[g + 3] = 255));
                  }
                else if (_ == 5)
                  for (
                    var k = i.t258 ? i.t258.length : 4,
                      m = k > 4 ? 1 : 0,
                      n = 0;
                    n < w;
                    n++
                  ) {
                    var g = n << 2,
                      z = n * k,
                      T = 255 - u[z],
                      C = 255 - u[z + 1],
                      I = 255 - u[z + 2],
                      j = (255 - u[z + 3]) * (1 / 255);
                    ((l[g] = ~~(T * j + 0.5)),
                      (l[g + 1] = ~~(C * j + 0.5)),
                      (l[g + 2] = ~~(I * j + 0.5)),
                      (l[g + 3] = 255 * (1 - m) + u[z + 4] * m));
                  }
                else P("Unknown Photometric interpretation: " + _);
                return l;
              }),
              (E.replaceIMG = function (i) {
                i == null && (i = document.getElementsByTagName("img"));
                for (
                  var r = ["tif", "tiff", "dng", "cr2", "nef"], t = 0;
                  t < i.length;
                  t++
                ) {
                  var w = i[t],
                    d = w.getAttribute("src");
                  if (d != null) {
                    var u = d.split(".").pop().toLowerCase();
                    if (r.indexOf(u) != -1) {
                      var l = new XMLHttpRequest();
                      (E._xhrs.push(l),
                        E._imgs.push(w),
                        l.open("GET", d),
                        (l.responseType = "arraybuffer"),
                        (l.onload = E._imgLoaded),
                        l.send());
                    }
                  }
                }
              }),
              (E._xhrs = []),
              (E._imgs = []),
              (E._imgLoaded = function (i) {
                var r = i.target.response,
                  t = E.decode(r),
                  w = t,
                  d = 0,
                  u = w[0];
                t[0].subIFD && (w = w.concat(t[0].subIFD));
                for (var l = 0; l < w.length; l++) {
                  var h = w[l];
                  if (!(h.t258 == null || h.t258.length < 3)) {
                    var _ = h.t256 * h.t257;
                    _ > d && ((d = _), (u = h));
                  }
                }
                E.decodeImage(r, u, t);
                var y = E.toRGBA8(u),
                  s = u.width,
                  c = u.height,
                  v = E._xhrs.indexOf(i.target),
                  h = E._imgs[v];
                (E._xhrs.splice(v, 1), E._imgs.splice(v, 1));
                var n = document.createElement("canvas");
                ((n.width = s), (n.height = c));
                for (
                  var g = n.getContext("2d"),
                    b = g.createImageData(s, c),
                    l = 0;
                  l < y.length;
                  l++
                )
                  b.data[l] = y[l];
                (g.putImageData(b, 0, 0), h.setAttribute("src", n.toDataURL()));
              }),
              (E._binBE = {
                nextZero: function (i, r) {
                  for (; i[r] != 0;) r++;
                  return r;
                },
                readUshort: function (i, r) {
                  return (i[r] << 8) | i[r + 1];
                },
                readShort: function (i, r) {
                  var t = E._binBE.ui8;
                  return (
                    (t[0] = i[r + 1]),
                    (t[1] = i[r + 0]),
                    E._binBE.i16[0]
                  );
                },
                readInt: function (i, r) {
                  var t = E._binBE.ui8;
                  return (
                    (t[0] = i[r + 3]),
                    (t[1] = i[r + 2]),
                    (t[2] = i[r + 1]),
                    (t[3] = i[r + 0]),
                    E._binBE.i32[0]
                  );
                },
                readUint: function (i, r) {
                  var t = E._binBE.ui8;
                  return (
                    (t[0] = i[r + 3]),
                    (t[1] = i[r + 2]),
                    (t[2] = i[r + 1]),
                    (t[3] = i[r + 0]),
                    E._binBE.ui32[0]
                  );
                },
                readASCII: function (i, r, t) {
                  for (var w = "", d = 0; d < t; d++)
                    w += String.fromCharCode(i[r + d]);
                  return w;
                },
                readFloat: function (i, r) {
                  for (var t = E._binBE.ui8, w = 0; w < 4; w++)
                    t[w] = i[r + 3 - w];
                  return E._binBE.fl32[0];
                },
                readDouble: function (i, r) {
                  for (var t = E._binBE.ui8, w = 0; w < 8; w++)
                    t[w] = i[r + 7 - w];
                  return E._binBE.fl64[0];
                },
                writeUshort: function (i, r, t) {
                  ((i[r] = (t >> 8) & 255), (i[r + 1] = t & 255));
                },
                writeUint: function (i, r, t) {
                  ((i[r] = (t >> 24) & 255),
                    (i[r + 1] = (t >> 16) & 255),
                    (i[r + 2] = (t >> 8) & 255),
                    (i[r + 3] = (t >> 0) & 255));
                },
                writeASCII: function (i, r, t) {
                  for (var w = 0; w < t.length; w++) i[r + w] = t.charCodeAt(w);
                },
                writeDouble: function (i, r, t) {
                  E._binBE.fl64[0] = t;
                  for (var w = 0; w < 8; w++) i[r + w] = E._binBE.ui8[7 - w];
                },
              }),
              (E._binBE.ui8 = new Uint8Array(8)),
              (E._binBE.i16 = new Int16Array(E._binBE.ui8.buffer)),
              (E._binBE.i32 = new Int32Array(E._binBE.ui8.buffer)),
              (E._binBE.ui32 = new Uint32Array(E._binBE.ui8.buffer)),
              (E._binBE.fl32 = new Float32Array(E._binBE.ui8.buffer)),
              (E._binBE.fl64 = new Float64Array(E._binBE.ui8.buffer)),
              (E._binLE = {
                nextZero: E._binBE.nextZero,
                readUshort: function (i, r) {
                  return (i[r + 1] << 8) | i[r];
                },
                readShort: function (i, r) {
                  var t = E._binBE.ui8;
                  return (
                    (t[0] = i[r + 0]),
                    (t[1] = i[r + 1]),
                    E._binBE.i16[0]
                  );
                },
                readInt: function (i, r) {
                  var t = E._binBE.ui8;
                  return (
                    (t[0] = i[r + 0]),
                    (t[1] = i[r + 1]),
                    (t[2] = i[r + 2]),
                    (t[3] = i[r + 3]),
                    E._binBE.i32[0]
                  );
                },
                readUint: function (i, r) {
                  var t = E._binBE.ui8;
                  return (
                    (t[0] = i[r + 0]),
                    (t[1] = i[r + 1]),
                    (t[2] = i[r + 2]),
                    (t[3] = i[r + 3]),
                    E._binBE.ui32[0]
                  );
                },
                readASCII: E._binBE.readASCII,
                readFloat: function (i, r) {
                  for (var t = E._binBE.ui8, w = 0; w < 4; w++) t[w] = i[r + w];
                  return E._binBE.fl32[0];
                },
                readDouble: function (i, r) {
                  for (var t = E._binBE.ui8, w = 0; w < 8; w++) t[w] = i[r + w];
                  return E._binBE.fl64[0];
                },
              }),
              (E._copyTile = function (i, r, t, w, d, u, l, _) {
                for (
                  var y = Math.min(r, d - l), s = Math.min(t, u - _), c = 0;
                  c < s;
                  c++
                )
                  for (var v = (_ + c) * d + l, h = c * r, n = 0; n < y; n++)
                    w[v + n] = i[h + n];
              }),
              (E.LosslessJpegDecode = (function () {
                function i(d) {
                  ((this.w = d), (this.N = 0), (this._ = 0), (this.G = 0));
                }
                i.prototype = {
                  t: function (d) {
                    this.N = Math.max(0, Math.min(this.w.length, d));
                  },
                  i: function () {
                    return this.w[this.N++];
                  },
                  l: function () {
                    var d = this.N;
                    return ((this.N += 2), (this.w[d] << 8) | this.w[d + 1]);
                  },
                  J: function () {
                    return (
                      this._ == 0 &&
                        ((this.G = this.w[this.N]),
                        (this.N += 1 + ((this.G + 1) >>> 8)),
                        (this._ = 8)),
                      (this.G >>> --this._) & 1
                    );
                  },
                  Z: function (d) {
                    var u = this._,
                      l = this.G,
                      _ = Math.min(u, d);
                    ((d -= _), (u -= _));
                    for (var y = (l >>> u) & ((1 << _) - 1); d > 0;)
                      ((l = this.w[this.N]),
                        (this.N += 1 + ((l + 1) >>> 8)),
                        (_ = Math.min(8, d)),
                        (d -= _),
                        (u = 8 - _),
                        (y <<= _),
                        (y |= (l >>> u) & ((1 << _) - 1)));
                    return ((this._ = u), (this.G = l), y);
                  },
                };
                var r = {};
                ((r.X = function () {
                  return [0, 0, -1];
                }),
                  (r.s = function (d, u, l) {
                    d[r.Y(d, 0, l) + 2] = u;
                  }),
                  (r.Y = function (d, u, l) {
                    if (d[u + 2] != -1) return 0;
                    if (l == 0) return u;
                    for (var _ = 0; _ < 2; _++) {
                      d[u + _] == 0 &&
                        ((d[u + _] = d.length),
                        d.push(0),
                        d.push(0),
                        d.push(-1));
                      var y = r.Y(d, d[u + _], l - 1);
                      if (y != 0) return y;
                    }
                    return 0;
                  }),
                  (r.B = function (d, u) {
                    for (var l = 0, _ = 0, y = 0, s = u._, c = u.G, v = u.N; ;)
                      if (
                        (s == 0 &&
                          ((c = u.w[v]), (v += 1 + ((c + 1) >>> 8)), (s = 8)),
                        (y = (c >>> --s) & 1),
                        (l = d[l + y]),
                        (_ = d[l + 2]),
                        _ != -1)
                      )
                        return ((u._ = s), (u.G = c), (u.N = v), _);
                    return -1;
                  }));
                function t(d) {
                  ((this.z = new i(d)), this.D(this.z));
                }
                ((t.prototype = {
                  $: function (d, u) {
                    ((this.Q = d.i()), (this.F = d.l()), (this.o = d.l()));
                    var l = (this.O = d.i());
                    this.L = [];
                    for (var _ = 0; _ < l; _++) {
                      var y = d.i();
                      (d.i(), d.i(), (this.L[y] = _));
                    }
                    d.t(d.N + u - (6 + l * 3));
                  },
                  e: function () {
                    var d = 0,
                      u = this.z.i();
                    this.H == null && (this.H = {});
                    for (
                      var l = (this.H[u] = r.X()), _ = [], y = 0;
                      y < 16;
                      y++
                    )
                      ((_[y] = this.z.i()), (d += _[y]));
                    for (var y = 0; y < 16; y++)
                      for (var s = 0; s < _[y]; s++) r.s(l, this.z.i(), y + 1);
                    return d + 17;
                  },
                  W: function (d) {
                    for (; d > 0;) d -= this.e();
                  },
                  p: function (d, u) {
                    var l = d.i();
                    this.U || (this.U = []);
                    for (var _ = 0; _ < l; _++) {
                      var y = d.i(),
                        s = d.i();
                      this.U[this.L[y]] = this.H[s >>> 4];
                    }
                    ((this.g = d.i()), d.t(d.N + u - (2 + l * 2)));
                  },
                  D: function (d) {
                    var u = !1,
                      l = d.l();
                    if (l === t.q)
                      do {
                        var l = d.l(),
                          _ = d.l() - 2;
                        switch (l) {
                          case t.m:
                            this.$(d, _);
                            break;
                          case t.K:
                            this.W(_);
                            break;
                          case t.V:
                            (this.p(d, _), (u = !0));
                            break;
                          default:
                            d.t(d.N + _);
                            break;
                        }
                      } while (!u);
                  },
                  I: function (d, u) {
                    var l = r.B(u, d);
                    if (l == 16) return -32768;
                    var _ = d.Z(l);
                    return (
                      (_ & (1 << (l - 1))) == 0 && (_ -= (1 << l) - 1),
                      _
                    );
                  },
                  B: function (d, u) {
                    for (
                      var l = this.z,
                        _ = this.O,
                        y = this.F,
                        s = this.I,
                        c = this.g,
                        v = this.o * _,
                        h = this.U,
                        n = 0;
                      n < _;
                      n++
                    )
                      d[n] = s(l, h[n]) + (1 << (this.Q - 1));
                    for (var g = _; g < v; g += _)
                      for (var n = 0; n < _; n++)
                        d[g + n] = s(l, h[n]) + d[g + n - _];
                    for (var b = u, k = 1; k < y; k++) {
                      for (var n = 0; n < _; n++)
                        d[b + n] = s(l, h[n]) + d[b + n - u];
                      for (var g = _; g < v; g += _)
                        for (var n = 0; n < _; n++) {
                          var S = b + g + n,
                            D = d[S - _];
                          (c == 6 &&
                            (D = d[S - u] + ((D - d[S - _ - u]) >>> 1)),
                            (d[S] = D + s(l, h[n])));
                        }
                      b += u;
                    }
                  },
                }),
                  (t.m = 65475),
                  (t.K = 65476),
                  (t.q = 65496),
                  (t.V = 65498));
                function w(d) {
                  var u = new t(d),
                    l = u.Q > 8 ? Uint16Array : Uint8Array,
                    _ = new l(u.o * u.F * u.O),
                    y = u.o * u.O;
                  return (u.B(_, y), _);
                }
                return w;
              })()));
          })(L, Y);
        })();
      })(cr)),
    cr.exports
  );
}
var Tt = It(),
  Ar = St(Tt);
function jt(p, L) {
  const Y = p.getContext("2d");
  if (!Y) {
    (typeof logger < "u" ? logger : console).error(
      "putImageData: canvas context is null, can't draw image data",
    );
    return;
  }
  const { width: P, height: E } = L;
  ((p.width = P),
    (p.height = E),
    requestAnimationFrame(() => {
      Y?.putImageData(new ImageData(L.data, P, E), 0, 0);
    }));
}
function Jt(p) {
  const L = Ar.decode(p);
  let Y = 0,
    P = L,
    E = P[0];
  L[0].subIFD && (P = P.concat(L[0].subIFD));
  for (const t of P) {
    if (t.t258 == null || t.t258.length < 3) continue;
    const w = t.t256 * t.t257;
    w > Y && ((Y = w), (E = t));
  }
  Ar.decodeImage(p, E, L);
  const G = Ar.toRGBA8(E),
    { width: i, height: r } = E;
  return { rgba: G, width: i, height: r };
}
function Kt({ rgba: p, width: L, height: Y }, P) {
  jt(P, new ImageData(new Uint8ClampedArray(p.buffer), L, Y));
}
var Yt = Object.freeze({ __proto__: null, decodeTIFF: Jt, draw: Kt });
Rr(Yt);
//# sourceMappingURL=worker-Bp-CcYlr.js.map
