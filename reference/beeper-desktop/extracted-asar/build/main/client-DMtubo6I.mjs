import {
  O as b,
  b as Ke,
  y as bt,
  c as J,
  T as Os,
  E as Ps,
  F as tr,
  z as sr,
  v as nr,
  L as rr,
  i as ir,
  a5 as ar,
  K as or,
  a7 as lr,
  a as Pt,
  Q as cr,
  n as ts,
  V as ur,
  l as _e,
  o as ss,
  A as Ts,
  N as hr,
  h as dr,
  R as fr,
  B as pr,
  d as mr,
  k as _r,
  P as gr,
  U as wr,
} from "./index-BJhQkpW6.mjs";
(function () {
  try {
    var n =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    n.SENTRY_RELEASE = { id: "4.3.209" };
    var e = new n.Error().stack;
    e &&
      ((n._sentryDebugIds = n._sentryDebugIds || {}),
      (n._sentryDebugIds[e] = "7848abd4-0cfb-4332-806e-251fb9b5dd35"),
      (n._sentryDebugIdIdentifier =
        "sentry-dbid-7848abd4-0cfb-4332-806e-251fb9b5dd35"));
  } catch {}
})();
function S(n, e, t, s, r) {
  if (typeof e == "function" ? n !== e || !0 : !e.has(n))
    throw new TypeError(
      "Cannot write private member to an object whose class did not declare it",
    );
  return (e.set(n, t), t);
}
function o(n, e, t, s) {
  if (t === "a" && !s)
    throw new TypeError("Private accessor was defined without a getter");
  if (typeof e == "function" ? n !== e || !s : !e.has(n))
    throw new TypeError(
      "Cannot read private member from an object whose class did not declare it",
    );
  return t === "m" ? s : t === "a" ? s.call(n) : s ? s.value : e.get(n);
}
let Ms = function () {
  const { crypto: n } = globalThis;
  if (n?.randomUUID) return ((Ms = n.randomUUID.bind(n)), n.randomUUID());
  const e = new Uint8Array(1),
    t = n ? () => n.getRandomValues(e)[0] : () => (Math.random() * 255) & 255;
  return "10000000-1000-4000-8000-100000000000".replace(/[018]/g, (s) =>
    (+s ^ (t() & (15 >> (+s / 4)))).toString(16),
  );
};
const yr = /^[a-z][a-z0-9+.-]*:/i,
  br = (n) => yr.test(n);
let W = (n) => ((W = Array.isArray), W(n)),
  ns = W;
function Ns(n) {
  return typeof n != "object" ? {} : (n ?? {});
}
function Sr(n) {
  if (!n) return !0;
  for (const e in n) return !1;
  return !0;
}
function Ar(n, e) {
  return Object.prototype.hasOwnProperty.call(n, e);
}
function dt(n) {
  return n != null && typeof n == "object" && !Array.isArray(n);
}
const xr = (n, e) => {
    if (typeof e != "number" || !Number.isInteger(e))
      throw new b(`${n} must be an integer`);
    if (e < 0) throw new b(`${n} must be a positive integer`);
    return e;
  },
  Cr = (n) => {
    try {
      return JSON.parse(n);
    } catch {
      return;
    }
  },
  ke = (n) => new Promise((e) => setTimeout(e, n)),
  ce = "6.8.0",
  Rr = () =>
    typeof window < "u" &&
    typeof window.document < "u" &&
    typeof navigator < "u";
function vr() {
  return typeof Deno < "u" && Deno.build != null
    ? "deno"
    : typeof EdgeRuntime < "u"
      ? "edge"
      : Object.prototype.toString.call(
            typeof globalThis.process < "u" ? globalThis.process : 0,
          ) === "[object process]"
        ? "node"
        : "unknown";
}
const Ir = () => {
  const n = vr();
  if (n === "deno")
    return {
      "X-Stainless-Lang": "js",
      "X-Stainless-Package-Version": ce,
      "X-Stainless-OS": is(Deno.build.os),
      "X-Stainless-Arch": rs(Deno.build.arch),
      "X-Stainless-Runtime": "deno",
      "X-Stainless-Runtime-Version":
        typeof Deno.version == "string"
          ? Deno.version
          : (Deno.version?.deno ?? "unknown"),
    };
  if (typeof EdgeRuntime < "u")
    return {
      "X-Stainless-Lang": "js",
      "X-Stainless-Package-Version": ce,
      "X-Stainless-OS": "Unknown",
      "X-Stainless-Arch": `other:${EdgeRuntime}`,
      "X-Stainless-Runtime": "edge",
      "X-Stainless-Runtime-Version": globalThis.process.version,
    };
  if (n === "node")
    return {
      "X-Stainless-Lang": "js",
      "X-Stainless-Package-Version": ce,
      "X-Stainless-OS": is(globalThis.process.platform ?? "unknown"),
      "X-Stainless-Arch": rs(globalThis.process.arch ?? "unknown"),
      "X-Stainless-Runtime": "node",
      "X-Stainless-Runtime-Version": globalThis.process.version ?? "unknown",
    };
  const e = $r();
  return e
    ? {
        "X-Stainless-Lang": "js",
        "X-Stainless-Package-Version": ce,
        "X-Stainless-OS": "Unknown",
        "X-Stainless-Arch": "unknown",
        "X-Stainless-Runtime": `browser:${e.browser}`,
        "X-Stainless-Runtime-Version": e.version,
      }
    : {
        "X-Stainless-Lang": "js",
        "X-Stainless-Package-Version": ce,
        "X-Stainless-OS": "Unknown",
        "X-Stainless-Arch": "unknown",
        "X-Stainless-Runtime": "unknown",
        "X-Stainless-Runtime-Version": "unknown",
      };
};
function $r() {
  if (typeof navigator > "u" || !navigator) return null;
  const n = [
    { key: "edge", pattern: /Edge(?:\W+(\d+)\.(\d+)(?:\.(\d+))?)?/ },
    { key: "ie", pattern: /MSIE(?:\W+(\d+)\.(\d+)(?:\.(\d+))?)?/ },
    { key: "ie", pattern: /Trident(?:.*rv\:(\d+)\.(\d+)(?:\.(\d+))?)?/ },
    { key: "chrome", pattern: /Chrome(?:\W+(\d+)\.(\d+)(?:\.(\d+))?)?/ },
    { key: "firefox", pattern: /Firefox(?:\W+(\d+)\.(\d+)(?:\.(\d+))?)?/ },
    {
      key: "safari",
      pattern:
        /(?:Version\W+(\d+)\.(\d+)(?:\.(\d+))?)?(?:\W+Mobile\S*)?\W+Safari/,
    },
  ];
  for (const { key: e, pattern: t } of n) {
    const s = t.exec(navigator.userAgent);
    if (s) {
      const r = s[1] || 0,
        i = s[2] || 0,
        a = s[3] || 0;
      return { browser: e, version: `${r}.${i}.${a}` };
    }
  }
  return null;
}
const rs = (n) =>
    n === "x32"
      ? "x32"
      : n === "x86_64" || n === "x64"
        ? "x64"
        : n === "arm"
          ? "arm"
          : n === "aarch64" || n === "arm64"
            ? "arm64"
            : n
              ? `other:${n}`
              : "unknown",
  is = (n) => (
    (n = n.toLowerCase()),
    n.includes("ios")
      ? "iOS"
      : n === "android"
        ? "Android"
        : n === "darwin"
          ? "MacOS"
          : n === "win32"
            ? "Windows"
            : n === "freebsd"
              ? "FreeBSD"
              : n === "openbsd"
                ? "OpenBSD"
                : n === "linux"
                  ? "Linux"
                  : n
                    ? `Other:${n}`
                    : "Unknown"
  );
let as;
const kr = () => as ?? (as = Ir());
function Er() {
  if (typeof fetch < "u") return fetch;
  throw new Error(
    "`fetch` is not defined as a global; Either pass `fetch` to the client, `new OpenAI({ fetch })` or polyfill the global, `globalThis.fetch = fetch`",
  );
}
function Fs(...n) {
  const e = globalThis.ReadableStream;
  if (typeof e > "u")
    throw new Error(
      "`ReadableStream` is not defined as a global; You will need to polyfill it, `globalThis.ReadableStream = ReadableStream`",
    );
  return new e(...n);
}
function Ls(n) {
  let e =
    Symbol.asyncIterator in n
      ? n[Symbol.asyncIterator]()
      : n[Symbol.iterator]();
  return Fs({
    start() {},
    async pull(t) {
      const { done: s, value: r } = await e.next();
      s ? t.close() : t.enqueue(r);
    },
    async cancel() {
      await e.return?.();
    },
  });
}
function Bs(n) {
  if (n[Symbol.asyncIterator]) return n;
  const e = n.getReader();
  return {
    async next() {
      try {
        const t = await e.read();
        return (t?.done && e.releaseLock(), t);
      } catch (t) {
        throw (e.releaseLock(), t);
      }
    },
    async return() {
      const t = e.cancel();
      return (e.releaseLock(), await t, { done: !0, value: void 0 });
    },
    [Symbol.asyncIterator]() {
      return this;
    },
  };
}
async function Or(n) {
  if (n === null || typeof n != "object") return;
  if (n[Symbol.asyncIterator]) {
    await n[Symbol.asyncIterator]().return?.();
    return;
  }
  const e = n.getReader(),
    t = e.cancel();
  (e.releaseLock(), await t);
}
const Pr = ({ headers: n, body: e }) => ({
    bodyHeaders: { "content-type": "application/json" },
    body: JSON.stringify(e),
  }),
  Ds = "RFC3986",
  Us = (n) => String(n),
  os = { RFC1738: (n) => String(n).replace(/%20/g, "+"), RFC3986: Us },
  Tr = "RFC1738";
let St = (n, e) => (
  (St =
    Object.hasOwn ??
    Function.prototype.call.bind(Object.prototype.hasOwnProperty)),
  St(n, e)
);
const V = (() => {
    const n = [];
    for (let e = 0; e < 256; ++e)
      n.push("%" + ((e < 16 ? "0" : "") + e.toString(16)).toUpperCase());
    return n;
  })(),
  ft = 1024,
  Mr = (n, e, t, s, r) => {
    if (n.length === 0) return n;
    let i = n;
    if (
      (typeof n == "symbol"
        ? (i = Symbol.prototype.toString.call(n))
        : typeof n != "string" && (i = String(n)),
      t === "iso-8859-1")
    )
      return escape(i).replace(/%u[0-9a-f]{4}/gi, function (l) {
        return "%26%23" + parseInt(l.slice(2), 16) + "%3B";
      });
    let a = "";
    for (let l = 0; l < i.length; l += ft) {
      const u = i.length >= ft ? i.slice(l, l + ft) : i,
        f = [];
      for (let g = 0; g < u.length; ++g) {
        let d = u.charCodeAt(g);
        if (
          d === 45 ||
          d === 46 ||
          d === 95 ||
          d === 126 ||
          (d >= 48 && d <= 57) ||
          (d >= 65 && d <= 90) ||
          (d >= 97 && d <= 122) ||
          (r === Tr && (d === 40 || d === 41))
        ) {
          f[f.length] = u.charAt(g);
          continue;
        }
        if (d < 128) {
          f[f.length] = V[d];
          continue;
        }
        if (d < 2048) {
          f[f.length] = V[192 | (d >> 6)] + V[128 | (d & 63)];
          continue;
        }
        if (d < 55296 || d >= 57344) {
          f[f.length] =
            V[224 | (d >> 12)] + V[128 | ((d >> 6) & 63)] + V[128 | (d & 63)];
          continue;
        }
        ((g += 1),
          (d = 65536 + (((d & 1023) << 10) | (u.charCodeAt(g) & 1023))),
          (f[f.length] =
            V[240 | (d >> 18)] +
            V[128 | ((d >> 12) & 63)] +
            V[128 | ((d >> 6) & 63)] +
            V[128 | (d & 63)]));
      }
      a += f.join("");
    }
    return a;
  };
function Nr(n) {
  return !n || typeof n != "object"
    ? !1
    : !!(n.constructor && n.constructor.isBuffer && n.constructor.isBuffer(n));
}
function ls(n, e) {
  if (W(n)) {
    const t = [];
    for (let s = 0; s < n.length; s += 1) t.push(e(n[s]));
    return t;
  }
  return e(n);
}
const Ws = {
    brackets(n) {
      return String(n) + "[]";
    },
    comma: "comma",
    indices(n, e) {
      return String(n) + "[" + e + "]";
    },
    repeat(n) {
      return String(n);
    },
  },
  qs = function (n, e) {
    Array.prototype.push.apply(n, W(e) ? e : [e]);
  };
let cs;
const P = {
  addQueryPrefix: !1,
  allowDots: !1,
  allowEmptyArrays: !1,
  arrayFormat: "indices",
  charset: "utf-8",
  charsetSentinel: !1,
  delimiter: "&",
  encode: !0,
  encodeDotInKeys: !1,
  encoder: Mr,
  encodeValuesOnly: !1,
  format: Ds,
  formatter: Us,
  indices: !1,
  serializeDate(n) {
    return (
      cs ?? (cs = Function.prototype.call.bind(Date.prototype.toISOString))
    )(n);
  },
  skipNulls: !1,
  strictNullHandling: !1,
};
function Fr(n) {
  return (
    typeof n == "string" ||
    typeof n == "number" ||
    typeof n == "boolean" ||
    typeof n == "symbol" ||
    typeof n == "bigint"
  );
}
const pt = {};
function js(n, e, t, s, r, i, a, l, u, f, g, d, w, c, A, y, I, C) {
  let _ = n,
    T = C,
    R = 0,
    X = !1;
  for (; (T = T.get(pt)) !== void 0 && !X;) {
    const $ = T.get(n);
    if (((R += 1), typeof $ < "u")) {
      if ($ === R) throw new RangeError("Cyclic object value");
      X = !0;
    }
    typeof T.get(pt) > "u" && (R = 0);
  }
  if (
    (typeof f == "function"
      ? (_ = f(e, _))
      : _ instanceof Date
        ? (_ = w?.(_))
        : t === "comma" &&
          W(_) &&
          (_ = ls(_, function ($) {
            return $ instanceof Date ? w?.($) : $;
          })),
    _ === null)
  ) {
    if (i) return u && !y ? u(e, P.encoder, I, "key", c) : e;
    _ = "";
  }
  if (Fr(_) || Nr(_)) {
    if (u) {
      const $ = y ? e : u(e, P.encoder, I, "key", c);
      return [A?.($) + "=" + A?.(u(_, P.encoder, I, "value", c))];
    }
    return [A?.(e) + "=" + A?.(String(_))];
  }
  const D = [];
  if (typeof _ > "u") return D;
  let v;
  if (t === "comma" && W(_))
    (y && u && (_ = ls(_, u)),
      (v = [{ value: _.length > 0 ? _.join(",") || null : void 0 }]));
  else if (W(f)) v = f;
  else {
    const $ = Object.keys(_);
    v = g ? $.sort(g) : $;
  }
  const F = l ? String(e).replace(/\./g, "%2E") : String(e),
    M = s && W(_) && _.length === 1 ? F + "[]" : F;
  if (r && W(_) && _.length === 0) return M + "[]";
  for (let $ = 0; $ < v.length; ++$) {
    const E = v[$],
      Zt = typeof E == "object" && typeof E.value < "u" ? E.value : _[E];
    if (a && Zt === null) continue;
    const ht = d && l ? E.replace(/\./g, "%2E") : E,
      er = W(_)
        ? typeof t == "function"
          ? t(M, ht)
          : M
        : M + (d ? "." + ht : "[" + ht + "]");
    C.set(n, R);
    const es = new WeakMap();
    (es.set(pt, C),
      qs(
        D,
        js(
          Zt,
          er,
          t,
          s,
          r,
          i,
          a,
          l,
          t === "comma" && y && W(_) ? null : u,
          f,
          g,
          d,
          w,
          c,
          A,
          y,
          I,
          es,
        ),
      ));
  }
  return D;
}
function Lr(n = P) {
  if (typeof n.allowEmptyArrays < "u" && typeof n.allowEmptyArrays != "boolean")
    throw new TypeError(
      "`allowEmptyArrays` option can only be `true` or `false`, when provided",
    );
  if (typeof n.encodeDotInKeys < "u" && typeof n.encodeDotInKeys != "boolean")
    throw new TypeError(
      "`encodeDotInKeys` option can only be `true` or `false`, when provided",
    );
  if (
    n.encoder !== null &&
    typeof n.encoder < "u" &&
    typeof n.encoder != "function"
  )
    throw new TypeError("Encoder has to be a function.");
  const e = n.charset || P.charset;
  if (
    typeof n.charset < "u" &&
    n.charset !== "utf-8" &&
    n.charset !== "iso-8859-1"
  )
    throw new TypeError(
      "The charset option must be either utf-8, iso-8859-1, or undefined",
    );
  let t = Ds;
  if (typeof n.format < "u") {
    if (!St(os, n.format))
      throw new TypeError("Unknown format option provided.");
    t = n.format;
  }
  const s = os[t];
  let r = P.filter;
  (typeof n.filter == "function" || W(n.filter)) && (r = n.filter);
  let i;
  if (
    (n.arrayFormat && n.arrayFormat in Ws
      ? (i = n.arrayFormat)
      : "indices" in n
        ? (i = n.indices ? "indices" : "repeat")
        : (i = P.arrayFormat),
    "commaRoundTrip" in n && typeof n.commaRoundTrip != "boolean")
  )
    throw new TypeError("`commaRoundTrip` must be a boolean, or absent");
  const a =
    typeof n.allowDots > "u"
      ? n.encodeDotInKeys
        ? !0
        : P.allowDots
      : !!n.allowDots;
  return {
    addQueryPrefix:
      typeof n.addQueryPrefix == "boolean"
        ? n.addQueryPrefix
        : P.addQueryPrefix,
    allowDots: a,
    allowEmptyArrays:
      typeof n.allowEmptyArrays == "boolean"
        ? !!n.allowEmptyArrays
        : P.allowEmptyArrays,
    arrayFormat: i,
    charset: e,
    charsetSentinel:
      typeof n.charsetSentinel == "boolean"
        ? n.charsetSentinel
        : P.charsetSentinel,
    commaRoundTrip: !!n.commaRoundTrip,
    delimiter: typeof n.delimiter > "u" ? P.delimiter : n.delimiter,
    encode: typeof n.encode == "boolean" ? n.encode : P.encode,
    encodeDotInKeys:
      typeof n.encodeDotInKeys == "boolean"
        ? n.encodeDotInKeys
        : P.encodeDotInKeys,
    encoder: typeof n.encoder == "function" ? n.encoder : P.encoder,
    encodeValuesOnly:
      typeof n.encodeValuesOnly == "boolean"
        ? n.encodeValuesOnly
        : P.encodeValuesOnly,
    filter: r,
    format: t,
    formatter: s,
    serializeDate:
      typeof n.serializeDate == "function" ? n.serializeDate : P.serializeDate,
    skipNulls: typeof n.skipNulls == "boolean" ? n.skipNulls : P.skipNulls,
    sort: typeof n.sort == "function" ? n.sort : null,
    strictNullHandling:
      typeof n.strictNullHandling == "boolean"
        ? n.strictNullHandling
        : P.strictNullHandling,
  };
}
function Br(n, e = {}) {
  let t = n;
  const s = Lr(e);
  let r, i;
  typeof s.filter == "function"
    ? ((i = s.filter), (t = i("", t)))
    : W(s.filter) && ((i = s.filter), (r = i));
  const a = [];
  if (typeof t != "object" || t === null) return "";
  const l = Ws[s.arrayFormat],
    u = l === "comma" && s.commaRoundTrip;
  (r || (r = Object.keys(t)), s.sort && r.sort(s.sort));
  const f = new WeakMap();
  for (let w = 0; w < r.length; ++w) {
    const c = r[w];
    (s.skipNulls && t[c] === null) ||
      qs(
        a,
        js(
          t[c],
          c,
          l,
          u,
          s.allowEmptyArrays,
          s.strictNullHandling,
          s.skipNulls,
          s.encodeDotInKeys,
          s.encode ? s.encoder : null,
          s.filter,
          s.sort,
          s.allowDots,
          s.serializeDate,
          s.format,
          s.formatter,
          s.encodeValuesOnly,
          s.charset,
          f,
        ),
      );
  }
  const g = a.join(s.delimiter);
  let d = s.addQueryPrefix === !0 ? "?" : "";
  return (
    s.charsetSentinel &&
      (s.charset === "iso-8859-1"
        ? (d += "utf8=%26%2310003%3B&")
        : (d += "utf8=%E2%9C%93&")),
    g.length > 0 ? d + g : ""
  );
}
function Dr(n) {
  let e = 0;
  for (const r of n) e += r.length;
  const t = new Uint8Array(e);
  let s = 0;
  for (const r of n) (t.set(r, s), (s += r.length));
  return t;
}
let us;
function Tt(n) {
  let e;
  return (us ?? ((e = new globalThis.TextEncoder()), (us = e.encode.bind(e))))(
    n,
  );
}
let hs;
function ds(n) {
  let e;
  return (hs ?? ((e = new globalThis.TextDecoder()), (hs = e.decode.bind(e))))(
    n,
  );
}
var q, j;
class st {
  constructor() {
    (q.set(this, void 0),
      j.set(this, void 0),
      S(this, q, new Uint8Array()),
      S(this, j, null));
  }
  decode(e) {
    if (e == null) return [];
    const t =
      e instanceof ArrayBuffer
        ? new Uint8Array(e)
        : typeof e == "string"
          ? Tt(e)
          : e;
    S(this, q, Dr([o(this, q, "f"), t]));
    const s = [];
    let r;
    for (; (r = Ur(o(this, q, "f"), o(this, j, "f"))) != null;) {
      if (r.carriage && o(this, j, "f") == null) {
        S(this, j, r.index);
        continue;
      }
      if (
        o(this, j, "f") != null &&
        (r.index !== o(this, j, "f") + 1 || r.carriage)
      ) {
        (s.push(ds(o(this, q, "f").subarray(0, o(this, j, "f") - 1))),
          S(this, q, o(this, q, "f").subarray(o(this, j, "f"))),
          S(this, j, null));
        continue;
      }
      const i = o(this, j, "f") !== null ? r.preceding - 1 : r.preceding,
        a = ds(o(this, q, "f").subarray(0, i));
      (s.push(a),
        S(this, q, o(this, q, "f").subarray(r.index)),
        S(this, j, null));
    }
    return s;
  }
  flush() {
    return o(this, q, "f").length
      ? this.decode(`
`)
      : [];
  }
}
((q = new WeakMap()), (j = new WeakMap()));
st.NEWLINE_CHARS = new Set([
  `
`,
  "\r",
]);
st.NEWLINE_REGEXP = /\r\n|[\n\r]/g;
function Ur(n, e) {
  for (let r = e ?? 0; r < n.length; r++) {
    if (n[r] === 10) return { preceding: r, index: r + 1, carriage: !1 };
    if (n[r] === 13) return { preceding: r, index: r + 1, carriage: !0 };
  }
  return null;
}
function Wr(n) {
  for (let s = 0; s < n.length - 1; s++) {
    if ((n[s] === 10 && n[s + 1] === 10) || (n[s] === 13 && n[s + 1] === 13))
      return s + 2;
    if (
      n[s] === 13 &&
      n[s + 1] === 10 &&
      s + 3 < n.length &&
      n[s + 2] === 13 &&
      n[s + 3] === 10
    )
      return s + 4;
  }
  return -1;
}
const Ve = { off: 0, error: 200, warn: 300, info: 400, debug: 500 },
  fs = (n, e, t) => {
    if (n) {
      if (Ar(Ve, n)) return n;
      L(t).warn(
        `${e} was set to ${JSON.stringify(n)}, expected one of ${JSON.stringify(Object.keys(Ve))}`,
      );
    }
  };
function ge() {}
function Oe(n, e, t) {
  return !e || Ve[n] > Ve[t] ? ge : e[n].bind(e);
}
const qr = { error: ge, warn: ge, info: ge, debug: ge };
let ps = new WeakMap();
function L(n) {
  const e = n.logger,
    t = n.logLevel ?? "off";
  if (!e) return qr;
  const s = ps.get(e);
  if (s && s[0] === t) return s[1];
  const r = {
    error: Oe("error", e, t),
    warn: Oe("warn", e, t),
    info: Oe("info", e, t),
    debug: Oe("debug", e, t),
  };
  return (ps.set(e, [t, r]), r);
}
const te = (n) => (
  n.options && ((n.options = { ...n.options }), delete n.options.headers),
  n.headers &&
    (n.headers = Object.fromEntries(
      (n.headers instanceof Headers
        ? [...n.headers]
        : Object.entries(n.headers)
      ).map(([e, t]) => [
        e,
        e.toLowerCase() === "authorization" ||
        e.toLowerCase() === "cookie" ||
        e.toLowerCase() === "set-cookie"
          ? "***"
          : t,
      ]),
    )),
  "retryOfRequestLogID" in n &&
    (n.retryOfRequestLogID && (n.retryOf = n.retryOfRequestLogID),
    delete n.retryOfRequestLogID),
  n
);
var me;
class Q {
  constructor(e, t, s) {
    ((this.iterator = e),
      me.set(this, void 0),
      (this.controller = t),
      S(this, me, s));
  }
  static fromSSEResponse(e, t, s) {
    let r = !1;
    const i = s ? L(s) : console;
    async function* a() {
      if (r)
        throw new b(
          "Cannot iterate over a consumed stream, use `.tee()` to split the stream.",
        );
      r = !0;
      let l = !1;
      try {
        for await (const u of jr(e, t))
          if (!l) {
            if (u.data.startsWith("[DONE]")) {
              l = !0;
              continue;
            }
            if (u.event === null || !u.event.startsWith("thread.")) {
              let f;
              try {
                f = JSON.parse(u.data);
              } catch (g) {
                throw (
                  i.error("Could not parse message into JSON:", u.data),
                  i.error("From chunk:", u.raw),
                  g
                );
              }
              if (f && f.error)
                throw new Ke(void 0, f.error, void 0, e.headers);
              yield f;
            } else {
              let f;
              try {
                f = JSON.parse(u.data);
              } catch (g) {
                throw (
                  console.error("Could not parse message into JSON:", u.data),
                  console.error("From chunk:", u.raw),
                  g
                );
              }
              if (u.event == "error")
                throw new Ke(void 0, f.error, f.message, void 0);
              yield { event: u.event, data: f };
            }
          }
        l = !0;
      } catch (u) {
        if (bt(u)) return;
        throw u;
      } finally {
        l || t.abort();
      }
    }
    return new Q(a, t, s);
  }
  static fromReadableStream(e, t, s) {
    let r = !1;
    async function* i() {
      const l = new st(),
        u = Bs(e);
      for await (const f of u) for (const g of l.decode(f)) yield g;
      for (const f of l.flush()) yield f;
    }
    async function* a() {
      if (r)
        throw new b(
          "Cannot iterate over a consumed stream, use `.tee()` to split the stream.",
        );
      r = !0;
      let l = !1;
      try {
        for await (const u of i()) l || (u && (yield JSON.parse(u)));
        l = !0;
      } catch (u) {
        if (bt(u)) return;
        throw u;
      } finally {
        l || t.abort();
      }
    }
    return new Q(a, t, s);
  }
  [((me = new WeakMap()), Symbol.asyncIterator)]() {
    return this.iterator();
  }
  tee() {
    const e = [],
      t = [],
      s = this.iterator(),
      r = (i) => ({
        next: () => {
          if (i.length === 0) {
            const a = s.next();
            (e.push(a), t.push(a));
          }
          return i.shift();
        },
      });
    return [
      new Q(() => r(e), this.controller, o(this, me, "f")),
      new Q(() => r(t), this.controller, o(this, me, "f")),
    ];
  }
  toReadableStream() {
    const e = this;
    let t;
    return Fs({
      async start() {
        t = e[Symbol.asyncIterator]();
      },
      async pull(s) {
        try {
          const { value: r, done: i } = await t.next();
          if (i) return s.close();
          const a = Tt(
            JSON.stringify(r) +
              `
`,
          );
          s.enqueue(a);
        } catch (r) {
          s.error(r);
        }
      },
      async cancel() {
        await t.return?.();
      },
    });
  }
}
async function* jr(n, e) {
  if (!n.body)
    throw (
      e.abort(),
      typeof globalThis.navigator < "u" &&
      globalThis.navigator.product === "ReactNative"
        ? new b(
            "The default react-native fetch implementation does not support streaming. Please use expo/fetch: https://docs.expo.dev/versions/latest/sdk/expo/#expofetch-api",
          )
        : new b("Attempted to iterate over a response with no body")
    );
  const t = new Xr(),
    s = new st(),
    r = Bs(n.body);
  for await (const i of Hr(r))
    for (const a of s.decode(i)) {
      const l = t.decode(a);
      l && (yield l);
    }
  for (const i of s.flush()) {
    const a = t.decode(i);
    a && (yield a);
  }
}
async function* Hr(n) {
  let e = new Uint8Array();
  for await (const t of n) {
    if (t == null) continue;
    const s =
      t instanceof ArrayBuffer
        ? new Uint8Array(t)
        : typeof t == "string"
          ? Tt(t)
          : t;
    let r = new Uint8Array(e.length + s.length);
    (r.set(e), r.set(s, e.length), (e = r));
    let i;
    for (; (i = Wr(e)) !== -1;) (yield e.slice(0, i), (e = e.slice(i)));
  }
  e.length > 0 && (yield e);
}
class Xr {
  constructor() {
    ((this.event = null), (this.data = []), (this.chunks = []));
  }
  decode(e) {
    if ((e.endsWith("\r") && (e = e.substring(0, e.length - 1)), !e)) {
      if (!this.event && !this.data.length) return null;
      const i = {
        event: this.event,
        data: this.data.join(`
`),
        raw: this.chunks,
      };
      return ((this.event = null), (this.data = []), (this.chunks = []), i);
    }
    if ((this.chunks.push(e), e.startsWith(":"))) return null;
    let [t, s, r] = Jr(e, ":");
    return (
      r.startsWith(" ") && (r = r.substring(1)),
      t === "event" ? (this.event = r) : t === "data" && this.data.push(r),
      null
    );
  }
}
function Jr(n, e) {
  const t = n.indexOf(e);
  return t !== -1
    ? [n.substring(0, t), e, n.substring(t + e.length)]
    : [n, "", ""];
}
async function Hs(n, e) {
  const {
      response: t,
      requestLogID: s,
      retryOfRequestLogID: r,
      startTime: i,
    } = e,
    a = await (async () => {
      if (e.options.stream)
        return (
          L(n).debug("response", t.status, t.url, t.headers, t.body),
          e.options.__streamClass
            ? e.options.__streamClass.fromSSEResponse(t, e.controller, n)
            : Q.fromSSEResponse(t, e.controller, n)
        );
      if (t.status === 204) return null;
      if (e.options.__binaryResponse) return t;
      const u = t.headers.get("content-type")?.split(";")[0]?.trim();
      if (u?.includes("application/json") || u?.endsWith("+json")) {
        const d = await t.json();
        return Xs(d, t);
      }
      return await t.text();
    })();
  return (
    L(n).debug(
      `[${s}] response parsed`,
      te({
        retryOfRequestLogID: r,
        url: t.url,
        status: t.status,
        body: a,
        durationMs: Date.now() - i,
      }),
    ),
    a
  );
}
function Xs(n, e) {
  return !n || typeof n != "object" || Array.isArray(n)
    ? n
    : Object.defineProperty(n, "_request_id", {
        value: e.headers.get("x-request-id"),
        enumerable: !1,
      });
}
var we;
class nt extends Promise {
  constructor(e, t, s = Hs) {
    (super((r) => {
      r(null);
    }),
      (this.responsePromise = t),
      (this.parseResponse = s),
      we.set(this, void 0),
      S(this, we, e));
  }
  _thenUnwrap(e) {
    return new nt(o(this, we, "f"), this.responsePromise, async (t, s) =>
      Xs(e(await this.parseResponse(t, s), s), s.response),
    );
  }
  asResponse() {
    return this.responsePromise.then((e) => e.response);
  }
  async withResponse() {
    const [e, t] = await Promise.all([this.parse(), this.asResponse()]);
    return { data: e, response: t, request_id: t.headers.get("x-request-id") };
  }
  parse() {
    return (
      this.parsedPromise ||
        (this.parsedPromise = this.responsePromise.then((e) =>
          this.parseResponse(o(this, we, "f"), e),
        )),
      this.parsedPromise
    );
  }
  then(e, t) {
    return this.parse().then(e, t);
  }
  catch(e) {
    return this.parse().catch(e);
  }
  finally(e) {
    return this.parse().finally(e);
  }
}
we = new WeakMap();
var Pe;
class Mt {
  constructor(e, t, s, r) {
    (Pe.set(this, void 0),
      S(this, Pe, e),
      (this.options = r),
      (this.response = t),
      (this.body = s));
  }
  hasNextPage() {
    return this.getPaginatedItems().length
      ? this.nextPageRequestOptions() != null
      : !1;
  }
  async getNextPage() {
    const e = this.nextPageRequestOptions();
    if (!e)
      throw new b(
        "No next page expected; please check `.hasNextPage()` before calling `.getNextPage()`.",
      );
    return await o(this, Pe, "f").requestAPIList(this.constructor, e);
  }
  async *iterPages() {
    let e = this;
    for (yield e; e.hasNextPage();) ((e = await e.getNextPage()), yield e);
  }
  async *[((Pe = new WeakMap()), Symbol.asyncIterator)]() {
    for await (const e of this.iterPages())
      for (const t of e.getPaginatedItems()) yield t;
  }
}
class Kr extends nt {
  constructor(e, t, s) {
    super(
      e,
      t,
      async (r, i) => new s(r, i.response, await Hs(r, i), i.options),
    );
  }
  async *[Symbol.asyncIterator]() {
    const e = await this;
    for await (const t of e) yield t;
  }
}
class rt extends Mt {
  constructor(e, t, s, r) {
    (super(e, t, s, r), (this.data = s.data || []), (this.object = s.object));
  }
  getPaginatedItems() {
    return this.data ?? [];
  }
  nextPageRequestOptions() {
    return null;
  }
}
class k extends Mt {
  constructor(e, t, s, r) {
    (super(e, t, s, r),
      (this.data = s.data || []),
      (this.has_more = s.has_more || !1));
  }
  getPaginatedItems() {
    return this.data ?? [];
  }
  hasNextPage() {
    return this.has_more === !1 ? !1 : super.hasNextPage();
  }
  nextPageRequestOptions() {
    const e = this.getPaginatedItems(),
      t = e[e.length - 1]?.id;
    return t
      ? { ...this.options, query: { ...Ns(this.options.query), after: t } }
      : null;
  }
}
class ze extends Mt {
  constructor(e, t, s, r) {
    (super(e, t, s, r),
      (this.data = s.data || []),
      (this.has_more = s.has_more || !1),
      (this.last_id = s.last_id || ""));
  }
  getPaginatedItems() {
    return this.data ?? [];
  }
  hasNextPage() {
    return this.has_more === !1 ? !1 : super.hasNextPage();
  }
  nextPageRequestOptions() {
    const e = this.last_id;
    return e
      ? { ...this.options, query: { ...Ns(this.options.query), after: e } }
      : null;
  }
}
const Js = () => {
  if (typeof File > "u") {
    const { process: n } = globalThis,
      e =
        typeof n?.versions?.node == "string" &&
        parseInt(n.versions.node.split(".")) < 20;
    throw new Error(
      "`File` is not defined as a global, which is required for file uploads." +
        (e
          ? " Update to Node 20 LTS or newer, or set `globalThis.File` to `import('node:buffer').File`."
          : ""),
    );
  }
};
function Re(n, e, t) {
  return (Js(), new File(n, e ?? "unknown_file", t));
}
function Be(n) {
  return (
    (
      (typeof n == "object" &&
        n !== null &&
        (("name" in n && n.name && String(n.name)) ||
          ("url" in n && n.url && String(n.url)) ||
          ("filename" in n && n.filename && String(n.filename)) ||
          ("path" in n && n.path && String(n.path)))) ||
      ""
    )
      .split(/[\\/]/)
      .pop() || void 0
  );
}
const Nt = (n) =>
    n != null &&
    typeof n == "object" &&
    typeof n[Symbol.asyncIterator] == "function",
  ms = async (n, e) => (At(n.body) ? { ...n, body: await Ks(n.body, e) } : n),
  ie = async (n, e) => ({ ...n, body: await Ks(n.body, e) }),
  _s = new WeakMap();
function Vr(n) {
  const e = typeof n == "function" ? n : n.fetch,
    t = _s.get(e);
  if (t) return t;
  const s = (async () => {
    try {
      const r = "Response" in e ? e.Response : (await e("data:,")).constructor,
        i = new FormData();
      return i.toString() !== (await new r(i).text());
    } catch {
      return !0;
    }
  })();
  return (_s.set(e, s), s);
}
const Ks = async (n, e) => {
    if (!(await Vr(e)))
      throw new TypeError(
        "The provided fetch function does not support file uploads with the current global FormData class.",
      );
    const t = new FormData();
    return (
      await Promise.all(Object.entries(n || {}).map(([s, r]) => xt(t, s, r))),
      t
    );
  },
  Vs = (n) => n instanceof Blob && "name" in n,
  zr = (n) =>
    typeof n == "object" &&
    n !== null &&
    (n instanceof Response || Nt(n) || Vs(n)),
  At = (n) => {
    if (zr(n)) return !0;
    if (Array.isArray(n)) return n.some(At);
    if (n && typeof n == "object") {
      for (const e in n) if (At(n[e])) return !0;
    }
    return !1;
  },
  xt = async (n, e, t) => {
    if (t !== void 0) {
      if (t == null)
        throw new TypeError(
          `Received null for "${e}"; to pass null in FormData, you must use the string 'null'`,
        );
      if (typeof t == "string" || typeof t == "number" || typeof t == "boolean")
        n.append(e, String(t));
      else if (t instanceof Response) n.append(e, Re([await t.blob()], Be(t)));
      else if (Nt(t))
        n.append(e, Re([await new Response(Ls(t)).blob()], Be(t)));
      else if (Vs(t)) n.append(e, t, Be(t));
      else if (Array.isArray(t))
        await Promise.all(t.map((s) => xt(n, e + "[]", s)));
      else if (typeof t == "object")
        await Promise.all(
          Object.entries(t).map(([s, r]) => xt(n, `${e}[${s}]`, r)),
        );
      else
        throw new TypeError(
          `Invalid value given to form, expected a string, number, boolean, object, Array, File or Blob but got ${t} instead`,
        );
    }
  },
  zs = (n) =>
    n != null &&
    typeof n == "object" &&
    typeof n.size == "number" &&
    typeof n.type == "string" &&
    typeof n.text == "function" &&
    typeof n.slice == "function" &&
    typeof n.arrayBuffer == "function",
  Qr = (n) =>
    n != null &&
    typeof n == "object" &&
    typeof n.name == "string" &&
    typeof n.lastModified == "number" &&
    zs(n),
  Gr = (n) =>
    n != null &&
    typeof n == "object" &&
    typeof n.url == "string" &&
    typeof n.blob == "function";
async function Yr(n, e, t) {
  if ((Js(), (n = await n), Qr(n)))
    return n instanceof File ? n : Re([await n.arrayBuffer()], n.name);
  if (Gr(n)) {
    const r = await n.blob();
    return (
      e || (e = new URL(n.url).pathname.split(/[\\/]/).pop()),
      Re(await Ct(r), e, t)
    );
  }
  const s = await Ct(n);
  if ((e || (e = Be(n)), !t?.type)) {
    const r = s.find((i) => typeof i == "object" && "type" in i && i.type);
    typeof r == "string" && (t = { ...t, type: r });
  }
  return Re(s, e, t);
}
async function Ct(n) {
  let e = [];
  if (typeof n == "string" || ArrayBuffer.isView(n) || n instanceof ArrayBuffer)
    e.push(n);
  else if (zs(n)) e.push(n instanceof Blob ? n : await n.arrayBuffer());
  else if (Nt(n)) for await (const t of n) e.push(...(await Ct(t)));
  else {
    const t = n?.constructor?.name;
    throw new Error(
      `Unexpected data type: ${typeof n}${t ? `; constructor: ${t}` : ""}${Zr(n)}`,
    );
  }
  return e;
}
function Zr(n) {
  return typeof n != "object" || n === null
    ? ""
    : `; props: [${Object.getOwnPropertyNames(n)
        .map((t) => `"${t}"`)
        .join(", ")}]`;
}
class m {
  constructor(e) {
    this._client = e;
  }
}
function Qs(n) {
  return n.replace(/[^A-Za-z0-9\-._~!$&'()*+,;=:@]+/g, encodeURIComponent);
}
const gs = Object.freeze(Object.create(null)),
  ei = (n = Qs) =>
    function (t, ...s) {
      if (t.length === 1) return t[0];
      let r = !1;
      const i = [],
        a = t.reduce((g, d, w) => {
          /[?#]/.test(d) && (r = !0);
          const c = s[w];
          let A = (r ? encodeURIComponent : n)("" + c);
          return (
            w !== s.length &&
              (c == null ||
                (typeof c == "object" &&
                  c.toString ===
                    Object.getPrototypeOf(
                      Object.getPrototypeOf(c.hasOwnProperty ?? gs) ?? gs,
                    )?.toString)) &&
              ((A = c + ""),
              i.push({
                start: g.length + d.length,
                length: A.length,
                error: `Value of type ${Object.prototype.toString.call(c).slice(8, -1)} is not a valid path parameter`,
              })),
            g + d + (w === s.length ? "" : A)
          );
        }, ""),
        l = a.split(/[?#]/, 1)[0],
        u = /(?<=^|\/)(?:\.|%2e){1,2}(?=\/|$)/gi;
      let f;
      for (; (f = u.exec(l)) !== null;)
        i.push({
          start: f.index,
          length: f[0].length,
          error: `Value "${f[0]}" can't be safely passed as a path parameter`,
        });
      if ((i.sort((g, d) => g.start - d.start), i.length > 0)) {
        let g = 0;
        const d = i.reduce((w, c) => {
          const A = " ".repeat(c.start - g),
            y = "^".repeat(c.length);
          return ((g = c.start + c.length), w + A + y);
        }, "");
        throw new b(`Path parameters result in path with invalid segments:
${i.map((w) => w.error).join(`
`)}
${a}
${d}`);
      }
      return a;
    },
  h = ei(Qs);
let Gs = class extends m {
  list(e, t = {}, s) {
    return this._client.getAPIList(h`/chat/completions/${e}/messages`, k, {
      query: t,
      ...s,
    });
  }
};
const Qe = (n) => n?.role === "assistant",
  Ys = (n) => n?.role === "tool";
var Rt, De, Ue, ye, be, We, Se, Y, Ae, Ge, Ye, ue, Zs;
class Ft {
  constructor() {
    (Rt.add(this),
      (this.controller = new AbortController()),
      De.set(this, void 0),
      Ue.set(this, () => {}),
      ye.set(this, () => {}),
      be.set(this, void 0),
      We.set(this, () => {}),
      Se.set(this, () => {}),
      Y.set(this, {}),
      Ae.set(this, !1),
      Ge.set(this, !1),
      Ye.set(this, !1),
      ue.set(this, !1),
      S(
        this,
        De,
        new Promise((e, t) => {
          (S(this, Ue, e, "f"), S(this, ye, t, "f"));
        }),
      ),
      S(
        this,
        be,
        new Promise((e, t) => {
          (S(this, We, e, "f"), S(this, Se, t, "f"));
        }),
      ),
      o(this, De, "f").catch(() => {}),
      o(this, be, "f").catch(() => {}));
  }
  _run(e) {
    setTimeout(() => {
      e().then(
        () => {
          (this._emitFinal(), this._emit("end"));
        },
        o(this, Rt, "m", Zs).bind(this),
      );
    }, 0);
  }
  _connected() {
    this.ended || (o(this, Ue, "f").call(this), this._emit("connect"));
  }
  get ended() {
    return o(this, Ae, "f");
  }
  get errored() {
    return o(this, Ge, "f");
  }
  get aborted() {
    return o(this, Ye, "f");
  }
  abort() {
    this.controller.abort();
  }
  on(e, t) {
    return (
      (o(this, Y, "f")[e] || (o(this, Y, "f")[e] = [])).push({ listener: t }),
      this
    );
  }
  off(e, t) {
    const s = o(this, Y, "f")[e];
    if (!s) return this;
    const r = s.findIndex((i) => i.listener === t);
    return (r >= 0 && s.splice(r, 1), this);
  }
  once(e, t) {
    return (
      (o(this, Y, "f")[e] || (o(this, Y, "f")[e] = [])).push({
        listener: t,
        once: !0,
      }),
      this
    );
  }
  emitted(e) {
    return new Promise((t, s) => {
      (S(this, ue, !0),
        e !== "error" && this.once("error", s),
        this.once(e, t));
    });
  }
  async done() {
    (S(this, ue, !0), await o(this, be, "f"));
  }
  _emit(e, ...t) {
    if (o(this, Ae, "f")) return;
    e === "end" && (S(this, Ae, !0), o(this, We, "f").call(this));
    const s = o(this, Y, "f")[e];
    if (
      (s &&
        ((o(this, Y, "f")[e] = s.filter((r) => !r.once)),
        s.forEach(({ listener: r }) => r(...t))),
      e === "abort")
    ) {
      const r = t[0];
      (!o(this, ue, "f") && !s?.length && Promise.reject(r),
        o(this, ye, "f").call(this, r),
        o(this, Se, "f").call(this, r),
        this._emit("end"));
      return;
    }
    if (e === "error") {
      const r = t[0];
      (!o(this, ue, "f") && !s?.length && Promise.reject(r),
        o(this, ye, "f").call(this, r),
        o(this, Se, "f").call(this, r),
        this._emit("end"));
    }
  }
  _emitFinal() {}
}
((De = new WeakMap()),
  (Ue = new WeakMap()),
  (ye = new WeakMap()),
  (be = new WeakMap()),
  (We = new WeakMap()),
  (Se = new WeakMap()),
  (Y = new WeakMap()),
  (Ae = new WeakMap()),
  (Ge = new WeakMap()),
  (Ye = new WeakMap()),
  (ue = new WeakMap()),
  (Rt = new WeakSet()),
  (Zs = function (e) {
    if (
      (S(this, Ge, !0),
      e instanceof Error && e.name === "AbortError" && (e = new J()),
      e instanceof J)
    )
      return (S(this, Ye, !0), this._emit("abort", e));
    if (e instanceof b) return this._emit("error", e);
    if (e instanceof Error) {
      const t = new b(e.message);
      return ((t.cause = e), this._emit("error", t));
    }
    return this._emit("error", new b(String(e)));
  }));
function ti(n) {
  return typeof n.parse == "function";
}
var U, vt, Ze, It, $t, kt, en, tn;
const si = 10;
class sn extends Ft {
  constructor() {
    (super(...arguments),
      U.add(this),
      (this._chatCompletions = []),
      (this.messages = []));
  }
  _addChatCompletion(e) {
    (this._chatCompletions.push(e), this._emit("chatCompletion", e));
    const t = e.choices[0]?.message;
    return (t && this._addMessage(t), e);
  }
  _addMessage(e, t = !0) {
    if (("content" in e || (e.content = null), this.messages.push(e), t)) {
      if ((this._emit("message", e), Ys(e) && e.content))
        this._emit("functionToolCallResult", e.content);
      else if (Qe(e) && e.tool_calls)
        for (const s of e.tool_calls)
          s.type === "function" && this._emit("functionToolCall", s.function);
    }
  }
  async finalChatCompletion() {
    await this.done();
    const e = this._chatCompletions[this._chatCompletions.length - 1];
    if (!e) throw new b("stream ended without producing a ChatCompletion");
    return e;
  }
  async finalContent() {
    return (await this.done(), o(this, U, "m", vt).call(this));
  }
  async finalMessage() {
    return (await this.done(), o(this, U, "m", Ze).call(this));
  }
  async finalFunctionToolCall() {
    return (await this.done(), o(this, U, "m", It).call(this));
  }
  async finalFunctionToolCallResult() {
    return (await this.done(), o(this, U, "m", $t).call(this));
  }
  async totalUsage() {
    return (await this.done(), o(this, U, "m", kt).call(this));
  }
  allChatCompletions() {
    return [...this._chatCompletions];
  }
  _emitFinal() {
    const e = this._chatCompletions[this._chatCompletions.length - 1];
    e && this._emit("finalChatCompletion", e);
    const t = o(this, U, "m", Ze).call(this);
    t && this._emit("finalMessage", t);
    const s = o(this, U, "m", vt).call(this);
    s && this._emit("finalContent", s);
    const r = o(this, U, "m", It).call(this);
    r && this._emit("finalFunctionToolCall", r);
    const i = o(this, U, "m", $t).call(this);
    (i != null && this._emit("finalFunctionToolCallResult", i),
      this._chatCompletions.some((a) => a.usage) &&
        this._emit("totalUsage", o(this, U, "m", kt).call(this)));
  }
  async _createChatCompletion(e, t, s) {
    const r = s?.signal;
    (r &&
      (r.aborted && this.controller.abort(),
      r.addEventListener("abort", () => this.controller.abort())),
      o(this, U, "m", en).call(this, t));
    const i = await e.chat.completions.create(
      { ...t, stream: !1 },
      { ...s, signal: this.controller.signal },
    );
    return (this._connected(), this._addChatCompletion(Os(i, t)));
  }
  async _runChatCompletion(e, t, s) {
    for (const r of t.messages) this._addMessage(r, !1);
    return await this._createChatCompletion(e, t, s);
  }
  async _runTools(e, t, s) {
    const r = "tool",
      { tool_choice: i = "auto", stream: a, ...l } = t,
      u = typeof i != "string" && i.type === "function" && i?.function?.name,
      { maxChatCompletions: f = si } = s || {},
      g = t.tools.map((c) => {
        if (Ps(c)) {
          if (!c.$callback)
            throw new b(
              "Tool given to `.runTools()` that does not have an associated function",
            );
          return {
            type: "function",
            function: {
              function: c.$callback,
              name: c.function.name,
              description: c.function.description || "",
              parameters: c.function.parameters,
              parse: c.$parseRaw,
              strict: !0,
            },
          };
        }
        return c;
      }),
      d = {};
    for (const c of g)
      c.type === "function" &&
        (d[c.function.name || c.function.function.name] = c.function);
    const w =
      "tools" in t
        ? g.map((c) =>
            c.type === "function"
              ? {
                  type: "function",
                  function: {
                    name: c.function.name || c.function.function.name,
                    parameters: c.function.parameters,
                    description: c.function.description,
                    strict: c.function.strict,
                  },
                }
              : c,
          )
        : void 0;
    for (const c of t.messages) this._addMessage(c, !1);
    for (let c = 0; c < f; ++c) {
      const y = (
        await this._createChatCompletion(
          e,
          { ...l, tool_choice: i, tools: w, messages: [...this.messages] },
          s,
        )
      ).choices[0]?.message;
      if (!y) throw new b("missing message in ChatCompletion response");
      if (!y.tool_calls?.length) return;
      for (const I of y.tool_calls) {
        if (I.type !== "function") continue;
        const C = I.id,
          { name: _, arguments: T } = I.function,
          R = d[_];
        if (R) {
          if (u && u !== _) {
            const F = `Invalid tool_call: ${JSON.stringify(_)}. ${JSON.stringify(u)} requested. Please try again`;
            this._addMessage({ role: r, tool_call_id: C, content: F });
            continue;
          }
        } else {
          const F = `Invalid tool_call: ${JSON.stringify(_)}. Available options are: ${Object.keys(
            d,
          )
            .map((M) => JSON.stringify(M))
            .join(", ")}. Please try again`;
          this._addMessage({ role: r, tool_call_id: C, content: F });
          continue;
        }
        let X;
        try {
          X = ti(R) ? await R.parse(T) : T;
        } catch (F) {
          const M = F instanceof Error ? F.message : String(F);
          this._addMessage({ role: r, tool_call_id: C, content: M });
          continue;
        }
        const D = await R.function(X, this),
          v = o(this, U, "m", tn).call(this, D);
        if ((this._addMessage({ role: r, tool_call_id: C, content: v }), u))
          return;
      }
    }
  }
}
((U = new WeakSet()),
  (vt = function () {
    return o(this, U, "m", Ze).call(this).content ?? null;
  }),
  (Ze = function () {
    let e = this.messages.length;
    for (; e-- > 0;) {
      const t = this.messages[e];
      if (Qe(t))
        return { ...t, content: t.content ?? null, refusal: t.refusal ?? null };
    }
    throw new b(
      "stream ended without producing a ChatCompletionMessage with role=assistant",
    );
  }),
  (It = function () {
    for (let e = this.messages.length - 1; e >= 0; e--) {
      const t = this.messages[e];
      if (Qe(t) && t?.tool_calls?.length)
        return t.tool_calls.filter((s) => s.type === "function").at(-1)
          ?.function;
    }
  }),
  ($t = function () {
    for (let e = this.messages.length - 1; e >= 0; e--) {
      const t = this.messages[e];
      if (
        Ys(t) &&
        t.content != null &&
        typeof t.content == "string" &&
        this.messages.some(
          (s) =>
            s.role === "assistant" &&
            s.tool_calls?.some(
              (r) => r.type === "function" && r.id === t.tool_call_id,
            ),
        )
      )
        return t.content;
    }
  }),
  (kt = function () {
    const e = { completion_tokens: 0, prompt_tokens: 0, total_tokens: 0 };
    for (const { usage: t } of this._chatCompletions)
      t &&
        ((e.completion_tokens += t.completion_tokens),
        (e.prompt_tokens += t.prompt_tokens),
        (e.total_tokens += t.total_tokens));
    return e;
  }),
  (en = function (e) {
    if (e.n != null && e.n > 1)
      throw new b(
        "ChatCompletion convenience helpers only support n=1 at this time. To use n>1, please use chat.completions.create() directly.",
      );
  }),
  (tn = function (e) {
    return typeof e == "string"
      ? e
      : e === void 0
        ? "undefined"
        : JSON.stringify(e);
  }));
class Lt extends sn {
  static runTools(e, t, s) {
    const r = new Lt(),
      i = {
        ...s,
        headers: { ...s?.headers, "X-Stainless-Helper-Method": "runTools" },
      };
    return (r._run(() => r._runTools(e, t, i)), r);
  }
  _addMessage(e, t = !0) {
    (super._addMessage(e, t),
      Qe(e) && e.content && this._emit("content", e.content));
  }
}
const nn = 1,
  rn = 2,
  an = 4,
  on = 8,
  ln = 16,
  cn = 32,
  un = 64,
  hn = 128,
  dn = 256,
  fn = hn | dn,
  pn = ln | cn | fn | un,
  mn = nn | rn | pn,
  _n = an | on,
  ni = mn | _n,
  N = {
    STR: nn,
    NUM: rn,
    ARR: an,
    OBJ: on,
    NULL: ln,
    BOOL: cn,
    NAN: un,
    INFINITY: hn,
    MINUS_INFINITY: dn,
    INF: fn,
    SPECIAL: pn,
    ATOM: mn,
    COLLECTION: _n,
    ALL: ni,
  };
class ri extends Error {}
class ii extends Error {}
function ai(n, e = N.ALL) {
  if (typeof n != "string")
    throw new TypeError(`expecting str, got ${typeof n}`);
  if (!n.trim()) throw new Error(`${n} is empty`);
  return oi(n.trim(), e);
}
const oi = (n, e) => {
    const t = n.length;
    let s = 0;
    const r = (w) => {
        throw new ri(`${w} at position ${s}`);
      },
      i = (w) => {
        throw new ii(`${w} at position ${s}`);
      },
      a = () => (
        d(),
        s >= t && r("Unexpected end of input"),
        n[s] === '"'
          ? l()
          : n[s] === "{"
            ? u()
            : n[s] === "["
              ? f()
              : n.substring(s, s + 4) === "null" ||
                  (N.NULL & e && t - s < 4 && "null".startsWith(n.substring(s)))
                ? ((s += 4), null)
                : n.substring(s, s + 4) === "true" ||
                    (N.BOOL & e &&
                      t - s < 4 &&
                      "true".startsWith(n.substring(s)))
                  ? ((s += 4), !0)
                  : n.substring(s, s + 5) === "false" ||
                      (N.BOOL & e &&
                        t - s < 5 &&
                        "false".startsWith(n.substring(s)))
                    ? ((s += 5), !1)
                    : n.substring(s, s + 8) === "Infinity" ||
                        (N.INFINITY & e &&
                          t - s < 8 &&
                          "Infinity".startsWith(n.substring(s)))
                      ? ((s += 8), 1 / 0)
                      : n.substring(s, s + 9) === "-Infinity" ||
                          (N.MINUS_INFINITY & e &&
                            1 < t - s &&
                            t - s < 9 &&
                            "-Infinity".startsWith(n.substring(s)))
                        ? ((s += 9), -1 / 0)
                        : n.substring(s, s + 3) === "NaN" ||
                            (N.NAN & e &&
                              t - s < 3 &&
                              "NaN".startsWith(n.substring(s)))
                          ? ((s += 3), NaN)
                          : g()
      ),
      l = () => {
        const w = s;
        let c = !1;
        for (s++; s < t && (n[s] !== '"' || (c && n[s - 1] === "\\"));)
          ((c = n[s] === "\\" ? !c : !1), s++);
        if (n.charAt(s) == '"')
          try {
            return JSON.parse(n.substring(w, ++s - Number(c)));
          } catch (A) {
            i(String(A));
          }
        else if (N.STR & e)
          try {
            return JSON.parse(n.substring(w, s - Number(c)) + '"');
          } catch {
            return JSON.parse(n.substring(w, n.lastIndexOf("\\")) + '"');
          }
        r("Unterminated string literal");
      },
      u = () => {
        (s++, d());
        const w = {};
        try {
          for (; n[s] !== "}";) {
            if ((d(), s >= t && N.OBJ & e)) return w;
            const c = l();
            (d(), s++);
            try {
              const A = a();
              Object.defineProperty(w, c, {
                value: A,
                writable: !0,
                enumerable: !0,
                configurable: !0,
              });
            } catch (A) {
              if (N.OBJ & e) return w;
              throw A;
            }
            (d(), n[s] === "," && s++);
          }
        } catch {
          if (N.OBJ & e) return w;
          r("Expected '}' at end of object");
        }
        return (s++, w);
      },
      f = () => {
        s++;
        const w = [];
        try {
          for (; n[s] !== "]";) (w.push(a()), d(), n[s] === "," && s++);
        } catch {
          if (N.ARR & e) return w;
          r("Expected ']' at end of array");
        }
        return (s++, w);
      },
      g = () => {
        if (s === 0) {
          n === "-" && N.NUM & e && r("Not sure what '-' is");
          try {
            return JSON.parse(n);
          } catch (c) {
            if (N.NUM & e)
              try {
                return n[n.length - 1] === "."
                  ? JSON.parse(n.substring(0, n.lastIndexOf(".")))
                  : JSON.parse(n.substring(0, n.lastIndexOf("e")));
              } catch {}
            i(String(c));
          }
        }
        const w = s;
        for (n[s] === "-" && s++; n[s] && !",]}".includes(n[s]);) s++;
        s == t && !(N.NUM & e) && r("Unterminated number literal");
        try {
          return JSON.parse(n.substring(w, s));
        } catch {
          n.substring(w, s) === "-" && N.NUM & e && r("Not sure what '-' is");
          try {
            return JSON.parse(n.substring(w, n.lastIndexOf("e")));
          } catch (A) {
            i(String(A));
          }
        }
      },
      d = () => {
        for (
          ;
          s < t &&
          ` 
\r	`.includes(n[s]);
        )
          s++;
      };
    return a();
  },
  ws = (n) => ai(n, N.ALL ^ N.NUM);
var O, G, ae, Z, mt, Te, _t, gt, wt, Me, yt, ys;
class $e extends sn {
  constructor(e) {
    (super(),
      O.add(this),
      G.set(this, void 0),
      ae.set(this, void 0),
      Z.set(this, void 0),
      S(this, G, e),
      S(this, ae, []));
  }
  get currentChatCompletionSnapshot() {
    return o(this, Z, "f");
  }
  static fromReadableStream(e) {
    const t = new $e(null);
    return (t._run(() => t._fromReadableStream(e)), t);
  }
  static createChatCompletion(e, t, s) {
    const r = new $e(t);
    return (
      r._run(() =>
        r._runChatCompletion(
          e,
          { ...t, stream: !0 },
          {
            ...s,
            headers: { ...s?.headers, "X-Stainless-Helper-Method": "stream" },
          },
        ),
      ),
      r
    );
  }
  async _createChatCompletion(e, t, s) {
    super._createChatCompletion;
    const r = s?.signal;
    (r &&
      (r.aborted && this.controller.abort(),
      r.addEventListener("abort", () => this.controller.abort())),
      o(this, O, "m", mt).call(this));
    const i = await e.chat.completions.create(
      { ...t, stream: !0 },
      { ...s, signal: this.controller.signal },
    );
    this._connected();
    for await (const a of i) o(this, O, "m", _t).call(this, a);
    if (i.controller.signal?.aborted) throw new J();
    return this._addChatCompletion(o(this, O, "m", Me).call(this));
  }
  async _fromReadableStream(e, t) {
    const s = t?.signal;
    (s &&
      (s.aborted && this.controller.abort(),
      s.addEventListener("abort", () => this.controller.abort())),
      o(this, O, "m", mt).call(this),
      this._connected());
    const r = Q.fromReadableStream(e, this.controller);
    let i;
    for await (const a of r)
      (i &&
        i !== a.id &&
        this._addChatCompletion(o(this, O, "m", Me).call(this)),
        o(this, O, "m", _t).call(this, a),
        (i = a.id));
    if (r.controller.signal?.aborted) throw new J();
    return this._addChatCompletion(o(this, O, "m", Me).call(this));
  }
  [((G = new WeakMap()),
  (ae = new WeakMap()),
  (Z = new WeakMap()),
  (O = new WeakSet()),
  (mt = function () {
    this.ended || S(this, Z, void 0);
  }),
  (Te = function (t) {
    let s = o(this, ae, "f")[t.index];
    return (
      s ||
      ((s = {
        content_done: !1,
        refusal_done: !1,
        logprobs_content_done: !1,
        logprobs_refusal_done: !1,
        done_tool_calls: new Set(),
        current_tool_call_index: null,
      }),
      (o(this, ae, "f")[t.index] = s),
      s)
    );
  }),
  (_t = function (t) {
    if (this.ended) return;
    const s = o(this, O, "m", ys).call(this, t);
    this._emit("chunk", t, s);
    for (const r of t.choices) {
      const i = s.choices[r.index];
      (r.delta.content != null &&
        i.message?.role === "assistant" &&
        i.message?.content &&
        (this._emit("content", r.delta.content, i.message.content),
        this._emit("content.delta", {
          delta: r.delta.content,
          snapshot: i.message.content,
          parsed: i.message.parsed,
        })),
        r.delta.refusal != null &&
          i.message?.role === "assistant" &&
          i.message?.refusal &&
          this._emit("refusal.delta", {
            delta: r.delta.refusal,
            snapshot: i.message.refusal,
          }),
        r.logprobs?.content != null &&
          i.message?.role === "assistant" &&
          this._emit("logprobs.content.delta", {
            content: r.logprobs?.content,
            snapshot: i.logprobs?.content ?? [],
          }),
        r.logprobs?.refusal != null &&
          i.message?.role === "assistant" &&
          this._emit("logprobs.refusal.delta", {
            refusal: r.logprobs?.refusal,
            snapshot: i.logprobs?.refusal ?? [],
          }));
      const a = o(this, O, "m", Te).call(this, i);
      i.finish_reason &&
        (o(this, O, "m", wt).call(this, i),
        a.current_tool_call_index != null &&
          o(this, O, "m", gt).call(this, i, a.current_tool_call_index));
      for (const l of r.delta.tool_calls ?? [])
        (a.current_tool_call_index !== l.index &&
          (o(this, O, "m", wt).call(this, i),
          a.current_tool_call_index != null &&
            o(this, O, "m", gt).call(this, i, a.current_tool_call_index)),
          (a.current_tool_call_index = l.index));
      for (const l of r.delta.tool_calls ?? []) {
        const u = i.message.tool_calls?.[l.index];
        u?.type &&
          (u?.type === "function"
            ? this._emit("tool_calls.function.arguments.delta", {
                name: u.function?.name,
                index: l.index,
                arguments: u.function.arguments,
                parsed_arguments: u.function.parsed_arguments,
                arguments_delta: l.function?.arguments ?? "",
              })
            : (u?.type, void 0));
      }
    }
  }),
  (gt = function (t, s) {
    if (o(this, O, "m", Te).call(this, t).done_tool_calls.has(s)) return;
    const i = t.message.tool_calls?.[s];
    if (!i) throw new Error("no tool call snapshot");
    if (!i.type) throw new Error("tool call snapshot missing `type`");
    if (i.type === "function") {
      const a = o(this, G, "f")?.tools?.find(
        (l) => tr(l) && l.function.name === i.function.name,
      );
      this._emit("tool_calls.function.arguments.done", {
        name: i.function.name,
        index: s,
        arguments: i.function.arguments,
        parsed_arguments: Ps(a)
          ? a.$parseRaw(i.function.arguments)
          : a?.function.strict
            ? JSON.parse(i.function.arguments)
            : null,
      });
    } else i.type;
  }),
  (wt = function (t) {
    const s = o(this, O, "m", Te).call(this, t);
    if (t.message.content && !s.content_done) {
      s.content_done = !0;
      const r = o(this, O, "m", yt).call(this);
      this._emit("content.done", {
        content: t.message.content,
        parsed: r ? r.$parseRaw(t.message.content) : null,
      });
    }
    (t.message.refusal &&
      !s.refusal_done &&
      ((s.refusal_done = !0),
      this._emit("refusal.done", { refusal: t.message.refusal })),
      t.logprobs?.content &&
        !s.logprobs_content_done &&
        ((s.logprobs_content_done = !0),
        this._emit("logprobs.content.done", { content: t.logprobs.content })),
      t.logprobs?.refusal &&
        !s.logprobs_refusal_done &&
        ((s.logprobs_refusal_done = !0),
        this._emit("logprobs.refusal.done", { refusal: t.logprobs.refusal })));
  }),
  (Me = function () {
    if (this.ended) throw new b("stream has ended, this shouldn't happen");
    const t = o(this, Z, "f");
    if (!t) throw new b("request ended without sending any chunks");
    return (S(this, Z, void 0), S(this, ae, []), li(t, o(this, G, "f")));
  }),
  (yt = function () {
    const t = o(this, G, "f")?.response_format;
    return sr(t) ? t : null;
  }),
  (ys = function (t) {
    var s, r, i, a;
    let l = o(this, Z, "f");
    const { choices: u, ...f } = t;
    l ? Object.assign(l, f) : (l = S(this, Z, { ...f, choices: [] }));
    for (const {
      delta: g,
      finish_reason: d,
      index: w,
      logprobs: c = null,
      ...A
    } of t.choices) {
      let y = l.choices[w];
      if (
        (y ||
          (y = l.choices[w] =
            { finish_reason: d, index: w, message: {}, logprobs: c, ...A }),
        c)
      )
        if (!y.logprobs) y.logprobs = Object.assign({}, c);
        else {
          const { content: D, refusal: v, ...F } = c;
          (Object.assign(y.logprobs, F),
            D &&
              ((s = y.logprobs).content ?? (s.content = []),
              y.logprobs.content.push(...D)),
            v &&
              ((r = y.logprobs).refusal ?? (r.refusal = []),
              y.logprobs.refusal.push(...v)));
        }
      if (
        d &&
        ((y.finish_reason = d), o(this, G, "f") && nr(o(this, G, "f")))
      ) {
        if (d === "length") throw new rr();
        if (d === "content_filter") throw new ir();
      }
      if ((Object.assign(y, A), !g)) continue;
      const {
        content: I,
        refusal: C,
        function_call: _,
        role: T,
        tool_calls: R,
        ...X
      } = g;
      if (
        (Object.assign(y.message, X),
        C && (y.message.refusal = (y.message.refusal || "") + C),
        T && (y.message.role = T),
        _ &&
          (y.message.function_call
            ? (_.name && (y.message.function_call.name = _.name),
              _.arguments &&
                ((i = y.message.function_call).arguments ?? (i.arguments = ""),
                (y.message.function_call.arguments += _.arguments)))
            : (y.message.function_call = _)),
        I &&
          ((y.message.content = (y.message.content || "") + I),
          !y.message.refusal &&
            o(this, O, "m", yt).call(this) &&
            (y.message.parsed = ws(y.message.content))),
        R)
      ) {
        y.message.tool_calls || (y.message.tool_calls = []);
        for (const { index: D, id: v, type: F, function: M, ...$ } of R) {
          const E = (a = y.message.tool_calls)[D] ?? (a[D] = {});
          (Object.assign(E, $),
            v && (E.id = v),
            F && (E.type = F),
            M &&
              (E.function ??
                (E.function = { name: M.name ?? "", arguments: "" })),
            M?.name && (E.function.name = M.name),
            M?.arguments &&
              ((E.function.arguments += M.arguments),
              ar(o(this, G, "f"), E) &&
                (E.function.parsed_arguments = ws(E.function.arguments))));
        }
      }
    }
    return l;
  }),
  Symbol.asyncIterator)]() {
    const e = [],
      t = [];
    let s = !1;
    return (
      this.on("chunk", (r) => {
        const i = t.shift();
        i ? i.resolve(r) : e.push(r);
      }),
      this.on("end", () => {
        s = !0;
        for (const r of t) r.resolve(void 0);
        t.length = 0;
      }),
      this.on("abort", (r) => {
        s = !0;
        for (const i of t) i.reject(r);
        t.length = 0;
      }),
      this.on("error", (r) => {
        s = !0;
        for (const i of t) i.reject(r);
        t.length = 0;
      }),
      {
        next: async () =>
          e.length
            ? { value: e.shift(), done: !1 }
            : s
              ? { value: void 0, done: !0 }
              : new Promise((i, a) => t.push({ resolve: i, reject: a })).then(
                  (i) =>
                    i ? { value: i, done: !1 } : { value: void 0, done: !0 },
                ),
        return: async () => (this.abort(), { value: void 0, done: !0 }),
      }
    );
  }
  toReadableStream() {
    return new Q(
      this[Symbol.asyncIterator].bind(this),
      this.controller,
    ).toReadableStream();
  }
}
function li(n, e) {
  const {
      id: t,
      choices: s,
      created: r,
      model: i,
      system_fingerprint: a,
      ...l
    } = n,
    u = {
      ...l,
      id: t,
      choices: s.map(
        ({ message: f, finish_reason: g, index: d, logprobs: w, ...c }) => {
          if (!g) throw new b(`missing finish_reason for choice ${d}`);
          const {
              content: A = null,
              function_call: y,
              tool_calls: I,
              ...C
            } = f,
            _ = f.role;
          if (!_) throw new b(`missing role for choice ${d}`);
          if (y) {
            const { arguments: T, name: R } = y;
            if (T == null)
              throw new b(`missing function_call.arguments for choice ${d}`);
            if (!R) throw new b(`missing function_call.name for choice ${d}`);
            return {
              ...c,
              message: {
                content: A,
                function_call: { arguments: T, name: R },
                role: _,
                refusal: f.refusal ?? null,
              },
              finish_reason: g,
              index: d,
              logprobs: w,
            };
          }
          return I
            ? {
                ...c,
                index: d,
                finish_reason: g,
                logprobs: w,
                message: {
                  ...C,
                  role: _,
                  content: A,
                  refusal: f.refusal ?? null,
                  tool_calls: I.map((T, R) => {
                    const { function: X, type: D, id: v, ...F } = T,
                      { arguments: M, name: $, ...E } = X || {};
                    if (v == null)
                      throw new b(`missing choices[${d}].tool_calls[${R}].id
${Ne(n)}`);
                    if (D == null)
                      throw new b(`missing choices[${d}].tool_calls[${R}].type
${Ne(n)}`);
                    if ($ == null)
                      throw new b(`missing choices[${d}].tool_calls[${R}].function.name
${Ne(n)}`);
                    if (M == null)
                      throw new b(`missing choices[${d}].tool_calls[${R}].function.arguments
${Ne(n)}`);
                    return {
                      ...F,
                      id: v,
                      type: D,
                      function: { ...E, name: $, arguments: M },
                    };
                  }),
                },
              }
            : {
                ...c,
                message: {
                  ...C,
                  content: A,
                  role: _,
                  refusal: f.refusal ?? null,
                },
                finish_reason: g,
                index: d,
                logprobs: w,
              };
        },
      ),
      created: r,
      model: i,
      object: "chat.completion",
      ...(a ? { system_fingerprint: a } : {}),
    };
  return or(u, e);
}
function Ne(n) {
  return JSON.stringify(n);
}
class et extends $e {
  static fromReadableStream(e) {
    const t = new et(null);
    return (t._run(() => t._fromReadableStream(e)), t);
  }
  static runTools(e, t, s) {
    const r = new et(t),
      i = {
        ...s,
        headers: { ...s?.headers, "X-Stainless-Helper-Method": "runTools" },
      };
    return (r._run(() => r._runTools(e, t, i)), r);
  }
}
let Bt = class extends m {
  constructor() {
    (super(...arguments), (this.messages = new Gs(this._client)));
  }
  create(e, t) {
    return this._client.post("/chat/completions", {
      body: e,
      ...t,
      stream: e.stream ?? !1,
    });
  }
  retrieve(e, t) {
    return this._client.get(h`/chat/completions/${e}`, t);
  }
  update(e, t, s) {
    return this._client.post(h`/chat/completions/${e}`, { body: t, ...s });
  }
  list(e = {}, t) {
    return this._client.getAPIList("/chat/completions", k, { query: e, ...t });
  }
  delete(e, t) {
    return this._client.delete(h`/chat/completions/${e}`, t);
  }
  parse(e, t) {
    return (
      lr(e.tools),
      this._client.chat.completions
        .create(e, {
          ...t,
          headers: {
            ...t?.headers,
            "X-Stainless-Helper-Method": "chat.completions.parse",
          },
        })
        ._thenUnwrap((s) => Os(s, e))
    );
  }
  runTools(e, t) {
    return e.stream
      ? et.runTools(this._client, e, t)
      : Lt.runTools(this._client, e, t);
  }
  stream(e, t) {
    return $e.createChatCompletion(this._client, e, t);
  }
};
Bt.Messages = Gs;
class Dt extends m {
  constructor() {
    (super(...arguments), (this.completions = new Bt(this._client)));
  }
}
Dt.Completions = Bt;
const gn = Symbol("brand.privateNullableHeaders");
function* ci(n) {
  if (!n) return;
  if (gn in n) {
    const { values: s, nulls: r } = n;
    yield* s.entries();
    for (const i of r) yield [i, null];
    return;
  }
  let e = !1,
    t;
  n instanceof Headers
    ? (t = n.entries())
    : ns(n)
      ? (t = n)
      : ((e = !0), (t = Object.entries(n ?? {})));
  for (let s of t) {
    const r = s[0];
    if (typeof r != "string")
      throw new TypeError("expected header name to be a string");
    const i = ns(s[1]) ? s[1] : [s[1]];
    let a = !1;
    for (const l of i)
      l !== void 0 && (e && !a && ((a = !0), yield [r, null]), yield [r, l]);
  }
}
const p = (n) => {
  const e = new Headers(),
    t = new Set();
  for (const s of n) {
    const r = new Set();
    for (const [i, a] of ci(s)) {
      const l = i.toLowerCase();
      (r.has(l) || (e.delete(i), r.add(l)),
        a === null ? (e.delete(i), t.add(l)) : (e.append(i, a), t.delete(l)));
    }
  }
  return { [gn]: !0, values: e, nulls: t };
};
class wn extends m {
  create(e, t) {
    return this._client.post("/audio/speech", {
      body: e,
      ...t,
      headers: p([{ Accept: "application/octet-stream" }, t?.headers]),
      __binaryResponse: !0,
    });
  }
}
class yn extends m {
  create(e, t) {
    return this._client.post(
      "/audio/transcriptions",
      ie(
        {
          body: e,
          ...t,
          stream: e.stream ?? !1,
          __metadata: { model: e.model },
        },
        this._client,
      ),
    );
  }
}
class bn extends m {
  create(e, t) {
    return this._client.post(
      "/audio/translations",
      ie({ body: e, ...t, __metadata: { model: e.model } }, this._client),
    );
  }
}
class Ee extends m {
  constructor() {
    (super(...arguments),
      (this.transcriptions = new yn(this._client)),
      (this.translations = new bn(this._client)),
      (this.speech = new wn(this._client)));
  }
}
Ee.Transcriptions = yn;
Ee.Translations = bn;
Ee.Speech = wn;
class Sn extends m {
  create(e, t) {
    return this._client.post("/batches", { body: e, ...t });
  }
  retrieve(e, t) {
    return this._client.get(h`/batches/${e}`, t);
  }
  list(e = {}, t) {
    return this._client.getAPIList("/batches", k, { query: e, ...t });
  }
  cancel(e, t) {
    return this._client.post(h`/batches/${e}/cancel`, t);
  }
}
class An extends m {
  create(e, t) {
    return this._client.post("/assistants", {
      body: e,
      ...t,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, t?.headers]),
    });
  }
  retrieve(e, t) {
    return this._client.get(h`/assistants/${e}`, {
      ...t,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, t?.headers]),
    });
  }
  update(e, t, s) {
    return this._client.post(h`/assistants/${e}`, {
      body: t,
      ...s,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
    });
  }
  list(e = {}, t) {
    return this._client.getAPIList("/assistants", k, {
      query: e,
      ...t,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, t?.headers]),
    });
  }
  delete(e, t) {
    return this._client.delete(h`/assistants/${e}`, {
      ...t,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, t?.headers]),
    });
  }
}
let xn = class extends m {
  create(e, t) {
    return this._client.post("/realtime/sessions", {
      body: e,
      ...t,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, t?.headers]),
    });
  }
};
class Cn extends m {
  create(e, t) {
    return this._client.post("/realtime/transcription_sessions", {
      body: e,
      ...t,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, t?.headers]),
    });
  }
}
let it = class extends m {
  constructor() {
    (super(...arguments),
      (this.sessions = new xn(this._client)),
      (this.transcriptionSessions = new Cn(this._client)));
  }
};
it.Sessions = xn;
it.TranscriptionSessions = Cn;
class Rn extends m {
  create(e, t) {
    return this._client.post("/chatkit/sessions", {
      body: e,
      ...t,
      headers: p([{ "OpenAI-Beta": "chatkit_beta=v1" }, t?.headers]),
    });
  }
  cancel(e, t) {
    return this._client.post(h`/chatkit/sessions/${e}/cancel`, {
      ...t,
      headers: p([{ "OpenAI-Beta": "chatkit_beta=v1" }, t?.headers]),
    });
  }
}
let vn = class extends m {
  retrieve(e, t) {
    return this._client.get(h`/chatkit/threads/${e}`, {
      ...t,
      headers: p([{ "OpenAI-Beta": "chatkit_beta=v1" }, t?.headers]),
    });
  }
  list(e = {}, t) {
    return this._client.getAPIList("/chatkit/threads", ze, {
      query: e,
      ...t,
      headers: p([{ "OpenAI-Beta": "chatkit_beta=v1" }, t?.headers]),
    });
  }
  delete(e, t) {
    return this._client.delete(h`/chatkit/threads/${e}`, {
      ...t,
      headers: p([{ "OpenAI-Beta": "chatkit_beta=v1" }, t?.headers]),
    });
  }
  listItems(e, t = {}, s) {
    return this._client.getAPIList(h`/chatkit/threads/${e}/items`, ze, {
      query: t,
      ...s,
      headers: p([{ "OpenAI-Beta": "chatkit_beta=v1" }, s?.headers]),
    });
  }
};
class at extends m {
  constructor() {
    (super(...arguments),
      (this.sessions = new Rn(this._client)),
      (this.threads = new vn(this._client)));
  }
}
at.Sessions = Rn;
at.Threads = vn;
class In extends m {
  create(e, t, s) {
    return this._client.post(h`/threads/${e}/messages`, {
      body: t,
      ...s,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
    });
  }
  retrieve(e, t, s) {
    const { thread_id: r } = t;
    return this._client.get(h`/threads/${r}/messages/${e}`, {
      ...s,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
    });
  }
  update(e, t, s) {
    const { thread_id: r, ...i } = t;
    return this._client.post(h`/threads/${r}/messages/${e}`, {
      body: i,
      ...s,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
    });
  }
  list(e, t = {}, s) {
    return this._client.getAPIList(h`/threads/${e}/messages`, k, {
      query: t,
      ...s,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
    });
  }
  delete(e, t, s) {
    const { thread_id: r } = t;
    return this._client.delete(h`/threads/${r}/messages/${e}`, {
      ...s,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
    });
  }
}
class $n extends m {
  retrieve(e, t, s) {
    const { thread_id: r, run_id: i, ...a } = t;
    return this._client.get(h`/threads/${r}/runs/${i}/steps/${e}`, {
      query: a,
      ...s,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
    });
  }
  list(e, t, s) {
    const { thread_id: r, ...i } = t;
    return this._client.getAPIList(h`/threads/${r}/runs/${e}/steps`, k, {
      query: i,
      ...s,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
    });
  }
}
const ui = (n) => {
    if (typeof Buffer < "u") {
      const e = Buffer.from(n, "base64");
      return Array.from(
        new Float32Array(
          e.buffer,
          e.byteOffset,
          e.length / Float32Array.BYTES_PER_ELEMENT,
        ),
      );
    } else {
      const e = atob(n),
        t = e.length,
        s = new Uint8Array(t);
      for (let r = 0; r < t; r++) s[r] = e.charCodeAt(r);
      return Array.from(new Float32Array(s.buffer));
    }
  },
  oe = (n) => {
    if (typeof globalThis.process < "u")
      return globalThis.process.env?.[n]?.trim() ?? void 0;
    if (typeof globalThis.Deno < "u")
      return globalThis.Deno.env?.get?.(n)?.trim();
  };
var B,
  ne,
  Et,
  z,
  qe,
  K,
  re,
  de,
  se,
  tt,
  H,
  je,
  He,
  ve,
  xe,
  Ce,
  bs,
  Ss,
  As,
  xs,
  Cs,
  Rs,
  vs;
class Ie extends Ft {
  constructor() {
    (super(...arguments),
      B.add(this),
      Et.set(this, []),
      z.set(this, {}),
      qe.set(this, {}),
      K.set(this, void 0),
      re.set(this, void 0),
      de.set(this, void 0),
      se.set(this, void 0),
      tt.set(this, void 0),
      H.set(this, void 0),
      je.set(this, void 0),
      He.set(this, void 0),
      ve.set(this, void 0));
  }
  [((Et = new WeakMap()),
  (z = new WeakMap()),
  (qe = new WeakMap()),
  (K = new WeakMap()),
  (re = new WeakMap()),
  (de = new WeakMap()),
  (se = new WeakMap()),
  (tt = new WeakMap()),
  (H = new WeakMap()),
  (je = new WeakMap()),
  (He = new WeakMap()),
  (ve = new WeakMap()),
  (B = new WeakSet()),
  Symbol.asyncIterator)]() {
    const e = [],
      t = [];
    let s = !1;
    return (
      this.on("event", (r) => {
        const i = t.shift();
        i ? i.resolve(r) : e.push(r);
      }),
      this.on("end", () => {
        s = !0;
        for (const r of t) r.resolve(void 0);
        t.length = 0;
      }),
      this.on("abort", (r) => {
        s = !0;
        for (const i of t) i.reject(r);
        t.length = 0;
      }),
      this.on("error", (r) => {
        s = !0;
        for (const i of t) i.reject(r);
        t.length = 0;
      }),
      {
        next: async () =>
          e.length
            ? { value: e.shift(), done: !1 }
            : s
              ? { value: void 0, done: !0 }
              : new Promise((i, a) => t.push({ resolve: i, reject: a })).then(
                  (i) =>
                    i ? { value: i, done: !1 } : { value: void 0, done: !0 },
                ),
        return: async () => (this.abort(), { value: void 0, done: !0 }),
      }
    );
  }
  static fromReadableStream(e) {
    const t = new ne();
    return (t._run(() => t._fromReadableStream(e)), t);
  }
  async _fromReadableStream(e, t) {
    const s = t?.signal;
    (s &&
      (s.aborted && this.controller.abort(),
      s.addEventListener("abort", () => this.controller.abort())),
      this._connected());
    const r = Q.fromReadableStream(e, this.controller);
    for await (const i of r) o(this, B, "m", xe).call(this, i);
    if (r.controller.signal?.aborted) throw new J();
    return this._addRun(o(this, B, "m", Ce).call(this));
  }
  toReadableStream() {
    return new Q(
      this[Symbol.asyncIterator].bind(this),
      this.controller,
    ).toReadableStream();
  }
  static createToolAssistantStream(e, t, s, r) {
    const i = new ne();
    return (
      i._run(() =>
        i._runToolAssistantStream(e, t, s, {
          ...r,
          headers: { ...r?.headers, "X-Stainless-Helper-Method": "stream" },
        }),
      ),
      i
    );
  }
  async _createToolAssistantStream(e, t, s, r) {
    const i = r?.signal;
    i &&
      (i.aborted && this.controller.abort(),
      i.addEventListener("abort", () => this.controller.abort()));
    const a = { ...s, stream: !0 },
      l = await e.submitToolOutputs(t, a, {
        ...r,
        signal: this.controller.signal,
      });
    this._connected();
    for await (const u of l) o(this, B, "m", xe).call(this, u);
    if (l.controller.signal?.aborted) throw new J();
    return this._addRun(o(this, B, "m", Ce).call(this));
  }
  static createThreadAssistantStream(e, t, s) {
    const r = new ne();
    return (
      r._run(() =>
        r._threadAssistantStream(e, t, {
          ...s,
          headers: { ...s?.headers, "X-Stainless-Helper-Method": "stream" },
        }),
      ),
      r
    );
  }
  static createAssistantStream(e, t, s, r) {
    const i = new ne();
    return (
      i._run(() =>
        i._runAssistantStream(e, t, s, {
          ...r,
          headers: { ...r?.headers, "X-Stainless-Helper-Method": "stream" },
        }),
      ),
      i
    );
  }
  currentEvent() {
    return o(this, je, "f");
  }
  currentRun() {
    return o(this, He, "f");
  }
  currentMessageSnapshot() {
    return o(this, K, "f");
  }
  currentRunStepSnapshot() {
    return o(this, ve, "f");
  }
  async finalRunSteps() {
    return (await this.done(), Object.values(o(this, z, "f")));
  }
  async finalMessages() {
    return (await this.done(), Object.values(o(this, qe, "f")));
  }
  async finalRun() {
    if ((await this.done(), !o(this, re, "f")))
      throw Error("Final run was not received.");
    return o(this, re, "f");
  }
  async _createThreadAssistantStream(e, t, s) {
    const r = s?.signal;
    r &&
      (r.aborted && this.controller.abort(),
      r.addEventListener("abort", () => this.controller.abort()));
    const i = { ...t, stream: !0 },
      a = await e.createAndRun(i, { ...s, signal: this.controller.signal });
    this._connected();
    for await (const l of a) o(this, B, "m", xe).call(this, l);
    if (a.controller.signal?.aborted) throw new J();
    return this._addRun(o(this, B, "m", Ce).call(this));
  }
  async _createAssistantStream(e, t, s, r) {
    const i = r?.signal;
    i &&
      (i.aborted && this.controller.abort(),
      i.addEventListener("abort", () => this.controller.abort()));
    const a = { ...s, stream: !0 },
      l = await e.create(t, a, { ...r, signal: this.controller.signal });
    this._connected();
    for await (const u of l) o(this, B, "m", xe).call(this, u);
    if (l.controller.signal?.aborted) throw new J();
    return this._addRun(o(this, B, "m", Ce).call(this));
  }
  static accumulateDelta(e, t) {
    for (const [s, r] of Object.entries(t)) {
      if (!e.hasOwnProperty(s)) {
        e[s] = r;
        continue;
      }
      let i = e[s];
      if (i == null) {
        e[s] = r;
        continue;
      }
      if (s === "index" || s === "type") {
        e[s] = r;
        continue;
      }
      if (typeof i == "string" && typeof r == "string") i += r;
      else if (typeof i == "number" && typeof r == "number") i += r;
      else if (dt(i) && dt(r)) i = this.accumulateDelta(i, r);
      else if (Array.isArray(i) && Array.isArray(r)) {
        if (i.every((a) => typeof a == "string" || typeof a == "number")) {
          i.push(...r);
          continue;
        }
        for (const a of r) {
          if (!dt(a))
            throw new Error(
              `Expected array delta entry to be an object but got: ${a}`,
            );
          const l = a.index;
          if (l == null)
            throw (
              console.error(a),
              new Error(
                "Expected array delta entry to have an `index` property",
              )
            );
          if (typeof l != "number")
            throw new Error(
              `Expected array delta entry \`index\` property to be a number but got ${l}`,
            );
          const u = i[l];
          u == null ? i.push(a) : (i[l] = this.accumulateDelta(u, a));
        }
        continue;
      } else
        throw Error(
          `Unhandled record type: ${s}, deltaValue: ${r}, accValue: ${i}`,
        );
      e[s] = i;
    }
    return e;
  }
  _addRun(e) {
    return e;
  }
  async _threadAssistantStream(e, t, s) {
    return await this._createThreadAssistantStream(t, e, s);
  }
  async _runAssistantStream(e, t, s, r) {
    return await this._createAssistantStream(t, e, s, r);
  }
  async _runToolAssistantStream(e, t, s, r) {
    return await this._createToolAssistantStream(t, e, s, r);
  }
}
((ne = Ie),
  (xe = function (e) {
    if (!this.ended)
      switch ((S(this, je, e), o(this, B, "m", As).call(this, e), e.event)) {
        case "thread.created":
          break;
        case "thread.run.created":
        case "thread.run.queued":
        case "thread.run.in_progress":
        case "thread.run.requires_action":
        case "thread.run.completed":
        case "thread.run.incomplete":
        case "thread.run.failed":
        case "thread.run.cancelling":
        case "thread.run.cancelled":
        case "thread.run.expired":
          o(this, B, "m", vs).call(this, e);
          break;
        case "thread.run.step.created":
        case "thread.run.step.in_progress":
        case "thread.run.step.delta":
        case "thread.run.step.completed":
        case "thread.run.step.failed":
        case "thread.run.step.cancelled":
        case "thread.run.step.expired":
          o(this, B, "m", Ss).call(this, e);
          break;
        case "thread.message.created":
        case "thread.message.in_progress":
        case "thread.message.delta":
        case "thread.message.completed":
        case "thread.message.incomplete":
          o(this, B, "m", bs).call(this, e);
          break;
        case "error":
          throw new Error(
            "Encountered an error event in event processing - errors should be processed earlier",
          );
      }
  }),
  (Ce = function () {
    if (this.ended) throw new b("stream has ended, this shouldn't happen");
    if (!o(this, re, "f")) throw Error("Final run has not been received");
    return o(this, re, "f");
  }),
  (bs = function (e) {
    const [t, s] = o(this, B, "m", Cs).call(this, e, o(this, K, "f"));
    (S(this, K, t), (o(this, qe, "f")[t.id] = t));
    for (const r of s) {
      const i = t.content[r.index];
      i?.type == "text" && this._emit("textCreated", i.text);
    }
    switch (e.event) {
      case "thread.message.created":
        this._emit("messageCreated", e.data);
        break;
      case "thread.message.in_progress":
        break;
      case "thread.message.delta":
        if ((this._emit("messageDelta", e.data.delta, t), e.data.delta.content))
          for (const r of e.data.delta.content) {
            if (r.type == "text" && r.text) {
              let i = r.text,
                a = t.content[r.index];
              if (a && a.type == "text") this._emit("textDelta", i, a.text);
              else
                throw Error(
                  "The snapshot associated with this text delta is not text or missing",
                );
            }
            if (r.index != o(this, de, "f")) {
              if (o(this, se, "f"))
                switch (o(this, se, "f").type) {
                  case "text":
                    this._emit(
                      "textDone",
                      o(this, se, "f").text,
                      o(this, K, "f"),
                    );
                    break;
                  case "image_file":
                    this._emit(
                      "imageFileDone",
                      o(this, se, "f").image_file,
                      o(this, K, "f"),
                    );
                    break;
                }
              S(this, de, r.index);
            }
            S(this, se, t.content[r.index]);
          }
        break;
      case "thread.message.completed":
      case "thread.message.incomplete":
        if (o(this, de, "f") !== void 0) {
          const r = e.data.content[o(this, de, "f")];
          if (r)
            switch (r.type) {
              case "image_file":
                this._emit("imageFileDone", r.image_file, o(this, K, "f"));
                break;
              case "text":
                this._emit("textDone", r.text, o(this, K, "f"));
                break;
            }
        }
        (o(this, K, "f") && this._emit("messageDone", e.data),
          S(this, K, void 0));
    }
  }),
  (Ss = function (e) {
    const t = o(this, B, "m", xs).call(this, e);
    switch ((S(this, ve, t), e.event)) {
      case "thread.run.step.created":
        this._emit("runStepCreated", e.data);
        break;
      case "thread.run.step.delta":
        const s = e.data.delta;
        if (
          s.step_details &&
          s.step_details.type == "tool_calls" &&
          s.step_details.tool_calls &&
          t.step_details.type == "tool_calls"
        )
          for (const i of s.step_details.tool_calls)
            i.index == o(this, tt, "f")
              ? this._emit(
                  "toolCallDelta",
                  i,
                  t.step_details.tool_calls[i.index],
                )
              : (o(this, H, "f") && this._emit("toolCallDone", o(this, H, "f")),
                S(this, tt, i.index),
                S(this, H, t.step_details.tool_calls[i.index]),
                o(this, H, "f") &&
                  this._emit("toolCallCreated", o(this, H, "f")));
        this._emit("runStepDelta", e.data.delta, t);
        break;
      case "thread.run.step.completed":
      case "thread.run.step.failed":
      case "thread.run.step.cancelled":
      case "thread.run.step.expired":
        (S(this, ve, void 0),
          e.data.step_details.type == "tool_calls" &&
            o(this, H, "f") &&
            (this._emit("toolCallDone", o(this, H, "f")), S(this, H, void 0)),
          this._emit("runStepDone", e.data, t));
        break;
    }
  }),
  (As = function (e) {
    (o(this, Et, "f").push(e), this._emit("event", e));
  }),
  (xs = function (e) {
    switch (e.event) {
      case "thread.run.step.created":
        return ((o(this, z, "f")[e.data.id] = e.data), e.data);
      case "thread.run.step.delta":
        let t = o(this, z, "f")[e.data.id];
        if (!t)
          throw Error("Received a RunStepDelta before creation of a snapshot");
        let s = e.data;
        if (s.delta) {
          const r = ne.accumulateDelta(t, s.delta);
          o(this, z, "f")[e.data.id] = r;
        }
        return o(this, z, "f")[e.data.id];
      case "thread.run.step.completed":
      case "thread.run.step.failed":
      case "thread.run.step.cancelled":
      case "thread.run.step.expired":
      case "thread.run.step.in_progress":
        o(this, z, "f")[e.data.id] = e.data;
        break;
    }
    if (o(this, z, "f")[e.data.id]) return o(this, z, "f")[e.data.id];
    throw new Error("No snapshot available");
  }),
  (Cs = function (e, t) {
    let s = [];
    switch (e.event) {
      case "thread.message.created":
        return [e.data, s];
      case "thread.message.delta":
        if (!t)
          throw Error(
            "Received a delta with no existing snapshot (there should be one from message creation)",
          );
        let r = e.data;
        if (r.delta.content)
          for (const i of r.delta.content)
            if (i.index in t.content) {
              let a = t.content[i.index];
              t.content[i.index] = o(this, B, "m", Rs).call(this, i, a);
            } else ((t.content[i.index] = i), s.push(i));
        return [t, s];
      case "thread.message.in_progress":
      case "thread.message.completed":
      case "thread.message.incomplete":
        if (t) return [t, s];
        throw Error("Received thread message event with no existing snapshot");
    }
    throw Error("Tried to accumulate a non-message event");
  }),
  (Rs = function (e, t) {
    return ne.accumulateDelta(t, e);
  }),
  (vs = function (e) {
    switch ((S(this, He, e.data), e.event)) {
      case "thread.run.created":
        break;
      case "thread.run.queued":
        break;
      case "thread.run.in_progress":
        break;
      case "thread.run.requires_action":
      case "thread.run.cancelled":
      case "thread.run.failed":
      case "thread.run.completed":
      case "thread.run.expired":
      case "thread.run.incomplete":
        (S(this, re, e.data),
          o(this, H, "f") &&
            (this._emit("toolCallDone", o(this, H, "f")), S(this, H, void 0)));
        break;
    }
  }));
let Ut = class extends m {
  constructor() {
    (super(...arguments), (this.steps = new $n(this._client)));
  }
  create(e, t, s) {
    const { include: r, ...i } = t;
    return this._client.post(h`/threads/${e}/runs`, {
      query: { include: r },
      body: i,
      ...s,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
      stream: t.stream ?? !1,
    });
  }
  retrieve(e, t, s) {
    const { thread_id: r } = t;
    return this._client.get(h`/threads/${r}/runs/${e}`, {
      ...s,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
    });
  }
  update(e, t, s) {
    const { thread_id: r, ...i } = t;
    return this._client.post(h`/threads/${r}/runs/${e}`, {
      body: i,
      ...s,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
    });
  }
  list(e, t = {}, s) {
    return this._client.getAPIList(h`/threads/${e}/runs`, k, {
      query: t,
      ...s,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
    });
  }
  cancel(e, t, s) {
    const { thread_id: r } = t;
    return this._client.post(h`/threads/${r}/runs/${e}/cancel`, {
      ...s,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
    });
  }
  async createAndPoll(e, t, s) {
    const r = await this.create(e, t, s);
    return await this.poll(r.id, { thread_id: e }, s);
  }
  createAndStream(e, t, s) {
    return Ie.createAssistantStream(e, this._client.beta.threads.runs, t, s);
  }
  async poll(e, t, s) {
    const r = p([
      s?.headers,
      {
        "X-Stainless-Poll-Helper": "true",
        "X-Stainless-Custom-Poll-Interval":
          s?.pollIntervalMs?.toString() ?? void 0,
      },
    ]);
    for (;;) {
      const { data: i, response: a } = await this.retrieve(e, t, {
        ...s,
        headers: { ...s?.headers, ...r },
      }).withResponse();
      switch (i.status) {
        case "queued":
        case "in_progress":
        case "cancelling":
          let l = 5e3;
          if (s?.pollIntervalMs) l = s.pollIntervalMs;
          else {
            const u = a.headers.get("openai-poll-after-ms");
            if (u) {
              const f = parseInt(u);
              isNaN(f) || (l = f);
            }
          }
          await ke(l);
          break;
        case "requires_action":
        case "incomplete":
        case "cancelled":
        case "completed":
        case "failed":
        case "expired":
          return i;
      }
    }
  }
  stream(e, t, s) {
    return Ie.createAssistantStream(e, this._client.beta.threads.runs, t, s);
  }
  submitToolOutputs(e, t, s) {
    const { thread_id: r, ...i } = t;
    return this._client.post(h`/threads/${r}/runs/${e}/submit_tool_outputs`, {
      body: i,
      ...s,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
      stream: t.stream ?? !1,
    });
  }
  async submitToolOutputsAndPoll(e, t, s) {
    const r = await this.submitToolOutputs(e, t, s);
    return await this.poll(r.id, t, s);
  }
  submitToolOutputsStream(e, t, s) {
    return Ie.createToolAssistantStream(
      e,
      this._client.beta.threads.runs,
      t,
      s,
    );
  }
};
Ut.Steps = $n;
class ot extends m {
  constructor() {
    (super(...arguments),
      (this.runs = new Ut(this._client)),
      (this.messages = new In(this._client)));
  }
  create(e = {}, t) {
    return this._client.post("/threads", {
      body: e,
      ...t,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, t?.headers]),
    });
  }
  retrieve(e, t) {
    return this._client.get(h`/threads/${e}`, {
      ...t,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, t?.headers]),
    });
  }
  update(e, t, s) {
    return this._client.post(h`/threads/${e}`, {
      body: t,
      ...s,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
    });
  }
  delete(e, t) {
    return this._client.delete(h`/threads/${e}`, {
      ...t,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, t?.headers]),
    });
  }
  createAndRun(e, t) {
    return this._client.post("/threads/runs", {
      body: e,
      ...t,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, t?.headers]),
      stream: e.stream ?? !1,
    });
  }
  async createAndRunPoll(e, t) {
    const s = await this.createAndRun(e, t);
    return await this.runs.poll(s.id, { thread_id: s.thread_id }, t);
  }
  createAndRunStream(e, t) {
    return Ie.createThreadAssistantStream(e, this._client.beta.threads, t);
  }
}
ot.Runs = Ut;
ot.Messages = In;
class fe extends m {
  constructor() {
    (super(...arguments),
      (this.realtime = new it(this._client)),
      (this.chatkit = new at(this._client)),
      (this.assistants = new An(this._client)),
      (this.threads = new ot(this._client)));
  }
}
fe.Realtime = it;
fe.ChatKit = at;
fe.Assistants = An;
fe.Threads = ot;
class kn extends m {
  create(e, t) {
    return this._client.post("/completions", {
      body: e,
      ...t,
      stream: e.stream ?? !1,
    });
  }
}
class En extends m {
  retrieve(e, t, s) {
    const { container_id: r } = t;
    return this._client.get(h`/containers/${r}/files/${e}/content`, {
      ...s,
      headers: p([{ Accept: "application/binary" }, s?.headers]),
      __binaryResponse: !0,
    });
  }
}
let Wt = class extends m {
  constructor() {
    (super(...arguments), (this.content = new En(this._client)));
  }
  create(e, t, s) {
    return this._client.post(
      h`/containers/${e}/files`,
      ie({ body: t, ...s }, this._client),
    );
  }
  retrieve(e, t, s) {
    const { container_id: r } = t;
    return this._client.get(h`/containers/${r}/files/${e}`, s);
  }
  list(e, t = {}, s) {
    return this._client.getAPIList(h`/containers/${e}/files`, k, {
      query: t,
      ...s,
    });
  }
  delete(e, t, s) {
    const { container_id: r } = t;
    return this._client.delete(h`/containers/${r}/files/${e}`, {
      ...s,
      headers: p([{ Accept: "*/*" }, s?.headers]),
    });
  }
};
Wt.Content = En;
class qt extends m {
  constructor() {
    (super(...arguments), (this.files = new Wt(this._client)));
  }
  create(e, t) {
    return this._client.post("/containers", { body: e, ...t });
  }
  retrieve(e, t) {
    return this._client.get(h`/containers/${e}`, t);
  }
  list(e = {}, t) {
    return this._client.getAPIList("/containers", k, { query: e, ...t });
  }
  delete(e, t) {
    return this._client.delete(h`/containers/${e}`, {
      ...t,
      headers: p([{ Accept: "*/*" }, t?.headers]),
    });
  }
}
qt.Files = Wt;
class On extends m {
  create(e, t, s) {
    const { include: r, ...i } = t;
    return this._client.post(h`/conversations/${e}/items`, {
      query: { include: r },
      body: i,
      ...s,
    });
  }
  retrieve(e, t, s) {
    const { conversation_id: r, ...i } = t;
    return this._client.get(h`/conversations/${r}/items/${e}`, {
      query: i,
      ...s,
    });
  }
  list(e, t = {}, s) {
    return this._client.getAPIList(h`/conversations/${e}/items`, ze, {
      query: t,
      ...s,
    });
  }
  delete(e, t, s) {
    const { conversation_id: r } = t;
    return this._client.delete(h`/conversations/${r}/items/${e}`, s);
  }
}
class jt extends m {
  constructor() {
    (super(...arguments), (this.items = new On(this._client)));
  }
  create(e = {}, t) {
    return this._client.post("/conversations", { body: e, ...t });
  }
  retrieve(e, t) {
    return this._client.get(h`/conversations/${e}`, t);
  }
  update(e, t, s) {
    return this._client.post(h`/conversations/${e}`, { body: t, ...s });
  }
  delete(e, t) {
    return this._client.delete(h`/conversations/${e}`, t);
  }
}
jt.Items = On;
class Pn extends m {
  create(e, t) {
    const s = !!e.encoding_format;
    let r = s ? e.encoding_format : "base64";
    s &&
      L(this._client).debug(
        "embeddings/user defined encoding_format:",
        e.encoding_format,
      );
    const i = this._client.post("/embeddings", {
      body: { ...e, encoding_format: r },
      ...t,
    });
    return s
      ? i
      : (L(this._client).debug(
          "embeddings/decoding base64 embeddings from base64",
        ),
        i._thenUnwrap(
          (a) => (
            a &&
              a.data &&
              a.data.forEach((l) => {
                const u = l.embedding;
                l.embedding = ui(u);
              }),
            a
          ),
        ));
  }
}
class Tn extends m {
  retrieve(e, t, s) {
    const { eval_id: r, run_id: i } = t;
    return this._client.get(h`/evals/${r}/runs/${i}/output_items/${e}`, s);
  }
  list(e, t, s) {
    const { eval_id: r, ...i } = t;
    return this._client.getAPIList(h`/evals/${r}/runs/${e}/output_items`, k, {
      query: i,
      ...s,
    });
  }
}
class Ht extends m {
  constructor() {
    (super(...arguments), (this.outputItems = new Tn(this._client)));
  }
  create(e, t, s) {
    return this._client.post(h`/evals/${e}/runs`, { body: t, ...s });
  }
  retrieve(e, t, s) {
    const { eval_id: r } = t;
    return this._client.get(h`/evals/${r}/runs/${e}`, s);
  }
  list(e, t = {}, s) {
    return this._client.getAPIList(h`/evals/${e}/runs`, k, { query: t, ...s });
  }
  delete(e, t, s) {
    const { eval_id: r } = t;
    return this._client.delete(h`/evals/${r}/runs/${e}`, s);
  }
  cancel(e, t, s) {
    const { eval_id: r } = t;
    return this._client.post(h`/evals/${r}/runs/${e}`, s);
  }
}
Ht.OutputItems = Tn;
class Xt extends m {
  constructor() {
    (super(...arguments), (this.runs = new Ht(this._client)));
  }
  create(e, t) {
    return this._client.post("/evals", { body: e, ...t });
  }
  retrieve(e, t) {
    return this._client.get(h`/evals/${e}`, t);
  }
  update(e, t, s) {
    return this._client.post(h`/evals/${e}`, { body: t, ...s });
  }
  list(e = {}, t) {
    return this._client.getAPIList("/evals", k, { query: e, ...t });
  }
  delete(e, t) {
    return this._client.delete(h`/evals/${e}`, t);
  }
}
Xt.Runs = Ht;
let Mn = class extends m {
  create(e, t) {
    return this._client.post("/files", ie({ body: e, ...t }, this._client));
  }
  retrieve(e, t) {
    return this._client.get(h`/files/${e}`, t);
  }
  list(e = {}, t) {
    return this._client.getAPIList("/files", k, { query: e, ...t });
  }
  delete(e, t) {
    return this._client.delete(h`/files/${e}`, t);
  }
  content(e, t) {
    return this._client.get(h`/files/${e}/content`, {
      ...t,
      headers: p([{ Accept: "application/binary" }, t?.headers]),
      __binaryResponse: !0,
    });
  }
  async waitForProcessing(
    e,
    { pollInterval: t = 5e3, maxWait: s = 1800 * 1e3 } = {},
  ) {
    const r = new Set(["processed", "error", "deleted"]),
      i = Date.now();
    let a = await this.retrieve(e);
    for (; !a.status || !r.has(a.status);)
      if ((await ke(t), (a = await this.retrieve(e)), Date.now() - i > s))
        throw new Pt({
          message: `Giving up on waiting for file ${e} to finish processing after ${s} milliseconds.`,
        });
    return a;
  }
};
class Nn extends m {}
let Fn = class extends m {
  run(e, t) {
    return this._client.post("/fine_tuning/alpha/graders/run", {
      body: e,
      ...t,
    });
  }
  validate(e, t) {
    return this._client.post("/fine_tuning/alpha/graders/validate", {
      body: e,
      ...t,
    });
  }
};
class Jt extends m {
  constructor() {
    (super(...arguments), (this.graders = new Fn(this._client)));
  }
}
Jt.Graders = Fn;
class Ln extends m {
  create(e, t, s) {
    return this._client.getAPIList(
      h`/fine_tuning/checkpoints/${e}/permissions`,
      rt,
      { body: t, method: "post", ...s },
    );
  }
  retrieve(e, t = {}, s) {
    return this._client.get(h`/fine_tuning/checkpoints/${e}/permissions`, {
      query: t,
      ...s,
    });
  }
  delete(e, t, s) {
    const { fine_tuned_model_checkpoint: r } = t;
    return this._client.delete(
      h`/fine_tuning/checkpoints/${r}/permissions/${e}`,
      s,
    );
  }
}
let Kt = class extends m {
  constructor() {
    (super(...arguments), (this.permissions = new Ln(this._client)));
  }
};
Kt.Permissions = Ln;
class Bn extends m {
  list(e, t = {}, s) {
    return this._client.getAPIList(h`/fine_tuning/jobs/${e}/checkpoints`, k, {
      query: t,
      ...s,
    });
  }
}
class Vt extends m {
  constructor() {
    (super(...arguments), (this.checkpoints = new Bn(this._client)));
  }
  create(e, t) {
    return this._client.post("/fine_tuning/jobs", { body: e, ...t });
  }
  retrieve(e, t) {
    return this._client.get(h`/fine_tuning/jobs/${e}`, t);
  }
  list(e = {}, t) {
    return this._client.getAPIList("/fine_tuning/jobs", k, { query: e, ...t });
  }
  cancel(e, t) {
    return this._client.post(h`/fine_tuning/jobs/${e}/cancel`, t);
  }
  listEvents(e, t = {}, s) {
    return this._client.getAPIList(h`/fine_tuning/jobs/${e}/events`, k, {
      query: t,
      ...s,
    });
  }
  pause(e, t) {
    return this._client.post(h`/fine_tuning/jobs/${e}/pause`, t);
  }
  resume(e, t) {
    return this._client.post(h`/fine_tuning/jobs/${e}/resume`, t);
  }
}
Vt.Checkpoints = Bn;
class pe extends m {
  constructor() {
    (super(...arguments),
      (this.methods = new Nn(this._client)),
      (this.jobs = new Vt(this._client)),
      (this.checkpoints = new Kt(this._client)),
      (this.alpha = new Jt(this._client)));
  }
}
pe.Methods = Nn;
pe.Jobs = Vt;
pe.Checkpoints = Kt;
pe.Alpha = Jt;
class Dn extends m {}
class zt extends m {
  constructor() {
    (super(...arguments), (this.graderModels = new Dn(this._client)));
  }
}
zt.GraderModels = Dn;
class Un extends m {
  createVariation(e, t) {
    return this._client.post(
      "/images/variations",
      ie({ body: e, ...t }, this._client),
    );
  }
  edit(e, t) {
    return this._client.post(
      "/images/edits",
      ie({ body: e, ...t, stream: e.stream ?? !1 }, this._client),
    );
  }
  generate(e, t) {
    return this._client.post("/images/generations", {
      body: e,
      ...t,
      stream: e.stream ?? !1,
    });
  }
}
class Wn extends m {
  retrieve(e, t) {
    return this._client.get(h`/models/${e}`, t);
  }
  list(e) {
    return this._client.getAPIList("/models", rt, e);
  }
  delete(e, t) {
    return this._client.delete(h`/models/${e}`, t);
  }
}
class qn extends m {
  create(e, t) {
    return this._client.post("/moderations", { body: e, ...t });
  }
}
class jn extends m {
  accept(e, t, s) {
    return this._client.post(h`/realtime/calls/${e}/accept`, {
      body: t,
      ...s,
      headers: p([{ Accept: "*/*" }, s?.headers]),
    });
  }
  hangup(e, t) {
    return this._client.post(h`/realtime/calls/${e}/hangup`, {
      ...t,
      headers: p([{ Accept: "*/*" }, t?.headers]),
    });
  }
  refer(e, t, s) {
    return this._client.post(h`/realtime/calls/${e}/refer`, {
      body: t,
      ...s,
      headers: p([{ Accept: "*/*" }, s?.headers]),
    });
  }
  reject(e, t = {}, s) {
    return this._client.post(h`/realtime/calls/${e}/reject`, {
      body: t,
      ...s,
      headers: p([{ Accept: "*/*" }, s?.headers]),
    });
  }
}
class Hn extends m {
  create(e, t) {
    return this._client.post("/realtime/client_secrets", { body: e, ...t });
  }
}
class lt extends m {
  constructor() {
    (super(...arguments),
      (this.clientSecrets = new Hn(this._client)),
      (this.calls = new jn(this._client)));
  }
}
lt.ClientSecrets = Hn;
lt.Calls = jn;
var le, Fe, ee, Le, Is, $s, ks, Es;
class Qt extends Ft {
  constructor(e) {
    (super(),
      le.add(this),
      Fe.set(this, void 0),
      ee.set(this, void 0),
      Le.set(this, void 0),
      S(this, Fe, e));
  }
  static createResponse(e, t, s) {
    const r = new Qt(t);
    return (
      r._run(() =>
        r._createOrRetrieveResponse(e, t, {
          ...s,
          headers: { ...s?.headers, "X-Stainless-Helper-Method": "stream" },
        }),
      ),
      r
    );
  }
  async _createOrRetrieveResponse(e, t, s) {
    const r = s?.signal;
    (r &&
      (r.aborted && this.controller.abort(),
      r.addEventListener("abort", () => this.controller.abort())),
      o(this, le, "m", Is).call(this));
    let i,
      a = null;
    ("response_id" in t
      ? ((i = await e.responses.retrieve(
          t.response_id,
          { stream: !0 },
          { ...s, signal: this.controller.signal, stream: !0 },
        )),
        (a = t.starting_after ?? null))
      : (i = await e.responses.create(
          { ...t, stream: !0 },
          { ...s, signal: this.controller.signal },
        )),
      this._connected());
    for await (const l of i) o(this, le, "m", $s).call(this, l, a);
    if (i.controller.signal?.aborted) throw new J();
    return o(this, le, "m", ks).call(this);
  }
  [((Fe = new WeakMap()),
  (ee = new WeakMap()),
  (Le = new WeakMap()),
  (le = new WeakSet()),
  (Is = function () {
    this.ended || S(this, ee, void 0);
  }),
  ($s = function (t, s) {
    if (this.ended) return;
    const r = (a, l) => {
        (s == null || l.sequence_number > s) && this._emit(a, l);
      },
      i = o(this, le, "m", Es).call(this, t);
    switch ((r("event", t), t.type)) {
      case "response.output_text.delta": {
        const a = i.output[t.output_index];
        if (!a) throw new b(`missing output at index ${t.output_index}`);
        if (a.type === "message") {
          const l = a.content[t.content_index];
          if (!l) throw new b(`missing content at index ${t.content_index}`);
          if (l.type !== "output_text")
            throw new b(`expected content to be 'output_text', got ${l.type}`);
          r("response.output_text.delta", { ...t, snapshot: l.text });
        }
        break;
      }
      case "response.function_call_arguments.delta": {
        const a = i.output[t.output_index];
        if (!a) throw new b(`missing output at index ${t.output_index}`);
        a.type === "function_call" &&
          r("response.function_call_arguments.delta", {
            ...t,
            snapshot: a.arguments,
          });
        break;
      }
      default:
        r(t.type, t);
        break;
    }
  }),
  (ks = function () {
    if (this.ended) throw new b("stream has ended, this shouldn't happen");
    const t = o(this, ee, "f");
    if (!t) throw new b("request ended without sending any events");
    S(this, ee, void 0);
    const s = hi(t, o(this, Fe, "f"));
    return (S(this, Le, s), s);
  }),
  (Es = function (t) {
    let s = o(this, ee, "f");
    if (!s) {
      if (t.type !== "response.created")
        throw new b(
          `When snapshot hasn't been set yet, expected 'response.created' event, got ${t.type}`,
        );
      return ((s = S(this, ee, t.response)), s);
    }
    switch (t.type) {
      case "response.output_item.added": {
        s.output.push(t.item);
        break;
      }
      case "response.content_part.added": {
        const r = s.output[t.output_index];
        if (!r) throw new b(`missing output at index ${t.output_index}`);
        const i = r.type,
          a = t.part;
        i === "message" && a.type !== "reasoning_text"
          ? r.content.push(a)
          : i === "reasoning" &&
            a.type === "reasoning_text" &&
            (r.content || (r.content = []), r.content.push(a));
        break;
      }
      case "response.output_text.delta": {
        const r = s.output[t.output_index];
        if (!r) throw new b(`missing output at index ${t.output_index}`);
        if (r.type === "message") {
          const i = r.content[t.content_index];
          if (!i) throw new b(`missing content at index ${t.content_index}`);
          if (i.type !== "output_text")
            throw new b(`expected content to be 'output_text', got ${i.type}`);
          i.text += t.delta;
        }
        break;
      }
      case "response.function_call_arguments.delta": {
        const r = s.output[t.output_index];
        if (!r) throw new b(`missing output at index ${t.output_index}`);
        r.type === "function_call" && (r.arguments += t.delta);
        break;
      }
      case "response.reasoning_text.delta": {
        const r = s.output[t.output_index];
        if (!r) throw new b(`missing output at index ${t.output_index}`);
        if (r.type === "reasoning") {
          const i = r.content?.[t.content_index];
          if (!i) throw new b(`missing content at index ${t.content_index}`);
          if (i.type !== "reasoning_text")
            throw new b(
              `expected content to be 'reasoning_text', got ${i.type}`,
            );
          i.text += t.delta;
        }
        break;
      }
      case "response.completed": {
        S(this, ee, t.response);
        break;
      }
    }
    return s;
  }),
  Symbol.asyncIterator)]() {
    const e = [],
      t = [];
    let s = !1;
    return (
      this.on("event", (r) => {
        const i = t.shift();
        i ? i.resolve(r) : e.push(r);
      }),
      this.on("end", () => {
        s = !0;
        for (const r of t) r.resolve(void 0);
        t.length = 0;
      }),
      this.on("abort", (r) => {
        s = !0;
        for (const i of t) i.reject(r);
        t.length = 0;
      }),
      this.on("error", (r) => {
        s = !0;
        for (const i of t) i.reject(r);
        t.length = 0;
      }),
      {
        next: async () =>
          e.length
            ? { value: e.shift(), done: !1 }
            : s
              ? { value: void 0, done: !0 }
              : new Promise((i, a) => t.push({ resolve: i, reject: a })).then(
                  (i) =>
                    i ? { value: i, done: !1 } : { value: void 0, done: !0 },
                ),
        return: async () => (this.abort(), { value: void 0, done: !0 }),
      }
    );
  }
  async finalResponse() {
    await this.done();
    const e = o(this, Le, "f");
    if (!e) throw new b("stream ended without producing a ChatCompletion");
    return e;
  }
}
function hi(n, e) {
  return cr(n, e);
}
class Xn extends m {
  list(e, t = {}, s) {
    return this._client.getAPIList(h`/responses/${e}/input_items`, k, {
      query: t,
      ...s,
    });
  }
}
class Jn extends m {
  count(e = {}, t) {
    return this._client.post("/responses/input_tokens", { body: e, ...t });
  }
}
class ct extends m {
  constructor() {
    (super(...arguments),
      (this.inputItems = new Xn(this._client)),
      (this.inputTokens = new Jn(this._client)));
  }
  create(e, t) {
    return this._client
      .post("/responses", { body: e, ...t, stream: e.stream ?? !1 })
      ._thenUnwrap(
        (s) => ("object" in s && s.object === "response" && ts(s), s),
      );
  }
  retrieve(e, t = {}, s) {
    return this._client
      .get(h`/responses/${e}`, { query: t, ...s, stream: t?.stream ?? !1 })
      ._thenUnwrap(
        (r) => ("object" in r && r.object === "response" && ts(r), r),
      );
  }
  delete(e, t) {
    return this._client.delete(h`/responses/${e}`, {
      ...t,
      headers: p([{ Accept: "*/*" }, t?.headers]),
    });
  }
  parse(e, t) {
    return this._client.responses.create(e, t)._thenUnwrap((s) => ur(s, e));
  }
  stream(e, t) {
    return Qt.createResponse(this._client, e, t);
  }
  cancel(e, t) {
    return this._client.post(h`/responses/${e}/cancel`, t);
  }
}
ct.InputItems = Xn;
ct.InputTokens = Jn;
class Kn extends m {
  create(e, t, s) {
    return this._client.post(
      h`/uploads/${e}/parts`,
      ie({ body: t, ...s }, this._client),
    );
  }
}
class Gt extends m {
  constructor() {
    (super(...arguments), (this.parts = new Kn(this._client)));
  }
  create(e, t) {
    return this._client.post("/uploads", { body: e, ...t });
  }
  cancel(e, t) {
    return this._client.post(h`/uploads/${e}/cancel`, t);
  }
  complete(e, t, s) {
    return this._client.post(h`/uploads/${e}/complete`, { body: t, ...s });
  }
}
Gt.Parts = Kn;
const di = async (n) => {
  const e = await Promise.allSettled(n),
    t = e.filter((r) => r.status === "rejected");
  if (t.length) {
    for (const r of t) console.error(r.reason);
    throw new Error(`${t.length} promise(s) failed - see the above errors`);
  }
  const s = [];
  for (const r of e) r.status === "fulfilled" && s.push(r.value);
  return s;
};
class Vn extends m {
  create(e, t, s) {
    return this._client.post(h`/vector_stores/${e}/file_batches`, {
      body: t,
      ...s,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
    });
  }
  retrieve(e, t, s) {
    const { vector_store_id: r } = t;
    return this._client.get(h`/vector_stores/${r}/file_batches/${e}`, {
      ...s,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
    });
  }
  cancel(e, t, s) {
    const { vector_store_id: r } = t;
    return this._client.post(h`/vector_stores/${r}/file_batches/${e}/cancel`, {
      ...s,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
    });
  }
  async createAndPoll(e, t, s) {
    const r = await this.create(e, t);
    return await this.poll(e, r.id, s);
  }
  listFiles(e, t, s) {
    const { vector_store_id: r, ...i } = t;
    return this._client.getAPIList(
      h`/vector_stores/${r}/file_batches/${e}/files`,
      k,
      {
        query: i,
        ...s,
        headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
      },
    );
  }
  async poll(e, t, s) {
    const r = p([
      s?.headers,
      {
        "X-Stainless-Poll-Helper": "true",
        "X-Stainless-Custom-Poll-Interval":
          s?.pollIntervalMs?.toString() ?? void 0,
      },
    ]);
    for (;;) {
      const { data: i, response: a } = await this.retrieve(
        t,
        { vector_store_id: e },
        { ...s, headers: r },
      ).withResponse();
      switch (i.status) {
        case "in_progress":
          let l = 5e3;
          if (s?.pollIntervalMs) l = s.pollIntervalMs;
          else {
            const u = a.headers.get("openai-poll-after-ms");
            if (u) {
              const f = parseInt(u);
              isNaN(f) || (l = f);
            }
          }
          await ke(l);
          break;
        case "failed":
        case "cancelled":
        case "completed":
          return i;
      }
    }
  }
  async uploadAndPoll(e, { files: t, fileIds: s = [] }, r) {
    if (t == null || t.length == 0)
      throw new Error(
        "No `files` provided to process. If you've already uploaded files you should use `.createAndPoll()` instead",
      );
    const i = r?.maxConcurrency ?? 5,
      a = Math.min(i, t.length),
      l = this._client,
      u = t.values(),
      f = [...s];
    async function g(w) {
      for (let c of w) {
        const A = await l.files.create({ file: c, purpose: "assistants" }, r);
        f.push(A.id);
      }
    }
    const d = Array(a).fill(u).map(g);
    return (await di(d), await this.createAndPoll(e, { file_ids: f }));
  }
}
class zn extends m {
  create(e, t, s) {
    return this._client.post(h`/vector_stores/${e}/files`, {
      body: t,
      ...s,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
    });
  }
  retrieve(e, t, s) {
    const { vector_store_id: r } = t;
    return this._client.get(h`/vector_stores/${r}/files/${e}`, {
      ...s,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
    });
  }
  update(e, t, s) {
    const { vector_store_id: r, ...i } = t;
    return this._client.post(h`/vector_stores/${r}/files/${e}`, {
      body: i,
      ...s,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
    });
  }
  list(e, t = {}, s) {
    return this._client.getAPIList(h`/vector_stores/${e}/files`, k, {
      query: t,
      ...s,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
    });
  }
  delete(e, t, s) {
    const { vector_store_id: r } = t;
    return this._client.delete(h`/vector_stores/${r}/files/${e}`, {
      ...s,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
    });
  }
  async createAndPoll(e, t, s) {
    const r = await this.create(e, t, s);
    return await this.poll(e, r.id, s);
  }
  async poll(e, t, s) {
    const r = p([
      s?.headers,
      {
        "X-Stainless-Poll-Helper": "true",
        "X-Stainless-Custom-Poll-Interval":
          s?.pollIntervalMs?.toString() ?? void 0,
      },
    ]);
    for (;;) {
      const i = await this.retrieve(
          t,
          { vector_store_id: e },
          { ...s, headers: r },
        ).withResponse(),
        a = i.data;
      switch (a.status) {
        case "in_progress":
          let l = 5e3;
          if (s?.pollIntervalMs) l = s.pollIntervalMs;
          else {
            const u = i.response.headers.get("openai-poll-after-ms");
            if (u) {
              const f = parseInt(u);
              isNaN(f) || (l = f);
            }
          }
          await ke(l);
          break;
        case "failed":
        case "completed":
          return a;
      }
    }
  }
  async upload(e, t, s) {
    const r = await this._client.files.create(
      { file: t, purpose: "assistants" },
      s,
    );
    return this.create(e, { file_id: r.id }, s);
  }
  async uploadAndPoll(e, t, s) {
    const r = await this.upload(e, t, s);
    return await this.poll(e, r.id, s);
  }
  content(e, t, s) {
    const { vector_store_id: r } = t;
    return this._client.getAPIList(
      h`/vector_stores/${r}/files/${e}/content`,
      rt,
      { ...s, headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]) },
    );
  }
}
class ut extends m {
  constructor() {
    (super(...arguments),
      (this.files = new zn(this._client)),
      (this.fileBatches = new Vn(this._client)));
  }
  create(e, t) {
    return this._client.post("/vector_stores", {
      body: e,
      ...t,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, t?.headers]),
    });
  }
  retrieve(e, t) {
    return this._client.get(h`/vector_stores/${e}`, {
      ...t,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, t?.headers]),
    });
  }
  update(e, t, s) {
    return this._client.post(h`/vector_stores/${e}`, {
      body: t,
      ...s,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
    });
  }
  list(e = {}, t) {
    return this._client.getAPIList("/vector_stores", k, {
      query: e,
      ...t,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, t?.headers]),
    });
  }
  delete(e, t) {
    return this._client.delete(h`/vector_stores/${e}`, {
      ...t,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, t?.headers]),
    });
  }
  search(e, t, s) {
    return this._client.getAPIList(h`/vector_stores/${e}/search`, rt, {
      body: t,
      method: "post",
      ...s,
      headers: p([{ "OpenAI-Beta": "assistants=v2" }, s?.headers]),
    });
  }
}
ut.Files = zn;
ut.FileBatches = Vn;
class Qn extends m {
  create(e, t) {
    return this._client.post("/videos", ms({ body: e, ...t }, this._client));
  }
  retrieve(e, t) {
    return this._client.get(h`/videos/${e}`, t);
  }
  list(e = {}, t) {
    return this._client.getAPIList("/videos", ze, { query: e, ...t });
  }
  delete(e, t) {
    return this._client.delete(h`/videos/${e}`, t);
  }
  downloadContent(e, t = {}, s) {
    return this._client.get(h`/videos/${e}/content`, {
      query: t,
      ...s,
      headers: p([{ Accept: "application/binary" }, s?.headers]),
      __binaryResponse: !0,
    });
  }
  remix(e, t, s) {
    return this._client.post(
      h`/videos/${e}/remix`,
      ms({ body: t, ...s }, this._client),
    );
  }
}
var he, Gn, Xe;
class Yn extends m {
  constructor() {
    (super(...arguments), he.add(this));
  }
  async unwrap(e, t, s = this._client.webhookSecret, r = 300) {
    return (await this.verifySignature(e, t, s, r), JSON.parse(e));
  }
  async verifySignature(e, t, s = this._client.webhookSecret, r = 300) {
    if (
      typeof crypto > "u" ||
      typeof crypto.subtle.importKey != "function" ||
      typeof crypto.subtle.verify != "function"
    )
      throw new Error(
        "Webhook signature verification is only supported when the `crypto` global is defined",
      );
    o(this, he, "m", Gn).call(this, s);
    const i = p([t]).values,
      a = o(this, he, "m", Xe).call(this, i, "webhook-signature"),
      l = o(this, he, "m", Xe).call(this, i, "webhook-timestamp"),
      u = o(this, he, "m", Xe).call(this, i, "webhook-id"),
      f = parseInt(l, 10);
    if (isNaN(f)) throw new _e("Invalid webhook timestamp format");
    const g = Math.floor(Date.now() / 1e3);
    if (g - f > r) throw new _e("Webhook timestamp is too old");
    if (f > g + r) throw new _e("Webhook timestamp is too new");
    const d = a
        .split(" ")
        .map((y) => (y.startsWith("v1,") ? y.substring(3) : y)),
      w = s.startsWith("whsec_")
        ? Buffer.from(s.replace("whsec_", ""), "base64")
        : Buffer.from(s, "utf-8"),
      c = u ? `${u}.${l}.${e}` : `${l}.${e}`,
      A = await crypto.subtle.importKey(
        "raw",
        w,
        { name: "HMAC", hash: "SHA-256" },
        !1,
        ["verify"],
      );
    for (const y of d)
      try {
        const I = Buffer.from(y, "base64");
        if (
          await crypto.subtle.verify("HMAC", A, I, new TextEncoder().encode(c))
        )
          return;
      } catch {
        continue;
      }
    throw new _e(
      "The given webhook signature does not match the expected signature",
    );
  }
}
((he = new WeakSet()),
  (Gn = function (e) {
    if (typeof e != "string" || e.length === 0)
      throw new Error(
        "The webhook secret must either be set using the env var, OPENAI_WEBHOOK_SECRET, on the client class, OpenAI({ webhookSecret: '123' }), or passed to this function",
      );
  }),
  (Xe = function (e, t) {
    if (!e) throw new Error("Headers are required");
    const s = e.get(t);
    if (s == null) throw new Error(`Missing required header: ${t}`);
    return s;
  }));
var Ot, Yt, Je, Zn;
class x {
  constructor({
    baseURL: e = oe("OPENAI_BASE_URL"),
    apiKey: t = oe("OPENAI_API_KEY"),
    organization: s = oe("OPENAI_ORG_ID") ?? null,
    project: r = oe("OPENAI_PROJECT_ID") ?? null,
    webhookSecret: i = oe("OPENAI_WEBHOOK_SECRET") ?? null,
    ...a
  } = {}) {
    if (
      (Ot.add(this),
      Je.set(this, void 0),
      (this.completions = new kn(this)),
      (this.chat = new Dt(this)),
      (this.embeddings = new Pn(this)),
      (this.files = new Mn(this)),
      (this.images = new Un(this)),
      (this.audio = new Ee(this)),
      (this.moderations = new qn(this)),
      (this.models = new Wn(this)),
      (this.fineTuning = new pe(this)),
      (this.graders = new zt(this)),
      (this.vectorStores = new ut(this)),
      (this.webhooks = new Yn(this)),
      (this.beta = new fe(this)),
      (this.batches = new Sn(this)),
      (this.uploads = new Gt(this)),
      (this.responses = new ct(this)),
      (this.realtime = new lt(this)),
      (this.conversations = new jt(this)),
      (this.evals = new Xt(this)),
      (this.containers = new qt(this)),
      (this.videos = new Qn(this)),
      t === void 0)
    )
      throw new b(
        "Missing credentials. Please pass an `apiKey`, or set the `OPENAI_API_KEY` environment variable.",
      );
    const l = {
      apiKey: t,
      organization: s,
      project: r,
      webhookSecret: i,
      ...a,
      baseURL: e || "https://api.openai.com/v1",
    };
    if (!l.dangerouslyAllowBrowser && Rr())
      throw new b(`It looks like you're running in a browser-like environment.

This is disabled by default, as it risks exposing your secret API credentials to attackers.
If you understand the risks and have appropriate mitigations in place,
you can set the \`dangerouslyAllowBrowser\` option to \`true\`, e.g.,

new OpenAI({ apiKey, dangerouslyAllowBrowser: true });

https://help.openai.com/en/articles/5112595-best-practices-for-api-key-safety
`);
    ((this.baseURL = l.baseURL),
      (this.timeout = l.timeout ?? Yt.DEFAULT_TIMEOUT),
      (this.logger = l.logger ?? console));
    const u = "warn";
    ((this.logLevel = u),
      (this.logLevel =
        fs(l.logLevel, "ClientOptions.logLevel", this) ??
        fs(oe("OPENAI_LOG"), "process.env['OPENAI_LOG']", this) ??
        u),
      (this.fetchOptions = l.fetchOptions),
      (this.maxRetries = l.maxRetries ?? 2),
      (this.fetch = l.fetch ?? Er()),
      S(this, Je, Pr),
      (this._options = l),
      (this.apiKey = typeof t == "string" ? t : "Missing Key"),
      (this.organization = s),
      (this.project = r),
      (this.webhookSecret = i));
  }
  withOptions(e) {
    return new this.constructor({
      ...this._options,
      baseURL: this.baseURL,
      maxRetries: this.maxRetries,
      timeout: this.timeout,
      logger: this.logger,
      logLevel: this.logLevel,
      fetch: this.fetch,
      fetchOptions: this.fetchOptions,
      apiKey: this.apiKey,
      organization: this.organization,
      project: this.project,
      webhookSecret: this.webhookSecret,
      ...e,
    });
  }
  defaultQuery() {
    return this._options.defaultQuery;
  }
  validateHeaders({ values: e, nulls: t }) {}
  async authHeaders(e) {
    return p([{ Authorization: `Bearer ${this.apiKey}` }]);
  }
  stringifyQuery(e) {
    return Br(e, { arrayFormat: "brackets" });
  }
  getUserAgent() {
    return `${this.constructor.name}/JS ${ce}`;
  }
  defaultIdempotencyKey() {
    return `stainless-node-retry-${Ms()}`;
  }
  makeStatusError(e, t, s, r) {
    return Ke.generate(e, t, s, r);
  }
  async _callApiKey() {
    const e = this._options.apiKey;
    if (typeof e != "function") return !1;
    let t;
    try {
      t = await e();
    } catch (s) {
      throw s instanceof b
        ? s
        : new b(`Failed to get token from 'apiKey' function: ${s.message}`, {
            cause: s,
          });
    }
    if (typeof t != "string" || !t)
      throw new b(
        `Expected 'apiKey' function argument to return a string but it returned ${t}`,
      );
    return ((this.apiKey = t), !0);
  }
  buildURL(e, t, s) {
    const r = (!o(this, Ot, "m", Zn).call(this) && s) || this.baseURL,
      i = br(e)
        ? new URL(e)
        : new URL(r + (r.endsWith("/") && e.startsWith("/") ? e.slice(1) : e)),
      a = this.defaultQuery();
    return (
      Sr(a) || (t = { ...a, ...t }),
      typeof t == "object" &&
        t &&
        !Array.isArray(t) &&
        (i.search = this.stringifyQuery(t)),
      i.toString()
    );
  }
  async prepareOptions(e) {
    await this._callApiKey();
  }
  async prepareRequest(e, { url: t, options: s }) {}
  get(e, t) {
    return this.methodRequest("get", e, t);
  }
  post(e, t) {
    return this.methodRequest("post", e, t);
  }
  patch(e, t) {
    return this.methodRequest("patch", e, t);
  }
  put(e, t) {
    return this.methodRequest("put", e, t);
  }
  delete(e, t) {
    return this.methodRequest("delete", e, t);
  }
  methodRequest(e, t, s) {
    return this.request(
      Promise.resolve(s).then((r) => ({ method: e, path: t, ...r })),
    );
  }
  request(e, t = null) {
    return new nt(this, this.makeRequest(e, t, void 0));
  }
  async makeRequest(e, t, s) {
    const r = await e,
      i = r.maxRetries ?? this.maxRetries;
    (t == null && (t = i), await this.prepareOptions(r));
    const {
      req: a,
      url: l,
      timeout: u,
    } = await this.buildRequest(r, { retryCount: i - t });
    await this.prepareRequest(a, { url: l, options: r });
    const f =
        "log_" +
        ((Math.random() * (1 << 24)) | 0).toString(16).padStart(6, "0"),
      g = s === void 0 ? "" : `, retryOf: ${s}`,
      d = Date.now();
    if (
      (L(this).debug(
        `[${f}] sending request`,
        te({
          retryOfRequestLogID: s,
          method: r.method,
          url: l,
          options: r,
          headers: a.headers,
        }),
      ),
      r.signal?.aborted)
    )
      throw new J();
    const w = new AbortController(),
      c = await this.fetchWithTimeout(l, a, u, w).catch(ss),
      A = Date.now();
    if (c instanceof globalThis.Error) {
      const C = `retrying, ${t} attempts remaining`;
      if (r.signal?.aborted) throw new J();
      const _ =
        bt(c) ||
        /timed? ?out/i.test(String(c) + ("cause" in c ? String(c.cause) : ""));
      if (t)
        return (
          L(this).info(
            `[${f}] connection ${_ ? "timed out" : "failed"} - ${C}`,
          ),
          L(this).debug(
            `[${f}] connection ${_ ? "timed out" : "failed"} (${C})`,
            te({
              retryOfRequestLogID: s,
              url: l,
              durationMs: A - d,
              message: c.message,
            }),
          ),
          this.retryRequest(r, t, s ?? f)
        );
      throw (
        L(this).info(
          `[${f}] connection ${_ ? "timed out" : "failed"} - error; no more retries left`,
        ),
        L(this).debug(
          `[${f}] connection ${_ ? "timed out" : "failed"} (error; no more retries left)`,
          te({
            retryOfRequestLogID: s,
            url: l,
            durationMs: A - d,
            message: c.message,
          }),
        ),
        _ ? new Pt() : new Ts({ cause: c })
      );
    }
    const y = [...c.headers.entries()]
        .filter(([C]) => C === "x-request-id")
        .map(([C, _]) => ", " + C + ": " + JSON.stringify(_))
        .join(""),
      I = `[${f}${g}${y}] ${a.method} ${l} ${c.ok ? "succeeded" : "failed"} with status ${c.status} in ${A - d}ms`;
    if (!c.ok) {
      const C = await this.shouldRetry(c);
      if (t && C) {
        const v = `retrying, ${t} attempts remaining`;
        return (
          await Or(c.body),
          L(this).info(`${I} - ${v}`),
          L(this).debug(
            `[${f}] response error (${v})`,
            te({
              retryOfRequestLogID: s,
              url: c.url,
              status: c.status,
              headers: c.headers,
              durationMs: A - d,
            }),
          ),
          this.retryRequest(r, t, s ?? f, c.headers)
        );
      }
      const _ = C ? "error; no more retries left" : "error; not retryable";
      L(this).info(`${I} - ${_}`);
      const T = await c.text().catch((v) => ss(v).message),
        R = Cr(T),
        X = R ? void 0 : T;
      throw (
        L(this).debug(
          `[${f}] response error (${_})`,
          te({
            retryOfRequestLogID: s,
            url: c.url,
            status: c.status,
            headers: c.headers,
            message: X,
            durationMs: Date.now() - d,
          }),
        ),
        this.makeStatusError(c.status, R, X, c.headers)
      );
    }
    return (
      L(this).info(I),
      L(this).debug(
        `[${f}] response start`,
        te({
          retryOfRequestLogID: s,
          url: c.url,
          status: c.status,
          headers: c.headers,
          durationMs: A - d,
        }),
      ),
      {
        response: c,
        options: r,
        controller: w,
        requestLogID: f,
        retryOfRequestLogID: s,
        startTime: d,
      }
    );
  }
  getAPIList(e, t, s) {
    return this.requestAPIList(t, { method: "get", path: e, ...s });
  }
  requestAPIList(e, t) {
    const s = this.makeRequest(t, null, void 0);
    return new Kr(this, s, e);
  }
  async fetchWithTimeout(e, t, s, r) {
    const { signal: i, method: a, ...l } = t || {};
    i && i.addEventListener("abort", () => r.abort());
    const u = setTimeout(() => r.abort(), s),
      f =
        (globalThis.ReadableStream &&
          l.body instanceof globalThis.ReadableStream) ||
        (typeof l.body == "object" &&
          l.body !== null &&
          Symbol.asyncIterator in l.body),
      g = {
        signal: r.signal,
        ...(f ? { duplex: "half" } : {}),
        method: "GET",
        ...l,
      };
    a && (g.method = a.toUpperCase());
    try {
      return await this.fetch.call(void 0, e, g);
    } finally {
      clearTimeout(u);
    }
  }
  async shouldRetry(e) {
    const t = e.headers.get("x-should-retry");
    return t === "true"
      ? !0
      : t === "false"
        ? !1
        : e.status === 408 ||
          e.status === 409 ||
          e.status === 429 ||
          e.status >= 500;
  }
  async retryRequest(e, t, s, r) {
    let i;
    const a = r?.get("retry-after-ms");
    if (a) {
      const u = parseFloat(a);
      Number.isNaN(u) || (i = u);
    }
    const l = r?.get("retry-after");
    if (l && !i) {
      const u = parseFloat(l);
      Number.isNaN(u) ? (i = Date.parse(l) - Date.now()) : (i = u * 1e3);
    }
    if (!(i && 0 <= i && i < 60 * 1e3)) {
      const u = e.maxRetries ?? this.maxRetries;
      i = this.calculateDefaultRetryTimeoutMillis(t, u);
    }
    return (await ke(i), this.makeRequest(e, t - 1, s));
  }
  calculateDefaultRetryTimeoutMillis(e, t) {
    const i = t - e,
      a = Math.min(0.5 * Math.pow(2, i), 8),
      l = 1 - Math.random() * 0.25;
    return a * l * 1e3;
  }
  async buildRequest(e, { retryCount: t = 0 } = {}) {
    const s = { ...e },
      { method: r, path: i, query: a, defaultBaseURL: l } = s,
      u = this.buildURL(i, a, l);
    ("timeout" in s && xr("timeout", s.timeout),
      (s.timeout = s.timeout ?? this.timeout));
    const { bodyHeaders: f, body: g } = this.buildBody({ options: s }),
      d = await this.buildHeaders({
        options: e,
        method: r,
        bodyHeaders: f,
        retryCount: t,
      });
    return {
      req: {
        method: r,
        headers: d,
        ...(s.signal && { signal: s.signal }),
        ...(globalThis.ReadableStream &&
          g instanceof globalThis.ReadableStream && { duplex: "half" }),
        ...(g && { body: g }),
        ...(this.fetchOptions ?? {}),
        ...(s.fetchOptions ?? {}),
      },
      url: u,
      timeout: s.timeout,
    };
  }
  async buildHeaders({ options: e, method: t, bodyHeaders: s, retryCount: r }) {
    let i = {};
    this.idempotencyHeader &&
      t !== "get" &&
      (e.idempotencyKey || (e.idempotencyKey = this.defaultIdempotencyKey()),
      (i[this.idempotencyHeader] = e.idempotencyKey));
    const a = p([
      i,
      {
        Accept: "application/json",
        "User-Agent": this.getUserAgent(),
        "X-Stainless-Retry-Count": String(r),
        ...(e.timeout
          ? { "X-Stainless-Timeout": String(Math.trunc(e.timeout / 1e3)) }
          : {}),
        ...kr(),
        "OpenAI-Organization": this.organization,
        "OpenAI-Project": this.project,
      },
      await this.authHeaders(e),
      this._options.defaultHeaders,
      s,
      e.headers,
    ]);
    return (this.validateHeaders(a), a.values);
  }
  buildBody({ options: { body: e, headers: t } }) {
    if (!e) return { bodyHeaders: void 0, body: void 0 };
    const s = p([t]);
    return ArrayBuffer.isView(e) ||
      e instanceof ArrayBuffer ||
      e instanceof DataView ||
      (typeof e == "string" && s.values.has("content-type")) ||
      (globalThis.Blob && e instanceof globalThis.Blob) ||
      e instanceof FormData ||
      e instanceof URLSearchParams ||
      (globalThis.ReadableStream && e instanceof globalThis.ReadableStream)
      ? { bodyHeaders: void 0, body: e }
      : typeof e == "object" &&
          (Symbol.asyncIterator in e ||
            (Symbol.iterator in e &&
              "next" in e &&
              typeof e.next == "function"))
        ? { bodyHeaders: void 0, body: Ls(e) }
        : o(this, Je, "f").call(this, { body: e, headers: s });
  }
}
((Yt = x),
  (Je = new WeakMap()),
  (Ot = new WeakSet()),
  (Zn = function () {
    return this.baseURL !== "https://api.openai.com/v1";
  }));
x.OpenAI = Yt;
x.DEFAULT_TIMEOUT = 6e5;
x.OpenAIError = b;
x.APIError = Ke;
x.APIConnectionError = Ts;
x.APIConnectionTimeoutError = Pt;
x.APIUserAbortError = J;
x.NotFoundError = hr;
x.ConflictError = dr;
x.RateLimitError = fr;
x.BadRequestError = pr;
x.AuthenticationError = mr;
x.InternalServerError = _r;
x.PermissionDeniedError = gr;
x.UnprocessableEntityError = wr;
x.InvalidWebhookSignatureError = _e;
x.toFile = Yr;
x.Completions = kn;
x.Chat = Dt;
x.Embeddings = Pn;
x.Files = Mn;
x.Images = Un;
x.Audio = Ee;
x.Moderations = qn;
x.Models = Wn;
x.FineTuning = pe;
x.Graders = zt;
x.VectorStores = ut;
x.Webhooks = Yn;
x.Beta = fe;
x.Batches = Sn;
x.Uploads = Gt;
x.Responses = ct;
x.Realtime = lt;
x.Conversations = jt;
x.Evals = Xt;
x.Containers = qt;
x.Videos = Qn;
export { nt as A, x as O, Kr as P, p as b, dt as i, oe as r, Yr as t };
//# sourceMappingURL=client-DMtubo6I.mjs.map
