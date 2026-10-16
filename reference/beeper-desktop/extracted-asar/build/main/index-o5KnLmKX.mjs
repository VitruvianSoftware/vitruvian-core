import * as xn from "node:process";
import { EventEmitter as wt } from "node:events";
import { randomUUID as tr } from "node:crypto";
import { Readable as dc } from "node:stream";
import { ReadableStream as pc, TransformStream as fc } from "node:stream/web";
import { AsyncLocalStorage as hc } from "node:async_hooks";
import {
  bz as h,
  bC as D,
  cA as a,
  bo as y,
  ap as X,
  bL as Y,
  cH as Tt,
  am as U,
  cG as Z,
  by as R,
  aF as J,
  aE as se,
  c0 as mc,
  al as j,
  b3 as no,
  bl as _c,
} from "./Keychain-CHHka2u7.mjs";
import { a9 as gc, a8 as yc } from "./index-BJhQkpW6.mjs";
import { a as ro } from "./_commonjsHelpers-CBUqixCJ.mjs";
import { r as vc } from "./index-Bo2CLT1C.mjs";
import Sc from "tty";
import wc from "util";
import "node:timers";
import { O as Tc } from "./client-DMtubo6I.mjs";
import so from "events";
import bc from "https";
import oo from "http";
import xc from "net";
import Ic from "tls";
import nr from "crypto";
import bt from "stream";
import Ec from "url";
import Cc from "zlib";
import Ac from "buffer";
import Dc from "node:module";
(function () {
  try {
    var t =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    t.SENTRY_RELEASE = { id: "4.3.209" };
    var e = new t.Error().stack;
    e &&
      ((t._sentryDebugIds = t._sentryDebugIds || {}),
      (t._sentryDebugIds[e] = "c3d076e8-2e68-402f-bf35-2aa0ad5d8d2e"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-c3d076e8-2e68-402f-bf35-2aa0ad5d8d2e"));
  } catch {}
})();
const Of = import.meta.filename,
  Rf = import.meta.dirname,
  io = Dc.createRequire(import.meta.url),
  ao = "2025-06-18",
  Oc = "2025-03-26",
  Rc = [ao, "2025-03-26", "2024-11-05", "2024-10-07"],
  xt = "2.0",
  rr = Z([a(), R().int()]),
  sr = a(),
  kc = h({ progressToken: D(rr) }).passthrough(),
  he = h({ _meta: D(kc) }).passthrough(),
  oe = h({ method: a(), params: D(he) }),
  It = h({ _meta: D(h({}).passthrough()) }).passthrough(),
  ge = h({ method: a(), params: D(It) }),
  le = h({ _meta: D(h({}).passthrough()) }).passthrough(),
  Et = Z([a(), R().int()]),
  or = h({ jsonrpc: y(xt), id: Et })
    .merge(oe)
    .strict(),
  co = (t) => or.safeParse(t).success,
  ir = h({ jsonrpc: y(xt) })
    .merge(ge)
    .strict(),
  uo = (t) => ir.safeParse(t).success,
  ar = h({ jsonrpc: y(xt), id: Et, result: le }).strict(),
  jn = (t) => ar.safeParse(t).success;
var Ee;
(function (t) {
  ((t[(t.ConnectionClosed = -32e3)] = "ConnectionClosed"),
    (t[(t.RequestTimeout = -32001)] = "RequestTimeout"),
    (t[(t.ParseError = -32700)] = "ParseError"),
    (t[(t.InvalidRequest = -32600)] = "InvalidRequest"),
    (t[(t.MethodNotFound = -32601)] = "MethodNotFound"),
    (t[(t.InvalidParams = -32602)] = "InvalidParams"),
    (t[(t.InternalError = -32603)] = "InternalError"));
})(Ee || (Ee = {}));
const cr = h({
    jsonrpc: y(xt),
    id: Et,
    error: h({ code: R().int(), message: a(), data: D(Tt()) }),
  }).strict(),
  lo = (t) => cr.safeParse(t).success,
  Nc = Z([or, ir, ar, cr]),
  ur = le.strict(),
  Xt = ge.extend({
    method: y("notifications/cancelled"),
    params: It.extend({ requestId: Et, reason: a().optional() }),
  }),
  po = h({ src: a(), mimeType: D(a()), sizes: D(U(a())) }).passthrough(),
  st = h({ icons: U(po).optional() }).passthrough(),
  ot = h({ name: a(), title: D(a()) }).passthrough(),
  lr = ot.extend({ version: a(), websiteUrl: D(a()) }).merge(st),
  fo = h({
    experimental: D(h({}).passthrough()),
    sampling: D(h({}).passthrough()),
    elicitation: D(h({}).passthrough()),
    roots: D(h({ listChanged: D(X()) }).passthrough()),
  }).passthrough(),
  dr = oe.extend({
    method: y("initialize"),
    params: he.extend({
      protocolVersion: a(),
      capabilities: fo,
      clientInfo: lr,
    }),
  }),
  Lc = (t) => dr.safeParse(t).success,
  ho = h({
    experimental: D(h({}).passthrough()),
    logging: D(h({}).passthrough()),
    completions: D(h({}).passthrough()),
    prompts: D(h({ listChanged: D(X()) }).passthrough()),
    resources: D(h({ subscribe: D(X()), listChanged: D(X()) }).passthrough()),
    tools: D(h({ listChanged: D(X()) }).passthrough()),
  }).passthrough(),
  mo = le.extend({
    protocolVersion: a(),
    capabilities: ho,
    serverInfo: lr,
    instructions: D(a()),
  }),
  pr = ge.extend({ method: y("notifications/initialized") }),
  Pc = (t) => pr.safeParse(t).success,
  Qt = oe.extend({ method: y("ping") }),
  _o = h({ progress: R(), total: D(R()), message: D(a()) }).passthrough(),
  en = ge.extend({
    method: y("notifications/progress"),
    params: It.merge(_o).extend({ progressToken: rr }),
  }),
  Ct = oe.extend({ params: he.extend({ cursor: D(sr) }).optional() }),
  At = le.extend({ nextCursor: D(sr) }),
  fr = h({
    uri: a(),
    mimeType: D(a()),
    _meta: D(h({}).passthrough()),
  }).passthrough(),
  hr = fr.extend({ text: a() }),
  mr = a().refine(
    (t) => {
      try {
        return (atob(t), !0);
      } catch {
        return !1;
      }
    },
    { message: "Invalid Base64 string" },
  ),
  _r = fr.extend({ blob: mr }),
  gr = ot
    .extend({
      uri: a(),
      description: D(a()),
      mimeType: D(a()),
      _meta: D(h({}).passthrough()),
    })
    .merge(st),
  go = ot
    .extend({
      uriTemplate: a(),
      description: D(a()),
      mimeType: D(a()),
      _meta: D(h({}).passthrough()),
    })
    .merge(st),
  yo = Ct.extend({ method: y("resources/list") }),
  vo = At.extend({ resources: U(gr) }),
  So = Ct.extend({ method: y("resources/templates/list") }),
  wo = At.extend({ resourceTemplates: U(go) }),
  To = oe.extend({
    method: y("resources/read"),
    params: he.extend({ uri: a() }),
  }),
  bo = le.extend({ contents: U(Z([hr, _r])) }),
  xo = ge.extend({ method: y("notifications/resources/list_changed") }),
  Io = oe.extend({
    method: y("resources/subscribe"),
    params: he.extend({ uri: a() }),
  }),
  Eo = oe.extend({
    method: y("resources/unsubscribe"),
    params: he.extend({ uri: a() }),
  }),
  Co = ge.extend({
    method: y("notifications/resources/updated"),
    params: It.extend({ uri: a() }),
  }),
  Ao = h({ name: a(), description: D(a()), required: D(X()) }).passthrough(),
  Do = ot
    .extend({
      description: D(a()),
      arguments: D(U(Ao)),
      _meta: D(h({}).passthrough()),
    })
    .merge(st),
  Oo = Ct.extend({ method: y("prompts/list") }),
  Ro = At.extend({ prompts: U(Do) }),
  ko = oe.extend({
    method: y("prompts/get"),
    params: he.extend({ name: a(), arguments: D(Y(a())) }),
  }),
  tn = h({
    type: y("text"),
    text: a(),
    _meta: D(h({}).passthrough()),
  }).passthrough(),
  nn = h({
    type: y("image"),
    data: mr,
    mimeType: a(),
    _meta: D(h({}).passthrough()),
  }).passthrough(),
  rn = h({
    type: y("audio"),
    data: mr,
    mimeType: a(),
    _meta: D(h({}).passthrough()),
  }).passthrough(),
  No = h({
    type: y("resource"),
    resource: Z([hr, _r]),
    _meta: D(h({}).passthrough()),
  }).passthrough(),
  Lo = gr.extend({ type: y("resource_link") }),
  yr = Z([tn, nn, rn, Lo, No]),
  Po = h({ role: J(["user", "assistant"]), content: yr }).passthrough(),
  Mo = le.extend({ description: D(a()), messages: U(Po) }),
  Fo = ge.extend({ method: y("notifications/prompts/list_changed") }),
  Uo = h({
    title: D(a()),
    readOnlyHint: D(X()),
    destructiveHint: D(X()),
    idempotentHint: D(X()),
    openWorldHint: D(X()),
  }).passthrough(),
  $o = ot
    .extend({
      description: D(a()),
      inputSchema: h({
        type: y("object"),
        properties: D(h({}).passthrough()),
        required: D(U(a())),
      }).passthrough(),
      outputSchema: D(
        h({
          type: y("object"),
          properties: D(h({}).passthrough()),
          required: D(U(a())),
        }).passthrough(),
      ),
      annotations: D(Uo),
      _meta: D(h({}).passthrough()),
    })
    .merge(st),
  Bo = Ct.extend({ method: y("tools/list") }),
  jo = At.extend({ tools: U($o) }),
  vr = le.extend({
    content: U(yr).default([]),
    structuredContent: h({}).passthrough().optional(),
    isError: D(X()),
  }),
  Mc = vr.or(le.extend({ toolResult: Tt() })),
  qo = oe.extend({
    method: y("tools/call"),
    params: he.extend({ name: a(), arguments: D(Y(Tt())) }),
  }),
  Go = ge.extend({ method: y("notifications/tools/list_changed") }),
  Sr = J([
    "debug",
    "info",
    "notice",
    "warning",
    "error",
    "critical",
    "alert",
    "emergency",
  ]),
  Jo = oe.extend({
    method: y("logging/setLevel"),
    params: he.extend({ level: Sr }),
  }),
  Ho = ge.extend({
    method: y("notifications/message"),
    params: It.extend({ level: Sr, logger: D(a()), data: Tt() }),
  }),
  Wo = h({ name: a().optional() }).passthrough(),
  zo = h({
    hints: D(U(Wo)),
    costPriority: D(R().min(0).max(1)),
    speedPriority: D(R().min(0).max(1)),
    intelligencePriority: D(R().min(0).max(1)),
  }).passthrough(),
  Vo = h({
    role: J(["user", "assistant"]),
    content: Z([tn, nn, rn]),
  }).passthrough(),
  Ko = oe.extend({
    method: y("sampling/createMessage"),
    params: he.extend({
      messages: U(Vo),
      systemPrompt: D(a()),
      includeContext: D(J(["none", "thisServer", "allServers"])),
      temperature: D(R()),
      maxTokens: R().int(),
      stopSequences: D(U(a())),
      metadata: D(h({}).passthrough()),
      modelPreferences: D(zo),
    }),
  }),
  Yo = le.extend({
    model: a(),
    stopReason: D(J(["endTurn", "stopSequence", "maxTokens"]).or(a())),
    role: J(["user", "assistant"]),
    content: se("type", [tn, nn, rn]),
  }),
  Zo = h({
    type: y("boolean"),
    title: D(a()),
    description: D(a()),
    default: D(X()),
  }).passthrough(),
  Xo = h({
    type: y("string"),
    title: D(a()),
    description: D(a()),
    minLength: D(R()),
    maxLength: D(R()),
    format: D(J(["email", "uri", "date", "date-time"])),
  }).passthrough(),
  Qo = h({
    type: J(["number", "integer"]),
    title: D(a()),
    description: D(a()),
    minimum: D(R()),
    maximum: D(R()),
  }).passthrough(),
  ei = h({
    type: y("string"),
    title: D(a()),
    description: D(a()),
    enum: U(a()),
    enumNames: D(U(a())),
  }).passthrough(),
  ti = Z([Zo, Xo, Qo, ei]),
  ni = oe.extend({
    method: y("elicitation/create"),
    params: he.extend({
      message: a(),
      requestedSchema: h({
        type: y("object"),
        properties: Y(a(), ti),
        required: D(U(a())),
      }).passthrough(),
    }),
  }),
  ri = le.extend({
    action: J(["accept", "decline", "cancel"]),
    content: D(Y(a(), Tt())),
  }),
  wr = h({ type: y("ref/resource"), uri: a() }).passthrough(),
  Fc = wr,
  si = h({ type: y("ref/prompt"), name: a() }).passthrough(),
  oi = oe.extend({
    method: y("completion/complete"),
    params: he.extend({
      ref: Z([si, wr]),
      argument: h({ name: a(), value: a() }).passthrough(),
      context: D(h({ arguments: D(Y(a(), a())) })),
    }),
  }),
  ii = le.extend({
    completion: h({
      values: U(a()).max(100),
      total: D(R().int()),
      hasMore: D(X()),
    }).passthrough(),
  }),
  ai = h({
    uri: a().startsWith("file://"),
    name: D(a()),
    _meta: D(h({}).passthrough()),
  }).passthrough(),
  ci = oe.extend({ method: y("roots/list") }),
  ui = le.extend({ roots: U(ai) }),
  li = ge.extend({ method: y("notifications/roots/list_changed") }),
  Uc = Z([Qt, dr, oi, Jo, ko, Oo, yo, So, To, Io, Eo, qo, Bo]),
  $c = Z([Xt, en, pr, li]),
  Bc = Z([ur, Yo, ri, ui]),
  jc = Z([Qt, Ko, ni, ci]),
  qc = Z([Xt, en, Ho, Co, xo, Go, Fo]),
  Gc = Z([ur, mo, ii, Mo, Ro, vo, wo, bo, vr, jo]);
class mt extends Error {
  constructor(e, n, r) {
    (super(`MCP error ${e}: ${n}`),
      (this.code = e),
      (this.data = r),
      (this.name = "McpError"));
  }
}
const Ze = Object.freeze(
    Object.defineProperty(
      {
        __proto__: null,
        AudioContentSchema: rn,
        BaseMetadataSchema: ot,
        BlobResourceContentsSchema: _r,
        BooleanSchemaSchema: Zo,
        CallToolRequestSchema: qo,
        CallToolResultSchema: vr,
        CancelledNotificationSchema: Xt,
        ClientCapabilitiesSchema: fo,
        ClientNotificationSchema: $c,
        ClientRequestSchema: Uc,
        ClientResultSchema: Bc,
        CompatibilityCallToolResultSchema: Mc,
        CompleteRequestSchema: oi,
        CompleteResultSchema: ii,
        ContentBlockSchema: yr,
        CreateMessageRequestSchema: Ko,
        CreateMessageResultSchema: Yo,
        CursorSchema: sr,
        DEFAULT_NEGOTIATED_PROTOCOL_VERSION: Oc,
        ElicitRequestSchema: ni,
        ElicitResultSchema: ri,
        EmbeddedResourceSchema: No,
        EmptyResultSchema: ur,
        EnumSchemaSchema: ei,
        get ErrorCode() {
          return Ee;
        },
        GetPromptRequestSchema: ko,
        GetPromptResultSchema: Mo,
        IconSchema: po,
        IconsSchema: st,
        ImageContentSchema: nn,
        ImplementationSchema: lr,
        InitializeRequestSchema: dr,
        InitializeResultSchema: mo,
        InitializedNotificationSchema: pr,
        JSONRPCErrorSchema: cr,
        JSONRPCMessageSchema: Nc,
        JSONRPCNotificationSchema: ir,
        JSONRPCRequestSchema: or,
        JSONRPCResponseSchema: ar,
        JSONRPC_VERSION: xt,
        LATEST_PROTOCOL_VERSION: ao,
        ListPromptsRequestSchema: Oo,
        ListPromptsResultSchema: Ro,
        ListResourceTemplatesRequestSchema: So,
        ListResourceTemplatesResultSchema: wo,
        ListResourcesRequestSchema: yo,
        ListResourcesResultSchema: vo,
        ListRootsRequestSchema: ci,
        ListRootsResultSchema: ui,
        ListToolsRequestSchema: Bo,
        ListToolsResultSchema: jo,
        LoggingLevelSchema: Sr,
        LoggingMessageNotificationSchema: Ho,
        McpError: mt,
        ModelHintSchema: Wo,
        ModelPreferencesSchema: zo,
        NotificationSchema: ge,
        NumberSchemaSchema: Qo,
        PaginatedRequestSchema: Ct,
        PaginatedResultSchema: At,
        PingRequestSchema: Qt,
        PrimitiveSchemaDefinitionSchema: ti,
        ProgressNotificationSchema: en,
        ProgressSchema: _o,
        ProgressTokenSchema: rr,
        PromptArgumentSchema: Ao,
        PromptListChangedNotificationSchema: Fo,
        PromptMessageSchema: Po,
        PromptReferenceSchema: si,
        PromptSchema: Do,
        ReadResourceRequestSchema: To,
        ReadResourceResultSchema: bo,
        RequestIdSchema: Et,
        RequestSchema: oe,
        ResourceContentsSchema: fr,
        ResourceLinkSchema: Lo,
        ResourceListChangedNotificationSchema: xo,
        ResourceReferenceSchema: Fc,
        ResourceSchema: gr,
        ResourceTemplateReferenceSchema: wr,
        ResourceTemplateSchema: go,
        ResourceUpdatedNotificationSchema: Co,
        ResultSchema: le,
        RootSchema: ai,
        RootsListChangedNotificationSchema: li,
        SUPPORTED_PROTOCOL_VERSIONS: Rc,
        SamplingMessageSchema: Vo,
        ServerCapabilitiesSchema: ho,
        ServerNotificationSchema: qc,
        ServerRequestSchema: jc,
        ServerResultSchema: Gc,
        SetLevelRequestSchema: Jo,
        StringSchemaSchema: Xo,
        SubscribeRequestSchema: Io,
        TextContentSchema: tn,
        TextResourceContentsSchema: hr,
        ToolAnnotationsSchema: Uo,
        ToolListChangedNotificationSchema: Go,
        ToolSchema: $o,
        UnsubscribeRequestSchema: Eo,
        isInitializeRequest: Lc,
        isInitializedNotification: Pc,
        isJSONRPCError: lo,
        isJSONRPCNotification: uo,
        isJSONRPCRequest: co,
        isJSONRPCResponse: jn,
      },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  ),
  sn = 6e4;
class kf {
  constructor(e) {
    ((this._options = e),
      (this._requestMessageId = 0),
      (this._requestHandlers = new Map()),
      (this._requestHandlerAbortControllers = new Map()),
      (this._notificationHandlers = new Map()),
      (this._responseHandlers = new Map()),
      (this._progressHandlers = new Map()),
      (this._timeoutInfo = new Map()),
      (this._pendingDebouncedNotifications = new Set()),
      this.setNotificationHandler(Xt, (n) => {
        const r = this._requestHandlerAbortControllers.get(n.params.requestId);
        r?.abort(n.params.reason);
      }),
      this.setNotificationHandler(en, (n) => {
        this._onprogress(n);
      }),
      this.setRequestHandler(Qt, (n) => ({})));
  }
  _setupTimeout(e, n, r, o, s = !1) {
    this._timeoutInfo.set(e, {
      timeoutId: setTimeout(o, n),
      startTime: Date.now(),
      timeout: n,
      maxTotalTimeout: r,
      resetTimeoutOnProgress: s,
      onTimeout: o,
    });
  }
  _resetTimeout(e) {
    const n = this._timeoutInfo.get(e);
    if (!n) return !1;
    const r = Date.now() - n.startTime;
    if (n.maxTotalTimeout && r >= n.maxTotalTimeout)
      throw (
        this._timeoutInfo.delete(e),
        new mt(Ee.RequestTimeout, "Maximum total timeout exceeded", {
          maxTotalTimeout: n.maxTotalTimeout,
          totalElapsed: r,
        })
      );
    return (
      clearTimeout(n.timeoutId),
      (n.timeoutId = setTimeout(n.onTimeout, n.timeout)),
      !0
    );
  }
  _cleanupTimeout(e) {
    const n = this._timeoutInfo.get(e);
    n && (clearTimeout(n.timeoutId), this._timeoutInfo.delete(e));
  }
  async connect(e) {
    var n, r, o;
    this._transport = e;
    const s =
      (n = this.transport) === null || n === void 0 ? void 0 : n.onclose;
    this._transport.onclose = () => {
      (s?.(), this._onclose());
    };
    const i =
      (r = this.transport) === null || r === void 0 ? void 0 : r.onerror;
    this._transport.onerror = (u) => {
      (i?.(u), this._onerror(u));
    };
    const c =
      (o = this._transport) === null || o === void 0 ? void 0 : o.onmessage;
    ((this._transport.onmessage = (u, l) => {
      (c?.(u, l),
        jn(u) || lo(u)
          ? this._onresponse(u)
          : co(u)
            ? this._onrequest(u, l)
            : uo(u)
              ? this._onnotification(u)
              : this._onerror(
                  new Error(`Unknown message type: ${JSON.stringify(u)}`),
                ));
    }),
      await this._transport.start());
  }
  _onclose() {
    var e;
    const n = this._responseHandlers;
    ((this._responseHandlers = new Map()),
      this._progressHandlers.clear(),
      this._pendingDebouncedNotifications.clear(),
      (this._transport = void 0),
      (e = this.onclose) === null || e === void 0 || e.call(this));
    const r = new mt(Ee.ConnectionClosed, "Connection closed");
    for (const o of n.values()) o(r);
  }
  _onerror(e) {
    var n;
    (n = this.onerror) === null || n === void 0 || n.call(this, e);
  }
  _onnotification(e) {
    var n;
    const r =
      (n = this._notificationHandlers.get(e.method)) !== null && n !== void 0
        ? n
        : this.fallbackNotificationHandler;
    r !== void 0 &&
      Promise.resolve()
        .then(() => r(e))
        .catch((o) =>
          this._onerror(
            new Error(`Uncaught error in notification handler: ${o}`),
          ),
        );
  }
  _onrequest(e, n) {
    var r, o;
    const s =
        (r = this._requestHandlers.get(e.method)) !== null && r !== void 0
          ? r
          : this.fallbackRequestHandler,
      i = this._transport;
    if (s === void 0) {
      i?.send({
        jsonrpc: "2.0",
        id: e.id,
        error: { code: Ee.MethodNotFound, message: "Method not found" },
      }).catch((l) =>
        this._onerror(new Error(`Failed to send an error response: ${l}`)),
      );
      return;
    }
    const c = new AbortController();
    this._requestHandlerAbortControllers.set(e.id, c);
    const u = {
      signal: c.signal,
      sessionId: i?.sessionId,
      _meta: (o = e.params) === null || o === void 0 ? void 0 : o._meta,
      sendNotification: (l) => this.notification(l, { relatedRequestId: e.id }),
      sendRequest: (l, d, g) =>
        this.request(l, d, { ...g, relatedRequestId: e.id }),
      authInfo: n?.authInfo,
      requestId: e.id,
      requestInfo: n?.requestInfo,
    };
    Promise.resolve()
      .then(() => s(e, u))
      .then(
        (l) => {
          if (!c.signal.aborted)
            return i?.send({ result: l, jsonrpc: "2.0", id: e.id });
        },
        (l) => {
          var d;
          if (!c.signal.aborted)
            return i?.send({
              jsonrpc: "2.0",
              id: e.id,
              error: {
                code: Number.isSafeInteger(l.code) ? l.code : Ee.InternalError,
                message:
                  (d = l.message) !== null && d !== void 0
                    ? d
                    : "Internal error",
              },
            });
        },
      )
      .catch((l) => this._onerror(new Error(`Failed to send response: ${l}`)))
      .finally(() => {
        this._requestHandlerAbortControllers.delete(e.id);
      });
  }
  _onprogress(e) {
    const { progressToken: n, ...r } = e.params,
      o = Number(n),
      s = this._progressHandlers.get(o);
    if (!s) {
      this._onerror(
        new Error(
          `Received a progress notification for an unknown token: ${JSON.stringify(e)}`,
        ),
      );
      return;
    }
    const i = this._responseHandlers.get(o),
      c = this._timeoutInfo.get(o);
    if (c && i && c.resetTimeoutOnProgress)
      try {
        this._resetTimeout(o);
      } catch (u) {
        i(u);
        return;
      }
    s(r);
  }
  _onresponse(e) {
    const n = Number(e.id),
      r = this._responseHandlers.get(n);
    if (r === void 0) {
      this._onerror(
        new Error(
          `Received a response for an unknown message ID: ${JSON.stringify(e)}`,
        ),
      );
      return;
    }
    if (
      (this._responseHandlers.delete(n),
      this._progressHandlers.delete(n),
      this._cleanupTimeout(n),
      jn(e))
    )
      r(e);
    else {
      const o = new mt(e.error.code, e.error.message, e.error.data);
      r(o);
    }
  }
  get transport() {
    return this._transport;
  }
  async close() {
    var e;
    await ((e = this._transport) === null || e === void 0 ? void 0 : e.close());
  }
  request(e, n, r) {
    const {
      relatedRequestId: o,
      resumptionToken: s,
      onresumptiontoken: i,
    } = r ?? {};
    return new Promise((c, u) => {
      var l, d, g, f, v, _;
      if (!this._transport) {
        u(new Error("Not connected"));
        return;
      }
      (((l = this._options) === null || l === void 0
        ? void 0
        : l.enforceStrictCapabilities) === !0 &&
        this.assertCapabilityForMethod(e.method),
        (d = r?.signal) === null || d === void 0 || d.throwIfAborted());
      const w = this._requestMessageId++,
        E = { ...e, jsonrpc: "2.0", id: w };
      r?.onprogress &&
        (this._progressHandlers.set(w, r.onprogress),
        (E.params = {
          ...e.params,
          _meta: {
            ...(((g = e.params) === null || g === void 0 ? void 0 : g._meta) ||
              {}),
            progressToken: w,
          },
        }));
      const b = (C) => {
        var p;
        (this._responseHandlers.delete(w),
          this._progressHandlers.delete(w),
          this._cleanupTimeout(w),
          (p = this._transport) === null ||
            p === void 0 ||
            p
              .send(
                {
                  jsonrpc: "2.0",
                  method: "notifications/cancelled",
                  params: { requestId: w, reason: String(C) },
                },
                {
                  relatedRequestId: o,
                  resumptionToken: s,
                  onresumptiontoken: i,
                },
              )
              .catch((m) =>
                this._onerror(new Error(`Failed to send cancellation: ${m}`)),
              ),
          u(C));
      };
      (this._responseHandlers.set(w, (C) => {
        var p;
        if (!(!((p = r?.signal) === null || p === void 0) && p.aborted)) {
          if (C instanceof Error) return u(C);
          try {
            const m = n.parse(C.result);
            c(m);
          } catch (m) {
            u(m);
          }
        }
      }),
        (f = r?.signal) === null ||
          f === void 0 ||
          f.addEventListener("abort", () => {
            var C;
            b((C = r?.signal) === null || C === void 0 ? void 0 : C.reason);
          }));
      const I = (v = r?.timeout) !== null && v !== void 0 ? v : sn,
        O = () =>
          b(new mt(Ee.RequestTimeout, "Request timed out", { timeout: I }));
      (this._setupTimeout(
        w,
        I,
        r?.maxTotalTimeout,
        O,
        (_ = r?.resetTimeoutOnProgress) !== null && _ !== void 0 ? _ : !1,
      ),
        this._transport
          .send(E, {
            relatedRequestId: o,
            resumptionToken: s,
            onresumptiontoken: i,
          })
          .catch((C) => {
            (this._cleanupTimeout(w), u(C));
          }));
    });
  }
  async notification(e, n) {
    var r, o;
    if (!this._transport) throw new Error("Not connected");
    if (
      (this.assertNotificationCapability(e.method),
      ((o =
        (r = this._options) === null || r === void 0
          ? void 0
          : r.debouncedNotificationMethods) !== null && o !== void 0
        ? o
        : []
      ).includes(e.method) &&
        !e.params &&
        !n?.relatedRequestId)
    ) {
      if (this._pendingDebouncedNotifications.has(e.method)) return;
      (this._pendingDebouncedNotifications.add(e.method),
        Promise.resolve().then(() => {
          var u;
          if (
            (this._pendingDebouncedNotifications.delete(e.method),
            !this._transport)
          )
            return;
          const l = { ...e, jsonrpc: "2.0" };
          (u = this._transport) === null ||
            u === void 0 ||
            u.send(l, n).catch((d) => this._onerror(d));
        }));
      return;
    }
    const c = { ...e, jsonrpc: "2.0" };
    await this._transport.send(c, n);
  }
  setRequestHandler(e, n) {
    const r = e.shape.method.value;
    (this.assertRequestHandlerCapability(r),
      this._requestHandlers.set(r, (o, s) =>
        Promise.resolve(n(e.parse(o), s)),
      ));
  }
  removeRequestHandler(e) {
    this._requestHandlers.delete(e);
  }
  assertCanSetRequestHandler(e) {
    if (this._requestHandlers.has(e))
      throw new Error(
        `A request handler for ${e} already exists, which would be overridden`,
      );
  }
  setNotificationHandler(e, n) {
    this._notificationHandlers.set(e.shape.method.value, (r) =>
      Promise.resolve(n(e.parse(r))),
    );
  }
  removeNotificationHandler(e) {
    this._notificationHandlers.delete(e);
  }
}
function Nf(t, e) {
  return Object.entries(e).reduce(
    (n, [r, o]) => (
      o && typeof o == "object"
        ? (n[r] = n[r] ? { ...n[r], ...o } : o)
        : (n[r] = o),
      n
    ),
    { ...t },
  );
}
async function Tr(t) {
  try {
    return [null, await t()];
  } catch (e) {
    return [e, null];
  }
}
class Ie extends Error {
  state;
  constructor(e, n) {
    (super(e), (this.state = n));
  }
}
class di extends Ie {}
class qn extends Ie {}
class ae extends Ie {}
class G extends Ie {}
class Gn extends Ie {
  error;
  constructor(e, n, r) {
    (super(e, r), (this.error = n));
  }
}
class pi extends Ie {
  error;
  constructor(e, n, r) {
    (super(e, r), (this.error = n));
  }
}
class Jn extends Ie {
  result;
  constructor(e, n, r) {
    (super(e, r), (this.result = n));
  }
}
class gt extends Ie {
  result;
  constructor(e, n, r) {
    (super(e, r), (this.result = n));
  }
}
function it(t) {
  if (typeof t != "object" || t === null) return;
  const e = t;
  return e._zod?.def || e._def || e.def;
}
function on(t) {
  const e = it(t);
  if (!e) return;
  const n =
    (typeof e.typeName == "string" && e.typeName) ||
    (typeof e.type == "string" && e.type);
  if (typeof n != "string") return;
  const r = n.toLowerCase();
  return r.startsWith("zod") ? r.slice(3) : r;
}
function $e(t) {
  return it(t) ? on(t) === "object" : !1;
}
function Jc(t) {
  return (
    typeof t == "object" &&
    t !== null &&
    "input" in t &&
    typeof t.input == "string"
  );
}
const Hc = "http://json-schema.org/draft-07/schema#",
  Wc = new Set(["optional"]),
  zc = new Set([
    "brand",
    "branded",
    "catch",
    "default",
    "effects",
    "pipeline",
    "pipe",
    "prefault",
    "readonly",
    "refinement",
    "transform",
  ]),
  is = {
    string: { type: "string" },
    number: { type: "number" },
    bigint: { type: "integer" },
    boolean: { type: "boolean" },
    date: { type: "string", format: "date-time" },
  };
function fi(t) {
  return (
    typeof t == "object" &&
    t !== null &&
    t.type === "object" &&
    "properties" in t &&
    "additionalProperties" in t
  );
}
function Vc(t) {
  const e = hi(t);
  if (e)
    return (
      Array.isArray(e.required) || (e.required = []),
      typeof e.additionalProperties > "u" && (e.additionalProperties = !1),
      typeof e.$schema != "string" && (e.$schema = Hc),
      e
    );
}
function hi(t) {
  const e = iu(t);
  if (!e) return;
  const n = {},
    r = [];
  for (const [o, s] of Object.entries(e)) {
    const { schema: i, optional: c } = Kc(s);
    if (!i) return;
    ((n[o] = i), c || r.push(o));
  }
  return {
    type: "object",
    properties: n,
    required: r,
    additionalProperties: !1,
  };
}
function Kc(t) {
  let e = Hn(t),
    n = !1;
  for (; Wc.has(on(e) ?? "");) {
    n = !0;
    const r = it(e),
      o = Hn(r?.innerType);
    if (!o || o === e) break;
    e = o;
  }
  return { schema: we(e), optional: n };
}
function we(t) {
  if (t === void 0) return;
  const e = Hn(t),
    n = on(e),
    r = it(e);
  if (n) {
    if (n in is) return is[n];
    switch (n) {
      case "object":
        return hi(e);
      case "array":
        return Yc(r);
      case "tuple":
        return Zc(r);
      case "union":
        return Xc(r);
      case "intersection":
        return Qc(r);
      case "literal":
        return su(r);
      case "enum":
      case "nativeenum":
        return ou(r);
      case "record":
        return eu(r);
      case "map":
        return tu(r);
      case "set":
        return nu(r);
      case "nullable":
        return ru(r);
      default:
        return;
    }
  }
}
function Yc(t) {
  const e = we(mi(t, "element", "items", "type"));
  return e ? { type: "array", items: e } : void 0;
}
function Zc(t) {
  const e = _i(t?.items)
    .map((r) => we(r))
    .filter(Boolean);
  if (!e.length) return;
  const n = { type: "array", items: e, minItems: e.length };
  return (t?.rest || (n.maxItems = e.length), n);
}
function Xc(t) {
  const e = _i(t?.options ?? t?.schemas)
    .map((n) => we(n))
    .filter(Boolean);
  return e.length ? { anyOf: e } : void 0;
}
function Qc(t) {
  const e = we(t?.left),
    n = we(t?.right);
  return e && n ? { allOf: [e, n] } : void 0;
}
function eu(t) {
  const e = we(t?.valueType ?? t?.values);
  return e ? { type: "object", additionalProperties: e } : void 0;
}
function tu(t) {
  const e = we(t?.valueType ?? t?.values);
  return e ? { type: "array", items: e } : void 0;
}
function nu(t) {
  const e = we(t?.valueType);
  return e ? { type: "array", items: e, uniqueItems: !0 } : void 0;
}
function ru(t) {
  const e = we(t?.innerType ?? t?.type);
  return e ? { anyOf: [e, { type: "null" }] } : void 0;
}
function Hn(t) {
  let e = t;
  for (; zc.has(on(e) ?? "");) {
    const n = it(e),
      r =
        n?.innerType ??
        n?.schema ??
        n?.base ??
        n?.type ??
        n?.wrapped ??
        n?.underlying;
    if (!r || r === e) return e;
    e = r;
  }
  return e;
}
function mi(t, ...e) {
  if (t) {
    for (const n of e) if (n in t && t[n] !== void 0) return t[n];
  }
}
function _i(t) {
  return Array.isArray(t) ? t : t === void 0 ? [] : [t];
}
function su(t) {
  if (!t) return;
  const e = mi(t, "value", "literal");
  if (e !== void 0) return { const: e, type: e === null ? "null" : typeof e };
}
function ou(t) {
  if (t) {
    if (Array.isArray(t.values)) return { enum: t.values };
    if (Array.isArray(t.options)) return { enum: t.options };
    if (t.values && typeof t.values == "object")
      return { enum: Object.values(t.values) };
    if (t.enum && typeof t.enum == "object")
      return { enum: Object.values(t.enum) };
  }
}
function iu(t) {
  if (typeof t != "object" || t === null) return;
  const e = t;
  if (e.shape && typeof e.shape == "object") return e.shape;
  if (typeof e.shape == "function")
    try {
      return e.shape();
    } catch {
      return;
    }
  const r = it(e)?.shape;
  if (r && typeof r == "object") return r;
  if (typeof r == "function")
    try {
      return r();
    } catch {
      return;
    }
}
const au = yc,
  cu = gc;
function gi(t) {
  return Vc(t);
}
function Wt(t) {
  if (
    ((t = t.replace(/\s/g, "_")),
    (t = t.replace(/[^a-zA-Z0-9]/g, "_")),
    t.length === 0)
  )
    throw new Error("Tool name cannot be empty");
  return t;
}
function br(t, e) {
  const n = (r) => JSON.parse(r);
  if ($e(t)) {
    const r = (s) => {
      const i = gi(t);
      if (i) return { schema: i, parser: (u) => t.parse(JSON.parse(u)) };
      const c =
        s instanceof Error ? ` Upstream helper error: ${s.message}` : "";
      throw new G(
        `Unable to convert the provided Zod schema to JSON Schema. Ensure that the \`zod\` package is available at runtime or provide a JSON schema object instead.${c}`,
      );
    };
    let o;
    try {
      o = au({ name: e, parameters: t, function: () => {}, description: "" });
    } catch (s) {
      return r(s);
    }
    return fi(o.parameters)
      ? { schema: o.parameters, parser: o.$parseRaw }
      : r();
  } else if (typeof t == "object" && t !== null)
    return { schema: t, parser: n };
  throw new G("Input type is not a ZodObject or a valid JSON schema");
}
function as(t) {
  if (t === "text") return "text";
  if ($e(t)) {
    const e = (r, o) => {
      const s = gi(t);
      if (s)
        return {
          type: r?.type ?? "json_schema",
          name: r?.name ?? "output",
          strict: r?.strict ?? !1,
          schema: s,
        };
      const i =
        o instanceof Error ? ` Upstream helper error: ${o.message}` : "";
      throw new G(
        `Unable to convert the provided Zod schema to JSON Schema. Ensure that the \`zod\` package is available at runtime or provide a JSON schema object instead.${i}`,
      );
    };
    let n;
    try {
      n = cu(t, "output");
    } catch (r) {
      return e(void 0, r);
    }
    return fi(n.schema)
      ? { type: n.type, name: n.name, strict: n.strict || !1, schema: n.schema }
      : e(n);
  }
  return t;
}
var Pt = { exports: {} },
  Mt = { exports: {} },
  In,
  cs;
function yi() {
  if (cs) return In;
  cs = 1;
  function t(e) {
    ((r.debug = r),
      (r.default = r),
      (r.coerce = l),
      (r.disable = c),
      (r.enable = s),
      (r.enabled = u),
      (r.humanize = vc()),
      (r.destroy = d),
      Object.keys(e).forEach((g) => {
        r[g] = e[g];
      }),
      (r.names = []),
      (r.skips = []),
      (r.formatters = {}));
    function n(g) {
      let f = 0;
      for (let v = 0; v < g.length; v++)
        ((f = (f << 5) - f + g.charCodeAt(v)), (f |= 0));
      return r.colors[Math.abs(f) % r.colors.length];
    }
    r.selectColor = n;
    function r(g) {
      let f,
        v = null,
        _,
        w;
      function E(...b) {
        if (!E.enabled) return;
        const I = E,
          O = Number(new Date()),
          C = O - (f || O);
        ((I.diff = C),
          (I.prev = f),
          (I.curr = O),
          (f = O),
          (b[0] = r.coerce(b[0])),
          typeof b[0] != "string" && b.unshift("%O"));
        let p = 0;
        ((b[0] = b[0].replace(/%([a-zA-Z%])/g, (x, T) => {
          if (x === "%%") return "%";
          p++;
          const k = r.formatters[T];
          if (typeof k == "function") {
            const N = b[p];
            ((x = k.call(I, N)), b.splice(p, 1), p--);
          }
          return x;
        })),
          r.formatArgs.call(I, b),
          (I.log || r.log).apply(I, b));
      }
      return (
        (E.namespace = g),
        (E.useColors = r.useColors()),
        (E.color = r.selectColor(g)),
        (E.extend = o),
        (E.destroy = r.destroy),
        Object.defineProperty(E, "enabled", {
          enumerable: !0,
          configurable: !1,
          get: () =>
            v !== null
              ? v
              : (_ !== r.namespaces && ((_ = r.namespaces), (w = r.enabled(g))),
                w),
          set: (b) => {
            v = b;
          },
        }),
        typeof r.init == "function" && r.init(E),
        E
      );
    }
    function o(g, f) {
      const v = r(this.namespace + (typeof f > "u" ? ":" : f) + g);
      return ((v.log = this.log), v);
    }
    function s(g) {
      (r.save(g), (r.namespaces = g), (r.names = []), (r.skips = []));
      const f = (typeof g == "string" ? g : "")
        .trim()
        .replace(/\s+/g, ",")
        .split(",")
        .filter(Boolean);
      for (const v of f)
        v[0] === "-" ? r.skips.push(v.slice(1)) : r.names.push(v);
    }
    function i(g, f) {
      let v = 0,
        _ = 0,
        w = -1,
        E = 0;
      for (; v < g.length;)
        if (_ < f.length && (f[_] === g[v] || f[_] === "*"))
          f[_] === "*" ? ((w = _), (E = v), _++) : (v++, _++);
        else if (w !== -1) ((_ = w + 1), E++, (v = E));
        else return !1;
      for (; _ < f.length && f[_] === "*";) _++;
      return _ === f.length;
    }
    function c() {
      const g = [...r.names, ...r.skips.map((f) => "-" + f)].join(",");
      return (r.enable(""), g);
    }
    function u(g) {
      for (const f of r.skips) if (i(g, f)) return !1;
      for (const f of r.names) if (i(g, f)) return !0;
      return !1;
    }
    function l(g) {
      return g instanceof Error ? g.stack || g.message : g;
    }
    function d() {
      console.warn(
        "Instance method `debug.destroy()` is deprecated and no longer does anything. It will be removed in the next major version of `debug`.",
      );
    }
    return (r.enable(r.load()), r);
  }
  return ((In = t), In);
}
var us;
function uu() {
  return (
    us ||
      ((us = 1),
      (function (t, e) {
        ((e.formatArgs = r),
          (e.save = o),
          (e.load = s),
          (e.useColors = n),
          (e.storage = i()),
          (e.destroy = (() => {
            let u = !1;
            return () => {
              u ||
                ((u = !0),
                console.warn(
                  "Instance method `debug.destroy()` is deprecated and no longer does anything. It will be removed in the next major version of `debug`.",
                ));
            };
          })()),
          (e.colors = [
            "#0000CC",
            "#0000FF",
            "#0033CC",
            "#0033FF",
            "#0066CC",
            "#0066FF",
            "#0099CC",
            "#0099FF",
            "#00CC00",
            "#00CC33",
            "#00CC66",
            "#00CC99",
            "#00CCCC",
            "#00CCFF",
            "#3300CC",
            "#3300FF",
            "#3333CC",
            "#3333FF",
            "#3366CC",
            "#3366FF",
            "#3399CC",
            "#3399FF",
            "#33CC00",
            "#33CC33",
            "#33CC66",
            "#33CC99",
            "#33CCCC",
            "#33CCFF",
            "#6600CC",
            "#6600FF",
            "#6633CC",
            "#6633FF",
            "#66CC00",
            "#66CC33",
            "#9900CC",
            "#9900FF",
            "#9933CC",
            "#9933FF",
            "#99CC00",
            "#99CC33",
            "#CC0000",
            "#CC0033",
            "#CC0066",
            "#CC0099",
            "#CC00CC",
            "#CC00FF",
            "#CC3300",
            "#CC3333",
            "#CC3366",
            "#CC3399",
            "#CC33CC",
            "#CC33FF",
            "#CC6600",
            "#CC6633",
            "#CC9900",
            "#CC9933",
            "#CCCC00",
            "#CCCC33",
            "#FF0000",
            "#FF0033",
            "#FF0066",
            "#FF0099",
            "#FF00CC",
            "#FF00FF",
            "#FF3300",
            "#FF3333",
            "#FF3366",
            "#FF3399",
            "#FF33CC",
            "#FF33FF",
            "#FF6600",
            "#FF6633",
            "#FF9900",
            "#FF9933",
            "#FFCC00",
            "#FFCC33",
          ]));
        function n() {
          if (
            typeof window < "u" &&
            window.process &&
            (window.process.type === "renderer" || window.process.__nwjs)
          )
            return !0;
          if (
            typeof navigator < "u" &&
            navigator.userAgent &&
            navigator.userAgent.toLowerCase().match(/(edge|trident)\/(\d+)/)
          )
            return !1;
          let u;
          return (
            (typeof document < "u" &&
              document.documentElement &&
              document.documentElement.style &&
              document.documentElement.style.WebkitAppearance) ||
            (typeof window < "u" &&
              window.console &&
              (window.console.firebug ||
                (window.console.exception && window.console.table))) ||
            (typeof navigator < "u" &&
              navigator.userAgent &&
              (u = navigator.userAgent.toLowerCase().match(/firefox\/(\d+)/)) &&
              parseInt(u[1], 10) >= 31) ||
            (typeof navigator < "u" &&
              navigator.userAgent &&
              navigator.userAgent.toLowerCase().match(/applewebkit\/(\d+)/))
          );
        }
        function r(u) {
          if (
            ((u[0] =
              (this.useColors ? "%c" : "") +
              this.namespace +
              (this.useColors ? " %c" : " ") +
              u[0] +
              (this.useColors ? "%c " : " ") +
              "+" +
              t.exports.humanize(this.diff)),
            !this.useColors)
          )
            return;
          const l = "color: " + this.color;
          u.splice(1, 0, l, "color: inherit");
          let d = 0,
            g = 0;
          (u[0].replace(/%[a-zA-Z%]/g, (f) => {
            f !== "%%" && (d++, f === "%c" && (g = d));
          }),
            u.splice(g, 0, l));
        }
        e.log = console.debug || console.log || (() => {});
        function o(u) {
          try {
            u ? e.storage.setItem("debug", u) : e.storage.removeItem("debug");
          } catch {}
        }
        function s() {
          let u;
          try {
            u = e.storage.getItem("debug") || e.storage.getItem("DEBUG");
          } catch {}
          return (
            !u &&
              typeof process < "u" &&
              "env" in process &&
              (u = process.env.DEBUG),
            u
          );
        }
        function i() {
          try {
            return localStorage;
          } catch {}
        }
        t.exports = yi()(e);
        const { formatters: c } = t.exports;
        c.j = function (u) {
          try {
            return JSON.stringify(u);
          } catch (l) {
            return "[UnexpectedJSONParseError]: " + l.message;
          }
        };
      })(Mt, Mt.exports)),
    Mt.exports
  );
}
var Ft = { exports: {} },
  ls;
function lu() {
  return (
    ls ||
      ((ls = 1),
      (function (t, e) {
        const n = Sc,
          r = wc;
        ((e.init = d),
          (e.log = c),
          (e.formatArgs = s),
          (e.save = u),
          (e.load = l),
          (e.useColors = o),
          (e.destroy = r.deprecate(
            () => {},
            "Instance method `debug.destroy()` is deprecated and no longer does anything. It will be removed in the next major version of `debug`.",
          )),
          (e.colors = [6, 2, 3, 4, 5, 1]));
        try {
          const f = mc();
          f &&
            (f.stderr || f).level >= 2 &&
            (e.colors = [
              20, 21, 26, 27, 32, 33, 38, 39, 40, 41, 42, 43, 44, 45, 56, 57,
              62, 63, 68, 69, 74, 75, 76, 77, 78, 79, 80, 81, 92, 93, 98, 99,
              112, 113, 128, 129, 134, 135, 148, 149, 160, 161, 162, 163, 164,
              165, 166, 167, 168, 169, 170, 171, 172, 173, 178, 179, 184, 185,
              196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208,
              209, 214, 215, 220, 221,
            ]);
        } catch {}
        e.inspectOpts = Object.keys(process.env)
          .filter((f) => /^debug_/i.test(f))
          .reduce((f, v) => {
            const _ = v
              .substring(6)
              .toLowerCase()
              .replace(/_([a-z])/g, (E, b) => b.toUpperCase());
            let w = process.env[v];
            return (
              /^(yes|on|true|enabled)$/i.test(w)
                ? (w = !0)
                : /^(no|off|false|disabled)$/i.test(w)
                  ? (w = !1)
                  : w === "null"
                    ? (w = null)
                    : (w = Number(w)),
              (f[_] = w),
              f
            );
          }, {});
        function o() {
          return "colors" in e.inspectOpts
            ? !!e.inspectOpts.colors
            : n.isatty(process.stderr.fd);
        }
        function s(f) {
          const { namespace: v, useColors: _ } = this;
          if (_) {
            const w = this.color,
              E = "\x1B[3" + (w < 8 ? w : "8;5;" + w),
              b = `  ${E};1m${v} \x1B[0m`;
            ((f[0] =
              b +
              f[0]
                .split(
                  `
`,
                )
                .join(
                  `
` + b,
                )),
              f.push(E + "m+" + t.exports.humanize(this.diff) + "\x1B[0m"));
          } else f[0] = i() + v + " " + f[0];
        }
        function i() {
          return e.inspectOpts.hideDate ? "" : new Date().toISOString() + " ";
        }
        function c(...f) {
          return process.stderr.write(
            r.formatWithOptions(e.inspectOpts, ...f) +
              `
`,
          );
        }
        function u(f) {
          f ? (process.env.DEBUG = f) : delete process.env.DEBUG;
        }
        function l() {
          return process.env.DEBUG;
        }
        function d(f) {
          f.inspectOpts = {};
          const v = Object.keys(e.inspectOpts);
          for (let _ = 0; _ < v.length; _++)
            f.inspectOpts[v[_]] = e.inspectOpts[v[_]];
        }
        t.exports = yi()(e);
        const { formatters: g } = t.exports;
        ((g.o = function (f) {
          return (
            (this.inspectOpts.colors = this.useColors),
            r
              .inspect(f, this.inspectOpts)
              .split(
                `
`,
              )
              .map((v) => v.trim())
              .join(" ")
          );
        }),
          (g.O = function (f) {
            return (
              (this.inspectOpts.colors = this.useColors),
              r.inspect(f, this.inspectOpts)
            );
          }));
      })(Ft, Ft.exports)),
    Ft.exports
  );
}
var ds;
function du() {
  return (
    ds ||
      ((ds = 1),
      typeof process > "u" ||
      process.type === "renderer" ||
      process.browser === !0 ||
      process.__nwjs
        ? (Pt.exports = uu())
        : (Pt.exports = lu())),
    Pt.exports
  );
}
var pu = du();
const an = ro(pu);
function xr() {
  return Ir();
}
function Wn(t) {
  const e = xr();
  return typeof e < "u" && (e[t] === "true" || e[t] === "1");
}
const vi = {
    get disabled() {
      return xr().NODE_ENV === "test"
        ? !0
        : Wn("OPENAI_AGENTS_DISABLE_TRACING");
    },
  },
  Si = {
    get dontLogModelData() {
      return Wn("OPENAI_AGENTS_DONT_LOG_MODEL_DATA");
    },
    get dontLogToolData() {
      return Wn("OPENAI_AGENTS_DONT_LOG_TOOL_DATA");
    },
  },
  fu = Si.dontLogModelData,
  hu = Si.dontLogToolData;
function je(t = "openai-agents") {
  return {
    namespace: t,
    debug: an(t),
    error: console.error,
    warn: console.warn,
    dontLogModelData: fu,
    dontLogToolData: hu,
  };
}
const P = je("openai-agents:core"),
  ps = 20;
function Oe(t) {
  if (t == null) return String(t);
  if (wi(t)) return _t(new Uint8Array(t));
  if (Ti(t)) {
    const e = t;
    return _t(new Uint8Array(e.buffer, e.byteOffset, e.byteLength));
  }
  if (typeof t == "string") return t;
  if (typeof t == "object")
    try {
      return JSON.stringify(t, gu);
    } catch {
      return "[object with circular references]";
    }
  return String(t);
}
function wi(t) {
  if (t instanceof ArrayBuffer) return !0;
  const e = globalThis.SharedArrayBuffer;
  return !!(e && t instanceof e);
}
function Ti(t) {
  return typeof ArrayBuffer < "u" && ArrayBuffer.isView(t);
}
function mu(t) {
  return (
    typeof t == "object" &&
    t !== null &&
    t.type === "Buffer" &&
    Array.isArray(t.data)
  );
}
function _t(t) {
  if (t.length === 0) return "[byte array (0 bytes)]";
  const e = Math.min(t.length, ps),
    n = [];
  for (let s = 0; s < e; s++) n.push(_u(t[s]));
  const r = t.length > ps ? " …" : "";
  return `[byte array ${n.join(" ")}${r} (${t.length} bytes)]`;
}
function _u(t) {
  return `0x${t.toString(16).padStart(2, "0")}`;
}
function gu(t, e) {
  if (wi(e)) return _t(new Uint8Array(e));
  if (Ti(e)) {
    const n = e;
    return _t(new Uint8Array(n.buffer, n.byteOffset, n.byteLength));
  }
  return mu(e) ? _t(Uint8Array.from(e.data)) : e;
}
function yu(t) {
  return {
    type: "computer",
    name: t.name ?? "computer_use_preview",
    computer: t.computer,
  };
}
function vu(t) {
  return "serverUrl" in t
    ? {
        type: "hosted_tool",
        name: "hosted_mcp",
        providerData:
          typeof t.requireApproval > "u" || t.requireApproval === "never"
            ? {
                type: "mcp",
                server_label: t.serverLabel,
                server_url: t.serverUrl,
                authorization: t.authorization,
                require_approval: "never",
                allowed_tools: ze(t.allowedTools),
                headers: t.headers,
              }
            : {
                type: "mcp",
                server_label: t.serverLabel,
                server_url: t.serverUrl,
                authorization: t.authorization,
                allowed_tools: ze(t.allowedTools),
                headers: t.headers,
                require_approval:
                  typeof t.requireApproval == "string"
                    ? "always"
                    : En(t.requireApproval),
                on_approval: t.onApproval,
              },
      }
    : "connectorId" in t
      ? {
          type: "hosted_tool",
          name: "hosted_mcp",
          providerData:
            typeof t.requireApproval > "u" || t.requireApproval === "never"
              ? {
                  type: "mcp",
                  server_label: t.serverLabel,
                  connector_id: t.connectorId,
                  authorization: t.authorization,
                  require_approval: "never",
                  allowed_tools: ze(t.allowedTools),
                  headers: t.headers,
                }
              : {
                  type: "mcp",
                  server_label: t.serverLabel,
                  connector_id: t.connectorId,
                  authorization: t.authorization,
                  allowed_tools: ze(t.allowedTools),
                  headers: t.headers,
                  require_approval:
                    typeof t.requireApproval == "string"
                      ? "always"
                      : En(t.requireApproval),
                  on_approval: t.onApproval,
                },
        }
      : {
          type: "hosted_tool",
          name: "hosted_mcp",
          providerData:
            typeof t.requireApproval > "u" || t.requireApproval === "never"
              ? {
                  type: "mcp",
                  server_label: t.serverLabel,
                  require_approval: "never",
                  allowed_tools: ze(t.allowedTools),
                }
              : {
                  type: "mcp",
                  server_label: t.serverLabel,
                  allowed_tools: ze(t.allowedTools),
                  require_approval:
                    typeof t.requireApproval == "string"
                      ? "always"
                      : En(t.requireApproval),
                  on_approval: t.onApproval,
                },
        };
}
function Su(t, e) {
  return `An error occurred while running the tool. Please try again. Error: ${e instanceof Error ? e.toString() : String(e)}`;
}
function yt(t) {
  const e = t.name ? Wt(t.name) : Wt(t.execute.name),
    n = typeof t.errorFunction > "u" ? Su : t.errorFunction;
  if (!e)
    throw new Error(
      "Tool name cannot be empty. Either name your function or provide a name in the options.",
    );
  const r = t.strict ?? !0;
  if (!r && $e(t.parameters))
    throw new G("Strict mode is required for Zod parameters");
  const { parser: o, schema: s } = br(t.parameters, e);
  async function i(d, g, f) {
    const [v, _] = await Tr(() => o(g));
    if (v !== null)
      throw (
        P.dontLogToolData
          ? P.debug(`Invalid JSON input for tool ${e}`)
          : P.debug(`Invalid JSON input for tool ${e}: ${g}`),
        new ae("Invalid JSON input for tool")
      );
    P.dontLogToolData
      ? P.debug(`Invoking tool ${e}`)
      : P.debug(`Invoking tool ${e} with input ${g}`);
    const w = await t.execute(_, d, f),
      E = Oe(w);
    return (
      P.dontLogToolData
        ? P.debug(`Tool ${e} completed`)
        : P.debug(`Tool ${e} returned: ${E}`),
      w
    );
  }
  async function c(d, g, f) {
    return i(d, g, f).catch((v) => {
      if (n)
        return (
          tt()?.setError({
            message: "Error running tool (non-fatal)",
            data: { tool_name: e, error: v.toString() },
          }),
          n(d, v)
        );
      throw v;
    });
  }
  const u =
      typeof t.needsApproval == "function"
        ? t.needsApproval
        : async () =>
            typeof t.needsApproval == "boolean" ? t.needsApproval : !1,
    l =
      typeof t.isEnabled == "function"
        ? async (d, g) => {
            const f = t.isEnabled;
            return !!(await f({ runContext: d, agent: g }));
          }
        : async () => (typeof t.isEnabled == "boolean" ? t.isEnabled : !0);
  return {
    type: "function",
    name: e,
    description: t.description,
    parameters: s,
    strict: r,
    invoke: c,
    needsApproval: u,
    isEnabled: l,
  };
}
function En(t) {
  const e = {};
  return (
    t.always && (e.always = { tool_names: t.always.toolNames }),
    t.never && (e.never = { tool_names: t.never.toolNames }),
    e
  );
}
function ze(t) {
  if (!(typeof t > "u"))
    return Array.isArray(t)
      ? { tool_names: t }
      : { tool_names: t?.toolNames ?? [] };
}
const wu = "openai-agents:stdio-mcp-client",
  Tu = "openai-agents:streamable-http-mcp-client",
  bu = "openai-agents:sse-mcp-client";
class bi {
  cacheToolsList;
  _cachedTools = void 0;
  toolFilter;
  logger;
  constructor(e) {
    ((this.logger = e.logger ?? je(wu)),
      (this.cacheToolsList = e.cacheToolsList ?? !1),
      (this.toolFilter = e.toolFilter));
  }
  debugLog(e) {
    an.enabled(this.logger.namespace) && this.logger.debug(e());
  }
}
class xi {
  cacheToolsList;
  _cachedTools = void 0;
  toolFilter;
  logger;
  constructor(e) {
    ((this.logger = e.logger ?? je(Tu)),
      (this.cacheToolsList = e.cacheToolsList ?? !1),
      (this.toolFilter = e.toolFilter));
  }
  debugLog(e) {
    an.enabled(this.logger.namespace) && this.logger.debug(e());
  }
}
class Ii {
  cacheToolsList;
  _cachedTools = void 0;
  toolFilter;
  logger;
  constructor(e) {
    ((this.logger = e.logger ?? je(bu)),
      (this.cacheToolsList = e.cacheToolsList ?? !1),
      (this.toolFilter = e.toolFilter));
  }
  debugLog(e) {
    an.enabled(this.logger.namespace) && this.logger.debug(e());
  }
}
h({
  name: a(),
  description: a().optional(),
  inputSchema: h({
    type: y("object"),
    properties: Y(a(), j()),
    required: U(a()),
    additionalProperties: X(),
  }),
});
class xu extends bi {
  underlying;
  constructor(e) {
    (super(e), (this.underlying = new Du(e)));
  }
  get name() {
    return this.underlying.name;
  }
  connect() {
    return this.underlying.connect();
  }
  close() {
    return this.underlying.close();
  }
  async listTools() {
    if (this.cacheToolsList && this._cachedTools) return this._cachedTools;
    const e = await this.underlying.listTools();
    return (this.cacheToolsList && (this._cachedTools = e), e);
  }
  callTool(e, n) {
    return this.underlying.callTool(e, n);
  }
  invalidateToolsCache() {
    return this.underlying.invalidateToolsCache();
  }
}
class Iu extends xi {
  underlying;
  constructor(e) {
    (super(e), (this.underlying = new Ru(e)));
  }
  get name() {
    return this.underlying.name;
  }
  connect() {
    return this.underlying.connect();
  }
  close() {
    return this.underlying.close();
  }
  async listTools() {
    if (this.cacheToolsList && this._cachedTools) return this._cachedTools;
    const e = await this.underlying.listTools();
    return (this.cacheToolsList && (this._cachedTools = e), e);
  }
  callTool(e, n) {
    return this.underlying.callTool(e, n);
  }
  invalidateToolsCache() {
    return this.underlying.invalidateToolsCache();
  }
}
class Eu extends Ii {
  underlying;
  constructor(e) {
    (super(e), (this.underlying = new Ou(e)));
  }
  get name() {
    return this.underlying.name;
  }
  connect() {
    return this.underlying.connect();
  }
  close() {
    return this.underlying.close();
  }
  async listTools() {
    if (this.cacheToolsList && this._cachedTools) return this._cachedTools;
    const e = await this.underlying.listTools();
    return (this.cacheToolsList && (this._cachedTools = e), e);
  }
  callTool(e, n) {
    return this.underlying.callTool(e, n);
  }
  invalidateToolsCache() {
    return this.underlying.invalidateToolsCache();
  }
}
const qt = {};
async function cn(t) {
  delete qt[t];
}
async function Cu({
  server: t,
  convertSchemasToStrict: e,
  runContext: n,
  agent: r,
}) {
  return t.cacheToolsList && qt[t.name]
    ? qt[t.name].map((o) => zn(o, t, e))
    : la(
        async (o) => {
          const s = await t.listTools();
          let i = s;
          if (n && r) {
            const u = { runContext: n, agent: r, serverName: t.name },
              l = [];
            for (const d of s) {
              const g = t.toolFilter;
              if (g)
                if (typeof g == "function") {
                  if (!(await g(u, d))) {
                    P.debug(
                      `MCP Tool (server: ${t.name}, tool: ${d.name}) is blocked by the callable filter.`,
                    );
                    continue;
                  }
                } else {
                  const f = g.allowedToolNames ?? [],
                    v = g.blockedToolNames ?? [];
                  if (f.length > 0 || v.length > 0) {
                    const _ = f.length > 0 ? f.includes(d.name) : !0,
                      w = v.length > 0 ? v.includes(d.name) : !1;
                    if (!_ || w) {
                      w
                        ? P.debug(
                            `MCP Tool (server: ${t.name}, tool: ${d.name}) is blocked by the static filter.`,
                          )
                        : _ ||
                          P.debug(
                            `MCP Tool (server: ${t.name}, tool: ${d.name}) is not allowed by the static filter.`,
                          );
                      continue;
                    }
                  }
                }
              l.push(d);
            }
            i = l;
          }
          o.spanData.result = i.map((u) => u.name);
          const c = i.map((u) => zn(u, t, e));
          return (t.cacheToolsList && (qt[t.name] = i), c);
        },
        { data: { server: t.name } },
      );
}
async function Ei(t, e, n, r = !1) {
  const o = Array.isArray(t)
      ? { mcpServers: t, runContext: e, agent: n, convertSchemasToStrict: r }
      : t,
    {
      mcpServers: s,
      convertSchemasToStrict: i = !1,
      runContext: c,
      agent: u,
    } = o,
    l = [],
    d = new Set();
  for (const g of s) {
    const f = await Cu({
        server: g,
        convertSchemasToStrict: i,
        runContext: c,
        agent: u,
      }),
      _ = [...new Set(f.map((w) => w.name))].filter((w) => d.has(w));
    if (_.length > 0)
      throw new G(
        `Duplicate tool names found across MCP servers: ${_.join(", ")}`,
      );
    for (const w of f) (d.add(w.name), l.push(w));
  }
  return l;
}
function zn(t, e, n) {
  async function r(i, c) {
    let u = {};
    typeof i == "string" && i
      ? (u = JSON.parse(i))
      : typeof i == "object" && i != null && (u = i);
    const l = tt();
    l && (l.spanData.mcp_data = { server: e.name });
    const d = await e.callTool(t.name, u);
    return d.length === 1 ? d[0] : d;
  }
  const o = {
    ...t.inputSchema,
    type: t.inputSchema?.type ?? "object",
    properties: t.inputSchema?.properties ?? {},
    required: t.inputSchema?.required ?? [],
    additionalProperties: t.inputSchema?.additionalProperties ?? !1,
  };
  if (n || o.additionalProperties === !0)
    try {
      const i = Au(o);
      return yt({
        name: t.name,
        description: t.description || "",
        parameters: i,
        strict: !0,
        execute: r,
      });
    } catch (i) {
      P.warn(`Error converting MCP schema to strict mode: ${i}`);
    }
  const s = { ...o, additionalProperties: !0 };
  return yt({
    name: t.name,
    description: t.description || "",
    parameters: s,
    strict: !1,
    execute: r,
  });
}
function Au(t) {
  const e = { ...t, additionalProperties: !1 };
  return (e.required || (e.required = []), e);
}
function fe(t) {
  throw (
    P.error(
      `
Failed to load the MCP SDK. Please install the @modelcontextprotocol/sdk package.

npm install @modelcontextprotocol/sdk
    `.trim(),
    ),
    t
  );
}
class Du extends bi {
  session = null;
  _cacheDirty = !0;
  _toolsList = [];
  serverInitializeResult = null;
  clientSessionTimeoutSeconds;
  timeout;
  params;
  _name;
  transport = null;
  constructor(e) {
    if (
      (super(e),
      (this.clientSessionTimeoutSeconds = e.clientSessionTimeoutSeconds ?? 5),
      (this.timeout = e.timeout ?? sn),
      "fullCommand" in e)
    ) {
      const n = e.fullCommand.split(" "),
        r = n.shift();
      if (!r) throw new Error("Invalid fullCommand: " + e.fullCommand);
      this.params = {
        ...e,
        command: r,
        args: n,
        encoding: e.encoding || "utf-8",
        encodingErrorHandler: e.encodingErrorHandler || "strict",
      };
    } else this.params = e;
    this._name = e.name || `stdio: ${this.params.command}`;
  }
  async connect() {
    try {
      const { StdioClientTransport: e } =
          await import("./stdio-DSoBbdMS.mjs").catch(fe),
        { Client: n } = await import("./index-BpO2rBmi.mjs").catch(fe);
      ((this.transport = new e({
        command: this.params.command,
        args: this.params.args,
        env: this.params.env,
        cwd: this.params.cwd,
      })),
        (this.session = new n({ name: this._name, version: "1.0.0" })),
        await this.session.connect(this.transport),
        (this.serverInitializeResult = {
          serverInfo: { name: this._name, version: "1.0.0" },
        }));
    } catch (e) {
      throw (
        this.logger.error("Error initializing MCP server:", e),
        await this.close(),
        e
      );
    }
    this.debugLog(() => `Connected to MCP server: ${this._name}`);
  }
  async invalidateToolsCache() {
    (await cn(this.name), (this._cacheDirty = !0));
  }
  async listTools() {
    const { ListToolsResultSchema: e } = await Promise.resolve()
      .then(() => Ze)
      .catch(fe);
    if (!this.session)
      throw new Error(
        "Server not initialized. Make sure you call connect() first.",
      );
    if (this.cacheToolsList && !this._cacheDirty && this._toolsList)
      return this._toolsList;
    this._cacheDirty = !1;
    const n = await this.session.listTools();
    return (
      this.debugLog(() => `Listed tools: ${JSON.stringify(n)}`),
      (this._toolsList = e.parse(n).tools),
      this._toolsList
    );
  }
  async callTool(e, n) {
    const { CallToolResultSchema: r } = await Promise.resolve()
      .then(() => Ze)
      .catch(fe);
    if (!this.session)
      throw new Error(
        "Server not initialized. Make sure you call connect() first.",
      );
    const o = await this.session.callTool(
        { name: e, arguments: n ?? {} },
        void 0,
        { timeout: this.timeout },
      ),
      i = r.parse(o).content;
    return (
      this.debugLog(
        () =>
          `Called tool ${e} (args: ${JSON.stringify(n)}, result: ${JSON.stringify(i)})`,
      ),
      i
    );
  }
  get name() {
    return this._name;
  }
  async close() {
    (this.transport && (await this.transport.close(), (this.transport = null)),
      this.session && (await this.session.close(), (this.session = null)));
  }
}
class Ou extends Ii {
  session = null;
  _cacheDirty = !0;
  _toolsList = [];
  serverInitializeResult = null;
  clientSessionTimeoutSeconds;
  timeout;
  params;
  _name;
  transport = null;
  constructor(e) {
    (super(e),
      (this.clientSessionTimeoutSeconds = e.clientSessionTimeoutSeconds ?? 5),
      (this.params = e),
      (this._name = e.name || `sse: ${this.params.url}`),
      (this.timeout = e.timeout ?? sn));
  }
  async connect() {
    try {
      const { SSEClientTransport: e } =
          await import("./sse-l3DRQviM.mjs").catch(fe),
        { Client: n } = await import("./index-BpO2rBmi.mjs").catch(fe);
      ((this.transport = new e(new URL(this.params.url), {
        authProvider: this.params.authProvider,
        requestInit: this.params.requestInit,
        eventSourceInit: this.params.eventSourceInit,
      })),
        (this.session = new n({ name: this._name, version: "1.0.0" })),
        await this.session.connect(this.transport),
        (this.serverInitializeResult = {
          serverInfo: { name: this._name, version: "1.0.0" },
        }));
    } catch (e) {
      throw (
        this.logger.error("Error initializing MCP server:", e),
        await this.close(),
        e
      );
    }
    this.debugLog(() => `Connected to MCP server: ${this._name}`);
  }
  async invalidateToolsCache() {
    (await cn(this.name), (this._cacheDirty = !0));
  }
  async listTools() {
    const { ListToolsResultSchema: e } = await Promise.resolve()
      .then(() => Ze)
      .catch(fe);
    if (!this.session)
      throw new Error(
        "Server not initialized. Make sure you call connect() first.",
      );
    if (this.cacheToolsList && !this._cacheDirty && this._toolsList)
      return this._toolsList;
    this._cacheDirty = !1;
    const n = await this.session.listTools();
    return (
      this.debugLog(() => `Listed tools: ${JSON.stringify(n)}`),
      (this._toolsList = e.parse(n).tools),
      this._toolsList
    );
  }
  async callTool(e, n) {
    const { CallToolResultSchema: r } = await Promise.resolve()
      .then(() => Ze)
      .catch(fe);
    if (!this.session)
      throw new Error(
        "Server not initialized. Make sure you call connect() first.",
      );
    const o = await this.session.callTool(
        { name: e, arguments: n ?? {} },
        void 0,
        { timeout: this.timeout },
      ),
      i = r.parse(o).content;
    return (
      this.debugLog(
        () =>
          `Called tool ${e} (args: ${JSON.stringify(n)}, result: ${JSON.stringify(i)})`,
      ),
      i
    );
  }
  get name() {
    return this._name;
  }
  async close() {
    (this.transport && (await this.transport.close(), (this.transport = null)),
      this.session && (await this.session.close(), (this.session = null)));
  }
}
class Ru extends xi {
  session = null;
  _cacheDirty = !0;
  _toolsList = [];
  serverInitializeResult = null;
  clientSessionTimeoutSeconds;
  timeout;
  params;
  _name;
  transport = null;
  constructor(e) {
    (super(e),
      (this.clientSessionTimeoutSeconds = e.clientSessionTimeoutSeconds ?? 5),
      (this.params = e),
      (this._name = e.name || `streamable-http: ${this.params.url}`),
      (this.timeout = e.timeout ?? sn));
  }
  async connect() {
    try {
      const { StreamableHTTPClientTransport: e } =
          await import("./streamableHttp-C2-F8Eo0.mjs").catch(fe),
        { Client: n } = await import("./index-BpO2rBmi.mjs").catch(fe);
      ((this.transport = new e(new URL(this.params.url), {
        authProvider: this.params.authProvider,
        requestInit: this.params.requestInit,
        fetch: this.params.fetch,
        reconnectionOptions: this.params.reconnectionOptions,
        sessionId: this.params.sessionId,
      })),
        (this.session = new n({ name: this._name, version: "1.0.0" })),
        await this.session.connect(this.transport),
        (this.serverInitializeResult = {
          serverInfo: { name: this._name, version: "1.0.0" },
        }));
    } catch (e) {
      throw (
        this.logger.error("Error initializing MCP server:", e),
        await this.close(),
        e
      );
    }
    this.debugLog(() => `Connected to MCP server: ${this._name}`);
  }
  async invalidateToolsCache() {
    (await cn(this.name), (this._cacheDirty = !0));
  }
  async listTools() {
    const { ListToolsResultSchema: e } = await Promise.resolve()
      .then(() => Ze)
      .catch(fe);
    if (!this.session)
      throw new Error(
        "Server not initialized. Make sure you call connect() first.",
      );
    if (this.cacheToolsList && !this._cacheDirty && this._toolsList)
      return this._toolsList;
    this._cacheDirty = !1;
    const n = await this.session.listTools();
    return (
      this.debugLog(() => `Listed tools: ${JSON.stringify(n)}`),
      (this._toolsList = e.parse(n).tools),
      this._toolsList
    );
  }
  async callTool(e, n) {
    const { CallToolResultSchema: r } = await Promise.resolve()
      .then(() => Ze)
      .catch(fe);
    if (!this.session)
      throw new Error(
        "Server not initialized. Make sure you call connect() first.",
      );
    const o = await this.session.callTool(
        { name: e, arguments: n ?? {} },
        void 0,
        { timeout: this.timeout },
      ),
      i = r.parse(o).content;
    return (
      this.debugLog(
        () =>
          `Called tool ${e} (args: ${JSON.stringify(n)}, result: ${JSON.stringify(i)})`,
      ),
      i
    );
  }
  get name() {
    return this._name;
  }
  async close() {
    (this.transport && (await this.transport.close(), (this.transport = null)),
      this.session && (await this.session.close(), (this.session = null)));
  }
}
function Ir() {
  if (typeof xn > "u" || typeof xn.env > "u") {
    try {
      const t = (0, eval)("import.meta");
      if (typeof t == "object" && typeof t.env == "object") return t.env;
    } catch {}
    return {};
  }
  return xn.env;
}
class ku {
  constructor() {}
  setTimeout(e, n) {
    return setTimeout(e, n);
  }
  clearTimeout(e) {
    clearTimeout(e);
  }
}
const Nu = new ku();
class Er {
  on(e, n) {
    return (this.eventEmitter.on(e, n), this.eventEmitter);
  }
  off(e, n) {
    return (this.eventEmitter.off(e, n), this.eventEmitter);
  }
  emit(e, ...n) {
    return this.eventEmitter.emit(e, ...n);
  }
  once(e, n) {
    return (this.eventEmitter.once(e, n), this.eventEmitter);
  }
}
class Ci extends Er {
  eventEmitter = new wt();
}
class Lu extends Er {
  eventEmitter = new wt();
}
const Ai = "OPENAI_DEFAULT_MODEL";
function Dt(t) {
  return t.startsWith("gpt-5-chat") ? !1 : t.startsWith("gpt-5");
}
function Cr() {
  return Dt(un());
}
function un() {
  return xr()[Ai]?.toLowerCase() ?? "gpt-4.1";
}
function Di(t) {
  const e = t ?? un();
  return Dt(e)
    ? { reasoning: { effort: "low" }, text: { verbosity: "low" } }
    : {};
}
function Ar(t) {
  return JSON.stringify({ assistant: t.name });
}
function Pu(t) {
  return `transfer_to_${Wt(t.name)}`;
}
function Mu(t) {
  return `Handoff to the ${t.name} agent to handle the request. ${t.handoffDescription ?? ""}`;
}
class Dr {
  toolName;
  toolDescription;
  inputJsonSchema = {
    type: "object",
    properties: {},
    required: [],
    additionalProperties: !1,
  };
  strictJsonSchema = !0;
  onInvokeHandoff;
  agentName;
  inputFilter;
  agent;
  getHandoffAsFunctionTool() {
    return {
      type: "function",
      name: this.toolName,
      description: this.toolDescription,
      parameters: this.inputJsonSchema,
      strict: this.strictJsonSchema,
    };
  }
  isEnabled = async () => !0;
  constructor(e, n) {
    ((this.agentName = e.name),
      (this.onInvokeHandoff = n),
      (this.toolName = Pu(e)),
      (this.toolDescription = Mu(e)),
      (this.agent = e));
  }
}
function Or(t, e = {}) {
  let n;
  const r = !!e.onHandoff,
    o = !!e.inputType;
  if (!(r === o))
    throw new G(
      "You must provide either both `onHandoff` and `inputType` or neither.",
    );
  async function i(u, l) {
    if (n) {
      if (!l)
        throw (
          Ye({
            message: `Handoff function expected non empty input but got: ${l}`,
            data: { details: "input is empty" },
          }),
          new ae("Handoff function expected non empty input")
        );
      try {
        const d = await n(l);
        e.onHandoff && (await e.onHandoff(u, d));
      } catch (d) {
        throw (
          Ye({ message: "Invalid JSON provided", data: {} }),
          P.dontLogToolData ||
            P.error(`Invalid JSON when parsing: ${l}. Error: ${d}`),
          new ae("Invalid JSON provided")
        );
      }
    } else await e.onHandoff?.(u);
    return t;
  }
  const c = new Dr(t, i);
  if (typeof e.isEnabled == "function") {
    const u = e.isEnabled;
    c.isEnabled = async ({ runContext: l, agent: d }) =>
      !!(await u({ runContext: l, agent: d }));
  } else
    typeof e.isEnabled == "boolean" && (c.isEnabled = async () => e.isEnabled);
  if (e.inputType) {
    const u = br(e.inputType, c.toolName);
    ((c.inputJsonSchema = u.schema), (c.strictJsonSchema = !0), (n = u.parser));
  }
  return (
    e.toolNameOverride && (c.toolName = e.toolNameOverride),
    e.toolDescriptionOverride &&
      (c.toolDescription = e.toolDescriptionOverride),
    e.inputFilter && (c.inputFilter = e.inputFilter),
    c
  );
}
function Oi(t) {
  return t instanceof Dr ? t : Or(t);
}
function Ri(t) {
  if (t.type !== "message" || t.role !== "assistant") return;
  const e = t.content[t.content.length - 1];
  if (e.type === "output_text") return e.text;
}
function Fu(t) {
  return t.output.length === 0 ? "" : Ri(t.output[t.output.length - 1]) || "";
}
const Vn = new WeakMap();
function Uu(t, e) {
  t && Vn.set(t, e);
}
function $u(t) {
  const e = Vn.get(t);
  return (e && Vn.delete(t), e);
}
const Bu = h({ input: a() });
class Se extends Ci {
  static create(e) {
    return new Se({
      ...e,
      handoffs: e.handoffs,
      outputType: e.outputType,
      handoffOutputTypeWarningEnabled: !1,
    });
  }
  static DEFAULT_MODEL_PLACEHOLDER = "";
  name;
  instructions;
  prompt;
  handoffDescription;
  handoffs;
  model;
  modelSettings;
  tools;
  mcpServers;
  inputGuardrails;
  outputGuardrails;
  outputType = "text";
  toolUseBehavior;
  resetToolChoice;
  constructor(e) {
    if ((super(), typeof e.name != "string" || e.name.trim() === ""))
      throw new G("Agent must have a name.");
    if (
      ((this.name = e.name),
      (this.instructions = e.instructions ?? Se.DEFAULT_MODEL_PLACEHOLDER),
      (this.prompt = e.prompt),
      (this.handoffDescription = e.handoffDescription ?? ""),
      (this.handoffs = e.handoffs ?? []),
      (this.model = e.model ?? ""),
      (this.modelSettings = e.modelSettings ?? Di()),
      (this.tools = e.tools ?? []),
      (this.mcpServers = e.mcpServers ?? []),
      (this.inputGuardrails = e.inputGuardrails ?? []),
      (this.outputGuardrails = e.outputGuardrails ?? []),
      e.outputType && (this.outputType = e.outputType),
      (this.toolUseBehavior = e.toolUseBehavior ?? "run_llm_again"),
      (this.resetToolChoice = e.resetToolChoice ?? !0),
      e.model !== void 0 &&
        Cr() &&
        (typeof e.model != "string" || !Dt(e.model)) &&
        e.modelSettings === void 0 &&
        (this.modelSettings = {}),
      (e.handoffOutputTypeWarningEnabled === void 0 ||
        e.handoffOutputTypeWarningEnabled) &&
        this.handoffs &&
        this.outputType)
    ) {
      const n = new Set([JSON.stringify(this.outputType)]);
      for (const r of this.handoffs)
        "outputType" in r && r.outputType
          ? n.add(JSON.stringify(r.outputType))
          : "agent" in r &&
            r.agent.outputType &&
            n.add(JSON.stringify(r.agent.outputType));
      n.size > 1 &&
        P.warn(
          `[Agent] Warning: Handoff agents have different output types: ${Array.from(n).join(", ")}. You can make it type-safe by using Agent.create({ ... }) method instead.`,
        );
    }
  }
  get outputSchemaName() {
    if (this.outputType === "text") return "text";
    if ($e(this.outputType)) return "ZodOutput";
    if (typeof this.outputType == "object") return this.outputType.name;
    throw new Error(`Unknown output type: ${this.outputType}`);
  }
  clone(e) {
    return new Se({ ...this, ...e });
  }
  asTool(e) {
    const {
      toolName: n,
      toolDescription: r,
      customOutputExtractor: o,
      needsApproval: s,
      runConfig: i,
      runOptions: c,
      isEnabled: u,
    } = e;
    return yt({
      name: n ?? Wt(this.name),
      description: r ?? "",
      parameters: Bu,
      strict: !0,
      needsApproval: s,
      isEnabled: u,
      execute: async (l, d, g) => {
        if (!Jc(l)) throw new ae("Agent tool called with invalid input");
        const _ = await new jr(i ?? {}).run(this, l.input, {
            context: d,
            ...(c ?? {}),
          }),
          w =
            typeof this.toolUseBehavior == "object" &&
            this.toolUseBehavior !== null &&
            "stopAtToolNames" in this.toolUseBehavior;
        typeof o != "function" &&
          w &&
          P.debug(
            `You're passing the agent (name: ${this.name}) with toolUseBehavior.stopAtToolNames configured as a tool to a different agent; this may not work as you expect. You may want to have a wrapper function tool to consistently return the final output.`,
          );
        const E =
          typeof o == "function"
            ? await o(_)
            : Fu(_.rawResponses[_.rawResponses.length - 1]);
        return (g?.toolCall && Uu(g.toolCall, _), E);
      },
    });
  }
  async getSystemPrompt(e) {
    return typeof this.instructions == "function"
      ? await this.instructions(e, this)
      : this.instructions;
  }
  async getPrompt(e) {
    return typeof this.prompt == "function"
      ? await this.prompt(e, this)
      : this.prompt;
  }
  async getMcpTools(e) {
    return this.mcpServers.length > 0
      ? Ei({
          mcpServers: this.mcpServers,
          runContext: e,
          agent: this,
          convertSchemasToStrict: !1,
        })
      : [];
  }
  async getAllTools(e) {
    const n = await this.getMcpTools(e),
      r = [];
    for (const o of this.tools) {
      if (o.type === "function") {
        const s = o.isEnabled;
        if (
          !(typeof s == "function"
            ? await s(e, this)
            : typeof s == "boolean"
              ? s
              : !0)
        )
          continue;
      }
      r.push(o);
    }
    return [...n, ...r];
  }
  async getEnabledHandoffs(e) {
    const n = this.handoffs?.map((o) => Oi(o)) ?? [],
      r = [];
    for (const o of n)
      (await o.isEnabled({ runContext: e, agent: this })) && r.push(o);
    return r;
  }
  processFinalOutput(e) {
    if (this.outputType === "text") return e;
    if (typeof this.outputType == "object") {
      const n = JSON.parse(e);
      return $e(this.outputType) ? this.outputType.parse(n) : n;
    }
    throw new Error(`Unknown output type: ${this.outputType}`);
  }
  toJSON() {
    return { name: this.name };
  }
}
function fs({ name: t, execute: e }) {
  return {
    type: "input",
    name: t,
    guardrailFunction: e,
    async run(n) {
      return { guardrail: { type: "input", name: t }, output: await e(n) };
    },
  };
}
function zt({ name: t, execute: e }) {
  return {
    type: "output",
    name: t,
    guardrailFunction: e,
    async run(n) {
      return {
        guardrail: { type: "output", name: t },
        agent: n.agent,
        agentOutput: n.agentOutput,
        output: await e(n),
      };
    },
  };
}
let Kn;
function ki(t) {
  Kn = t;
}
function ju() {
  if (typeof Kn > "u")
    throw new Error(
      "No default model provider set. Make sure to set a provider using setDefaultModelProvider before calling getDefaultModelProvider or pass an explicit provider.",
    );
  return Kn;
}
const Q = h({ providerData: Y(a(), j()).optional() }),
  ke = Q.extend({ id: a().optional() }),
  Ni = Q.extend({ type: y("refusal"), refusal: a() }),
  Li = Q.extend({ type: y("output_text"), text: a() }),
  ln = Q.extend({ type: y("input_text"), text: a() }),
  Pi = Q.extend({ type: y("reasoning_text"), text: a() }),
  Rr = Q.extend({
    type: y("input_image"),
    image: a()
      .or(h({ id: a().describe("OpenAI file ID") }))
      .describe(
        "Either base64 encoded image data, a data URL, or an object with a file ID.",
      )
      .optional(),
    detail: a().optional(),
  }),
  kr = Q.extend({
    type: y("input_file"),
    file: a()
      .describe(
        "Either base64 encoded file data or a publicly accessible file URL",
      )
      .or(h({ id: a().describe("OpenAI file ID") }))
      .or(h({ url: a().describe("Publicly accessible file URL") }))
      .describe("Contents of the file or an object with a file ID.")
      .optional(),
    filename: a().optional(),
  }),
  Nr = Q.extend({
    type: y("audio"),
    audio: a()
      .or(h({ id: a() }))
      .describe("Base64 encoded audio data or file id"),
    format: a().nullable().optional(),
    transcript: a().nullable().optional(),
  }),
  Mi = Q.extend({
    type: y("image"),
    image: a().describe("Base64 encoded image data"),
  }),
  Fi = Q.extend({ type: y("text"), text: a() }),
  qu = h({
    data: Z([a(), no(Uint8Array)]).describe(
      "Base64 image data, or raw bytes that will be base64 encoded automatically.",
    ),
    mediaType: a().optional(),
  }),
  Gu = h({
    url: a().describe("Publicly accessible URL pointing to the image content"),
  }),
  Ju = h({
    fileId: a().describe("OpenAI file ID referencing uploaded image content"),
  }),
  Hu = Z([qu, Gu, Ju]).describe(
    "Inline image data or references to uploaded content.",
  ),
  Wu = h({
    data: Z([a(), no(Uint8Array)]).describe(
      "Base64 encoded file data, or raw bytes that will be encoded automatically.",
    ),
    mediaType: a().describe("IANA media type describing the file contents"),
    filename: a().describe("Filename associated with the inline data"),
  }),
  zu = h({
    url: a().describe("Publicly accessible URL for the file content"),
    filename: a().optional(),
  }),
  Vu = h({
    id: a().describe("OpenAI file ID referencing uploaded content"),
    filename: a().optional(),
  }),
  Ku = Z([
    a().describe("Existing data URL or base64 string"),
    Wu,
    zu,
    Vu,
  ]).describe(
    "Inline data (with metadata) or references pointing to file contents.",
  ),
  Yu = (...t) => a(),
  Ui = Q.extend({
    type: y("image"),
    image: a().or(Hu).optional(),
    detail: Yu("low", "high", "auto").optional(),
  }),
  $i = Q.extend({ type: y("file"), file: Ku }),
  Bi = Q.extend({
    type: y("computer_screenshot"),
    data: a().describe("Base64 encoded image data or URL"),
  }),
  ji = se("type", [
    h({ type: y("screenshot") }),
    h({
      type: y("click"),
      x: R(),
      y: R(),
      button: J(["left", "right", "wheel", "back", "forward"]),
    }),
    h({ type: y("double_click"), x: R(), y: R() }),
    h({ type: y("scroll"), x: R(), y: R(), scroll_x: R(), scroll_y: R() }),
    h({ type: y("type"), text: a() }),
    h({ type: y("wait") }),
    h({ type: y("move"), x: R(), y: R() }),
    h({ type: y("keypress"), keys: U(a()) }),
    h({ type: y("drag"), path: U(h({ x: R(), y: R() })) }),
  ]),
  qi = se("type", [Li, Ni, Nr, Mi]),
  Lr = ke.extend({ type: y("message").optional() }),
  Ot = Lr.extend({
    role: y("assistant"),
    status: J(["in_progress", "completed", "incomplete"]),
    content: U(qi),
  }),
  Gi = se("type", [ln, Rr, kr, Nr]),
  Pr = Lr.extend({ role: y("user"), content: U(Gi).or(a()) }),
  Ji = Lr.extend({ role: y("system"), content: a() }),
  Zu = se("role", [Ji, Ot, Pr]),
  Xe = ke.extend({
    type: y("hosted_tool_call"),
    name: a().describe("The name of the hosted tool"),
    arguments: a().describe("The arguments of the hosted tool call").optional(),
    status: a().optional(),
    output: a().optional(),
  }),
  Qe = ke.extend({
    type: y("function_call"),
    callId: a().describe("The ID of the tool call"),
    name: a().describe("The name of the function"),
    status: J(["in_progress", "completed", "incomplete"]).optional(),
    arguments: a(),
  }),
  Hi = se("type", [Fi, Ui, $i]),
  Wi = se("type", [ln, Rr, kr]),
  Vt = ke.extend({
    type: y("function_call_result"),
    name: a().describe("The name of the tool"),
    callId: a().describe("The ID of the tool call"),
    status: J(["in_progress", "completed", "incomplete"]),
    output: Z([a(), Hi, U(Wi)]).describe(
      "Output returned by the tool call. Supports plain strings, legacy ToolOutput items, or structured input_* items.",
    ),
  }),
  dn = ke.extend({
    type: y("computer_call"),
    callId: a().describe("The ID of the computer call"),
    status: J(["in_progress", "completed", "incomplete"]),
    action: ji,
  }),
  zi = ke.extend({
    type: y("computer_call_result"),
    callId: a().describe("The ID of the computer call"),
    output: Bi,
  }),
  Vi = se("type", [dn, Qe, Xe]),
  pn = Q.extend({
    id: a().optional(),
    type: y("reasoning"),
    content: U(ln),
    rawContent: U(Pi).optional(),
  }),
  Mr = ke.extend({ type: y("unknown") }),
  fn = se("type", [Ot, Xe, Qe, dn, pn, Mr]),
  Ki = Z([Pr, Ot, Ji, Xe, Qe, dn, Vt, zi, pn, Mr]),
  Yi = h({
    requests: R().optional(),
    inputTokens: R(),
    outputTokens: R(),
    totalTokens: R(),
    inputTokensDetails: Y(a(), R()).optional(),
    outputTokensDetails: Y(a(), R()).optional(),
  }),
  Fr = Q.extend({ type: y("output_text_delta"), delta: a() }),
  Zi = Q.extend({ type: y("response_started") }),
  Ur = Q.extend({
    type: y("response_done"),
    response: Q.extend({ id: a(), usage: Yi, output: U(fn) }),
  }),
  Xi = Q.extend({
    type: y("model"),
    event: j().describe("The event from the model"),
  }),
  Xu = se("type", [Fr, Ur, Zi, Xi]),
  Qu = Object.freeze(
    Object.defineProperty(
      {
        __proto__: null,
        AssistantContent: qi,
        AssistantMessageItem: Ot,
        AudioContent: Nr,
        ComputerCallResultItem: zi,
        ComputerToolOutput: Bi,
        ComputerUseCallItem: dn,
        FunctionCallItem: Qe,
        FunctionCallResultItem: Vt,
        HostedToolCallItem: Xe,
        ImageContent: Mi,
        InputFile: kr,
        InputImage: Rr,
        InputText: ln,
        ItemBase: ke,
        MessageItem: Zu,
        ModelItem: Ki,
        OutputModelItem: fn,
        OutputText: Li,
        ReasoningItem: pn,
        ReasoningText: Pi,
        Refusal: Ni,
        SharedBase: Q,
        StreamEvent: Xu,
        StreamEventGenericItem: Xi,
        StreamEventResponseCompleted: Ur,
        StreamEventResponseStarted: Zi,
        StreamEventTextStream: Fr,
        ToolCallItem: Vi,
        ToolCallOutputContent: Hi,
        ToolCallStructuredOutput: Wi,
        ToolOutputFileContent: $i,
        ToolOutputImage: Ui,
        ToolOutputText: Fi,
        UnknownItem: Mr,
        UsageData: Yi,
        UserContent: Gi,
        UserMessageItem: Pr,
        computerActions: ji,
      },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  );
class Re {
  requests;
  inputTokens;
  outputTokens;
  totalTokens;
  inputTokensDetails = [];
  outputTokensDetails = [];
  constructor(e) {
    if (typeof e > "u")
      ((this.requests = 0),
        (this.inputTokens = 0),
        (this.outputTokens = 0),
        (this.totalTokens = 0),
        (this.inputTokensDetails = []),
        (this.outputTokensDetails = []));
    else {
      ((this.requests = e?.requests ?? 1),
        (this.inputTokens = e?.inputTokens ?? e?.input_tokens ?? 0),
        (this.outputTokens = e?.outputTokens ?? e?.output_tokens ?? 0),
        (this.totalTokens = e?.totalTokens ?? e?.total_tokens ?? 0));
      const n = e?.inputTokensDetails ?? e?.input_tokens_details;
      this.inputTokensDetails = n ? [n] : [];
      const r = e?.outputTokensDetails ?? e?.output_tokens_details;
      this.outputTokensDetails = r ? [r] : [];
    }
  }
  add(e) {
    ((this.requests += e.requests),
      (this.inputTokens += e.inputTokens),
      (this.outputTokens += e.outputTokens),
      (this.totalTokens += e.totalTokens),
      e.inputTokensDetails &&
        this.inputTokensDetails.push(...e.inputTokensDetails),
      e.outputTokensDetails &&
        this.outputTokensDetails.push(...e.outputTokensDetails));
  }
}
class Fe {
  context;
  usage;
  #e;
  constructor(e = {}) {
    ((this.context = e), (this.usage = new Re()), (this.#e = new Map()));
  }
  _rebuildApprovals(e) {
    this.#e = new Map(Object.entries(e));
  }
  isToolApproved(e) {
    const { toolName: n, callId: r } = e,
      o = this.#e.get(n);
    if (o?.approved === !0 && o.rejected === !0)
      return (
        P.warn(
          "Tool is permanently approved and rejected at the same time. Approval takes precedence",
        ),
        !0
      );
    if (o?.approved === !0) return !0;
    if (o?.rejected === !0) return !1;
    const s = Array.isArray(o?.approved) ? o.approved.includes(r) : !1,
      i = Array.isArray(o?.rejected) ? o.rejected.includes(r) : !1;
    if (s && i)
      return (
        P.warn(
          `Tool call ${r} is both approved and rejected at the same time. Approval takes precedence`,
        ),
        !0
      );
    if (s) return !0;
    if (i) return !1;
  }
  approveTool(e, { alwaysApprove: n = !1 } = {}) {
    const r = e.rawItem.name;
    if (n) {
      this.#e.set(r, { approved: !0, rejected: [] });
      return;
    }
    const o = this.#e.get(r) ?? { approved: [], rejected: [] };
    if (Array.isArray(o.approved)) {
      const s = "callId" in e.rawItem ? e.rawItem.callId : e.rawItem.id;
      o.approved.push(s);
    }
    this.#e.set(r, o);
  }
  rejectTool(e, { alwaysReject: n = !1 } = {}) {
    const r = e.rawItem.name;
    if (n) {
      this.#e.set(r, { approved: !1, rejected: !0 });
      return;
    }
    const o = this.#e.get(r) ?? { approved: [], rejected: [] };
    if (Array.isArray(o.rejected)) {
      const s = "callId" in e.rawItem ? e.rawItem.callId : e.rawItem.id;
      o.rejected.push(s);
    }
    this.#e.set(r, o);
  }
  toJSON() {
    return {
      context: this.context,
      usage: this.usage,
      approvals: Object.fromEntries(this.#e.entries()),
    };
  }
}
function hs(t) {
  return t.type === "function"
    ? {
        type: "function",
        name: t.name,
        description: t.description,
        parameters: t.parameters,
        strict: t.strict,
      }
    : t.type === "computer"
      ? {
          type: "computer",
          name: t.name,
          environment: t.computer.environment,
          dimensions: t.computer.dimensions,
        }
      : { type: "hosted_tool", name: t.name, providerData: t.providerData };
}
function ms(t) {
  return {
    toolName: t.toolName,
    toolDescription: t.toolDescription,
    inputJsonSchema: t.inputJsonSchema,
    strictJsonSchema: t.strictJsonSchema,
  };
}
class qe {
  type = "base_item";
  rawItem;
  toJSON() {
    return { type: this.type, rawItem: this.rawItem };
  }
}
class Rt extends qe {
  rawItem;
  agent;
  type = "message_output_item";
  constructor(e, n) {
    (super(), (this.rawItem = e), (this.agent = n));
  }
  toJSON() {
    return { ...super.toJSON(), agent: this.agent.toJSON() };
  }
  get content() {
    let e = "";
    for (const n of this.rawItem.content)
      n.type === "output_text" && (e += n.text);
    return e;
  }
}
class De extends qe {
  rawItem;
  agent;
  type = "tool_call_item";
  constructor(e, n) {
    (super(), (this.rawItem = e), (this.agent = n));
  }
  toJSON() {
    return { ...super.toJSON(), agent: this.agent.toJSON() };
  }
}
class Be extends qe {
  rawItem;
  agent;
  output;
  type = "tool_call_output_item";
  constructor(e, n, r) {
    (super(), (this.rawItem = e), (this.agent = n), (this.output = r));
  }
  toJSON() {
    return {
      ...super.toJSON(),
      agent: this.agent.toJSON(),
      output: Oe(this.output),
    };
  }
}
class hn extends qe {
  rawItem;
  agent;
  type = "reasoning_item";
  constructor(e, n) {
    (super(), (this.rawItem = e), (this.agent = n));
  }
  toJSON() {
    return { ...super.toJSON(), agent: this.agent.toJSON() };
  }
}
class mn extends qe {
  rawItem;
  agent;
  type = "handoff_call_item";
  constructor(e, n) {
    (super(), (this.rawItem = e), (this.agent = n));
  }
  toJSON() {
    return { ...super.toJSON(), agent: this.agent.toJSON() };
  }
}
class _n extends qe {
  rawItem;
  sourceAgent;
  targetAgent;
  type = "handoff_output_item";
  constructor(e, n, r) {
    (super(),
      (this.rawItem = e),
      (this.sourceAgent = n),
      (this.targetAgent = r));
  }
  toJSON() {
    return {
      ...super.toJSON(),
      sourceAgent: this.sourceAgent.toJSON(),
      targetAgent: this.targetAgent.toJSON(),
    };
  }
}
class ue extends qe {
  rawItem;
  agent;
  type = "tool_approval_item";
  constructor(e, n) {
    (super(), (this.rawItem = e), (this.agent = n));
  }
  toJSON() {
    return { ...super.toJSON(), agent: this.agent.toJSON() };
  }
}
function el(t) {
  return t
    .filter((e) => e.type === "message_output_item")
    .map((e) => e.content)
    .join("");
}
function ye(t) {
  return async (e, ...n) =>
    Qn(async () => {
      const r = t(...n);
      Ue(r);
      try {
        return (r.start(), await e(r));
      } catch (o) {
        throw (r.setError({ message: o.message, data: o.data }), o);
      } finally {
        (r.end(), Ae());
      }
    });
}
function $r(t, e) {
  return (
    (t = {}),
    ee().createSpan({ ...t, data: { type: "response", ...t.data } }, e)
  );
}
const Qi = ye($r);
function Kt(t, e) {
  return ee().createSpan(
    {
      ...t,
      data: { type: "agent", name: t?.data?.name ?? "Agent", ...t?.data },
    },
    e,
  );
}
const tl = ye(Kt);
function ea(t, e) {
  return ee().createSpan(
    {
      ...t,
      data: {
        type: "function",
        input: t?.data?.input ?? "",
        output: t?.data?.output ?? "",
        ...t?.data,
      },
    },
    e,
  );
}
const Yn = ye(ea);
function ta(t, e) {
  return ee().createSpan({ ...t, data: { type: "handoff", ...t?.data } }, e);
}
const na = ye(ta);
function Br(t, e) {
  return ee().createSpan({ ...t, data: { type: "generation", ...t?.data } }, e);
}
const ra = ye(Br);
function sa(t, e) {
  return ee().createSpan(
    { ...t, data: { type: "custom", data: {}, ...t?.data } },
    e,
  );
}
const nl = ye(sa);
function oa(t, e) {
  return ee().createSpan(
    { ...t, data: { type: "guardrail", triggered: !1, ...t?.data } },
    e,
  );
}
const Zn = ye(oa);
function ia(t, e) {
  return ee().createSpan(
    { ...t, data: { type: "transcription", ...t.data } },
    e,
  );
}
const rl = ye(ia);
function aa(t, e) {
  return ee().createSpan({ ...t, data: { type: "speech", ...t.data } }, e);
}
const sl = ye(aa);
function ca(t, e) {
  return ee().createSpan(
    { ...t, data: { type: "speech_group", ...t?.data } },
    e,
  );
}
const ol = ye(ca);
function ua(t, e) {
  return ee().createSpan({ ...t, data: { type: "mcp_tools", ...t?.data } }, e);
}
const la = ye(ua);
function vt(t) {
  if (t.length === 0) return "";
  const e =
    typeof globalThis < "u" && globalThis.Buffer ? globalThis.Buffer : void 0;
  if (e) return e.from(t).toString("base64");
  let n = "";
  for (let i = 0; i < t.length; i += 1) n += String.fromCharCode(t[i]);
  if (typeof globalThis.btoa == "function") return globalThis.btoa(n);
  const r = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
  let o = "",
    s = 0;
  for (; s < n.length;) {
    const i = n.charCodeAt(s++),
      c = n.charCodeAt(s++),
      u = n.charCodeAt(s++),
      l = i >> 2,
      d = ((i & 3) << 4) | (c >> 4),
      g = isNaN(c) ? 64 : ((c & 15) << 2) | (u >> 6),
      f = isNaN(u) ? 64 : u & 63;
    o += r.charAt(l) + r.charAt(d) + r.charAt(g) + r.charAt(f);
  }
  return o;
}
class da {
  data;
  type = "raw_model_stream_event";
  constructor(e) {
    this.data = e;
  }
}
class pa {
  name;
  item;
  type = "run_item_stream_event";
  constructor(e, n) {
    ((this.name = e), (this.item = n));
  }
}
class fa {
  agent;
  type = "agent_updated_stream_event";
  constructor(e) {
    this.agent = e;
  }
}
function _s(t, e, n, r) {
  const o = [],
    s = [],
    i = [],
    c = [],
    u = [],
    l = [],
    d = new Map(r.map((_) => [_.toolName, _])),
    g = new Map(n.filter((_) => _.type === "function").map((_) => [_.name, _])),
    f = n.find((_) => _.type === "computer"),
    v = new Map(
      n
        .filter(
          (_) => _.type === "hosted_tool" && _.providerData?.type === "mcp",
        )
        .map((_) => _)
        .map((_) => [_.providerData.server_label, _]),
    );
  for (const _ of t.output) {
    if (_.type === "message") _.role === "assistant" && o.push(new Rt(_, e));
    else if (_.type === "hosted_tool_call") {
      o.push(new De(_, e));
      const E = _.name;
      if (
        (l.push(E),
        _.providerData?.type === "mcp_approval_request" ||
          _.name === "mcp_approval_request")
      ) {
        const b = _.providerData,
          I = b.server_label,
          O = v.get(I);
        if (typeof O > "u") {
          const p = `MCP server (${I}) not found in Agent (${e.name})`;
          throw (Ye({ message: p, data: { mcp_server_label: I } }), new ae(p));
        }
        const C = new ue(
          {
            type: "hosted_tool_call",
            name: b.name,
            id: b.id,
            status: "in_progress",
            providerData: b,
          },
          e,
        );
        (u.push({ requestItem: C, mcpTool: O }),
          O.providerData.on_approval || o.push(C));
      }
    } else if (_.type === "reasoning") o.push(new hn(_, e));
    else if (_.type === "computer_call") {
      if ((o.push(new De(_, e)), l.push("computer_use"), !f))
        throw (
          Ye({
            message: "Model produced computer action without a computer tool.",
            data: { agent_name: e.name },
          }),
          new ae("Model produced computer action without a computer tool.")
        );
      c.push({ toolCall: _, computer: f });
    }
    if (_.type !== "function_call") continue;
    l.push(_.name);
    const w = d.get(_.name);
    if (w) (o.push(new mn(_, e)), s.push({ toolCall: _, handoff: w }));
    else {
      const E = g.get(_.name);
      if (!E)
        throw (
          Ye({
            message: `Tool ${_.name} not found in agent ${e.name}.`,
            data: { tool_name: _.name, agent_name: e.name },
          }),
          new ae(`Tool ${_.name} not found in agent ${e.name}.`)
        );
      (o.push(new De(_, e)), i.push({ toolCall: _, tool: E }));
    }
  }
  return {
    newItems: o,
    handoffs: s,
    functions: i,
    computerActions: c,
    mcpApprovalRequests: u,
    toolsUsed: l,
    hasToolsOrApprovalsToRun() {
      return s.length > 0 || i.length > 0 || u.length > 0 || c.length > 0;
    },
  };
}
const il = se("type", [
  h({ type: y("next_step_handoff"), newAgent: j() }),
  h({ type: y("next_step_final_output"), output: a() }),
  h({ type: y("next_step_run_again") }),
  h({ type: y("next_step_interruption"), data: Y(a(), j()) }),
]);
class de {
  originalInput;
  modelResponse;
  preStepItems;
  newStepItems;
  nextStep;
  constructor(e, n, r, o, s) {
    ((this.originalInput = e),
      (this.modelResponse = n),
      (this.preStepItems = r),
      (this.newStepItems = o),
      (this.nextStep = s));
  }
  get generatedItems() {
    return this.preStepItems.concat(this.newStepItems);
  }
}
function gs(t, e, n) {
  return t.resetToolChoice && e.hasUsedTools(t)
    ? { ...n, toolChoice: void 0 }
    : n;
}
async function ys(t, e, n, r, o, s, i) {
  const c = n
      .filter(
        (_) =>
          _ instanceof ue &&
          "callId" in _.rawItem &&
          _.rawItem.type === "function_call",
      )
      .map((_) => _.rawItem.callId),
    u = o.functions.filter((_) => c.includes(_.toolCall.callId)),
    l = await ha(t, u, s, i),
    d = l.map((_) => _.runItem),
    g = o.mcpApprovalRequests.filter(
      (_) =>
        _.requestItem.type === "tool_approval_item" &&
        _.requestItem.rawItem.type === "hosted_tool_call" &&
        _.requestItem.rawItem.providerData?.type === "mcp_approval_request",
    );
  for (const _ of g) {
    const w = _.requestItem.rawItem.id,
      E = i._context.isToolApproved({
        toolName: _.requestItem.rawItem.name,
        callId: w,
      });
    if (typeof E < "u") {
      const b = { approve: E, approval_request_id: w, reason: void 0 };
      d.push(
        new De(
          {
            type: "hosted_tool_call",
            name: "mcp_approval_response",
            providerData: b,
          },
          t,
        ),
      );
    }
  }
  const f = await ma(t, l, i),
    v = n.filter((_) => !(_ instanceof ue));
  return f.isFinalOutput
    ? (s.emit("agent_end", i._context, t, f.finalOutput),
      t.emit("agent_end", i._context, f.finalOutput),
      new de(e, r, v, d, {
        type: "next_step_final_output",
        output: f.finalOutput,
      }))
    : f.isInterrupted
      ? new de(e, r, v, d, {
          type: "next_step_interruption",
          data: { interruptions: f.interruptions },
        })
      : new de(e, r, v, d, { type: "next_step_run_again" });
}
async function vs(t, e, n, r, o, s, i) {
  const c = n;
  let u = o.newItems;
  const [l, d] = await Promise.all([
    ha(t, o.functions, s, i),
    fl(t, o.computerActions, s, i._context),
  ]);
  if (
    ((u = u.concat(l.map((E) => E.runItem))),
    (u = u.concat(d)),
    o.mcpApprovalRequests.length > 0)
  )
    for (const E of o.mcpApprovalRequests) {
      const b = E.mcpTool.providerData,
        I = E.requestItem.rawItem.providerData;
      if (b.on_approval) {
        const O = await b.on_approval(i._context, E.requestItem),
          C = {
            approve: O.approve,
            approval_request_id: I.id,
            reason: O.reason,
          };
        u.push(
          new De(
            {
              type: "hosted_tool_call",
              name: "mcp_approval_response",
              providerData: C,
            },
            t,
          ),
        );
      } else {
        u.push(E.requestItem);
        const O = {
          type: "hosted_mcp_tool_approval",
          tool: E.mcpTool,
          runItem: new ue(
            {
              type: "hosted_tool_call",
              name: I.name,
              id: I.id,
              arguments: I.arguments,
              status: "in_progress",
              providerData: I,
            },
            t,
          ),
        };
        l.push(O);
      }
    }
  if (o.handoffs.length > 0)
    return await hl(t, e, c, u, r, o.handoffs, s, i._context);
  const g = await ma(t, l, i);
  if (g.isFinalOutput)
    return (
      s.emit("agent_end", i._context, t, g.finalOutput),
      t.emit("agent_end", i._context, g.finalOutput),
      new de(e, r, c, u, {
        type: "next_step_final_output",
        output: g.finalOutput,
      })
    );
  if (g.isInterrupted)
    return new de(e, r, c, u, {
      type: "next_step_interruption",
      data: { interruptions: g.interruptions },
    });
  if (
    (o.functions?.length ?? 0) > 0 ||
    (o.computerActions?.length ?? 0) > 0 ||
    (o.mcpApprovalRequests?.length ?? 0) > 0 ||
    (o.handoffs?.length ?? 0) > 0
  )
    return new de(e, r, c, u, { type: "next_step_run_again" });
  const v = u.filter((E) => E instanceof Rt),
    _ = v.length > 0 ? Ri(v[v.length - 1].rawItem) : void 0;
  if (typeof _ > "u")
    return new de(e, r, c, u, { type: "next_step_run_again" });
  if (!l.some((E) => E.runItem instanceof ue)) {
    if (t.outputType === "text")
      return new de(e, r, c, u, { type: "next_step_final_output", output: _ });
    if (t.outputType !== "text" && _) {
      const { parser: E } = br(t.outputType, "final_output"),
        [b] = await Tr(() => E(_));
      if (b)
        throw (
          Ye({ message: "Invalid output type", data: { error: String(b) } }),
          new ae("Invalid output type")
        );
      return new de(e, r, c, u, { type: "next_step_final_output", output: _ });
    }
  }
  return new de(e, r, c, u, { type: "next_step_run_again" });
}
function Yt(t, e) {
  const n = al(e);
  if (n) {
    const r = n.map(cl);
    return {
      type: "function_call_result",
      name: t.name,
      callId: t.callId,
      status: "completed",
      output: r,
    };
  }
  return {
    type: "function_call_result",
    name: t.name,
    callId: t.callId,
    status: "completed",
    output: { type: "text", text: Oe(e) },
  };
}
function al(t) {
  if (Array.isArray(t)) {
    const n = [];
    for (const r of t) {
      const o = Ss(r);
      if (!o) return null;
      n.push(o);
    }
    return n;
  }
  const e = Ss(t);
  return e ? [e] : null;
}
function Ss(t) {
  if (!Me(t)) return null;
  const e = t.type;
  if (e === "text" && typeof t.text == "string") {
    const n = { type: "text", text: t.text };
    return (Me(t.providerData) && (n.providerData = t.providerData), n);
  }
  if (e === "image") {
    const n = { type: "image" };
    let r, o;
    const s = re(t.mediaType) ? t.mediaType : void 0,
      i = t.image;
    if (typeof i == "string" && i.length > 0) r = i;
    else if (Me(i)) {
      const c = i,
        u = re(c.mediaType) ? c.mediaType : s;
      if (
        (re(c.url)
          ? (r = c.url)
          : (re(c.data) ||
              (c.data instanceof Uint8Array && c.data.length > 0)) &&
            (r = Ut(c.data, u)),
        !r)
      ) {
        const l = (re(c.fileId) && c.fileId) || (re(c.id) && c.id) || void 0;
        l && (o = l);
      }
    }
    if (
      (!r &&
        typeof t.imageUrl == "string" &&
        t.imageUrl.length > 0 &&
        (r = t.imageUrl),
      !o &&
        typeof t.fileId == "string" &&
        t.fileId.length > 0 &&
        (o = t.fileId),
      !r && typeof t.data == "string" && t.data.length > 0
        ? (r = s ? Ut(t.data, s) : t.data)
        : !r &&
          t.data instanceof Uint8Array &&
          t.data.length > 0 &&
          (r = Ut(t.data, s)),
      typeof t.detail == "string" &&
        t.detail.length > 0 &&
        (n.detail = t.detail),
      r)
    )
      n.image = r;
    else if (o) n.image = { fileId: o };
    else return null;
    return (Me(t.providerData) && (n.providerData = t.providerData), n);
  }
  if (e === "file") {
    const n = ul(t);
    if (!n) return null;
    const r = { type: "file", file: n };
    return (Me(t.providerData) && (r.providerData = t.providerData), r);
  }
  return null;
}
function cl(t) {
  if (t.type === "text") {
    const n = { type: "input_text", text: t.text };
    return (t.providerData && (n.providerData = t.providerData), n);
  }
  if (t.type === "image") {
    const n = { type: "input_image" };
    if (
      (typeof t.detail == "string" &&
        t.detail.length > 0 &&
        (n.detail = t.detail),
      typeof t.image == "string" && t.image.length > 0)
    )
      n.image = t.image;
    else if (Me(t.image)) {
      const r = t.image,
        o = re(r.mediaType) ? r.mediaType : void 0;
      if (re(r.url)) n.image = r.url;
      else if (re(r.data))
        n.image = o && !r.data.startsWith("data:") ? Ve(r.data, o) : r.data;
      else if (r.data instanceof Uint8Array && r.data.length > 0) {
        const s = vt(r.data);
        n.image = Ve(s, o);
      } else {
        const s = (re(r.fileId) && r.fileId) || (re(r.id) && r.id) || void 0;
        s && (n.image = { id: s });
      }
    }
    return (t.providerData && (n.providerData = t.providerData), n);
  }
  if (t.type === "file") {
    const n = { type: "input_file" },
      r = t.file;
    if (typeof r == "string") n.file = r;
    else if (r && typeof r == "object") {
      const o = r;
      if ("data" in o && o.data) {
        const s = o.mediaType ?? "text/plain";
        if (typeof o.data == "string") n.file = Ve(o.data, s);
        else {
          const i = vt(o.data);
          n.file = Ve(i, s);
        }
      } else if (typeof o.url == "string" && o.url.length > 0)
        n.file = { url: o.url };
      else {
        const s =
          (typeof o.id == "string" && o.id.length > 0 && o.id) ||
          (typeof o.fileId == "string" && o.fileId.length > 0
            ? o.fileId
            : void 0);
        s && (n.file = { id: s });
      }
      typeof o.filename == "string" &&
        o.filename.length > 0 &&
        (n.filename = o.filename);
    }
    return (t.providerData && (n.providerData = t.providerData), n);
  }
  return t;
}
function ul(t) {
  const e = t.file;
  if (typeof e == "string" && e.length > 0) return e;
  const n = ll(e);
  if (n) return n;
  const r = dl(t);
  return r || null;
}
function ll(t) {
  if (!Me(t)) return null;
  if ("data" in t && t.data !== void 0) {
    const n = t.data,
      r = typeof n == "string" && n.length > 0,
      o = n instanceof Uint8Array && n.length > 0;
    return (!r && !o) || !re(t.mediaType) || !re(t.filename)
      ? null
      : {
          data: typeof n == "string" ? n : new Uint8Array(n),
          mediaType: t.mediaType,
          filename: t.filename,
        };
  }
  if (re(t.url)) {
    const n = { url: t.url };
    return (re(t.filename) && (n.filename = t.filename), n);
  }
  const e = (re(t.id) && t.id) || (re(t.fileId) && t.fileId);
  if (e) {
    const n = { id: e };
    return (re(t.filename) && (n.filename = t.filename), n);
  }
  return null;
}
function dl(t) {
  const e =
      typeof t.filename == "string" && t.filename.length > 0
        ? t.filename
        : void 0,
    n =
      typeof t.mediaType == "string" && t.mediaType.length > 0
        ? t.mediaType
        : void 0;
  if (typeof t.fileData == "string" && t.fileData.length > 0)
    return !n || !e ? null : { data: t.fileData, mediaType: n, filename: e };
  if (t.fileData instanceof Uint8Array && t.fileData.length > 0)
    return !n || !e
      ? null
      : { data: new Uint8Array(t.fileData), mediaType: n, filename: e };
  if (typeof t.fileUrl == "string" && t.fileUrl.length > 0) {
    const r = { url: t.fileUrl };
    return (e && (r.filename = e), r);
  }
  if (typeof t.fileId == "string" && t.fileId.length > 0) {
    const r = { id: t.fileId };
    return (e && (r.filename = e), r);
  }
  return null;
}
function Me(t) {
  return typeof t == "object" && t !== null;
}
function re(t) {
  return typeof t == "string" && t.length > 0;
}
function Ut(t, e) {
  if (typeof t == "string") return e && !t.startsWith("data:") ? Ve(t, e) : t;
  const n = vt(t);
  return Ve(n, e);
}
function Ve(t, e) {
  return e ? `data:${e};base64,${t}` : t;
}
async function ha(t, e, n, r) {
  async function o(s) {
    let i = s.toolCall.arguments;
    if (
      (s.tool.parameters &&
        ($e(s.tool.parameters)
          ? (i = s.tool.parameters.parse(i))
          : (i = JSON.parse(i))),
      await s.tool.needsApproval(r._context, i, s.toolCall.callId))
    ) {
      const u = r._context.isToolApproved({
        toolName: s.tool.name,
        callId: s.toolCall.callId,
      });
      if (u === !1)
        return Yn(
          async (l) => {
            const d = "Tool execution was not approved.";
            return (
              l.setError({
                message: d,
                data: {
                  tool_name: s.tool.name,
                  error: `Tool execution for ${s.toolCall.callId} was manually rejected by user.`,
                },
              }),
              (l.spanData.output = d),
              {
                type: "function_output",
                tool: s.tool,
                output: d,
                runItem: new Be(Yt(s.toolCall, d), t, d),
              }
            );
          },
          { data: { name: s.tool.name } },
        );
      if (u !== !0)
        return {
          type: "function_approval",
          tool: s.tool,
          runItem: new ue(s.toolCall, t),
        };
    }
    return Yn(
      async (u) => {
        n.config.traceIncludeSensitiveData &&
          (u.spanData.input = s.toolCall.arguments);
        try {
          (n.emit("agent_tool_start", r._context, t, s.tool, {
            toolCall: s.toolCall,
          }),
            t.emit("agent_tool_start", r._context, s.tool, {
              toolCall: s.toolCall,
            }));
          const l = await s.tool.invoke(r._context, s.toolCall.arguments, {
              toolCall: s.toolCall,
            }),
            d = Oe(l);
          (n.emit("agent_tool_end", r._context, t, s.tool, d, {
            toolCall: s.toolCall,
          }),
            t.emit("agent_tool_end", r._context, s.tool, d, {
              toolCall: s.toolCall,
            }),
            n.config.traceIncludeSensitiveData && (u.spanData.output = d));
          const g = {
              type: "function_output",
              tool: s.tool,
              output: l,
              runItem: new Be(Yt(s.toolCall, l), t, l),
            },
            f = $u(s.toolCall);
          if (f) {
            g.agentRunResult = f;
            const v = f.interruptions;
            v.length > 0 && (g.interruptions = v);
          }
          return g;
        } catch (l) {
          throw (
            u.setError({
              message: "Error running tool",
              data: { tool_name: s.tool.name, error: String(l) },
            }),
            l
          );
        }
      },
      { data: { name: s.tool.name } },
    );
  }
  try {
    return await Promise.all(e.map(o));
  } catch (s) {
    throw new pi(`Failed to run function tools: ${s}`, s, r);
  }
}
async function pl(t, e) {
  const n = e.action;
  let r;
  switch (n.type) {
    case "click":
      await t.click(n.x, n.y, n.button);
      break;
    case "double_click":
      await t.doubleClick(n.x, n.y);
      break;
    case "drag":
      await t.drag(n.path.map((o) => [o.x, o.y]));
      break;
    case "keypress":
      await t.keypress(n.keys);
      break;
    case "move":
      await t.move(n.x, n.y);
      break;
    case "screenshot":
      r = await t.screenshot();
      break;
    case "scroll":
      await t.scroll(n.x, n.y, n.scroll_x, n.scroll_y);
      break;
    case "type":
      await t.type(n.text);
      break;
    case "wait":
      await t.wait();
      break;
  }
  if (
    typeof r < "u" ||
    (typeof t.screenshot == "function" &&
      ((r = await t.screenshot()), typeof r < "u"))
  )
    return r;
  throw new Error("Computer does not implement screenshot()");
}
async function fl(t, e, n, r, o = void 0) {
  const s = o ?? P,
    i = [];
  for (const c of e) {
    const u = c.computer.computer,
      l = c.toolCall;
    (n.emit("agent_tool_start", r, t, c.computer, { toolCall: l }),
      typeof t.emit == "function" &&
        t.emit("agent_tool_start", r, c.computer, { toolCall: l }));
    let d;
    try {
      d = await pl(u, l);
    } catch (v) {
      (s.error("Failed to execute computer action:", v), (d = ""));
    }
    (n.emit("agent_tool_end", r, t, c.computer, d, { toolCall: l }),
      typeof t.emit == "function" &&
        t.emit("agent_tool_end", r, c.computer, d, { toolCall: l }));
    const g = d ? `data:image/png;base64,${d}` : "",
      f = {
        type: "computer_call_result",
        callId: l.callId,
        output: { type: "computer_screenshot", data: g },
      };
    i.push(new Be(f, t, g));
  }
  return i;
}
async function hl(t, e, n, r, o, s, i, c) {
  if (((r = [...r]), s.length === 0))
    return (
      P.warn(
        "Incorrectly called executeHandoffCalls with no handoffs. This should not happen. Moving on.",
      ),
      new de(e, o, n, r, { type: "next_step_run_again" })
    );
  if (s.length > 1) {
    const l = "Multiple handoffs detected, ignoring this one.";
    for (let d = 1; d < s.length; d++)
      r.push(new Be(Yt(s[d].toolCall, l), t, l));
  }
  const u = s[0];
  return na(
    async (l) => {
      const d = u.handoff,
        g = await d.onInvokeHandoff(c, u.toolCall.arguments);
      if (((l.spanData.to_agent = g.name), s.length > 1)) {
        const v = s.map((_) => _.handoff.agentName);
        l.setError({
          message: "Multiple handoffs requested",
          data: { requested_agents: v },
        });
      }
      (r.push(new _n(Yt(u.toolCall, Ar(g)), t, g)),
        i.emit("agent_handoff", c, t, g),
        t.emit("agent_handoff", c, g));
      const f = d.inputFilter ?? i.config.handoffInputFilter;
      if (f) {
        (P.debug("Filtering inputs for handoff"),
          typeof f != "function" &&
            l.setError({
              message: "Invalid input filter",
              data: { details: "not callable" },
            }));
        const v = {
            inputHistory: Array.isArray(e) ? [...e] : e,
            preHandoffItems: [...n],
            newItems: [...r],
            runContext: c,
          },
          _ = f(v);
        ((e = _.inputHistory), (n = _.preHandoffItems), (r = _.newItems));
      }
      return new de(e, o, n, r, { type: "next_step_handoff", newAgent: g });
    },
    { data: { from_agent: t.name } },
  );
}
const $t = { isFinalOutput: !1, isInterrupted: void 0 };
async function ma(t, e, n) {
  if (e.length === 0) return $t;
  const r = [];
  for (const i of e)
    if (
      (i.runItem instanceof ue && r.push(i.runItem),
      i.type === "function_output")
    ) {
      if (Array.isArray(i.interruptions)) r.push(...i.interruptions);
      else if (i.agentRunResult) {
        const c = i.agentRunResult.interruptions;
        c.length > 0 && r.push(...c);
      }
    }
  if (r.length > 0)
    return { isFinalOutput: !1, isInterrupted: !0, interruptions: r };
  if (t.toolUseBehavior === "run_llm_again") return $t;
  const o = e[0];
  if (t.toolUseBehavior === "stop_on_first_tool")
    return o?.type === "function_output"
      ? { isFinalOutput: !0, isInterrupted: void 0, finalOutput: Oe(o.output) }
      : $t;
  const s = t.toolUseBehavior;
  if (typeof s == "object") {
    const i = e.find((c) => s.stopAtToolNames.includes(c.tool.name));
    return i?.type === "function_output"
      ? { isFinalOutput: !0, isInterrupted: void 0, finalOutput: Oe(i.output) }
      : $t;
  }
  if (typeof s == "function") return s(n._context, e);
  throw new G(`Invalid toolUseBehavior: ${s}`, n);
}
function ml(t) {
  if (t instanceof Rt) return "message_output_created";
  if (t instanceof mn) return "handoff_requested";
  if (t instanceof _n) return "handoff_occurred";
  if (t instanceof De) return "tool_called";
  if (t instanceof Be) return "tool_output";
  if (t instanceof hn) return "reasoning_item_created";
  if (t instanceof ue) return "tool_approval_requested";
}
function _a(t, e) {
  const n = ml(e);
  if (!n) {
    P.warn("Unknown item type: ", e);
    return;
  }
  t._addItem(new pa(n, e));
}
function _l(t, e) {
  for (const n of e) _a(t, n);
}
function ws(t, e, n) {
  const r = n?.skipItems;
  for (const o of e.newStepItems) r?.has(o) || _a(t, o);
}
class Ts {
  #e = new Map();
  addToolUse(e, n) {
    this.#e.set(e, n);
  }
  hasUsedTools(e) {
    return this.#e.has(e);
  }
  toJSON() {
    return Object.fromEntries(
      Array.from(this.#e.entries()).map(([e, n]) => [e.name, n]),
    );
  }
}
const Gt = "1.0",
  gl = y(Gt),
  ve = h({ name: a() }),
  yl = h({
    object: y("trace.span"),
    id: a(),
    trace_id: a(),
    parent_id: a().nullable(),
    started_at: a().nullable(),
    ended_at: a().nullable(),
    error: h({ message: a(), data: Y(a(), j()).optional() }).nullable(),
    span_data: Y(a(), j()),
  }),
  ga = yl.extend({ previous_span: _c(() => ga).optional() }),
  ya = h({
    requests: R(),
    inputTokens: R(),
    outputTokens: R(),
    totalTokens: R(),
  }),
  bs = h({
    usage: ya,
    output: U(fn),
    responseId: a().optional(),
    providerData: Y(a(), j()).optional(),
  }),
  va = se("type", [
    h({ type: y("message_output_item"), rawItem: Ot, agent: ve }),
    h({ type: y("tool_call_item"), rawItem: Vi.or(Xe), agent: ve }),
    h({
      type: y("tool_call_output_item"),
      rawItem: Vt,
      agent: ve,
      output: a(),
    }),
    h({ type: y("reasoning_item"), rawItem: pn, agent: ve }),
    h({ type: y("handoff_call_item"), rawItem: Qe, agent: ve }),
    h({
      type: y("handoff_output_item"),
      rawItem: Vt,
      sourceAgent: ve,
      targetAgent: ve,
    }),
    h({ type: y("tool_approval_item"), rawItem: Qe.or(Xe), agent: ve }),
  ]),
  vl = h({
    object: y("trace"),
    id: a(),
    workflow_name: a(),
    group_id: a().nullable(),
    metadata: Y(a(), j()),
  }),
  Sl = h({
    newItems: U(va),
    toolsUsed: U(a()),
    handoffs: U(h({ toolCall: j(), handoff: j() })),
    functions: U(h({ toolCall: j(), tool: j() })),
    computerActions: U(h({ toolCall: j(), computer: j() })),
    mcpApprovalRequests: U(
      h({
        requestItem: h({
          rawItem: h({
            type: y("hosted_tool_call"),
            name: a(),
            arguments: a().optional(),
            status: a().optional(),
            output: a().optional(),
            providerData: Y(a(), j()).nullable().optional(),
          }),
        }),
        mcpTool: h({
          type: y("hosted_tool"),
          name: y("hosted_mcp"),
          providerData: Y(a(), j()),
        }),
      }),
    ).optional(),
  }),
  Sa = h({ tripwireTriggered: X(), outputInfo: j() }),
  wl = h({ guardrail: h({ type: y("input"), name: a() }), output: Sa }),
  Tl = h({
    guardrail: h({ type: y("output"), name: a() }),
    agentOutput: j(),
    agent: ve,
    output: Sa,
  }),
  xs = h({
    $schemaVersion: gl,
    currentTurn: R(),
    currentAgent: ve,
    originalInput: a().or(U(Ki)),
    modelResponses: U(bs),
    context: h({
      usage: ya,
      approvals: Y(
        a(),
        h({ approved: U(a()).or(X()), rejected: U(a()).or(X()) }),
      ),
      context: Y(a(), j()),
    }),
    toolUseTracker: Y(a(), U(a())),
    maxTurns: R(),
    currentAgentSpan: ga.nullable().optional(),
    noActiveAgentRun: X(),
    inputGuardrailResults: U(wl),
    outputGuardrailResults: U(Tl),
    currentStep: il.optional(),
    lastModelResponse: bs.optional(),
    generatedItems: U(va),
    lastProcessedResponse: Sl.optional(),
    trace: vl.nullable(),
  });
class Ce {
  _currentTurn = 0;
  _currentAgent;
  _originalInput;
  _modelResponses;
  _currentAgentSpan;
  _context;
  _toolUseTracker;
  _generatedItems;
  _maxTurns;
  _noActiveAgentRun = !0;
  _lastTurnResponse;
  _inputGuardrailResults;
  _outputGuardrailResults;
  _currentStep = void 0;
  _lastProcessedResponse = void 0;
  _trace = null;
  constructor(e, n, r, o) {
    ((this._context = e),
      (this._originalInput = structuredClone(n)),
      (this._modelResponses = []),
      (this._currentAgentSpan = void 0),
      (this._currentAgent = r),
      (this._toolUseTracker = new Ts()),
      (this._generatedItems = []),
      (this._maxTurns = o),
      (this._inputGuardrailResults = []),
      (this._outputGuardrailResults = []),
      (this._trace = et()));
  }
  get history() {
    return St(this._originalInput, this._generatedItems);
  }
  getInterruptions() {
    return this._currentStep?.type !== "next_step_interruption"
      ? []
      : this._currentStep.data.interruptions;
  }
  approve(e, n = { alwaysApprove: !1 }) {
    this._context.approveTool(e, n);
  }
  reject(e, n = { alwaysReject: !1 }) {
    this._context.rejectTool(e, n);
  }
  toJSON() {
    const e = {
        $schemaVersion: Gt,
        currentTurn: this._currentTurn,
        currentAgent: { name: this._currentAgent.name },
        originalInput: this._originalInput,
        modelResponses: this._modelResponses.map((r) => ({
          usage: {
            requests: r.usage.requests,
            inputTokens: r.usage.inputTokens,
            outputTokens: r.usage.outputTokens,
            totalTokens: r.usage.totalTokens,
          },
          output: r.output,
          responseId: r.responseId,
          providerData: r.providerData,
        })),
        context: this._context.toJSON(),
        toolUseTracker: this._toolUseTracker.toJSON(),
        maxTurns: this._maxTurns,
        currentAgentSpan: this._currentAgentSpan?.toJSON(),
        noActiveAgentRun: this._noActiveAgentRun,
        inputGuardrailResults: this._inputGuardrailResults,
        outputGuardrailResults: this._outputGuardrailResults.map((r) => ({
          ...r,
          agent: r.agent.toJSON(),
        })),
        currentStep: this._currentStep,
        lastModelResponse: this._lastTurnResponse,
        generatedItems: this._generatedItems.map((r) => r.toJSON()),
        lastProcessedResponse: this._lastProcessedResponse,
        trace: this._trace ? this._trace.toJSON() : null,
      },
      n = xs.safeParse(e);
    if (!n.success)
      throw new di(`Failed to serialize run state. ${n.error.message}`);
    return n.data;
  }
  toString() {
    return JSON.stringify(this.toJSON());
  }
  static async fromString(e, n) {
    const [r, o] = await Tr(() => JSON.parse(n));
    if (r)
      throw new G(
        `Failed to parse run state. ${r instanceof Error ? r.message : String(r)}`,
      );
    const s = o.$schemaVersion;
    if (!s) throw new G("Run state is missing schema version");
    if (s !== Gt)
      throw new G(
        `Run state schema version ${s} is not supported. Please use version ${Gt}`,
      );
    const i = xs.parse(JSON.parse(n)),
      c = bl(e),
      u = new Fe(i.context.context);
    u._rebuildApprovals(i.context.approvals);
    const l = c.get(i.currentAgent.name);
    if (!l) throw new G(`Agent ${i.currentAgent.name} not found`);
    const d = new Ce(u, "", l, i.maxTurns);
    ((d._currentTurn = i.currentTurn), (d._toolUseTracker = new Ts()));
    for (const [g, f] of Object.entries(i.toolUseTracker))
      d._toolUseTracker.addToolUse(c.get(g), f);
    if (i.currentAgentSpan) {
      i.trace || P.warn("Trace is not set, skipping tracing setup");
      const g = ee().createTrace({
        traceId: i.trace?.id,
        name: i.trace?.workflow_name,
        groupId: i.trace?.group_id ?? void 0,
        metadata: i.trace?.metadata,
      });
      ((d._currentAgentSpan = wa(g, i.currentAgentSpan)), (d._trace = g));
    }
    return (
      (d._noActiveAgentRun = i.noActiveAgentRun),
      (d._inputGuardrailResults = i.inputGuardrailResults),
      (d._outputGuardrailResults = i.outputGuardrailResults.map((g) => ({
        ...g,
        agent: c.get(g.agent.name),
      }))),
      (d._currentStep = i.currentStep),
      (d._originalInput = i.originalInput),
      (d._modelResponses = i.modelResponses.map(Is)),
      (d._lastTurnResponse = i.lastModelResponse
        ? Is(i.lastModelResponse)
        : void 0),
      (d._generatedItems = i.generatedItems.map((g) => Ta(g, c))),
      (d._lastProcessedResponse = i.lastProcessedResponse
        ? await xl(c, d._currentAgent, d._context, i.lastProcessedResponse)
        : void 0),
      i.currentStep?.type === "next_step_handoff" &&
        (d._currentStep = {
          type: "next_step_handoff",
          newAgent: c.get(i.currentStep.newAgent.name),
        }),
      d
    );
  }
}
function bl(t) {
  const e = new Map(),
    n = [t];
  for (; n.length > 0;) {
    const r = n.shift();
    if (!e.has(r.name)) {
      e.set(r.name, r);
      for (const o of r.handoffs)
        o instanceof Se
          ? e.has(o.name) || n.push(o)
          : o.agent && (e.has(o.agent.name) || n.push(o.agent));
    }
  }
  return e;
}
function wa(t, e) {
  const n = e.span_data,
    r = e.previous_span ? wa(t, e.previous_span) : void 0,
    o = ee().createSpan(
      {
        spanId: e.id,
        traceId: e.trace_id,
        parentId: e.parent_id ?? void 0,
        startedAt: e.started_at ?? void 0,
        endedAt: e.ended_at ?? void 0,
        data: n,
      },
      t,
    );
  return ((o.previousSpan = r), o);
}
function Is(t) {
  const e = new Re();
  return (
    (e.requests = t.usage.requests),
    (e.inputTokens = t.usage.inputTokens),
    (e.outputTokens = t.usage.outputTokens),
    (e.totalTokens = t.usage.totalTokens),
    {
      usage: e,
      output: t.output.map((n) => fn.parse(n)),
      responseId: t.responseId,
      providerData: t.providerData,
    }
  );
}
function Ta(t, e) {
  switch (t.type) {
    case "message_output_item":
      return new Rt(t.rawItem, e.get(t.agent.name));
    case "tool_call_item":
      return new De(t.rawItem, e.get(t.agent.name));
    case "tool_call_output_item":
      return new Be(t.rawItem, e.get(t.agent.name), t.output);
    case "reasoning_item":
      return new hn(t.rawItem, e.get(t.agent.name));
    case "handoff_call_item":
      return new mn(t.rawItem, e.get(t.agent.name));
    case "handoff_output_item":
      return new _n(
        t.rawItem,
        e.get(t.sourceAgent.name),
        e.get(t.targetAgent.name),
      );
    case "tool_approval_item":
      return new ue(t.rawItem, e.get(t.agent.name));
  }
}
async function xl(t, e, n, r) {
  const o = await e.getAllTools(n),
    s = new Map(o.filter((l) => l.type === "function").map((l) => [l.name, l])),
    i = new Map(o.filter((l) => l.type === "computer").map((l) => [l.name, l])),
    c = new Map(
      e.handoffs.map((l) =>
        l instanceof Se ? [l.name, Or(l)] : [l.toolName, l],
      ),
    ),
    u = {
      newItems: r.newItems.map((l) => Ta(l, t)),
      toolsUsed: r.toolsUsed,
      handoffs: r.handoffs.map((l) => {
        if (!c.has(l.handoff.toolName))
          throw new G(`Handoff ${l.handoff.toolName} not found`);
        return { toolCall: l.toolCall, handoff: c.get(l.handoff.toolName) };
      }),
      functions: await Promise.all(
        r.functions.map(async (l) => {
          if (!s.has(l.tool.name)) throw new G(`Tool ${l.tool.name} not found`);
          return { toolCall: l.toolCall, tool: s.get(l.tool.name) };
        }),
      ),
      computerActions: r.computerActions.map((l) => {
        const d = l.computer.name;
        if (!i.has(d)) throw new G(`Computer tool ${d} not found`);
        return { toolCall: l.toolCall, computer: i.get(d) };
      }),
      mcpApprovalRequests: (r.mcpApprovalRequests ?? []).map((l) => ({
        requestItem: new ue(l.requestItem.rawItem, e),
        mcpTool: l.mcpTool,
      })),
    };
  return {
    ...u,
    hasToolsOrApprovalsToRun() {
      return (
        u.handoffs.length > 0 ||
        u.functions.length > 0 ||
        u.mcpApprovalRequests.length > 0 ||
        u.computerActions.length > 0
      );
    },
  };
}
const Es = 10;
function Cs(t, e) {
  return t ? !1 : e ? !0 : "enabled_without_data";
}
function Xn(t) {
  return typeof t == "string"
    ? [{ type: "message", role: "user", content: t }]
    : [...t];
}
class As {
  conversationId;
  previousResponseId;
  sentInitialInput = !1;
  sentItems = new WeakSet();
  serverItems = new WeakSet();
  constructor({ conversationId: e, previousResponseId: n }) {
    ((this.conversationId = e ?? void 0),
      (this.previousResponseId = n ?? void 0));
  }
  primeFromState({ originalInput: e, generatedItems: n, modelResponses: r }) {
    if (this.sentInitialInput) return;
    for (const s of Xn(e)) s && typeof s == "object" && this.sentItems.add(s);
    this.sentInitialInput = !0;
    const o = r[r.length - 1];
    for (const s of r)
      for (const i of s.output)
        i && typeof i == "object" && this.serverItems.add(i);
    !this.conversationId &&
      o?.responseId &&
      (this.previousResponseId = o.responseId);
    for (const s of n) {
      const i = s.rawItem;
      !i ||
        typeof i != "object" ||
        (this.serverItems.has(i) && this.sentItems.add(i));
    }
  }
  trackServerItems(e) {
    if (e) {
      for (const n of e.output)
        n && typeof n == "object" && this.serverItems.add(n);
      !this.conversationId &&
        this.previousResponseId !== void 0 &&
        e.responseId &&
        (this.previousResponseId = e.responseId);
    }
  }
  prepareInput(e, n) {
    const r = [];
    if (!this.sentInitialInput) {
      const o = Xn(e);
      for (const s of o)
        (r.push(s), s && typeof s == "object" && this.sentItems.add(s));
      this.sentInitialInput = !0;
    }
    for (const o of n) {
      if (o.type === "tool_approval_item") continue;
      const s = o.rawItem;
      !s ||
        typeof s != "object" ||
        this.sentItems.has(s) ||
        this.serverItems.has(s) ||
        (r.push(s), this.sentItems.add(s));
    }
    return r;
  }
}
function St(t, e) {
  const n = e
    .filter((r) => r.type !== "tool_approval_item")
    .map((r) => r.rawItem);
  return [...Xn(t), ...n];
}
class jr extends Lu {
  config;
  inputGuardrailDefs;
  outputGuardrailDefs;
  constructor(e = {}) {
    (super(),
      (this.config = {
        modelProvider: e.modelProvider ?? ju(),
        model: e.model,
        modelSettings: e.modelSettings,
        handoffInputFilter: e.handoffInputFilter,
        inputGuardrails: e.inputGuardrails,
        outputGuardrails: e.outputGuardrails,
        tracingDisabled: e.tracingDisabled ?? !1,
        traceIncludeSensitiveData: e.traceIncludeSensitiveData ?? !0,
        workflowName: e.workflowName ?? "Agent workflow",
        traceId: e.traceId,
        groupId: e.groupId,
        traceMetadata: e.traceMetadata,
      }),
      (this.inputGuardrailDefs = (e.inputGuardrails ?? []).map(fs)),
      (this.outputGuardrailDefs = (e.outputGuardrails ?? []).map(zt)));
  }
  async #e(e, n, r) {
    return Qn(async () => {
      const o = n instanceof Ce,
        s = o
          ? n
          : new Ce(
              r.context instanceof Fe ? r.context : new Fe(r.context),
              n,
              e,
              r.maxTurns ?? Es,
            ),
        i =
          r.conversationId || r.previousResponseId
            ? new As({
                conversationId: r.conversationId,
                previousResponseId: r.previousResponseId,
              })
            : void 0;
      i &&
        o &&
        i.primeFromState({
          originalInput: s._originalInput,
          generatedItems: s._generatedItems,
          modelResponses: s._modelResponses,
        });
      try {
        for (;;) {
          const c =
            (s._currentAgent.model !== void 0 &&
              s._currentAgent.model !== "") ||
            (this.config.model !== void 0 && this.config.model !== "");
          let u = Ds(s._currentAgent.model, this.config.model);
          if (
            (typeof u == "string" &&
              (u = await this.config.modelProvider.getModel(u)),
            (s._currentStep = s._currentStep ?? {
              type: "next_step_run_again",
            }),
            s._currentStep.type === "next_step_interruption")
          ) {
            if (
              (P.debug("Continuing from interruption"),
              !s._lastTurnResponse || !s._lastProcessedResponse)
            )
              throw new G("No model response found in previous state", s);
            const l = await ys(
              s._currentAgent,
              s._originalInput,
              s._generatedItems,
              s._lastTurnResponse,
              s._lastProcessedResponse,
              this,
              s,
            );
            if (
              (s._toolUseTracker.addToolUse(
                s._currentAgent,
                s._lastProcessedResponse.toolsUsed,
              ),
              (s._originalInput = l.originalInput),
              (s._generatedItems = l.generatedItems),
              (s._currentStep = l.nextStep),
              l.nextStep.type === "next_step_interruption")
            )
              return new Jt(s);
            continue;
          }
          if (s._currentStep.type === "next_step_run_again") {
            const l = await s._currentAgent.getEnabledHandoffs(s._context);
            if (!s._currentAgentSpan) {
              const C = l.map((p) => p.agentName);
              ((s._currentAgentSpan = Kt({
                data: {
                  name: s._currentAgent.name,
                  handoffs: C,
                  output_type: s._currentAgent.outputSchemaName,
                },
              })),
                s._currentAgentSpan.start(),
                Ue(s._currentAgentSpan));
            }
            const d = await s._currentAgent.getAllTools(s._context),
              g = d.map((C) => hs(C)),
              f = l.map((C) => ms(C));
            if (
              (s._currentAgentSpan &&
                (s._currentAgentSpan.spanData.tools = d.map((C) => C.name)),
              s._currentTurn++,
              s._currentTurn > s._maxTurns)
            )
              throw (
                s._currentAgentSpan?.setError({
                  message: "Max turns exceeded",
                  data: { max_turns: s._maxTurns },
                }),
                new qn(`Max turns (${s._maxTurns}) exceeded`, s)
              );
            (P.debug(
              `Running agent ${s._currentAgent.name} (turn ${s._currentTurn})`,
            ),
              s._currentTurn === 1 && (await this.#t(s)));
            const v = i
              ? i.prepareInput(s._originalInput, s._generatedItems)
              : St(s._originalInput, s._generatedItems);
            s._noActiveAgentRun &&
              (s._currentAgent.emit("agent_start", s._context, s._currentAgent),
              this.emit("agent_start", s._context, s._currentAgent));
            let _ = {
              ...this.config.modelSettings,
              ...s._currentAgent.modelSettings,
            };
            const w = s._currentAgent.modelSettings;
            ((_ = Os(c, w, u, _)),
              (_ = gs(s._currentAgent, s._toolUseTracker, _)));
            const E = i?.previousResponseId ?? r.previousResponseId,
              b = i?.conversationId ?? r.conversationId;
            ((s._lastTurnResponse = await u.getResponse({
              systemInstructions: await s._currentAgent.getSystemPrompt(
                s._context,
              ),
              prompt: await s._currentAgent.getPrompt(s._context),
              ...(c ? { overridePromptModel: !0 } : {}),
              input: v,
              previousResponseId: E,
              conversationId: b,
              modelSettings: _,
              tools: g,
              outputType: as(s._currentAgent.outputType),
              handoffs: f,
              tracing: Cs(
                this.config.tracingDisabled,
                this.config.traceIncludeSensitiveData,
              ),
              signal: r.signal,
            })),
              s._modelResponses.push(s._lastTurnResponse),
              s._context.usage.add(s._lastTurnResponse.usage),
              (s._noActiveAgentRun = !1),
              i?.trackServerItems(s._lastTurnResponse));
            const I = _s(s._lastTurnResponse, s._currentAgent, d, l);
            s._lastProcessedResponse = I;
            const O = await vs(
              s._currentAgent,
              s._originalInput,
              s._generatedItems,
              s._lastTurnResponse,
              s._lastProcessedResponse,
              this,
              s,
            );
            (s._toolUseTracker.addToolUse(
              s._currentAgent,
              s._lastProcessedResponse.toolsUsed,
            ),
              (s._originalInput = O.originalInput),
              (s._generatedItems = O.generatedItems),
              (s._currentStep = O.nextStep));
          }
          if (
            s._currentStep &&
            s._currentStep.type === "next_step_final_output"
          )
            return (
              await this.#n(s, s._currentStep.output),
              this.emit(
                "agent_end",
                s._context,
                s._currentAgent,
                s._currentStep.output,
              ),
              s._currentAgent.emit(
                "agent_end",
                s._context,
                s._currentStep.output,
              ),
              new Jt(s)
            );
          if (s._currentStep && s._currentStep.type === "next_step_handoff")
            ((s._currentAgent = s._currentStep.newAgent),
              s._currentAgentSpan &&
                (s._currentAgentSpan.end(),
                Ae(),
                (s._currentAgentSpan = void 0)),
              (s._noActiveAgentRun = !0),
              (s._currentStep = { type: "next_step_run_again" }));
          else {
            if (
              s._currentStep &&
              s._currentStep.type === "next_step_interruption"
            )
              return new Jt(s);
            P.debug("Running next loop");
          }
        }
      } catch (c) {
        throw (
          s._currentAgentSpan &&
            s._currentAgentSpan.setError({
              message: "Error in agent run",
              data: { error: String(c) },
            }),
          c
        );
      } finally {
        s._currentAgentSpan &&
          (s._currentStep?.type !== "next_step_interruption" &&
            s._currentAgentSpan.end(),
          Ae());
      }
    });
  }
  async #t(e) {
    const n = this.inputGuardrailDefs.concat(
      e._currentAgent.inputGuardrails.map(fs),
    );
    if (n.length > 0) {
      const r = {
        agent: e._currentAgent,
        input: e._originalInput,
        context: e._context,
      };
      try {
        const o = await Promise.all(
          n.map(async (s) =>
            Zn(
              async (i) => {
                const c = await s.run(r);
                return ((i.spanData.triggered = c.output.tripwireTriggered), c);
              },
              { data: { name: s.name } },
              e._currentAgentSpan,
            ),
          ),
        );
        for (const s of o)
          if (s.output.tripwireTriggered)
            throw (
              e._currentAgentSpan &&
                e._currentAgentSpan.setError({
                  message: "Guardrail tripwire triggered",
                  data: { guardrail: s.guardrail.name },
                }),
              new Jn(
                `Input guardrail triggered: ${JSON.stringify(s.output.outputInfo)}`,
                s,
                e,
              )
            );
      } catch (o) {
        throw o instanceof Jn
          ? o
          : (e._currentTurn--,
            new Gn(`Input guardrail failed to complete: ${o}`, o, e));
      }
    }
  }
  async #n(e, n) {
    const r = this.outputGuardrailDefs.concat(
      e._currentAgent.outputGuardrails.map(zt),
    );
    if (r.length > 0) {
      const o = e._currentAgent.processFinalOutput(n),
        s = {
          agent: e._currentAgent,
          agentOutput: o,
          context: e._context,
          details: { modelResponse: e._lastTurnResponse },
        };
      try {
        const i = await Promise.all(
          r.map(async (c) =>
            Zn(
              async (u) => {
                const l = await c.run(s);
                return ((u.spanData.triggered = l.output.tripwireTriggered), l);
              },
              { data: { name: c.name } },
              e._currentAgentSpan,
            ),
          ),
        );
        for (const c of i)
          if (c.output.tripwireTriggered)
            throw (
              e._currentAgentSpan &&
                e._currentAgentSpan.setError({
                  message: "Guardrail tripwire triggered",
                  data: { guardrail: c.guardrail.name },
                }),
              new gt(
                `Output guardrail triggered: ${JSON.stringify(c.output.outputInfo)}`,
                c,
                e,
              )
            );
      } catch (i) {
        throw i instanceof gt
          ? i
          : new Gn(`Output guardrail failed to complete: ${i}`, i, e);
      }
    }
  }
  async #r(e, n, r) {
    const o =
      n.conversationId || n.previousResponseId
        ? new As({
            conversationId: n.conversationId,
            previousResponseId: n.previousResponseId,
          })
        : void 0;
    o &&
      r &&
      o.primeFromState({
        originalInput: e.state._originalInput,
        generatedItems: e.state._generatedItems,
        modelResponses: e.state._modelResponses,
      });
    try {
      for (;;) {
        const s = e.state._currentAgent,
          i = await s.getEnabledHandoffs(e.state._context),
          c = await s.getAllTools(e.state._context),
          u = c.map((d) => hs(d)),
          l = i.map((d) => ms(d));
        if (
          ((e.state._currentStep = e.state._currentStep ?? {
            type: "next_step_run_again",
          }),
          e.state._currentStep.type === "next_step_interruption")
        ) {
          if (
            (P.debug("Continuing from interruption"),
            !e.state._lastTurnResponse || !e.state._lastProcessedResponse)
          )
            throw new G("No model response found in previous state", e.state);
          const d = await ys(
            e.state._currentAgent,
            e.state._originalInput,
            e.state._generatedItems,
            e.state._lastTurnResponse,
            e.state._lastProcessedResponse,
            this,
            e.state,
          );
          if (
            (ws(e, d),
            e.state._toolUseTracker.addToolUse(
              e.state._currentAgent,
              e.state._lastProcessedResponse.toolsUsed,
            ),
            (e.state._originalInput = d.originalInput),
            (e.state._generatedItems = d.generatedItems),
            (e.state._currentStep = d.nextStep),
            d.nextStep.type === "next_step_interruption")
          )
            return;
          continue;
        }
        if (e.state._currentStep.type === "next_step_run_again") {
          if (!e.state._currentAgentSpan) {
            const p = i.map((m) => m.agentName);
            ((e.state._currentAgentSpan = Kt({
              data: {
                name: s.name,
                handoffs: p,
                tools: c.map((m) => m.name),
                output_type: s.outputSchemaName,
              },
            })),
              e.state._currentAgentSpan.start(),
              Ue(e.state._currentAgentSpan));
          }
          if (
            (e.state._currentTurn++, e.state._currentTurn > e.state._maxTurns)
          )
            throw (
              e.state._currentAgentSpan?.setError({
                message: "Max turns exceeded",
                data: { max_turns: e.state._maxTurns },
              }),
              new qn(`Max turns (${e.state._maxTurns}) exceeded`, e.state)
            );
          P.debug(`Running agent ${s.name} (turn ${e.state._currentTurn})`);
          const d =
            (s.model !== void 0 && s.model !== "") ||
            (this.config.model !== void 0 && this.config.model !== "");
          let g = Ds(s.model, this.config.model);
          (typeof g == "string" &&
            (g = await this.config.modelProvider.getModel(g)),
            e.state._currentTurn === 1 && (await this.#t(e.state)));
          let f = { ...this.config.modelSettings, ...s.modelSettings };
          const v = s.modelSettings;
          ((f = Os(d, v, g, f)), (f = gs(s, e.state._toolUseTracker, f)));
          const _ = o
            ? o.prepareInput(e.input, e.newItems)
            : St(e.input, e.newItems);
          e.state._noActiveAgentRun &&
            (s.emit("agent_start", e.state._context, s),
            this.emit("agent_start", e.state._context, s));
          let w;
          const E = o?.previousResponseId ?? n.previousResponseId,
            b = o?.conversationId ?? n.conversationId;
          for await (const p of g.getStreamedResponse({
            systemInstructions: await s.getSystemPrompt(e.state._context),
            prompt: await s.getPrompt(e.state._context),
            ...(d ? { overridePromptModel: !0 } : {}),
            input: _,
            previousResponseId: E,
            conversationId: b,
            modelSettings: f,
            tools: u,
            handoffs: l,
            outputType: as(s.outputType),
            tracing: Cs(
              this.config.tracingDisabled,
              this.config.traceIncludeSensitiveData,
            ),
            signal: n.signal,
          })) {
            if (p.type === "response_done") {
              const m = Ur.parse(p);
              w = {
                usage: new Re(m.response.usage),
                output: m.response.output,
                responseId: m.response.id,
              };
            }
            if (e.cancelled) return;
            e._addItem(new da(p));
          }
          if (((e.state._noActiveAgentRun = !1), !w))
            throw new ae("Model did not produce a final response!", e.state);
          ((e.state._lastTurnResponse = w),
            o?.trackServerItems(w),
            e.state._modelResponses.push(e.state._lastTurnResponse));
          const I = _s(e.state._lastTurnResponse, s, c, i);
          e.state._lastProcessedResponse = I;
          const O = new Set(I.newItems);
          O.size > 0 && _l(e, I.newItems);
          const C = await vs(
            s,
            e.state._originalInput,
            e.state._generatedItems,
            e.state._lastTurnResponse,
            e.state._lastProcessedResponse,
            this,
            e.state,
          );
          (ws(e, C, { skipItems: O }),
            e.state._toolUseTracker.addToolUse(s, I.toolsUsed),
            (e.state._originalInput = C.originalInput),
            (e.state._generatedItems = C.generatedItems),
            (e.state._currentStep = C.nextStep));
        }
        if (e.state._currentStep.type === "next_step_final_output") {
          (await this.#n(e.state, e.state._currentStep.output),
            this.emit(
              "agent_end",
              e.state._context,
              s,
              e.state._currentStep.output,
            ),
            s.emit("agent_end", e.state._context, e.state._currentStep.output));
          return;
        } else {
          if (e.state._currentStep.type === "next_step_interruption") return;
          e.state._currentStep.type === "next_step_handoff"
            ? ((e.state._currentAgent = e.state._currentStep?.newAgent),
              e.state._currentAgentSpan &&
                (e.state._currentAgentSpan.end(), Ae()),
              (e.state._currentAgentSpan = void 0),
              e._addItem(new fa(e.state._currentAgent)),
              (e.state._noActiveAgentRun = !0),
              (e.state._currentStep = { type: "next_step_run_again" }))
            : P.debug("Running next loop");
        }
      }
    } catch (s) {
      throw (
        e.state._currentAgentSpan &&
          e.state._currentAgentSpan.setError({
            message: "Error in agent run",
            data: { error: String(s) },
          }),
        s
      );
    } finally {
      e.state._currentAgentSpan &&
        (e.state._currentStep?.type !== "next_step_interruption" &&
          e.state._currentAgentSpan.end(),
        Ae());
    }
  }
  async #i(e, n, r) {
    return (
      (r = r ?? {}),
      Qn(async () => {
        const o = n instanceof Ce,
          s = o
            ? n
            : new Ce(
                r.context instanceof Fe ? r.context : new Fe(r.context),
                n,
                e,
                r.maxTurns ?? Es,
              ),
          i = new qr({ signal: r.signal, state: s });
        i.maxTurns = r.maxTurns ?? s._maxTurns;
        const c = this.#r(i, r, o).then(
          () => {
            i._done();
          },
          (u) => {
            i._raiseError(u);
          },
        );
        return (i._setStreamLoopPromise(c), i);
      })
    );
  }
  run(e, n, r = { stream: !1, context: void 0 }) {
    return n instanceof Ce && n._trace
      ? Ia(
          n._trace,
          async () => (
            n._currentAgentSpan && Ue(n._currentAgentSpan),
            r?.stream ? this.#i(e, n, r) : this.#e(e, n, r)
          ),
        )
      : Ea(async () => (r?.stream ? this.#i(e, n, r) : this.#e(e, n, r)), {
          traceId: this.config.traceId,
          name: this.config.workflowName,
          groupId: this.config.groupId,
          metadata: this.config.traceMetadata,
        });
  }
}
let Bt;
function Il() {
  return Bt || ((Bt = new jr()), Bt);
}
function Ds(t, e) {
  return (typeof t == "string" && t !== Se.DEFAULT_MODEL_PLACEHOLDER) || t
    ? t
    : (e ?? t ?? Se.DEFAULT_MODEL_PLACEHOLDER);
}
async function El(t, e, n) {
  const r = Il();
  return n?.stream ? await r.run(t, e, n) : await r.run(t, e, n);
}
function Os(t, e, n, r) {
  if (
    Cr() &&
    t &&
    (typeof n != "string" || !Dt(n)) &&
    (e.providerData?.reasoning ||
      e.providerData?.text?.verbosity ||
      e.providerData?.reasoning_effort)
  ) {
    const o = { ...r };
    return (
      delete o.providerData?.reasoning,
      delete o.providerData?.text?.verbosity,
      delete o.providerData?.reasoning_effort,
      o.reasoning && (delete o.reasoning.effort, delete o.reasoning.summary),
      o.text && delete o.text.verbosity,
      o
    );
  }
  return r;
}
class ba {
  state;
  constructor(e) {
    this.state = e;
  }
  get history() {
    return St(this.input, this.newItems);
  }
  get output() {
    return St([], this.newItems);
  }
  get input() {
    return this.state._originalInput;
  }
  get newItems() {
    return this.state._generatedItems;
  }
  get rawResponses() {
    return this.state._modelResponses;
  }
  get lastResponseId() {
    const e = this.rawResponses;
    return e && e.length > 0 ? e[e.length - 1].responseId : void 0;
  }
  get lastAgent() {
    return this.state._currentAgent;
  }
  get inputGuardrailResults() {
    return this.state._inputGuardrailResults;
  }
  get outputGuardrailResults() {
    return this.state._outputGuardrailResults;
  }
  get interruptions() {
    return this.state._currentStep?.type === "next_step_interruption"
      ? this.state._currentStep.data.interruptions
      : [];
  }
  get finalOutput() {
    if (this.state._currentStep?.type === "next_step_final_output")
      return this.state._currentAgent.processFinalOutput(
        this.state._currentStep.output,
      );
    P.warn("Accessed finalOutput before agent run is completed.");
  }
}
class Jt extends ba {
  constructor(e) {
    super(e);
  }
}
class qr extends ba {
  get currentAgent() {
    return this.lastAgent;
  }
  currentTurn = 0;
  maxTurns;
  #e = null;
  #t;
  #n;
  #r;
  #i;
  #o;
  #a;
  #s = !1;
  #c;
  constructor(e = {}) {
    if (
      (super(e.state),
      (this.#t = e.signal),
      (this.#r = new pc({
        start: (n) => {
          this.#n = n;
        },
        cancel: () => {
          this.#s = !0;
        },
      })),
      (this.#i = new Promise((n, r) => {
        ((this.#o = n), (this.#a = r));
      })),
      this.#t)
    ) {
      const n = () => {
        if (this.#s) return;
        this.#s = !0;
        const r = this.#n;
        if (((this.#n = void 0), this.#r.locked)) {
          if (r)
            try {
              r.close();
            } catch (o) {
              P.debug(`Failed to close readable stream on abort: ${o}`);
            }
        } else
          this.#r.cancel(this.#t?.reason).catch((o) => {
            P.debug(`Failed to cancel readable stream on abort: ${o}`);
          });
        this.#o?.();
      };
      this.#t.aborted
        ? n()
        : this.#t.addEventListener("abort", n, { once: !0 });
    }
  }
  _addItem(e) {
    this.cancelled || this.#n?.enqueue(e);
  }
  _done() {
    !this.cancelled &&
      this.#n &&
      (this.#n.close(), (this.#n = void 0), this.#o?.());
  }
  _raiseError(e) {
    (!this.cancelled && this.#n && (this.#n.error(e), (this.#n = void 0)),
      (this.#e = e),
      this.#a?.(e),
      this.#i.catch((n) => {
        P.debug(`Resulted in an error: ${n}`);
      }));
  }
  get cancelled() {
    return this.#s;
  }
  toStream() {
    return this.#r;
  }
  get completed() {
    return this.#i;
  }
  get error() {
    return this.#e;
  }
  toTextStream(e = {}) {
    const n = this.#r.pipeThrough(
      new fc({
        transform(r, o) {
          if (
            r.type === "raw_model_stream_event" &&
            r.data.type === "output_text_delta"
          ) {
            const s = Fr.parse(r.data);
            o.enqueue(s.delta);
          }
        },
      }),
    );
    return e.compatibleWithNodeStreams ? dc.fromWeb(n) : n;
  }
  [Symbol.asyncIterator]() {
    return this.#r[Symbol.asyncIterator]();
  }
  _setStreamLoopPromise(e) {
    this.#c = e;
  }
  _getStreamLoopPromise() {
    return this.#c;
  }
}
let Rs;
function Te() {
  return ((Rs ??= new hc()), Rs);
}
function et() {
  const t = Te().getStore();
  return t?.trace ? t.trace : null;
}
function tt() {
  const t = Te().getStore();
  return t?.span ? t.span : null;
}
function xa(t) {
  return async () => {
    const e = et();
    if (!e) throw new Error("No trace found");
    await e.start();
    const n = await t(e);
    if (n instanceof qr) {
      const r = n._getStreamLoopPromise();
      if (r) return (r.finally(() => e.end()), n);
    }
    return (await e.end(), n);
  };
}
async function Ia(t, e, n = {}) {
  const r = typeof t == "string" ? ee().createTrace({ ...n, name: t }) : t;
  return Te().run({ trace: r }, xa(e));
}
async function Ea(t, e = {}) {
  if (et()) return await t();
  const r = ee().createTrace(e);
  return Te().run({ trace: r }, xa(t));
}
function Ue(t) {
  const e = Te().getStore();
  if (!e) throw new Error("No existing trace found");
  (e.span &&
    ((e.span.previousSpan = e.previousSpan), (e.previousSpan = e.span)),
    (e.span = t),
    Te().enterWith(e));
}
function Ae() {
  const t = Te().getStore();
  t &&
    ((t.span = t.previousSpan),
    (t.previousSpan = t.previousSpan?.previousSpan),
    Te().enterWith(t));
}
function Ye(t) {
  const e = tt();
  e && e.setError(t);
}
function Cl(t) {
  return {
    trace: t.trace?.clone(),
    span: t.span?.clone(),
    previousSpan: t.previousSpan?.clone(),
  };
}
function Qn(t) {
  const e = Te().getStore();
  if (!e) throw new Error("No existing trace found");
  const n = Cl(e);
  return Te().run(n, t);
}
class Ca {
  async export(e) {
    if (vi.disabled) {
      P.debug("Tracing is disabled. Skipping export");
      return;
    }
    for (const n of e)
      n.type === "trace"
        ? console.log(
            `[Exporter] Export trace traceId=${n.traceId} name=${n.name}${n.groupId ? ` groupId=${n.groupId}` : ""}`,
          )
        : console.log(`[Exporter] Export span: ${JSON.stringify(n)}`);
  }
}
class Gr {
  #e;
  #t;
  #n;
  #r;
  #i;
  #o = [];
  #a;
  #s = null;
  #c = !1;
  #d = null;
  constructor(
    e,
    {
      maxQueueSize: n = 1e3,
      maxBatchSize: r = 100,
      scheduleDelay: o = 5e3,
      exportTriggerRatio: s = 0.8,
    } = {},
  ) {
    ((this.#e = n),
      (this.#t = r),
      (this.#n = o),
      (this.#r = n * s),
      (this.#i = e),
      (this.#a = Nu),
      this.start());
  }
  start() {
    ((this.#d = new AbortController()), this.#p());
  }
  async #u(e) {
    if (this.#o.length + 1 > this.#e) {
      P.error("Dropping trace because buffer is full");
      return;
    }
    (this.#o.push(e), this.#o.length > this.#r && (await this.#l()));
  }
  #p() {
    ((this.#s = this.#a.setTimeout(async () => {
      (await this.#l(), this.#p());
    }, this.#n)),
      typeof this.#s.unref == "function" && this.#s.unref());
  }
  async #l(e = !1) {
    if (this.#o.length !== 0) {
      if (
        (P.debug(
          `Exporting batches. Force: ${e}. Buffer size: ${this.#o.length}`,
        ),
        e || this.#o.length < this.#t)
      ) {
        const n = [...this.#o];
        ((this.#o = []),
          (this.#c = !0),
          await this.#i.export(n),
          (this.#c = !1));
      } else if (this.#o.length > 0) {
        const n = this.#o.splice(0, this.#t);
        ((this.#c = !0), await this.#i.export(n), (this.#c = !1));
      }
    }
  }
  async onTraceStart(e) {
    await this.#u(e);
  }
  async onTraceEnd(e) {}
  async onSpanStart(e) {}
  async onSpanEnd(e) {
    await this.#u(e);
  }
  async shutdown(e) {
    for (
      e &&
        this.#a.setTimeout(() => {
          this.#d?.abort();
        }, e),
        P.debug("Shutting down gracefully");
      this.#o.length > 0;
    ) {
      if (
        (P.debug(`Waiting for buffer to empty. Items left: ${this.#o.length}`),
        this.#c || (await this.#l(!0)),
        this.#d?.signal.aborted)
      ) {
        (P.debug("Timeout reached, force flushing"), await this.#l(!0));
        break;
      }
      await new Promise((n) => this.#a.setTimeout(n, 500));
    }
    (P.debug("Buffer empty. Exiting"),
      this.#a && this.#s && this.#a.clearTimeout(this.#s));
  }
  async forceFlush() {
    this.#o.length > 0 && (await this.#l(!0));
  }
}
class Al {
  #e = [];
  start() {
    for (const e of this.#e) e.start && e.start();
  }
  addTraceProcessor(e) {
    this.#e.push(e);
  }
  setProcessors(e) {
    P.debug("Shutting down old processors");
    for (const n of this.#e) n.shutdown();
    this.#e = e;
  }
  async onTraceStart(e) {
    for (const n of this.#e) await n.onTraceStart(e);
  }
  async onTraceEnd(e) {
    for (const n of this.#e) await n.onTraceEnd(e);
  }
  async onSpanStart(e) {
    for (const n of this.#e) await n.onSpanStart(e);
  }
  async onSpanEnd(e) {
    for (const n of this.#e) await n.onSpanEnd(e);
  }
  async shutdown(e) {
    for (const n of this.#e) await n.shutdown(e);
  }
  async forceFlush() {
    for (const e of this.#e) await e.forceFlush();
  }
}
let Cn = null,
  An = null;
function Dl() {
  return (Cn || (Cn = new Ca()), Cn);
}
function Aa() {
  return (An || (An = new Gr(Dl())), An);
}
function ks() {
  return new Date().toISOString();
}
function Jr() {
  return `trace_${tr().replace(/-/g, "")}`;
}
function Da() {
  return `span_${tr().replace(/-/g, "").slice(0, 24)}`;
}
function Ol() {
  return `group_${tr().replace(/-/g, "").slice(0, 24)}`;
}
function Rl(t) {
  return Object.fromEntries(
    Object.entries(t).filter(([e]) => !e.startsWith("_")),
  );
}
class nt {
  type = "trace.span";
  #e;
  #t;
  #n;
  #r;
  #i;
  #o;
  #a;
  #s;
  #c;
  constructor(e, n) {
    ((this.#t = e.traceId),
      (this.#n = e.spanId ?? Da()),
      (this.#e = e.data),
      (this.#i = n),
      (this.#r = e.parentId ?? null),
      (this.#s = e.error ?? null),
      (this.#o = e.startedAt ?? null),
      (this.#a = e.endedAt ?? null));
  }
  get traceId() {
    return this.#t;
  }
  get spanData() {
    return this.#e;
  }
  get spanId() {
    return this.#n;
  }
  get parentId() {
    return this.#r;
  }
  get previousSpan() {
    return this.#c;
  }
  set previousSpan(e) {
    this.#c = e;
  }
  start() {
    if (this.#o) {
      P.warn("Span already started");
      return;
    }
    ((this.#o = ks()), this.#i.onSpanStart(this));
  }
  end() {
    if (this.#a) {
      P.debug("Span already finished", this.spanData);
      return;
    }
    ((this.#a = ks()), this.#i.onSpanEnd(this));
  }
  setError(e) {
    this.#s = e;
  }
  get error() {
    return this.#s;
  }
  get startedAt() {
    return this.#o;
  }
  get endedAt() {
    return this.#a;
  }
  clone() {
    const e = new nt(
      {
        traceId: this.traceId,
        spanId: this.spanId,
        parentId: this.parentId ?? void 0,
        data: this.spanData,
        startedAt: this.#o ?? void 0,
        endedAt: this.#a ?? void 0,
        error: this.#s ?? void 0,
      },
      this.#i,
    );
    return ((e.previousSpan = this.previousSpan?.clone()), e);
  }
  toJSON() {
    return {
      object: this.type,
      id: this.spanId,
      trace_id: this.traceId,
      parent_id: this.parentId,
      started_at: this.startedAt,
      ended_at: this.endedAt,
      span_data: Rl(this.spanData),
      error: this.error,
    };
  }
}
class xe extends nt {
  constructor(e, n) {
    super({ traceId: "no-op", spanId: "no-op", data: e }, n);
  }
  start() {}
  end() {}
  setError() {}
  toJSON() {
    return null;
  }
}
class rt {
  type = "trace";
  traceId;
  name;
  groupId = null;
  metadata;
  #e;
  #t;
  constructor(e, n) {
    ((this.traceId = e.traceId ?? Jr()),
      (this.name = e.name ?? "Agent workflow"),
      (this.groupId = e.groupId ?? null),
      (this.metadata = e.metadata ?? {}),
      (this.#e = n ?? Aa()),
      (this.#t = e.started ?? !1));
  }
  async start() {
    this.#t || ((this.#t = !0), await this.#e.onTraceStart(this));
  }
  async end() {
    this.#t && ((this.#t = !1), await this.#e.onTraceEnd(this));
  }
  clone() {
    return new rt({
      traceId: this.traceId,
      name: this.name,
      groupId: this.groupId ?? void 0,
      metadata: this.metadata,
      started: this.#t,
    });
  }
  toJSON() {
    return {
      object: this.type,
      id: this.traceId,
      workflow_name: this.name,
      group_id: this.groupId,
      metadata: this.metadata,
    };
  }
}
class Ht extends rt {
  constructor() {
    super({});
  }
  async start() {}
  async end() {}
  toJSON() {
    return null;
  }
}
class Oa {
  #e;
  #t;
  constructor() {
    ((this.#e = new Al()), (this.#t = vi.disabled), this.#n());
  }
  registerProcessor(e) {
    this.#e.addTraceProcessor(e);
  }
  setProcessors(e) {
    this.#e.setProcessors(e);
  }
  getCurrentTrace() {
    return et();
  }
  getCurrentSpan() {
    return tt();
  }
  setDisabled(e) {
    this.#t = e;
  }
  startExportLoop() {
    this.#e.start();
  }
  createTrace(e) {
    if (this.#t)
      return (
        P.debug("Tracing is disabled, Not creating trace %o", e),
        new Ht()
      );
    const n = e.traceId ?? Jr(),
      r = e.name ?? "Agent workflow";
    return (
      P.debug("Creating trace %s with name %s", n, r),
      new rt({ ...e, name: r, traceId: n }, this.#e)
    );
  }
  createSpan(e, n) {
    if (this.#t || e.disabled)
      return (
        P.debug("Tracing is disabled, Not creating span %o", e),
        new xe(e.data, this.#e)
      );
    let r, o;
    if (n) {
      if (n instanceof rt) {
        if (n instanceof Ht)
          return (
            P.debug("Parent trace is no-op, returning NoopSpan"),
            new xe(e.data, this.#e)
          );
        o = n.traceId;
      } else if (n instanceof nt) {
        if (n instanceof xe)
          return (
            P.debug("Parent span is no-op, returning NoopSpan"),
            new xe(e.data, this.#e)
          );
        ((r = n.spanId), (o = n.traceId));
      }
    } else {
      const s = et(),
        i = tt();
      if (!s)
        return (
          P.error(
            "No active trace. Make sure to start a trace with `withTrace()` first. Returning NoopSpan.",
          ),
          new xe(e.data, this.#e)
        );
      if (i instanceof xe || s instanceof Ht)
        return (
          P.debug(`Parent ${i} or ${s} is no-op, returning NoopSpan`),
          new xe(e.data, this.#e)
        );
      ((o = s.traceId),
        i
          ? (P.debug("Using parent span %s", i.spanId), (r = i.spanId))
          : P.debug("No parent span, using current trace %s", s.traceId));
    }
    return o
      ? (P.debug(
          `Creating span ${JSON.stringify(e.data)} with id ${e.spanId ?? o}`,
        ),
        new nt({ ...e, traceId: o, parentId: r }, this.#e))
      : (P.error(
          "No traceId found. Make sure to start a trace with `withTrace()` first. Returning NoopSpan.",
        ),
        new xe(e.data, this.#e));
  }
  async shutdown(e) {
    try {
      (P.debug("Shutting down tracing provider"), await this.#e.shutdown(e));
    } catch (n) {
      P.error("Error shutting down tracing provider %o", n);
    }
  }
  #n() {
    if (typeof process < "u" && typeof process.on == "function") {
      const e = async () => {
        const n = setTimeout(() => {
          (console.warn("Cleanup timeout, forcing exit"), process.exit(1));
        }, 5e3);
        try {
          await this.shutdown();
        } finally {
          clearTimeout(n);
        }
      };
      (process.on("beforeExit", e),
        process.on("SIGINT", async () => {
          (await e(), Ns("SIGINT") || process.exit(130));
        }),
        process.on("SIGTERM", async () => {
          (await e(), Ns("SIGTERM") || process.exit(0));
        }),
        process.on("unhandledRejection", async (n, r) => {
          (P.error("Unhandled rejection", n, r),
            await e(),
            kl("unhandledRejection") || process.exit(1));
        }));
    }
  }
  async forceFlush() {
    await this.#e.forceFlush();
  }
}
function Ns(t) {
  return process.listeners(t).length > 1;
}
function kl(t) {
  return process.listeners(t).length > 1;
}
let Dn;
function ee() {
  return (Dn || (Dn = new Oa()), Dn);
}
function Ra(t) {
  ee().registerProcessor(t);
}
function ka(t) {
  ee().setProcessors(t);
}
function Nl(t) {
  ee().setDisabled(t);
}
function Ll() {
  ee().startExportLoop();
}
function Pl(t, e) {
  return {
    type: "message",
    role: "user",
    content: typeof t == "string" ? [{ type: "input_text", text: t }] : t,
    providerData: e,
  };
}
function Ml(t, e) {
  return { type: "message", role: "system", content: t, providerData: e };
}
function Fl(t, e) {
  return {
    type: "message",
    role: "assistant",
    content: typeof t == "string" ? [{ type: "output_text", text: t }] : t,
    status: "completed",
    providerData: e,
  };
}
function Ul(t) {
  if (!t?.allowed && !t?.blocked) return;
  const e = {};
  return (
    t?.allowed && (e.allowedToolNames = t.allowed),
    t?.blocked && (e.blockedToolNames = t.blocked),
    e
  );
}
Ra(Aa());
const $l = { version: "0.2.1" },
  Bl = "responses";
let Na = Bl,
  La,
  Pa,
  Ma;
function jl(t) {
  Ma = t;
}
function ql() {
  return Ma ?? Ir().OPENAI_API_KEY;
}
function Gl() {
  return Na === "responses";
}
function Jl(t) {
  Na = t;
}
function Hl(t) {
  La = t;
}
function Wl() {
  return La;
}
function zl(t) {
  Pa = t;
}
function Vl() {
  return Pa ?? Ir().OPENAI_API_KEY;
}
const Hr = { "User-Agent": `Agents/JavaScript ${$l.version}` },
  te = je("openai-agents:openai"),
  Kl = J(["in_progress", "completed", "searching", "failed"]).default("failed"),
  Yl = J([
    "in_progress",
    "completed",
    "searching",
    "failed",
    "incomplete",
  ]).default("failed"),
  Zl = J(["in_progress", "completed", "interpreting"]).default("in_progress"),
  Xl = J(["in_progress", "completed", "generating", "failed"]).default(
    "failed",
  );
function Ql(t = {}) {
  const e = {
    type: "web_search",
    name: t.name ?? "web_search",
    user_location: t.userLocation,
    filters: t.filters?.allowedDomains
      ? { allowed_domains: t.filters.allowedDomains }
      : void 0,
    search_context_size: t.searchContextSize ?? "medium",
  };
  return { type: "hosted_tool", name: t.name ?? "web_search", providerData: e };
}
function ed(t, e = {}) {
  const n = Array.isArray(t) ? t : [t],
    r = {
      type: "file_search",
      name: e.name ?? "file_search",
      vector_store_ids: n,
      max_num_results: e.maxNumResults,
      include_search_results: e.includeSearchResults,
      ranking_options: e.rankingOptions,
      filters: e.filters,
    };
  return {
    type: "hosted_tool",
    name: e.name ?? "file_search",
    providerData: r,
  };
}
function td(t = {}) {
  const e = {
    type: "code_interpreter",
    name: t.name ?? "code_interpreter",
    container: t.container ?? { type: "auto" },
  };
  return {
    type: "hosted_tool",
    name: t.name ?? "code_interpreter",
    providerData: e,
  };
}
function nd(t = {}) {
  const e = {
    type: "image_generation",
    name: t.name ?? "image_generation",
    background: t.background,
    input_fidelity: t.inputFidelity,
    input_image_mask: t.inputImageMask,
    model: t.model,
    moderation: t.moderation,
    output_compression: t.outputCompression,
    output_format: t.outputFormat,
    partial_images: t.partialImages,
    quality: t.quality,
    size: t.size,
  };
  return {
    type: "hosted_tool",
    name: t.name ?? "image_generation",
    providerData: e,
  };
}
function V(t) {
  if (!t || typeof t != "object" || Array.isArray(t)) return t;
  const e = {};
  for (const [n, r] of Object.entries(t)) {
    const o = n.replace(/([A-Z])/g, "_$1").toLowerCase();
    e[o] = V(r);
  }
  return e;
}
const rd = J([
    "file_search",
    "web_search",
    "web_search_preview",
    "computer_use_preview",
    "code_interpreter",
    "image_generation",
    "mcp",
  ]),
  sd = J(["auto", "required", "none"]);
function od(t) {
  if (typeof t > "u") return;
  const e = sd.safeParse(t);
  if (e.success) return e.data;
  const n = rd.safeParse(t);
  return n.success ? { type: n.data } : { type: "function", name: t };
}
function id(t, e) {
  return t === "text" ? e : { ...e, format: t };
}
function ad(t) {
  if (typeof t == "string") return t;
  if (Array.isArray(t)) return t.map(Ls);
  if (Zt(t) && typeof t.type == "string") {
    if (t.type === "text" && typeof t.text == "string") return t.text;
    if (t.type === "image" || t.type === "file") return cd(t).map(Ls);
  }
  return String(t);
}
function cd(t) {
  if (t.type === "text") {
    const e = { type: "input_text", text: t.text };
    return (t.providerData && (e.providerData = t.providerData), [e]);
  }
  if (t.type === "image") {
    const e = { type: "input_image" };
    t.detail && (e.detail = t.detail);
    const n = t.imageUrl,
      r = t.fileId,
      o = t.data;
    if (typeof t.image == "string" && t.image.length > 0) e.image = t.image;
    else if (Zt(t.image)) {
      const s = t.image,
        i = ld(s);
      if (typeof s.url == "string" && s.url.length > 0) e.image = s.url;
      else if (typeof s.data == "string" && s.data.length > 0)
        e.image = Ke(s.data, i);
      else if (s.data instanceof Uint8Array && s.data.length > 0)
        e.image = Ke(s.data, i);
      else {
        const c =
          (typeof s.fileId == "string" && s.fileId.length > 0 && s.fileId) ||
          (typeof s.id == "string" && s.id.length > 0 ? s.id : void 0);
        c && (e.image = { id: c });
      }
    } else if (typeof n == "string" && n.length > 0) e.image = n;
    else if (typeof r == "string" && r.length > 0) e.image = { id: r };
    else {
      let s;
      (typeof o == "string" && o.length > 0
        ? (s = o)
        : o instanceof Uint8Array && o.length > 0 && (s = vt(o)),
        s && (e.image = s));
    }
    return (t.providerData && (e.providerData = t.providerData), [e]);
  }
  if (t.type === "file") {
    const e = { type: "input_file" },
      n = t.file ?? t.file;
    if (typeof n == "string") e.file = n;
    else if (Zt(n)) {
      if (typeof n.data == "string" && n.data.length > 0)
        e.file = Ke(n.data, n.mediaType ?? "text/plain");
      else if (n.data instanceof Uint8Array && n.data.length > 0)
        e.file = Ke(n.data, n.mediaType ?? "text/plain");
      else if (typeof n.url == "string" && n.url.length > 0)
        e.file = { url: n.url };
      else {
        const r =
          (typeof n.id == "string" && n.id.length > 0 && n.id) ||
          (typeof n.fileId == "string" && n.fileId.length > 0
            ? n.fileId
            : void 0);
        r && (e.file = { id: r });
      }
      typeof n.filename == "string" &&
        n.filename.length > 0 &&
        (e.filename = n.filename);
    }
    if (!e.file) {
      const r = ud(t);
      (r.file && (e.file = r.file), r.filename && (e.filename = r.filename));
    }
    return (t.providerData && (e.providerData = t.providerData), [e]);
  }
  throw new G(`Unsupported tool output type: ${JSON.stringify(t)}`);
}
function Ls(t) {
  if (t.type === "input_text") return { type: "input_text", text: t.text };
  if (t.type === "input_image") {
    const e = { type: "input_image" },
      n = t.image ?? t.imageUrl;
    typeof n == "string"
      ? (e.image_url = n)
      : Zt(n) && typeof n.id == "string" && (e.file_id = n.id);
    const r = t.fileId;
    return (
      typeof r == "string" && (e.file_id = r),
      t.detail && (e.detail = t.detail),
      e
    );
  }
  if (t.type === "input_file") {
    const e = { type: "input_file" };
    if (typeof t.file == "string") {
      const s = t.file.trim();
      s.startsWith("data:")
        ? (e.file_data = s)
        : s.startsWith("http://") || s.startsWith("https://")
          ? (e.file_url = s)
          : /^[A-Za-z0-9+/=]+$/.test(s)
            ? (e.file_data = s)
            : (e.file_url = s);
    } else
      t.file &&
      typeof t.file == "object" &&
      "id" in t.file &&
      typeof t.file.id == "string"
        ? (e.file_id = t.file.id)
        : t.file &&
          typeof t.file == "object" &&
          "url" in t.file &&
          typeof t.file.url == "string" &&
          (e.file_url = t.file.url);
    const n = t.fileData;
    typeof n == "string" && (e.file_data = n);
    const r = t.fileUrl;
    typeof r == "string" && (e.file_url = r);
    const o = t.fileId;
    return (
      typeof o == "string" && (e.file_id = o),
      t.filename && (e.filename = t.filename),
      e
    );
  }
  throw new G(`Unsupported structured tool output: ${JSON.stringify(t)}`);
}
function ud(t) {
  const e =
      typeof t.filename == "string" && t.filename.length > 0
        ? t.filename
        : void 0,
    n =
      (typeof t.id == "string" && t.id.length > 0 && t.id) ??
      (typeof t.fileId == "string" && t.fileId.length > 0 ? t.fileId : void 0);
  return n
    ? { file: { id: n }, filename: e }
    : typeof t.fileUrl == "string" && t.fileUrl.length > 0
      ? { file: { url: t.fileUrl }, filename: e }
      : typeof t.fileData == "string" && t.fileData.length > 0
        ? { file: Ke(t.fileData, t.mediaType ?? "text/plain"), filename: e }
        : t.fileData instanceof Uint8Array && t.fileData.length > 0
          ? { file: Ke(t.fileData, t.mediaType ?? "text/plain"), filename: e }
          : {};
}
function Zt(t) {
  return typeof t == "object" && t !== null;
}
function ld(t) {
  if (typeof t.mediaType == "string" && t.mediaType.length > 0)
    return t.mediaType;
}
function Ke(t, e) {
  const n = typeof t == "string" ? t : vt(t);
  return e ? `data:${e};base64,${n}` : n;
}
function dd(t, e) {
  const n = [],
    r = [];
  for (const o of t) {
    const { tool: s, include: i } = pd(o);
    if ((n.push(s), i && i.length > 0)) for (const c of i) r.push(c);
  }
  return { tools: [...n, ...e.map(hd)], include: r };
}
function pd(t) {
  if (t.type === "function")
    return {
      tool: {
        type: "function",
        name: t.name,
        description: t.description,
        parameters: t.parameters,
        strict: t.strict,
      },
      include: void 0,
    };
  if (t.type === "computer")
    return {
      tool: {
        type: "computer_use_preview",
        environment: t.environment,
        display_width: t.dimensions[0],
        display_height: t.dimensions[1],
      },
      include: void 0,
    };
  if (t.type === "hosted_tool") {
    if (t.providerData?.type === "web_search")
      return {
        tool: {
          type: "web_search",
          user_location: t.providerData.user_location,
          filters: t.providerData.filters,
          search_context_size: t.providerData.search_context_size,
        },
        include: void 0,
      };
    if (t.providerData?.type === "web_search_preview")
      return {
        tool: {
          type: "web_search_preview",
          user_location: t.providerData.user_location,
          search_context_size: t.providerData.search_context_size,
        },
        include: void 0,
      };
    if (t.providerData?.type === "file_search")
      return {
        tool: {
          type: "file_search",
          vector_store_ids:
            t.providerData.vector_store_ids ||
            (typeof t.providerData.vector_store_id == "string"
              ? [t.providerData.vector_store_id]
              : t.providerData.vector_store_id),
          max_num_results: t.providerData.max_num_results,
          ranking_options: t.providerData.ranking_options,
          filters: t.providerData.filters,
        },
        include: t.providerData.include_search_results
          ? ["file_search_call.results"]
          : void 0,
      };
    if (t.providerData?.type === "code_interpreter")
      return {
        tool: { type: "code_interpreter", container: t.providerData.container },
        include: void 0,
      };
    if (t.providerData?.type === "image_generation")
      return {
        tool: {
          type: "image_generation",
          background: t.providerData.background,
          input_fidelity: t.providerData.input_fidelity,
          input_image_mask: t.providerData.input_image_mask,
          model: t.providerData.model,
          moderation: t.providerData.moderation,
          output_compression: t.providerData.output_compression,
          output_format: t.providerData.output_format,
          partial_images: t.providerData.partial_images,
          quality: t.providerData.quality,
          size: t.providerData.size,
        },
        include: void 0,
      };
    if (t.providerData?.type === "mcp")
      return {
        tool: {
          type: "mcp",
          server_label: t.providerData.server_label,
          server_url: t.providerData.server_url,
          connector_id: t.providerData.connector_id,
          authorization: t.providerData.authorization,
          allowed_tools: t.providerData.allowed_tools,
          headers: t.providerData.headers,
          require_approval: fd(t.providerData.require_approval),
        },
        include: void 0,
      };
    if (t.providerData) return { tool: t.providerData, include: void 0 };
  }
  throw new Error(`Unsupported tool type: ${JSON.stringify(t)}`);
}
function fd(t) {
  return t === "never" || t === void 0
    ? "never"
    : t === "always"
      ? "always"
      : {
          never: { tool_names: t.never?.tool_names },
          always: { tool_names: t.always?.tool_names },
        };
}
function hd(t) {
  return {
    name: t.toolName,
    description: t.toolDescription,
    parameters: t.inputJsonSchema,
    strict: t.strictJsonSchema,
    type: "function",
  };
}
function Fa(t) {
  if (t.type === "input_text")
    return { type: "input_text", text: t.text, ...V(t.providerData) };
  if (t.type === "input_image") {
    const e = { type: "input_image", detail: t.detail ?? "auto" };
    return (
      typeof t.image == "string"
        ? (e.image_url = t.image)
        : t.image && "id" in t.image
          ? (e.file_id = t.image.id)
          : typeof t.imageUrl == "string"
            ? (e.image_url = t.imageUrl)
            : typeof t.fileId == "string" && (e.file_id = t.fileId),
      { ...e, ...V(t.providerData) }
    );
  } else if (t.type === "input_file") {
    const e = { type: "input_file" };
    if (typeof t.file == "string")
      if (t.file.startsWith("data:")) e.file_data = t.file;
      else if (t.file.startsWith("https://")) e.file_url = t.file;
      else
        throw new G(
          "Unsupported string data for file input. If you're trying to pass an uploaded file's ID, use an object with the ID property instead.",
        );
    else
      t.file && typeof t.file == "object" && "id" in t.file
        ? (e.file_id = t.file.id)
        : t.file &&
          typeof t.file == "object" &&
          "url" in t.file &&
          (e.file_url = t.file.url);
    const n = t.fileData;
    typeof n == "string" && (e.file_data = n);
    const r = t.fileUrl;
    typeof r == "string" && (e.file_url = r);
    const o = t.fileId;
    return (
      typeof o == "string" && (e.file_id = o),
      t.filename && (e.filename = t.filename),
      { ...e, ...V(t.providerData) }
    );
  }
  throw new G(`Unsupported input content type: ${JSON.stringify(t)}`);
}
function md(t) {
  if (t.type === "output_text")
    return {
      type: "output_text",
      text: t.text,
      annotations: [],
      ...V(t.providerData),
    };
  if (t.type === "refusal")
    return { type: "refusal", refusal: t.refusal, ...V(t.providerData) };
  throw new G(`Unsupported output content type: ${JSON.stringify(t)}`);
}
function _d(t) {
  if (t.role === "system")
    return {
      id: t.id,
      role: "system",
      content: t.content,
      ...V(t.providerData),
    };
  if (t.role === "user")
    return typeof t.content == "string"
      ? { id: t.id, role: "user", content: t.content, ...V(t.providerData) }
      : {
          id: t.id,
          role: "user",
          content: t.content.map(Fa),
          ...V(t.providerData),
        };
  if (t.role === "assistant")
    return {
      type: "message",
      id: t.id,
      role: "assistant",
      content: t.content.map(md),
      status: t.status,
      ...V(t.providerData),
    };
  throw new G(`Unsupported item ${JSON.stringify(t)}`);
}
function gd(t) {
  return (
    t.type === "message" || (typeof t.type > "u" && typeof t.role == "string")
  );
}
function yd(t) {
  if (!t) return;
  const e = {};
  for (const [n, r] of Object.entries(t.variables ?? {}))
    typeof r == "string" ? (e[n] = r) : typeof r == "object" && (e[n] = Fa(r));
  return { id: t.promptId, version: t.version, variables: e };
}
function vd(t) {
  return typeof t == "string"
    ? [{ role: "user", content: t }]
    : t.map((e) => {
        if (gd(e)) return _d(e);
        if (e.type === "function_call")
          return {
            id: e.id,
            type: "function_call",
            name: e.name,
            call_id: e.callId,
            arguments: e.arguments,
            status: e.status,
            ...V(e.providerData),
          };
        if (e.type === "function_call_result") {
          const r = ad(e.output);
          return {
            type: "function_call_output",
            id: e.id,
            call_id: e.callId,
            output: r,
            status: e.status,
            ...V(e.providerData),
          };
        }
        if (e.type === "reasoning")
          return {
            id: e.id,
            type: "reasoning",
            summary: e.content.map((o) => ({
              type: "summary_text",
              text: o.text,
              ...V(o.providerData),
            })),
            encrypted_content: e.providerData?.encryptedContent,
            ...V(e.providerData),
          };
        if (e.type === "computer_call")
          return {
            type: "computer_call",
            call_id: e.callId,
            id: e.id,
            action: e.action,
            status: e.status,
            pending_safety_checks: [],
            ...V(e.providerData),
          };
        if (e.type === "computer_call_result")
          return {
            type: "computer_call_output",
            id: e.id,
            call_id: e.callId,
            output: Sd(e),
            status: e.providerData?.status,
            acknowledged_safety_checks:
              e.providerData?.acknowledgedSafetyChecks,
            ...V(e.providerData),
          };
        if (e.type === "hosted_tool_call") {
          if (
            e.providerData?.type === "web_search_call" ||
            e.providerData?.type === "web_search"
          )
            return {
              ...V(e.providerData),
              type: "web_search_call",
              id: e.id,
              status: Kl.parse(e.status ?? "failed"),
            };
          if (
            e.providerData?.type === "file_search_call" ||
            e.providerData?.type === "file_search"
          )
            return {
              ...V(e.providerData),
              type: "file_search_call",
              id: e.id,
              status: Yl.parse(e.status ?? "failed"),
              queries: e.providerData?.queries ?? [],
              results: e.providerData?.results,
            };
          if (
            e.providerData?.type === "code_interpreter_call" ||
            e.providerData?.type === "code_interpreter"
          )
            return {
              ...V(e.providerData),
              type: "code_interpreter_call",
              id: e.id,
              code: e.providerData?.code ?? "",
              outputs: e.providerData?.outputs ?? e.providerData?.results ?? [],
              status: Zl.parse(e.status ?? "failed"),
              container_id: e.providerData?.container_id,
            };
          if (
            e.providerData?.type === "image_generation_call" ||
            e.providerData?.type === "image_generation"
          )
            return {
              ...V(e.providerData),
              type: "image_generation_call",
              id: e.id,
              result: e.providerData?.result ?? null,
              status: Xl.parse(e.status ?? "failed"),
            };
          if (
            e.providerData?.type === "mcp_list_tools" ||
            e.name === "mcp_list_tools"
          ) {
            const r = e.providerData;
            return {
              ...V(e.providerData),
              type: "mcp_list_tools",
              id: e.id,
              tools: V(r.tools),
              server_label: r.server_label,
              error: r.error,
            };
          } else if (
            e.providerData?.type === "mcp_approval_request" ||
            e.name === "mcp_approval_request"
          ) {
            const r = e.providerData;
            return {
              ...V(e.providerData),
              type: "mcp_approval_request",
              id: r.id ?? e.id,
              name: r.name,
              arguments: r.arguments,
              server_label: r.server_label,
            };
          } else if (
            e.providerData?.type === "mcp_approval_response" ||
            e.name === "mcp_approval_response"
          ) {
            const r = e.providerData;
            return {
              ...V(r),
              type: "mcp_approval_response",
              id: r.id,
              approve: r.approve,
              approval_request_id: r.approval_request_id,
              reason: r.reason,
            };
          } else if (
            e.providerData?.type === "mcp_call" ||
            e.name === "mcp_call"
          ) {
            const r = e.providerData;
            return {
              ...V(r),
              type: "mcp_call",
              id: r.id ?? e.id,
              name: r.name,
              arguments: r.arguments,
              server_label: r.server_label,
              error: r.error,
            };
          }
          throw new G(
            `Unsupported built-in tool call type: ${JSON.stringify(e)}`,
          );
        }
        if (e.type === "unknown") return { ...V(e.providerData), id: e.id };
        const n = e;
        throw new G(`Unsupported item ${JSON.stringify(n)}`);
      });
}
function Sd(t) {
  return { type: "computer_screenshot", image_url: t.output.data };
}
function wd(t) {
  if (t.type === "output_text") {
    const { type: e, text: n, ...r } = t;
    return { type: e, text: n, ...r };
  }
  if (t.type === "refusal") {
    const { type: e, refusal: n, ...r } = t;
    return { type: e, refusal: n, ...r };
  }
  throw new Error(`Unsupported message content type: ${JSON.stringify(t)}`);
}
function Ps(t) {
  return t.map((e) => {
    if (e.type === "message") {
      const { id: n, type: r, role: o, content: s, status: i, ...c } = e;
      return {
        id: n,
        type: r,
        role: o,
        content: s.map(wd),
        status: i,
        providerData: c,
      };
    } else if (
      e.type === "file_search_call" ||
      e.type === "web_search_call" ||
      e.type === "image_generation_call" ||
      e.type === "code_interpreter_call"
    ) {
      const { status: n, ...r } = e;
      let o;
      return (
        "result" in r && r.result !== null && ((o = r.result), delete r.result),
        {
          type: "hosted_tool_call",
          id: e.id,
          name: e.type,
          status: n,
          output: o,
          providerData: r,
        }
      );
    } else if (e.type === "function_call") {
      const { call_id: n, name: r, status: o, arguments: s, ...i } = e;
      return {
        type: "function_call",
        id: e.id,
        callId: n,
        name: r,
        status: o,
        arguments: s,
        providerData: i,
      };
    } else if (e.type === "computer_call") {
      const { call_id: n, status: r, action: o, ...s } = e;
      return {
        type: "computer_call",
        id: e.id,
        callId: n,
        status: r,
        action: o,
        providerData: s,
      };
    } else if (e.type === "mcp_list_tools") {
      const { ...n } = e;
      return {
        type: "hosted_tool_call",
        id: e.id,
        name: e.type,
        status: "completed",
        output: void 0,
        providerData: n,
      };
    } else if (e.type === "mcp_approval_request") {
      const { ...n } = e;
      return {
        type: "hosted_tool_call",
        id: e.id,
        name: "mcp_approval_request",
        status: "completed",
        output: void 0,
        providerData: n,
      };
    } else if (e.type === "mcp_call") {
      const { output: n, ...r } = e;
      return {
        type: "hosted_tool_call",
        id: e.id,
        name: e.type,
        status: "completed",
        output: n || void 0,
        providerData: r,
      };
    } else if (e.type === "reasoning") {
      const { summary: n, ...r } = e;
      return {
        type: "reasoning",
        id: e.id,
        content: n.map((s) => {
          const { text: i, ...c } = s;
          return { type: "input_text", text: i, providerData: c };
        }),
        providerData: r,
      };
    }
    return { type: "unknown", providerData: e };
  });
}
class Ua {
  #e;
  #t;
  constructor(e, n) {
    ((this.#e = e), (this.#t = n));
  }
  async #n(e, n) {
    const r = vd(e.input),
      { tools: o, include: s } = dd(e.tools, e.handoffs),
      i = od(e.modelSettings.toolChoice),
      { text: c, ...u } = e.modelSettings.providerData ?? {};
    e.modelSettings.reasoning &&
      (u.reasoning = { ...e.modelSettings.reasoning, ...u.reasoning });
    let l = c;
    e.modelSettings.text && (l = { ...e.modelSettings.text, ...c });
    const d = id(e.outputType, l),
      g = yd(e.prompt);
    let f;
    if (typeof e.modelSettings.parallelToolCalls == "boolean") {
      if (e.modelSettings.parallelToolCalls && o.length === 0)
        throw new Error("Parallel tool calls are not supported without tools");
      f = e.modelSettings.parallelToolCalls;
    }
    const _ = {
      ...(!e.prompt || e.overridePromptModel === !0 ? { model: this.#t } : {}),
      instructions: Td(e.systemInstructions),
      input: r,
      include: s,
      tools: o,
      previous_response_id: e.previousResponseId,
      conversation: e.conversationId,
      prompt: g,
      temperature: e.modelSettings.temperature,
      top_p: e.modelSettings.topP,
      truncation: e.modelSettings.truncation,
      max_output_tokens: e.modelSettings.maxTokens,
      tool_choice: i,
      parallel_tool_calls: f,
      stream: n,
      text: d,
      store: e.modelSettings.store,
      ...u,
    };
    te.dontLogModelData
      ? te.debug("Calling LLM")
      : te.debug(`Calling LLM. Request data: ${JSON.stringify(_, null, 2)}`);
    const w = await this.#e.responses.create(_, {
      headers: Hr,
      signal: e.signal,
    });
    return (
      te.dontLogModelData
        ? te.debug("Response received")
        : te.debug(`Response received: ${JSON.stringify(w, null, 2)}`),
      w
    );
  }
  async getResponse(e) {
    const n = await Qi(async (o) => {
      const s = await this.#n(e, !1);
      return (
        e.tracing &&
          ((o.spanData.response_id = s.id),
          (o.spanData._input = e.input),
          (o.spanData._response = s)),
        s
      );
    });
    return {
      usage: new Re({
        inputTokens: n.usage?.input_tokens ?? 0,
        outputTokens: n.usage?.output_tokens ?? 0,
        totalTokens: n.usage?.total_tokens ?? 0,
        inputTokensDetails: { ...n.usage?.input_tokens_details },
        outputTokensDetails: { ...n.usage?.output_tokens_details },
      }),
      output: Ps(n.output),
      responseId: n.id,
      providerData: n,
    };
  }
  async *getStreamedResponse(e) {
    const n = e.tracing ? $r() : void 0;
    try {
      n &&
        (n.start(), Ue(n), e.tracing === !0 && (n.spanData._input = e.input));
      const r = await this.#n(e, !0);
      let o;
      for await (const s of r) {
        if (s.type === "response.created")
          yield { type: "response_started", providerData: { ...s } };
        else if (s.type === "response.completed") {
          o = s.response;
          const { response: i, ...c } = s,
            { output: u, usage: l, id: d, ...g } = i;
          (yield {
            type: "response_done",
            response: {
              id: d,
              output: Ps(u),
              usage: {
                inputTokens: l?.input_tokens ?? 0,
                outputTokens: l?.output_tokens ?? 0,
                totalTokens: l?.total_tokens ?? 0,
                inputTokensDetails: { ...l?.input_tokens_details },
                outputTokensDetails: { ...l?.output_tokens_details },
              },
              providerData: g,
            },
            providerData: c,
          },
            yield { type: "model", event: s });
        } else if (s.type === "response.output_text.delta") {
          const { delta: i, ...c } = s;
          yield { type: "output_text_delta", delta: i, providerData: c };
        }
        yield { type: "model", event: s };
      }
      e.tracing &&
        n &&
        o &&
        ((n.spanData.response_id = o.id), (n.spanData._response = o));
    } catch (r) {
      throw (
        n &&
          n.setError({
            message: "Error streaming response",
            data: {
              error: e.tracing
                ? String(r)
                : r instanceof Error
                  ? r.name
                  : void 0,
            },
          }),
        r
      );
    } finally {
      n && (n.end(), Ae());
    }
  }
}
function Td(t) {
  if (typeof t == "string") return t.trim() === "" ? void 0 : t;
}
async function* bd(t, e) {
  let n;
  const r = {
    started: !1,
    text_content_index_and_output: null,
    refusal_content_index_and_output: null,
    function_calls: {},
    reasoning: "",
  };
  for await (const i of e) {
    if (
      (r.started ||
        ((r.started = !0),
        yield { type: "response_started", providerData: { ...i } }),
      yield { type: "model", event: i },
      (n = i.usage || void 0),
      !i.choices?.[0]?.delta)
    )
      continue;
    const c = i.choices[0].delta;
    if (
      (c.content &&
        (r.text_content_index_and_output ||
          (r.text_content_index_and_output = [
            r.refusal_content_index_and_output ? 1 : 0,
            {
              text: "",
              type: "output_text",
              providerData: { annotations: [] },
            },
          ]),
        yield {
          type: "output_text_delta",
          delta: c.content,
          providerData: { ...i },
        },
        (r.text_content_index_and_output[1].text += c.content)),
      "reasoning" in c &&
        c.reasoning &&
        typeof c.reasoning == "string" &&
        (r.reasoning += c.reasoning),
      "refusal" in c &&
        c.refusal &&
        (r.refusal_content_index_and_output ||
          (r.refusal_content_index_and_output = [
            r.text_content_index_and_output ? 1 : 0,
            { refusal: "", type: "refusal" },
          ]),
        (r.refusal_content_index_and_output[1].refusal += c.refusal)),
      c.tool_calls)
    )
      for (const u of c.tool_calls) {
        u.index in r.function_calls ||
          (r.function_calls[u.index] = {
            id: er,
            arguments: "",
            name: "",
            type: "function_call",
            callId: "",
          });
        const l = u.function;
        ((r.function_calls[u.index].arguments += l?.arguments || ""),
          (r.function_calls[u.index].name += l?.name || ""),
          (r.function_calls[u.index].callId += u.id || ""));
      }
  }
  const o = [];
  if (
    (r.reasoning &&
      o.push({
        type: "reasoning",
        content: [],
        rawContent: [{ type: "reasoning_text", text: r.reasoning }],
      }),
    r.text_content_index_and_output || r.refusal_content_index_and_output)
  ) {
    const i = {
      id: er,
      content: [],
      role: "assistant",
      type: "message",
      status: "completed",
    };
    (r.text_content_index_and_output &&
      i.content.push(r.text_content_index_and_output[1]),
      r.refusal_content_index_and_output &&
        i.content.push(r.refusal_content_index_and_output[1]),
      o.push(i));
  }
  for (const i of Object.values(r.function_calls)) o.push(i);
  yield {
    type: "response_done",
    response: {
      id: t.id,
      usage: {
        inputTokens: n?.prompt_tokens ?? 0,
        outputTokens: n?.completion_tokens ?? 0,
        totalTokens: n?.total_tokens ?? 0,
        inputTokensDetails: {
          cached_tokens: n?.prompt_tokens_details?.cached_tokens ?? 0,
        },
        outputTokensDetails: {
          reasoning_tokens: n?.completion_tokens_details?.reasoning_tokens ?? 0,
        },
      },
      output: o,
    },
  };
}
function xd(t) {
  if (!(t == null || t == null))
    return t === "auto" || t === "required" || t === "none"
      ? t
      : { type: "function", function: { name: t } };
}
function Id(t) {
  if (typeof t == "string") return t;
  const e = [];
  for (const n of t)
    if (n.type === "output_text")
      e.push({ type: "text", text: n.text, ...n.providerData });
    else if (n.type === "refusal")
      e.push({ type: "refusal", refusal: n.refusal, ...n.providerData });
    else {
      if (n.type === "audio" || n.type === "image") continue;
      {
        const r = n;
        throw new Error(`Unknown content: ${JSON.stringify(r)}`);
      }
    }
  return e;
}
function Ed(t) {
  if (typeof t == "string") return t;
  const e = [];
  for (const n of t)
    if (n.type === "input_text")
      e.push({ type: "text", text: n.text, ...n.providerData });
    else if (n.type === "input_image") {
      const r =
        typeof n.image == "string"
          ? n.image
          : typeof n.imageUrl == "string"
            ? n.imageUrl
            : void 0;
      if (!r)
        throw new Error(
          `Only image URLs are supported for input_image: ${JSON.stringify(n)}`,
        );
      const { image_url: o, ...s } = n.providerData || {};
      e.push({ type: "image_url", image_url: { url: r, ...o }, ...s });
    } else {
      if (n.type === "input_file")
        throw new Error(
          `File uploads are not supported for chat completions: ${JSON.stringify(n)}`,
        );
      if (n.type === "audio") {
        const { input_audio: r, ...o } = n.providerData || {};
        e.push({
          type: "input_audio",
          input_audio: { data: n.audio, ...r },
          ...o,
        });
      } else {
        const r = n;
        throw new Error(`Unknown content: ${JSON.stringify(r)}`);
      }
    }
  return e;
}
function Cd(t) {
  return (
    t.type === "message" || (typeof t.type > "u" && typeof t.role == "string")
  );
}
function Ad(t) {
  if (typeof t == "string") return [{ role: "user", content: t }];
  const e = [];
  let n = null;
  const r = () => {
      n &&
        ((!n.tool_calls || n.tool_calls.length === 0) && delete n.tool_calls,
        e.push(n),
        (n = null));
    },
    o = () => (n || (n = { role: "assistant", tool_calls: [] }), n);
  for (const s of t)
    if (Cd(s)) {
      const { content: i, role: c, providerData: u } = s;
      if ((r(), c === "assistant")) {
        const l = { role: "assistant", content: Id(i), ...u };
        if (Array.isArray(i)) {
          const d = i.find((g) => g.type === "audio");
          d && (l.audio = { id: "", ...d.providerData });
        }
        e.push(l);
      } else
        c === "user"
          ? e.push({ role: c, content: Ed(i), ...u })
          : c === "system" && e.push({ role: "system", content: i, ...u });
    } else if (s.type === "reasoning") {
      const i = o();
      i.reasoning = s.rawContent?.[0]?.text;
      continue;
    } else if (s.type === "hosted_tool_call")
      if (s.name === "file_search_call") {
        const i = o(),
          c = i.tool_calls ?? [],
          u = s,
          { function: l, ...d } = u.providerData ?? {},
          { arguments: g, ...f } = l ?? {};
        (c.push({
          id: u.id || "",
          type: "function",
          function: {
            name: "file_search_call",
            arguments: JSON.stringify({
              queries: u.providerData?.queries ?? [],
              status: u.status,
              ...g,
            }),
            ...f,
          },
          ...d,
        }),
          (i.tool_calls = c));
        continue;
      } else
        throw new G(
          "Hosted tool calls are not supported for chat completions. Got item: " +
            JSON.stringify(s),
        );
    else {
      if (s.type === "computer_call" || s.type === "computer_call_result")
        throw new G(
          "Computer use calls are not supported for chat completions. Got item: " +
            JSON.stringify(s),
        );
      if (s.type === "function_call") {
        const i = o(),
          c = i.tool_calls ?? [],
          u = s;
        (c.push({
          id: u.callId,
          type: "function",
          function: { name: u.name, arguments: u.arguments ?? "{}" },
        }),
          (i.tool_calls = c));
      } else if (s.type === "function_call_result") {
        r();
        const i = s,
          c = Dd(i.output);
        e.push({
          role: "tool",
          tool_call_id: i.callId,
          content: c,
          ...i.providerData,
        });
      } else if (s.type === "unknown") e.push({ ...s.providerData });
      else {
        const i = s;
        throw new Error(`Unknown item type: ${JSON.stringify(i)}`);
      }
    }
  return (r(), e);
}
function Dd(t) {
  if (typeof t == "string") return t;
  if (Array.isArray(t)) {
    if (!t.every((n) => n.type === "input_text"))
      throw new G("Only text tool outputs are supported for chat completions.");
    return t.map((n) => n.text).join("");
  }
  if (Od(t) && t.type === "text" && typeof t.text == "string") return t.text;
  throw new G(
    "Only text tool outputs are supported for chat completions. Got item: " +
      JSON.stringify(t),
  );
}
function Od(t) {
  return typeof t == "object" && t !== null;
}
function Rd(t) {
  if (t.type === "function")
    return {
      type: "function",
      function: {
        name: t.name,
        description: t.description || "",
        parameters: t.parameters,
        strict: t.strict,
      },
    };
  throw new Error(
    `Hosted tools are not supported with the ChatCompletions API. Got tool type: ${t.type}, tool: ${JSON.stringify(t)}`,
  );
}
function kd(t) {
  return {
    type: "function",
    function: {
      name: t.toolName,
      description: t.toolDescription || "",
      parameters: t.inputJsonSchema,
    },
  };
}
const er = "FAKE_ID";
function Nd(t) {
  return (
    "reasoning" in t && typeof t.reasoning == "string" && t.reasoning !== ""
  );
}
class $a {
  #e;
  #t;
  constructor(e, n) {
    ((this.#e = e), (this.#t = n));
  }
  async getResponse(e) {
    const n = await ra(async (s) => {
        ((s.spanData.model = this.#t),
          (s.spanData.model_config = e.modelSettings
            ? {
                temperature: e.modelSettings.temperature,
                top_p: e.modelSettings.topP,
                frequency_penalty: e.modelSettings.frequencyPenalty,
                presence_penalty: e.modelSettings.presencePenalty,
                reasoning_effort: e.modelSettings.reasoning?.effort,
                verbosity: e.modelSettings.text?.verbosity,
              }
            : { base_url: this.#e.baseURL }));
        const i = await this.#n(e, s, !1);
        return (s && e.tracing === !0 && (s.spanData.output = [i]), i);
      }),
      r = [];
    if (n.choices && n.choices[0]) {
      const s = n.choices[0].message;
      if (
        (Nd(s) &&
          r.push({
            type: "reasoning",
            content: [],
            rawContent: [{ type: "reasoning_text", text: s.reasoning }],
          }),
        s.content !== void 0 &&
          s.content !== null &&
          !(s.tool_calls && s.content === ""))
      ) {
        const { content: i, ...c } = s;
        r.push({
          id: n.id,
          type: "message",
          role: "assistant",
          content: [{ type: "output_text", text: i || "", providerData: c }],
          status: "completed",
        });
      } else if (s.refusal) {
        const { refusal: i, ...c } = s;
        r.push({
          id: n.id,
          type: "message",
          role: "assistant",
          content: [{ type: "refusal", refusal: i || "", providerData: c }],
          status: "completed",
        });
      } else if (s.audio) {
        const { data: i, ...c } = s.audio;
        r.push({
          id: n.id,
          type: "message",
          role: "assistant",
          content: [{ type: "audio", audio: i, providerData: c }],
          status: "completed",
        });
      } else if (s.tool_calls) {
        for (const i of s.tool_calls)
          if (i.type === "function") {
            const { id: c, ...u } = i,
              { arguments: l, name: d, ...g } = i.function;
            r.push({
              id: n.id,
              type: "function_call",
              arguments: l,
              name: d,
              callId: c,
              status: "completed",
              providerData: { ...u, ...g },
            });
          }
      }
    }
    return {
      usage: n.usage ? new Re(Pd(n.usage)) : new Re(),
      output: r,
      responseId: n.id,
      providerData: n,
    };
  }
  async *getStreamedResponse(e) {
    const n = e.tracing ? Br() : void 0;
    try {
      n && (n.start(), Ue(n));
      const r = await this.#n(e, n, !0),
        o = {
          id: er,
          created: Math.floor(Date.now() / 1e3),
          model: this.#t,
          object: "chat.completion",
          choices: [],
          usage: { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 },
        };
      for await (const s of bd(o, r)) yield s;
      n && o && e.tracing === !0 && (n.spanData.output = [o]);
    } catch (r) {
      throw (
        n &&
          n.setError({
            message: "Error streaming response",
            data: {
              error:
                e.tracing === !0
                  ? String(r)
                  : r instanceof Error
                    ? r.name
                    : void 0,
            },
          }),
        r
      );
    } finally {
      n && (n.end(), Ae());
    }
  }
  async #n(e, n, r) {
    const o = [];
    if (e.tools) for (const g of e.tools) o.push(Rd(g));
    if (e.handoffs) for (const g of e.handoffs) o.push(kd(g));
    const s = Ld(e.outputType);
    let i;
    if (typeof e.modelSettings.parallelToolCalls == "boolean") {
      if (e.modelSettings.parallelToolCalls && o.length === 0)
        throw new Error("Parallel tool calls are not supported without tools");
      i = e.modelSettings.parallelToolCalls;
    }
    const c = Ad(e.input);
    (e.systemInstructions &&
      c.unshift({ content: e.systemInstructions, role: "system" }),
      n && e.tracing === !0 && (n.spanData.input = c));
    const u = e.modelSettings.providerData ?? {};
    (e.modelSettings.reasoning &&
      e.modelSettings.reasoning.effort &&
      (u.reasoning_effort = e.modelSettings.reasoning.effort),
      e.modelSettings.text &&
        e.modelSettings.text.verbosity &&
        (u.verbosity = e.modelSettings.text.verbosity));
    const l = {
      model: this.#t,
      messages: c,
      tools: o.length ? o : void 0,
      temperature: e.modelSettings.temperature,
      top_p: e.modelSettings.topP,
      frequency_penalty: e.modelSettings.frequencyPenalty,
      presence_penalty: e.modelSettings.presencePenalty,
      max_tokens: e.modelSettings.maxTokens,
      tool_choice: xd(e.modelSettings.toolChoice),
      response_format: s,
      parallel_tool_calls: i,
      stream: r,
      store: e.modelSettings.store,
      ...u,
    };
    te.dontLogModelData
      ? te.debug("Calling LLM")
      : te.debug(`Calling LLM. Request data: ${JSON.stringify(l, null, 2)}`);
    const d = await this.#e.chat.completions.create(l, {
      headers: Hr,
      signal: e.signal,
    });
    return (
      te.dontLogModelData
        ? te.debug("Response received")
        : te.debug(`Response received: ${JSON.stringify(d, null, 2)}`),
      d
    );
  }
}
function Ld(t) {
  return t === "text"
    ? { type: "text" }
    : t.type === "json_schema"
      ? {
          type: "json_schema",
          json_schema: { name: t.name, strict: t.strict, schema: t.schema },
        }
      : { type: "json_object" };
}
function Pd(t) {
  return {
    requests: 1,
    input_tokens: t.prompt_tokens,
    output_tokens: t.completion_tokens,
    total_tokens: t.total_tokens,
    input_tokens_details: {
      cached_tokens: t.prompt_tokens_details?.cached_tokens || 0,
    },
    output_tokens_details: {
      reasoning_tokens: t.completion_tokens_details?.reasoning_tokens || 0,
    },
  };
}
class Ba {
  #e;
  #t;
  #n;
  constructor(e = {}) {
    if (((this.#n = e), this.#n.openAIClient)) {
      if (this.#n.apiKey)
        throw new Error("Cannot provide both apiKey and openAIClient");
      if (this.#n.baseURL)
        throw new Error("Cannot provide both baseURL and openAIClient");
      this.#e = this.#n.openAIClient;
    }
    this.#t = this.#n.useResponses;
  }
  #r() {
    return (
      this.#e ||
        (this.#e =
          Wl() ??
          new Tc({
            apiKey: this.#n.apiKey ?? Vl(),
            baseURL: this.#n.baseURL,
            organization: this.#n.organization,
            project: this.#n.project,
          })),
      this.#e
    );
  }
  async getModel(e) {
    const n = e || un();
    return (this.#t ?? Gl()) ? new Ua(this.#r(), n) : new $a(this.#r(), n);
  }
}
class ja {
  #e;
  constructor(e = {}) {
    this.#e = {
      apiKey: e.apiKey ?? void 0,
      organization: e.organization ?? "",
      project: e.project ?? "",
      endpoint: e.endpoint ?? "https://api.openai.com/v1/traces/ingest",
      maxRetries: e.maxRetries ?? 3,
      baseDelay: e.baseDelay ?? 1e3,
      maxDelay: e.maxDelay ?? 3e4,
    };
  }
  async export(e, n) {
    const r = this.#e.apiKey ?? ql();
    if (!r) {
      te.error(
        "No API key provided for OpenAI tracing exporter. Exports will be skipped",
      );
      return;
    }
    const o = { data: e.map((c) => c.toJSON()).filter((c) => !!c) };
    let s = 0,
      i = this.#e.baseDelay;
    for (; s < this.#e.maxRetries;) {
      try {
        const u = await fetch(this.#e.endpoint, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${r}`,
            "OpenAI-Beta": "traces=v1",
            ...Hr,
          },
          body: JSON.stringify(o),
          signal: n,
        });
        if (u.ok) {
          te.debug(`Exported ${o.data.length} items`);
          return;
        }
        if (u.status >= 400 && u.status < 500) {
          te.error(
            `[non-fatal] Tracing client error ${u.status}: ${await u.text()}`,
          );
          return;
        }
        te.warn(`[non-fatal] Tracing: server error ${u.status}, retrying.`);
      } catch (u) {
        te.error("[non-fatal] Tracing: request failed: ", u);
      }
      if (n?.aborted) {
        te.error("Tracing: request aborted");
        return;
      }
      const c = i + Math.random() * 0.1 * i;
      (await new Promise((u) => setTimeout(u, c)),
        (i = Math.min(i * 2, this.#e.maxDelay)),
        s++);
    }
    te.error(
      `Tracing: failed to export traces after ${this.#e.maxRetries} attempts`,
    );
  }
}
function qa() {
  const t = new ja(),
    e = new Gr(t);
  ka([e]);
}
const Ms = { version: "0.2.1" };
function Ga(t) {
  const e = atob(t),
    n = e.length,
    r = new Uint8Array(n);
  for (let o = 0; o < n; o++) r[o] = e.charCodeAt(o);
  return r.buffer;
}
function Ja(t) {
  const e = String.fromCharCode(...new Uint8Array(t));
  return btoa(e);
}
function Ha(t) {
  if (
    typeof t > "u" ||
    t === null ||
    typeof t != "object" ||
    !("type" in t) ||
    typeof t.type != "string" ||
    !t.type ||
    t.type !== "message" ||
    !("content" in t) ||
    !Array.isArray(t.content) ||
    t.content.length < 1
  )
    return;
  const e = t.content[t.content.length - 1];
  if (!(!("type" in e) || typeof e.type != "string")) {
    if (e.type === "output_text")
      return typeof e.text == "string" ? e.text : void 0;
    if (e.type === "output_audio")
      return typeof e.transcript == "string" ? e.transcript : void 0;
  }
}
function Md(t, e) {
  const n = t.filter((s) => !e.some((i) => i.itemId === s.itemId)),
    r = e.filter((s) => !t.some((i) => i.itemId === s.itemId)),
    o = e.filter((s) =>
      t.some(
        (i) => i.itemId === s.itemId && JSON.stringify(i) !== JSON.stringify(s),
      ),
    );
  return { removals: n, additions: r, updates: o };
}
function Fd() {
  return typeof window > "u" ? !1 : typeof window.RTCPeerConnection < "u";
}
function Fs(t) {
  return t.role === "system"
    ? t
    : t.role === "assistant"
      ? {
          ...t,
          content: t.content.map((e) =>
            e.type === "output_audio" ? { ...e, audio: null } : e,
          ),
        }
      : t.role === "user"
        ? {
            ...t,
            content: t.content.map((e) =>
              e.type === "input_audio" ? { ...e, audio: null } : e,
            ),
          }
        : t;
}
function Us(t, e, n) {
  if (e.type === "conversation.item.input_audio_transcription.completed")
    return t.map((s) => {
      if (
        s.itemId === e.item_id &&
        s.type === "message" &&
        "role" in s &&
        s.role === "user"
      ) {
        const i = s.content.map((c) =>
          c.type === "input_audio" ? { ...c, transcript: e.transcript } : c,
        );
        return { ...s, content: i, status: "completed" };
      }
      return s;
    });
  const r = !n && e.type === "message" ? Fs(e) : e,
    o = t.findIndex((s) => s.itemId === e.itemId);
  if (o !== -1)
    return t.map((s, i) =>
      i === o ? r : !n && s.type === "message" ? Fs(s) : s,
    );
  if (e.previousItemId) {
    const s = t.findIndex((i) => i.itemId === e.previousItemId);
    return s !== -1 ? [...t.slice(0, s + 1), r, ...t.slice(s + 1)] : [...t, r];
  } else return [...t, r];
}
const Wa = {
  "User-Agent": `Agents/JavaScript ${Ms.version}`,
  "X-OpenAI-Agents-SDK": `openai-agents-sdk.${Ms.version}`,
};
function Ud(t, e) {
  const { name: n, arguments: r, ...o } = e;
  return new ue(
    {
      type: "hosted_tool_call",
      name: n,
      arguments: JSON.stringify(r),
      status: "in_progress",
      providerData: { ...o },
    },
    t,
  );
}
function $s(t) {
  const { name: e, arguments: n, providerData: r } = t.rawItem,
    { itemId: o, serverLabel: s, ...i } = r ?? {};
  if (!o || !s)
    throw new Error("Invalid approval item for Realtime MCP approval request");
  return {
    type: "mcp_approval_request",
    itemId: o,
    serverLabel: s,
    ...i,
    name: e,
    arguments: n ? JSON.parse(n) : {},
    approved: null,
  };
}
class $d extends Se {
  voice;
  constructor(e) {
    (super(e), (this.voice = e.voice));
  }
}
function Bd(t) {
  return { debounceTextLength: t.debounceTextLength ?? 100 };
}
function jd({ policyHint: t, ...e }) {
  const n = zt(e),
    r = t ?? n.name;
  return {
    ...n,
    policyHint: r,
    run: async (o) => {
      const s = await n.run(o);
      return { ...s, guardrail: { ...s.guardrail, policyHint: r } };
    },
  };
}
function qd(t) {
  return `
⚠️ Your last answer was blocked. 
Failed Guardrail Reason: ${t.guardrail.policyHint}. 
Failure Details: ${JSON.stringify(t.output.outputInfo ?? {})}. 
Please respond again following policy. Apologize for not being able to answer the question (while avoiding the specific reason) and divert discussion back to an approved topic immediately and not invite more discussion.
`.trim();
}
function Pe(t, e) {
  return t in e && typeof e[t] < "u";
}
function Gd(t) {
  return (
    Pe("modalities", t) ||
    Pe("inputAudioFormat", t) ||
    Pe("outputAudioFormat", t) ||
    Pe("inputAudioTranscription", t) ||
    Pe("turnDetection", t) ||
    Pe("inputAudioNoiseReduction", t) ||
    Pe("speed", t)
  );
}
function Jd(t) {
  if (!Gd(t)) {
    const e = t.audio?.input
        ? {
            format: jt(t.audio.input.format),
            noiseReduction: t.audio.input.noiseReduction ?? null,
            transcription: t.audio.input.transcription,
            turnDetection: t.audio.input.turnDetection,
          }
        : void 0,
      n = t.audio?.output?.voice ?? t.voice,
      r =
        t.audio?.output || typeof n < "u"
          ? {
              format: jt(t.audio?.output?.format),
              voice: n,
              speed: t.audio?.output?.speed,
            }
          : void 0;
    return {
      model: t.model,
      instructions: t.instructions,
      toolChoice: t.toolChoice,
      tools: t.tools,
      tracing: t.tracing,
      providerData: t.providerData,
      prompt: t.prompt,
      outputModalities: t.outputModalities,
      audio: e || r ? { input: e, output: r } : void 0,
    };
  }
  return {
    model: t.model,
    instructions: t.instructions,
    toolChoice: t.toolChoice,
    tools: t.tools,
    tracing: t.tracing,
    providerData: t.providerData,
    prompt: t.prompt,
    outputModalities: t.modalities,
    audio: {
      input: {
        format: jt(t.inputAudioFormat),
        noiseReduction: t.inputAudioNoiseReduction ?? null,
        transcription: t.inputAudioTranscription,
        turnDetection: t.turnDetection,
      },
      output: {
        format: jt(t.outputAudioFormat),
        voice: t.voice,
        speed: t.speed,
      },
    },
  };
}
function jt(t) {
  if (!t) return;
  if (typeof t == "object") return t;
  const e = String(t);
  return e === "pcm16"
    ? { type: "audio/pcm", rate: 24e3 }
    : e === "g711_ulaw"
      ? { type: "audio/pcmu" }
      : e === "g711_alaw"
        ? { type: "audio/pcma" }
        : { type: "audio/pcm", rate: 24e3 };
}
h({ itemId: a() });
const Bs = se("role", [
    h({
      itemId: a(),
      previousItemId: a().nullable().optional(),
      type: y("message"),
      role: y("system"),
      content: U(h({ type: y("input_text"), text: a() })),
    }),
    h({
      itemId: a(),
      previousItemId: a().nullable().optional(),
      type: y("message"),
      role: y("user"),
      status: J(["in_progress", "completed"]),
      content: U(
        h({ type: y("input_text"), text: a() }).or(
          h({
            type: y("input_audio"),
            audio: a().nullable().optional(),
            transcript: a().nullable(),
          }),
        ),
      ),
    }),
    h({
      itemId: a(),
      previousItemId: a().nullable().optional(),
      type: y("message"),
      role: y("assistant"),
      status: J(["in_progress", "completed", "incomplete"]),
      content: U(
        h({ type: y("output_text"), text: a() }).or(
          h({
            type: y("output_audio"),
            audio: a().nullable().optional(),
            transcript: a().nullable().optional(),
          }),
        ),
      ),
    }),
  ]),
  js = h({
    itemId: a(),
    previousItemId: a().nullable().optional(),
    type: y("function_call"),
    status: J(["in_progress", "completed", "incomplete"]),
    arguments: a(),
    name: a(),
    output: a().nullable(),
  }),
  qs = h({
    itemId: a(),
    previousItemId: a().nullable().optional(),
    type: J(["mcp_call", "mcp_tool_call"]),
    status: J(["in_progress", "completed", "incomplete"]),
    arguments: a(),
    name: a(),
    output: a().nullable(),
  }),
  Hd = h({
    itemId: a(),
    type: y("mcp_approval_request"),
    serverLabel: a(),
    name: a(),
    arguments: Y(a(), j()),
    approved: X().optional().nullable(),
  }),
  pe = je("openai-agents:realtime"),
  za = h({
    id: a().optional().nullable(),
    conversation_id: a().optional().nullable(),
    max_output_tokens: R().or(y("inf")).optional().nullable(),
    metadata: Y(a(), j()).optional().nullable(),
    output_modalities: U(a()).optional().nullable(),
    object: y("realtime.response").optional().nullable(),
    output: U(j()).optional().nullable(),
    audio: h({
      output: h({
        format: j().optional().nullable(),
        voice: a().optional().nullable(),
      })
        .optional()
        .nullable(),
    })
      .optional()
      .nullable(),
    status: J(["completed", "incomplete", "failed", "cancelled", "in_progress"])
      .optional()
      .nullable(),
    status_details: Y(a(), j()).optional().nullable(),
    usage: h({
      input_tokens: R().optional(),
      input_token_details: Y(a(), j()).optional().nullable(),
      output_tokens: R().optional(),
      output_token_details: Y(a(), j()).optional().nullable(),
    })
      .optional()
      .nullable(),
  }),
  Wd = h({
    id: a().optional(),
    audio: a().nullable().optional(),
    text: a().nullable().optional(),
    transcript: a().nullable().optional(),
    type: Z([
      y("input_text"),
      y("input_audio"),
      y("item_reference"),
      y("output_text"),
      y("output_audio"),
    ]),
  }),
  at = h({
    id: a().optional(),
    arguments: a().optional(),
    call_id: a().optional(),
    content: U(Wd).optional(),
    name: a().optional(),
    output: a().nullable().optional(),
    role: J(["user", "assistant", "system"]).optional(),
    status: J(["completed", "incomplete", "in_progress"]).optional(),
    type: J([
      "message",
      "function_call",
      "function_call_output",
      "mcp_list_tools",
      "mcp_tool_call",
      "mcp_call",
      "mcp_approval_request",
      "mcp_approval_response",
    ]).optional(),
    approval_request_id: a().nullable().optional(),
    approve: X().nullable().optional(),
    reason: a().nullable().optional(),
    server_label: a().optional(),
    error: j().nullable().optional(),
    tools: U(
      h({
        name: a(),
        description: a(),
        input_schema: Y(j()).optional(),
      }).passthrough(),
    ).optional(),
  }).passthrough(),
  zd = h({
    type: y("conversation.created"),
    event_id: a(),
    conversation: h({
      id: a().optional(),
      object: y("realtime.conversation").optional(),
    }),
  }),
  Vd = h({
    type: y("conversation.item.added"),
    event_id: a(),
    item: at,
    previous_item_id: a().nullable().optional(),
  }),
  Kd = h({
    type: y("conversation.item.done"),
    event_id: a(),
    item: at,
    previous_item_id: a().nullable().optional(),
  }),
  Yd = h({ type: y("conversation.item.deleted"), event_id: a(), item_id: a() }),
  Zd = h({
    type: y("conversation.item.input_audio_transcription.completed"),
    event_id: a(),
    item_id: a(),
    content_index: R(),
    transcript: a(),
    logprobs: U(j()).nullable().optional(),
  }),
  Xd = h({
    type: y("conversation.item.input_audio_transcription.delta"),
    event_id: a(),
    item_id: a(),
    content_index: R().optional(),
    delta: a().optional(),
    logprobs: U(j()).nullable().optional(),
  }),
  Qd = h({
    type: y("conversation.item.input_audio_transcription.failed"),
    event_id: a(),
    item_id: a(),
    content_index: R(),
    error: h({
      code: a().optional(),
      message: a().optional(),
      param: a().optional(),
      type: a().optional(),
    }),
  }),
  ep = h({ type: y("conversation.item.retrieved"), event_id: a(), item: at }),
  tp = h({
    type: y("conversation.item.truncated"),
    event_id: a(),
    item_id: a(),
    audio_end_ms: R(),
    content_index: R(),
  }),
  np = h({
    type: y("conversation.item.create"),
    item: at,
    event_id: a().optional(),
    previous_item_id: a().nullable().optional(),
  }),
  rp = h({
    type: y("conversation.item.delete"),
    item_id: a(),
    event_id: a().optional(),
  }),
  sp = h({
    type: y("conversation.item.retrieve"),
    item_id: a(),
    event_id: a().optional(),
  }),
  op = h({
    type: y("conversation.item.truncate"),
    item_id: a(),
    audio_end_ms: R(),
    content_index: R(),
    event_id: a().optional(),
  }),
  ip = h({ type: y("error"), event_id: a().optional(), error: j().optional() }),
  ap = h({ type: y("input_audio_buffer.cleared"), event_id: a() }),
  cp = h({
    type: y("input_audio_buffer.append"),
    audio: a(),
    event_id: a().optional(),
  }),
  up = h({ type: y("input_audio_buffer.clear"), event_id: a().optional() }),
  lp = h({ type: y("input_audio_buffer.commit"), event_id: a().optional() }),
  dp = h({
    type: y("input_audio_buffer.committed"),
    event_id: a(),
    item_id: a(),
    previous_item_id: a().nullable().optional(),
  }),
  pp = h({
    type: y("input_audio_buffer.speech_started"),
    event_id: a(),
    item_id: a(),
    audio_start_ms: R(),
  }),
  fp = h({
    type: y("input_audio_buffer.speech_stopped"),
    event_id: a(),
    item_id: a(),
    audio_end_ms: R(),
  }),
  hp = h({
    type: y("output_audio_buffer.started"),
    event_id: a(),
  }).passthrough(),
  mp = h({
    type: y("output_audio_buffer.stopped"),
    event_id: a(),
  }).passthrough(),
  _p = h({ type: y("output_audio_buffer.cleared"), event_id: a() }),
  gp = h({
    type: y("rate_limits.updated"),
    event_id: a(),
    rate_limits: U(
      h({
        limit: R().optional(),
        name: J(["requests", "tokens"]).optional(),
        remaining: R().optional(),
        reset_seconds: R().optional(),
      }),
    ),
  }),
  yp = h({
    type: y("response.output_audio.delta"),
    event_id: a(),
    item_id: a(),
    content_index: R(),
    delta: a(),
    output_index: R(),
    response_id: a(),
  }),
  vp = h({
    type: y("response.output_audio.done"),
    event_id: a(),
    item_id: a(),
    content_index: R(),
    output_index: R(),
    response_id: a(),
  }),
  Sp = h({
    type: y("response.output_audio_transcript.delta"),
    event_id: a(),
    item_id: a(),
    content_index: R(),
    delta: a(),
    output_index: R(),
    response_id: a(),
  }),
  wp = h({
    type: y("response.output_audio_transcript.done"),
    event_id: a(),
    item_id: a(),
    content_index: R(),
    transcript: a(),
    output_index: R(),
    response_id: a(),
  }),
  Tp = h({
    type: y("response.content_part.added"),
    event_id: a(),
    item_id: a(),
    content_index: R(),
    output_index: R(),
    response_id: a(),
    part: h({
      audio: a().optional(),
      text: a().optional(),
      transcript: a().optional(),
      type: J(["text", "audio"]).optional(),
    }),
  }),
  bp = h({
    type: y("response.content_part.done"),
    event_id: a(),
    item_id: a(),
    content_index: R(),
    output_index: R(),
    response_id: a(),
    part: h({
      audio: a().optional(),
      text: a().optional(),
      transcript: a().optional(),
      type: J(["text", "audio"]).optional(),
    }),
  }),
  xp = h({ type: y("response.created"), event_id: a(), response: za }),
  Va = h({ type: y("response.done"), event_id: a(), response: za }),
  Ip = h({
    type: y("response.function_call_arguments.delta"),
    event_id: a(),
    item_id: a(),
    call_id: a(),
    delta: a(),
    output_index: R(),
    response_id: a(),
  }),
  Ep = h({
    type: y("response.function_call_arguments.done"),
    event_id: a(),
    item_id: a(),
    call_id: a(),
    arguments: a(),
    output_index: R(),
    response_id: a(),
  }),
  Cp = h({
    type: y("response.output_item.added"),
    event_id: a(),
    item: at,
    output_index: R(),
    response_id: a(),
  }),
  Ap = h({
    type: y("response.output_item.done"),
    event_id: a(),
    item: at,
    output_index: R(),
    response_id: a(),
  }),
  Dp = h({
    type: y("response.output_text.delta"),
    event_id: a(),
    item_id: a(),
    content_index: R(),
    delta: a(),
    output_index: R(),
    response_id: a(),
  }),
  Op = h({
    type: y("response.output_text.done"),
    event_id: a(),
    item_id: a(),
    content_index: R(),
    text: a(),
    output_index: R(),
    response_id: a(),
  }),
  Rp = h({ type: y("session.created"), event_id: a(), session: j() }),
  kp = h({ type: y("session.updated"), event_id: a(), session: j() }),
  Np = h({
    type: y("response.cancel"),
    event_id: a().optional(),
    response_id: a().optional(),
  }),
  Lp = h({
    type: y("response.create"),
    event_id: a().optional(),
    response: j().optional(),
  }),
  Pp = h({ type: y("session.update"), event_id: a().optional(), session: j() }),
  Mp = h({
    type: y("mcp_list_tools.in_progress"),
    event_id: a().optional(),
    item_id: a().optional(),
  }),
  Fp = h({
    type: y("mcp_list_tools.completed"),
    event_id: a().optional(),
    item_id: a().optional(),
  }),
  Up = h({
    type: y("response.mcp_call_arguments.delta"),
    event_id: a(),
    response_id: a(),
    item_id: a(),
    output_index: R(),
    delta: a(),
    obfuscation: a(),
  }),
  $p = h({
    type: y("response.mcp_call_arguments.done"),
    event_id: a(),
    response_id: a(),
    item_id: a(),
    output_index: R(),
    arguments: a(),
  }),
  Bp = h({
    type: y("response.mcp_call.in_progress"),
    event_id: a(),
    output_index: R(),
    item_id: a(),
  }),
  jp = h({
    type: y("response.mcp_call.completed"),
    event_id: a(),
    output_index: R(),
    item_id: a(),
  }),
  qp = h({
    type: y("mcp_list_tools.failed"),
    event_id: a().optional(),
    item_id: a().optional(),
  }),
  Gp = h({ type: a(), event_id: a().optional().nullable() }).passthrough(),
  Jp = se("type", [
    zd,
    Vd,
    Kd,
    Yd,
    Zd,
    Xd,
    Qd,
    ep,
    tp,
    ip,
    ap,
    dp,
    pp,
    fp,
    hp,
    mp,
    _p,
    gp,
    yp,
    vp,
    Sp,
    wp,
    Tp,
    bp,
    xp,
    Va,
    Ip,
    Ep,
    Cp,
    Ap,
    Dp,
    Op,
    Rp,
    kp,
    Mp,
    Fp,
    qp,
    Up,
    $p,
    Bp,
    jp,
  ]);
se("type", [np, rp, sp, op, cp, up, lp, Np, Lp, Pp]);
function Wr(t) {
  const e = JSON.parse(t.data.toString()),
    n = Jp.safeParse(e);
  if (!n.success) {
    const r = Gp.safeParse(e);
    return r.success
      ? { data: r.data, isGeneric: !0 }
      : { data: null, isGeneric: !0 };
  }
  return { data: n.data, isGeneric: !1 };
}
const Ka = "gpt-realtime",
  _e = {
    outputModalities: ["audio"],
    audio: {
      input: {
        format: { type: "audio/pcm", rate: 24e3 },
        transcription: { model: "gpt-4o-mini-transcribe" },
        turnDetection: { type: "semantic_vad" },
        noiseReduction: null,
      },
      output: { format: { type: "audio/pcm", rate: 24e3 }, speed: 1 },
    },
  };
class kt extends Er {
  #e;
  #t;
  #n = null;
  #r = null;
  eventEmitter = new wt();
  constructor(e = {}) {
    (super(), (this.#e = e.model ?? Ka), (this.#t = e.apiKey));
  }
  get currentModel() {
    return this.#e;
  }
  set currentModel(e) {
    this.#e = e;
  }
  get _rawSessionConfig() {
    return this.#r ?? null;
  }
  async _getApiKey(e) {
    const n = e.apiKey ?? this.#t;
    return typeof n == "function" ? await n() : n;
  }
  _onMessage(e) {
    const { data: n, isGeneric: r } = Wr(e);
    if (n !== null && (this.emit("*", n), !r)) {
      if (
        (n.type === "error"
          ? this.emit("error", { type: "error", error: n })
          : this.emit(n.type, n),
        n.type === "response.created")
      ) {
        this.emit("turn_started", {
          type: "response_started",
          providerData: { ...n },
        });
        return;
      }
      if (
        (n.type === "session.updated" && (this.#r = n.session),
        n.type === "response.done")
      ) {
        const o = Va.safeParse(n);
        if (!o.success) {
          pe.error("Error parsing response done event", o.error);
          return;
        }
        const s = o.data.response.usage?.input_tokens ?? 0,
          i = o.data.response.usage?.output_tokens ?? 0,
          c = s + i,
          u = new Re({
            inputTokens: s,
            inputTokensDetails:
              o.data.response.usage?.input_token_details ?? {},
            outputTokens: i,
            outputTokensDetails:
              o.data.response.usage?.output_token_details ?? {},
            totalTokens: c,
          });
        (this.emit("usage_update", u),
          this.emit("turn_done", {
            type: "response_done",
            response: {
              id: o.data.response.id ?? "",
              output: o.data.response.output ?? [],
              usage: {
                inputTokens: s,
                inputTokensDetails:
                  o.data.response.usage?.input_token_details ?? {},
                outputTokens: i,
                outputTokensDetails:
                  o.data.response.usage?.output_token_details ?? {},
                totalTokens: c,
              },
            },
          }));
        return;
      }
      if (n.type === "response.output_audio.done") {
        this.emit("audio_done");
        return;
      }
      if (n.type === "conversation.item.deleted") {
        this.emit("item_deleted", { itemId: n.item_id });
        return;
      }
      if (
        n.type === "conversation.item.input_audio_transcription.completed" ||
        n.type === "conversation.item.truncated"
      ) {
        this.sendEvent({
          type: "conversation.item.retrieve",
          item_id: n.item_id,
        });
        return;
      }
      if (
        n.type === "conversation.item.input_audio_transcription.delta" ||
        n.type === "response.output_text.delta" ||
        n.type === "response.output_audio_transcript.delta" ||
        n.type === "response.function_call_arguments.delta"
      ) {
        n.type === "response.output_audio_transcript.delta" &&
          this.emit("audio_transcript_delta", {
            type: "transcript_delta",
            delta: n.delta,
            itemId: n.item_id,
            responseId: n.response_id,
          });
        return;
      }
      if (
        n.type === "conversation.item.added" ||
        n.type === "conversation.item.done" ||
        n.type === "conversation.item.retrieved"
      ) {
        if (
          n.item.type === "mcp_list_tools" &&
          n.type === "conversation.item.done"
        ) {
          const o = n.item.server_label ?? "",
            s = n.item.tools ?? [];
          try {
            this.emit("mcp_tools_listed", { serverLabel: o, tools: s });
          } catch (i) {
            pe.error("Error emitting mcp_tools_listed", i, n.item);
          }
          return;
        }
        if (n.item.type === "message") {
          const o =
              n.type === "conversation.item.added" ||
              n.type === "conversation.item.done"
                ? n.previous_item_id
                : null,
            s = Bs.parse({
              itemId: n.item.id,
              previousItemId: o,
              type: n.item.type,
              role: n.item.role,
              content: n.item.content,
              status: n.item.status,
            });
          this.emit("item_update", s);
          return;
        }
        if (
          n.item.type === "mcp_approval_request" &&
          n.type === "conversation.item.done"
        ) {
          const o = n.item,
            s = Hd.parse({
              itemId: o.id,
              type: o.type,
              serverLabel: o.server_label,
              name: o.name,
              arguments: JSON.parse(o.arguments || "{}"),
              approved: o.approved,
            });
          (this.emit("item_update", s), this.emit("mcp_approval_request", s));
          return;
        }
        if (n.item.type === "mcp_tool_call" || n.item.type === "mcp_call") {
          const o =
              n.type === "conversation.item.done" ? "completed" : "in_progress",
            s = qs.parse({
              itemId: n.item.id,
              type: n.item.type,
              status: o,
              arguments: n.item.arguments,
              name: n.item.name,
              output: n.item.output,
            });
          (this.emit("item_update", s),
            n.type === "conversation.item.done" &&
              this.emit("mcp_tool_call_completed", s));
          return;
        }
      }
      if (n.type === "response.mcp_call.in_progress") {
        const o = n;
        this.sendEvent({
          type: "conversation.item.retrieve",
          item_id: o.item_id,
        });
        return;
      }
      if (n.type === "mcp_list_tools.in_progress") {
        const o = n;
        o.item_id &&
          this.sendEvent({
            type: "conversation.item.retrieve",
            item_id: o.item_id,
          });
        return;
      }
      if (
        n.type === "response.output_item.done" ||
        n.type === "response.output_item.added"
      ) {
        const o = n.item;
        if (o.type === "function_call" && o.status === "completed") {
          const s = js.parse({
            itemId: o.id,
            type: o.type,
            status: "in_progress",
            arguments: o.arguments,
            name: o.name,
            output: null,
          });
          (this.emit("item_update", s),
            this.emit("function_call", {
              id: o.id,
              type: "function_call",
              callId: o.call_id ?? "",
              arguments: o.arguments ?? "",
              name: o.name ?? "",
            }));
          return;
        }
        if (o.type === "mcp_tool_call" || o.type === "mcp_call") {
          const s = qs.parse({
            itemId: o.id,
            type: o.type,
            status:
              n.type === "response.output_item.done"
                ? "completed"
                : "in_progress",
            arguments: o.arguments,
            name: o.name,
            output: o.output,
          });
          this.emit("item_update", s);
          return;
        }
        if (o.type === "message") {
          const s = Bs.parse({
            itemId: n.item.id,
            type: n.item.type,
            role: n.item.role,
            content: n.item.content,
            status:
              n.type === "response.output_item.done"
                ? (o.status ?? "completed")
                : (o.status ?? "in_progress"),
          });
          this.emit("item_update", s);
          return;
        }
      }
    }
  }
  _onError(e) {
    this.emit("error", { type: "error", error: e });
  }
  _onOpen() {
    this.emit("connected");
  }
  _onClose() {
    this.emit("disconnected");
  }
  sendMessage(e, n, { triggerResponse: r = !0 } = {}) {
    const o =
      typeof e == "string"
        ? [{ type: "input_text", text: e }]
        : e.content.map((s) =>
            s.type === "input_image"
              ? {
                  type: "input_image",
                  image_url: s.image,
                  ...(s.providerData ?? {}),
                }
              : s,
          );
    (this.sendEvent({
      type: "conversation.item.create",
      item: { type: "message", role: "user", content: o },
      ...n,
    }),
      r && this.sendEvent({ type: "response.create" }));
  }
  addImage(e, { triggerResponse: n = !0 } = {}) {
    this.sendMessage(
      {
        type: "message",
        role: "user",
        content: [{ type: "input_image", image: e }],
      },
      {},
      { triggerResponse: n },
    );
  }
  _getMergedSessionConfig(e) {
    const n = Jd(e),
      r = {
        type: "realtime",
        instructions: n.instructions,
        model: n.model ?? this.#e,
        output_modalities: n.outputModalities ?? _e.outputModalities,
        audio: {
          input: {
            format: n.audio?.input?.format ?? _e.audio?.input?.format,
            noise_reduction:
              n.audio?.input?.noiseReduction ?? _e.audio?.input?.noiseReduction,
            transcription:
              n.audio?.input?.transcription ?? _e.audio?.input?.transcription,
            turn_detection:
              kt.buildTurnDetectionConfig(n.audio?.input?.turnDetection) ??
              _e.audio?.input?.turnDetection,
          },
          output: {
            format: n.audio?.output?.format ?? _e.audio?.output?.format,
            voice: n.audio?.output?.voice ?? _e.audio?.output?.voice,
            speed: n.audio?.output?.speed ?? _e.audio?.output?.speed,
          },
        },
        tool_choice: n.toolChoice ?? _e.toolChoice,
        ...(n.providerData ?? {}),
      };
    return (
      n.prompt &&
        (r.prompt = {
          id: n.prompt.promptId,
          version: n.prompt.version,
          variables: n.prompt.variables,
        }),
      n.tools &&
        n.tools.length > 0 &&
        (r.tools = n.tools.map((o) => ({ ...o, strict: void 0 }))),
      r
    );
  }
  static buildTurnDetectionConfig(e) {
    if (typeof e > "u") return;
    const {
        type: n,
        createResponse: r,
        create_response: o,
        eagerness: s,
        interruptResponse: i,
        interrupt_response: c,
        prefixPaddingMs: u,
        prefix_padding_ms: l,
        silenceDurationMs: d,
        silence_duration_ms: g,
        threshold: f,
        idleTimeoutMs: v,
        idle_timeout_ms: _,
        ...w
      } = e,
      E = {
        type: n,
        create_response: r || o,
        eagerness: s,
        interrupt_response: i || c,
        prefix_padding_ms: u || l,
        silence_duration_ms: d || g,
        idle_timeout_ms: v || _,
        threshold: f,
        ...w,
      };
    return (
      Object.keys(E).forEach((b) => {
        E[b] === void 0 && delete E[b];
      }),
      Object.keys(E).length > 0 ? E : void 0
    );
  }
  set _tracingConfig(e) {
    this.#n = e;
  }
  _updateTracingConfig(e) {
    if ((typeof this.#n > "u" && (this.#n = null), e === "auto")) {
      this.sendEvent({
        type: "session.update",
        session: { type: "realtime", tracing: "auto" },
      });
      return;
    }
    if (
      this.#n !== null &&
      typeof this.#n != "string" &&
      typeof e != "string"
    ) {
      pe.warn(
        "Tracing config is already set, skipping setting it again. This likely happens when you already set a tracing config on session creation.",
      );
      return;
    }
    if (e === null) {
      (pe.debug(
        "Disabling tracing for this session. It cannot be turned on for this session from this point on.",
      ),
        this.sendEvent({
          type: "session.update",
          session: { type: "realtime", tracing: null },
        }));
      return;
    }
    if (this.#n === null || typeof this.#n == "string") {
      this.sendEvent({
        type: "session.update",
        session: { type: "realtime", tracing: e },
      });
      return;
    }
    if (
      e?.group_id !== this.#n?.group_id ||
      e?.metadata !== this.#n?.metadata ||
      e?.workflow_name !== this.#n?.workflow_name
    ) {
      pe.warn(
        "Mismatch in tracing config. Ignoring the new tracing config. This likely happens when you already set a tracing config on session creation. Current tracing config: %s, new tracing config: %s",
        JSON.stringify(this.#n),
        JSON.stringify(e),
      );
      return;
    }
    this.sendEvent({
      type: "session.update",
      session: { type: "realtime", tracing: e },
    });
  }
  updateSessionConfig(e) {
    const n = this._getMergedSessionConfig(e);
    this.sendEvent({ type: "session.update", session: n });
  }
  sendFunctionCallOutput(e, n, r = !0) {
    this.sendEvent({
      type: "conversation.item.create",
      item: { type: "function_call_output", output: n, call_id: e.callId },
    });
    try {
      const o = js.parse({
        itemId: e.id,
        previousItemId: e.previousItemId,
        type: "function_call",
        status: "completed",
        arguments: e.arguments,
        name: e.name,
        output: n,
      });
      this.emit("item_update", o);
    } catch (o) {
      pe.error("Error parsing tool call item", o, e);
    }
    r && this.sendEvent({ type: "response.create" });
  }
  sendAudio(e, { commit: n = !1 } = {}) {
    (this.sendEvent({ type: "input_audio_buffer.append", audio: Ja(e) }),
      n && this.sendEvent({ type: "input_audio_buffer.commit" }));
  }
  resetHistory(e, n) {
    const { removals: r, additions: o, updates: s } = Md(e, n),
      i = new Set(r.map((u) => u.itemId));
    for (const u of s) i.add(u.itemId);
    if (i.size > 0)
      for (const u of i)
        this.sendEvent({ type: "conversation.item.delete", item_id: u });
    const c = [...o, ...s];
    for (const u of c)
      if (u.type === "message") {
        const l = {
          type: "message",
          role: u.role,
          content: u.content,
          id: u.itemId,
        };
        (u.role !== "system" && u.status && (l.status = u.status),
          this.sendEvent({ type: "conversation.item.create", item: l }));
      } else
        u.type === "function_call" &&
          pe.warn(
            "Function calls cannot be manually added or updated at the moment. Ignoring.",
          );
  }
  sendMcpResponse(e, n) {
    this.sendEvent({
      type: "conversation.item.create",
      previous_item_id: e.itemId,
      item: {
        type: "mcp_approval_response",
        approval_request_id: e.itemId,
        approve: n,
      },
    });
  }
}
class Ya extends kt {
  options;
  #e;
  #t = {
    status: "disconnected",
    peerConnection: void 0,
    dataChannel: void 0,
    callId: void 0,
  };
  #n;
  #r = !1;
  #i = !1;
  constructor(e = {}) {
    if (typeof RTCPeerConnection > "u")
      throw new Error("WebRTC is not supported in this environment");
    (super(e),
      (this.options = e),
      (this.#e = e.baseUrl ?? "https://api.openai.com/v1/realtime/calls"),
      (this.#n = e.useInsecureApiKey ?? !1));
  }
  get callId() {
    return this.#t.callId;
  }
  get status() {
    return this.#t.status;
  }
  get connectionState() {
    return this.#t;
  }
  get muted() {
    return this.#i;
  }
  async connect(e) {
    if (this.#t.status === "connected") return;
    this.#t.status === "connecting" &&
      pe.warn(
        "Realtime connection already in progress. Please await original promise",
      );
    const n = e.model ?? this.currentModel;
    this.currentModel = n;
    const r = e.url ?? this.#e,
      o = await this._getApiKey(e);
    return (
      typeof o == "string" && o.startsWith("ek_"),
      new Promise(async (s, i) => {
        try {
          const c = {
              ...(e.initialSessionConfig || {}),
              model: this.currentModel,
            },
            u = new URL(r);
          let l = new RTCPeerConnection();
          const d = l.createDataChannel("oai-events");
          let g;
          ((this.#t = {
            status: "connecting",
            peerConnection: l,
            dataChannel: d,
            callId: g,
          }),
            this.emit("connection_change", this.#t.status),
            d.addEventListener("open", () => {
              ((this.#t = {
                status: "connected",
                peerConnection: l,
                dataChannel: d,
                callId: g,
              }),
                this.updateSessionConfig(c),
                this.emit("connection_change", this.#t.status),
                this._onOpen(),
                s());
            }),
            d.addEventListener("error", (b) => {
              (this.close(), this._onError(b), i(b));
            }),
            d.addEventListener("message", (b) => {
              this._onMessage(b);
              const { data: I, isGeneric: O } = Wr(b);
              !I ||
                O ||
                (I.type === "response.created"
                  ? (this.#r = !0)
                  : I.type === "response.done" && (this.#r = !1),
                I.type === "session.created" &&
                  ((this._tracingConfig = I.session.tracing),
                  this._updateTracingConfig(c.tracing ?? "auto")));
            }));
          const f =
            this.options.audioElement ?? document.createElement("audio");
          ((f.autoplay = !0),
            (l.ontrack = (b) => {
              f.srcObject = b.streams[0];
            }));
          const v =
            this.options.mediaStream ??
            (await navigator.mediaDevices.getUserMedia({ audio: !0 }));
          (l.addTrack(v.getAudioTracks()[0]),
            this.options.changePeerConnection &&
              ((l = await this.options.changePeerConnection(l)),
              (this.#t = { ...this.#t, peerConnection: l })));
          const _ = await l.createOffer();
          if ((await l.setLocalDescription(_), !_.sdp))
            throw new Error("Failed to create offer");
          const w = await fetch(u, {
            method: "POST",
            body: _.sdp,
            headers: {
              "Content-Type": "application/sdp",
              Authorization: `Bearer ${o}`,
              "X-OpenAI-Agents-SDK": Wa["X-OpenAI-Agents-SDK"],
            },
          });
          ((g = w.headers?.get("Location")?.split("/").pop()),
            (this.#t = { ...this.#t, callId: g }));
          const E = { type: "answer", sdp: await w.text() };
          await l.setRemoteDescription(E);
        } catch (c) {
          (this.close(), this._onError(c), i(c));
        }
      })
    );
  }
  sendEvent(e) {
    if (!this.#t.dataChannel || this.#t.dataChannel.readyState !== "open")
      throw new Error(
        "WebRTC data channel is not connected. Make sure you call `connect()` before sending events.",
      );
    this.#t.dataChannel.send(JSON.stringify(e));
  }
  mute(e) {
    ((this.#i = e),
      this.#t.peerConnection &&
        this.#t.peerConnection.getSenders().forEach((r) => {
          r.track && (r.track.enabled = !e);
        }));
  }
  close() {
    if (
      (this.#t.dataChannel && this.#t.dataChannel.close(),
      this.#t.peerConnection)
    ) {
      const e = this.#t.peerConnection;
      (e.getSenders().forEach((n) => {
        n.track?.stop();
      }),
        e.close());
    }
    this.#t.status !== "disconnected" &&
      ((this.#t = {
        status: "disconnected",
        peerConnection: void 0,
        dataChannel: void 0,
        callId: void 0,
      }),
      this.emit("connection_change", this.#t.status),
      this._onClose());
  }
  interrupt() {
    (this.#r && (this.sendEvent({ type: "response.cancel" }), (this.#r = !1)),
      this.sendEvent({ type: "output_audio_buffer.clear" }));
  }
}
var ft = { exports: {} },
  On,
  Gs;
function Ne() {
  if (Gs) return On;
  Gs = 1;
  const t = ["nodebuffer", "arraybuffer", "fragments"],
    e = typeof Blob < "u";
  return (
    e && t.push("blob"),
    (On = {
      BINARY_TYPES: t,
      EMPTY_BUFFER: Buffer.alloc(0),
      GUID: "258EAFA5-E914-47DA-95CA-C5AB0DC85B11",
      hasBlob: e,
      kForOnEventAttribute: Symbol("kIsForOnEventAttribute"),
      kListener: Symbol("kListener"),
      kStatusCode: Symbol("status-code"),
      kWebSocket: Symbol("websocket"),
      NOOP: () => {},
    }),
    On
  );
}
var Js;
function gn() {
  if (Js) return ft.exports;
  Js = 1;
  const { EMPTY_BUFFER: t } = Ne(),
    e = Buffer[Symbol.species];
  function n(c, u) {
    if (c.length === 0) return t;
    if (c.length === 1) return c[0];
    const l = Buffer.allocUnsafe(u);
    let d = 0;
    for (let g = 0; g < c.length; g++) {
      const f = c[g];
      (l.set(f, d), (d += f.length));
    }
    return d < u ? new e(l.buffer, l.byteOffset, d) : l;
  }
  function r(c, u, l, d, g) {
    for (let f = 0; f < g; f++) l[d + f] = c[f] ^ u[f & 3];
  }
  function o(c, u) {
    for (let l = 0; l < c.length; l++) c[l] ^= u[l & 3];
  }
  function s(c) {
    return c.length === c.buffer.byteLength
      ? c.buffer
      : c.buffer.slice(c.byteOffset, c.byteOffset + c.length);
  }
  function i(c) {
    if (((i.readOnly = !0), Buffer.isBuffer(c))) return c;
    let u;
    return (
      c instanceof ArrayBuffer
        ? (u = new e(c))
        : ArrayBuffer.isView(c)
          ? (u = new e(c.buffer, c.byteOffset, c.byteLength))
          : ((u = Buffer.from(c)), (i.readOnly = !1)),
      u
    );
  }
  if (
    ((ft.exports = {
      concat: n,
      mask: r,
      toArrayBuffer: s,
      toBuffer: i,
      unmask: o,
    }),
    !process.env.WS_NO_BUFFER_UTIL)
  )
    try {
      const c = io("bufferutil");
      ((ft.exports.mask = function (u, l, d, g, f) {
        f < 48 ? r(u, l, d, g, f) : c.mask(u, l, d, g, f);
      }),
        (ft.exports.unmask = function (u, l) {
          u.length < 32 ? o(u, l) : c.unmask(u, l);
        }));
    } catch {}
  return ft.exports;
}
var Rn, Hs;
function Hp() {
  if (Hs) return Rn;
  Hs = 1;
  const t = Symbol("kDone"),
    e = Symbol("kRun");
  class n {
    constructor(o) {
      ((this[t] = () => {
        (this.pending--, this[e]());
      }),
        (this.concurrency = o || 1 / 0),
        (this.jobs = []),
        (this.pending = 0));
    }
    add(o) {
      (this.jobs.push(o), this[e]());
    }
    [e]() {
      if (this.pending !== this.concurrency && this.jobs.length) {
        const o = this.jobs.shift();
        (this.pending++, o(this[t]));
      }
    }
  }
  return ((Rn = n), Rn);
}
var kn, Ws;
function yn() {
  if (Ws) return kn;
  Ws = 1;
  const t = Cc,
    e = gn(),
    n = Hp(),
    { kStatusCode: r } = Ne(),
    o = Buffer[Symbol.species],
    s = Buffer.from([0, 0, 255, 255]),
    i = Symbol("permessage-deflate"),
    c = Symbol("total-length"),
    u = Symbol("callback"),
    l = Symbol("buffers"),
    d = Symbol("error");
  let g;
  class f {
    constructor(b, I, O) {
      if (
        ((this._maxPayload = O | 0),
        (this._options = b || {}),
        (this._threshold =
          this._options.threshold !== void 0 ? this._options.threshold : 1024),
        (this._isServer = !!I),
        (this._deflate = null),
        (this._inflate = null),
        (this.params = null),
        !g)
      ) {
        const C =
          this._options.concurrencyLimit !== void 0
            ? this._options.concurrencyLimit
            : 10;
        g = new n(C);
      }
    }
    static get extensionName() {
      return "permessage-deflate";
    }
    offer() {
      const b = {};
      return (
        this._options.serverNoContextTakeover &&
          (b.server_no_context_takeover = !0),
        this._options.clientNoContextTakeover &&
          (b.client_no_context_takeover = !0),
        this._options.serverMaxWindowBits &&
          (b.server_max_window_bits = this._options.serverMaxWindowBits),
        this._options.clientMaxWindowBits
          ? (b.client_max_window_bits = this._options.clientMaxWindowBits)
          : this._options.clientMaxWindowBits == null &&
            (b.client_max_window_bits = !0),
        b
      );
    }
    accept(b) {
      return (
        (b = this.normalizeParams(b)),
        (this.params = this._isServer
          ? this.acceptAsServer(b)
          : this.acceptAsClient(b)),
        this.params
      );
    }
    cleanup() {
      if (
        (this._inflate && (this._inflate.close(), (this._inflate = null)),
        this._deflate)
      ) {
        const b = this._deflate[u];
        (this._deflate.close(),
          (this._deflate = null),
          b &&
            b(
              new Error(
                "The deflate stream was closed while data was being processed",
              ),
            ));
      }
    }
    acceptAsServer(b) {
      const I = this._options,
        O = b.find(
          (C) =>
            !(
              (I.serverNoContextTakeover === !1 &&
                C.server_no_context_takeover) ||
              (C.server_max_window_bits &&
                (I.serverMaxWindowBits === !1 ||
                  (typeof I.serverMaxWindowBits == "number" &&
                    I.serverMaxWindowBits > C.server_max_window_bits))) ||
              (typeof I.clientMaxWindowBits == "number" &&
                !C.client_max_window_bits)
            ),
        );
      if (!O) throw new Error("None of the extension offers can be accepted");
      return (
        I.serverNoContextTakeover && (O.server_no_context_takeover = !0),
        I.clientNoContextTakeover && (O.client_no_context_takeover = !0),
        typeof I.serverMaxWindowBits == "number" &&
          (O.server_max_window_bits = I.serverMaxWindowBits),
        typeof I.clientMaxWindowBits == "number"
          ? (O.client_max_window_bits = I.clientMaxWindowBits)
          : (O.client_max_window_bits === !0 || I.clientMaxWindowBits === !1) &&
            delete O.client_max_window_bits,
        O
      );
    }
    acceptAsClient(b) {
      const I = b[0];
      if (
        this._options.clientNoContextTakeover === !1 &&
        I.client_no_context_takeover
      )
        throw new Error('Unexpected parameter "client_no_context_takeover"');
      if (!I.client_max_window_bits)
        typeof this._options.clientMaxWindowBits == "number" &&
          (I.client_max_window_bits = this._options.clientMaxWindowBits);
      else if (
        this._options.clientMaxWindowBits === !1 ||
        (typeof this._options.clientMaxWindowBits == "number" &&
          I.client_max_window_bits > this._options.clientMaxWindowBits)
      )
        throw new Error(
          'Unexpected or invalid parameter "client_max_window_bits"',
        );
      return I;
    }
    normalizeParams(b) {
      return (
        b.forEach((I) => {
          Object.keys(I).forEach((O) => {
            let C = I[O];
            if (C.length > 1)
              throw new Error(`Parameter "${O}" must have only a single value`);
            if (((C = C[0]), O === "client_max_window_bits")) {
              if (C !== !0) {
                const p = +C;
                if (!Number.isInteger(p) || p < 8 || p > 15)
                  throw new TypeError(
                    `Invalid value for parameter "${O}": ${C}`,
                  );
                C = p;
              } else if (!this._isServer)
                throw new TypeError(`Invalid value for parameter "${O}": ${C}`);
            } else if (O === "server_max_window_bits") {
              const p = +C;
              if (!Number.isInteger(p) || p < 8 || p > 15)
                throw new TypeError(`Invalid value for parameter "${O}": ${C}`);
              C = p;
            } else if (
              O === "client_no_context_takeover" ||
              O === "server_no_context_takeover"
            ) {
              if (C !== !0)
                throw new TypeError(`Invalid value for parameter "${O}": ${C}`);
            } else throw new Error(`Unknown parameter "${O}"`);
            I[O] = C;
          });
        }),
        b
      );
    }
    decompress(b, I, O) {
      g.add((C) => {
        this._decompress(b, I, (p, m) => {
          (C(), O(p, m));
        });
      });
    }
    compress(b, I, O) {
      g.add((C) => {
        this._compress(b, I, (p, m) => {
          (C(), O(p, m));
        });
      });
    }
    _decompress(b, I, O) {
      const C = this._isServer ? "client" : "server";
      if (!this._inflate) {
        const p = `${C}_max_window_bits`,
          m =
            typeof this.params[p] != "number"
              ? t.Z_DEFAULT_WINDOWBITS
              : this.params[p];
        ((this._inflate = t.createInflateRaw({
          ...this._options.zlibInflateOptions,
          windowBits: m,
        })),
          (this._inflate[i] = this),
          (this._inflate[c] = 0),
          (this._inflate[l] = []),
          this._inflate.on("error", w),
          this._inflate.on("data", _));
      }
      ((this._inflate[u] = O),
        this._inflate.write(b),
        I && this._inflate.write(s),
        this._inflate.flush(() => {
          const p = this._inflate[d];
          if (p) {
            (this._inflate.close(), (this._inflate = null), O(p));
            return;
          }
          const m = e.concat(this._inflate[l], this._inflate[c]);
          (this._inflate._readableState.endEmitted
            ? (this._inflate.close(), (this._inflate = null))
            : ((this._inflate[c] = 0),
              (this._inflate[l] = []),
              I &&
                this.params[`${C}_no_context_takeover`] &&
                this._inflate.reset()),
            O(null, m));
        }));
    }
    _compress(b, I, O) {
      const C = this._isServer ? "server" : "client";
      if (!this._deflate) {
        const p = `${C}_max_window_bits`,
          m =
            typeof this.params[p] != "number"
              ? t.Z_DEFAULT_WINDOWBITS
              : this.params[p];
        ((this._deflate = t.createDeflateRaw({
          ...this._options.zlibDeflateOptions,
          windowBits: m,
        })),
          (this._deflate[c] = 0),
          (this._deflate[l] = []),
          this._deflate.on("data", v));
      }
      ((this._deflate[u] = O),
        this._deflate.write(b),
        this._deflate.flush(t.Z_SYNC_FLUSH, () => {
          if (!this._deflate) return;
          let p = e.concat(this._deflate[l], this._deflate[c]);
          (I && (p = new o(p.buffer, p.byteOffset, p.length - 4)),
            (this._deflate[u] = null),
            (this._deflate[c] = 0),
            (this._deflate[l] = []),
            I &&
              this.params[`${C}_no_context_takeover`] &&
              this._deflate.reset(),
            O(null, p));
        }));
    }
  }
  kn = f;
  function v(E) {
    (this[l].push(E), (this[c] += E.length));
  }
  function _(E) {
    if (
      ((this[c] += E.length),
      this[i]._maxPayload < 1 || this[c] <= this[i]._maxPayload)
    ) {
      this[l].push(E);
      return;
    }
    ((this[d] = new RangeError("Max payload size exceeded")),
      (this[d].code = "WS_ERR_UNSUPPORTED_MESSAGE_LENGTH"),
      (this[d][r] = 1009),
      this.removeListener("data", _),
      this.reset());
  }
  function w(E) {
    if (((this[i]._inflate = null), this[d])) {
      this[u](this[d]);
      return;
    }
    ((E[r] = 1007), this[u](E));
  }
  return kn;
}
var ht = { exports: {} },
  zs;
function Nt() {
  if (zs) return ht.exports;
  zs = 1;
  const { isUtf8: t } = Ac,
    { hasBlob: e } = Ne(),
    n = [
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 0, 0, 1, 1, 0, 1, 1, 0, 1, 1,
      1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
      1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 1, 1, 1, 1, 1, 1,
      1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1,
      0, 1, 0,
    ];
  function r(i) {
    return (
      (i >= 1e3 && i <= 1014 && i !== 1004 && i !== 1005 && i !== 1006) ||
      (i >= 3e3 && i <= 4999)
    );
  }
  function o(i) {
    const c = i.length;
    let u = 0;
    for (; u < c;)
      if ((i[u] & 128) === 0) u++;
      else if ((i[u] & 224) === 192) {
        if (u + 1 === c || (i[u + 1] & 192) !== 128 || (i[u] & 254) === 192)
          return !1;
        u += 2;
      } else if ((i[u] & 240) === 224) {
        if (
          u + 2 >= c ||
          (i[u + 1] & 192) !== 128 ||
          (i[u + 2] & 192) !== 128 ||
          (i[u] === 224 && (i[u + 1] & 224) === 128) ||
          (i[u] === 237 && (i[u + 1] & 224) === 160)
        )
          return !1;
        u += 3;
      } else if ((i[u] & 248) === 240) {
        if (
          u + 3 >= c ||
          (i[u + 1] & 192) !== 128 ||
          (i[u + 2] & 192) !== 128 ||
          (i[u + 3] & 192) !== 128 ||
          (i[u] === 240 && (i[u + 1] & 240) === 128) ||
          (i[u] === 244 && i[u + 1] > 143) ||
          i[u] > 244
        )
          return !1;
        u += 4;
      } else return !1;
    return !0;
  }
  function s(i) {
    return (
      e &&
      typeof i == "object" &&
      typeof i.arrayBuffer == "function" &&
      typeof i.type == "string" &&
      typeof i.stream == "function" &&
      (i[Symbol.toStringTag] === "Blob" || i[Symbol.toStringTag] === "File")
    );
  }
  if (
    ((ht.exports = {
      isBlob: s,
      isValidStatusCode: r,
      isValidUTF8: o,
      tokenChars: n,
    }),
    t)
  )
    ht.exports.isValidUTF8 = function (i) {
      return i.length < 24 ? o(i) : t(i);
    };
  else if (!process.env.WS_NO_UTF_8_VALIDATE)
    try {
      const i = io("utf-8-validate");
      ht.exports.isValidUTF8 = function (c) {
        return c.length < 32 ? o(c) : i(c);
      };
    } catch {}
  return ht.exports;
}
var Nn, Vs;
function Za() {
  if (Vs) return Nn;
  Vs = 1;
  const { Writable: t } = bt,
    e = yn(),
    { BINARY_TYPES: n, EMPTY_BUFFER: r, kStatusCode: o, kWebSocket: s } = Ne(),
    { concat: i, toArrayBuffer: c, unmask: u } = gn(),
    { isValidStatusCode: l, isValidUTF8: d } = Nt(),
    g = Buffer[Symbol.species],
    f = 0,
    v = 1,
    _ = 2,
    w = 3,
    E = 4,
    b = 5,
    I = 6;
  class O extends t {
    constructor(p = {}) {
      (super(),
        (this._allowSynchronousEvents =
          p.allowSynchronousEvents !== void 0 ? p.allowSynchronousEvents : !0),
        (this._binaryType = p.binaryType || n[0]),
        (this._extensions = p.extensions || {}),
        (this._isServer = !!p.isServer),
        (this._maxPayload = p.maxPayload | 0),
        (this._skipUTF8Validation = !!p.skipUTF8Validation),
        (this[s] = void 0),
        (this._bufferedBytes = 0),
        (this._buffers = []),
        (this._compressed = !1),
        (this._payloadLength = 0),
        (this._mask = void 0),
        (this._fragmented = 0),
        (this._masked = !1),
        (this._fin = !1),
        (this._opcode = 0),
        (this._totalPayloadLength = 0),
        (this._messageLength = 0),
        (this._fragments = []),
        (this._errored = !1),
        (this._loop = !1),
        (this._state = f));
    }
    _write(p, m, x) {
      if (this._opcode === 8 && this._state == f) return x();
      ((this._bufferedBytes += p.length),
        this._buffers.push(p),
        this.startLoop(x));
    }
    consume(p) {
      if (((this._bufferedBytes -= p), p === this._buffers[0].length))
        return this._buffers.shift();
      if (p < this._buffers[0].length) {
        const x = this._buffers[0];
        return (
          (this._buffers[0] = new g(x.buffer, x.byteOffset + p, x.length - p)),
          new g(x.buffer, x.byteOffset, p)
        );
      }
      const m = Buffer.allocUnsafe(p);
      do {
        const x = this._buffers[0],
          T = m.length - p;
        (p >= x.length
          ? m.set(this._buffers.shift(), T)
          : (m.set(new Uint8Array(x.buffer, x.byteOffset, p), T),
            (this._buffers[0] = new g(
              x.buffer,
              x.byteOffset + p,
              x.length - p,
            ))),
          (p -= x.length));
      } while (p > 0);
      return m;
    }
    startLoop(p) {
      this._loop = !0;
      do
        switch (this._state) {
          case f:
            this.getInfo(p);
            break;
          case v:
            this.getPayloadLength16(p);
            break;
          case _:
            this.getPayloadLength64(p);
            break;
          case w:
            this.getMask();
            break;
          case E:
            this.getData(p);
            break;
          case b:
          case I:
            this._loop = !1;
            return;
        }
      while (this._loop);
      this._errored || p();
    }
    getInfo(p) {
      if (this._bufferedBytes < 2) {
        this._loop = !1;
        return;
      }
      const m = this.consume(2);
      if ((m[0] & 48) !== 0) {
        const T = this.createError(
          RangeError,
          "RSV2 and RSV3 must be clear",
          !0,
          1002,
          "WS_ERR_UNEXPECTED_RSV_2_3",
        );
        p(T);
        return;
      }
      const x = (m[0] & 64) === 64;
      if (x && !this._extensions[e.extensionName]) {
        const T = this.createError(
          RangeError,
          "RSV1 must be clear",
          !0,
          1002,
          "WS_ERR_UNEXPECTED_RSV_1",
        );
        p(T);
        return;
      }
      if (
        ((this._fin = (m[0] & 128) === 128),
        (this._opcode = m[0] & 15),
        (this._payloadLength = m[1] & 127),
        this._opcode === 0)
      ) {
        if (x) {
          const T = this.createError(
            RangeError,
            "RSV1 must be clear",
            !0,
            1002,
            "WS_ERR_UNEXPECTED_RSV_1",
          );
          p(T);
          return;
        }
        if (!this._fragmented) {
          const T = this.createError(
            RangeError,
            "invalid opcode 0",
            !0,
            1002,
            "WS_ERR_INVALID_OPCODE",
          );
          p(T);
          return;
        }
        this._opcode = this._fragmented;
      } else if (this._opcode === 1 || this._opcode === 2) {
        if (this._fragmented) {
          const T = this.createError(
            RangeError,
            `invalid opcode ${this._opcode}`,
            !0,
            1002,
            "WS_ERR_INVALID_OPCODE",
          );
          p(T);
          return;
        }
        this._compressed = x;
      } else if (this._opcode > 7 && this._opcode < 11) {
        if (!this._fin) {
          const T = this.createError(
            RangeError,
            "FIN must be set",
            !0,
            1002,
            "WS_ERR_EXPECTED_FIN",
          );
          p(T);
          return;
        }
        if (x) {
          const T = this.createError(
            RangeError,
            "RSV1 must be clear",
            !0,
            1002,
            "WS_ERR_UNEXPECTED_RSV_1",
          );
          p(T);
          return;
        }
        if (
          this._payloadLength > 125 ||
          (this._opcode === 8 && this._payloadLength === 1)
        ) {
          const T = this.createError(
            RangeError,
            `invalid payload length ${this._payloadLength}`,
            !0,
            1002,
            "WS_ERR_INVALID_CONTROL_PAYLOAD_LENGTH",
          );
          p(T);
          return;
        }
      } else {
        const T = this.createError(
          RangeError,
          `invalid opcode ${this._opcode}`,
          !0,
          1002,
          "WS_ERR_INVALID_OPCODE",
        );
        p(T);
        return;
      }
      if (
        (!this._fin && !this._fragmented && (this._fragmented = this._opcode),
        (this._masked = (m[1] & 128) === 128),
        this._isServer)
      ) {
        if (!this._masked) {
          const T = this.createError(
            RangeError,
            "MASK must be set",
            !0,
            1002,
            "WS_ERR_EXPECTED_MASK",
          );
          p(T);
          return;
        }
      } else if (this._masked) {
        const T = this.createError(
          RangeError,
          "MASK must be clear",
          !0,
          1002,
          "WS_ERR_UNEXPECTED_MASK",
        );
        p(T);
        return;
      }
      this._payloadLength === 126
        ? (this._state = v)
        : this._payloadLength === 127
          ? (this._state = _)
          : this.haveLength(p);
    }
    getPayloadLength16(p) {
      if (this._bufferedBytes < 2) {
        this._loop = !1;
        return;
      }
      ((this._payloadLength = this.consume(2).readUInt16BE(0)),
        this.haveLength(p));
    }
    getPayloadLength64(p) {
      if (this._bufferedBytes < 8) {
        this._loop = !1;
        return;
      }
      const m = this.consume(8),
        x = m.readUInt32BE(0);
      if (x > Math.pow(2, 21) - 1) {
        const T = this.createError(
          RangeError,
          "Unsupported WebSocket frame: payload length > 2^53 - 1",
          !1,
          1009,
          "WS_ERR_UNSUPPORTED_DATA_PAYLOAD_LENGTH",
        );
        p(T);
        return;
      }
      ((this._payloadLength = x * Math.pow(2, 32) + m.readUInt32BE(4)),
        this.haveLength(p));
    }
    haveLength(p) {
      if (
        this._payloadLength &&
        this._opcode < 8 &&
        ((this._totalPayloadLength += this._payloadLength),
        this._totalPayloadLength > this._maxPayload && this._maxPayload > 0)
      ) {
        const m = this.createError(
          RangeError,
          "Max payload size exceeded",
          !1,
          1009,
          "WS_ERR_UNSUPPORTED_MESSAGE_LENGTH",
        );
        p(m);
        return;
      }
      this._masked ? (this._state = w) : (this._state = E);
    }
    getMask() {
      if (this._bufferedBytes < 4) {
        this._loop = !1;
        return;
      }
      ((this._mask = this.consume(4)), (this._state = E));
    }
    getData(p) {
      let m = r;
      if (this._payloadLength) {
        if (this._bufferedBytes < this._payloadLength) {
          this._loop = !1;
          return;
        }
        ((m = this.consume(this._payloadLength)),
          this._masked &&
            (this._mask[0] | this._mask[1] | this._mask[2] | this._mask[3]) !==
              0 &&
            u(m, this._mask));
      }
      if (this._opcode > 7) {
        this.controlMessage(m, p);
        return;
      }
      if (this._compressed) {
        ((this._state = b), this.decompress(m, p));
        return;
      }
      (m.length &&
        ((this._messageLength = this._totalPayloadLength),
        this._fragments.push(m)),
        this.dataMessage(p));
    }
    decompress(p, m) {
      this._extensions[e.extensionName].decompress(p, this._fin, (T, k) => {
        if (T) return m(T);
        if (k.length) {
          if (
            ((this._messageLength += k.length),
            this._messageLength > this._maxPayload && this._maxPayload > 0)
          ) {
            const N = this.createError(
              RangeError,
              "Max payload size exceeded",
              !1,
              1009,
              "WS_ERR_UNSUPPORTED_MESSAGE_LENGTH",
            );
            m(N);
            return;
          }
          this._fragments.push(k);
        }
        (this.dataMessage(m), this._state === f && this.startLoop(m));
      });
    }
    dataMessage(p) {
      if (!this._fin) {
        this._state = f;
        return;
      }
      const m = this._messageLength,
        x = this._fragments;
      if (
        ((this._totalPayloadLength = 0),
        (this._messageLength = 0),
        (this._fragmented = 0),
        (this._fragments = []),
        this._opcode === 2)
      ) {
        let T;
        (this._binaryType === "nodebuffer"
          ? (T = i(x, m))
          : this._binaryType === "arraybuffer"
            ? (T = c(i(x, m)))
            : this._binaryType === "blob"
              ? (T = new Blob(x))
              : (T = x),
          this._allowSynchronousEvents
            ? (this.emit("message", T, !0), (this._state = f))
            : ((this._state = I),
              setImmediate(() => {
                (this.emit("message", T, !0),
                  (this._state = f),
                  this.startLoop(p));
              })));
      } else {
        const T = i(x, m);
        if (!this._skipUTF8Validation && !d(T)) {
          const k = this.createError(
            Error,
            "invalid UTF-8 sequence",
            !0,
            1007,
            "WS_ERR_INVALID_UTF8",
          );
          p(k);
          return;
        }
        this._state === b || this._allowSynchronousEvents
          ? (this.emit("message", T, !1), (this._state = f))
          : ((this._state = I),
            setImmediate(() => {
              (this.emit("message", T, !1),
                (this._state = f),
                this.startLoop(p));
            }));
      }
    }
    controlMessage(p, m) {
      if (this._opcode === 8) {
        if (p.length === 0)
          ((this._loop = !1), this.emit("conclude", 1005, r), this.end());
        else {
          const x = p.readUInt16BE(0);
          if (!l(x)) {
            const k = this.createError(
              RangeError,
              `invalid status code ${x}`,
              !0,
              1002,
              "WS_ERR_INVALID_CLOSE_CODE",
            );
            m(k);
            return;
          }
          const T = new g(p.buffer, p.byteOffset + 2, p.length - 2);
          if (!this._skipUTF8Validation && !d(T)) {
            const k = this.createError(
              Error,
              "invalid UTF-8 sequence",
              !0,
              1007,
              "WS_ERR_INVALID_UTF8",
            );
            m(k);
            return;
          }
          ((this._loop = !1), this.emit("conclude", x, T), this.end());
        }
        this._state = f;
        return;
      }
      this._allowSynchronousEvents
        ? (this.emit(this._opcode === 9 ? "ping" : "pong", p),
          (this._state = f))
        : ((this._state = I),
          setImmediate(() => {
            (this.emit(this._opcode === 9 ? "ping" : "pong", p),
              (this._state = f),
              this.startLoop(m));
          }));
    }
    createError(p, m, x, T, k) {
      ((this._loop = !1), (this._errored = !0));
      const N = new p(x ? `Invalid WebSocket frame: ${m}` : m);
      return (
        Error.captureStackTrace(N, this.createError),
        (N.code = k),
        (N[o] = T),
        N
      );
    }
  }
  return ((Nn = O), Nn);
}
var Ln, Ks;
function Xa() {
  if (Ks) return Ln;
  Ks = 1;
  const { Duplex: t } = bt,
    { randomFillSync: e } = nr,
    n = yn(),
    { EMPTY_BUFFER: r, kWebSocket: o, NOOP: s } = Ne(),
    { isBlob: i, isValidStatusCode: c } = Nt(),
    { mask: u, toBuffer: l } = gn(),
    d = Symbol("kByteLength"),
    g = Buffer.alloc(4),
    f = 8 * 1024;
  let v,
    _ = f;
  const w = 0,
    E = 1,
    b = 2;
  class I {
    constructor(m, x, T) {
      ((this._extensions = x || {}),
        T && ((this._generateMask = T), (this._maskBuffer = Buffer.alloc(4))),
        (this._socket = m),
        (this._firstFragment = !0),
        (this._compress = !1),
        (this._bufferedBytes = 0),
        (this._queue = []),
        (this._state = w),
        (this.onerror = s),
        (this[o] = void 0));
    }
    static frame(m, x) {
      let T,
        k = !1,
        N = 2,
        q = !1;
      x.mask &&
        ((T = x.maskBuffer || g),
        x.generateMask
          ? x.generateMask(T)
          : (_ === f &&
              (v === void 0 && (v = Buffer.alloc(f)), e(v, 0, f), (_ = 0)),
            (T[0] = v[_++]),
            (T[1] = v[_++]),
            (T[2] = v[_++]),
            (T[3] = v[_++])),
        (q = (T[0] | T[1] | T[2] | T[3]) === 0),
        (N = 6));
      let H;
      typeof m == "string"
        ? (!x.mask || q) && x[d] !== void 0
          ? (H = x[d])
          : ((m = Buffer.from(m)), (H = m.length))
        : ((H = m.length), (k = x.mask && x.readOnly && !q));
      let K = H;
      H >= 65536 ? ((N += 8), (K = 127)) : H > 125 && ((N += 2), (K = 126));
      const B = Buffer.allocUnsafe(k ? H + N : N);
      return (
        (B[0] = x.fin ? x.opcode | 128 : x.opcode),
        x.rsv1 && (B[0] |= 64),
        (B[1] = K),
        K === 126
          ? B.writeUInt16BE(H, 2)
          : K === 127 && ((B[2] = B[3] = 0), B.writeUIntBE(H, 4, 6)),
        x.mask
          ? ((B[1] |= 128),
            (B[N - 4] = T[0]),
            (B[N - 3] = T[1]),
            (B[N - 2] = T[2]),
            (B[N - 1] = T[3]),
            q
              ? [B, m]
              : k
                ? (u(m, T, B, N, H), [B])
                : (u(m, T, m, 0, H), [B, m]))
          : [B, m]
      );
    }
    close(m, x, T, k) {
      let N;
      if (m === void 0) N = r;
      else {
        if (typeof m != "number" || !c(m))
          throw new TypeError(
            "First argument must be a valid error code number",
          );
        if (x === void 0 || !x.length)
          ((N = Buffer.allocUnsafe(2)), N.writeUInt16BE(m, 0));
        else {
          const H = Buffer.byteLength(x);
          if (H > 123)
            throw new RangeError(
              "The message must not be greater than 123 bytes",
            );
          ((N = Buffer.allocUnsafe(2 + H)),
            N.writeUInt16BE(m, 0),
            typeof x == "string" ? N.write(x, 2) : N.set(x, 2));
        }
      }
      const q = {
        [d]: N.length,
        fin: !0,
        generateMask: this._generateMask,
        mask: T,
        maskBuffer: this._maskBuffer,
        opcode: 8,
        readOnly: !1,
        rsv1: !1,
      };
      this._state !== w
        ? this.enqueue([this.dispatch, N, !1, q, k])
        : this.sendFrame(I.frame(N, q), k);
    }
    ping(m, x, T) {
      let k, N;
      if (
        (typeof m == "string"
          ? ((k = Buffer.byteLength(m)), (N = !1))
          : i(m)
            ? ((k = m.size), (N = !1))
            : ((m = l(m)), (k = m.length), (N = l.readOnly)),
        k > 125)
      )
        throw new RangeError(
          "The data size must not be greater than 125 bytes",
        );
      const q = {
        [d]: k,
        fin: !0,
        generateMask: this._generateMask,
        mask: x,
        maskBuffer: this._maskBuffer,
        opcode: 9,
        readOnly: N,
        rsv1: !1,
      };
      i(m)
        ? this._state !== w
          ? this.enqueue([this.getBlobData, m, !1, q, T])
          : this.getBlobData(m, !1, q, T)
        : this._state !== w
          ? this.enqueue([this.dispatch, m, !1, q, T])
          : this.sendFrame(I.frame(m, q), T);
    }
    pong(m, x, T) {
      let k, N;
      if (
        (typeof m == "string"
          ? ((k = Buffer.byteLength(m)), (N = !1))
          : i(m)
            ? ((k = m.size), (N = !1))
            : ((m = l(m)), (k = m.length), (N = l.readOnly)),
        k > 125)
      )
        throw new RangeError(
          "The data size must not be greater than 125 bytes",
        );
      const q = {
        [d]: k,
        fin: !0,
        generateMask: this._generateMask,
        mask: x,
        maskBuffer: this._maskBuffer,
        opcode: 10,
        readOnly: N,
        rsv1: !1,
      };
      i(m)
        ? this._state !== w
          ? this.enqueue([this.getBlobData, m, !1, q, T])
          : this.getBlobData(m, !1, q, T)
        : this._state !== w
          ? this.enqueue([this.dispatch, m, !1, q, T])
          : this.sendFrame(I.frame(m, q), T);
    }
    send(m, x, T) {
      const k = this._extensions[n.extensionName];
      let N = x.binary ? 2 : 1,
        q = x.compress,
        H,
        K;
      (typeof m == "string"
        ? ((H = Buffer.byteLength(m)), (K = !1))
        : i(m)
          ? ((H = m.size), (K = !1))
          : ((m = l(m)), (H = m.length), (K = l.readOnly)),
        this._firstFragment
          ? ((this._firstFragment = !1),
            q &&
              k &&
              k.params[
                k._isServer
                  ? "server_no_context_takeover"
                  : "client_no_context_takeover"
              ] &&
              (q = H >= k._threshold),
            (this._compress = q))
          : ((q = !1), (N = 0)),
        x.fin && (this._firstFragment = !0));
      const B = {
        [d]: H,
        fin: x.fin,
        generateMask: this._generateMask,
        mask: x.mask,
        maskBuffer: this._maskBuffer,
        opcode: N,
        readOnly: K,
        rsv1: q,
      };
      i(m)
        ? this._state !== w
          ? this.enqueue([this.getBlobData, m, this._compress, B, T])
          : this.getBlobData(m, this._compress, B, T)
        : this._state !== w
          ? this.enqueue([this.dispatch, m, this._compress, B, T])
          : this.dispatch(m, this._compress, B, T);
    }
    getBlobData(m, x, T, k) {
      ((this._bufferedBytes += T[d]),
        (this._state = b),
        m
          .arrayBuffer()
          .then((N) => {
            if (this._socket.destroyed) {
              const H = new Error(
                "The socket was closed while the blob was being read",
              );
              process.nextTick(O, this, H, k);
              return;
            }
            this._bufferedBytes -= T[d];
            const q = l(N);
            x
              ? this.dispatch(q, x, T, k)
              : ((this._state = w),
                this.sendFrame(I.frame(q, T), k),
                this.dequeue());
          })
          .catch((N) => {
            process.nextTick(C, this, N, k);
          }));
    }
    dispatch(m, x, T, k) {
      if (!x) {
        this.sendFrame(I.frame(m, T), k);
        return;
      }
      const N = this._extensions[n.extensionName];
      ((this._bufferedBytes += T[d]),
        (this._state = E),
        N.compress(m, T.fin, (q, H) => {
          if (this._socket.destroyed) {
            const K = new Error(
              "The socket was closed while data was being compressed",
            );
            O(this, K, k);
            return;
          }
          ((this._bufferedBytes -= T[d]),
            (this._state = w),
            (T.readOnly = !1),
            this.sendFrame(I.frame(H, T), k),
            this.dequeue());
        }));
    }
    dequeue() {
      for (; this._state === w && this._queue.length;) {
        const m = this._queue.shift();
        ((this._bufferedBytes -= m[3][d]),
          Reflect.apply(m[0], this, m.slice(1)));
      }
    }
    enqueue(m) {
      ((this._bufferedBytes += m[3][d]), this._queue.push(m));
    }
    sendFrame(m, x) {
      m.length === 2
        ? (this._socket.cork(),
          this._socket.write(m[0]),
          this._socket.write(m[1], x),
          this._socket.uncork())
        : this._socket.write(m[0], x);
    }
  }
  Ln = I;
  function O(p, m, x) {
    typeof x == "function" && x(m);
    for (let T = 0; T < p._queue.length; T++) {
      const k = p._queue[T],
        N = k[k.length - 1];
      typeof N == "function" && N(m);
    }
  }
  function C(p, m, x) {
    (O(p, m, x), p.onerror(m));
  }
  return Ln;
}
var Pn, Ys;
function Wp() {
  if (Ys) return Pn;
  Ys = 1;
  const { kForOnEventAttribute: t, kListener: e } = Ne(),
    n = Symbol("kCode"),
    r = Symbol("kData"),
    o = Symbol("kError"),
    s = Symbol("kMessage"),
    i = Symbol("kReason"),
    c = Symbol("kTarget"),
    u = Symbol("kType"),
    l = Symbol("kWasClean");
  class d {
    constructor(b) {
      ((this[c] = null), (this[u] = b));
    }
    get target() {
      return this[c];
    }
    get type() {
      return this[u];
    }
  }
  (Object.defineProperty(d.prototype, "target", { enumerable: !0 }),
    Object.defineProperty(d.prototype, "type", { enumerable: !0 }));
  class g extends d {
    constructor(b, I = {}) {
      (super(b),
        (this[n] = I.code === void 0 ? 0 : I.code),
        (this[i] = I.reason === void 0 ? "" : I.reason),
        (this[l] = I.wasClean === void 0 ? !1 : I.wasClean));
    }
    get code() {
      return this[n];
    }
    get reason() {
      return this[i];
    }
    get wasClean() {
      return this[l];
    }
  }
  (Object.defineProperty(g.prototype, "code", { enumerable: !0 }),
    Object.defineProperty(g.prototype, "reason", { enumerable: !0 }),
    Object.defineProperty(g.prototype, "wasClean", { enumerable: !0 }));
  class f extends d {
    constructor(b, I = {}) {
      (super(b),
        (this[o] = I.error === void 0 ? null : I.error),
        (this[s] = I.message === void 0 ? "" : I.message));
    }
    get error() {
      return this[o];
    }
    get message() {
      return this[s];
    }
  }
  (Object.defineProperty(f.prototype, "error", { enumerable: !0 }),
    Object.defineProperty(f.prototype, "message", { enumerable: !0 }));
  class v extends d {
    constructor(b, I = {}) {
      (super(b), (this[r] = I.data === void 0 ? null : I.data));
    }
    get data() {
      return this[r];
    }
  }
  (Object.defineProperty(v.prototype, "data", { enumerable: !0 }),
    (Pn = {
      CloseEvent: g,
      ErrorEvent: f,
      Event: d,
      EventTarget: {
        addEventListener(E, b, I = {}) {
          for (const C of this.listeners(E))
            if (!I[t] && C[e] === b && !C[t]) return;
          let O;
          if (E === "message")
            O = function (p, m) {
              const x = new v("message", { data: m ? p : p.toString() });
              ((x[c] = this), w(b, this, x));
            };
          else if (E === "close")
            O = function (p, m) {
              const x = new g("close", {
                code: p,
                reason: m.toString(),
                wasClean: this._closeFrameReceived && this._closeFrameSent,
              });
              ((x[c] = this), w(b, this, x));
            };
          else if (E === "error")
            O = function (p) {
              const m = new f("error", { error: p, message: p.message });
              ((m[c] = this), w(b, this, m));
            };
          else if (E === "open")
            O = function () {
              const p = new d("open");
              ((p[c] = this), w(b, this, p));
            };
          else return;
          ((O[t] = !!I[t]),
            (O[e] = b),
            I.once ? this.once(E, O) : this.on(E, O));
        },
        removeEventListener(E, b) {
          for (const I of this.listeners(E))
            if (I[e] === b && !I[t]) {
              this.removeListener(E, I);
              break;
            }
        },
      },
      MessageEvent: v,
    }));
  function w(E, b, I) {
    typeof E == "object" && E.handleEvent
      ? E.handleEvent.call(E, I)
      : E.call(b, I);
  }
  return Pn;
}
var Mn, Zs;
function Qa() {
  if (Zs) return Mn;
  Zs = 1;
  const { tokenChars: t } = Nt();
  function e(o, s, i) {
    o[s] === void 0 ? (o[s] = [i]) : o[s].push(i);
  }
  function n(o) {
    const s = Object.create(null);
    let i = Object.create(null),
      c = !1,
      u = !1,
      l = !1,
      d,
      g,
      f = -1,
      v = -1,
      _ = -1,
      w = 0;
    for (; w < o.length; w++)
      if (((v = o.charCodeAt(w)), d === void 0))
        if (_ === -1 && t[v] === 1) f === -1 && (f = w);
        else if (w !== 0 && (v === 32 || v === 9))
          _ === -1 && f !== -1 && (_ = w);
        else if (v === 59 || v === 44) {
          if (f === -1)
            throw new SyntaxError(`Unexpected character at index ${w}`);
          _ === -1 && (_ = w);
          const b = o.slice(f, _);
          (v === 44 ? (e(s, b, i), (i = Object.create(null))) : (d = b),
            (f = _ = -1));
        } else throw new SyntaxError(`Unexpected character at index ${w}`);
      else if (g === void 0)
        if (_ === -1 && t[v] === 1) f === -1 && (f = w);
        else if (v === 32 || v === 9) _ === -1 && f !== -1 && (_ = w);
        else if (v === 59 || v === 44) {
          if (f === -1)
            throw new SyntaxError(`Unexpected character at index ${w}`);
          (_ === -1 && (_ = w),
            e(i, o.slice(f, _), !0),
            v === 44 && (e(s, d, i), (i = Object.create(null)), (d = void 0)),
            (f = _ = -1));
        } else if (v === 61 && f !== -1 && _ === -1)
          ((g = o.slice(f, w)), (f = _ = -1));
        else throw new SyntaxError(`Unexpected character at index ${w}`);
      else if (u) {
        if (t[v] !== 1)
          throw new SyntaxError(`Unexpected character at index ${w}`);
        (f === -1 ? (f = w) : c || (c = !0), (u = !1));
      } else if (l)
        if (t[v] === 1) f === -1 && (f = w);
        else if (v === 34 && f !== -1) ((l = !1), (_ = w));
        else if (v === 92) u = !0;
        else throw new SyntaxError(`Unexpected character at index ${w}`);
      else if (v === 34 && o.charCodeAt(w - 1) === 61) l = !0;
      else if (_ === -1 && t[v] === 1) f === -1 && (f = w);
      else if (f !== -1 && (v === 32 || v === 9)) _ === -1 && (_ = w);
      else if (v === 59 || v === 44) {
        if (f === -1)
          throw new SyntaxError(`Unexpected character at index ${w}`);
        _ === -1 && (_ = w);
        let b = o.slice(f, _);
        (c && ((b = b.replace(/\\/g, "")), (c = !1)),
          e(i, g, b),
          v === 44 && (e(s, d, i), (i = Object.create(null)), (d = void 0)),
          (g = void 0),
          (f = _ = -1));
      } else throw new SyntaxError(`Unexpected character at index ${w}`);
    if (f === -1 || l || v === 32 || v === 9)
      throw new SyntaxError("Unexpected end of input");
    _ === -1 && (_ = w);
    const E = o.slice(f, _);
    return (
      d === void 0
        ? e(s, E, i)
        : (g === void 0
            ? e(i, E, !0)
            : c
              ? e(i, g, E.replace(/\\/g, ""))
              : e(i, g, E),
          e(s, d, i)),
      s
    );
  }
  function r(o) {
    return Object.keys(o)
      .map((s) => {
        let i = o[s];
        return (
          Array.isArray(i) || (i = [i]),
          i
            .map((c) =>
              [s]
                .concat(
                  Object.keys(c).map((u) => {
                    let l = c[u];
                    return (
                      Array.isArray(l) || (l = [l]),
                      l.map((d) => (d === !0 ? u : `${u}=${d}`)).join("; ")
                    );
                  }),
                )
                .join("; "),
            )
            .join(", ")
        );
      })
      .join(", ");
  }
  return ((Mn = { format: r, parse: n }), Mn);
}
var Fn, Xs;
function zr() {
  if (Xs) return Fn;
  Xs = 1;
  const t = so,
    e = bc,
    n = oo,
    r = xc,
    o = Ic,
    { randomBytes: s, createHash: i } = nr,
    { Duplex: c, Readable: u } = bt,
    { URL: l } = Ec,
    d = yn(),
    g = Za(),
    f = Xa(),
    { isBlob: v } = Nt(),
    {
      BINARY_TYPES: _,
      EMPTY_BUFFER: w,
      GUID: E,
      kForOnEventAttribute: b,
      kListener: I,
      kStatusCode: O,
      kWebSocket: C,
      NOOP: p,
    } = Ne(),
    {
      EventTarget: { addEventListener: m, removeEventListener: x },
    } = Wp(),
    { format: T, parse: k } = Qa(),
    { toBuffer: N } = gn(),
    q = 30 * 1e3,
    H = Symbol("kAborted"),
    K = [8, 13],
    B = ["CONNECTING", "OPEN", "CLOSING", "CLOSED"],
    me = /^[!#$%&'*+\-.0-9A-Z^_`|a-z~]+$/;
  class F extends t {
    constructor(A, M, $) {
      (super(),
        (this._binaryType = _[0]),
        (this._closeCode = 1006),
        (this._closeFrameReceived = !1),
        (this._closeFrameSent = !1),
        (this._closeMessage = w),
        (this._closeTimer = null),
        (this._errorEmitted = !1),
        (this._extensions = {}),
        (this._paused = !1),
        (this._protocol = ""),
        (this._readyState = F.CONNECTING),
        (this._receiver = null),
        (this._sender = null),
        (this._socket = null),
        A !== null
          ? ((this._bufferedAmount = 0),
            (this._isServer = !1),
            (this._redirects = 0),
            M === void 0
              ? (M = [])
              : Array.isArray(M) ||
                (typeof M == "object" && M !== null
                  ? (($ = M), (M = []))
                  : (M = [M])),
            be(this, A, M, $))
          : ((this._autoPong = $.autoPong), (this._isServer = !0)));
    }
    get binaryType() {
      return this._binaryType;
    }
    set binaryType(A) {
      _.includes(A) &&
        ((this._binaryType = A),
        this._receiver && (this._receiver._binaryType = A));
    }
    get bufferedAmount() {
      return this._socket
        ? this._socket._writableState.length + this._sender._bufferedBytes
        : this._bufferedAmount;
    }
    get extensions() {
      return Object.keys(this._extensions).join();
    }
    get isPaused() {
      return this._paused;
    }
    get onclose() {
      return null;
    }
    get onerror() {
      return null;
    }
    get onopen() {
      return null;
    }
    get onmessage() {
      return null;
    }
    get protocol() {
      return this._protocol;
    }
    get readyState() {
      return this._readyState;
    }
    get url() {
      return this._url;
    }
    setSocket(A, M, $) {
      const L = new g({
          allowSynchronousEvents: $.allowSynchronousEvents,
          binaryType: this.binaryType,
          extensions: this._extensions,
          isServer: this._isServer,
          maxPayload: $.maxPayload,
          skipUTF8Validation: $.skipUTF8Validation,
        }),
        z = new f(A, this._extensions, $.generateMask);
      ((this._receiver = L),
        (this._sender = z),
        (this._socket = A),
        (L[C] = this),
        (z[C] = this),
        (A[C] = this),
        L.on("conclude", rc),
        L.on("drain", sc),
        L.on("error", oc),
        L.on("message", ic),
        L.on("ping", ac),
        L.on("pong", cc),
        (z.onerror = uc),
        A.setTimeout && A.setTimeout(0),
        A.setNoDelay && A.setNoDelay(),
        M.length > 0 && A.unshift(M),
        A.on("close", Zr),
        A.on("data", Lt),
        A.on("end", Xr),
        A.on("error", Qr),
        (this._readyState = F.OPEN),
        this.emit("open"));
    }
    emitClose() {
      if (!this._socket) {
        ((this._readyState = F.CLOSED),
          this.emit("close", this._closeCode, this._closeMessage));
        return;
      }
      (this._extensions[d.extensionName] &&
        this._extensions[d.extensionName].cleanup(),
        this._receiver.removeAllListeners(),
        (this._readyState = F.CLOSED),
        this.emit("close", this._closeCode, this._closeMessage));
    }
    close(A, M) {
      if (this.readyState !== F.CLOSED) {
        if (this.readyState === F.CONNECTING) {
          ce(
            this,
            this._req,
            "WebSocket was closed before the connection was established",
          );
          return;
        }
        if (this.readyState === F.CLOSING) {
          this._closeFrameSent &&
            (this._closeFrameReceived ||
              this._receiver._writableState.errorEmitted) &&
            this._socket.end();
          return;
        }
        ((this._readyState = F.CLOSING),
          this._sender.close(A, M, !this._isServer, ($) => {
            $ ||
              ((this._closeFrameSent = !0),
              (this._closeFrameReceived ||
                this._receiver._writableState.errorEmitted) &&
                this._socket.end());
          }),
          Yr(this));
      }
    }
    pause() {
      this.readyState === F.CONNECTING ||
        this.readyState === F.CLOSED ||
        ((this._paused = !0), this._socket.pause());
    }
    ping(A, M, $) {
      if (this.readyState === F.CONNECTING)
        throw new Error("WebSocket is not open: readyState 0 (CONNECTING)");
      if (
        (typeof A == "function"
          ? (($ = A), (A = M = void 0))
          : typeof M == "function" && (($ = M), (M = void 0)),
        typeof A == "number" && (A = A.toString()),
        this.readyState !== F.OPEN)
      ) {
        wn(this, A, $);
        return;
      }
      (M === void 0 && (M = !this._isServer), this._sender.ping(A || w, M, $));
    }
    pong(A, M, $) {
      if (this.readyState === F.CONNECTING)
        throw new Error("WebSocket is not open: readyState 0 (CONNECTING)");
      if (
        (typeof A == "function"
          ? (($ = A), (A = M = void 0))
          : typeof M == "function" && (($ = M), (M = void 0)),
        typeof A == "number" && (A = A.toString()),
        this.readyState !== F.OPEN)
      ) {
        wn(this, A, $);
        return;
      }
      (M === void 0 && (M = !this._isServer), this._sender.pong(A || w, M, $));
    }
    resume() {
      this.readyState === F.CONNECTING ||
        this.readyState === F.CLOSED ||
        ((this._paused = !1),
        this._receiver._writableState.needDrain || this._socket.resume());
    }
    send(A, M, $) {
      if (this.readyState === F.CONNECTING)
        throw new Error("WebSocket is not open: readyState 0 (CONNECTING)");
      if (
        (typeof M == "function" && (($ = M), (M = {})),
        typeof A == "number" && (A = A.toString()),
        this.readyState !== F.OPEN)
      ) {
        wn(this, A, $);
        return;
      }
      const L = {
        binary: typeof A != "string",
        mask: !this._isServer,
        compress: !0,
        fin: !0,
        ...M,
      };
      (this._extensions[d.extensionName] || (L.compress = !1),
        this._sender.send(A || w, L, $));
    }
    terminate() {
      if (this.readyState !== F.CLOSED) {
        if (this.readyState === F.CONNECTING) {
          ce(
            this,
            this._req,
            "WebSocket was closed before the connection was established",
          );
          return;
        }
        this._socket &&
          ((this._readyState = F.CLOSING), this._socket.destroy());
      }
    }
  }
  (Object.defineProperty(F, "CONNECTING", {
    enumerable: !0,
    value: B.indexOf("CONNECTING"),
  }),
    Object.defineProperty(F.prototype, "CONNECTING", {
      enumerable: !0,
      value: B.indexOf("CONNECTING"),
    }),
    Object.defineProperty(F, "OPEN", {
      enumerable: !0,
      value: B.indexOf("OPEN"),
    }),
    Object.defineProperty(F.prototype, "OPEN", {
      enumerable: !0,
      value: B.indexOf("OPEN"),
    }),
    Object.defineProperty(F, "CLOSING", {
      enumerable: !0,
      value: B.indexOf("CLOSING"),
    }),
    Object.defineProperty(F.prototype, "CLOSING", {
      enumerable: !0,
      value: B.indexOf("CLOSING"),
    }),
    Object.defineProperty(F, "CLOSED", {
      enumerable: !0,
      value: B.indexOf("CLOSED"),
    }),
    Object.defineProperty(F.prototype, "CLOSED", {
      enumerable: !0,
      value: B.indexOf("CLOSED"),
    }),
    [
      "binaryType",
      "bufferedAmount",
      "extensions",
      "isPaused",
      "protocol",
      "readyState",
      "url",
    ].forEach((S) => {
      Object.defineProperty(F.prototype, S, { enumerable: !0 });
    }),
    ["open", "error", "close", "message"].forEach((S) => {
      Object.defineProperty(F.prototype, `on${S}`, {
        enumerable: !0,
        get() {
          for (const A of this.listeners(S)) if (A[b]) return A[I];
          return null;
        },
        set(A) {
          for (const M of this.listeners(S))
            if (M[b]) {
              this.removeListener(S, M);
              break;
            }
          typeof A == "function" && this.addEventListener(S, A, { [b]: !0 });
        },
      });
    }),
    (F.prototype.addEventListener = m),
    (F.prototype.removeEventListener = x),
    (Fn = F));
  function be(S, A, M, $) {
    const L = {
      allowSynchronousEvents: !0,
      autoPong: !0,
      protocolVersion: K[1],
      maxPayload: 104857600,
      skipUTF8Validation: !1,
      perMessageDeflate: !0,
      followRedirects: !1,
      maxRedirects: 10,
      ...$,
      socketPath: void 0,
      hostname: void 0,
      protocol: void 0,
      timeout: void 0,
      method: "GET",
      host: void 0,
      path: void 0,
      port: void 0,
    };
    if (((S._autoPong = L.autoPong), !K.includes(L.protocolVersion)))
      throw new RangeError(
        `Unsupported protocol version: ${L.protocolVersion} (supported versions: ${K.join(", ")})`,
      );
    let z;
    if (A instanceof l) z = A;
    else
      try {
        z = new l(A);
      } catch {
        throw new SyntaxError(`Invalid URL: ${A}`);
      }
    (z.protocol === "http:"
      ? (z.protocol = "ws:")
      : z.protocol === "https:" && (z.protocol = "wss:"),
      (S._url = z.href));
    const Ge = z.protocol === "wss:",
      Je = z.protocol === "ws+unix:";
    let ct;
    if (
      (z.protocol !== "ws:" && !Ge && !Je
        ? (ct = `The URL's protocol must be one of "ws:", "wss:", "http:", "https:", or "ws+unix:"`)
        : Je && !z.pathname
          ? (ct = "The URL's pathname is empty")
          : z.hash && (ct = "The URL contains a fragment identifier"),
      ct)
    ) {
      const W = new SyntaxError(ct);
      if (S._redirects === 0) throw W;
      Le(S, W);
      return;
    }
    const es = Ge ? 443 : 80,
      ts = s(16).toString("base64"),
      ns = Ge ? e.request : n.request,
      ut = new Set();
    let lt;
    if (
      ((L.createConnection = L.createConnection || (Ge ? Sn : vn)),
      (L.defaultPort = L.defaultPort || es),
      (L.port = z.port || es),
      (L.host = z.hostname.startsWith("[")
        ? z.hostname.slice(1, -1)
        : z.hostname),
      (L.headers = {
        ...L.headers,
        "Sec-WebSocket-Version": L.protocolVersion,
        "Sec-WebSocket-Key": ts,
        Connection: "Upgrade",
        Upgrade: "websocket",
      }),
      (L.path = z.pathname + z.search),
      (L.timeout = L.handshakeTimeout),
      L.perMessageDeflate &&
        ((lt = new d(
          L.perMessageDeflate !== !0 ? L.perMessageDeflate : {},
          !1,
          L.maxPayload,
        )),
        (L.headers["Sec-WebSocket-Extensions"] = T({
          [d.extensionName]: lt.offer(),
        }))),
      M.length)
    ) {
      for (const W of M) {
        if (typeof W != "string" || !me.test(W) || ut.has(W))
          throw new SyntaxError(
            "An invalid or duplicated subprotocol was specified",
          );
        ut.add(W);
      }
      L.headers["Sec-WebSocket-Protocol"] = M.join(",");
    }
    if (
      (L.origin &&
        (L.protocolVersion < 13
          ? (L.headers["Sec-WebSocket-Origin"] = L.origin)
          : (L.headers.Origin = L.origin)),
      (z.username || z.password) && (L.auth = `${z.username}:${z.password}`),
      Je)
    ) {
      const W = L.path.split(":");
      ((L.socketPath = W[0]), (L.path = W[1]));
    }
    let ne;
    if (L.followRedirects) {
      if (S._redirects === 0) {
        ((S._originalIpc = Je),
          (S._originalSecure = Ge),
          (S._originalHostOrSocketPath = Je ? L.socketPath : z.host));
        const W = $ && $.headers;
        if ((($ = { ...$, headers: {} }), W))
          for (const [ie, He] of Object.entries(W))
            $.headers[ie.toLowerCase()] = He;
      } else if (S.listenerCount("redirect") === 0) {
        const W = Je
          ? S._originalIpc
            ? L.socketPath === S._originalHostOrSocketPath
            : !1
          : S._originalIpc
            ? !1
            : z.host === S._originalHostOrSocketPath;
        (!W || (S._originalSecure && !Ge)) &&
          (delete L.headers.authorization,
          delete L.headers.cookie,
          W || delete L.headers.host,
          (L.auth = void 0));
      }
      (L.auth &&
        !$.headers.authorization &&
        ($.headers.authorization =
          "Basic " + Buffer.from(L.auth).toString("base64")),
        (ne = S._req = ns(L)),
        S._redirects && S.emit("redirect", S.url, ne));
    } else ne = S._req = ns(L);
    (L.timeout &&
      ne.on("timeout", () => {
        ce(S, ne, "Opening handshake has timed out");
      }),
      ne.on("error", (W) => {
        ne === null || ne[H] || ((ne = S._req = null), Le(S, W));
      }),
      ne.on("response", (W) => {
        const ie = W.headers.location,
          He = W.statusCode;
        if (ie && L.followRedirects && He >= 300 && He < 400) {
          if (++S._redirects > L.maxRedirects) {
            ce(S, ne, "Maximum redirects exceeded");
            return;
          }
          ne.abort();
          let dt;
          try {
            dt = new l(ie, A);
          } catch {
            const We = new SyntaxError(`Invalid URL: ${ie}`);
            Le(S, We);
            return;
          }
          be(S, dt, M, $);
        } else
          S.emit("unexpected-response", ne, W) ||
            ce(S, ne, `Unexpected server response: ${W.statusCode}`);
      }),
      ne.on("upgrade", (W, ie, He) => {
        if ((S.emit("upgrade", W), S.readyState !== F.CONNECTING)) return;
        ne = S._req = null;
        const dt = W.headers.upgrade;
        if (dt === void 0 || dt.toLowerCase() !== "websocket") {
          ce(S, ie, "Invalid Upgrade header");
          return;
        }
        const rs = i("sha1")
          .update(ts + E)
          .digest("base64");
        if (W.headers["sec-websocket-accept"] !== rs) {
          ce(S, ie, "Invalid Sec-WebSocket-Accept header");
          return;
        }
        const We = W.headers["sec-websocket-protocol"];
        let pt;
        if (
          (We !== void 0
            ? ut.size
              ? ut.has(We) || (pt = "Server sent an invalid subprotocol")
              : (pt = "Server sent a subprotocol but none was requested")
            : ut.size && (pt = "Server sent no subprotocol"),
          pt)
        ) {
          ce(S, ie, pt);
          return;
        }
        We && (S._protocol = We);
        const ss = W.headers["sec-websocket-extensions"];
        if (ss !== void 0) {
          if (!lt) {
            ce(
              S,
              ie,
              "Server sent a Sec-WebSocket-Extensions header but no extension was requested",
            );
            return;
          }
          let Tn;
          try {
            Tn = k(ss);
          } catch {
            ce(S, ie, "Invalid Sec-WebSocket-Extensions header");
            return;
          }
          const os = Object.keys(Tn);
          if (os.length !== 1 || os[0] !== d.extensionName) {
            ce(S, ie, "Server indicated an extension that was not requested");
            return;
          }
          try {
            lt.accept(Tn[d.extensionName]);
          } catch {
            ce(S, ie, "Invalid Sec-WebSocket-Extensions header");
            return;
          }
          S._extensions[d.extensionName] = lt;
        }
        S.setSocket(ie, He, {
          allowSynchronousEvents: L.allowSynchronousEvents,
          generateMask: L.generateMask,
          maxPayload: L.maxPayload,
          skipUTF8Validation: L.skipUTF8Validation,
        });
      }),
      L.finishRequest ? L.finishRequest(ne, S) : ne.end());
  }
  function Le(S, A) {
    ((S._readyState = F.CLOSING),
      (S._errorEmitted = !0),
      S.emit("error", A),
      S.emitClose());
  }
  function vn(S) {
    return ((S.path = S.socketPath), r.connect(S));
  }
  function Sn(S) {
    return (
      (S.path = void 0),
      !S.servername &&
        S.servername !== "" &&
        (S.servername = r.isIP(S.host) ? "" : S.host),
      o.connect(S)
    );
  }
  function ce(S, A, M) {
    S._readyState = F.CLOSING;
    const $ = new Error(M);
    (Error.captureStackTrace($, ce),
      A.setHeader
        ? ((A[H] = !0),
          A.abort(),
          A.socket && !A.socket.destroyed && A.socket.destroy(),
          process.nextTick(Le, S, $))
        : (A.destroy($),
          A.once("error", S.emit.bind(S, "error")),
          A.once("close", S.emitClose.bind(S))));
  }
  function wn(S, A, M) {
    if (A) {
      const $ = v(A) ? A.size : N(A).length;
      S._socket ? (S._sender._bufferedBytes += $) : (S._bufferedAmount += $);
    }
    if (M) {
      const $ = new Error(
        `WebSocket is not open: readyState ${S.readyState} (${B[S.readyState]})`,
      );
      process.nextTick(M, $);
    }
  }
  function rc(S, A) {
    const M = this[C];
    ((M._closeFrameReceived = !0),
      (M._closeMessage = A),
      (M._closeCode = S),
      M._socket[C] !== void 0 &&
        (M._socket.removeListener("data", Lt),
        process.nextTick(Kr, M._socket),
        S === 1005 ? M.close() : M.close(S, A)));
  }
  function sc() {
    const S = this[C];
    S.isPaused || S._socket.resume();
  }
  function oc(S) {
    const A = this[C];
    (A._socket[C] !== void 0 &&
      (A._socket.removeListener("data", Lt),
      process.nextTick(Kr, A._socket),
      A.close(S[O])),
      A._errorEmitted || ((A._errorEmitted = !0), A.emit("error", S)));
  }
  function Vr() {
    this[C].emitClose();
  }
  function ic(S, A) {
    this[C].emit("message", S, A);
  }
  function ac(S) {
    const A = this[C];
    (A._autoPong && A.pong(S, !this._isServer, p), A.emit("ping", S));
  }
  function cc(S) {
    this[C].emit("pong", S);
  }
  function Kr(S) {
    S.resume();
  }
  function uc(S) {
    const A = this[C];
    A.readyState !== F.CLOSED &&
      (A.readyState === F.OPEN && ((A._readyState = F.CLOSING), Yr(A)),
      this._socket.end(),
      A._errorEmitted || ((A._errorEmitted = !0), A.emit("error", S)));
  }
  function Yr(S) {
    S._closeTimer = setTimeout(S._socket.destroy.bind(S._socket), q);
  }
  function Zr() {
    const S = this[C];
    (this.removeListener("close", Zr),
      this.removeListener("data", Lt),
      this.removeListener("end", Xr),
      (S._readyState = F.CLOSING));
    let A;
    (!this._readableState.endEmitted &&
      !S._closeFrameReceived &&
      !S._receiver._writableState.errorEmitted &&
      (A = S._socket.read()) !== null &&
      S._receiver.write(A),
      S._receiver.end(),
      (this[C] = void 0),
      clearTimeout(S._closeTimer),
      S._receiver._writableState.finished ||
      S._receiver._writableState.errorEmitted
        ? S.emitClose()
        : (S._receiver.on("error", Vr), S._receiver.on("finish", Vr)));
  }
  function Lt(S) {
    this[C]._receiver.write(S) || this.pause();
  }
  function Xr() {
    const S = this[C];
    ((S._readyState = F.CLOSING), S._receiver.end(), this.end());
  }
  function Qr() {
    const S = this[C];
    (this.removeListener("error", Qr),
      this.on("error", p),
      S && ((S._readyState = F.CLOSING), this.destroy()));
  }
  return Fn;
}
var Un, Qs;
function zp() {
  if (Qs) return Un;
  ((Qs = 1), zr());
  const { Duplex: t } = bt;
  function e(s) {
    s.emit("close");
  }
  function n() {
    !this.destroyed && this._writableState.finished && this.destroy();
  }
  function r(s) {
    (this.removeListener("error", r),
      this.destroy(),
      this.listenerCount("error") === 0 && this.emit("error", s));
  }
  function o(s, i) {
    let c = !0;
    const u = new t({
      ...i,
      autoDestroy: !1,
      emitClose: !1,
      objectMode: !1,
      writableObjectMode: !1,
    });
    return (
      s.on("message", function (d, g) {
        const f = !g && u._readableState.objectMode ? d.toString() : d;
        u.push(f) || s.pause();
      }),
      s.once("error", function (d) {
        u.destroyed || ((c = !1), u.destroy(d));
      }),
      s.once("close", function () {
        u.destroyed || u.push(null);
      }),
      (u._destroy = function (l, d) {
        if (s.readyState === s.CLOSED) {
          (d(l), process.nextTick(e, u));
          return;
        }
        let g = !1;
        (s.once("error", function (v) {
          ((g = !0), d(v));
        }),
          s.once("close", function () {
            (g || d(l), process.nextTick(e, u));
          }),
          c && s.terminate());
      }),
      (u._final = function (l) {
        if (s.readyState === s.CONNECTING) {
          s.once("open", function () {
            u._final(l);
          });
          return;
        }
        s._socket !== null &&
          (s._socket._writableState.finished
            ? (l(), u._readableState.endEmitted && u.destroy())
            : (s._socket.once("finish", function () {
                l();
              }),
              s.close()));
      }),
      (u._read = function () {
        s.isPaused && s.resume();
      }),
      (u._write = function (l, d, g) {
        if (s.readyState === s.CONNECTING) {
          s.once("open", function () {
            u._write(l, d, g);
          });
          return;
        }
        s.send(l, g);
      }),
      u.on("end", n),
      u.on("error", r),
      u
    );
  }
  return ((Un = o), Un);
}
zp();
Za();
Xa();
var Vp = zr();
const Kp = ro(Vp);
var $n, eo;
function Yp() {
  if (eo) return $n;
  eo = 1;
  const { tokenChars: t } = Nt();
  function e(n) {
    const r = new Set();
    let o = -1,
      s = -1,
      i = 0;
    for (i; i < n.length; i++) {
      const u = n.charCodeAt(i);
      if (s === -1 && t[u] === 1) o === -1 && (o = i);
      else if (i !== 0 && (u === 32 || u === 9))
        s === -1 && o !== -1 && (s = i);
      else if (u === 44) {
        if (o === -1)
          throw new SyntaxError(`Unexpected character at index ${i}`);
        s === -1 && (s = i);
        const l = n.slice(o, s);
        if (r.has(l))
          throw new SyntaxError(`The "${l}" subprotocol is duplicated`);
        (r.add(l), (o = s = -1));
      } else throw new SyntaxError(`Unexpected character at index ${i}`);
    }
    if (o === -1 || s !== -1) throw new SyntaxError("Unexpected end of input");
    const c = n.slice(o, i);
    if (r.has(c)) throw new SyntaxError(`The "${c}" subprotocol is duplicated`);
    return (r.add(c), r);
  }
  return (($n = { parse: e }), $n);
}
var Bn, to;
function Zp() {
  if (to) return Bn;
  to = 1;
  const t = so,
    e = oo,
    { Duplex: n } = bt,
    { createHash: r } = nr,
    o = Qa(),
    s = yn(),
    i = Yp(),
    c = zr(),
    { GUID: u, kWebSocket: l } = Ne(),
    d = /^[+/0-9A-Za-z]{22}==$/,
    g = 0,
    f = 1,
    v = 2;
  class _ extends t {
    constructor(p, m) {
      if (
        (super(),
        (p = {
          allowSynchronousEvents: !0,
          autoPong: !0,
          maxPayload: 100 * 1024 * 1024,
          skipUTF8Validation: !1,
          perMessageDeflate: !1,
          handleProtocols: null,
          clientTracking: !0,
          verifyClient: null,
          noServer: !1,
          backlog: null,
          server: null,
          host: null,
          path: null,
          port: null,
          WebSocket: c,
          ...p,
        }),
        (p.port == null && !p.server && !p.noServer) ||
          (p.port != null && (p.server || p.noServer)) ||
          (p.server && p.noServer))
      )
        throw new TypeError(
          'One and only one of the "port", "server", or "noServer" options must be specified',
        );
      if (
        (p.port != null
          ? ((this._server = e.createServer((x, T) => {
              const k = e.STATUS_CODES[426];
              (T.writeHead(426, {
                "Content-Length": k.length,
                "Content-Type": "text/plain",
              }),
                T.end(k));
            })),
            this._server.listen(p.port, p.host, p.backlog, m))
          : p.server && (this._server = p.server),
        this._server)
      ) {
        const x = this.emit.bind(this, "connection");
        this._removeListeners = w(this._server, {
          listening: this.emit.bind(this, "listening"),
          error: this.emit.bind(this, "error"),
          upgrade: (T, k, N) => {
            this.handleUpgrade(T, k, N, x);
          },
        });
      }
      (p.perMessageDeflate === !0 && (p.perMessageDeflate = {}),
        p.clientTracking &&
          ((this.clients = new Set()), (this._shouldEmitClose = !1)),
        (this.options = p),
        (this._state = g));
    }
    address() {
      if (this.options.noServer)
        throw new Error('The server is operating in "noServer" mode');
      return this._server ? this._server.address() : null;
    }
    close(p) {
      if (this._state === v) {
        (p &&
          this.once("close", () => {
            p(new Error("The server is not running"));
          }),
          process.nextTick(E, this));
        return;
      }
      if ((p && this.once("close", p), this._state !== f))
        if (((this._state = f), this.options.noServer || this.options.server))
          (this._server &&
            (this._removeListeners(),
            (this._removeListeners = this._server = null)),
            this.clients
              ? this.clients.size
                ? (this._shouldEmitClose = !0)
                : process.nextTick(E, this)
              : process.nextTick(E, this));
        else {
          const m = this._server;
          (this._removeListeners(),
            (this._removeListeners = this._server = null),
            m.close(() => {
              E(this);
            }));
        }
    }
    shouldHandle(p) {
      if (this.options.path) {
        const m = p.url.indexOf("?");
        if ((m !== -1 ? p.url.slice(0, m) : p.url) !== this.options.path)
          return !1;
      }
      return !0;
    }
    handleUpgrade(p, m, x, T) {
      m.on("error", b);
      const k = p.headers["sec-websocket-key"],
        N = p.headers.upgrade,
        q = +p.headers["sec-websocket-version"];
      if (p.method !== "GET") {
        O(this, p, m, 405, "Invalid HTTP method");
        return;
      }
      if (N === void 0 || N.toLowerCase() !== "websocket") {
        O(this, p, m, 400, "Invalid Upgrade header");
        return;
      }
      if (k === void 0 || !d.test(k)) {
        O(this, p, m, 400, "Missing or invalid Sec-WebSocket-Key header");
        return;
      }
      if (q !== 13 && q !== 8) {
        O(this, p, m, 400, "Missing or invalid Sec-WebSocket-Version header", {
          "Sec-WebSocket-Version": "13, 8",
        });
        return;
      }
      if (!this.shouldHandle(p)) {
        I(m, 400);
        return;
      }
      const H = p.headers["sec-websocket-protocol"];
      let K = new Set();
      if (H !== void 0)
        try {
          K = i.parse(H);
        } catch {
          O(this, p, m, 400, "Invalid Sec-WebSocket-Protocol header");
          return;
        }
      const B = p.headers["sec-websocket-extensions"],
        me = {};
      if (this.options.perMessageDeflate && B !== void 0) {
        const F = new s(
          this.options.perMessageDeflate,
          !0,
          this.options.maxPayload,
        );
        try {
          const be = o.parse(B);
          be[s.extensionName] &&
            (F.accept(be[s.extensionName]), (me[s.extensionName] = F));
        } catch {
          O(
            this,
            p,
            m,
            400,
            "Invalid or unacceptable Sec-WebSocket-Extensions header",
          );
          return;
        }
      }
      if (this.options.verifyClient) {
        const F = {
          origin: p.headers[`${q === 8 ? "sec-websocket-origin" : "origin"}`],
          secure: !!(p.socket.authorized || p.socket.encrypted),
          req: p,
        };
        if (this.options.verifyClient.length === 2) {
          this.options.verifyClient(F, (be, Le, vn, Sn) => {
            if (!be) return I(m, Le || 401, vn, Sn);
            this.completeUpgrade(me, k, K, p, m, x, T);
          });
          return;
        }
        if (!this.options.verifyClient(F)) return I(m, 401);
      }
      this.completeUpgrade(me, k, K, p, m, x, T);
    }
    completeUpgrade(p, m, x, T, k, N, q) {
      if (!k.readable || !k.writable) return k.destroy();
      if (k[l])
        throw new Error(
          "server.handleUpgrade() was called more than once with the same socket, possibly due to a misconfiguration",
        );
      if (this._state > g) return I(k, 503);
      const K = [
          "HTTP/1.1 101 Switching Protocols",
          "Upgrade: websocket",
          "Connection: Upgrade",
          `Sec-WebSocket-Accept: ${r("sha1")
            .update(m + u)
            .digest("base64")}`,
        ],
        B = new this.options.WebSocket(null, void 0, this.options);
      if (x.size) {
        const me = this.options.handleProtocols
          ? this.options.handleProtocols(x, T)
          : x.values().next().value;
        me && (K.push(`Sec-WebSocket-Protocol: ${me}`), (B._protocol = me));
      }
      if (p[s.extensionName]) {
        const me = p[s.extensionName].params,
          F = o.format({ [s.extensionName]: [me] });
        (K.push(`Sec-WebSocket-Extensions: ${F}`), (B._extensions = p));
      }
      (this.emit("headers", K, T),
        k.write(
          K.concat(`\r
`).join(`\r
`),
        ),
        k.removeListener("error", b),
        B.setSocket(k, N, {
          allowSynchronousEvents: this.options.allowSynchronousEvents,
          maxPayload: this.options.maxPayload,
          skipUTF8Validation: this.options.skipUTF8Validation,
        }),
        this.clients &&
          (this.clients.add(B),
          B.on("close", () => {
            (this.clients.delete(B),
              this._shouldEmitClose &&
                !this.clients.size &&
                process.nextTick(E, this));
          })),
        q(B, T));
    }
  }
  Bn = _;
  function w(C, p) {
    for (const m of Object.keys(p)) C.on(m, p[m]);
    return function () {
      for (const x of Object.keys(p)) C.removeListener(x, p[x]);
    };
  }
  function E(C) {
    ((C._state = v), C.emit("close"));
  }
  function b() {
    this.destroy();
  }
  function I(C, p, m, x) {
    ((m = m || e.STATUS_CODES[p]),
      (x = {
        Connection: "close",
        "Content-Type": "text/html",
        "Content-Length": Buffer.byteLength(m),
        ...x,
      }),
      C.once("finish", C.destroy),
      C.end(
        `HTTP/1.1 ${p} ${e.STATUS_CODES[p]}\r
` +
          Object.keys(x).map((T) => `${T}: ${x[T]}`).join(`\r
`) +
          `\r
\r
` +
          m,
      ));
  }
  function O(C, p, m, x, T, k) {
    if (C.listenerCount("wsClientError")) {
      const N = new Error(T);
      (Error.captureStackTrace(N, O), C.emit("wsClientError", N, m, p));
    } else I(m, x, T, k);
  }
  return Bn;
}
Zp();
class ec extends kt {
  #e;
  #t;
  #n = { status: "disconnected", websocket: void 0 };
  #r;
  #i;
  #o;
  _firstAudioTimestamp;
  _audioLengthMs = 0;
  #a = !1;
  #s;
  #c;
  constructor(e = {}) {
    (super(e),
      (this.#t = e.url),
      (this.#r = e.useInsecureApiKey ?? !1),
      (this.#s = e.createWebSocket),
      (this.#c = e.skipOpenEventListeners ?? !1));
  }
  getCommonRequestHeaders() {
    return Wa;
  }
  get status() {
    return this.#n.status;
  }
  get connectionState() {
    return this.#n;
  }
  get muted() {
    return null;
  }
  get currentItemId() {
    return this.#i;
  }
  _onAudio(e) {
    this.emit("audio", e);
  }
  async #d(e, n, r) {
    if (this.#n.websocket) {
      e();
      return;
    }
    if (!this.#e)
      throw new G(
        "API key is not set. Please call `connect()` with an API key first.",
      );
    let o = null;
    if (this.#s) o = await this.#s({ url: this.#t, apiKey: this.#e });
    else {
      const i = {
        headers: {
          Authorization: `Bearer ${this.#e}`,
          ...this.getCommonRequestHeaders(),
        },
      };
      o = new Kp(this.#t, i);
    }
    ((this.#n = { status: "connecting", websocket: o }),
      this.emit("connection_change", this.#n.status));
    const s = () => {
      ((this.#n = { status: "connected", websocket: o }),
        this.emit("connection_change", this.#n.status),
        this._onOpen(),
        e());
    };
    (this.#c === !0 ? s() : o.addEventListener("open", s),
      o.addEventListener("error", (i) => {
        (this._onError(i),
          (this.#n = { status: "disconnected", websocket: void 0 }),
          this.emit("connection_change", this.#n.status),
          n(i));
      }),
      o.addEventListener("message", (i) => {
        this._onMessage(i);
        const { data: c, isGeneric: u } = Wr(i);
        if (!(!c || u))
          if (c.type === "response.output_audio.delta") {
            ((this.#o = c.content_index),
              (this.#i = c.item_id),
              this._firstAudioTimestamp === void 0 &&
                ((this._firstAudioTimestamp = Date.now()),
                (this._audioLengthMs = 0)));
            const l = Ga(c.delta),
              d = this._rawSessionConfig?.audio?.output?.format;
            if (d && typeof d == "object") {
              const f = d.type;
              if (f === "audio/pcmu" || f === "audio/pcma")
                this._audioLengthMs += l.byteLength / 8;
              else if (f === "audio/pcm") {
                const v = d.rate ?? 24e3;
                this._audioLengthMs += (l.byteLength / 2 / v) * 1e3;
              } else this._audioLengthMs += l.byteLength / 24 / 2;
            } else
              typeof d == "string"
                ? d.startsWith("g711_")
                  ? (this._audioLengthMs += l.byteLength / 8)
                  : (this._audioLengthMs += l.byteLength / 24 / 2)
                : (this._audioLengthMs += l.byteLength / 24 / 2);
            const g = { type: "audio", data: l, responseId: c.response_id };
            this._onAudio(g);
          } else if (c.type === "input_audio_buffer.speech_started") {
            const l =
              this._rawSessionConfig?.audio?.input?.turn_detection
                ?.interrupt_response ?? !1;
            this.interrupt(!l);
          } else
            c.type === "response.created"
              ? (this.#a = !0)
              : c.type === "response.done"
                ? (this.#a = !1)
                : c.type === "session.created" &&
                  ((this._tracingConfig = c.session.tracing),
                  this._updateTracingConfig(r.tracing ?? "auto"));
      }),
      o.addEventListener("close", () => {
        ((this.#n = { status: "disconnected", websocket: void 0 }),
          this.emit("connection_change", this.#n.status),
          this._onClose());
      }));
  }
  async connect(e) {
    const n = e.model ?? this.currentModel;
    ((this.currentModel = n), (this.#e = await this._getApiKey(e)));
    const r =
      e.url ??
      this.#t ??
      `wss://api.openai.com/v1/realtime?model=${this.currentModel}`;
    this.#t = r;
    const o = { ...(e.initialSessionConfig || {}), model: this.currentModel };
    (await new Promise((s, i) => {
      this.#d(s, i, o).catch(i);
    }),
      await this.updateSessionConfig(o));
  }
  sendEvent(e) {
    if (!this.#n.websocket)
      throw new Error(
        "WebSocket is not connected. Make sure you call `connect()` before sending events.",
      );
    this.#n.websocket.send(JSON.stringify(e));
  }
  close() {
    (this.#n.websocket?.close(),
      (this.#i = void 0),
      (this._firstAudioTimestamp = void 0),
      (this._audioLengthMs = 0),
      (this.#o = void 0));
  }
  mute(e) {
    throw new Error(
      "Mute is not supported for the WebSocket transport. You have to mute the audio input yourself.",
    );
  }
  sendAudio(e, n = {}) {
    this.#n.status === "connected" && super.sendAudio(e, n);
  }
  _cancelResponse() {
    this.#a && (this.sendEvent({ type: "response.cancel" }), (this.#a = !1));
  }
  _interrupt(e, n = !0) {
    if (e < 0) return;
    n && this._cancelResponse();
    const r = this._audioLengthMs ?? Number.POSITIVE_INFINITY,
      o = Math.max(0, Math.floor(Math.min(e, r)));
    (this.emit("audio_interrupted"),
      this.sendEvent({
        type: "conversation.item.truncate",
        item_id: this.#i,
        content_index: this.#o,
        audio_end_ms: o,
      }));
  }
  interrupt(e = !0) {
    if (!this.#i || typeof this._firstAudioTimestamp != "number") return;
    const n = Date.now() - this._firstAudioTimestamp;
    (n >= 0 && this._interrupt(n, e),
      (this.#i = void 0),
      (this._firstAudioTimestamp = void 0),
      (this._audioLengthMs = 0),
      (this.#o = void 0));
  }
}
const tc = Symbol("backgroundResult");
function Xp(t) {
  return { [tc]: !0, content: t };
}
function nc(t) {
  return typeof t == "object" && t !== null && tc in t;
}
function Qp(t) {
  return (
    t.type === "function" ||
    (t.type === "hosted_tool" && t.name === "hosted_mcp")
  );
}
function ef(t) {
  if (t.type === "function") return t;
  if (t.type === "hosted_tool" && t.name === "hosted_mcp") {
    const e =
      t.providerData.server_url && t.providerData.server_url.length > 0
        ? t.providerData.server_url
        : void 0;
    return {
      type: "mcp",
      server_label: t.providerData.server_label,
      server_url: e,
      headers: t.providerData.headers,
      allowed_tools: t.providerData.allowed_tools,
      require_approval: t.providerData.require_approval,
    };
  }
  throw new G(`Invalid tool type: ${t}`);
}
function tf() {
  return JSON.parse(JSON.stringify(_e));
}
class nf extends wt {
  initialAgent;
  options;
  #e;
  #t;
  #n;
  #r;
  #i = [];
  #o;
  #a = {};
  #s = [];
  #c;
  #d = {};
  #u = !1;
  #p = new Map();
  #l = [];
  #_ = tf();
  #g = !0;
  constructor(e, n = {}) {
    (super(),
      (this.initialAgent = e),
      (this.options = n),
      (typeof n.transport > "u" && Fd()) || n.transport === "webrtc"
        ? (this.#e = new Ya())
        : n.transport === "websocket" || typeof n.transport > "u"
          ? (this.#e = new ec())
          : (this.#e = n.transport),
      (this.#t = e),
      (this.#r = new Fe({ ...(n.context ?? {}), history: this.#s })),
      (this.#i = (n.outputGuardrails ?? []).map(jd)),
      (this.#o = Bd(n.outputGuardrailSettings ?? {})),
      (this.#c = n.historyStoreAudio ?? !1),
      (this.#g = n.automaticallyTriggerResponseForMcpToolCalls ?? !0));
  }
  get transport() {
    return this.#e;
  }
  get currentAgent() {
    return this.#t;
  }
  get usage() {
    return this.#r.usage;
  }
  get context() {
    return this.#r;
  }
  get muted() {
    return this.#e.muted;
  }
  get history() {
    return this.#s;
  }
  get availableMcpTools() {
    return this.#l;
  }
  async #f(e) {
    this.#t = e;
    const n = await this.#t.getEnabledHandoffs(this.#r),
      r = n.map((c) => c.getHandoffAsFunctionTool()),
      o = (await this.#t.getAllTools(this.#r)).filter(Qp).map(ef),
      s = typeof this.#t.tools < "u" || typeof this.#t.mcpServers < "u",
      i = n.length > 0;
    ((this.#n = s || i ? [...o, ...r] : void 0), this.#v());
  }
  async #h(e = {}) {
    const n = await this.#t.getSystemPrompt(this.#r),
      r = this.options.tracingDisabled
        ? null
        : this.options.workflowName
          ? { workflow_name: this.options.workflowName }
          : "auto";
    r !== null && r !== "auto"
      ? (this.options.groupId && (r.group_id = this.options.groupId),
        this.options.traceMetadata && (r.metadata = this.options.traceMetadata))
      : (this.options.groupId || this.options.traceMetadata) &&
        pe.warn(
          "In order to set traceMetadata or a groupId you need to specify a workflowName.",
        );
    const s = {
      ...{ ...(this.#_ ?? {}), ...(this.options.config ?? {}), ...(e ?? {}) },
      instructions: n,
      voice: this.#t.voice,
      model: this.options.model,
      tools: this.#n,
      tracing: r,
      prompt:
        typeof this.#t.prompt == "function"
          ? await this.#t.prompt(this.#r, this.#t)
          : this.#t.prompt,
    };
    return ((this.#_ = s), s);
  }
  async updateAgent(e) {
    return (
      this.#t.emit("agent_handoff", this.#r, e),
      this.emit("agent_handoff", this.#r, this.#t, e),
      await this.#f(e),
      await this.#e.updateSessionConfig(await this.#h()),
      e
    );
  }
  async #S(e, n) {
    const r = await n.onInvokeHandoff(this.#r, e.arguments);
    (this.#t.emit("agent_handoff", this.#r, r),
      this.emit("agent_handoff", this.#r, this.#t, r),
      await this.#f(r),
      await this.#e.updateSessionConfig(await this.#h()));
    const o = Ar(r);
    return (this.#e.sendFunctionCallOutput(e, o, !0), r);
  }
  async #m(e, n) {
    this.#r.context.history = JSON.parse(JSON.stringify(this.#s));
    let r = e.arguments;
    if (
      (n.parameters &&
        ($e(n.parameters) ? (r = n.parameters.parse(r)) : (r = JSON.parse(r))),
      await n.needsApproval(this.#r, r, e.callId))
    ) {
      const c = this.context.isToolApproved({
        toolName: n.name,
        callId: e.callId,
      });
      if (c === !1) {
        (this.emit("agent_tool_start", this.#r, this.#t, n, { toolCall: e }),
          this.#t.emit("agent_tool_start", this.#r, n, { toolCall: e }));
        const u = "Tool execution was not approved.";
        (this.#e.sendFunctionCallOutput(e, u, !0),
          this.emit("agent_tool_end", this.#r, this.#t, n, u, { toolCall: e }),
          this.#t.emit("agent_tool_end", this.#r, n, u, { toolCall: e }));
        return;
      } else if (typeof c > "u") {
        this.emit("tool_approval_requested", this.#r, this.#t, {
          type: "function_approval",
          tool: n,
          approvalItem: new ue(e, this.#t),
        });
        return;
      }
    }
    (this.emit("agent_tool_start", this.#r, this.#t, n, { toolCall: e }),
      this.#t.emit("agent_tool_start", this.#r, n, { toolCall: e }),
      (this.#r.context.history = JSON.parse(JSON.stringify(this.#s))));
    const s = await n.invoke(this.#r, e.arguments, { toolCall: e });
    let i;
    (nc(s)
      ? ((i = Oe(s.content)), this.#e.sendFunctionCallOutput(e, i, !1))
      : ((i = Oe(s)), this.#e.sendFunctionCallOutput(e, i, !0)),
      this.emit("agent_tool_end", this.#r, this.#t, n, i, { toolCall: e }),
      this.#t.emit("agent_tool_end", this.#r, n, i, { toolCall: e }));
  }
  async #w(e) {
    const n = await this.#t.getEnabledHandoffs(this.#r),
      r = new Map(n.map((c) => [c.toolName, c])),
      o = await this.#t.getAllTools(this.#r),
      s = new Map(o.map((c) => [c.name, c])),
      i = r.get(e.name);
    if (i) await this.#S(e, i);
    else {
      const c = s.get(e.name);
      if (c && c.type === "function") await this.#m(e, c);
      else throw new ae(`Tool ${e.name} not found`);
    }
  }
  async #y(e, n, r) {
    if (this.#i.length === 0) return;
    const o = { agent: this.#t, agentOutput: e, context: this.#r },
      i = (await Promise.all(this.#i.map((c) => c.run(o)))).find(
        (c) => c.output.tripwireTriggered,
      );
    if (i) {
      if (this.#d[n]) return;
      this.#d[n] = !0;
      const c = new gt(
        `Output guardrail triggered: ${JSON.stringify(i.output.outputInfo)}`,
        i,
      );
      (this.emit("guardrail_tripped", this.#r, this.#t, c, { itemId: r }),
        this.interrupt());
      const u = qd(i);
      this.sendMessage(u);
      return;
    }
  }
  #T() {
    (this.#e.on("*", (r) => {
      if (
        (this.emit("transport_event", r),
        r.type === "conversation.item.input_audio_transcription.completed")
      )
        try {
          const o = r;
          ((this.#s = Us(this.#s, o, this.#c)),
            (this.#r.context.history = this.#s),
            this.emit("history_updated", this.#s));
        } catch (o) {
          this.emit("error", { type: "error", error: o });
        }
    }),
      this.#e.on("mcp_tools_listed", ({ serverLabel: r, tools: o }) => {
        try {
          (this.#p.set(r, o ?? []), this.#v());
        } catch (s) {
          this.emit("error", { type: "error", error: s });
        }
      }),
      this.#e.on("audio", (r) => {
        (this.#u ||
          ((this.#u = !0), this.emit("audio_start", this.#r, this.#t)),
          this.emit("audio", r));
      }),
      this.#e.on("turn_started", () => {
        ((this.#u = !1),
          this.emit("agent_start", this.#r, this.#t),
          this.#t.emit("agent_start", this.#r, this.#t));
      }),
      this.#e.on("turn_done", (r) => {
        const o = r.response.output[r.response.output.length - 1],
          s = Ha(o) ?? "",
          i = o?.id ?? "";
        (this.emit("agent_end", this.#r, this.#t, s),
          this.#t.emit("agent_end", this.#r, s),
          this.#y(s, r.response.id, i));
      }),
      this.#e.on("audio_done", () => {
        (this.#u && (this.#u = !1),
          this.emit("audio_stopped", this.#r, this.#t));
      }));
    let e = 0,
      n;
    (this.#e.on("audio_transcript_delta", (r) => {
      try {
        const o = r.delta,
          s = r.itemId,
          i = r.responseId;
        n !== s && ((n = s), (e = 0));
        const u = (this.#a[s] ?? "") + o;
        if (((this.#a[s] = u), this.#o.debounceTextLength < 0)) return;
        const l = Math.floor(u.length / this.#o.debounceTextLength);
        l > e && ((e = l), this.#y(u, i, s));
      } catch (o) {
        this.emit("error", { type: "error", error: o });
      }
    }),
      this.#e.on("item_update", (r) => {
        try {
          const o = !this.#s.some((s) => s.itemId === r.itemId);
          if (
            ((this.#s = Us(this.#s, r, this.#c)),
            (this.#r.context.history = this.#s),
            o)
          ) {
            const s = this.#s.find((i) => i.itemId === r.itemId);
            s && this.emit("history_added", s);
          }
          this.emit("history_updated", this.#s);
        } catch (o) {
          this.emit("error", { type: "error", error: o });
        }
      }),
      this.#e.on("item_deleted", (r) => {
        try {
          ((this.#s = this.#s.filter((o) => o.itemId !== r.itemId)),
            (this.#r.context.history = this.#s),
            this.emit("history_updated", this.#s));
        } catch (o) {
          this.emit("error", { type: "error", error: o });
        }
      }),
      this.#e.on("function_call", async (r) => {
        try {
          await this.#w(r);
        } catch (o) {
          (pe.error("Error handling function call", o),
            this.emit("error", { type: "error", error: o }));
        }
      }),
      this.#e.on("usage_update", (r) => {
        this.#r.usage.add(r);
      }),
      this.#e.on("audio_interrupted", () => {
        (this.#u && (this.#u = !1),
          this.emit("audio_interrupted", this.#r, this.#t));
      }),
      this.#e.on("error", (r) => {
        this.emit("error", r);
      }),
      this.#e.on("mcp_tool_call_completed", (r) => {
        (this.emit("mcp_tool_call_completed", this.#r, this.#t, r),
          this.#g && this.#e.sendEvent({ type: "response.create" }));
      }),
      this.#e.on("mcp_approval_request", (r) => {
        this.emit("tool_approval_requested", this.#r, this.#t, {
          type: "mcp_approval_request",
          approvalItem: Ud(this.#t, r),
        });
      }));
  }
  #v() {
    const e = this.#n?.filter((c) => c.type === "mcp"),
      n = (c) => {
        const u = c.allowed_tools;
        if (u) {
          if (Array.isArray(u)) return u;
          if (u && Array.isArray(u.tool_names)) return u.tool_names;
        }
      },
      r = new Map();
    for (const c of e) {
      const u = this.#p.get(c.server_label) ?? [],
        l = n(c);
      for (const d of u)
        (l && !l.includes(d.name)) || r.has(d.name) || r.set(d.name, d);
    }
    const o = Array.from(r.values()),
      s = this.#l;
    (s.length !== o.length ||
      JSON.stringify(s.map((c) => c.name).sort()) !==
        JSON.stringify(o.map((c) => c.name).sort())) &&
      ((this.#l = o), this.emit("mcp_tools_changed", this.#l));
  }
  async connect(e) {
    (await this.#f(this.initialAgent),
      this.#T(),
      await this.#e.connect({
        apiKey: e.apiKey ?? this.options.apiKey,
        model: this.options.model,
        url: e.url,
        initialSessionConfig: await this.#h(this.options.config),
      }),
      (this.#s = []),
      this.emit("history_updated", this.#s));
  }
  updateHistory(e) {
    let n;
    (typeof e == "function" ? (n = e(this.#s)) : (n = e),
      this.#e.resetHistory(this.#s, n));
  }
  sendMessage(e, n = {}) {
    this.#e.sendMessage(e, n);
  }
  addImage(e, { triggerResponse: n = !0 } = {}) {
    this.#e.addImage(e, { triggerResponse: n });
  }
  mute(e) {
    this.#e.mute(e);
  }
  close() {
    ((this.#d = {}), this.#e.close());
  }
  sendAudio(e, n = {}) {
    this.#e.sendAudio(e, n);
  }
  interrupt() {
    this.#e.interrupt();
  }
  async approve(e, n = { alwaysApprove: !1 }) {
    this.#r.approveTool(e, n);
    const r = this.#t.tools.find((o) => o.name === e.rawItem.name);
    if (r && r.type === "function" && e.rawItem.type === "function_call")
      await this.#m(e.rawItem, r);
    else if (e.rawItem.type === "hosted_tool_call") {
      n.alwaysApprove &&
        pe.warn(
          "Always approving MCP tools is not supported. Use the allowed tools configuration instead.",
        );
      const o = $s(e);
      this.#e.sendMcpResponse(o, !0);
    } else throw new ae(`Tool ${e.rawItem.name} not found`);
  }
  async reject(e, n = { alwaysReject: !1 }) {
    this.#r.rejectTool(e, n);
    const r = this.#t.tools.find((o) => o.name === e.rawItem.name);
    if (r && r.type === "function" && e.rawItem.type === "function_call")
      await this.#m(e.rawItem, r);
    else if (e.rawItem.type === "hosted_tool_call") {
      n.alwaysReject &&
        pe.warn(
          "Always rejecting MCP tools is not supported. Use the allowed tools configuration instead.",
        );
      const o = $s(e);
      this.#e.sendMcpResponse(o, !1);
    } else throw new ae(`Tool ${e.rawItem.name} not found`);
  }
}
const rf = {
    base64ToArrayBuffer: Ga,
    arrayBufferToBase64: Ja,
    getLastTextFromAudioOutputMessage: Ha,
  },
  sf = Object.freeze(
    Object.defineProperty(
      {
        __proto__: null,
        DEFAULT_OPENAI_REALTIME_MODEL: Ka,
        DEFAULT_OPENAI_REALTIME_SESSION_CONFIG: _e,
        ModelBehaviorError: ae,
        OpenAIRealtimeBase: kt,
        OpenAIRealtimeWebRTC: Ya,
        OpenAIRealtimeWebSocket: ec,
        OutputGuardrailTripwireTriggered: gt,
        RealtimeAgent: $d,
        RealtimeSession: nf,
        UserError: G,
        backgroundResult: Xp,
        isBackgroundResult: nc,
        tool: yt,
        utils: rf,
      },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  );
ki(new Ba());
qa();
const Lf = Object.freeze(
  Object.defineProperty(
    {
      __proto__: null,
      Agent: Se,
      AgentHooks: Ci,
      AgentsError: Ie,
      BatchTraceProcessor: Gr,
      ConsoleSpanExporter: Ca,
      GuardrailExecutionError: Gn,
      Handoff: Dr,
      InputGuardrailTripwireTriggered: Jn,
      MCPServerSSE: Eu,
      MCPServerStdio: xu,
      MCPServerStreamableHttp: Iu,
      MaxTurnsExceededError: qn,
      ModelBehaviorError: ae,
      NoopSpan: xe,
      NoopTrace: Ht,
      OPENAI_DEFAULT_MODEL_ENV_VARIABLE_NAME: Ai,
      OpenAIChatCompletionsModel: $a,
      OpenAIProvider: Ba,
      OpenAIResponsesModel: Ua,
      OpenAITracingExporter: ja,
      OutputGuardrailTripwireTriggered: gt,
      RunAgentUpdatedStreamEvent: fa,
      RunContext: Fe,
      RunHandoffCallItem: mn,
      RunHandoffOutputItem: _n,
      RunItemStreamEvent: pa,
      RunMessageOutputItem: Rt,
      RunRawModelStreamEvent: da,
      RunReasoningItem: hn,
      RunResult: Jt,
      RunState: Ce,
      RunToolApprovalItem: ue,
      RunToolCallItem: De,
      RunToolCallOutputItem: Be,
      Runner: jr,
      RuntimeEventEmitter: wt,
      Span: nt,
      StreamedRunResult: qr,
      SystemError: di,
      ToolCallError: pi,
      Trace: rt,
      TraceProvider: Oa,
      Usage: Re,
      UserError: G,
      addTraceProcessor: Ra,
      assistant: Fl,
      codeInterpreterTool: td,
      computerTool: yu,
      createAgentSpan: Kt,
      createCustomSpan: sa,
      createFunctionSpan: ea,
      createGenerationSpan: Br,
      createGuardrailSpan: oa,
      createHandoffSpan: ta,
      createMCPListToolsSpan: ua,
      createMCPToolStaticFilter: Ul,
      createResponseSpan: $r,
      createSpeechGroupSpan: ca,
      createSpeechSpan: aa,
      createTranscriptionSpan: ia,
      defineOutputGuardrail: zt,
      extractAllTextOutput: el,
      fileSearchTool: ed,
      generateGroupId: Ol,
      generateSpanId: Da,
      generateTraceId: Jr,
      getAllMcpTools: Ei,
      getCurrentSpan: tt,
      getCurrentTrace: et,
      getDefaultModel: un,
      getDefaultModelSettings: Di,
      getGlobalTraceProvider: ee,
      getHandoff: Oi,
      getLogger: je,
      getOrCreateTrace: Ea,
      getTransferMessage: Ar,
      gpt5ReasoningSettingsRequired: Dt,
      handoff: Or,
      hostedMcpTool: vu,
      imageGenerationTool: nd,
      invalidateServerToolsCache: cn,
      isGpt5Default: Cr,
      mcpToFunctionTool: zn,
      protocol: Qu,
      realtime: sf,
      resetCurrentSpan: Ae,
      run: El,
      setCurrentSpan: Ue,
      setDefaultModelProvider: ki,
      setDefaultOpenAIClient: Hl,
      setDefaultOpenAIKey: zl,
      setDefaultOpenAITracingExporter: qa,
      setOpenAIAPI: Jl,
      setTraceProcessors: ka,
      setTracingDisabled: Nl,
      setTracingExportApiKey: jl,
      startTraceExportLoop: Ll,
      system: Ml,
      tool: yt,
      user: Pl,
      webSearchTool: Ql,
      withAgentSpan: tl,
      withCustomSpan: nl,
      withFunctionSpan: Yn,
      withGenerationSpan: ra,
      withGuardrailSpan: Zn,
      withHandoffSpan: na,
      withMCPListToolsSpan: la,
      withResponseSpan: Qi,
      withSpeechGroupSpan: ol,
      withSpeechSpan: sl,
      withTrace: Ia,
      withTranscriptionSpan: rl,
    },
    Symbol.toStringTag,
    { value: "Module" },
  ),
);
export {
  vr as C,
  ur as E,
  Mo as G,
  mo as I,
  Nc as J,
  ao as L,
  mt as M,
  kf as P,
  bo as R,
  Rc as S,
  ii as a,
  Ee as b,
  Ro as c,
  wo as d,
  vo as e,
  jo as f,
  Pc as g,
  co as h,
  Lf as i,
  jn as j,
  Nf as m,
};
//# sourceMappingURL=index-o5KnLmKX.mjs.map
