import { h as x, g as O, J as S, j as P } from "./index-o5KnLmKX.mjs";
import { U as y, a as T, e as R } from "./auth-DECY5s84.mjs";
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
    var l =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    l.SENTRY_RELEASE = { id: "4.3.209" };
    var t = new l.Error().stack;
    t &&
      ((l._sentryDebugIds = l._sentryDebugIds || {}),
      (l._sentryDebugIds[t] = "5b578f34-9c8b-4a2e-8c28-1c0ae51f4612"),
      (l._sentryDebugIdIdentifier =
        "sentry-dbid-5b578f34-9c8b-4a2e-8c28-1c0ae51f4612"));
  } catch {}
})();
class I extends Error {
  constructor(t, e) {
    (super(t),
      (this.name = "ParseError"),
      (this.type = e.type),
      (this.field = e.field),
      (this.value = e.value),
      (this.line = e.line));
  }
}
function g(l) {}
function A(l) {
  if (typeof l == "function")
    throw new TypeError(
      "`callbacks` must be an object, got a function instead. Did you mean `{onEvent: fn}`?",
    );
  const { onEvent: t = g, onError: e = g, onRetry: r = g, onComment: o } = l;
  let n = "",
    i = !0,
    c,
    u = "",
    p = "";
  function _(s) {
    const a = i ? s.replace(/^\xEF\xBB\xBF/, "") : s,
      [h, v] = D(`${n}${a}`);
    for (const E of h) d(E);
    ((n = v), (i = !1));
  }
  function d(s) {
    if (s === "") {
      m();
      return;
    }
    if (s.startsWith(":")) {
      o && o(s.slice(s.startsWith(": ") ? 2 : 1));
      return;
    }
    const a = s.indexOf(":");
    if (a !== -1) {
      const h = s.slice(0, a),
        v = s[a + 1] === " " ? 2 : 1,
        E = s.slice(a + v);
      f(h, E, s);
      return;
    }
    f(s, "", s);
  }
  function f(s, a, h) {
    switch (s) {
      case "event":
        p = a;
        break;
      case "data":
        u = `${u}${a}
`;
        break;
      case "id":
        c = a.includes("\0") ? void 0 : a;
        break;
      case "retry":
        /^\d+$/.test(a)
          ? r(parseInt(a, 10))
          : e(
              new I(`Invalid \`retry\` value: "${a}"`, {
                type: "invalid-retry",
                value: a,
                line: h,
              }),
            );
        break;
      default:
        e(
          new I(`Unknown field "${s.length > 20 ? `${s.slice(0, 20)}…` : s}"`, {
            type: "unknown-field",
            field: s,
            value: a,
            line: h,
          }),
        );
        break;
    }
  }
  function m() {
    (u.length > 0 &&
      t({
        id: c,
        event: p || void 0,
        data: u.endsWith(`
`)
          ? u.slice(0, -1)
          : u,
      }),
      (c = void 0),
      (u = ""),
      (p = ""));
  }
  function w(s = {}) {
    (n && s.consume && d(n),
      (i = !0),
      (c = void 0),
      (u = ""),
      (p = ""),
      (n = ""));
  }
  return { feed: _, reset: w };
}
function D(l) {
  const t = [];
  let e = "",
    r = 0;
  for (; r < l.length;) {
    const o = l.indexOf("\r", r),
      n = l.indexOf(
        `
`,
        r,
      );
    let i = -1;
    if (
      (o !== -1 && n !== -1
        ? (i = Math.min(o, n))
        : o !== -1
          ? (i = o)
          : n !== -1 && (i = n),
      i === -1)
    ) {
      e = l.slice(r);
      break;
    } else {
      const c = l.slice(r, i);
      (t.push(c),
        (r = i + 1),
        l[r - 1] === "\r" &&
          l[r] ===
            `
` &&
          r++);
    }
  }
  return [t, e];
}
class C extends TransformStream {
  constructor({ onError: t, onRetry: e, onComment: r } = {}) {
    let o;
    super({
      start(n) {
        o = A({
          onEvent: (i) => {
            n.enqueue(i);
          },
          onError(i) {
            t === "terminate" ? n.error(i) : typeof t == "function" && t(i);
          },
          onRetry: e,
          onComment: r,
        });
      },
      transform(n) {
        o.feed(n);
      },
    });
  }
}
const F = {
  initialReconnectionDelay: 1e3,
  maxReconnectionDelay: 3e4,
  reconnectionDelayGrowFactor: 1.5,
  maxRetries: 2,
};
class b extends Error {
  constructor(t, e) {
    (super(`Streamable HTTP error: ${e}`), (this.code = t));
  }
}
class te {
  constructor(t, e) {
    var r;
    ((this._hasCompletedAuthFlow = !1),
      (this._url = t),
      (this._resourceMetadataUrl = void 0),
      (this._requestInit = e?.requestInit),
      (this._authProvider = e?.authProvider),
      (this._fetch = e?.fetch),
      (this._sessionId = e?.sessionId),
      (this._reconnectionOptions =
        (r = e?.reconnectionOptions) !== null && r !== void 0 ? r : F));
  }
  async _authThenStart() {
    var t;
    if (!this._authProvider) throw new y("No auth provider");
    let e;
    try {
      e = await T(this._authProvider, {
        serverUrl: this._url,
        resourceMetadataUrl: this._resourceMetadataUrl,
        fetchFn: this._fetch,
      });
    } catch (r) {
      throw ((t = this.onerror) === null || t === void 0 || t.call(this, r), r);
    }
    if (e !== "AUTHORIZED") throw new y();
    return await this._startOrAuthSse({ resumptionToken: void 0 });
  }
  async _commonHeaders() {
    var t;
    const e = {};
    if (this._authProvider) {
      const o = await this._authProvider.tokens();
      o && (e.Authorization = `Bearer ${o.access_token}`);
    }
    (this._sessionId && (e["mcp-session-id"] = this._sessionId),
      this._protocolVersion &&
        (e["mcp-protocol-version"] = this._protocolVersion));
    const r = this._normalizeHeaders(
      (t = this._requestInit) === null || t === void 0 ? void 0 : t.headers,
    );
    return new Headers({ ...e, ...r });
  }
  async _startOrAuthSse(t) {
    var e, r, o;
    const { resumptionToken: n } = t;
    try {
      const i = await this._commonHeaders();
      (i.set("Accept", "text/event-stream"), n && i.set("last-event-id", n));
      const c = await ((e = this._fetch) !== null && e !== void 0 ? e : fetch)(
        this._url,
        {
          method: "GET",
          headers: i,
          signal:
            (r = this._abortController) === null || r === void 0
              ? void 0
              : r.signal,
        },
      );
      if (!c.ok) {
        if (c.status === 401 && this._authProvider)
          return await this._authThenStart();
        if (c.status === 405) return;
        throw new b(c.status, `Failed to open SSE stream: ${c.statusText}`);
      }
      this._handleSseStream(c.body, t, !0);
    } catch (i) {
      throw ((o = this.onerror) === null || o === void 0 || o.call(this, i), i);
    }
  }
  _getNextReconnectionDelay(t) {
    const e = this._reconnectionOptions.initialReconnectionDelay,
      r = this._reconnectionOptions.reconnectionDelayGrowFactor,
      o = this._reconnectionOptions.maxReconnectionDelay;
    return Math.min(e * Math.pow(r, t), o);
  }
  _normalizeHeaders(t) {
    return t
      ? t instanceof Headers
        ? Object.fromEntries(t.entries())
        : Array.isArray(t)
          ? Object.fromEntries(t)
          : { ...t }
      : {};
  }
  _scheduleReconnection(t, e = 0) {
    var r;
    const o = this._reconnectionOptions.maxRetries;
    if (o > 0 && e >= o) {
      (r = this.onerror) === null ||
        r === void 0 ||
        r.call(
          this,
          new Error(`Maximum reconnection attempts (${o}) exceeded.`),
        );
      return;
    }
    const n = this._getNextReconnectionDelay(e);
    setTimeout(() => {
      this._startOrAuthSse(t).catch((i) => {
        var c;
        ((c = this.onerror) === null ||
          c === void 0 ||
          c.call(
            this,
            new Error(
              `Failed to reconnect SSE stream: ${i instanceof Error ? i.message : String(i)}`,
            ),
          ),
          this._scheduleReconnection(t, e + 1));
      });
    }, n);
  }
  _handleSseStream(t, e, r) {
    if (!t) return;
    const { onresumptiontoken: o, replayMessageId: n } = e;
    let i;
    (async () => {
      var u, p, _, d;
      try {
        const f = t
          .pipeThrough(new TextDecoderStream())
          .pipeThrough(new C())
          .getReader();
        for (;;) {
          const { value: m, done: w } = await f.read();
          if (w) break;
          if (
            (m.id && ((i = m.id), o?.(m.id)), !m.event || m.event === "message")
          )
            try {
              const s = S.parse(JSON.parse(m.data));
              (n !== void 0 && P(s) && (s.id = n),
                (u = this.onmessage) === null ||
                  u === void 0 ||
                  u.call(this, s));
            } catch (s) {
              (p = this.onerror) === null || p === void 0 || p.call(this, s);
            }
        }
      } catch (f) {
        if (
          ((_ = this.onerror) === null ||
            _ === void 0 ||
            _.call(this, new Error(`SSE stream disconnected: ${f}`)),
          r && this._abortController && !this._abortController.signal.aborted)
        )
          try {
            this._scheduleReconnection(
              { resumptionToken: i, onresumptiontoken: o, replayMessageId: n },
              0,
            );
          } catch (m) {
            (d = this.onerror) === null ||
              d === void 0 ||
              d.call(
                this,
                new Error(
                  `Failed to reconnect: ${m instanceof Error ? m.message : String(m)}`,
                ),
              );
          }
      }
    })();
  }
  async start() {
    if (this._abortController)
      throw new Error(
        "StreamableHTTPClientTransport already started! If using Client class, note that connect() calls start() automatically.",
      );
    this._abortController = new AbortController();
  }
  async finishAuth(t) {
    if (!this._authProvider) throw new y("No auth provider");
    if (
      (await T(this._authProvider, {
        serverUrl: this._url,
        authorizationCode: t,
        resourceMetadataUrl: this._resourceMetadataUrl,
        fetchFn: this._fetch,
      })) !== "AUTHORIZED"
    )
      throw new y("Failed to authorize");
  }
  async close() {
    var t, e;
    ((t = this._abortController) === null || t === void 0 || t.abort(),
      (e = this.onclose) === null || e === void 0 || e.call(this));
  }
  async send(t, e) {
    var r, o, n, i;
    try {
      const { resumptionToken: c, onresumptiontoken: u } = e || {};
      if (c) {
        this._startOrAuthSse({
          resumptionToken: c,
          replayMessageId: x(t) ? t.id : void 0,
        }).catch((a) => {
          var h;
          return (h = this.onerror) === null || h === void 0
            ? void 0
            : h.call(this, a);
        });
        return;
      }
      const p = await this._commonHeaders();
      (p.set("content-type", "application/json"),
        p.set("accept", "application/json, text/event-stream"));
      const _ = {
          ...this._requestInit,
          method: "POST",
          headers: p,
          body: JSON.stringify(t),
          signal:
            (r = this._abortController) === null || r === void 0
              ? void 0
              : r.signal,
        },
        d = await ((o = this._fetch) !== null && o !== void 0 ? o : fetch)(
          this._url,
          _,
        ),
        f = d.headers.get("mcp-session-id");
      if ((f && (this._sessionId = f), !d.ok)) {
        if (d.status === 401 && this._authProvider) {
          if (this._hasCompletedAuthFlow)
            throw new b(
              401,
              "Server returned 401 after successful authentication",
            );
          if (
            ((this._resourceMetadataUrl = R(d)),
            (await T(this._authProvider, {
              serverUrl: this._url,
              resourceMetadataUrl: this._resourceMetadataUrl,
              fetchFn: this._fetch,
            })) !== "AUTHORIZED")
          )
            throw new y();
          return ((this._hasCompletedAuthFlow = !0), this.send(t));
        }
        const a = await d.text().catch(() => null);
        throw new Error(`Error POSTing to endpoint (HTTP ${d.status}): ${a}`);
      }
      if (((this._hasCompletedAuthFlow = !1), d.status === 202)) {
        O(t) &&
          this._startOrAuthSse({ resumptionToken: void 0 }).catch((a) => {
            var h;
            return (h = this.onerror) === null || h === void 0
              ? void 0
              : h.call(this, a);
          });
        return;
      }
      const w =
          (Array.isArray(t) ? t : [t]).filter(
            (a) => "method" in a && "id" in a && a.id !== void 0,
          ).length > 0,
        s = d.headers.get("content-type");
      if (w)
        if (s?.includes("text/event-stream"))
          this._handleSseStream(d.body, { onresumptiontoken: u }, !1);
        else if (s?.includes("application/json")) {
          const a = await d.json(),
            h = Array.isArray(a) ? a.map((v) => S.parse(v)) : [S.parse(a)];
          for (const v of h)
            (n = this.onmessage) === null || n === void 0 || n.call(this, v);
        } else throw new b(-1, `Unexpected content type: ${s}`);
    } catch (c) {
      throw ((i = this.onerror) === null || i === void 0 || i.call(this, c), c);
    }
  }
  get sessionId() {
    return this._sessionId;
  }
  async terminateSession() {
    var t, e, r;
    if (this._sessionId)
      try {
        const o = await this._commonHeaders(),
          n = {
            ...this._requestInit,
            method: "DELETE",
            headers: o,
            signal:
              (t = this._abortController) === null || t === void 0
                ? void 0
                : t.signal,
          },
          i = await ((e = this._fetch) !== null && e !== void 0 ? e : fetch)(
            this._url,
            n,
          );
        if (!i.ok && i.status !== 405)
          throw new b(i.status, `Failed to terminate session: ${i.statusText}`);
        this._sessionId = void 0;
      } catch (o) {
        throw (
          (r = this.onerror) === null || r === void 0 || r.call(this, o),
          o
        );
      }
  }
  setProtocolVersion(t) {
    this._protocolVersion = t;
  }
  get protocolVersion() {
    return this._protocolVersion;
  }
}
export { te as StreamableHTTPClientTransport, b as StreamableHTTPError };
//# sourceMappingURL=streamableHttp-C2-F8Eo0.mjs.map
