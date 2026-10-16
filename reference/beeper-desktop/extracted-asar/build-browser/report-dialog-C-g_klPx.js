import { g as B } from "./index-Cw3pknxT.js";
(function () {
  try {
    var t =
      typeof window < "u"
        ? window
        : typeof B < "u"
          ? B
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    t.SENTRY_RELEASE = { id: "4.3.209" };
    var e = new t.Error().stack;
    e &&
      ((t._sentryDebugIds = t._sentryDebugIds || {}),
      (t._sentryDebugIds[e] = "f7436828-8a8c-469c-8787-2f230de24587"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-f7436828-8a8c-469c-8787-2f230de24587"));
  } catch {}
})();
const m = typeof __SENTRY_DEBUG__ > "u" || __SENTRY_DEBUG__,
  _ = globalThis,
  w = "10.17.0";
function O() {
  return (at(_), _);
}
function at(t) {
  const e = (t.__SENTRY__ = t.__SENTRY__ || {});
  return ((e.version = e.version || w), (e[w] = e[w] || {}));
}
function Y(t, e, n = _) {
  const r = (n.__SENTRY__ = n.__SENTRY__ || {}),
    s = (r[w] = r[w] || {});
  return s[t] || (s[t] = e());
}
const ar = ["debug", "info", "warn", "error", "log", "assert", "trace"],
  ae = "Sentry Logger ",
  _t = {};
function ct(t) {
  if (!("console" in _)) return t();
  const e = _.console,
    n = {},
    r = Object.keys(_t);
  r.forEach((s) => {
    const i = _t[s];
    ((n[s] = e[s]), (e[s] = i));
  });
  try {
    return t();
  } finally {
    r.forEach((s) => {
      e[s] = n[s];
    });
  }
}
function ce() {
  ft().enabled = !0;
}
function ue() {
  ft().enabled = !1;
}
function wt() {
  return ft().enabled;
}
function fe(...t) {
  ut("log", ...t);
}
function pe(...t) {
  ut("warn", ...t);
}
function de(...t) {
  ut("error", ...t);
}
function ut(t, ...e) {
  m &&
    wt() &&
    ct(() => {
      _.console[t](`${ae}[${t}]:`, ...e);
    });
}
function ft() {
  return m ? Y("loggerSettings", () => ({ enabled: !1 })) : { enabled: !1 };
}
const d = {
    enable: ce,
    disable: ue,
    isEnabled: wt,
    log: fe,
    warn: pe,
    error: de,
  },
  Pt = 50,
  le = "?",
  gt = /\(error: (.*)\)/,
  ht = /captureMessage|captureException/;
function _e(...t) {
  const e = t.sort((n, r) => n[0] - r[0]).map((n) => n[1]);
  return (n, r = 0, s = 0) => {
    const i = [],
      o = n.split(`
`);
    for (let a = r; a < o.length; a++) {
      let c = o[a];
      c.length > 1024 && (c = c.slice(0, 1024));
      const u = gt.test(c) ? c.replace(gt, "$1") : c;
      if (!u.match(/\S*Error: /)) {
        for (const f of e) {
          const p = f(u);
          if (p) {
            i.push(p);
            break;
          }
        }
        if (i.length >= Pt + s) break;
      }
    }
    return ge(i.slice(s));
  };
}
function cr(t) {
  return Array.isArray(t) ? _e(...t) : t;
}
function ge(t) {
  if (!t.length) return [];
  const e = Array.from(t);
  return (
    /sentryWrapped/.test(F(e).function || "") && e.pop(),
    e.reverse(),
    ht.test(F(e).function || "") &&
      (e.pop(), ht.test(F(e).function || "") && e.pop()),
    e
      .slice(0, Pt)
      .map((n) => ({
        ...n,
        filename: n.filename || F(e).filename,
        function: n.function || le,
      }))
  );
}
function F(t) {
  return t[t.length - 1] || {};
}
const J = "<anonymous>";
function he(t) {
  try {
    return !t || typeof t != "function" ? J : t.name || J;
  } catch {
    return J;
  }
}
function ur(t) {
  const e = t.exception;
  if (e) {
    const n = [];
    try {
      return (
        e.values.forEach((r) => {
          r.stacktrace.frames && n.push(...r.stacktrace.frames);
        }),
        n
      );
    } catch {
      return;
    }
  }
}
const kt = Object.prototype.toString;
function me(t) {
  switch (kt.call(t)) {
    case "[object Error]":
    case "[object Exception]":
    case "[object DOMException]":
    case "[object WebAssembly.Exception]":
      return !0;
    default:
      return $(t, Error);
  }
}
function M(t, e) {
  return kt.call(t) === `[object ${e}]`;
}
function fr(t) {
  return M(t, "ErrorEvent");
}
function pr(t) {
  return M(t, "DOMError");
}
function dr(t) {
  return M(t, "DOMException");
}
function G(t) {
  return M(t, "String");
}
function Se(t) {
  return (
    typeof t == "object" &&
    t !== null &&
    "__sentry_template_string__" in t &&
    "__sentry_template_values__" in t
  );
}
function lr(t) {
  return (
    t === null || Se(t) || (typeof t != "object" && typeof t != "function")
  );
}
function $t(t) {
  return M(t, "Object");
}
function ye(t) {
  return typeof Event < "u" && $(t, Event);
}
function Ee(t) {
  return typeof Element < "u" && $(t, Element);
}
function be(t) {
  return M(t, "RegExp");
}
function z(t) {
  return !!(t?.then && typeof t.then == "function");
}
function Te(t) {
  return (
    $t(t) &&
    "nativeEvent" in t &&
    "preventDefault" in t &&
    "stopPropagation" in t
  );
}
function $(t, e) {
  try {
    return t instanceof e;
  } catch {
    return !1;
  }
}
function Lt(t) {
  return !!(typeof t == "object" && t !== null && (t.__isVue || t._isVue));
}
function _r(t) {
  return typeof Request < "u" && $(t, Request);
}
const pt = _,
  Ie = 80;
function Ae(t, e = {}) {
  if (!t) return "<unknown>";
  try {
    let n = t;
    const r = 5,
      s = [];
    let i = 0,
      o = 0;
    const a = " > ",
      c = a.length;
    let u;
    const f = Array.isArray(e) ? e : e.keyAttrs,
      p = (!Array.isArray(e) && e.maxStringLength) || Ie;
    for (
      ;
      n &&
      i++ < r &&
      ((u = Ce(n, f)),
      !(u === "html" || (i > 1 && o + s.length * c + u.length >= p)));
    )
      (s.push(u), (o += u.length), (n = n.parentNode));
    return s.reverse().join(a);
  } catch {
    return "<unknown>";
  }
}
function Ce(t, e) {
  const n = t,
    r = [];
  if (!n?.tagName) return "";
  if (pt.HTMLElement && n instanceof HTMLElement && n.dataset) {
    if (n.dataset.sentryComponent) return n.dataset.sentryComponent;
    if (n.dataset.sentryElement) return n.dataset.sentryElement;
  }
  r.push(n.tagName.toLowerCase());
  const s = e?.length
    ? e.filter((o) => n.getAttribute(o)).map((o) => [o, n.getAttribute(o)])
    : null;
  if (s?.length)
    s.forEach((o) => {
      r.push(`[${o[0]}="${o[1]}"]`);
    });
  else {
    n.id && r.push(`#${n.id}`);
    const o = n.className;
    if (o && G(o)) {
      const a = o.split(/\s+/);
      for (const c of a) r.push(`.${c}`);
    }
  }
  const i = ["aria-label", "type", "name", "title", "alt"];
  for (const o of i) {
    const a = n.getAttribute(o);
    a && r.push(`[${o}="${a}"]`);
  }
  return r.join("");
}
function Ne() {
  try {
    return pt.document.location.href;
  } catch {
    return "";
  }
}
function gr(t) {
  if (!pt.HTMLElement) return null;
  let e = t;
  const n = 5;
  for (let r = 0; r < n; r++) {
    if (!e) return null;
    if (e instanceof HTMLElement) {
      if (e.dataset.sentryComponent) return e.dataset.sentryComponent;
      if (e.dataset.sentryElement) return e.dataset.sentryElement;
    }
    e = e.parentNode;
  }
  return null;
}
function H(t, e = 0) {
  return typeof t != "string" || e === 0 || t.length <= e
    ? t
    : `${t.slice(0, e)}...`;
}
function Q(t, e) {
  let n = t;
  const r = n.length;
  if (r <= 150) return n;
  e > r && (e = r);
  let s = Math.max(e - 60, 0);
  s < 5 && (s = 0);
  let i = Math.min(s + 140, r);
  return (
    i > r - 5 && (i = r),
    i === r && (s = Math.max(i - 140, 0)),
    (n = n.slice(s, i)),
    s > 0 && (n = `'{snip} ${n}`),
    i < r && (n += " {snip}"),
    n
  );
}
function hr(t, e) {
  if (!Array.isArray(t)) return "";
  const n = [];
  for (let r = 0; r < t.length; r++) {
    const s = t[r];
    try {
      Lt(s) ? n.push("[VueViewModel]") : n.push(String(s));
    } catch {
      n.push("[value cannot be serialized]");
    }
  }
  return n.join(e);
}
function Re(t, e, n = !1) {
  return G(t)
    ? be(e)
      ? e.test(t)
      : G(e)
        ? n
          ? t === e
          : t.includes(e)
        : !1
    : !1;
}
function mr(t, e = [], n = !1) {
  return e.some((r) => Re(t, r, n));
}
function Sr(t, e, n) {
  if (!(e in t)) return;
  const r = t[e];
  if (typeof r != "function") return;
  const s = n(r);
  typeof s == "function" && Ft(s, r);
  try {
    t[e] = s;
  } catch {
    m && d.log(`Failed to replace method "${e}" in object`, t);
  }
}
function T(t, e, n) {
  try {
    Object.defineProperty(t, e, { value: n, writable: !0, configurable: !0 });
  } catch {
    m && d.log(`Failed to add non-enumerable property "${e}" to object`, t);
  }
}
function Ft(t, e) {
  try {
    const n = e.prototype || {};
    ((t.prototype = e.prototype = n), T(t, "__sentry_original__", e));
  } catch {}
}
function xe(t) {
  return t.__sentry_original__;
}
function Ut(t) {
  if (me(t))
    return { message: t.message, name: t.name, stack: t.stack, ...St(t) };
  if (ye(t)) {
    const e = {
      type: t.type,
      target: mt(t.target),
      currentTarget: mt(t.currentTarget),
      ...St(t),
    };
    return (
      typeof CustomEvent < "u" && $(t, CustomEvent) && (e.detail = t.detail),
      e
    );
  } else return t;
}
function mt(t) {
  try {
    return Ee(t) ? Ae(t) : Object.prototype.toString.call(t);
  } catch {
    return "<unknown>";
  }
}
function St(t) {
  if (typeof t == "object" && t !== null) {
    const e = {};
    for (const n in t)
      Object.prototype.hasOwnProperty.call(t, n) && (e[n] = t[n]);
    return e;
  } else return {};
}
function yr(t, e = 40) {
  const n = Object.keys(Ut(t));
  n.sort();
  const r = n[0];
  if (!r) return "[object has no keys]";
  if (r.length >= e) return H(r, e);
  for (let s = n.length; s > 0; s--) {
    const i = n.slice(0, s).join(", ");
    if (!(i.length > e)) return s === n.length ? i : H(i, e);
  }
  return "";
}
function De() {
  const t = _;
  return t.crypto || t.msCrypto;
}
function A(t = De()) {
  let e = () => Math.random() * 16;
  try {
    if (t?.randomUUID) return t.randomUUID().replace(/-/g, "");
    t?.getRandomValues &&
      (e = () => {
        const n = new Uint8Array(1);
        return (t.getRandomValues(n), n[0]);
      });
  } catch {}
  return ("10000000100040008000" + 1e11).replace(/[018]/g, (n) =>
    (n ^ ((e() & 15) >> (n / 4))).toString(16),
  );
}
function jt(t) {
  return t.exception?.values?.[0];
}
function Er(t) {
  const { message: e, event_id: n } = t;
  if (e) return e;
  const r = jt(t);
  return r
    ? r.type && r.value
      ? `${r.type}: ${r.value}`
      : r.type || r.value || n || "<unknown>"
    : n || "<unknown>";
}
function Oe(t, e, n) {
  const r = (t.exception = t.exception || {}),
    s = (r.values = r.values || []),
    i = (s[0] = s[0] || {});
  (i.value || (i.value = e || ""), i.type || (i.type = "Error"));
}
function vt(t, e) {
  const n = jt(t);
  if (!n) return;
  const r = { type: "generic", handled: !0 },
    s = n.mechanism;
  if (((n.mechanism = { ...r, ...s, ...e }), e && "data" in e)) {
    const i = { ...s?.data, ...e.data };
    n.mechanism.data = i;
  }
}
function br(t, e, n = 5) {
  if (e.lineno === void 0) return;
  const r = t.length,
    s = Math.max(Math.min(r - 1, e.lineno - 1), 0);
  e.pre_context = t.slice(Math.max(0, s - n), s).map((o) => Q(o, 0));
  const i = Math.min(r - 1, s);
  ((e.context_line = Q(t[i], e.colno || 0)),
    (e.post_context = t
      .slice(Math.min(s + 1, r), s + 1 + n)
      .map((o) => Q(o, 0))));
}
function Tr(t) {
  if (Me(t)) return !0;
  try {
    T(t, "__sentry_captured__", !0);
  } catch {}
  return !1;
}
function Me(t) {
  try {
    return t.__sentry_captured__;
  } catch {}
}
const Bt = 1e3;
function dt() {
  return Date.now() / Bt;
}
function we() {
  const { performance: t } = _;
  if (!t?.now || !t.timeOrigin) return dt;
  const e = t.timeOrigin;
  return () => (e + t.now()) / Bt;
}
let yt;
function lt() {
  return (yt ?? (yt = we()))();
}
let Z;
function Pe() {
  const { performance: t } = _;
  if (!t?.now) return [void 0, "none"];
  const e = 3600 * 1e3,
    n = t.now(),
    r = Date.now(),
    s = t.timeOrigin ? Math.abs(t.timeOrigin + n - r) : e,
    i = s < e,
    o = t.timing?.navigationStart,
    c = typeof o == "number" ? Math.abs(o + n - r) : e,
    u = c < e;
  return i || u
    ? s <= c
      ? [t.timeOrigin, "timeOrigin"]
      : [o, "navigationStart"]
    : [r, "dateNow"];
}
function Ir() {
  return (Z || (Z = Pe()), Z[0]);
}
function ke(t) {
  const e = lt(),
    n = {
      sid: A(),
      init: !0,
      timestamp: e,
      started: e,
      duration: 0,
      status: "ok",
      errors: 0,
      ignoreDuration: !1,
      toJSON: () => Le(n),
    };
  return (t && W(n, t), n);
}
function W(t, e = {}) {
  if (
    (e.user &&
      (!t.ipAddress && e.user.ip_address && (t.ipAddress = e.user.ip_address),
      !t.did &&
        !e.did &&
        (t.did = e.user.id || e.user.email || e.user.username)),
    (t.timestamp = e.timestamp || lt()),
    e.abnormal_mechanism && (t.abnormal_mechanism = e.abnormal_mechanism),
    e.ignoreDuration && (t.ignoreDuration = e.ignoreDuration),
    e.sid && (t.sid = e.sid.length === 32 ? e.sid : A()),
    e.init !== void 0 && (t.init = e.init),
    !t.did && e.did && (t.did = `${e.did}`),
    typeof e.started == "number" && (t.started = e.started),
    t.ignoreDuration)
  )
    t.duration = void 0;
  else if (typeof e.duration == "number") t.duration = e.duration;
  else {
    const n = t.timestamp - t.started;
    t.duration = n >= 0 ? n : 0;
  }
  (e.release && (t.release = e.release),
    e.environment && (t.environment = e.environment),
    !t.ipAddress && e.ipAddress && (t.ipAddress = e.ipAddress),
    !t.userAgent && e.userAgent && (t.userAgent = e.userAgent),
    typeof e.errors == "number" && (t.errors = e.errors),
    e.status && (t.status = e.status));
}
function $e(t, e) {
  let n = {};
  (t.status === "ok" && (n = { status: "exited" }), W(t, n));
}
function Le(t) {
  return {
    sid: `${t.sid}`,
    init: t.init,
    started: new Date(t.started * 1e3).toISOString(),
    timestamp: new Date(t.timestamp * 1e3).toISOString(),
    status: t.status,
    errors: t.errors,
    did:
      typeof t.did == "number" || typeof t.did == "string"
        ? `${t.did}`
        : void 0,
    duration: t.duration,
    abnormal_mechanism: t.abnormal_mechanism,
    attrs: {
      release: t.release,
      environment: t.environment,
      ip_address: t.ipAddress,
      user_agent: t.userAgent,
    },
  };
}
function K(t, e, n = 2) {
  if (!e || typeof e != "object" || n <= 0) return e;
  if (t && Object.keys(e).length === 0) return t;
  const r = { ...t };
  for (const s in e)
    Object.prototype.hasOwnProperty.call(e, s) && (r[s] = K(r[s], e[s], n - 1));
  return r;
}
function P() {
  return A();
}
function V() {
  return A().substring(16);
}
const et = "_sentrySpan";
function Et(t, e) {
  e ? T(t, et, e) : delete t[et];
}
function nt(t) {
  return t[et];
}
const Fe = 100;
class E {
  constructor() {
    ((this._notifyingListeners = !1),
      (this._scopeListeners = []),
      (this._eventProcessors = []),
      (this._breadcrumbs = []),
      (this._attachments = []),
      (this._user = {}),
      (this._tags = {}),
      (this._extra = {}),
      (this._contexts = {}),
      (this._sdkProcessingMetadata = {}),
      (this._propagationContext = { traceId: P(), sampleRand: Math.random() }));
  }
  clone() {
    const e = new E();
    return (
      (e._breadcrumbs = [...this._breadcrumbs]),
      (e._tags = { ...this._tags }),
      (e._extra = { ...this._extra }),
      (e._contexts = { ...this._contexts }),
      this._contexts.flags &&
        (e._contexts.flags = { values: [...this._contexts.flags.values] }),
      (e._user = this._user),
      (e._level = this._level),
      (e._session = this._session),
      (e._transactionName = this._transactionName),
      (e._fingerprint = this._fingerprint),
      (e._eventProcessors = [...this._eventProcessors]),
      (e._attachments = [...this._attachments]),
      (e._sdkProcessingMetadata = { ...this._sdkProcessingMetadata }),
      (e._propagationContext = { ...this._propagationContext }),
      (e._client = this._client),
      (e._lastEventId = this._lastEventId),
      Et(e, nt(this)),
      e
    );
  }
  setClient(e) {
    this._client = e;
  }
  setLastEventId(e) {
    this._lastEventId = e;
  }
  getClient() {
    return this._client;
  }
  lastEventId() {
    return this._lastEventId;
  }
  addScopeListener(e) {
    this._scopeListeners.push(e);
  }
  addEventProcessor(e) {
    return (this._eventProcessors.push(e), this);
  }
  setUser(e) {
    return (
      (this._user = e || {
        email: void 0,
        id: void 0,
        ip_address: void 0,
        username: void 0,
      }),
      this._session && W(this._session, { user: e }),
      this._notifyScopeListeners(),
      this
    );
  }
  getUser() {
    return this._user;
  }
  setTags(e) {
    return (
      (this._tags = { ...this._tags, ...e }),
      this._notifyScopeListeners(),
      this
    );
  }
  setTag(e, n) {
    return (
      (this._tags = { ...this._tags, [e]: n }),
      this._notifyScopeListeners(),
      this
    );
  }
  setExtras(e) {
    return (
      (this._extra = { ...this._extra, ...e }),
      this._notifyScopeListeners(),
      this
    );
  }
  setExtra(e, n) {
    return (
      (this._extra = { ...this._extra, [e]: n }),
      this._notifyScopeListeners(),
      this
    );
  }
  setFingerprint(e) {
    return ((this._fingerprint = e), this._notifyScopeListeners(), this);
  }
  setLevel(e) {
    return ((this._level = e), this._notifyScopeListeners(), this);
  }
  setTransactionName(e) {
    return ((this._transactionName = e), this._notifyScopeListeners(), this);
  }
  setContext(e, n) {
    return (
      n === null ? delete this._contexts[e] : (this._contexts[e] = n),
      this._notifyScopeListeners(),
      this
    );
  }
  setSession(e) {
    return (
      e ? (this._session = e) : delete this._session,
      this._notifyScopeListeners(),
      this
    );
  }
  getSession() {
    return this._session;
  }
  update(e) {
    if (!e) return this;
    const n = typeof e == "function" ? e(this) : e,
      r = n instanceof E ? n.getScopeData() : $t(n) ? e : void 0,
      {
        tags: s,
        extra: i,
        user: o,
        contexts: a,
        level: c,
        fingerprint: u = [],
        propagationContext: f,
      } = r || {};
    return (
      (this._tags = { ...this._tags, ...s }),
      (this._extra = { ...this._extra, ...i }),
      (this._contexts = { ...this._contexts, ...a }),
      o && Object.keys(o).length && (this._user = o),
      c && (this._level = c),
      u.length && (this._fingerprint = u),
      f && (this._propagationContext = f),
      this
    );
  }
  clear() {
    return (
      (this._breadcrumbs = []),
      (this._tags = {}),
      (this._extra = {}),
      (this._user = {}),
      (this._contexts = {}),
      (this._level = void 0),
      (this._transactionName = void 0),
      (this._fingerprint = void 0),
      (this._session = void 0),
      Et(this, void 0),
      (this._attachments = []),
      this.setPropagationContext({ traceId: P(), sampleRand: Math.random() }),
      this._notifyScopeListeners(),
      this
    );
  }
  addBreadcrumb(e, n) {
    const r = typeof n == "number" ? n : Fe;
    if (r <= 0) return this;
    const s = {
      timestamp: dt(),
      ...e,
      message: e.message ? H(e.message, 2048) : e.message,
    };
    return (
      this._breadcrumbs.push(s),
      this._breadcrumbs.length > r &&
        ((this._breadcrumbs = this._breadcrumbs.slice(-r)),
        this._client?.recordDroppedEvent("buffer_overflow", "log_item")),
      this._notifyScopeListeners(),
      this
    );
  }
  getLastBreadcrumb() {
    return this._breadcrumbs[this._breadcrumbs.length - 1];
  }
  clearBreadcrumbs() {
    return ((this._breadcrumbs = []), this._notifyScopeListeners(), this);
  }
  addAttachment(e) {
    return (this._attachments.push(e), this);
  }
  clearAttachments() {
    return ((this._attachments = []), this);
  }
  getScopeData() {
    return {
      breadcrumbs: this._breadcrumbs,
      attachments: this._attachments,
      contexts: this._contexts,
      tags: this._tags,
      extra: this._extra,
      user: this._user,
      level: this._level,
      fingerprint: this._fingerprint || [],
      eventProcessors: this._eventProcessors,
      propagationContext: this._propagationContext,
      sdkProcessingMetadata: this._sdkProcessingMetadata,
      transactionName: this._transactionName,
      span: nt(this),
    };
  }
  setSDKProcessingMetadata(e) {
    return (
      (this._sdkProcessingMetadata = K(this._sdkProcessingMetadata, e, 2)),
      this
    );
  }
  setPropagationContext(e) {
    return ((this._propagationContext = e), this);
  }
  getPropagationContext() {
    return this._propagationContext;
  }
  captureException(e, n) {
    const r = n?.event_id || A();
    if (!this._client)
      return (
        m &&
          d.warn("No client configured on scope - will not capture exception!"),
        r
      );
    const s = new Error("Sentry syntheticException");
    return (
      this._client.captureException(
        e,
        { originalException: e, syntheticException: s, ...n, event_id: r },
        this,
      ),
      r
    );
  }
  captureMessage(e, n, r) {
    const s = r?.event_id || A();
    if (!this._client)
      return (
        m &&
          d.warn("No client configured on scope - will not capture message!"),
        s
      );
    const i = new Error(e);
    return (
      this._client.captureMessage(
        e,
        n,
        { originalException: e, syntheticException: i, ...r, event_id: s },
        this,
      ),
      s
    );
  }
  captureEvent(e, n) {
    const r = n?.event_id || A();
    return this._client
      ? (this._client.captureEvent(e, { ...n, event_id: r }, this), r)
      : (m && d.warn("No client configured on scope - will not capture event!"),
        r);
  }
  _notifyScopeListeners() {
    this._notifyingListeners ||
      ((this._notifyingListeners = !0),
      this._scopeListeners.forEach((e) => {
        e(this);
      }),
      (this._notifyingListeners = !1));
  }
}
function Ue() {
  return Y("defaultCurrentScope", () => new E());
}
function je() {
  return Y("defaultIsolationScope", () => new E());
}
class ve {
  constructor(e, n) {
    let r;
    e ? (r = e) : (r = new E());
    let s;
    (n ? (s = n) : (s = new E()),
      (this._stack = [{ scope: r }]),
      (this._isolationScope = s));
  }
  withScope(e) {
    const n = this._pushScope();
    let r;
    try {
      r = e(n);
    } catch (s) {
      throw (this._popScope(), s);
    }
    return z(r)
      ? r.then(
          (s) => (this._popScope(), s),
          (s) => {
            throw (this._popScope(), s);
          },
        )
      : (this._popScope(), r);
  }
  getClient() {
    return this.getStackTop().client;
  }
  getScope() {
    return this.getStackTop().scope;
  }
  getIsolationScope() {
    return this._isolationScope;
  }
  getStackTop() {
    return this._stack[this._stack.length - 1];
  }
  _pushScope() {
    const e = this.getScope().clone();
    return (this._stack.push({ client: this.getClient(), scope: e }), e);
  }
  _popScope() {
    return this._stack.length <= 1 ? !1 : !!this._stack.pop();
  }
}
function D() {
  const t = O(),
    e = at(t);
  return (e.stack = e.stack || new ve(Ue(), je()));
}
function Be(t) {
  return D().withScope(t);
}
function Ge(t, e) {
  const n = D();
  return n.withScope(() => ((n.getStackTop().scope = t), e(t)));
}
function bt(t) {
  return D().withScope(() => t(D().getIsolationScope()));
}
function He() {
  return {
    withIsolationScope: bt,
    withScope: Be,
    withSetScope: Ge,
    withSetIsolationScope: (t, e) => bt(e),
    getCurrentScope: () => D().getScope(),
    getIsolationScope: () => D().getIsolationScope(),
  };
}
function L(t) {
  const e = at(t);
  return e.acs ? e.acs : He();
}
function C() {
  const t = O();
  return L(t).getCurrentScope();
}
function S() {
  const t = O();
  return L(t).getIsolationScope();
}
function Ye() {
  return Y("globalScope", () => new E());
}
function ze(...t) {
  const e = O(),
    n = L(e);
  if (t.length === 2) {
    const [r, s] = t;
    return r ? n.withSetScope(r, s) : n.withScope(s);
  }
  return n.withScope(t[0]);
}
function Ar(...t) {
  const e = O(),
    n = L(e);
  if (t.length === 2) {
    const [r, s] = t;
    return r ? n.withSetIsolationScope(r, s) : n.withIsolationScope(s);
  }
  return n.withIsolationScope(t[0]);
}
function N() {
  return C().getClient();
}
function Cr(t) {
  const e = t.getPropagationContext(),
    { traceId: n, parentSpanId: r, propagationSpanId: s } = e,
    i = { trace_id: n, span_id: s || V() };
  return (r && (i.parent_span_id = r), i);
}
const Gt = "sentry.source",
  We = "sentry.sample_rate",
  Ke = "sentry.previous_trace_sample_rate",
  Ve = "sentry.op",
  Xe = "sentry.origin",
  Nr = "sentry.idle_span_finish_reason",
  Rr = "sentry.measurement_unit",
  xr = "sentry.measurement_value",
  qe = "sentry.custom_span_name",
  Dr = "sentry.profile_id",
  Or = "sentry.exclusive_time",
  Mr = "http.request.method",
  wr = "url.full",
  Pr = "sentry.link.type",
  Je = 0,
  Ht = 1,
  h = 2;
function Qe(t) {
  if (t < 400 && t >= 100) return { code: Ht };
  if (t >= 400 && t < 500)
    switch (t) {
      case 401:
        return { code: h, message: "unauthenticated" };
      case 403:
        return { code: h, message: "permission_denied" };
      case 404:
        return { code: h, message: "not_found" };
      case 409:
        return { code: h, message: "already_exists" };
      case 413:
        return { code: h, message: "failed_precondition" };
      case 429:
        return { code: h, message: "resource_exhausted" };
      case 499:
        return { code: h, message: "cancelled" };
      default:
        return { code: h, message: "invalid_argument" };
    }
  if (t >= 500 && t < 600)
    switch (t) {
      case 501:
        return { code: h, message: "unimplemented" };
      case 503:
        return { code: h, message: "unavailable" };
      case 504:
        return { code: h, message: "deadline_exceeded" };
      default:
        return { code: h, message: "internal_error" };
    }
  return { code: h, message: "unknown_error" };
}
function kr(t, e) {
  t.setAttribute("http.response.status_code", e);
  const n = Qe(e);
  n.message !== "unknown_error" && t.setStatus(n);
}
const Yt = "_sentryScope",
  zt = "_sentryIsolationScope";
function Ze(t) {
  try {
    const e = _.WeakRef;
    if (typeof e == "function") return new e(t);
  } catch {}
  return t;
}
function tn(t) {
  if (t) {
    if (typeof t == "object" && "deref" in t && typeof t.deref == "function")
      try {
        return t.deref();
      } catch {
        return;
      }
    return t;
  }
}
function $r(t, e, n) {
  t && (T(t, zt, Ze(n)), T(t, Yt, e));
}
function Wt(t) {
  const e = t;
  return { scope: e[Yt], isolationScope: tn(e[zt]) };
}
const Kt = "sentry-",
  en = /^sentry-/,
  nn = 8192;
function Vt(t) {
  const e = sn(t);
  if (!e) return;
  const n = Object.entries(e).reduce((r, [s, i]) => {
    if (s.match(en)) {
      const o = s.slice(Kt.length);
      r[o] = i;
    }
    return r;
  }, {});
  if (Object.keys(n).length > 0) return n;
}
function rn(t) {
  if (!t) return;
  const e = Object.entries(t).reduce(
    (n, [r, s]) => (s && (n[`${Kt}${r}`] = s), n),
    {},
  );
  return on(e);
}
function sn(t) {
  if (!(!t || (!G(t) && !Array.isArray(t))))
    return Array.isArray(t)
      ? t.reduce((e, n) => {
          const r = Tt(n);
          return (
            Object.entries(r).forEach(([s, i]) => {
              e[s] = i;
            }),
            e
          );
        }, {})
      : Tt(t);
}
function Tt(t) {
  return t
    .split(",")
    .map((e) =>
      e.split("=").map((n) => {
        try {
          return decodeURIComponent(n.trim());
        } catch {
          return;
        }
      }),
    )
    .reduce((e, [n, r]) => (n && r && (e[n] = r), e), {});
}
function on(t) {
  if (Object.keys(t).length !== 0)
    return Object.entries(t).reduce((e, [n, r], s) => {
      const i = `${encodeURIComponent(n)}=${encodeURIComponent(r)}`,
        o = s === 0 ? i : `${e},${i}`;
      return o.length > nn
        ? (m &&
            d.warn(
              `Not adding key: ${n} with val: ${r} to baggage header due to exceeding baggage size limits.`,
            ),
          e)
        : o;
    }, "");
}
const an = /^o(\d+)\./,
  cn = /^(?:(\w+):)\/\/(?:(\w+)(?::(\w+)?)?@)([\w.-]+)(?::(\d+))?\/(.+)/;
function un(t) {
  return t === "http" || t === "https";
}
function fn(t, e = !1) {
  const {
    host: n,
    path: r,
    pass: s,
    port: i,
    projectId: o,
    protocol: a,
    publicKey: c,
  } = t;
  return `${a}://${c}${e && s ? `:${s}` : ""}@${n}${i ? `:${i}` : ""}/${r && `${r}/`}${o}`;
}
function pn(t) {
  const e = cn.exec(t);
  if (!e) {
    ct(() => {
      console.error(`Invalid Sentry Dsn: ${t}`);
    });
    return;
  }
  const [n, r, s = "", i = "", o = "", a = ""] = e.slice(1);
  let c = "",
    u = a;
  const f = u.split("/");
  if ((f.length > 1 && ((c = f.slice(0, -1).join("/")), (u = f.pop())), u)) {
    const p = u.match(/^\d+/);
    p && (u = p[0]);
  }
  return Xt({
    host: i,
    pass: s,
    path: c,
    projectId: u,
    port: o,
    protocol: n,
    publicKey: r,
  });
}
function Xt(t) {
  return {
    protocol: t.protocol,
    publicKey: t.publicKey || "",
    pass: t.pass || "",
    host: t.host,
    port: t.port || "",
    path: t.path || "",
    projectId: t.projectId,
  };
}
function dn(t) {
  if (!m) return !0;
  const { port: e, projectId: n, protocol: r } = t;
  return ["protocol", "publicKey", "host", "projectId"].find((o) =>
    t[o] ? !1 : (d.error(`Invalid Sentry Dsn: ${o} missing`), !0),
  )
    ? !1
    : n.match(/^\d+$/)
      ? un(r)
        ? e && isNaN(parseInt(e, 10))
          ? (d.error(`Invalid Sentry Dsn: Invalid port ${e}`), !1)
          : !0
        : (d.error(`Invalid Sentry Dsn: Invalid protocol ${r}`), !1)
      : (d.error(`Invalid Sentry Dsn: Invalid projectId ${n}`), !1);
}
function ln(t) {
  return t.match(an)?.[1];
}
function qt(t) {
  const e = t.getOptions(),
    { host: n } = t.getDsn() || {};
  let r;
  return (e.orgId ? (r = String(e.orgId)) : n && (r = ln(n)), r);
}
function _n(t) {
  const e = typeof t == "string" ? pn(t) : Xt(t);
  if (!(!e || !dn(e))) return e;
}
function It(t) {
  if (typeof t == "boolean") return Number(t);
  const e = typeof t == "string" ? parseFloat(t) : t;
  if (!(typeof e != "number" || isNaN(e) || e < 0 || e > 1)) return e;
}
const gn = new RegExp(
  "^[ \\t]*([0-9a-f]{32})?-?([0-9a-f]{16})?-?([01])?[ \\t]*$",
);
function hn(t) {
  if (!t) return;
  const e = t.match(gn);
  if (!e) return;
  let n;
  return (
    e[3] === "1" ? (n = !0) : e[3] === "0" && (n = !1),
    { traceId: e[1], parentSampled: n, parentSpanId: e[2] }
  );
}
function Lr(t, e) {
  const n = hn(t),
    r = Vt(e);
  if (!n?.traceId) return { traceId: P(), sampleRand: Math.random() };
  const s = yn(n, r);
  r && (r.sample_rand = s.toString());
  const { traceId: i, parentSpanId: o, parentSampled: a } = n;
  return {
    traceId: i,
    parentSpanId: o,
    sampled: a,
    dsc: r || {},
    sampleRand: s,
  };
}
function mn(t = P(), e = V(), n) {
  let r = "";
  return (n !== void 0 && (r = n ? "-1" : "-0"), `${t}-${e}${r}`);
}
function Sn(t = P(), e = V(), n) {
  return `00-${t}-${e}-${n ? "01" : "00"}`;
}
function yn(t, e) {
  const n = It(e?.sample_rand);
  if (n !== void 0) return n;
  const r = It(e?.sample_rate);
  return r && t?.parentSampled !== void 0
    ? t.parentSampled
      ? Math.random() * r
      : r + Math.random() * (1 - r)
    : Math.random();
}
function Fr(t, e) {
  const n = qt(t);
  return e && n && e !== n
    ? (d.log(
        `Won't continue trace because org IDs don't match (incoming baggage: ${e}, SDK options: ${n})`,
      ),
      !1)
    : (t.getOptions().strictTraceContinuation || !1) && ((e && !n) || (!e && n))
      ? (d.log(
          `Starting a new trace because strict trace continuation is enabled but one org ID is missing (incoming baggage: ${e}, Sentry client: ${n})`,
        ),
        !1)
      : !0;
}
const Ur = 0,
  Jt = 1;
let At = !1;
function jr(t) {
  const { spanId: e, traceId: n } = t.spanContext(),
    {
      data: r,
      op: s,
      parent_span_id: i,
      status: o,
      origin: a,
      links: c,
    } = X(t);
  return {
    parent_span_id: i,
    span_id: e,
    trace_id: n,
    data: r,
    op: s,
    status: o,
    origin: a,
    links: c,
  };
}
function En(t) {
  const { spanId: e, traceId: n, isRemote: r } = t.spanContext(),
    s = r ? e : X(t).parent_span_id,
    i = Wt(t).scope,
    o = r ? i?.getPropagationContext().propagationSpanId || V() : e;
  return { parent_span_id: s, span_id: o, trace_id: n };
}
function vr(t) {
  const { traceId: e, spanId: n } = t.spanContext(),
    r = q(t);
  return mn(e, n, r);
}
function Br(t) {
  const { traceId: e, spanId: n } = t.spanContext(),
    r = q(t);
  return Sn(e, n, r);
}
function bn(t) {
  if (t && t.length > 0)
    return t.map(
      ({
        context: { spanId: e, traceId: n, traceFlags: r, ...s },
        attributes: i,
      }) => ({
        span_id: e,
        trace_id: n,
        sampled: r === Jt,
        attributes: i,
        ...s,
      }),
    );
}
function Ct(t) {
  return typeof t == "number"
    ? Nt(t)
    : Array.isArray(t)
      ? t[0] + t[1] / 1e9
      : t instanceof Date
        ? Nt(t.getTime())
        : lt();
}
function Nt(t) {
  return t > 9999999999 ? t / 1e3 : t;
}
function X(t) {
  if (In(t)) return t.getSpanJSON();
  const { spanId: e, traceId: n } = t.spanContext();
  if (Tn(t)) {
    const {
        attributes: r,
        startTime: s,
        name: i,
        endTime: o,
        status: a,
        links: c,
      } = t,
      u =
        "parentSpanId" in t
          ? t.parentSpanId
          : "parentSpanContext" in t
            ? t.parentSpanContext?.spanId
            : void 0;
    return {
      span_id: e,
      trace_id: n,
      data: r,
      description: i,
      parent_span_id: u,
      start_timestamp: Ct(s),
      timestamp: Ct(o) || void 0,
      status: An(a),
      op: r[Ve],
      origin: r[Xe],
      links: bn(c),
    };
  }
  return { span_id: e, trace_id: n, start_timestamp: 0, data: {} };
}
function Tn(t) {
  const e = t;
  return (
    !!e.attributes && !!e.startTime && !!e.name && !!e.endTime && !!e.status
  );
}
function In(t) {
  return typeof t.getSpanJSON == "function";
}
function q(t) {
  const { traceFlags: e } = t.spanContext();
  return e === Jt;
}
function An(t) {
  if (!(!t || t.code === Je))
    return t.code === Ht ? "ok" : t.message || "unknown_error";
}
const R = "_sentryChildSpans",
  rt = "_sentryRootSpan";
function Gr(t, e) {
  const n = t[rt] || t;
  (T(e, rt, n), t[R] ? t[R].add(e) : T(t, R, new Set([e])));
}
function Hr(t, e) {
  t[R] && t[R].delete(e);
}
function Yr(t) {
  const e = new Set();
  function n(r) {
    if (!e.has(r) && q(r)) {
      e.add(r);
      const s = r[R] ? Array.from(r[R]) : [];
      for (const i of s) n(i);
    }
  }
  return (n(t), Array.from(e));
}
function Qt(t) {
  return t[rt] || t;
}
function zr() {
  const t = O(),
    e = L(t);
  return e.getActiveSpan ? e.getActiveSpan() : nt(C());
}
function Wr() {
  At ||
    (ct(() => {
      console.warn(
        "[Sentry] Returning null from `beforeSendSpan` is disallowed. To drop certain spans, configure the respective integrations directly or use `ignoreSpans`.",
      );
    }),
    (At = !0));
}
function Kr(t, e) {
  (t.updateName(e), t.setAttributes({ [Gt]: "custom", [qe]: e }));
}
function Cn(t) {
  if (typeof __SENTRY_TRACING__ == "boolean" && !__SENTRY_TRACING__) return !1;
  const e = t || N()?.getOptions();
  return !!e && (e.tracesSampleRate != null || !!e.tracesSampler);
}
const Zt = "production",
  te = "_frozenDsc";
function Vr(t, e) {
  T(t, te, e);
}
function ee(t, e) {
  const n = e.getOptions(),
    { publicKey: r } = e.getDsn() || {},
    s = {
      environment: n.environment || Zt,
      release: n.release,
      public_key: r,
      trace_id: t,
      org_id: qt(e),
    };
  return (e.emit("createDsc", s), s);
}
function Xr(t, e) {
  const n = e.getPropagationContext();
  return n.dsc || ee(n.traceId, t);
}
function ne(t) {
  const e = N();
  if (!e) return {};
  const n = Qt(t),
    r = X(n),
    s = r.data,
    i = n.spanContext().traceState,
    o = i?.get("sentry.sample_rate") ?? s[We] ?? s[Ke];
  function a(b) {
    return (
      (typeof o == "number" || typeof o == "string") &&
        (b.sample_rate = `${o}`),
      b
    );
  }
  const c = n[te];
  if (c) return a(c);
  const u = i?.get("sentry.dsc"),
    f = u && Vt(u);
  if (f) return a(f);
  const p = ee(t.spanContext().traceId, e),
    g = s[Gt],
    l = r.description;
  return (
    g !== "url" && l && (p.transaction = l),
    Cn() &&
      ((p.sampled = String(q(n))),
      (p.sample_rand =
        i?.get("sentry.sample_rand") ??
        Wt(n).scope?.getPropagationContext().sampleRand.toString())),
    a(p),
    e.emit("createDsc", p, n),
    p
  );
}
function qr(t) {
  const e = ne(t);
  return rn(e);
}
function I(t, e = 100, n = 1 / 0) {
  try {
    return st("", t, e, n);
  } catch (r) {
    return { ERROR: `**non-serializable** (${r})` };
  }
}
function Nn(t, e = 3, n = 100 * 1024) {
  const r = I(t, e);
  return On(r) > n ? Nn(t, e - 1, n) : r;
}
function st(t, e, n = 1 / 0, r = 1 / 0, s = Mn()) {
  const [i, o] = s;
  if (
    e == null ||
    ["boolean", "string"].includes(typeof e) ||
    (typeof e == "number" && Number.isFinite(e))
  )
    return e;
  const a = Rn(t, e);
  if (!a.startsWith("[object ")) return a;
  if (e.__sentry_skip_normalization__) return e;
  const c =
    typeof e.__sentry_override_normalization_depth__ == "number"
      ? e.__sentry_override_normalization_depth__
      : n;
  if (c === 0) return a.replace("object ", "");
  if (i(e)) return "[Circular ~]";
  const u = e;
  if (u && typeof u.toJSON == "function")
    try {
      const l = u.toJSON();
      return st("", l, c - 1, r, s);
    } catch {}
  const f = Array.isArray(e) ? [] : {};
  let p = 0;
  const g = Ut(e);
  for (const l in g) {
    if (!Object.prototype.hasOwnProperty.call(g, l)) continue;
    if (p >= r) {
      f[l] = "[MaxProperties ~]";
      break;
    }
    const b = g[l];
    ((f[l] = st(l, b, c - 1, r, s)), p++);
  }
  return (o(e), f);
}
function Rn(t, e) {
  try {
    if (t === "domain" && e && typeof e == "object" && e._events)
      return "[Domain]";
    if (t === "domainEmitter") return "[DomainEmitter]";
    if (typeof B < "u" && e === B) return "[Global]";
    if (typeof window < "u" && e === window) return "[Window]";
    if (typeof document < "u" && e === document) return "[Document]";
    if (Lt(e)) return "[VueViewModel]";
    if (Te(e)) return "[SyntheticEvent]";
    if (typeof e == "number" && !Number.isFinite(e)) return `[${e}]`;
    if (typeof e == "function") return `[Function: ${he(e)}]`;
    if (typeof e == "symbol") return `[${String(e)}]`;
    if (typeof e == "bigint") return `[BigInt: ${String(e)}]`;
    const n = xn(e);
    return /^HTML(\w*)Element$/.test(n)
      ? `[HTMLElement: ${n}]`
      : `[object ${n}]`;
  } catch (n) {
    return `**non-serializable** (${n})`;
  }
}
function xn(t) {
  const e = Object.getPrototypeOf(t);
  return e?.constructor ? e.constructor.name : "null prototype";
}
function Dn(t) {
  return ~-encodeURI(t).split(/%..|./).length;
}
function On(t) {
  return Dn(JSON.stringify(t));
}
function Mn() {
  const t = new WeakSet();
  function e(r) {
    return t.has(r) ? !0 : (t.add(r), !1);
  }
  function n(r) {
    t.delete(r);
  }
  return [e, n];
}
const tt = 0,
  Rt = 1,
  xt = 2;
function wn(t) {
  return new k((e) => {
    e(t);
  });
}
function Pn(t) {
  return new k((e, n) => {
    n(t);
  });
}
class k {
  constructor(e) {
    ((this._state = tt), (this._handlers = []), this._runExecutor(e));
  }
  then(e, n) {
    return new k((r, s) => {
      (this._handlers.push([
        !1,
        (i) => {
          if (!e) r(i);
          else
            try {
              r(e(i));
            } catch (o) {
              s(o);
            }
        },
        (i) => {
          if (!n) s(i);
          else
            try {
              r(n(i));
            } catch (o) {
              s(o);
            }
        },
      ]),
        this._executeHandlers());
    });
  }
  catch(e) {
    return this.then((n) => n, e);
  }
  finally(e) {
    return new k((n, r) => {
      let s, i;
      return this.then(
        (o) => {
          ((i = !1), (s = o), e && e());
        },
        (o) => {
          ((i = !0), (s = o), e && e());
        },
      ).then(() => {
        if (i) {
          r(s);
          return;
        }
        n(s);
      });
    });
  }
  _executeHandlers() {
    if (this._state === tt) return;
    const e = this._handlers.slice();
    ((this._handlers = []),
      e.forEach((n) => {
        n[0] ||
          (this._state === Rt && n[1](this._value),
          this._state === xt && n[2](this._value),
          (n[0] = !0));
      }));
  }
  _runExecutor(e) {
    const n = (i, o) => {
        if (this._state === tt) {
          if (z(o)) {
            o.then(r, s);
            return;
          }
          ((this._state = i), (this._value = o), this._executeHandlers());
        }
      },
      r = (i) => {
        n(Rt, i);
      },
      s = (i) => {
        n(xt, i);
      };
    try {
      e(r, s);
    } catch (i) {
      s(i);
    }
  }
}
function kn(t, e, n, r = 0) {
  try {
    const s = it(e, n, t, r);
    return z(s) ? s : wn(s);
  } catch (s) {
    return Pn(s);
  }
}
function it(t, e, n, r) {
  const s = n[r];
  if (!t || !s) return t;
  const i = s({ ...t }, e);
  return (
    m && i === null && d.log(`Event processor "${s.id || "?"}" dropped event`),
    z(i) ? i.then((o) => it(o, e, n, r + 1)) : it(i, e, n, r + 1)
  );
}
function $n(t, e) {
  const {
    fingerprint: n,
    span: r,
    breadcrumbs: s,
    sdkProcessingMetadata: i,
  } = e;
  (Ln(t, e), r && jn(t, r), vn(t, n), Fn(t, s), Un(t, i));
}
function Dt(t, e) {
  const {
    extra: n,
    tags: r,
    user: s,
    contexts: i,
    level: o,
    sdkProcessingMetadata: a,
    breadcrumbs: c,
    fingerprint: u,
    eventProcessors: f,
    attachments: p,
    propagationContext: g,
    transactionName: l,
    span: b,
  } = e;
  (U(t, "extra", n),
    U(t, "tags", r),
    U(t, "user", s),
    U(t, "contexts", i),
    (t.sdkProcessingMetadata = K(t.sdkProcessingMetadata, a, 2)),
    o && (t.level = o),
    l && (t.transactionName = l),
    b && (t.span = b),
    c.length && (t.breadcrumbs = [...t.breadcrumbs, ...c]),
    u.length && (t.fingerprint = [...t.fingerprint, ...u]),
    f.length && (t.eventProcessors = [...t.eventProcessors, ...f]),
    p.length && (t.attachments = [...t.attachments, ...p]),
    (t.propagationContext = { ...t.propagationContext, ...g }));
}
function U(t, e, n) {
  t[e] = K(t[e], n, 1);
}
function Ln(t, e) {
  const {
    extra: n,
    tags: r,
    user: s,
    contexts: i,
    level: o,
    transactionName: a,
  } = e;
  (Object.keys(n).length && (t.extra = { ...n, ...t.extra }),
    Object.keys(r).length && (t.tags = { ...r, ...t.tags }),
    Object.keys(s).length && (t.user = { ...s, ...t.user }),
    Object.keys(i).length && (t.contexts = { ...i, ...t.contexts }),
    o && (t.level = o),
    a && t.type !== "transaction" && (t.transaction = a));
}
function Fn(t, e) {
  const n = [...(t.breadcrumbs || []), ...e];
  t.breadcrumbs = n.length ? n : void 0;
}
function Un(t, e) {
  t.sdkProcessingMetadata = { ...t.sdkProcessingMetadata, ...e };
}
function jn(t, e) {
  ((t.contexts = { trace: En(e), ...t.contexts }),
    (t.sdkProcessingMetadata = {
      dynamicSamplingContext: ne(e),
      ...t.sdkProcessingMetadata,
    }));
  const n = Qt(e),
    r = X(n).description;
  r && !t.transaction && t.type === "transaction" && (t.transaction = r);
}
function vn(t, e) {
  ((t.fingerprint = t.fingerprint
    ? Array.isArray(t.fingerprint)
      ? t.fingerprint
      : [t.fingerprint]
    : []),
    e && (t.fingerprint = t.fingerprint.concat(e)),
    t.fingerprint.length || delete t.fingerprint);
}
let j, Ot, v;
function re(t) {
  const e = _._sentryDebugIds;
  if (!e) return {};
  const n = Object.keys(e);
  return (
    (v && n.length === Ot) ||
      ((Ot = n.length),
      (v = n.reduce((r, s) => {
        j || (j = {});
        const i = j[s];
        if (i) r[i[0]] = i[1];
        else {
          const o = t(s);
          for (let a = o.length - 1; a >= 0; a--) {
            const u = o[a]?.filename,
              f = e[s];
            if (u && f) {
              ((r[u] = f), (j[s] = [u, f]));
              break;
            }
          }
        }
        return r;
      }, {}))),
    v
  );
}
function Jr(t, e) {
  const n = re(t);
  if (!n) return [];
  const r = [];
  for (const s of e)
    s && n[s] && r.push({ type: "sourcemap", code_file: s, debug_id: n[s] });
  return r;
}
function Qr(t, e, n, r, s, i) {
  const { normalizeDepth: o = 3, normalizeMaxBreadth: a = 1e3 } = t,
    c = {
      ...e,
      event_id: e.event_id || n.event_id || A(),
      timestamp: e.timestamp || dt(),
    },
    u = n.integrations || t.integrations.map((y) => y.name);
  (Bn(c, t),
    Yn(c, u),
    s && s.emit("applyFrameMetadata", e),
    e.type === void 0 && Gn(c, t.stackParser));
  const f = Wn(r, n.captureContext);
  n.mechanism && vt(c, n.mechanism);
  const p = s ? s.getEventProcessors() : [],
    g = Ye().getScopeData();
  if (i) {
    const y = i.getScopeData();
    Dt(g, y);
  }
  if (f) {
    const y = f.getScopeData();
    Dt(g, y);
  }
  const l = [...(n.attachments || []), ...g.attachments];
  (l.length && (n.attachments = l), $n(c, g));
  const b = [...p, ...g.eventProcessors];
  return kn(b, c, n).then(
    (y) => (y && Hn(y), typeof o == "number" && o > 0 ? zn(y, o, a) : y),
  );
}
function Bn(t, e) {
  const { environment: n, release: r, dist: s, maxValueLength: i = 250 } = e;
  ((t.environment = t.environment || n || Zt),
    !t.release && r && (t.release = r),
    !t.dist && s && (t.dist = s));
  const o = t.request;
  o?.url && (o.url = H(o.url, i));
}
function Gn(t, e) {
  const n = re(e);
  t.exception?.values?.forEach((r) => {
    r.stacktrace?.frames?.forEach((s) => {
      s.filename && (s.debug_id = n[s.filename]);
    });
  });
}
function Hn(t) {
  const e = {};
  if (
    (t.exception?.values?.forEach((r) => {
      r.stacktrace?.frames?.forEach((s) => {
        s.debug_id &&
          (s.abs_path
            ? (e[s.abs_path] = s.debug_id)
            : s.filename && (e[s.filename] = s.debug_id),
          delete s.debug_id);
      });
    }),
    Object.keys(e).length === 0)
  )
    return;
  ((t.debug_meta = t.debug_meta || {}),
    (t.debug_meta.images = t.debug_meta.images || []));
  const n = t.debug_meta.images;
  Object.entries(e).forEach(([r, s]) => {
    n.push({ type: "sourcemap", code_file: r, debug_id: s });
  });
}
function Yn(t, e) {
  e.length > 0 &&
    ((t.sdk = t.sdk || {}),
    (t.sdk.integrations = [...(t.sdk.integrations || []), ...e]));
}
function zn(t, e, n) {
  if (!t) return null;
  const r = {
    ...t,
    ...(t.breadcrumbs && {
      breadcrumbs: t.breadcrumbs.map((s) => ({
        ...s,
        ...(s.data && { data: I(s.data, e, n) }),
      })),
    }),
    ...(t.user && { user: I(t.user, e, n) }),
    ...(t.contexts && { contexts: I(t.contexts, e, n) }),
    ...(t.extra && { extra: I(t.extra, e, n) }),
  };
  return (
    t.contexts?.trace &&
      r.contexts &&
      ((r.contexts.trace = t.contexts.trace),
      t.contexts.trace.data &&
        (r.contexts.trace.data = I(t.contexts.trace.data, e, n))),
    t.spans &&
      (r.spans = t.spans.map((s) => ({
        ...s,
        ...(s.data && { data: I(s.data, e, n) }),
      }))),
    t.contexts?.flags &&
      r.contexts &&
      (r.contexts.flags = I(t.contexts.flags, 3, n)),
    r
  );
}
function Wn(t, e) {
  if (!e) return t;
  const n = t ? t.clone() : new E();
  return (n.update(e), n);
}
function Kn(t) {
  if (t)
    return Vn(t) ? { captureContext: t } : qn(t) ? { captureContext: t } : t;
}
function Vn(t) {
  return t instanceof E || typeof t == "function";
}
const Xn = [
  "user",
  "level",
  "extra",
  "contexts",
  "tags",
  "fingerprint",
  "propagationContext",
];
function qn(t) {
  return Object.keys(t).some((e) => Xn.includes(e));
}
function Jn(t, e) {
  return C().captureException(t, Kn(e));
}
function Zr(t, e) {
  const n = typeof e == "string" ? e : void 0,
    r = typeof e != "string" ? { captureContext: e } : void 0;
  return C().captureMessage(t, n, r);
}
function ts(t, e) {
  return C().captureEvent(t, e);
}
function es(t, e) {
  S().setContext(t, e);
}
function ns(t) {
  S().setExtras(t);
}
function rs(t, e) {
  S().setExtra(t, e);
}
function ss(t) {
  S().setTags(t);
}
function is(t, e) {
  S().setTag(t, e);
}
function os(t) {
  S().setUser(t);
}
function Qn() {
  return S().lastEventId();
}
async function as(t) {
  const e = N();
  return e
    ? e.flush(t)
    : (m && d.warn("Cannot flush events. No client defined."),
      Promise.resolve(!1));
}
async function cs(t) {
  const e = N();
  return e
    ? e.close(t)
    : (m && d.warn("Cannot flush events and disable SDK. No client defined."),
      Promise.resolve(!1));
}
function us() {
  return !!N();
}
function fs() {
  const t = N();
  return t?.getOptions().enabled !== !1 && !!t?.getTransport();
}
function ps(t) {
  S().addEventProcessor(t);
}
function ds(t) {
  const e = S(),
    n = C(),
    { userAgent: r } = _.navigator || {},
    s = ke({
      user: n.getUser() || e.getUser(),
      ...(r && { userAgent: r }),
      ...t,
    }),
    i = e.getSession();
  return (
    i?.status === "ok" && W(i, { status: "exited" }),
    se(),
    e.setSession(s),
    s
  );
}
function se() {
  const t = S(),
    n = C().getSession() || t.getSession();
  (n && $e(n), ie(), t.setSession());
}
function ie() {
  const t = S(),
    e = N(),
    n = t.getSession();
  n && e && e.captureSession(n);
}
function ls(t = !1) {
  if (t) {
    se();
    return;
  }
  ie();
}
const Zn = "7";
function oe(t) {
  const e = t.protocol ? `${t.protocol}:` : "",
    n = t.port ? `:${t.port}` : "";
  return `${e}//${t.host}${n}${t.path ? `/${t.path}` : ""}/api/`;
}
function tr(t) {
  return `${oe(t)}${t.projectId}/envelope/`;
}
function er(t, e) {
  const n = { sentry_version: Zn };
  return (
    t.publicKey && (n.sentry_key = t.publicKey),
    e && (n.sentry_client = `${e.name}/${e.version}`),
    new URLSearchParams(n).toString()
  );
}
function _s(t, e, n) {
  return e || `${tr(t)}?${er(t, n)}`;
}
function nr(t, e) {
  const n = _n(t);
  if (!n) return "";
  const r = `${oe(n)}embed/error-page/`;
  let s = `dsn=${fn(n)}`;
  for (const i in e)
    if (i !== "dsn" && i !== "onClose")
      if (i === "user") {
        const o = e.user;
        if (!o) continue;
        (o.name && (s += `&name=${encodeURIComponent(o.name)}`),
          o.email && (s += `&email=${encodeURIComponent(o.email)}`));
      } else s += `&${encodeURIComponent(i)}=${encodeURIComponent(e[i])}`;
  return `${r}?${s}`;
}
const x = _;
let ot = 0;
function gs() {
  return ot > 0;
}
function rr() {
  (ot++,
    setTimeout(() => {
      ot--;
    }));
}
function sr(t, e = {}) {
  function n(s) {
    return typeof s == "function";
  }
  if (!n(t)) return t;
  try {
    const s = t.__sentry_wrapped__;
    if (s) return typeof s == "function" ? s : t;
    if (xe(t)) return t;
  } catch {
    return t;
  }
  const r = function (...s) {
    try {
      const i = s.map((o) => sr(o, e));
      return t.apply(this, i);
    } catch (i) {
      throw (
        rr(),
        ze((o) => {
          (o.addEventProcessor(
            (a) => (
              e.mechanism && (Oe(a, void 0), vt(a, e.mechanism)),
              (a.extra = { ...a.extra, arguments: s }),
              a
            ),
          ),
            Jn(i));
        }),
        i
      );
    }
  };
  try {
    for (const s in t)
      Object.prototype.hasOwnProperty.call(t, s) && (r[s] = t[s]);
  } catch {}
  (Ft(r, t), T(t, "__sentry_wrapped__", r));
  try {
    Object.getOwnPropertyDescriptor(r, "name").configurable &&
      Object.defineProperty(r, "name", {
        get() {
          return t.name;
        },
      });
  } catch {}
  return r;
}
function hs() {
  const t = Ne(),
    { referrer: e } = x.document || {},
    { userAgent: n } = x.navigator || {},
    r = { ...(e && { Referer: e }), ...(n && { "User-Agent": n }) };
  return { url: t, headers: r };
}
const Mt = typeof __SENTRY_DEBUG__ > "u" || __SENTRY_DEBUG__;
function ms(t = {}) {
  const e = x.document,
    n = e?.head || e?.body;
  if (!n) {
    Mt && d.error("[showReportDialog] Global document not defined");
    return;
  }
  const r = C(),
    i = N()?.getDsn();
  if (!i) {
    Mt && d.error("[showReportDialog] DSN not configured");
    return;
  }
  const o = {
      ...t,
      user: { ...r.getUser(), ...t.user },
      eventId: t.eventId || Qn(),
    },
    a = x.document.createElement("script");
  ((a.async = !0), (a.crossOrigin = "anonymous"), (a.src = nr(i, o)));
  const { onLoad: c, onClose: u } = o;
  if ((c && (a.onload = c), u)) {
    const f = (p) => {
      if (p.data === "__sentry_reportdialog_closed__")
        try {
          u();
        } finally {
          x.removeEventListener("message", f);
        }
    };
    x.addEventListener("message", f);
  }
  n.appendChild(a);
}
export {
  se as $,
  vt as A,
  Oe as B,
  ar as C,
  m as D,
  T as E,
  Vt as F,
  _ as G,
  Ir as H,
  ts as I,
  Jn as J,
  Zr as K,
  ls as L,
  Tr as M,
  cs as N,
  ct as O,
  bn as P,
  _e as Q,
  dt as R,
  w as S,
  gn as T,
  le as U,
  d as V,
  x as W,
  pn as X,
  fn as Y,
  rn as Z,
  nt as _,
  Mt as a,
  wn as a$,
  yr as a0,
  Sr as a1,
  as as a2,
  Vr as a3,
  mn as a4,
  V as a5,
  P as a6,
  Sn as a7,
  zr as a8,
  L as a9,
  pr as aA,
  dr as aB,
  fs as aC,
  me as aD,
  fr as aE,
  ye as aF,
  us as aG,
  $ as aH,
  Re as aI,
  Se as aJ,
  $t as aK,
  lr as aL,
  _r as aM,
  G as aN,
  z as aO,
  Qn as aP,
  _n as aQ,
  K as aR,
  Dt as aS,
  I as aT,
  Nn as aU,
  _t as aV,
  It as aW,
  Qr as aX,
  Lr as aY,
  Pn as aZ,
  Hr as a_,
  Wt as aa,
  N as ab,
  gr as ac,
  C as ad,
  Jr as ae,
  Xr as af,
  ne as ag,
  _s as ah,
  Er as ai,
  ur as aj,
  he as ak,
  Ye as al,
  Y as am,
  hs as an,
  S as ao,
  Ne as ap,
  O as aq,
  xe as ar,
  Qt as as,
  at,
  Yr as au,
  Qe as av,
  An as aw,
  Cr as ax,
  Cn as ay,
  Ae as az,
  Zt as b,
  hr as b0,
  $r as b1,
  es as b2,
  rs as b3,
  ns as b4,
  kr as b5,
  is as b6,
  ss as b7,
  os as b8,
  Fr as b9,
  gs as ba,
  ms as bb,
  Wr as bc,
  q as bd,
  Ct as be,
  qr as bf,
  X as bg,
  En as bh,
  vr as bi,
  Br as bj,
  jr as bk,
  cr as bl,
  ds as bm,
  mr as bn,
  lt as bo,
  H as bp,
  W as bq,
  Kr as br,
  A as bs,
  Ar as bt,
  ze as bu,
  sr as bv,
  Or as c,
  Mr as d,
  Dr as e,
  qe as f,
  Nr as g,
  Rr as h,
  xr as i,
  Ve as j,
  Xe as k,
  Ke as l,
  We as m,
  Gt as n,
  wr as o,
  Pr as p,
  Kt as q,
  h as r,
  Ht as s,
  E as t,
  Ur as u,
  Jt as v,
  Et as w,
  Gr as x,
  br as y,
  ps as z,
};
//# sourceMappingURL=report-dialog-C-g_klPx.js.map
