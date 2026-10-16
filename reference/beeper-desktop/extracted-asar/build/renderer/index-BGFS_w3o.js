import { dk as k, cK as _ } from "./App-CsJiApxN.js";
import "./sentry-common-BxRELKId.js";
import "./matrix-util-Cr_UwXbj.js";
import "./index-Cw3pknxT.js";
import "./main-process-state-wkFhis-C.js";
import "./index-Dhe7xemD.js";
import "./index-CcYzEQCb.js";
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
      (e._sentryDebugIds[t] = "860c1028-e06f-4d8c-a3d7-16fe60bc1127"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-860c1028-e06f-4d8c-a3d7-16fe60bc1127"));
  } catch {}
})();
const P = Symbol("Comlink.proxy"),
  z = Symbol("Comlink.endpoint"),
  F = Symbol("Comlink.releaseProxy"),
  T = Symbol("Comlink.finalizer"),
  b = Symbol("Comlink.thrown"),
  I = (e) => (typeof e == "object" && e !== null) || typeof e == "function",
  j = {
    canHandle: (e) => I(e) && e[P],
    serialize(e) {
      const { port1: t, port2: r } = new MessageChannel();
      return (M(e, t), [r, [r]]);
    },
    deserialize(e) {
      return (e.start(), D(e));
    },
  },
  H = {
    canHandle: (e) => I(e) && b in e,
    serialize({ value: e }) {
      let t;
      return (
        e instanceof Error
          ? (t = {
              isError: !0,
              value: { message: e.message, name: e.name, stack: e.stack },
            })
          : (t = { isError: !1, value: e }),
        [t, []]
      );
    },
    deserialize(e) {
      throw e.isError
        ? Object.assign(new Error(e.value.message), e.value)
        : e.value;
    },
  },
  A = new Map([
    ["proxy", j],
    ["throw", H],
  ]);
function U(e, t) {
  for (const r of e)
    if (t === r || r === "*" || (r instanceof RegExp && r.test(t))) return !0;
  return !1;
}
function M(e, t = globalThis, r = ["*"]) {
  (t.addEventListener("message", function a(n) {
    if (!n || !n.data) return;
    if (!U(r, n.origin)) {
      console.warn(`Invalid origin '${n.origin}' for comlink proxy`);
      return;
    }
    const { id: o, type: f, path: l } = Object.assign({ path: [] }, n.data),
      u = (n.data.argumentList || []).map(d);
    let s;
    try {
      const i = l.slice(0, -1).reduce((c, y) => c[y], e),
        g = l.reduce((c, y) => c[y], e);
      switch (f) {
        case "GET":
          s = g;
          break;
        case "SET":
          ((i[l.slice(-1)[0]] = d(n.data.value)), (s = !0));
          break;
        case "APPLY":
          s = g.apply(i, u);
          break;
        case "CONSTRUCT":
          {
            const c = new g(...u);
            s = Y(c);
          }
          break;
        case "ENDPOINT":
          {
            const { port1: c, port2: y } = new MessageChannel();
            (M(e, y), (s = w(c, [c])));
          }
          break;
        case "RELEASE":
          s = void 0;
          break;
        default:
          return;
      }
    } catch (i) {
      s = { value: i, [b]: 0 };
    }
    Promise.resolve(s)
      .catch((i) => ({ value: i, [b]: 0 }))
      .then((i) => {
        const [g, c] = x(i);
        (t.postMessage(Object.assign(Object.assign({}, g), { id: o }), c),
          f === "RELEASE" &&
            (t.removeEventListener("message", a),
            O(t),
            T in e && typeof e[T] == "function" && e[T]()));
      })
      .catch((i) => {
        const [g, c] = x({
          value: new TypeError("Unserializable return value"),
          [b]: 0,
        });
        t.postMessage(Object.assign(Object.assign({}, g), { id: o }), c);
      });
  }),
    t.start && t.start());
}
function V(e) {
  return e.constructor.name === "MessagePort";
}
function O(e) {
  V(e) && e.close();
}
function D(e, t) {
  const r = new Map();
  return (
    e.addEventListener("message", function (n) {
      const { data: o } = n;
      if (!o || !o.id) return;
      const f = r.get(o.id);
      if (f)
        try {
          f(o);
        } finally {
          r.delete(o.id);
        }
    }),
    S(e, r, [], t)
  );
}
function p(e) {
  if (e) throw new Error("Proxy has been released and is not useable");
}
function L(e) {
  return m(e, new Map(), { type: "RELEASE" }).then(() => {
    O(e);
  });
}
const h = new WeakMap(),
  E =
    "FinalizationRegistry" in globalThis &&
    new FinalizationRegistry((e) => {
      const t = (h.get(e) || 0) - 1;
      (h.set(e, t), t === 0 && L(e));
    });
function W(e, t) {
  const r = (h.get(t) || 0) + 1;
  (h.set(t, r), E && E.register(e, t, e));
}
function v(e) {
  E && E.unregister(e);
}
function S(e, t, r = [], a = function () {}) {
  let n = !1;
  const o = new Proxy(a, {
    get(f, l) {
      if ((p(n), l === F))
        return () => {
          (v(o), L(e), t.clear(), (n = !0));
        };
      if (l === "then") {
        if (r.length === 0) return { then: () => o };
        const u = m(e, t, {
          type: "GET",
          path: r.map((s) => s.toString()),
        }).then(d);
        return u.then.bind(u);
      }
      return S(e, t, [...r, l]);
    },
    set(f, l, u) {
      p(n);
      const [s, i] = x(u);
      return m(
        e,
        t,
        { type: "SET", path: [...r, l].map((g) => g.toString()), value: s },
        i,
      ).then(d);
    },
    apply(f, l, u) {
      p(n);
      const s = r[r.length - 1];
      if (s === z) return m(e, t, { type: "ENDPOINT" }).then(d);
      if (s === "bind") return S(e, t, r.slice(0, -1));
      const [i, g] = C(u);
      return m(
        e,
        t,
        { type: "APPLY", path: r.map((c) => c.toString()), argumentList: i },
        g,
      ).then(d);
    },
    construct(f, l) {
      p(n);
      const [u, s] = C(l);
      return m(
        e,
        t,
        {
          type: "CONSTRUCT",
          path: r.map((i) => i.toString()),
          argumentList: u,
        },
        s,
      ).then(d);
    },
  });
  return (W(o, e), o);
}
function B(e) {
  return Array.prototype.concat.apply([], e);
}
function C(e) {
  const t = e.map(x);
  return [t.map((r) => r[0]), B(t.map((r) => r[1]))];
}
const N = new WeakMap();
function w(e, t) {
  return (N.set(e, t), e);
}
function Y(e) {
  return Object.assign(e, { [P]: !0 });
}
function x(e) {
  for (const [t, r] of A)
    if (r.canHandle(e)) {
      const [a, n] = r.serialize(e);
      return [{ type: "HANDLER", name: t, value: a }, n];
    }
  return [{ type: "RAW", value: e }, N.get(e) || []];
}
function d(e) {
  switch (e.type) {
    case "HANDLER":
      return A.get(e.name).deserialize(e.value);
    case "RAW":
      return e.value;
  }
}
function m(e, t, r, a) {
  return new Promise((n) => {
    const o = G();
    (t.set(o, n),
      e.start && e.start(),
      e.postMessage(Object.assign({ id: o }, r), a));
  });
}
function G() {
  return new Array(4)
    .fill(0)
    .map(() => Math.floor(Math.random() * Number.MAX_SAFE_INTEGER).toString(16))
    .join("-");
}
var q = Symbol("getEndpoint"),
  $ = (e) => {
    const t = D(e);
    return new Proxy(t, {
      get(r, a, n) {
        return a === q ? e : Reflect.get(r, a, n);
      },
    });
  };
const K = "OffscreenCanvas" in window;
function X(e, t) {
  const r = e.getContext("2d");
  if (!r) {
    (typeof logger < "u" ? logger : console).error(
      "putImageData: canvas context is null, can't draw image data",
    );
    return;
  }
  const { width: a, height: n } = t;
  ((e.width = a),
    (e.height = n),
    requestAnimationFrame(() => {
      r?.putImageData(new ImageData(t.data, a, n), 0, 0);
    }));
}
const R = $(
  new Worker(
    new URL(
      "" + new URL("worker-Bp-CcYlr.js", import.meta.url).href,
      import.meta.url,
    ),
    { type: "module" },
  ),
);
async function J(e, t) {
  logger.debug("tiff fetch");
  const a = await (await fetch(e)).arrayBuffer();
  if ((logger.debug("tiff image fetched", a.byteLength, "bytes"), K)) {
    const n = t.transferControlToOffscreen();
    logger.debug("tiff worker decoding");
    const o = await R.decodeTIFF(w(a, [a]));
    (logger.debug("tiff worker transferring"),
      await R.draw(w(o, [o.rgba.buffer]), w(n, [n])));
  } else {
    const n = await R.decodeTIFF(w(a, [a]));
    X(t, new ImageData(new Uint8ClampedArray(n.rgba), n.width, n.height));
  }
  logger.debug("tiff worker completed");
}
const ie = ({ src: e, ...t }) => {
  const r = k.useRef(!1),
    [a, n] = k.useState(!0),
    o = k.useCallback(
      (f) => {
        ((r.current = f == null),
          f &&
            (async () => {
              try {
                await J(e, f);
              } finally {
                r.current || n(!1);
              }
            })());
      },
      [e],
    );
  return _.jsx("canvas", {
    className: a ? "img loading" : "img",
    ref: o,
    ...t,
    "data-sentry-component": "TiffImg",
    "data-sentry-source-file": "index.tsx",
  });
};
export { ie as default };
//# sourceMappingURL=index-BGFS_w3o.js.map
