import { J as st } from "./index-o5KnLmKX.mjs";
import { U as x, a as H, e as X } from "./auth-DECY5s84.mjs";
import "node:process";
import "node:events";
import "node:crypto";
import "node:stream";
import "node:stream/web";
import "node:async_hooks";
import "./Keychain-CHHka2u7.mjs";
import "./constants-BL_pdRyX.mjs";
import "path";
import "os";
import "url";
import "./index-DKkZ9dV1.mjs";
import "worker_threads";
import "fs";
import "./util-CrY9x2BW.mjs";
import "./_commonjsHelpers-CBUqixCJ.mjs";
import "./sentry-common-CDPx3Glo.mjs";
import "./package-CIHfweXK.mjs";
import "./sentry-enabled-COAVq6nC.mjs";
import "tty";
import "better-sqlite3";
import "node:url";
import "node:path";
import "./logger-DoW0T1f3.mjs";
import "./startup-checkpoints-BQimOHWq.mjs";
import "./AsyncSqlite-CpInlfQ-.mjs";
import "./machine-id-DFkLVgcU.mjs";
import "perf_hooks";
import "child_process";
import "./index-CNG_AM8w.mjs";
import "timers/promises";
import "async_hooks";
import "fs/promises";
import "./index-B_PiTES1.mjs";
import "node:util";
import "node:child_process";
import "node:os";
import "./index-CMOlVndj.mjs";
import "assert";
import "events";
import "buffer";
import "stream";
import "util";
import "node:fs";
import "node:module";
import "./index-BJhQkpW6.mjs";
import "crypto";
import "http";
import "zlib";
import "https";
import "net";
import "tls";
import "stream/promises";
import "node:fs/promises";
import "./index-C7dxdDjs.mjs";
import "node:string_decoder";
import "./index-DaNOOrJg.mjs";
import "./utils-D8MokWSu.mjs";
import "./index-BiKiNEmj.mjs";
import "./register-proxy-7lV9pun2.mjs";
import "domain";
import "./index-BiHJsdYm.mjs";
import "./rolling-logger-C9NTeNo3.mjs";
import "./got-_wC7Q_ix.mjs";
import "dns";
import "http2";
import "module";
import "./index-8JaOpgio.mjs";
import "node:worker_threads";
import "./index-Bo2CLT1C.mjs";
import "node:timers";
import "./client-DMtubo6I.mjs";
(function () {
  try {
    var i =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    i.SENTRY_RELEASE = { id: "4.3.209" };
    var e = new i.Error().stack;
    e &&
      ((i._sentryDebugIds = i._sentryDebugIds || {}),
      (i._sentryDebugIds[e] = "f780b55a-f4ad-463c-b0f4-21d12e024be0"),
      (i._sentryDebugIdIdentifier =
        "sentry-dbid-f780b55a-f4ad-463c-b0f4-21d12e024be0"));
  } catch {}
})();
class j extends Error {
  constructor(e, t) {
    (super(e),
      (this.name = "ParseError"),
      (this.type = t.type),
      (this.field = t.field),
      (this.value = t.value),
      (this.line = t.line));
  }
}
function G(i) {}
function ot(i) {
  if (typeof i == "function")
    throw new TypeError(
      "`callbacks` must be an object, got a function instead. Did you mean `{onEvent: fn}`?",
    );
  const { onEvent: e = G, onError: t = G, onRetry: r = G, onComment: d } = i;
  let o = "",
    u = !0,
    n,
    a = "",
    c = "";
  function f(h) {
    const p = u ? h.replace(/^\xEF\xBB\xBF/, "") : h,
      [S, D] = nt(`${o}${p}`);
    for (const F of S) E(F);
    ((o = D), (u = !1));
  }
  function E(h) {
    if (h === "") {
      $();
      return;
    }
    if (h.startsWith(":")) {
      d && d(h.slice(h.startsWith(": ") ? 2 : 1));
      return;
    }
    const p = h.indexOf(":");
    if (p !== -1) {
      const S = h.slice(0, p),
        D = h[p + 1] === " " ? 2 : 1,
        F = h.slice(p + D);
      b(S, F, h);
      return;
    }
    b(h, "", h);
  }
  function b(h, p, S) {
    switch (h) {
      case "event":
        c = p;
        break;
      case "data":
        a = `${a}${p}
`;
        break;
      case "id":
        n = p.includes("\0") ? void 0 : p;
        break;
      case "retry":
        /^\d+$/.test(p)
          ? r(parseInt(p, 10))
          : t(
              new j(`Invalid \`retry\` value: "${p}"`, {
                type: "invalid-retry",
                value: p,
                line: S,
              }),
            );
        break;
      default:
        t(
          new j(`Unknown field "${h.length > 20 ? `${h.slice(0, 20)}…` : h}"`, {
            type: "unknown-field",
            field: h,
            value: p,
            line: S,
          }),
        );
        break;
    }
  }
  function $() {
    (a.length > 0 &&
      e({
        id: n,
        event: c || void 0,
        data: a.endsWith(`
`)
          ? a.slice(0, -1)
          : a,
      }),
      (n = void 0),
      (a = ""),
      (c = ""));
  }
  function L(h = {}) {
    (o && h.consume && E(o),
      (u = !0),
      (n = void 0),
      (a = ""),
      (c = ""),
      (o = ""));
  }
  return { feed: f, reset: L };
}
function nt(i) {
  const e = [];
  let t = "",
    r = 0;
  for (; r < i.length;) {
    const d = i.indexOf("\r", r),
      o = i.indexOf(
        `
`,
        r,
      );
    let u = -1;
    if (
      (d !== -1 && o !== -1
        ? (u = Math.min(d, o))
        : d !== -1
          ? (u = d)
          : o !== -1 && (u = o),
      u === -1)
    ) {
      t = i.slice(r);
      break;
    } else {
      const n = i.slice(r, u);
      (e.push(n),
        (r = u + 1),
        i[r - 1] === "\r" &&
          i[r] ===
            `
` &&
          r++);
    }
  }
  return [e, t];
}
class tt extends Event {
  constructor(e, t) {
    var r, d;
    (super(e),
      (this.code = (r = t?.code) != null ? r : void 0),
      (this.message = (d = t?.message) != null ? d : void 0));
  }
  [Symbol.for("nodejs.util.inspect.custom")](e, t, r) {
    return r(et(this), t);
  }
  [Symbol.for("Deno.customInspect")](e, t) {
    return e(et(this), t);
  }
}
function at(i) {
  const e = globalThis.DOMException;
  return typeof e == "function" ? new e(i, "SyntaxError") : new SyntaxError(i);
}
function q(i) {
  return i instanceof Error
    ? "errors" in i && Array.isArray(i.errors)
      ? i.errors.map(q).join(", ")
      : "cause" in i && i.cause instanceof Error
        ? `${i}: ${q(i.cause)}`
        : i.message
    : `${i}`;
}
function et(i) {
  return {
    type: i.type,
    message: i.message,
    code: i.code,
    defaultPrevented: i.defaultPrevented,
    cancelable: i.cancelable,
    timeStamp: i.timeStamp,
  };
}
var rt = (i) => {
    throw TypeError(i);
  },
  Q = (i, e, t) => e.has(i) || rt("Cannot " + t),
  s = (i, e, t) => (
    Q(i, e, "read from private field"),
    t ? t.call(i) : e.get(i)
  ),
  v = (i, e, t) =>
    e.has(i)
      ? rt("Cannot add the same private member more than once")
      : e instanceof WeakSet
        ? e.add(i)
        : e.set(i, t),
  l = (i, e, t, r) => (Q(i, e, "write to private field"), e.set(i, t), t),
  w = (i, e, t) => (Q(i, e, "access private method"), t),
  m,
  y,
  C,
  R,
  A,
  U,
  M,
  P,
  g,
  I,
  O,
  T,
  k,
  _,
  B,
  J,
  V,
  it,
  z,
  Z,
  N,
  Y,
  K;
class W extends EventTarget {
  constructor(e, t) {
    var r, d;
    (super(),
      v(this, _),
      (this.CONNECTING = 0),
      (this.OPEN = 1),
      (this.CLOSED = 2),
      v(this, m),
      v(this, y),
      v(this, C),
      v(this, R),
      v(this, A),
      v(this, U),
      v(this, M),
      v(this, P, null),
      v(this, g),
      v(this, I),
      v(this, O, null),
      v(this, T, null),
      v(this, k, null),
      v(this, J, async (o) => {
        var u;
        s(this, I).reset();
        const { body: n, redirected: a, status: c, headers: f } = o;
        if (c === 204) {
          (w(this, _, N).call(
            this,
            "Server sent HTTP 204, not reconnecting",
            204,
          ),
            this.close());
          return;
        }
        if ((a ? l(this, C, new URL(o.url)) : l(this, C, void 0), c !== 200)) {
          w(this, _, N).call(this, `Non-200 status code (${c})`, c);
          return;
        }
        if (!(f.get("content-type") || "").startsWith("text/event-stream")) {
          w(this, _, N).call(
            this,
            'Invalid content type, expected "text/event-stream"',
            c,
          );
          return;
        }
        if (s(this, m) === this.CLOSED) return;
        l(this, m, this.OPEN);
        const E = new Event("open");
        if (
          ((u = s(this, k)) == null || u.call(this, E),
          this.dispatchEvent(E),
          typeof n != "object" || !n || !("getReader" in n))
        ) {
          (w(this, _, N).call(
            this,
            "Invalid response body, expected a web ReadableStream",
            c,
          ),
            this.close());
          return;
        }
        const b = new TextDecoder(),
          $ = n.getReader();
        let L = !0;
        do {
          const { done: h, value: p } = await $.read();
          (p && s(this, I).feed(b.decode(p, { stream: !h })),
            h && ((L = !1), s(this, I).reset(), w(this, _, Y).call(this)));
        } while (L);
      }),
      v(this, V, (o) => {
        (l(this, g, void 0),
          !(o.name === "AbortError" || o.type === "aborted") &&
            w(this, _, Y).call(this, q(o)));
      }),
      v(this, z, (o) => {
        typeof o.id == "string" && l(this, P, o.id);
        const u = new MessageEvent(o.event || "message", {
          data: o.data,
          origin: s(this, C) ? s(this, C).origin : s(this, y).origin,
          lastEventId: o.id || "",
        });
        (s(this, T) &&
          (!o.event || o.event === "message") &&
          s(this, T).call(this, u),
          this.dispatchEvent(u));
      }),
      v(this, Z, (o) => {
        l(this, U, o);
      }),
      v(this, K, () => {
        (l(this, M, void 0),
          s(this, m) === this.CONNECTING && w(this, _, B).call(this));
      }));
    try {
      if (e instanceof URL) l(this, y, e);
      else if (typeof e == "string") l(this, y, new URL(e, ht()));
      else throw new Error("Invalid URL");
    } catch {
      throw at("An invalid or illegal string was specified");
    }
    (l(this, I, ot({ onEvent: s(this, z), onRetry: s(this, Z) })),
      l(this, m, this.CONNECTING),
      l(this, U, 3e3),
      l(this, A, (r = t?.fetch) != null ? r : globalThis.fetch),
      l(this, R, (d = t?.withCredentials) != null ? d : !1),
      w(this, _, B).call(this));
  }
  get readyState() {
    return s(this, m);
  }
  get url() {
    return s(this, y).href;
  }
  get withCredentials() {
    return s(this, R);
  }
  get onerror() {
    return s(this, O);
  }
  set onerror(e) {
    l(this, O, e);
  }
  get onmessage() {
    return s(this, T);
  }
  set onmessage(e) {
    l(this, T, e);
  }
  get onopen() {
    return s(this, k);
  }
  set onopen(e) {
    l(this, k, e);
  }
  addEventListener(e, t, r) {
    const d = t;
    super.addEventListener(e, d, r);
  }
  removeEventListener(e, t, r) {
    const d = t;
    super.removeEventListener(e, d, r);
  }
  close() {
    (s(this, M) && clearTimeout(s(this, M)),
      s(this, m) !== this.CLOSED &&
        (s(this, g) && s(this, g).abort(),
        l(this, m, this.CLOSED),
        l(this, g, void 0)));
  }
}
((m = new WeakMap()),
  (y = new WeakMap()),
  (C = new WeakMap()),
  (R = new WeakMap()),
  (A = new WeakMap()),
  (U = new WeakMap()),
  (M = new WeakMap()),
  (P = new WeakMap()),
  (g = new WeakMap()),
  (I = new WeakMap()),
  (O = new WeakMap()),
  (T = new WeakMap()),
  (k = new WeakMap()),
  (_ = new WeakSet()),
  (B = function () {
    (l(this, m, this.CONNECTING),
      l(this, g, new AbortController()),
      s(this, A)(s(this, y), w(this, _, it).call(this))
        .then(s(this, J))
        .catch(s(this, V)));
  }),
  (J = new WeakMap()),
  (V = new WeakMap()),
  (it = function () {
    var i;
    const e = {
      mode: "cors",
      redirect: "follow",
      headers: {
        Accept: "text/event-stream",
        ...(s(this, P) ? { "Last-Event-ID": s(this, P) } : void 0),
      },
      cache: "no-store",
      signal: (i = s(this, g)) == null ? void 0 : i.signal,
    };
    return (
      "window" in globalThis &&
        (e.credentials = this.withCredentials ? "include" : "same-origin"),
      e
    );
  }),
  (z = new WeakMap()),
  (Z = new WeakMap()),
  (N = function (i, e) {
    var t;
    s(this, m) !== this.CLOSED && l(this, m, this.CLOSED);
    const r = new tt("error", { code: e, message: i });
    ((t = s(this, O)) == null || t.call(this, r), this.dispatchEvent(r));
  }),
  (Y = function (i, e) {
    var t;
    if (s(this, m) === this.CLOSED) return;
    l(this, m, this.CONNECTING);
    const r = new tt("error", { code: e, message: i });
    ((t = s(this, O)) == null || t.call(this, r),
      this.dispatchEvent(r),
      l(this, M, setTimeout(s(this, K), s(this, U))));
  }),
  (K = new WeakMap()),
  (W.CONNECTING = 0),
  (W.OPEN = 1),
  (W.CLOSED = 2));
function ht() {
  const i = "document" in globalThis ? globalThis.document : void 0;
  return i &&
    typeof i == "object" &&
    "baseURI" in i &&
    typeof i.baseURI == "string"
    ? i.baseURI
    : void 0;
}
class ct extends Error {
  constructor(e, t, r) {
    (super(`SSE error: ${t}`), (this.code = e), (this.event = r));
  }
}
class ke {
  constructor(e, t) {
    ((this._url = e),
      (this._resourceMetadataUrl = void 0),
      (this._eventSourceInit = t?.eventSourceInit),
      (this._requestInit = t?.requestInit),
      (this._authProvider = t?.authProvider),
      (this._fetch = t?.fetch));
  }
  async _authThenStart() {
    var e;
    if (!this._authProvider) throw new x("No auth provider");
    let t;
    try {
      t = await H(this._authProvider, {
        serverUrl: this._url,
        resourceMetadataUrl: this._resourceMetadataUrl,
        fetchFn: this._fetch,
      });
    } catch (r) {
      throw ((e = this.onerror) === null || e === void 0 || e.call(this, r), r);
    }
    if (t !== "AUTHORIZED") throw new x();
    return await this._startOrAuth();
  }
  async _commonHeaders() {
    var e;
    const t = {};
    if (this._authProvider) {
      const r = await this._authProvider.tokens();
      r && (t.Authorization = `Bearer ${r.access_token}`);
    }
    return (
      this._protocolVersion &&
        (t["mcp-protocol-version"] = this._protocolVersion),
      new Headers({
        ...t,
        ...((e = this._requestInit) === null || e === void 0
          ? void 0
          : e.headers),
      })
    );
  }
  _startOrAuth() {
    var e, t, r;
    const d =
      (r =
        (t =
          (e =
            this === null || this === void 0
              ? void 0
              : this._eventSourceInit) === null || e === void 0
            ? void 0
            : e.fetch) !== null && t !== void 0
          ? t
          : this._fetch) !== null && r !== void 0
        ? r
        : fetch;
    return new Promise((o, u) => {
      ((this._eventSource = new W(this._url.href, {
        ...this._eventSourceInit,
        fetch: async (n, a) => {
          const c = await this._commonHeaders();
          c.set("Accept", "text/event-stream");
          const f = await d(n, { ...a, headers: c });
          return (
            f.status === 401 &&
              f.headers.has("www-authenticate") &&
              (this._resourceMetadataUrl = X(f)),
            f
          );
        },
      })),
        (this._abortController = new AbortController()),
        (this._eventSource.onerror = (n) => {
          var a;
          if (n.code === 401 && this._authProvider) {
            this._authThenStart().then(o, u);
            return;
          }
          const c = new ct(n.code, n.message, n);
          (u(c),
            (a = this.onerror) === null || a === void 0 || a.call(this, c));
        }),
        (this._eventSource.onopen = () => {}),
        this._eventSource.addEventListener("endpoint", (n) => {
          var a;
          const c = n;
          try {
            if (
              ((this._endpoint = new URL(c.data, this._url)),
              this._endpoint.origin !== this._url.origin)
            )
              throw new Error(
                `Endpoint origin does not match connection origin: ${this._endpoint.origin}`,
              );
          } catch (f) {
            (u(f),
              (a = this.onerror) === null || a === void 0 || a.call(this, f),
              this.close());
            return;
          }
          o();
        }),
        (this._eventSource.onmessage = (n) => {
          var a, c;
          const f = n;
          let E;
          try {
            E = st.parse(JSON.parse(f.data));
          } catch (b) {
            (a = this.onerror) === null || a === void 0 || a.call(this, b);
            return;
          }
          (c = this.onmessage) === null || c === void 0 || c.call(this, E);
        }));
    });
  }
  async start() {
    if (this._eventSource)
      throw new Error(
        "SSEClientTransport already started! If using Client class, note that connect() calls start() automatically.",
      );
    return await this._startOrAuth();
  }
  async finishAuth(e) {
    if (!this._authProvider) throw new x("No auth provider");
    if (
      (await H(this._authProvider, {
        serverUrl: this._url,
        authorizationCode: e,
        resourceMetadataUrl: this._resourceMetadataUrl,
        fetchFn: this._fetch,
      })) !== "AUTHORIZED"
    )
      throw new x("Failed to authorize");
  }
  async close() {
    var e, t, r;
    ((e = this._abortController) === null || e === void 0 || e.abort(),
      (t = this._eventSource) === null || t === void 0 || t.close(),
      (r = this.onclose) === null || r === void 0 || r.call(this));
  }
  async send(e) {
    var t, r, d;
    if (!this._endpoint) throw new Error("Not connected");
    try {
      const o = await this._commonHeaders();
      o.set("content-type", "application/json");
      const u = {
          ...this._requestInit,
          method: "POST",
          headers: o,
          body: JSON.stringify(e),
          signal:
            (t = this._abortController) === null || t === void 0
              ? void 0
              : t.signal,
        },
        n = await ((r = this._fetch) !== null && r !== void 0 ? r : fetch)(
          this._endpoint,
          u,
        );
      if (!n.ok) {
        if (n.status === 401 && this._authProvider) {
          if (
            ((this._resourceMetadataUrl = X(n)),
            (await H(this._authProvider, {
              serverUrl: this._url,
              resourceMetadataUrl: this._resourceMetadataUrl,
              fetchFn: this._fetch,
            })) !== "AUTHORIZED")
          )
            throw new x();
          return this.send(e);
        }
        const a = await n.text().catch(() => null);
        throw new Error(`Error POSTing to endpoint (HTTP ${n.status}): ${a}`);
      }
    } catch (o) {
      throw ((d = this.onerror) === null || d === void 0 || d.call(this, o), o);
    }
  }
  setProtocolVersion(e) {
    this._protocolVersion = e;
  }
}
export { ke as SSEClientTransport, ct as SseError };
//# sourceMappingURL=sse-l3DRQviM.mjs.map
