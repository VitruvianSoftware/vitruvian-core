import { aa as ys, ae as Nc, M as vm } from "./sentry-common-BxRELKId.js";
import {
  D as N,
  V as S,
  ak as zt,
  G as ne,
  a8 as Pe,
  as as Ne,
  r as lt,
  aI as Ni,
  a6 as Jn,
  a5 as Pn,
  u as bd,
  Y as kn,
  at as Ed,
  aT as Ko,
  ag as Ct,
  bg as ee,
  bc as uo,
  bd as ti,
  h as vd,
  i as Td,
  bo as ke,
  j as Rt,
  k as Ze,
  v as Tm,
  be as Fn,
  n as rt,
  P as wm,
  c as Jo,
  e as Zo,
  aw as Im,
  ab as W,
  aa as Oc,
  ad as ue,
  au as Bn,
  f as Lc,
  bk as km,
  aO as wd,
  ay as Je,
  aW as Qo,
  aq as ea,
  a9 as ta,
  F as Cm,
  b9 as Rm,
  bu as qe,
  _ as Id,
  a3 as ts,
  ao as Cn,
  x as kd,
  b1 as xm,
  m as na,
  w as jt,
  aY as Cd,
  g as Zn,
  a_ as Am,
  R as ni,
  aQ as Mm,
  ah as Rd,
  bs as Un,
  M as $c,
  aL as ri,
  bq as Dc,
  b as xd,
  aX as Nm,
  ax as Ad,
  af as ra,
  aZ as Md,
  aJ as sa,
  aR as Om,
  aK as qt,
  bh as Lm,
  O as si,
  am as $m,
  al as Nd,
  aS as Pc,
  a$ as ia,
  X as Dm,
  S as bs,
  aC as Od,
  bi as Ld,
  Z as Pm,
  T as Fm,
  bj as Bm,
  a4 as Um,
  a7 as Hm,
  ar as $d,
  ai as Lt,
  bn as it,
  aH as Es,
  C as oa,
  a1 as Xe,
  aV as Fc,
  A as Gt,
  b0 as vs,
  K as Ts,
  J as Qn,
  aj as lo,
  aD as Bt,
  E as aa,
  bp as Dd,
  s as Wm,
  b5 as er,
  aM as Pd,
  q as zm,
  W as B,
  aE as Fd,
  aA as Bc,
  aB as jm,
  B as Uc,
  aF as ca,
  aU as qm,
  a0 as Gm,
  U as dt,
  Q as Vm,
  a as G,
  az as Ym,
  ac as Xm,
  bv as tr,
  bm as fo,
  L as po,
  ba as Bd,
  I as pr,
  ap as ii,
  aN as ho,
  an as ua,
  bl as Km,
  y as Jm,
  o as Zm,
  d as Qm,
  l as eg,
  p as tg,
  H as Ud,
  ae as ng,
  t as rg,
  z as sg,
  N as ig,
  $ as og,
  a2 as ag,
  av as cg,
  aG as ug,
  aP as lg,
  b2 as dg,
  b3 as fg,
  b4 as pg,
  b6 as la,
  b7 as hg,
  b8 as mg,
  bb as gg,
  bf as _g,
  br as Sg,
  bt as yg,
} from "./report-dialog-7bETf2vU.js";
import { g as ws } from "./index-Cw3pknxT.js";
(function () {
  try {
    var e =
      typeof window < "u"
        ? window
        : typeof ws < "u"
          ? ws
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    e.SENTRY_RELEASE = { id: "4.3.209" };
    var t = new e.Error().stack;
    t &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[t] = "b1a13b8f-0f8e-42e6-a954-8ebeedcf01ed"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-b1a13b8f-0f8e-42e6-a954-8ebeedcf01ed"));
  } catch {}
})();
const Ut = typeof __SENTRY_DEBUG__ > "u" || __SENTRY_DEBUG__,
  je = globalThis,
  Hn = "10.17.0";
function da() {
  return (fa(je), je);
}
function fa(e) {
  const t = (e.__SENTRY__ = e.__SENTRY__ || {});
  return ((t.version = t.version || Hn), (t[Hn] = t[Hn] || {}));
}
function oi(e, t, n = je) {
  const r = (n.__SENTRY__ = n.__SENTRY__ || {}),
    s = (r[Hn] = r[Hn] || {});
  return s[e] || (s[e] = t());
}
const bg = "Sentry Logger ",
  Hc = {};
function Eg(e) {
  if (!("console" in je)) return e();
  const t = je.console,
    n = {},
    r = Object.keys(Hc);
  r.forEach((s) => {
    const i = Hc[s];
    ((n[s] = t[s]), (t[s] = i));
  });
  try {
    return e();
  } finally {
    r.forEach((s) => {
      t[s] = n[s];
    });
  }
}
function vg() {
  ha().enabled = !0;
}
function Tg() {
  ha().enabled = !1;
}
function Hd() {
  return ha().enabled;
}
function wg(...e) {
  pa("log", ...e);
}
function Ig(...e) {
  pa("warn", ...e);
}
function kg(...e) {
  pa("error", ...e);
}
function pa(e, ...t) {
  Ut &&
    Hd() &&
    Eg(() => {
      je.console[e](`${bg}[${e}]:`, ...t);
    });
}
function ha() {
  return Ut ? oi("loggerSettings", () => ({ enabled: !1 })) : { enabled: !1 };
}
const ot = {
    enable: vg,
    disable: Tg,
    isEnabled: Hd,
    log: wg,
    warn: Ig,
    error: kg,
  },
  Cg = Object.prototype.toString;
function Rg(e, t) {
  return Cg.call(e) === `[object ${t}]`;
}
function xg(e) {
  return Rg(e, "Object");
}
function Ag(e) {
  return !!(e?.then && typeof e.then == "function");
}
const Mg = je;
function Ng() {
  try {
    return Mg.document.location.href;
  } catch {
    return "";
  }
}
function Og(e, t = 0) {
  return typeof e != "string" || t === 0 || e.length <= t
    ? e
    : `${e.slice(0, t)}...`;
}
function Lg(e, t, n) {
  try {
    Object.defineProperty(e, t, { value: n, writable: !0, configurable: !0 });
  } catch {
    Ut && ot.log(`Failed to add non-enumerable property "${t}" to object`, e);
  }
}
function $g() {
  const e = je;
  return e.crypto || e.msCrypto;
}
function Wn(e = $g()) {
  let t = () => Math.random() * 16;
  try {
    if (e?.randomUUID) return e.randomUUID().replace(/-/g, "");
    e?.getRandomValues &&
      (t = () => {
        const n = new Uint8Array(1);
        return (e.getRandomValues(n), n[0]);
      });
  } catch {}
  return ("10000000100040008000" + 1e11).replace(/[018]/g, (n) =>
    (n ^ ((t() & 15) >> (n / 4))).toString(16),
  );
}
const Wd = 1e3;
function zd() {
  return Date.now() / Wd;
}
function Dg() {
  const { performance: e } = je;
  if (!e?.now || !e.timeOrigin) return zd;
  const t = e.timeOrigin;
  return () => (t + e.now()) / Wd;
}
let Wc;
function Pg() {
  return (Wc ?? (Wc = Dg()))();
}
function Fg(e, t = {}) {
  if (
    (t.user &&
      (!e.ipAddress && t.user.ip_address && (e.ipAddress = t.user.ip_address),
      !e.did &&
        !t.did &&
        (e.did = t.user.id || t.user.email || t.user.username)),
    (e.timestamp = t.timestamp || Pg()),
    t.abnormal_mechanism && (e.abnormal_mechanism = t.abnormal_mechanism),
    t.ignoreDuration && (e.ignoreDuration = t.ignoreDuration),
    t.sid && (e.sid = t.sid.length === 32 ? t.sid : Wn()),
    t.init !== void 0 && (e.init = t.init),
    !e.did && t.did && (e.did = `${t.did}`),
    typeof t.started == "number" && (e.started = t.started),
    e.ignoreDuration)
  )
    e.duration = void 0;
  else if (typeof t.duration == "number") e.duration = t.duration;
  else {
    const n = e.timestamp - e.started;
    e.duration = n >= 0 ? n : 0;
  }
  (t.release && (e.release = t.release),
    t.environment && (e.environment = t.environment),
    !e.ipAddress && t.ipAddress && (e.ipAddress = t.ipAddress),
    !e.userAgent && t.userAgent && (e.userAgent = t.userAgent),
    typeof t.errors == "number" && (e.errors = t.errors),
    t.status && (e.status = t.status));
}
function jd(e, t, n = 2) {
  if (!t || typeof t != "object" || n <= 0) return t;
  if (e && Object.keys(t).length === 0) return e;
  const r = { ...e };
  for (const s in t)
    Object.prototype.hasOwnProperty.call(t, s) &&
      (r[s] = jd(r[s], t[s], n - 1));
  return r;
}
function zc() {
  return Wn();
}
const mo = "_sentrySpan";
function jc(e, t) {
  t ? Lg(e, mo, t) : delete e[mo];
}
function qc(e) {
  return e[mo];
}
const Bg = 100;
let nr = class go {
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
      (this._propagationContext = {
        traceId: zc(),
        sampleRand: Math.random(),
      }));
  }
  clone() {
    const t = new go();
    return (
      (t._breadcrumbs = [...this._breadcrumbs]),
      (t._tags = { ...this._tags }),
      (t._extra = { ...this._extra }),
      (t._contexts = { ...this._contexts }),
      this._contexts.flags &&
        (t._contexts.flags = { values: [...this._contexts.flags.values] }),
      (t._user = this._user),
      (t._level = this._level),
      (t._session = this._session),
      (t._transactionName = this._transactionName),
      (t._fingerprint = this._fingerprint),
      (t._eventProcessors = [...this._eventProcessors]),
      (t._attachments = [...this._attachments]),
      (t._sdkProcessingMetadata = { ...this._sdkProcessingMetadata }),
      (t._propagationContext = { ...this._propagationContext }),
      (t._client = this._client),
      (t._lastEventId = this._lastEventId),
      jc(t, qc(this)),
      t
    );
  }
  setClient(t) {
    this._client = t;
  }
  setLastEventId(t) {
    this._lastEventId = t;
  }
  getClient() {
    return this._client;
  }
  lastEventId() {
    return this._lastEventId;
  }
  addScopeListener(t) {
    this._scopeListeners.push(t);
  }
  addEventProcessor(t) {
    return (this._eventProcessors.push(t), this);
  }
  setUser(t) {
    return (
      (this._user = t || {
        email: void 0,
        id: void 0,
        ip_address: void 0,
        username: void 0,
      }),
      this._session && Fg(this._session, { user: t }),
      this._notifyScopeListeners(),
      this
    );
  }
  getUser() {
    return this._user;
  }
  setTags(t) {
    return (
      (this._tags = { ...this._tags, ...t }),
      this._notifyScopeListeners(),
      this
    );
  }
  setTag(t, n) {
    return (
      (this._tags = { ...this._tags, [t]: n }),
      this._notifyScopeListeners(),
      this
    );
  }
  setExtras(t) {
    return (
      (this._extra = { ...this._extra, ...t }),
      this._notifyScopeListeners(),
      this
    );
  }
  setExtra(t, n) {
    return (
      (this._extra = { ...this._extra, [t]: n }),
      this._notifyScopeListeners(),
      this
    );
  }
  setFingerprint(t) {
    return ((this._fingerprint = t), this._notifyScopeListeners(), this);
  }
  setLevel(t) {
    return ((this._level = t), this._notifyScopeListeners(), this);
  }
  setTransactionName(t) {
    return ((this._transactionName = t), this._notifyScopeListeners(), this);
  }
  setContext(t, n) {
    return (
      n === null ? delete this._contexts[t] : (this._contexts[t] = n),
      this._notifyScopeListeners(),
      this
    );
  }
  setSession(t) {
    return (
      t ? (this._session = t) : delete this._session,
      this._notifyScopeListeners(),
      this
    );
  }
  getSession() {
    return this._session;
  }
  update(t) {
    if (!t) return this;
    const n = typeof t == "function" ? t(this) : t,
      r = n instanceof go ? n.getScopeData() : xg(n) ? t : void 0,
      {
        tags: s,
        extra: i,
        user: o,
        contexts: a,
        level: c,
        fingerprint: u = [],
        propagationContext: d,
      } = r || {};
    return (
      (this._tags = { ...this._tags, ...s }),
      (this._extra = { ...this._extra, ...i }),
      (this._contexts = { ...this._contexts, ...a }),
      o && Object.keys(o).length && (this._user = o),
      c && (this._level = c),
      u.length && (this._fingerprint = u),
      d && (this._propagationContext = d),
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
      jc(this, void 0),
      (this._attachments = []),
      this.setPropagationContext({ traceId: zc(), sampleRand: Math.random() }),
      this._notifyScopeListeners(),
      this
    );
  }
  addBreadcrumb(t, n) {
    const r = typeof n == "number" ? n : Bg;
    if (r <= 0) return this;
    const s = {
      timestamp: zd(),
      ...t,
      message: t.message ? Og(t.message, 2048) : t.message,
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
  addAttachment(t) {
    return (this._attachments.push(t), this);
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
      span: qc(this),
    };
  }
  setSDKProcessingMetadata(t) {
    return (
      (this._sdkProcessingMetadata = jd(this._sdkProcessingMetadata, t, 2)),
      this
    );
  }
  setPropagationContext(t) {
    return ((this._propagationContext = t), this);
  }
  getPropagationContext() {
    return this._propagationContext;
  }
  captureException(t, n) {
    const r = n?.event_id || Wn();
    if (!this._client)
      return (
        Ut &&
          ot.warn(
            "No client configured on scope - will not capture exception!",
          ),
        r
      );
    const s = new Error("Sentry syntheticException");
    return (
      this._client.captureException(
        t,
        { originalException: t, syntheticException: s, ...n, event_id: r },
        this,
      ),
      r
    );
  }
  captureMessage(t, n, r) {
    const s = r?.event_id || Wn();
    if (!this._client)
      return (
        Ut &&
          ot.warn("No client configured on scope - will not capture message!"),
        s
      );
    const i = new Error(t);
    return (
      this._client.captureMessage(
        t,
        n,
        { originalException: t, syntheticException: i, ...r, event_id: s },
        this,
      ),
      s
    );
  }
  captureEvent(t, n) {
    const r = n?.event_id || Wn();
    return this._client
      ? (this._client.captureEvent(t, { ...n, event_id: r }, this), r)
      : (Ut &&
          ot.warn("No client configured on scope - will not capture event!"),
        r);
  }
  _notifyScopeListeners() {
    this._notifyingListeners ||
      ((this._notifyingListeners = !0),
      this._scopeListeners.forEach((t) => {
        t(this);
      }),
      (this._notifyingListeners = !1));
  }
};
function Ug() {
  return oi("defaultCurrentScope", () => new nr());
}
function Hg() {
  return oi("defaultIsolationScope", () => new nr());
}
let Wg = class {
  constructor(t, n) {
    let r;
    t ? (r = t) : (r = new nr());
    let s;
    (n ? (s = n) : (s = new nr()),
      (this._stack = [{ scope: r }]),
      (this._isolationScope = s));
  }
  withScope(t) {
    const n = this._pushScope();
    let r;
    try {
      r = t(n);
    } catch (s) {
      throw (this._popScope(), s);
    }
    return Ag(r)
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
    const t = this.getScope().clone();
    return (this._stack.push({ client: this.getClient(), scope: t }), t);
  }
  _popScope() {
    return this._stack.length <= 1 ? !1 : !!this._stack.pop();
  }
};
function fn() {
  const e = da(),
    t = fa(e);
  return (t.stack = t.stack || new Wg(Ug(), Hg()));
}
function zg(e) {
  return fn().withScope(e);
}
function jg(e, t) {
  const n = fn();
  return n.withScope(() => ((n.getStackTop().scope = e), t(e)));
}
function Gc(e) {
  return fn().withScope(() => e(fn().getIsolationScope()));
}
function qg() {
  return {
    withIsolationScope: Gc,
    withScope: zg,
    withSetScope: jg,
    withSetIsolationScope: (e, t) => Gc(t),
    getCurrentScope: () => fn().getScope(),
    getIsolationScope: () => fn().getIsolationScope(),
  };
}
function qd(e) {
  const t = fa(e);
  return t.acs ? t.acs : qg();
}
function ai() {
  const e = da();
  return qd(e).getCurrentScope();
}
function Gg() {
  const e = da();
  return qd(e).getIsolationScope();
}
function Vg() {
  return oi("globalScope", () => new nr());
}
function hr() {
  return ai().getClient();
}
function Vc(e) {
  const t = hr();
  if (!t) {
    Ut &&
      ot.warn(
        `Cannot add integration "${e.name}" because no SDK Client is available.`,
      );
    return;
  }
  t.addIntegration(e);
}
function Yg(e, t = {}, n = ai()) {
  const {
      message: r,
      name: s,
      email: i,
      url: o,
      source: a,
      associatedEventId: c,
      tags: u,
    } = e,
    d = {
      contexts: {
        feedback: {
          contact_email: i,
          name: s,
          message: r,
          url: o,
          source: a,
          associated_event_id: c,
        },
      },
      type: "feedback",
      level: "info",
      tags: u,
    },
    l = n?.getClient() || hr();
  return (l && l.emit("beforeSendFeedback", d, t), n.captureEvent(d, t));
}
function Xg() {
  return typeof __SENTRY_BROWSER_BUNDLE__ < "u" && !!__SENTRY_BROWSER_BUNDLE__;
}
function Kg() {
  return (
    !Xg() &&
    Object.prototype.toString.call(typeof ys < "u" ? ys : 0) ===
      "[object process]"
  );
}
function Jg() {
  return typeof window < "u" && (!Kg() || Zg());
}
function Zg() {
  return je.process?.type === "renderer";
}
const We = je,
  re = We.document,
  Dn = We.navigator,
  Gd = "Report a Bug",
  Qg = "Cancel",
  e_ = "Send Bug Report",
  t_ = "Confirm",
  n_ = "Report a Bug",
  r_ = "your.email@example.org",
  s_ = "Email",
  i_ = "What's the bug? What did you expect?",
  o_ = "Description",
  a_ = "Your Name",
  c_ = "Name",
  u_ = "Thank you for your report!",
  l_ = "(required)",
  d_ = "Add a screenshot",
  f_ = "Remove screenshot",
  p_ = "Highlight",
  h_ = "Hide",
  m_ = "Remove",
  g_ = "widget",
  __ = "api",
  S_ = 5e3,
  Vd = (e, t = { includeReplay: !0 }) => {
    if (!e.message)
      throw new Error("Unable to submit feedback with empty message");
    const n = hr();
    if (!n) throw new Error("No client setup, cannot send feedback.");
    e.tags && Object.keys(e.tags).length && ai().setTags(e.tags);
    const r = Yg({ source: __, url: Ng(), ...e }, t);
    return new Promise((s, i) => {
      const o = setTimeout(
          () => i("Unable to determine if Feedback was correctly sent."),
          3e4,
        ),
        a = n.on("afterSendEvent", (c, u) => {
          if (c.event_id === r)
            return (
              clearTimeout(o),
              a(),
              u?.statusCode && u.statusCode >= 200 && u.statusCode < 300
                ? s(r)
                : u?.statusCode === 403
                  ? i(
                      "Unable to send feedback. This could be because this domain is not in your list of allowed domains.",
                    )
                  : i(
                      "Unable to send feedback. This could be because of network issues, or because you are using an ad-blocker.",
                    )
            );
        });
    });
  },
  ns = typeof __SENTRY_DEBUG__ > "u" || __SENTRY_DEBUG__;
function y_() {
  return !(
    /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(
      Dn.userAgent,
    ) ||
    (/Macintosh/i.test(Dn.userAgent) &&
      Dn.maxTouchPoints &&
      Dn.maxTouchPoints > 1) ||
    !isSecureContext
  );
}
function Dr(e, t) {
  return {
    ...e,
    ...t,
    tags: { ...e.tags, ...t.tags },
    onFormOpen: () => {
      (t.onFormOpen?.(), e.onFormOpen?.());
    },
    onFormClose: () => {
      (t.onFormClose?.(), e.onFormClose?.());
    },
    onSubmitSuccess: (n, r) => {
      (t.onSubmitSuccess?.(n, r), e.onSubmitSuccess?.(n, r));
    },
    onSubmitError: (n) => {
      (t.onSubmitError?.(n), e.onSubmitError?.(n));
    },
    onFormSubmitted: () => {
      (t.onFormSubmitted?.(), e.onFormSubmitted?.());
    },
    themeDark: { ...e.themeDark, ...t.themeDark },
    themeLight: { ...e.themeLight, ...t.themeLight },
  };
}
function b_(e) {
  const t = re.createElement("style");
  return (
    (t.textContent = `
.widget__actor {
  position: fixed;
  z-index: var(--z-index);
  margin: var(--page-margin);
  inset: var(--actor-inset);

  display: flex;
  align-items: center;
  gap: 8px;
  padding: 16px;

  font-family: inherit;
  font-size: var(--font-size);
  font-weight: 600;
  line-height: 1.14em;
  text-decoration: none;

  background: var(--actor-background, var(--background));
  border-radius: var(--actor-border-radius, 1.7em/50%);
  border: var(--actor-border, var(--border));
  box-shadow: var(--actor-box-shadow, var(--box-shadow));
  color: var(--actor-color, var(--foreground));
  fill: var(--actor-color, var(--foreground));
  cursor: pointer;
  opacity: 1;
  transition: transform 0.2s ease-in-out;
  transform: translate(0, 0) scale(1);
}
.widget__actor[aria-hidden="true"] {
  opacity: 0;
  pointer-events: none;
  visibility: hidden;
  transform: translate(0, 16px) scale(0.98);
}

.widget__actor:hover {
  background: var(--actor-hover-background, var(--background));
  filter: var(--interactive-filter);
}

.widget__actor svg {
  width: 1.14em;
  height: 1.14em;
}

@media (max-width: 600px) {
  .widget__actor span {
    display: none;
  }
}
`),
    e && t.setAttribute("nonce", e),
    t
  );
}
function Me(e, t) {
  return (
    Object.entries(t).forEach(([n, r]) => {
      e.setAttributeNS(null, n, r);
    }),
    e
  );
}
const Zt = 20,
  E_ = "http://www.w3.org/2000/svg";
function v_() {
  const e = (a) => We.document.createElementNS(E_, a),
    t = Me(e("svg"), {
      width: `${Zt}`,
      height: `${Zt}`,
      viewBox: `0 0 ${Zt} ${Zt}`,
      fill: "var(--actor-color, var(--foreground))",
    }),
    n = Me(e("g"), { clipPath: "url(#clip0_57_80)" }),
    r = Me(e("path"), {
      "fill-rule": "evenodd",
      "clip-rule": "evenodd",
      d: "M15.6622 15H12.3997C12.2129 14.9959 12.031 14.9396 11.8747 14.8375L8.04965 12.2H7.49956V19.1C7.4875 19.3348 7.3888 19.5568 7.22256 19.723C7.05632 19.8892 6.83435 19.9879 6.59956 20H2.04956C1.80193 19.9968 1.56535 19.8969 1.39023 19.7218C1.21511 19.5467 1.1153 19.3101 1.11206 19.0625V12.2H0.949652C0.824431 12.2017 0.700142 12.1783 0.584123 12.1311C0.468104 12.084 0.362708 12.014 0.274155 11.9255C0.185602 11.8369 0.115689 11.7315 0.0685419 11.6155C0.0213952 11.4995 -0.00202913 11.3752 -0.00034808 11.25V3.75C-0.00900498 3.62067 0.0092504 3.49095 0.0532651 3.36904C0.0972798 3.24712 0.166097 3.13566 0.255372 3.04168C0.344646 2.94771 0.452437 2.87327 0.571937 2.82307C0.691437 2.77286 0.82005 2.74798 0.949652 2.75H8.04965L11.8747 0.1625C12.031 0.0603649 12.2129 0.00407221 12.3997 0H15.6622C15.9098 0.00323746 16.1464 0.103049 16.3215 0.278167C16.4966 0.453286 16.5964 0.689866 16.5997 0.9375V3.25269C17.3969 3.42959 18.1345 3.83026 18.7211 4.41679C19.5322 5.22788 19.9878 6.32796 19.9878 7.47502C19.9878 8.62209 19.5322 9.72217 18.7211 10.5333C18.1345 11.1198 17.3969 11.5205 16.5997 11.6974V14.0125C16.6047 14.1393 16.5842 14.2659 16.5395 14.3847C16.4948 14.5035 16.4268 14.6121 16.3394 14.7042C16.252 14.7962 16.147 14.8698 16.0307 14.9206C15.9144 14.9714 15.7891 14.9984 15.6622 15ZM1.89695 10.325H1.88715V4.625H8.33715C8.52423 4.62301 8.70666 4.56654 8.86215 4.4625L12.6872 1.875H14.7247V13.125H12.6872L8.86215 10.4875C8.70666 10.3835 8.52423 10.327 8.33715 10.325H2.20217C2.15205 10.3167 2.10102 10.3125 2.04956 10.3125C1.9981 10.3125 1.94708 10.3167 1.89695 10.325ZM2.98706 12.2V18.1625H5.66206V12.2H2.98706ZM16.5997 9.93612V5.01393C16.6536 5.02355 16.7072 5.03495 16.7605 5.04814C17.1202 5.13709 17.4556 5.30487 17.7425 5.53934C18.0293 5.77381 18.2605 6.06912 18.4192 6.40389C18.578 6.73866 18.6603 7.10452 18.6603 7.47502C18.6603 7.84552 18.578 8.21139 18.4192 8.54616C18.2605 8.88093 18.0293 9.17624 17.7425 9.41071C17.4556 9.64518 17.1202 9.81296 16.7605 9.90191C16.7072 9.91509 16.6536 9.9265 16.5997 9.93612Z",
    });
  t.appendChild(n).appendChild(r);
  const s = e("defs"),
    i = Me(e("clipPath"), { id: "clip0_57_80" }),
    o = Me(e("rect"), { width: `${Zt}`, height: `${Zt}`, fill: "white" });
  return (
    i.appendChild(o),
    s.appendChild(i),
    t.appendChild(s).appendChild(i).appendChild(o),
    t
  );
}
function T_({
  triggerLabel: e,
  triggerAriaLabel: t,
  shadow: n,
  styleNonce: r,
}) {
  const s = re.createElement("button");
  if (
    ((s.type = "button"),
    (s.className = "widget__actor"),
    (s.ariaHidden = "false"),
    (s.ariaLabel = t || e || Gd),
    s.appendChild(v_()),
    e)
  ) {
    const o = re.createElement("span");
    (o.appendChild(re.createTextNode(e)), s.appendChild(o));
  }
  const i = b_(r);
  return {
    el: s,
    appendToDom() {
      (n.appendChild(i), n.appendChild(s));
    },
    removeFromDom() {
      (s.remove(), i.remove());
    },
    show() {
      s.ariaHidden = "false";
    },
    hide() {
      s.ariaHidden = "true";
    },
  };
}
const Yd = "rgba(88, 74, 192, 1)",
  w_ = {
    foreground: "#2b2233",
    background: "#ffffff",
    accentForeground: "white",
    accentBackground: Yd,
    successColor: "#268d75",
    errorColor: "#df3338",
    border: "1.5px solid rgba(41, 35, 47, 0.13)",
    boxShadow: "0px 4px 24px 0px rgba(43, 34, 51, 0.12)",
    outline: "1px auto var(--accent-background)",
    interactiveFilter: "brightness(95%)",
  },
  Yc = {
    foreground: "#ebe6ef",
    background: "#29232f",
    accentForeground: "white",
    accentBackground: Yd,
    successColor: "#2da98c",
    errorColor: "#f55459",
    border: "1.5px solid rgba(235, 230, 239, 0.15)",
    boxShadow: "0px 4px 24px 0px rgba(43, 34, 51, 0.12)",
    outline: "1px auto var(--accent-background)",
    interactiveFilter: "brightness(150%)",
  };
function Xc(e) {
  return `
  --foreground: ${e.foreground};
  --background: ${e.background};
  --accent-foreground: ${e.accentForeground};
  --accent-background: ${e.accentBackground};
  --success-color: ${e.successColor};
  --error-color: ${e.errorColor};
  --border: ${e.border};
  --box-shadow: ${e.boxShadow};
  --outline: ${e.outline};
  --interactive-filter: ${e.interactiveFilter};
  `;
}
function I_({ colorScheme: e, themeDark: t, themeLight: n, styleNonce: r }) {
  const s = re.createElement("style");
  return (
    (s.textContent = `
:host {
  --font-family: system-ui, 'Helvetica Neue', Arial, sans-serif;
  --font-size: 14px;
  --z-index: 100000;

  --page-margin: 16px;
  --inset: auto 0 0 auto;
  --actor-inset: var(--inset);

  font-family: var(--font-family);
  font-size: var(--font-size);

  ${e !== "system" ? "color-scheme: only light;" : ""}

  ${Xc(e === "dark" ? { ...Yc, ...t } : { ...w_, ...n })}
}

${
  e === "system"
    ? `
@media (prefers-color-scheme: dark) {
  :host {
    ${Xc({ ...Yc, ...t })}
  }
}`
    : ""
}
}
`),
    r && s.setAttribute("nonce", r),
    s
  );
}
const Xd =
  ({
    lazyLoadIntegration: e,
    getModalIntegration: t,
    getScreenshotIntegration: n,
  }) =>
  ({
    id: s = "sentry-feedback",
    autoInject: i = !0,
    showBranding: o = !0,
    isEmailRequired: a = !1,
    isNameRequired: c = !1,
    showEmail: u = !0,
    showName: d = !0,
    enableScreenshot: l = !0,
    useSentryUser: p = { email: "email", name: "username" },
    tags: f,
    styleNonce: h,
    scriptNonce: m,
    colorScheme: g = "system",
    themeLight: _ = {},
    themeDark: y = {},
    addScreenshotButtonLabel: M = d_,
    cancelButtonLabel: w = Qg,
    confirmButtonLabel: A = t_,
    emailLabel: C = s_,
    emailPlaceholder: E = r_,
    formTitle: I = n_,
    isRequiredLabel: b = l_,
    messageLabel: k = o_,
    messagePlaceholder: O = i_,
    nameLabel: v = c_,
    namePlaceholder: x = a_,
    removeScreenshotButtonLabel: U = f_,
    submitButtonLabel: q = e_,
    successMessageText: K = u_,
    triggerLabel: T = Gd,
    triggerAriaLabel: P = "",
    highlightToolText: R = p_,
    hideToolText: L = h_,
    removeHighlightText: V = m_,
    onFormOpen: Q,
    onFormClose: ge,
    onSubmitSuccess: le,
    onSubmitError: gt,
    onFormSubmitted: Be,
  } = {}) => {
    const Le = {
      id: s,
      autoInject: i,
      showBranding: o,
      isEmailRequired: a,
      isNameRequired: c,
      showEmail: u,
      showName: d,
      enableScreenshot: l,
      useSentryUser: p,
      tags: f,
      styleNonce: h,
      scriptNonce: m,
      colorScheme: g,
      themeDark: y,
      themeLight: _,
      triggerLabel: T,
      triggerAriaLabel: P,
      cancelButtonLabel: w,
      submitButtonLabel: q,
      confirmButtonLabel: A,
      formTitle: I,
      emailLabel: C,
      emailPlaceholder: E,
      messageLabel: k,
      messagePlaceholder: O,
      nameLabel: v,
      namePlaceholder: x,
      successMessageText: K,
      isRequiredLabel: b,
      addScreenshotButtonLabel: M,
      removeScreenshotButtonLabel: U,
      highlightToolText: R,
      hideToolText: L,
      removeHighlightText: V,
      onFormClose: ge,
      onFormOpen: Q,
      onSubmitError: gt,
      onSubmitSuccess: le,
      onFormSubmitted: Be,
    };
    let Re = null,
      _t = [];
    const St = (te) => {
        if (!Re) {
          const de = re.createElement("div");
          ((de.id = String(te.id)),
            re.body.appendChild(de),
            (Re = de.attachShadow({ mode: "open" })),
            Re.appendChild(I_(te)));
        }
        return Re;
      },
      Nn = async (te) => {
        const de = te.enableScreenshot && y_();
        let $e, Se;
        try {
          (($e = (t ? t() : await e("feedbackModalIntegration", m))()), Vc($e));
        } catch {
          throw (
            ns &&
              ot.error(
                "[Feedback] Error when trying to load feedback integrations. Try using `feedbackSyncIntegration` in your `Sentry.init`.",
              ),
            new Error("[Feedback] Missing feedback modal integration!")
          );
        }
        try {
          const Ve = de
            ? n
              ? n()
              : await e("feedbackScreenshotIntegration", m)
            : void 0;
          Ve && ((Se = Ve()), Vc(Se));
        } catch {
          ns &&
            ot.error(
              "[Feedback] Missing feedback screenshot integration. Proceeding without screenshots.",
            );
        }
        const Ee = $e.createDialog({
          options: {
            ...te,
            onFormClose: () => {
              (Ee?.close(), te.onFormClose?.());
            },
            onFormSubmitted: () => {
              (Ee?.close(), te.onFormSubmitted?.());
            },
          },
          screenshotIntegration: Se,
          sendFeedback: Vd,
          shadow: St(te),
        });
        return Ee;
      },
      $r = (te, de = {}) => {
        const $e = Dr(Le, de),
          Se =
            typeof te == "string"
              ? re.querySelector(te)
              : typeof te.addEventListener == "function"
                ? te
                : null;
        if (!Se)
          throw (
            ns && ot.error("[Feedback] Unable to attach to target element"),
            new Error("Unable to attach to target element")
          );
        let Ee = null;
        const Ve = async () => {
          (Ee ||
            (Ee = await Nn({
              ...$e,
              onFormSubmitted: () => {
                (Ee?.removeFromDom(), $e.onFormSubmitted?.());
              },
            })),
            Ee.appendToDom(),
            Ee.open());
        };
        Se.addEventListener("click", Ve);
        const Y = () => {
          ((_t = _t.filter((xe) => xe !== Y)),
            Ee?.removeFromDom(),
            (Ee = null),
            Se.removeEventListener("click", Ve));
        };
        return (_t.push(Y), Y);
      },
      On = (te = {}) => {
        const de = Dr(Le, te),
          $e = St(de),
          Se = T_({
            triggerLabel: de.triggerLabel,
            triggerAriaLabel: de.triggerAriaLabel,
            shadow: $e,
            styleNonce: h,
          });
        return (
          $r(Se.el, {
            ...de,
            onFormOpen() {
              Se.hide();
            },
            onFormClose() {
              Se.show();
            },
            onFormSubmitted() {
              Se.show();
            },
          }),
          Se
        );
      };
    return {
      name: "Feedback",
      setupOnce() {
        !Jg() ||
          !Le.autoInject ||
          (re.readyState === "loading"
            ? re.addEventListener("DOMContentLoaded", () => On().appendToDom())
            : On().appendToDom());
      },
      attachTo: $r,
      createWidget(te = {}) {
        const de = On(Dr(Le, te));
        return (de.appendToDom(), de);
      },
      async createForm(te = {}) {
        return Nn(Dr(Le, te));
      },
      remove() {
        (Re && (Re.parentElement?.remove(), (Re = null)),
          _t.forEach((te) => te()),
          (_t = []));
      },
    };
  };
function k_() {
  return hr()?.getIntegrationByName("Feedback");
}
var ci,
  ie,
  Kd,
  $t,
  Kc,
  Jd,
  _o,
  rr = {},
  ma = [],
  C_ = /acit|ex(?:s|g|n|p|$)|rph|grid|ows|mnc|ntw|ine[ch]|zoo|^ord|itera/i,
  ga = Array.isArray;
function vt(e, t) {
  for (var n in t) e[n] = t[n];
  return e;
}
function Zd(e) {
  var t = e.parentNode;
  t && t.removeChild(e);
}
function j(e, t, n) {
  var r,
    s,
    i,
    o = {};
  for (i in t)
    i == "key" ? (r = t[i]) : i == "ref" ? (s = t[i]) : (o[i] = t[i]);
  if (
    (arguments.length > 2 &&
      (o.children = arguments.length > 3 ? ci.call(arguments, 2) : n),
    typeof e == "function" && e.defaultProps != null)
  )
    for (i in e.defaultProps) o[i] === void 0 && (o[i] = e.defaultProps[i]);
  return rs(e, o, r, s, null);
}
function rs(e, t, n, r, s) {
  var i = {
    type: e,
    props: t,
    key: n,
    ref: r,
    __k: null,
    __: null,
    __b: 0,
    __e: null,
    __d: void 0,
    __c: null,
    constructor: void 0,
    __v: s ?? ++Kd,
    __i: -1,
    __u: 0,
  };
  return (s == null && ie.vnode != null && ie.vnode(i), i);
}
function mr(e) {
  return e.children;
}
function ss(e, t) {
  ((this.props = e), (this.context = t));
}
function pn(e, t) {
  if (t == null) return e.__ ? pn(e.__, e.__i + 1) : null;
  for (var n; t < e.__k.length; t++)
    if ((n = e.__k[t]) != null && n.__e != null) return n.__e;
  return typeof e.type == "function" ? pn(e) : null;
}
function R_(e, t, n) {
  var r,
    s = e.__v,
    i = s.__e,
    o = e.__P;
  if (o)
    return (
      ((r = vt({}, s)).__v = s.__v + 1),
      ie.vnode && ie.vnode(r),
      _a(
        o,
        r,
        s,
        e.__n,
        o.ownerSVGElement !== void 0,
        32 & s.__u ? [i] : null,
        t,
        i ?? pn(s),
        !!(32 & s.__u),
        n,
      ),
      (r.__.__k[r.__i] = r),
      (r.__d = void 0),
      r.__e != i && Qd(r),
      r
    );
}
function Qd(e) {
  var t, n;
  if ((e = e.__) != null && e.__c != null) {
    for (e.__e = e.__c.base = null, t = 0; t < e.__k.length; t++)
      if ((n = e.__k[t]) != null && n.__e != null) {
        e.__e = e.__c.base = n.__e;
        break;
      }
    return Qd(e);
  }
}
function Jc(e) {
  ((!e.__d && (e.__d = !0) && $t.push(e) && !Is.__r++) ||
    Kc !== ie.debounceRendering) &&
    ((Kc = ie.debounceRendering) || Jd)(Is);
}
function Is() {
  var e,
    t,
    n,
    r = [],
    s = [];
  for ($t.sort(_o); (e = $t.shift());)
    e.__d &&
      ((n = $t.length),
      (t = R_(e, r, s) || t),
      n === 0 || $t.length > n
        ? (So(r, t, s), (s.length = r.length = 0), (t = void 0), $t.sort(_o))
        : t && ie.__c && ie.__c(t, ma));
  (t && So(r, t, s), (Is.__r = 0));
}
function ef(e, t, n, r, s, i, o, a, c, u, d) {
  var l,
    p,
    f,
    h,
    m,
    g = (r && r.__k) || ma,
    _ = t.length;
  for (n.__d = c, x_(n, t, g), c = n.__d, l = 0; l < _; l++)
    (f = n.__k[l]) != null &&
      typeof f != "boolean" &&
      typeof f != "function" &&
      ((p = f.__i === -1 ? rr : g[f.__i] || rr),
      (f.__i = l),
      _a(e, f, p, s, i, o, a, c, u, d),
      (h = f.__e),
      f.ref &&
        p.ref != f.ref &&
        (p.ref && Sa(p.ref, null, f), d.push(f.ref, f.__c || h, f)),
      m == null && h != null && (m = h),
      65536 & f.__u || p.__k === f.__k
        ? (c = tf(f, c, e))
        : typeof f.type == "function" && f.__d !== void 0
          ? (c = f.__d)
          : h && (c = h.nextSibling),
      (f.__d = void 0),
      (f.__u &= -196609));
  ((n.__d = c), (n.__e = m));
}
function x_(e, t, n) {
  var r,
    s,
    i,
    o,
    a,
    c = t.length,
    u = n.length,
    d = u,
    l = 0;
  for (e.__k = [], r = 0; r < c; r++)
    (s = e.__k[r] =
      (s = t[r]) == null || typeof s == "boolean" || typeof s == "function"
        ? null
        : typeof s == "string" ||
            typeof s == "number" ||
            typeof s == "bigint" ||
            s.constructor == String
          ? rs(null, s, null, null, s)
          : ga(s)
            ? rs(mr, { children: s }, null, null, null)
            : s.constructor === void 0 && s.__b > 0
              ? rs(s.type, s.props, s.key, s.ref ? s.ref : null, s.__v)
              : s) != null
      ? ((s.__ = e),
        (s.__b = e.__b + 1),
        (a = A_(s, n, (o = r + l), d)),
        (s.__i = a),
        (i = null),
        a !== -1 && (d--, (i = n[a]) && (i.__u |= 131072)),
        i == null || i.__v === null
          ? (a == -1 && l--, typeof s.type != "function" && (s.__u |= 65536))
          : a !== o &&
            (a === o + 1
              ? l++
              : a > o
                ? d > c - o
                  ? (l += a - o)
                  : l--
                : (l = a < o && a == o - 1 ? a - o : 0),
            a !== r + l && (s.__u |= 65536)))
      : (i = n[r]) &&
        i.key == null &&
        i.__e &&
        (i.__e == e.__d && (e.__d = pn(i)), yo(i, i, !1), (n[r] = null), d--);
  if (d)
    for (r = 0; r < u; r++)
      (i = n[r]) != null &&
        (131072 & i.__u) == 0 &&
        (i.__e == e.__d && (e.__d = pn(i)), yo(i, i));
}
function tf(e, t, n) {
  var r, s;
  if (typeof e.type == "function") {
    for (r = e.__k, s = 0; r && s < r.length; s++)
      r[s] && ((r[s].__ = e), (t = tf(r[s], t, n)));
    return t;
  }
  e.__e != t && (n.insertBefore(e.__e, t || null), (t = e.__e));
  do t = t && t.nextSibling;
  while (t != null && t.nodeType === 8);
  return t;
}
function A_(e, t, n, r) {
  var s = e.key,
    i = e.type,
    o = n - 1,
    a = n + 1,
    c = t[n];
  if (c === null || (c && s == c.key && i === c.type)) return n;
  if (r > (c != null && (131072 & c.__u) == 0 ? 1 : 0))
    for (; o >= 0 || a < t.length;) {
      if (o >= 0) {
        if ((c = t[o]) && (131072 & c.__u) == 0 && s == c.key && i === c.type)
          return o;
        o--;
      }
      if (a < t.length) {
        if ((c = t[a]) && (131072 & c.__u) == 0 && s == c.key && i === c.type)
          return a;
        a++;
      }
    }
  return -1;
}
function Zc(e, t, n) {
  t[0] === "-"
    ? e.setProperty(t, n ?? "")
    : (e[t] =
        n == null ? "" : typeof n != "number" || C_.test(t) ? n : n + "px");
}
function Pr(e, t, n, r, s) {
  var i;
  e: if (t === "style")
    if (typeof n == "string") e.style.cssText = n;
    else {
      if ((typeof r == "string" && (e.style.cssText = r = ""), r))
        for (t in r) (n && t in n) || Zc(e.style, t, "");
      if (n) for (t in n) (r && n[t] === r[t]) || Zc(e.style, t, n[t]);
    }
  else if (t[0] === "o" && t[1] === "n")
    ((i = t !== (t = t.replace(/(PointerCapture)$|Capture$/i, "$1"))),
      (t = t.toLowerCase() in e ? t.toLowerCase().slice(2) : t.slice(2)),
      e.l || (e.l = {}),
      (e.l[t + i] = n),
      n
        ? r
          ? (n.u = r.u)
          : ((n.u = Date.now()), e.addEventListener(t, i ? eu : Qc, i))
        : e.removeEventListener(t, i ? eu : Qc, i));
  else {
    if (s) t = t.replace(/xlink(H|:h)/, "h").replace(/sName$/, "s");
    else if (
      t !== "width" &&
      t !== "height" &&
      t !== "href" &&
      t !== "list" &&
      t !== "form" &&
      t !== "tabIndex" &&
      t !== "download" &&
      t !== "rowSpan" &&
      t !== "colSpan" &&
      t !== "role" &&
      t in e
    )
      try {
        e[t] = n ?? "";
        break e;
      } catch {}
    typeof n == "function" ||
      (n == null || (n === !1 && t[4] !== "-")
        ? e.removeAttribute(t)
        : e.setAttribute(t, n));
  }
}
function Qc(e) {
  if (this.l) {
    var t = this.l[e.type + !1];
    if (e.t) {
      if (e.t <= t.u) return;
    } else e.t = Date.now();
    return t(ie.event ? ie.event(e) : e);
  }
}
function eu(e) {
  if (this.l) return this.l[e.type + !0](ie.event ? ie.event(e) : e);
}
function _a(e, t, n, r, s, i, o, a, c, u) {
  var d,
    l,
    p,
    f,
    h,
    m,
    g,
    _,
    y,
    M,
    w,
    A,
    C,
    E,
    I,
    b = t.type;
  if (t.constructor !== void 0) return null;
  (128 & n.__u && ((c = !!(32 & n.__u)), (i = [(a = t.__e = n.__e)])),
    (d = ie.__b) && d(t));
  e: if (typeof b == "function")
    try {
      if (
        ((_ = t.props),
        (y = (d = b.contextType) && r[d.__c]),
        (M = d ? (y ? y.props.value : d.__) : r),
        n.__c
          ? (g = (l = t.__c = n.__c).__ = l.__E)
          : ("prototype" in b && b.prototype.render
              ? (t.__c = l = new b(_, M))
              : ((t.__c = l = new ss(_, M)),
                (l.constructor = b),
                (l.render = N_)),
            y && y.sub(l),
            (l.props = _),
            l.state || (l.state = {}),
            (l.context = M),
            (l.__n = r),
            (p = l.__d = !0),
            (l.__h = []),
            (l._sb = [])),
        l.__s == null && (l.__s = l.state),
        b.getDerivedStateFromProps != null &&
          (l.__s == l.state && (l.__s = vt({}, l.__s)),
          vt(l.__s, b.getDerivedStateFromProps(_, l.__s))),
        (f = l.props),
        (h = l.state),
        (l.__v = t),
        p)
      )
        (b.getDerivedStateFromProps == null &&
          l.componentWillMount != null &&
          l.componentWillMount(),
          l.componentDidMount != null && l.__h.push(l.componentDidMount));
      else {
        if (
          (b.getDerivedStateFromProps == null &&
            _ !== f &&
            l.componentWillReceiveProps != null &&
            l.componentWillReceiveProps(_, M),
          !l.__e &&
            ((l.shouldComponentUpdate != null &&
              l.shouldComponentUpdate(_, l.__s, M) === !1) ||
              t.__v === n.__v))
        ) {
          for (
            t.__v !== n.__v && ((l.props = _), (l.state = l.__s), (l.__d = !1)),
              t.__e = n.__e,
              t.__k = n.__k,
              t.__k.forEach(function (k) {
                k && (k.__ = t);
              }),
              w = 0;
            w < l._sb.length;
            w++
          )
            l.__h.push(l._sb[w]);
          ((l._sb = []), l.__h.length && o.push(l));
          break e;
        }
        (l.componentWillUpdate != null && l.componentWillUpdate(_, l.__s, M),
          l.componentDidUpdate != null &&
            l.__h.push(function () {
              l.componentDidUpdate(f, h, m);
            }));
      }
      if (
        ((l.context = M),
        (l.props = _),
        (l.__P = e),
        (l.__e = !1),
        (A = ie.__r),
        (C = 0),
        "prototype" in b && b.prototype.render)
      ) {
        for (
          l.state = l.__s,
            l.__d = !1,
            A && A(t),
            d = l.render(l.props, l.state, l.context),
            E = 0;
          E < l._sb.length;
          E++
        )
          l.__h.push(l._sb[E]);
        l._sb = [];
      } else
        do
          ((l.__d = !1),
            A && A(t),
            (d = l.render(l.props, l.state, l.context)),
            (l.state = l.__s));
        while (l.__d && ++C < 25);
      ((l.state = l.__s),
        l.getChildContext != null && (r = vt(vt({}, r), l.getChildContext())),
        p ||
          l.getSnapshotBeforeUpdate == null ||
          (m = l.getSnapshotBeforeUpdate(f, h)),
        ef(
          e,
          ga(
            (I =
              d != null && d.type === mr && d.key == null
                ? d.props.children
                : d),
          )
            ? I
            : [I],
          t,
          n,
          r,
          s,
          i,
          o,
          a,
          c,
          u,
        ),
        (l.base = t.__e),
        (t.__u &= -161),
        l.__h.length && o.push(l),
        g && (l.__E = l.__ = null));
    } catch (k) {
      ((t.__v = null),
        c || i != null
          ? ((t.__e = a), (t.__u |= c ? 160 : 32), (i[i.indexOf(a)] = null))
          : ((t.__e = n.__e), (t.__k = n.__k)),
        ie.__e(k, t, n));
    }
  else
    i == null && t.__v === n.__v
      ? ((t.__k = n.__k), (t.__e = n.__e))
      : (t.__e = M_(n.__e, t, n, r, s, i, o, c, u));
  (d = ie.diffed) && d(t);
}
function So(e, t, n) {
  for (var r = 0; r < n.length; r++) Sa(n[r], n[++r], n[++r]);
  (ie.__c && ie.__c(t, e),
    e.some(function (s) {
      try {
        ((e = s.__h),
          (s.__h = []),
          e.some(function (i) {
            i.call(s);
          }));
      } catch (i) {
        ie.__e(i, s.__v);
      }
    }));
}
function M_(e, t, n, r, s, i, o, a, c) {
  var u,
    d,
    l,
    p,
    f,
    h,
    m,
    g = n.props,
    _ = t.props,
    y = t.type;
  if ((y === "svg" && (s = !0), i != null)) {
    for (u = 0; u < i.length; u++)
      if (
        (f = i[u]) &&
        "setAttribute" in f == !!y &&
        (y ? f.localName === y : f.nodeType === 3)
      ) {
        ((e = f), (i[u] = null));
        break;
      }
  }
  if (e == null) {
    if (y === null) return document.createTextNode(_);
    ((e = s
      ? document.createElementNS("http://www.w3.org/2000/svg", y)
      : document.createElement(y, _.is && _)),
      (i = null),
      (a = !1));
  }
  if (y === null) g === _ || (a && e.data === _) || (e.data = _);
  else {
    if (
      ((i = i && ci.call(e.childNodes)), (g = n.props || rr), !a && i != null)
    )
      for (g = {}, u = 0; u < e.attributes.length; u++)
        g[(f = e.attributes[u]).name] = f.value;
    for (u in g)
      ((f = g[u]),
        u == "children" ||
          (u == "dangerouslySetInnerHTML"
            ? (l = f)
            : u === "key" || u in _ || Pr(e, u, null, f, s)));
    for (u in _)
      ((f = _[u]),
        u == "children"
          ? (p = f)
          : u == "dangerouslySetInnerHTML"
            ? (d = f)
            : u == "value"
              ? (h = f)
              : u == "checked"
                ? (m = f)
                : u === "key" ||
                  (a && typeof f != "function") ||
                  g[u] === f ||
                  Pr(e, u, f, g[u], s));
    if (d)
      (a ||
        (l && (d.__html === l.__html || d.__html === e.innerHTML)) ||
        (e.innerHTML = d.__html),
        (t.__k = []));
    else if (
      (l && (e.innerHTML = ""),
      ef(
        e,
        ga(p) ? p : [p],
        t,
        n,
        r,
        s && y !== "foreignObject",
        i,
        o,
        i ? i[0] : n.__k && pn(n, 0),
        a,
        c,
      ),
      i != null)
    )
      for (u = i.length; u--;) i[u] != null && Zd(i[u]);
    a ||
      ((u = "value"),
      h !== void 0 &&
        (h !== e[u] ||
          (y === "progress" && !h) ||
          (y === "option" && h !== g[u])) &&
        Pr(e, u, h, g[u], !1),
      (u = "checked"),
      m !== void 0 && m !== e[u] && Pr(e, u, m, g[u], !1));
  }
  return e;
}
function Sa(e, t, n) {
  try {
    typeof e == "function" ? e(t) : (e.current = t);
  } catch (r) {
    ie.__e(r, n);
  }
}
function yo(e, t, n) {
  var r, s;
  if (
    (ie.unmount && ie.unmount(e),
    (r = e.ref) && ((r.current && r.current !== e.__e) || Sa(r, null, t)),
    (r = e.__c) != null)
  ) {
    if (r.componentWillUnmount)
      try {
        r.componentWillUnmount();
      } catch (i) {
        ie.__e(i, t);
      }
    ((r.base = r.__P = null), (e.__c = void 0));
  }
  if ((r = e.__k))
    for (s = 0; s < r.length; s++)
      r[s] && yo(r[s], t, n || typeof e.type != "function");
  (n || e.__e == null || Zd(e.__e), (e.__ = e.__e = e.__d = void 0));
}
function N_(e, t, n) {
  return this.constructor(e, n);
}
function O_(e, t, n) {
  var r, s, i, o;
  (ie.__ && ie.__(e, t),
    (s = (r = !1) ? null : t.__k),
    (i = []),
    (o = []),
    _a(
      t,
      (e = t.__k = j(mr, null, [e])),
      s || rr,
      rr,
      t.ownerSVGElement !== void 0,
      s ? null : t.firstChild ? ci.call(t.childNodes) : null,
      i,
      s ? s.__e : t.firstChild,
      r,
      o,
    ),
    (e.__d = void 0),
    So(i, e, o));
}
((ci = ma.slice),
  (ie = {
    __e: function (e, t, n, r) {
      for (var s, i, o; (t = t.__);)
        if ((s = t.__c) && !s.__)
          try {
            if (
              ((i = s.constructor) &&
                i.getDerivedStateFromError != null &&
                (s.setState(i.getDerivedStateFromError(e)), (o = s.__d)),
              s.componentDidCatch != null &&
                (s.componentDidCatch(e, r || {}), (o = s.__d)),
              o)
            )
              return (s.__E = s);
          } catch (a) {
            e = a;
          }
      throw e;
    },
  }),
  (Kd = 0),
  (ss.prototype.setState = function (e, t) {
    var n;
    ((n =
      this.__s != null && this.__s !== this.state
        ? this.__s
        : (this.__s = vt({}, this.state))),
      typeof e == "function" && (e = e(vt({}, n), this.props)),
      e && vt(n, e),
      e != null && this.__v && (t && this._sb.push(t), Jc(this)));
  }),
  (ss.prototype.forceUpdate = function (e) {
    this.__v && ((this.__e = !0), e && this.__h.push(e), Jc(this));
  }),
  (ss.prototype.render = mr),
  ($t = []),
  (Jd =
    typeof Promise == "function"
      ? Promise.prototype.then.bind(Promise.resolve())
      : setTimeout),
  (_o = function (e, t) {
    return e.__v.__b - t.__v.__b;
  }),
  (Is.__r = 0));
var ft,
  se,
  Oi,
  tu,
  hn = 0,
  nf = [],
  is = [],
  fe = ie,
  nu = fe.__b,
  ru = fe.__r,
  su = fe.diffed,
  iu = fe.__c,
  ou = fe.unmount,
  au = fe.__;
function Kt(e, t) {
  (fe.__h && fe.__h(se, e, hn || t), (hn = 0));
  var n = se.__H || (se.__H = { __: [], __h: [] });
  return (e >= n.__.length && n.__.push({ __V: is }), n.__[e]);
}
function Dt(e) {
  return ((hn = 1), rf(of, e));
}
function rf(e, t, n) {
  var r = Kt(ft++, 2);
  if (
    ((r.t = e),
    !r.__c &&
      ((r.__ = [
        n ? n(t) : of(void 0, t),
        function (a) {
          var c = r.__N ? r.__N[0] : r.__[0],
            u = r.t(c, a);
          c !== u && ((r.__N = [u, r.__[1]]), r.__c.setState({}));
        },
      ]),
      (r.__c = se),
      !se.u))
  ) {
    var s = function (a, c, u) {
      if (!r.__c.__H) return !0;
      var d = r.__c.__H.__.filter(function (p) {
        return !!p.__c;
      });
      if (
        d.every(function (p) {
          return !p.__N;
        })
      )
        return !i || i.call(this, a, c, u);
      var l = !1;
      return (
        d.forEach(function (p) {
          if (p.__N) {
            var f = p.__[0];
            ((p.__ = p.__N), (p.__N = void 0), f !== p.__[0] && (l = !0));
          }
        }),
        !(!l && r.__c.props === a) && (!i || i.call(this, a, c, u))
      );
    };
    se.u = !0;
    var i = se.shouldComponentUpdate,
      o = se.componentWillUpdate;
    ((se.componentWillUpdate = function (a, c, u) {
      if (this.__e) {
        var d = i;
        ((i = void 0), s(a, c, u), (i = d));
      }
      o && o.call(this, a, c, u);
    }),
      (se.shouldComponentUpdate = s));
  }
  return r.__N || r.__;
}
function L_(e, t) {
  var n = Kt(ft++, 3);
  !fe.__s && ya(n.__H, t) && ((n.__ = e), (n.i = t), se.__H.__h.push(n));
}
function sf(e, t) {
  var n = Kt(ft++, 4);
  !fe.__s && ya(n.__H, t) && ((n.__ = e), (n.i = t), se.__h.push(n));
}
function $_(e) {
  return (
    (hn = 5),
    gr(function () {
      return { current: e };
    }, [])
  );
}
function D_(e, t, n) {
  ((hn = 6),
    sf(
      function () {
        return typeof e == "function"
          ? (e(t()),
            function () {
              return e(null);
            })
          : e
            ? ((e.current = t()),
              function () {
                return (e.current = null);
              })
            : void 0;
      },
      n == null ? n : n.concat(e),
    ));
}
function gr(e, t) {
  var n = Kt(ft++, 7);
  return ya(n.__H, t) ? ((n.__V = e()), (n.i = t), (n.__h = e), n.__V) : n.__;
}
function un(e, t) {
  return (
    (hn = 8),
    gr(function () {
      return e;
    }, t)
  );
}
function P_(e) {
  var t = se.context[e.__c],
    n = Kt(ft++, 9);
  return (
    (n.c = e),
    t ? (n.__ == null && ((n.__ = !0), t.sub(se)), t.props.value) : e.__
  );
}
function F_(e, t) {
  fe.useDebugValue && fe.useDebugValue(t ? t(e) : e);
}
function B_(e) {
  var t = Kt(ft++, 10),
    n = Dt();
  return (
    (t.__ = e),
    se.componentDidCatch ||
      (se.componentDidCatch = function (r, s) {
        (t.__ && t.__(r, s), n[1](r));
      }),
    [
      n[0],
      function () {
        n[1](void 0);
      },
    ]
  );
}
function U_() {
  var e = Kt(ft++, 11);
  if (!e.__) {
    for (var t = se.__v; t !== null && !t.__m && t.__ !== null;) t = t.__;
    var n = t.__m || (t.__m = [0, 0]);
    e.__ = "P" + n[0] + "-" + n[1]++;
  }
  return e.__;
}
function H_() {
  for (var e; (e = nf.shift());)
    if (e.__P && e.__H)
      try {
        (e.__H.__h.forEach(os), e.__H.__h.forEach(bo), (e.__H.__h = []));
      } catch (t) {
        ((e.__H.__h = []), fe.__e(t, e.__v));
      }
}
((fe.__b = function (e) {
  ((se = null), nu && nu(e));
}),
  (fe.__ = function (e, t) {
    (t.__k && t.__k.__m && (e.__m = t.__k.__m), au && au(e, t));
  }),
  (fe.__r = function (e) {
    (ru && ru(e), (ft = 0));
    var t = (se = e.__c).__H;
    (t &&
      (Oi === se
        ? ((t.__h = []),
          (se.__h = []),
          t.__.forEach(function (n) {
            (n.__N && (n.__ = n.__N), (n.__V = is), (n.__N = n.i = void 0));
          }))
        : (t.__h.forEach(os), t.__h.forEach(bo), (t.__h = []), (ft = 0))),
      (Oi = se));
  }),
  (fe.diffed = function (e) {
    su && su(e);
    var t = e.__c;
    (t &&
      t.__H &&
      (t.__H.__h.length &&
        ((nf.push(t) !== 1 && tu === fe.requestAnimationFrame) ||
          ((tu = fe.requestAnimationFrame) || W_)(H_)),
      t.__H.__.forEach(function (n) {
        (n.i && (n.__H = n.i),
          n.__V !== is && (n.__ = n.__V),
          (n.i = void 0),
          (n.__V = is));
      })),
      (Oi = se = null));
  }),
  (fe.__c = function (e, t) {
    (t.some(function (n) {
      try {
        (n.__h.forEach(os),
          (n.__h = n.__h.filter(function (r) {
            return !r.__ || bo(r);
          })));
      } catch (r) {
        (t.some(function (s) {
          s.__h && (s.__h = []);
        }),
          (t = []),
          fe.__e(r, n.__v));
      }
    }),
      iu && iu(e, t));
  }),
  (fe.unmount = function (e) {
    ou && ou(e);
    var t,
      n = e.__c;
    n &&
      n.__H &&
      (n.__H.__.forEach(function (r) {
        try {
          os(r);
        } catch (s) {
          t = s;
        }
      }),
      (n.__H = void 0),
      t && fe.__e(t, n.__v));
  }));
var cu = typeof requestAnimationFrame == "function";
function W_(e) {
  var t,
    n = function () {
      (clearTimeout(r), cu && cancelAnimationFrame(t), setTimeout(e));
    },
    r = setTimeout(n, 100);
  cu && (t = requestAnimationFrame(n));
}
function os(e) {
  var t = se,
    n = e.__c;
  (typeof n == "function" && ((e.__c = void 0), n()), (se = t));
}
function bo(e) {
  var t = se;
  ((e.__c = e.__()), (se = t));
}
function ya(e, t) {
  return (
    !e ||
    e.length !== t.length ||
    t.some(function (n, r) {
      return n !== e[r];
    })
  );
}
function of(e, t) {
  return typeof t == "function" ? t(e) : t;
}
const z_ = Object.defineProperty(
    {
      __proto__: null,
      useCallback: un,
      useContext: P_,
      useDebugValue: F_,
      useEffect: L_,
      useErrorBoundary: B_,
      useId: U_,
      useImperativeHandle: D_,
      useLayoutEffect: sf,
      useMemo: gr,
      useReducer: rf,
      useRef: $_,
      useState: Dt,
    },
    Symbol.toStringTag,
    { value: "Module" },
  ),
  j_ = "http://www.w3.org/2000/svg";
function q_() {
  const e = (r) => re.createElementNS(j_, r),
    t = Me(e("svg"), {
      width: "32",
      height: "30",
      viewBox: "0 0 72 66",
      fill: "inherit",
    }),
    n = Me(e("path"), {
      transform: "translate(11, 11)",
      d: "M29,2.26a4.67,4.67,0,0,0-8,0L14.42,13.53A32.21,32.21,0,0,1,32.17,40.19H27.55A27.68,27.68,0,0,0,12.09,17.47L6,28a15.92,15.92,0,0,1,9.23,12.17H4.62A.76.76,0,0,1,4,39.06l2.94-5a10.74,10.74,0,0,0-3.36-1.9l-2.91,5a4.54,4.54,0,0,0,1.69,6.24A4.66,4.66,0,0,0,4.62,44H19.15a19.4,19.4,0,0,0-8-17.31l2.31-4A23.87,23.87,0,0,1,23.76,44H36.07a35.88,35.88,0,0,0-16.41-31.8l4.67-8a.77.77,0,0,1,1.05-.27c.53.29,20.29,34.77,20.66,35.17a.76.76,0,0,1-.68,1.13H40.6q.09,1.91,0,3.81h4.78A4.59,4.59,0,0,0,50,39.43a4.49,4.49,0,0,0-.62-2.28Z",
    });
  return (t.appendChild(n), t);
}
function G_({ options: e }) {
  const t = gr(() => ({ __html: q_().outerHTML }), []);
  return j(
    "h2",
    { class: "dialog__header" },
    j("span", { class: "dialog__title" }, e.formTitle),
    e.showBranding
      ? j("a", {
          class: "brand-link",
          target: "_blank",
          href: "https://sentry.io/welcome/",
          title: "Powered by Sentry",
          rel: "noopener noreferrer",
          dangerouslySetInnerHTML: t,
        })
      : null,
  );
}
function V_(e, t) {
  const n = [];
  return (
    t.isNameRequired && !e.name && n.push(t.nameLabel),
    t.isEmailRequired && !e.email && n.push(t.emailLabel),
    e.message || n.push(t.messageLabel),
    n
  );
}
function Li(e, t) {
  const n = e.get(t);
  return typeof n == "string" ? n.trim() : "";
}
function Y_({
  options: e,
  defaultEmail: t,
  defaultName: n,
  onFormClose: r,
  onSubmit: s,
  onSubmitSuccess: i,
  onSubmitError: o,
  showEmail: a,
  showName: c,
  screenshotInput: u,
}) {
  const {
      tags: d,
      addScreenshotButtonLabel: l,
      removeScreenshotButtonLabel: p,
      cancelButtonLabel: f,
      emailLabel: h,
      emailPlaceholder: m,
      isEmailRequired: g,
      isNameRequired: _,
      messageLabel: y,
      messagePlaceholder: M,
      nameLabel: w,
      namePlaceholder: A,
      submitButtonLabel: C,
      isRequiredLabel: E,
    } = e,
    [I, b] = Dt(!1),
    [k, O] = Dt(null),
    [v, x] = Dt(!1),
    U = u?.input,
    [q, K] = Dt(null),
    T = un((L) => {
      (K(L), x(!1));
    }, []),
    P = un(
      (L) => {
        const V = V_(L, {
          emailLabel: h,
          isEmailRequired: g,
          isNameRequired: _,
          messageLabel: y,
          nameLabel: w,
        });
        return (
          V.length > 0
            ? O(
                `Please enter in the following required fields: ${V.join(", ")}`,
              )
            : O(null),
          V.length === 0
        );
      },
      [h, g, _, y, w],
    ),
    R = un(
      async (L) => {
        b(!0);
        try {
          if ((L.preventDefault(), !(L.target instanceof HTMLFormElement)))
            return;
          const V = new FormData(L.target),
            Q = await (u && v ? u.value() : void 0),
            ge = {
              name: Li(V, "name"),
              email: Li(V, "email"),
              message: Li(V, "message"),
              attachments: Q ? [Q] : void 0,
            };
          if (!P(ge)) return;
          try {
            const le = await s(
              {
                name: ge.name,
                email: ge.email,
                message: ge.message,
                source: g_,
                tags: d,
              },
              { attachments: ge.attachments },
            );
            i(ge, le);
          } catch (le) {
            (ns && ot.error(le), O(le), o(le));
          }
        } finally {
          b(!1);
        }
      },
      [u && v, i, o],
    );
  return j(
    "form",
    { class: "form", onSubmit: R },
    U && v ? j(U, { onError: T }) : null,
    j(
      "fieldset",
      { class: "form__right", "data-sentry-feedback": !0, disabled: I },
      j(
        "div",
        { class: "form__top" },
        k ? j("div", { class: "form__error-container" }, k) : null,
        c
          ? j(
              "label",
              { for: "name", class: "form__label" },
              j($i, { label: w, isRequiredLabel: E, isRequired: _ }),
              j("input", {
                class: "form__input",
                defaultValue: n,
                id: "name",
                name: "name",
                placeholder: A,
                required: _,
                type: "text",
              }),
            )
          : j("input", {
              "aria-hidden": !0,
              value: n,
              name: "name",
              type: "hidden",
            }),
        a
          ? j(
              "label",
              { for: "email", class: "form__label" },
              j($i, { label: h, isRequiredLabel: E, isRequired: g }),
              j("input", {
                class: "form__input",
                defaultValue: t,
                id: "email",
                name: "email",
                placeholder: m,
                required: g,
                type: "email",
              }),
            )
          : j("input", {
              "aria-hidden": !0,
              value: t,
              name: "email",
              type: "hidden",
            }),
        j(
          "label",
          { for: "message", class: "form__label" },
          j($i, { label: y, isRequiredLabel: E, isRequired: !0 }),
          j("textarea", {
            autoFocus: !0,
            class: "form__input form__input--textarea",
            id: "message",
            name: "message",
            placeholder: M,
            required: !0,
            rows: 5,
          }),
        ),
        U
          ? j(
              "label",
              { for: "screenshot", class: "form__label" },
              j(
                "button",
                {
                  class: "btn btn--default",
                  disabled: I,
                  type: "button",
                  onClick: () => {
                    (K(null), x((L) => !L));
                  },
                },
                v ? p : l,
              ),
              q
                ? j("div", { class: "form__error-container" }, q.message)
                : null,
            )
          : null,
      ),
      j(
        "div",
        { class: "btn-group" },
        j(
          "button",
          { class: "btn btn--primary", disabled: I, type: "submit" },
          C,
        ),
        j(
          "button",
          {
            class: "btn btn--default",
            disabled: I,
            type: "button",
            onClick: r,
          },
          f,
        ),
      ),
    ),
  );
}
function $i({ label: e, isRequired: t, isRequiredLabel: n }) {
  return j(
    "span",
    { class: "form__label__text" },
    e,
    t && j("span", { class: "form__label__text--required" }, n),
  );
}
const Fr = 16,
  uu = 17,
  X_ = "http://www.w3.org/2000/svg";
function K_() {
  const e = (c) => We.document.createElementNS(X_, c),
    t = Me(e("svg"), {
      width: `${Fr}`,
      height: `${uu}`,
      viewBox: `0 0 ${Fr} ${uu}`,
      fill: "inherit",
    }),
    n = Me(e("g"), { clipPath: "url(#clip0_57_156)" }),
    r = Me(e("path"), {
      "fill-rule": "evenodd",
      "clip-rule": "evenodd",
      d: "M3.55544 15.1518C4.87103 16.0308 6.41775 16.5 8 16.5C10.1217 16.5 12.1566 15.6571 13.6569 14.1569C15.1571 12.6566 16 10.6217 16 8.5C16 6.91775 15.5308 5.37103 14.6518 4.05544C13.7727 2.73985 12.5233 1.71447 11.0615 1.10897C9.59966 0.503466 7.99113 0.34504 6.43928 0.653721C4.88743 0.962403 3.46197 1.72433 2.34315 2.84315C1.22433 3.96197 0.462403 5.38743 0.153721 6.93928C-0.15496 8.49113 0.00346625 10.0997 0.608967 11.5615C1.21447 13.0233 2.23985 14.2727 3.55544 15.1518ZM4.40546 3.1204C5.46945 2.40946 6.72036 2.03 8 2.03C9.71595 2.03 11.3616 2.71166 12.575 3.92502C13.7883 5.13838 14.47 6.78405 14.47 8.5C14.47 9.77965 14.0905 11.0306 13.3796 12.0945C12.6687 13.1585 11.6582 13.9878 10.476 14.4775C9.29373 14.9672 7.99283 15.0953 6.73777 14.8457C5.48271 14.596 4.32987 13.9798 3.42502 13.075C2.52018 12.1701 1.90397 11.0173 1.65432 9.76224C1.40468 8.50718 1.5328 7.20628 2.0225 6.02404C2.5122 4.8418 3.34148 3.83133 4.40546 3.1204Z",
    }),
    s = Me(e("path"), {
      d: "M6.68775 12.4297C6.78586 12.4745 6.89218 12.4984 7 12.5C7.11275 12.4955 7.22315 12.4664 7.32337 12.4145C7.4236 12.3627 7.51121 12.2894 7.58 12.2L12 5.63999C12.0848 5.47724 12.1071 5.28902 12.0625 5.11098C12.0178 4.93294 11.9095 4.77744 11.7579 4.67392C11.6064 4.57041 11.4221 4.52608 11.24 4.54931C11.0579 4.57254 10.8907 4.66173 10.77 4.79999L6.88 10.57L5.13 8.56999C5.06508 8.49566 4.98613 8.43488 4.89768 8.39111C4.80922 8.34735 4.713 8.32148 4.61453 8.31498C4.51605 8.30847 4.41727 8.32147 4.32382 8.35322C4.23038 8.38497 4.14413 8.43484 4.07 8.49999C3.92511 8.63217 3.83692 8.81523 3.82387 9.01092C3.81083 9.2066 3.87393 9.39976 4 9.54999L6.43 12.24C6.50187 12.3204 6.58964 12.385 6.68775 12.4297Z",
    });
  t.appendChild(n).append(s, r);
  const i = e("defs"),
    o = Me(e("clipPath"), { id: "clip0_57_156" }),
    a = Me(e("rect"), {
      width: `${Fr}`,
      height: `${Fr}`,
      fill: "white",
      transform: "translate(0 0.5)",
    });
  return (
    o.appendChild(a),
    i.appendChild(o),
    t.appendChild(i).appendChild(o).appendChild(a),
    t
  );
}
function J_({ open: e, onFormSubmitted: t, ...n }) {
  const r = n.options,
    s = gr(() => ({ __html: K_().outerHTML }), []),
    [i, o] = Dt(null),
    a = un(() => {
      (i && (clearTimeout(i), o(null)), t());
    }, [i]),
    c = un(
      (u, d) => {
        (n.onSubmitSuccess(u, d),
          o(
            setTimeout(() => {
              (t(), o(null));
            }, S_),
          ));
      },
      [t],
    );
  return j(
    mr,
    null,
    i
      ? j(
          "div",
          { class: "success__position", onClick: a },
          j(
            "div",
            { class: "success__content" },
            r.successMessageText,
            j("span", { class: "success__icon", dangerouslySetInnerHTML: s }),
          ),
        )
      : j(
          "dialog",
          { class: "dialog", onClick: r.onFormClose, open: e },
          j(
            "div",
            { class: "dialog__position" },
            j(
              "div",
              {
                class: "dialog__content",
                onClick: (u) => {
                  u.stopPropagation();
                },
              },
              j(G_, { options: r }),
              j(Y_, { ...n, onSubmitSuccess: c }),
            ),
          ),
        ),
  );
}
const Z_ = `
.dialog {
  position: fixed;
  z-index: var(--z-index);
  margin: 0;
  inset: 0;

  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0;
  height: 100vh;
  width: 100vw;

  color: var(--dialog-color, var(--foreground));
  fill: var(--dialog-color, var(--foreground));
  line-height: 1.75em;

  background-color: rgba(0, 0, 0, 0.05);
  border: none;
  inset: 0;
  opacity: 1;
  transition: opacity 0.2s ease-in-out;
}

.dialog__position {
  position: fixed;
  z-index: var(--z-index);
  inset: var(--dialog-inset);
  padding: var(--page-margin);
  display: flex;
  max-height: calc(100vh - (2 * var(--page-margin)));
}
@media (max-width: 600px) {
  .dialog__position {
    inset: var(--page-margin);
    padding: 0;
  }
}

.dialog__position:has(.editor) {
  inset: var(--page-margin);
  padding: 0;
}

.dialog:not([open]) {
  opacity: 0;
  pointer-events: none;
  visibility: hidden;
}
.dialog:not([open]) .dialog__content {
  transform: translate(0, -16px) scale(0.98);
}

.dialog__content {
  display: flex;
  flex-direction: column;
  gap: 16px;
  padding: var(--dialog-padding, 24px);
  max-width: 100%;
  width: 100%;
  max-height: 100%;
  overflow: auto;

  background: var(--dialog-background, var(--background));
  border-radius: var(--dialog-border-radius, 20px);
  border: var(--dialog-border, var(--border));
  box-shadow: var(--dialog-box-shadow, var(--box-shadow));
  transform: translate(0, 0) scale(1);
  transition: transform 0.2s ease-in-out;
}

`,
  Q_ = `
.dialog__header {
  display: flex;
  gap: 4px;
  justify-content: space-between;
  font-weight: var(--dialog-header-weight, 600);
  margin: 0;
}
.dialog__title {
  align-self: center;
  width: var(--form-width, 272px);
}

@media (max-width: 600px) {
  .dialog__title {
    width: auto;
  }
}

.dialog__position:has(.editor) .dialog__title {
  width: auto;
}


.brand-link {
  display: inline-flex;
}
.brand-link:focus-visible {
  outline: var(--outline);
}
`,
  eS = `
.form {
  display: flex;
  overflow: auto;
  flex-direction: row;
  gap: 16px;
  flex: 1 0;
}

.form fieldset {
  border: none;
  margin: 0;
  padding: 0;
}

.form__right {
  flex: 0 0 auto;
  display: flex;
  overflow: auto;
  flex-direction: column;
  justify-content: space-between;
  gap: 20px;
  width: var(--form-width, 100%);
}

.dialog__position:has(.editor) .form__right {
  width: var(--form-width, 272px);
}

.form__top {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.form__error-container {
  color: var(--error-color);
  fill: var(--error-color);
}

.form__label {
  display: flex;
  flex-direction: column;
  gap: 4px;
  margin: 0px;
}

.form__label__text {
  display: flex;
  gap: 4px;
  align-items: center;
}

.form__label__text--required {
  font-size: 0.85em;
}

.form__input {
  font-family: inherit;
  line-height: inherit;
  background: transparent;
  box-sizing: border-box;
  border: var(--input-border, var(--border));
  border-radius: var(--input-border-radius, 6px);
  color: var(--input-color, inherit);
  fill: var(--input-color, inherit);
  font-size: var(--input-font-size, inherit);
  font-weight: var(--input-font-weight, 500);
  padding: 6px 12px;
}

.form__input::placeholder {
  opacity: 0.65;
  color: var(--input-placeholder-color, inherit);
  filter: var(--interactive-filter);
}

.form__input:focus-visible {
  outline: var(--input-focus-outline, var(--outline));
}

.form__input--textarea {
  font-family: inherit;
  resize: vertical;
}

.error {
  color: var(--error-color);
  fill: var(--error-color);
}
`,
  tS = `
.btn-group {
  display: grid;
  gap: 8px;
}

.btn {
  line-height: inherit;
  border: var(--button-border, var(--border));
  border-radius: var(--button-border-radius, 6px);
  cursor: pointer;
  font-family: inherit;
  font-size: var(--button-font-size, inherit);
  font-weight: var(--button-font-weight, 600);
  padding: var(--button-padding, 6px 16px);
}
.btn[disabled] {
  opacity: 0.6;
  pointer-events: none;
}

.btn--primary {
  color: var(--button-primary-color, var(--accent-foreground));
  fill: var(--button-primary-color, var(--accent-foreground));
  background: var(--button-primary-background, var(--accent-background));
  border: var(--button-primary-border, var(--border));
  border-radius: var(--button-primary-border-radius, 6px);
  font-weight: var(--button-primary-font-weight, 500);
}
.btn--primary:hover {
  color: var(--button-primary-hover-color, var(--accent-foreground));
  fill: var(--button-primary-hover-color, var(--accent-foreground));
  background: var(--button-primary-hover-background, var(--accent-background));
  filter: var(--interactive-filter);
}
.btn--primary:focus-visible {
  background: var(--button-primary-hover-background, var(--accent-background));
  filter: var(--interactive-filter);
  outline: var(--button-primary-focus-outline, var(--outline));
}

.btn--default {
  color: var(--button-color, var(--foreground));
  fill: var(--button-color, var(--foreground));
  background: var(--button-background, var(--background));
  border: var(--button-border, var(--border));
  border-radius: var(--button-border-radius, 6px);
  font-weight: var(--button-font-weight, 500);
}
.btn--default:hover {
  color: var(--button-color, var(--foreground));
  fill: var(--button-color, var(--foreground));
  background: var(--button-hover-background, var(--background));
  filter: var(--interactive-filter);
}
.btn--default:focus-visible {
  background: var(--button-hover-background, var(--background));
  filter: var(--interactive-filter);
  outline: var(--button-focus-outline, var(--outline));
}
`,
  nS = `
.success__position {
  position: fixed;
  inset: var(--dialog-inset);
  padding: var(--page-margin);
  z-index: var(--z-index);
}
.success__content {
  background: var(--success-background, var(--background));
  border: var(--success-border, var(--border));
  border-radius: var(--success-border-radius, 1.7em/50%);
  box-shadow: var(--success-box-shadow, var(--box-shadow));
  font-weight: var(--success-font-weight, 600);
  color: var(--success-color);
  fill: var(--success-color);
  padding: 12px 24px;
  line-height: 1.75em;

  display: grid;
  align-items: center;
  grid-auto-flow: column;
  gap: 6px;
  cursor: default;
}

.success__icon {
  display: flex;
}
`;
function rS(e) {
  const t = re.createElement("style");
  return (
    (t.textContent = `
:host {
  --dialog-inset: var(--inset);
}

${Z_}
${Q_}
${eS}
${tS}
${nS}
`),
    e && t.setAttribute("nonce", e),
    t
  );
}
function sS() {
  const e = ai().getUser(),
    t = Gg().getUser(),
    n = Vg().getUser();
  return e && Object.keys(e).length ? e : t && Object.keys(t).length ? t : n;
}
const iS = () => ({
  name: "FeedbackModal",
  setupOnce() {},
  createDialog: ({
    options: e,
    screenshotIntegration: t,
    sendFeedback: n,
    shadow: r,
  }) => {
    const s = r,
      i = e.useSentryUser,
      o = sS(),
      a = re.createElement("div"),
      c = rS(e.styleNonce);
    let u = "";
    const d = {
        get el() {
          return a;
        },
        appendToDom() {
          !s.contains(c) &&
            !s.contains(a) &&
            (s.appendChild(c), s.appendChild(a));
        },
        removeFromDom() {
          (a.remove(), c.remove(), (re.body.style.overflow = u));
        },
        open() {
          (p(!0),
            e.onFormOpen?.(),
            hr()?.emit("openFeedbackWidget"),
            (u = re.body.style.overflow),
            (re.body.style.overflow = "hidden"));
        },
        close() {
          (p(!1), (re.body.style.overflow = u));
        },
      },
      l = t?.createInput({ h: j, hooks: z_, dialog: d, options: e }),
      p = (f) => {
        O_(
          j(J_, {
            options: e,
            screenshotInput: l,
            showName: e.showName || e.isNameRequired,
            showEmail: e.showEmail || e.isEmailRequired,
            defaultName: (i && o?.[i.name]) || "",
            defaultEmail: (i && o?.[i.email]) || "",
            onFormClose: () => {
              (p(!1), e.onFormClose?.());
            },
            onSubmit: n,
            onSubmitSuccess: (h, m) => {
              (p(!1), e.onSubmitSuccess?.(h, m));
            },
            onSubmitError: (h) => {
              e.onSubmitError?.(h);
            },
            onFormSubmitted: () => {
              e.onFormSubmitted?.();
            },
            open: f,
          }),
          a,
        );
      };
    return d;
  },
});
function oS({ h: e }) {
  return function () {
    return e(
      "svg",
      {
        "data-test-id": "icon-close",
        viewBox: "0 0 16 16",
        fill: "#2B2233",
        height: "25px",
        width: "25px",
      },
      e("circle", { r: "7", cx: "8", cy: "8", fill: "white" }),
      e("path", {
        strokeWidth: "1.5",
        d: "M8,16a8,8,0,1,1,8-8A8,8,0,0,1,8,16ZM8,1.53A6.47,6.47,0,1,0,14.47,8,6.47,6.47,0,0,0,8,1.53Z",
      }),
      e("path", {
        strokeWidth: "1.5",
        d: "M5.34,11.41a.71.71,0,0,1-.53-.22.74.74,0,0,1,0-1.06l5.32-5.32a.75.75,0,0,1,1.06,1.06L5.87,11.19A.74.74,0,0,1,5.34,11.41Z",
      }),
      e("path", {
        strokeWidth: "1.5",
        d: "M10.66,11.41a.74.74,0,0,1-.53-.22L4.81,5.87A.75.75,0,0,1,5.87,4.81l5.32,5.32a.74.74,0,0,1,0,1.06A.71.71,0,0,1,10.66,11.41Z",
      }),
    );
  };
}
function aS(e) {
  const t = re.createElement("style"),
    n = "#1A141F",
    r = "#302735";
  return (
    (t.textContent = `
.editor {
  display: flex;
  flex-grow: 1;
  flex-direction: column;
}

.editor__image-container {
  justify-items: center;
  padding: 15px;
  position: relative;
  height: 100%;
  border-radius: var(--menu-border-radius, 6px);

  background-color: ${n};
  background-image: repeating-linear-gradient(
      -145deg,
      transparent,
      transparent 8px,
      ${n} 8px,
      ${n} 11px
    ),
    repeating-linear-gradient(
      -45deg,
      transparent,
      transparent 15px,
      ${r} 15px,
      ${r} 16px
    );
}

.editor__canvas-container {
  width: 100%;
  height: 100%;
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
}

.editor__canvas-container > * {
  object-fit: contain;
  position: absolute;
}

.editor__tool-container {
  padding-top: 8px;
  display: flex;
  justify-content: center;
}

.editor__tool-bar {
  display: flex;
  gap: 8px;
}

.editor__tool {
  display: flex;
  padding: 8px 12px;
  justify-content: center;
  align-items: center;
  border: var(--button-border, var(--border));
  border-radius: var(--button-border-radius, 6px);
  background: var(--button-background, var(--background));
  color: var(--button-color, var(--foreground));
}

.editor__tool--active {
  background: var(--button-primary-background, var(--accent-background));
  color: var(--button-primary-color, var(--accent-foreground));
}

.editor__rect {
  position: absolute;
  z-index: 2;
}

.editor__rect button {
  opacity: 0;
  position: absolute;
  top: -12px;
  right: -12px;
  cursor: pointer;
  padding: 0;
  z-index: 3;
  border: none;
  background: none;
}

.editor__rect:hover button {
  opacity: 1;
}
`),
    e && t.setAttribute("nonce", e),
    t
  );
}
function cS({ h: e }) {
  return function ({ action: n, setAction: r, options: s }) {
    return e(
      "div",
      { class: "editor__tool-container" },
      e(
        "div",
        { class: "editor__tool-bar" },
        e(
          "button",
          {
            type: "button",
            class: `editor__tool ${n === "highlight" ? "editor__tool--active" : ""}`,
            onClick: () => {
              r(n === "highlight" ? "" : "highlight");
            },
          },
          s.highlightToolText,
        ),
        e(
          "button",
          {
            type: "button",
            class: `editor__tool ${n === "hide" ? "editor__tool--active" : ""}`,
            onClick: () => {
              r(n === "hide" ? "" : "hide");
            },
          },
          s.hideToolText,
        ),
      ),
    );
  };
}
function uS({ hooks: e }) {
  function t() {
    const [n, r] = e.useState(We.devicePixelRatio ?? 1);
    return (
      e.useEffect(() => {
        const s = () => {
            r(We.devicePixelRatio);
          },
          i = matchMedia(`(resolution: ${We.devicePixelRatio}dppx)`);
        return (
          i.addEventListener("change", s),
          () => {
            i.removeEventListener("change", s);
          }
        );
      }, []),
      n
    );
  }
  return function ({
    onBeforeScreenshot: r,
    onScreenshot: s,
    onAfterScreenshot: i,
    onError: o,
  }) {
    const a = t();
    e.useEffect(() => {
      (async () => {
        r();
        const u = await Dn.mediaDevices.getDisplayMedia({
            video: { width: We.innerWidth * a, height: We.innerHeight * a },
            audio: !1,
            monitorTypeSurfaces: "exclude",
            preferCurrentTab: !0,
            selfBrowserSurface: "include",
            surfaceSwitching: "exclude",
          }),
          d = re.createElement("video");
        (await new Promise((l, p) => {
          ((d.srcObject = u),
            (d.onloadedmetadata = () => {
              (s(d, a), u.getTracks().forEach((f) => f.stop()), l());
            }),
            d.play().catch(p));
        }),
          i());
      })().catch(o);
    }, []);
  };
}
function lS(e, t, n) {
  switch (e.type) {
    case "highlight": {
      ((t.shadowColor = "rgba(0, 0, 0, 0.7)"),
        (t.shadowBlur = 50),
        (t.fillStyle = n),
        t.fillRect(e.x - 1, e.y - 1, e.w + 2, e.h + 2),
        t.clearRect(e.x, e.y, e.w, e.h));
      break;
    }
    case "hide":
      ((t.fillStyle = "rgb(0, 0, 0)"), t.fillRect(e.x, e.y, e.w, e.h));
      break;
  }
}
function yt(e, t, n) {
  if (!e) return;
  const r = e.getContext("2d", t);
  r && n(e, r);
}
function Di(e, t) {
  yt(e, { alpha: !0 }, (n, r) => {
    r.drawImage(t, 0, 0, t.width, t.height, 0, 0, n.width, n.height);
  });
}
function Pi(e, t, n) {
  yt(e, { alpha: !0 }, (r, s) => {
    (n.length &&
      ((s.fillStyle = "rgba(0, 0, 0, 0.25)"),
      s.fillRect(0, 0, r.width, r.height)),
      n.forEach((i) => {
        lS(i, s, t);
      }));
  });
}
function dS({ h: e, hooks: t, outputBuffer: n, dialog: r, options: s }) {
  const i = uS({ hooks: t }),
    o = cS({ h: e }),
    a = oS({ h: e }),
    c = { __html: aS(s.styleNonce).innerText },
    u = r.el.style,
    d = ({ screenshot: l }) => {
      const [p, f] = t.useState("highlight"),
        [h, m] = t.useState([]),
        g = t.useRef(null),
        _ = t.useRef(null),
        y = t.useRef(null),
        M = t.useRef(null),
        [w, A] = t.useState(1),
        C = t.useMemo(() => {
          const v = re.getElementById(s.id);
          if (!v) return "white";
          const x = getComputedStyle(v);
          return (
            x.getPropertyValue("--button-primary-background") ||
            x.getPropertyValue("--accent-background")
          );
        }, [s.id]);
      t.useLayoutEffect(() => {
        const v = () => {
          const x = g.current;
          x &&
            (yt(l.canvas, { alpha: !1 }, (U) => {
              const q = Math.min(
                x.clientWidth / U.width,
                x.clientHeight / U.height,
              );
              A(q);
            }),
            (x.clientHeight === 0 || x.clientWidth === 0) && setTimeout(v, 0));
        };
        return (
          v(),
          We.addEventListener("resize", v),
          () => {
            We.removeEventListener("resize", v);
          }
        );
      }, [l]);
      const E = t.useCallback(
        (v, x) => {
          yt(v, { alpha: !0 }, (U, q) => {
            (q.scale(x, x),
              (U.width = l.canvas.width),
              (U.height = l.canvas.height));
          });
        },
        [l],
      );
      (t.useEffect(() => {
        (E(_.current, l.dpi), Di(_.current, l.canvas));
      }, [l]),
        t.useEffect(() => {
          (E(y.current, l.dpi),
            yt(y.current, { alpha: !0 }, (v, x) => {
              x.clearRect(0, 0, v.width, v.height);
            }),
            Pi(y.current, C, h));
        }, [h, C]),
        t.useEffect(() => {
          (E(n, l.dpi),
            Di(n, l.canvas),
            yt(re.createElement("canvas"), { alpha: !0 }, (v, x) => {
              (x.scale(l.dpi, l.dpi),
                (v.width = l.canvas.width),
                (v.height = l.canvas.height),
                Pi(v, C, h),
                Di(n, v));
            }));
        }, [h, l, C]));
      const I = (v) => {
          if (!p || !M.current) return;
          const x = M.current.getBoundingClientRect(),
            U = { type: p, x: v.offsetX / w, y: v.offsetY / w },
            q = (P, R) => {
              const L = (R.clientX - x.x) / w,
                V = (R.clientY - x.y) / w;
              return {
                type: P.type,
                x: Math.min(P.x, L),
                y: Math.min(P.y, V),
                w: Math.abs(L - P.x),
                h: Math.abs(V - P.y),
              };
            },
            K = (P) => {
              (yt(y.current, { alpha: !0 }, (R, L) => {
                L.clearRect(0, 0, R.width, R.height);
              }),
                Pi(y.current, C, [...h, q(U, P)]));
            },
            T = (P) => {
              const R = q(U, P);
              (R.w * w >= 1 && R.h * w >= 1 && m((L) => [...L, R]),
                re.removeEventListener("mousemove", K),
                re.removeEventListener("mouseup", T));
            };
          (re.addEventListener("mousemove", K),
            re.addEventListener("mouseup", T));
        },
        b = t.useCallback(
          (v) => (x) => {
            (x.preventDefault(),
              x.stopPropagation(),
              m((U) => {
                const q = [...U];
                return (q.splice(v, 1), q);
              }));
          },
          [],
        ),
        k = {
          width: `${l.canvas.width * w}px`,
          height: `${l.canvas.height * w}px`,
        },
        O = (v) => {
          v.stopPropagation();
        };
      return e(
        "div",
        { class: "editor" },
        e("style", { nonce: s.styleNonce, dangerouslySetInnerHTML: c }),
        e(
          "div",
          { class: "editor__image-container" },
          e(
            "div",
            { class: "editor__canvas-container", ref: g },
            e("canvas", { ref: _, id: "background", style: k }),
            e("canvas", { ref: y, id: "foreground", style: k }),
            e(
              "div",
              { ref: M, onMouseDown: I, style: k },
              h.map((v, x) =>
                e(
                  "div",
                  {
                    key: x,
                    class: "editor__rect",
                    style: {
                      top: `${v.y * w}px`,
                      left: `${v.x * w}px`,
                      width: `${v.w * w}px`,
                      height: `${v.h * w}px`,
                    },
                  },
                  e(
                    "button",
                    {
                      "aria-label": s.removeHighlightText,
                      onClick: b(x),
                      onMouseDown: O,
                      onMouseUp: O,
                      type: "button",
                    },
                    e(a, null),
                  ),
                ),
              ),
            ),
          ),
        ),
        e(o, { options: s, action: p, setAction: f }),
      );
    };
  return function ({ onError: p }) {
    const [f, h] = t.useState();
    return (
      i({
        onBeforeScreenshot: t.useCallback(() => {
          u.display = "none";
        }, []),
        onScreenshot: t.useCallback((m, g) => {
          (yt(re.createElement("canvas"), { alpha: !1 }, (_, y) => {
            (y.scale(g, g),
              (_.width = m.videoWidth),
              (_.height = m.videoHeight),
              y.drawImage(m, 0, 0, _.width, _.height),
              h({ canvas: _, dpi: g }));
          }),
            (n.width = m.videoWidth),
            (n.height = m.videoHeight));
        }, []),
        onAfterScreenshot: t.useCallback(() => {
          u.display = "block";
        }, []),
        onError: t.useCallback((m) => {
          ((u.display = "block"), p(m));
        }, []),
      }),
      f ? e(d, { screenshot: f }) : e("div", null)
    );
  };
}
const fS = () => ({
    name: "FeedbackScreenshot",
    setupOnce() {},
    createInput: ({ h: e, hooks: t, dialog: n, options: r }) => {
      const s = re.createElement("canvas");
      return {
        input: dS({ h: e, hooks: t, outputBuffer: s, dialog: n, options: r }),
        value: async () => {
          const i = await new Promise((o) => {
            s.toBlob(o, "image/png");
          });
          if (i)
            return {
              data: new Uint8Array(await i.arrayBuffer()),
              filename: "screenshot.png",
              contentType: "application/png",
            };
        },
      };
    },
  }),
  as = {},
  lu = {};
function _r(e, t) {
  ((as[e] = as[e] || []), as[e].push(t));
}
function Sr(e, t) {
  if (!lu[e]) {
    lu[e] = !0;
    try {
      t();
    } catch (n) {
      N && S.error(`Error while instrumenting ${e}`, n);
    }
  }
}
function Ht(e, t) {
  const n = e && as[e];
  if (n)
    for (const r of n)
      try {
        r(t);
      } catch (s) {
        N &&
          S.error(
            `Error while triggering instrumentation handler.
Type: ${e}
Name: ${zt(r)}
Error:`,
            s,
          );
      }
}
let Fi = null;
function af(e) {
  const t = "error";
  (_r(t, e), Sr(t, pS));
}
function pS() {
  ((Fi = ne.onerror),
    (ne.onerror = function (e, t, n, r, s) {
      return (
        Ht("error", { column: r, error: s, line: n, msg: e, url: t }),
        Fi ? Fi.apply(this, arguments) : !1
      );
    }),
    (ne.onerror.__SENTRY_INSTRUMENTED__ = !0));
}
let Bi = null;
function cf(e) {
  const t = "unhandledrejection";
  (_r(t, e), Sr(t, hS));
}
function hS() {
  ((Bi = ne.onunhandledrejection),
    (ne.onunhandledrejection = function (e) {
      return (Ht("unhandledrejection", e), Bi ? Bi.apply(this, arguments) : !0);
    }),
    (ne.onunhandledrejection.__SENTRY_INSTRUMENTED__ = !0));
}
let du = !1;
function uf() {
  if (du) return;
  function e() {
    const t = Pe(),
      n = t && Ne(t);
    if (n) {
      const r = "internal_error";
      (N && S.log(`[Tracing] Root span: ${r} -> Global error occurred`),
        n.setStatus({ code: lt, message: r }));
    }
  }
  ((e.tag = "sentry_tracingErrorCallback"), (du = !0), af(e), cf(e));
}
function fu(e) {
  S.log(
    `Ignoring span ${e.op} - ${e.description} because it matches \`ignoreSpans\`.`,
  );
}
function ks(e, t) {
  if (!t?.length || !e.description) return !1;
  for (const n of t) {
    if (gS(n)) {
      if (Ni(e.description, n)) return (N && fu(e), !0);
      continue;
    }
    if (!n.name && !n.op) continue;
    const r = n.name ? Ni(e.description, n.name) : !0,
      s = n.op ? e.op && Ni(e.op, n.op) : !0;
    if (r && s) return (N && fu(e), !0);
  }
  return !1;
}
function mS(e, t) {
  const n = t.parent_span_id,
    r = t.span_id;
  if (n) for (const s of e) s.parent_span_id === r && (s.parent_span_id = n);
}
function gS(e) {
  return typeof e == "string" || e instanceof RegExp;
}
let pt = class {
  constructor(t = {}) {
    ((this._traceId = t.traceId || Jn()), (this._spanId = t.spanId || Pn()));
  }
  spanContext() {
    return { spanId: this._spanId, traceId: this._traceId, traceFlags: bd };
  }
  end(t) {}
  setAttribute(t, n) {
    return this;
  }
  setAttributes(t) {
    return this;
  }
  setStatus(t) {
    return this;
  }
  updateName(t) {
    return this;
  }
  isRecording() {
    return !1;
  }
  addEvent(t, n, r) {
    return this;
  }
  addLink(t) {
    return this;
  }
  addLinks(t) {
    return this;
  }
  recordException(t, n) {}
};
function Mt(e, t = []) {
  return [e, t];
}
function _S(e, t) {
  const [n, r] = e;
  return [n, [...r, t]];
}
function Vt(e, t) {
  const n = e[1];
  for (const r of n) {
    const s = r[0].type;
    if (t(r, s)) return !0;
  }
  return !1;
}
function pu(e, t) {
  return Vt(e, (n, r) => t.includes(r));
}
function Cs(e) {
  const t = Ed(ne);
  return t.encodePolyfill ? t.encodePolyfill(e) : new TextEncoder().encode(e);
}
function SS(e) {
  const t = Ed(ne);
  return t.decodePolyfill ? t.decodePolyfill(e) : new TextDecoder().decode(e);
}
function Rs(e) {
  const [t, n] = e;
  let r = JSON.stringify(t);
  function s(i) {
    typeof r == "string"
      ? (r = typeof i == "string" ? r + i : [Cs(r), i])
      : r.push(typeof i == "string" ? Cs(i) : i);
  }
  for (const i of n) {
    const [o, a] = i;
    if (
      (s(`
${JSON.stringify(o)}
`),
      typeof a == "string" || a instanceof Uint8Array)
    )
      s(a);
    else {
      let c;
      try {
        c = JSON.stringify(a);
      } catch {
        c = JSON.stringify(Ko(a));
      }
      s(c);
    }
  }
  return typeof r == "string" ? r : yS(r);
}
function yS(e) {
  const t = e.reduce((s, i) => s + i.length, 0),
    n = new Uint8Array(t);
  let r = 0;
  for (const s of e) (n.set(s, r), (r += s.length));
  return n;
}
function bS(e) {
  let t = typeof e == "string" ? Cs(e) : e;
  function n(o) {
    const a = t.subarray(0, o);
    return ((t = t.subarray(o + 1)), a);
  }
  function r() {
    let o = t.indexOf(10);
    return (o < 0 && (o = t.length), JSON.parse(SS(n(o))));
  }
  const s = r(),
    i = [];
  for (; t.length;) {
    const o = r(),
      a = typeof o.length == "number" ? o.length : void 0;
    i.push([o, a ? n(a) : r()]);
  }
  return [s, i];
}
function ES(e) {
  return [{ type: "span" }, e];
}
function vS(e) {
  const t = typeof e.data == "string" ? Cs(e.data) : e.data;
  return [
    {
      type: "attachment",
      length: t.length,
      filename: e.filename,
      content_type: e.contentType,
      attachment_type: e.attachmentType,
    },
    t,
  ];
}
const TS = {
  session: "session",
  sessions: "session",
  attachment: "attachment",
  transaction: "transaction",
  event: "error",
  client_report: "internal",
  user_report: "default",
  profile: "profile",
  profile_chunk: "profile",
  replay_event: "replay",
  replay_recording: "replay",
  check_in: "monitor",
  feedback: "feedback",
  span: "span",
  raw_security: "security",
  log: "log_item",
};
function hu(e) {
  return TS[e];
}
function lf(e) {
  if (!e?.sdk) return;
  const { name: t, version: n } = e.sdk;
  return { name: t, version: n };
}
function wS(e, t, n, r) {
  const s = e.sdkProcessingMetadata?.dynamicSamplingContext;
  return {
    event_id: e.event_id,
    sent_at: new Date().toISOString(),
    ...(t && { sdk: t }),
    ...(!!n && r && { dsn: kn(r) }),
    ...(s && { trace: s }),
  };
}
function IS(e, t) {
  if (!t) return e;
  const n = e.sdk || {};
  return (
    (e.sdk = {
      ...n,
      name: n.name || t.name,
      version: n.version || t.version,
      integrations: [...(e.sdk?.integrations || []), ...(t.integrations || [])],
      packages: [...(e.sdk?.packages || []), ...(t.packages || [])],
      settings:
        e.sdk?.settings || t.settings
          ? { ...e.sdk?.settings, ...t.settings }
          : void 0,
    }),
    e
  );
}
function kS(e, t, n, r) {
  const s = lf(n),
    i = {
      sent_at: new Date().toISOString(),
      ...(s && { sdk: s }),
      ...(!!r && t && { dsn: kn(t) }),
    },
    o =
      "aggregates" in e
        ? [{ type: "sessions" }, e]
        : [{ type: "session" }, e.toJSON()];
  return Mt(i, [o]);
}
function CS(e, t, n, r) {
  const s = lf(n),
    i = e.type && e.type !== "replay_event" ? e.type : "event";
  IS(e, n?.sdk);
  const o = wS(e, s, r, t);
  return (delete e.sdkProcessingMetadata, Mt(o, [[{ type: i }, e]]));
}
function RS(e, t) {
  function n(f) {
    return !!f.trace_id && !!f.public_key;
  }
  const r = Ct(e[0]),
    s = t?.getDsn(),
    i = t?.getOptions().tunnel,
    o = {
      sent_at: new Date().toISOString(),
      ...(n(r) && { trace: r }),
      ...(!!i && s && { dsn: kn(s) }),
    },
    { beforeSendSpan: a, ignoreSpans: c } = t?.getOptions() || {},
    u = c?.length ? e.filter((f) => !ks(ee(f), c)) : e,
    d = e.length - u.length;
  d && t?.recordDroppedEvent("before_send", "span", d);
  const l = a
      ? (f) => {
          const h = ee(f),
            m = a(h);
          return m || (uo(), h);
        }
      : ee,
    p = [];
  for (const f of u) {
    const h = l(f);
    h && p.push(ES(h));
  }
  return Mt(o, p);
}
function xS(e) {
  if (!N) return;
  const {
      description: t = "< unknown name >",
      op: n = "< unknown op >",
      parent_span_id: r,
    } = ee(e),
    { spanId: s } = e.spanContext(),
    i = ti(e),
    o = Ne(e),
    a = o === e,
    c = `[Tracing] Starting ${i ? "sampled" : "unsampled"} ${a ? "root " : ""}span`,
    u = [`op: ${n}`, `name: ${t}`, `ID: ${s}`];
  if ((r && u.push(`parent ID: ${r}`), !a)) {
    const { op: d, description: l } = ee(o);
    (u.push(`root ID: ${o.spanContext().spanId}`),
      d && u.push(`root op: ${d}`),
      l && u.push(`root description: ${l}`));
  }
  S.log(`${c}
  ${u.join(`
  `)}`);
}
function AS(e) {
  if (!N) return;
  const { description: t = "< unknown name >", op: n = "< unknown op >" } =
      ee(e),
    { spanId: r } = e.spanContext(),
    i = Ne(e) === e,
    o = `[Tracing] Finishing "${n}" ${i ? "root " : ""}span "${t}" with ID ${r}`;
  S.log(o);
}
function MS(e, t, n, r = Pe()) {
  const s = r && Ne(r);
  s &&
    (N &&
      S.log(`[Measurement] Setting measurement on root span: ${e} = ${t} ${n}`),
    s.addEvent(e, { [Td]: t, [vd]: n }));
}
function mu(e) {
  if (!e || e.length === 0) return;
  const t = {};
  return (
    e.forEach((n) => {
      const r = n.attributes || {},
        s = r[vd],
        i = r[Td];
      typeof s == "string" &&
        typeof i == "number" &&
        (t[n.name] = { value: i, unit: s });
    }),
    t
  );
}
const gu = 1e3;
let ui = class {
  constructor(t = {}) {
    ((this._traceId = t.traceId || Jn()),
      (this._spanId = t.spanId || Pn()),
      (this._startTime = t.startTimestamp || ke()),
      (this._links = t.links),
      (this._attributes = {}),
      this.setAttributes({ [Ze]: "manual", [Rt]: t.op, ...t.attributes }),
      (this._name = t.name),
      t.parentSpanId && (this._parentSpanId = t.parentSpanId),
      "sampled" in t && (this._sampled = t.sampled),
      t.endTimestamp && (this._endTime = t.endTimestamp),
      (this._events = []),
      (this._isStandaloneSpan = t.isStandalone),
      this._endTime && this._onSpanEnded());
  }
  addLink(t) {
    return (this._links ? this._links.push(t) : (this._links = [t]), this);
  }
  addLinks(t) {
    return (this._links ? this._links.push(...t) : (this._links = t), this);
  }
  recordException(t, n) {}
  spanContext() {
    const { _spanId: t, _traceId: n, _sampled: r } = this;
    return { spanId: t, traceId: n, traceFlags: r ? Tm : bd };
  }
  setAttribute(t, n) {
    return (
      n === void 0 ? delete this._attributes[t] : (this._attributes[t] = n),
      this
    );
  }
  setAttributes(t) {
    return (Object.keys(t).forEach((n) => this.setAttribute(n, t[n])), this);
  }
  updateStartTime(t) {
    this._startTime = Fn(t);
  }
  setStatus(t) {
    return ((this._status = t), this);
  }
  updateName(t) {
    return ((this._name = t), this.setAttribute(rt, "custom"), this);
  }
  end(t) {
    this._endTime || ((this._endTime = Fn(t)), AS(this), this._onSpanEnded());
  }
  getSpanJSON() {
    return {
      data: this._attributes,
      description: this._name,
      op: this._attributes[Rt],
      parent_span_id: this._parentSpanId,
      span_id: this._spanId,
      start_timestamp: this._startTime,
      status: Im(this._status),
      timestamp: this._endTime,
      trace_id: this._traceId,
      origin: this._attributes[Ze],
      profile_id: this._attributes[Zo],
      exclusive_time: this._attributes[Jo],
      measurements: mu(this._events),
      is_segment: (this._isStandaloneSpan && Ne(this) === this) || void 0,
      segment_id: this._isStandaloneSpan
        ? Ne(this).spanContext().spanId
        : void 0,
      links: wm(this._links),
    };
  }
  isRecording() {
    return !this._endTime && !!this._sampled;
  }
  addEvent(t, n, r) {
    N && S.log("[Tracing] Adding an event to span:", t);
    const s = _u(n) ? n : r || ke(),
      i = _u(n) ? {} : n || {},
      o = { name: t, time: Fn(s), attributes: i };
    return (this._events.push(o), this);
  }
  isStandaloneSpan() {
    return !!this._isStandaloneSpan;
  }
  _onSpanEnded() {
    const t = W();
    if (
      (t && t.emit("spanEnd", this),
      !(this._isStandaloneSpan || this === Ne(this)))
    )
      return;
    if (this._isStandaloneSpan) {
      this._sampled
        ? OS(RS([this], t))
        : (N &&
            S.log(
              "[Tracing] Discarding standalone span because its trace was not chosen to be sampled.",
            ),
          t && t.recordDroppedEvent("sample_rate", "span"));
      return;
    }
    const r = this._convertSpanToTransaction();
    r && (Oc(this).scope || ue()).captureEvent(r);
  }
  _convertSpanToTransaction() {
    if (!Su(ee(this))) return;
    this._name ||
      (N &&
        S.warn(
          "Transaction has no name, falling back to `<unlabeled transaction>`.",
        ),
      (this._name = "<unlabeled transaction>"));
    const { scope: t, isolationScope: n } = Oc(this),
      r = t?.getScopeData().sdkProcessingMetadata?.normalizedRequest;
    if (this._sampled !== !0) return;
    const i = Bn(this)
        .filter((d) => d !== this && !NS(d))
        .map((d) => ee(d))
        .filter(Su),
      o = this._attributes[rt];
    (delete this._attributes[Lc],
      i.forEach((d) => {
        delete d.data[Lc];
      }));
    const a = {
        contexts: { trace: km(this) },
        spans:
          i.length > gu
            ? i
                .sort((d, l) => d.start_timestamp - l.start_timestamp)
                .slice(0, gu)
            : i,
        start_timestamp: this._startTime,
        timestamp: this._endTime,
        transaction: this._name,
        type: "transaction",
        sdkProcessingMetadata: {
          capturedSpanScope: t,
          capturedSpanIsolationScope: n,
          dynamicSamplingContext: Ct(this),
        },
        request: r,
        ...(o && { transaction_info: { source: o } }),
      },
      c = mu(this._events);
    return (
      c &&
        Object.keys(c).length &&
        (N &&
          S.log(
            "[Measurements] Adding measurements to transaction event",
            JSON.stringify(c, void 0, 2),
          ),
        (a.measurements = c)),
      a
    );
  }
};
function _u(e) {
  return (e && typeof e == "number") || e instanceof Date || Array.isArray(e);
}
function Su(e) {
  return !!e.start_timestamp && !!e.timestamp && !!e.span_id && !!e.trace_id;
}
function NS(e) {
  return e instanceof ui && e.isStandaloneSpan();
}
function OS(e) {
  const t = W();
  if (!t) return;
  const n = e[1];
  if (!n || n.length === 0) {
    t.recordDroppedEvent("before_send", "span");
    return;
  }
  t.sendEnvelope(e);
}
function df(e, t, n = () => {}, r = () => {}) {
  let s;
  try {
    s = e();
  } catch (i) {
    throw (t(i), n(), i);
  }
  return LS(s, t, n, r);
}
function LS(e, t, n, r) {
  return wd(e)
    ? e.then(
        (s) => (n(), r(s), s),
        (s) => {
          throw (t(s), n(), s);
        },
      )
    : (n(), r(e), e);
}
function $S(e, t, n) {
  if (!Je(e)) return [!1];
  let r, s;
  typeof e.tracesSampler == "function"
    ? ((s = e.tracesSampler({
        ...t,
        inheritOrSampleWith: (a) =>
          typeof t.parentSampleRate == "number"
            ? t.parentSampleRate
            : typeof t.parentSampled == "boolean"
              ? Number(t.parentSampled)
              : a,
      })),
      (r = !0))
    : t.parentSampled !== void 0
      ? (s = t.parentSampled)
      : typeof e.tracesSampleRate < "u" && ((s = e.tracesSampleRate), (r = !0));
  const i = Qo(s);
  if (i === void 0)
    return (
      N &&
        S.warn(
          `[Tracing] Discarding root span because of invalid sample rate. Sample rate must be a boolean or a number between 0 and 1. Got ${JSON.stringify(s)} of type ${JSON.stringify(typeof s)}.`,
        ),
      [!1]
    );
  if (!i)
    return (
      N &&
        S.log(
          `[Tracing] Discarding transaction because ${typeof e.tracesSampler == "function" ? "tracesSampler returned 0 or false" : "a negative sampling decision was inherited or tracesSampleRate is set to 0"}`,
        ),
      [!1, i, r]
    );
  const o = n < i;
  return (
    o ||
      (N &&
        S.log(
          `[Tracing] Discarding transaction because it's not included in the random sample (sampling rate = ${Number(s)})`,
        )),
    [o, i, r]
  );
}
const xs = "__SENTRY_SUPPRESS_TRACING__";
function ba(e, t) {
  const n = br();
  if (n.startSpan) return n.startSpan(e, t);
  const r = va(e),
    { forceTransaction: s, parentSpan: i, scope: o } = e,
    a = o?.clone();
  return qe(a, () =>
    hf(i)(() => {
      const u = ue(),
        d = Ta(u, i),
        p =
          e.onlyIfParent && !d
            ? new pt()
            : Ea({
                parentSpan: d,
                spanArguments: r,
                forceTransaction: s,
                scope: u,
              });
      return (
        jt(u, p),
        df(
          () => t(p),
          () => {
            const { status: f } = ee(p);
            p.isRecording() &&
              (!f || f === "ok") &&
              p.setStatus({ code: lt, message: "internal_error" });
          },
          () => {
            p.end();
          },
        )
      );
    }),
  );
}
function DS(e, t) {
  const n = br();
  if (n.startSpanManual) return n.startSpanManual(e, t);
  const r = va(e),
    { forceTransaction: s, parentSpan: i, scope: o } = e,
    a = o?.clone();
  return qe(a, () =>
    hf(i)(() => {
      const u = ue(),
        d = Ta(u, i),
        p =
          e.onlyIfParent && !d
            ? new pt()
            : Ea({
                parentSpan: d,
                spanArguments: r,
                forceTransaction: s,
                scope: u,
              });
      return (
        jt(u, p),
        df(
          () => t(p, () => p.end()),
          () => {
            const { status: f } = ee(p);
            p.isRecording() &&
              (!f || f === "ok") &&
              p.setStatus({ code: lt, message: "internal_error" });
          },
        )
      );
    }),
  );
}
function yr(e) {
  const t = br();
  if (t.startInactiveSpan) return t.startInactiveSpan(e);
  const n = va(e),
    { forceTransaction: r, parentSpan: s } = e;
  return (
    e.scope
      ? (o) => qe(e.scope, o)
      : s !== void 0
        ? (o) => li(s, o)
        : (o) => o()
  )(() => {
    const o = ue(),
      a = Ta(o, s);
    return e.onlyIfParent && !a
      ? new pt()
      : Ea({ parentSpan: a, spanArguments: n, forceTransaction: r, scope: o });
  });
}
const PS = (e, t) => {
  const n = ea(),
    r = ta(n);
  if (r.continueTrace) return r.continueTrace(e, t);
  const { sentryTrace: s, baggage: i } = e,
    o = W(),
    a = Cm(i);
  return o && !Rm(o, a?.org_id)
    ? pf(t)
    : qe((c) => {
        const u = Cd(s, i);
        return (c.setPropagationContext(u), t());
      });
};
function li(e, t) {
  const n = br();
  return n.withActiveSpan
    ? n.withActiveSpan(e, t)
    : qe((r) => (jt(r, e || void 0), t(r)));
}
function ff(e) {
  const t = br();
  return t.suppressTracing
    ? t.suppressTracing(e)
    : qe((n) => {
        n.setSDKProcessingMetadata({ [xs]: !0 });
        const r = e();
        return (n.setSDKProcessingMetadata({ [xs]: void 0 }), r);
      });
}
function pf(e) {
  return qe(
    (t) => (
      t.setPropagationContext({ traceId: Jn(), sampleRand: Math.random() }),
      N &&
        S.log(
          `Starting a new trace with id ${t.getPropagationContext().traceId}`,
        ),
      li(null, e)
    ),
  );
}
function Ea({
  parentSpan: e,
  spanArguments: t,
  forceTransaction: n,
  scope: r,
}) {
  if (!Je()) {
    const o = new pt();
    if (n || !e) {
      const a = {
        sampled: "false",
        sample_rate: "0",
        transaction: t.name,
        ...Ct(o),
      };
      ts(o, a);
    }
    return o;
  }
  const s = Cn();
  let i;
  if (e && !n) ((i = FS(e, r, t)), kd(e, i));
  else if (e) {
    const o = Ct(e),
      { traceId: a, spanId: c } = e.spanContext(),
      u = ti(e);
    ((i = yu({ traceId: a, parentSpanId: c, ...t }, r, u)), ts(i, o));
  } else {
    const {
      traceId: o,
      dsc: a,
      parentSpanId: c,
      sampled: u,
    } = { ...s.getPropagationContext(), ...r.getPropagationContext() };
    ((i = yu({ traceId: o, parentSpanId: c, ...t }, r, u)), a && ts(i, a));
  }
  return (xS(i), xm(i, r, s), i);
}
function va(e) {
  const n = { isStandalone: (e.experimental || {}).standalone, ...e };
  if (e.startTime) {
    const r = { ...n };
    return ((r.startTimestamp = Fn(e.startTime)), delete r.startTime, r);
  }
  return n;
}
function br() {
  const e = ea();
  return ta(e);
}
function yu(e, t, n) {
  const r = W(),
    s = r?.getOptions() || {},
    { name: i = "" } = e,
    o = { spanAttributes: { ...e.attributes }, spanName: i, parentSampled: n };
  r?.emit("beforeSampling", o, { decision: !1 });
  const a = o.parentSampled ?? n,
    c = o.spanAttributes,
    u = t.getPropagationContext(),
    [d, l, p] = t.getScopeData().sdkProcessingMetadata[xs]
      ? [!1]
      : $S(
          s,
          {
            name: i,
            parentSampled: a,
            attributes: c,
            parentSampleRate: Qo(u.dsc?.sample_rate),
          },
          u.sampleRand,
        ),
    f = new ui({
      ...e,
      attributes: {
        [rt]: "custom",
        [na]: l !== void 0 && p ? l : void 0,
        ...c,
      },
      sampled: d,
    });
  return (
    !d &&
      r &&
      (N &&
        S.log(
          "[Tracing] Discarding root span because its trace was not chosen to be sampled.",
        ),
      r.recordDroppedEvent("sample_rate", "transaction")),
    r && r.emit("spanStart", f),
    f
  );
}
function FS(e, t, n) {
  const { spanId: r, traceId: s } = e.spanContext(),
    i = t.getScopeData().sdkProcessingMetadata[xs] ? !1 : ti(e),
    o = i
      ? new ui({ ...n, parentSpanId: r, traceId: s, sampled: i })
      : new pt({ traceId: s });
  kd(e, o);
  const a = W();
  return (
    a && (a.emit("spanStart", o), n.endTimestamp && a.emit("spanEnd", o)),
    o
  );
}
function Ta(e, t) {
  if (t) return t;
  if (t === null) return;
  const n = Id(e);
  if (!n) return;
  const r = W();
  return (r ? r.getOptions() : {}).parentSpanIsAlwaysRootSpan ? Ne(n) : n;
}
function hf(e) {
  return e !== void 0 ? (t) => li(e, t) : (t) => t();
}
const cs = { idleTimeout: 1e3, finalTimeout: 3e4, childSpanTimeout: 15e3 },
  BS = "heartbeatFailed",
  US = "idleTimeout",
  HS = "finalTimeout",
  WS = "externalFinish";
function mf(e, t = {}) {
  const n = new Map();
  let r = !1,
    s,
    i = WS,
    o = !t.disableAutoFinish;
  const a = [],
    {
      idleTimeout: c = cs.idleTimeout,
      finalTimeout: u = cs.finalTimeout,
      childSpanTimeout: d = cs.childSpanTimeout,
      beforeSpanEnd: l,
      trimIdleSpanEndTimestamp: p = !0,
    } = t,
    f = W();
  if (!f || !Je()) {
    const E = new pt(),
      I = { sample_rate: "0", sampled: "false", ...Ct(E) };
    return (ts(E, I), E);
  }
  const h = ue(),
    m = Pe(),
    g = zS(e);
  g.end = new Proxy(g.end, {
    apply(E, I, b) {
      if ((l && l(g), I instanceof pt)) return;
      const [k, ...O] = b,
        v = k || ke(),
        x = Fn(v),
        U = Bn(g).filter((L) => L !== g),
        q = ee(g);
      if (!U.length || !p) return (C(x), Reflect.apply(E, I, [x, ...O]));
      const K = f.getOptions().ignoreSpans,
        T = U?.reduce(
          (L, V) => {
            const Q = ee(V);
            return !Q.timestamp || (K && ks(Q, K))
              ? L
              : L
                ? Math.max(L, Q.timestamp)
                : Q.timestamp;
          },
          void 0,
        ),
        P = q.start_timestamp,
        R = Math.min(
          P ? P + u / 1e3 : 1 / 0,
          Math.max(P || -1 / 0, Math.min(x, T || 1 / 0)),
        );
      return (C(R), Reflect.apply(E, I, [R, ...O]));
    },
  });
  function _() {
    s && (clearTimeout(s), (s = void 0));
  }
  function y(E) {
    (_(),
      (s = setTimeout(() => {
        !r && n.size === 0 && o && ((i = US), g.end(E));
      }, c)));
  }
  function M(E) {
    s = setTimeout(() => {
      !r && o && ((i = BS), g.end(E));
    }, d);
  }
  function w(E) {
    (_(), n.set(E, !0));
    const I = ke();
    M(I + d / 1e3);
  }
  function A(E) {
    if ((n.has(E) && n.delete(E), n.size === 0)) {
      const I = ke();
      y(I + c / 1e3);
    }
  }
  function C(E) {
    ((r = !0), n.clear(), a.forEach((x) => x()), jt(h, m));
    const I = ee(g),
      { start_timestamp: b } = I;
    if (!b) return;
    (I.data[Zn] || g.setAttribute(Zn, i),
      S.log(`[Tracing] Idle span "${I.op}" finished`));
    const O = Bn(g).filter((x) => x !== g);
    let v = 0;
    (O.forEach((x) => {
      x.isRecording() &&
        (x.setStatus({ code: lt, message: "cancelled" }),
        x.end(E),
        N &&
          S.log(
            "[Tracing] Cancelling span since span ended early",
            JSON.stringify(x, void 0, 2),
          ));
      const U = ee(x),
        { timestamp: q = 0, start_timestamp: K = 0 } = U,
        T = K <= E,
        P = (u + c) / 1e3,
        R = q - K <= P;
      if (N) {
        const L = JSON.stringify(x, void 0, 2);
        T
          ? R ||
            S.log(
              "[Tracing] Discarding span since it finished after idle span final timeout",
              L,
            )
          : S.log(
              "[Tracing] Discarding span since it happened after idle span was finished",
              L,
            );
      }
      (!R || !T) && (Am(g, x), v++);
    }),
      v > 0 && g.setAttribute("sentry.idle_span_discarded_spans", v));
  }
  return (
    a.push(
      f.on("spanStart", (E) => {
        if (
          r ||
          E === g ||
          ee(E).timestamp ||
          (E instanceof ui && E.isStandaloneSpan())
        )
          return;
        Bn(g).includes(E) && w(E.spanContext().spanId);
      }),
    ),
    a.push(
      f.on("spanEnd", (E) => {
        r || A(E.spanContext().spanId);
      }),
    ),
    a.push(
      f.on("idleSpanEnableAutoFinish", (E) => {
        E === g && ((o = !0), y(), n.size && M());
      }),
    ),
    t.disableAutoFinish || y(),
    setTimeout(() => {
      r ||
        (g.setStatus({ code: lt, message: "deadline_exceeded" }),
        (i = HS),
        g.end());
    }, u),
    g
  );
}
function zS(e) {
  const t = yr(e);
  return (jt(ue(), t), N && S.log("[Tracing] Started span is an idle span"), t);
}
const bu = [];
function jS(e) {
  const t = {};
  return (
    e.forEach((n) => {
      const { name: r } = n,
        s = t[r];
      (s && !s.isDefaultInstance && n.isDefaultInstance) || (t[r] = n);
    }),
    Object.values(t)
  );
}
function qS(e) {
  const t = e.defaultIntegrations || [],
    n = e.integrations;
  t.forEach((s) => {
    s.isDefaultInstance = !0;
  });
  let r;
  if (Array.isArray(n)) r = [...t, ...n];
  else if (typeof n == "function") {
    const s = n(t);
    r = Array.isArray(s) ? s : [s];
  } else r = t;
  return jS(r);
}
function GS(e, t) {
  const n = {};
  return (
    t.forEach((r) => {
      r && gf(e, r, n);
    }),
    n
  );
}
function Eu(e, t) {
  for (const n of t) n?.afterAllSetup && n.afterAllSetup(e);
}
function gf(e, t, n) {
  if (n[t.name]) {
    N &&
      S.log(`Integration skipped because it was already installed: ${t.name}`);
    return;
  }
  if (
    ((n[t.name] = t),
    bu.indexOf(t.name) === -1 &&
      typeof t.setupOnce == "function" &&
      (t.setupOnce(), bu.push(t.name)),
    t.setup && typeof t.setup == "function" && t.setup(e),
    typeof t.preprocessEvent == "function")
  ) {
    const r = t.preprocessEvent.bind(t);
    e.on("preprocessEvent", (s, i) => r(s, i, e));
  }
  if (typeof t.processEvent == "function") {
    const r = t.processEvent.bind(t),
      s = Object.assign((i, o) => r(i, o, e), { id: t.name });
    e.addEventProcessor(s);
  }
  N && S.log(`Integration installed: ${t.name}`);
}
function VS(e) {
  const t = W();
  if (!t) {
    N &&
      S.warn(
        `Cannot add integration "${e.name}" because no SDK Client is available.`,
      );
    return;
  }
  t.addIntegration(e);
}
function YS(e, t, n) {
  const r = [
    { type: "client_report" },
    { timestamp: ni(), discarded_events: e },
  ];
  return Mt(t ? { dsn: t } : {}, [r]);
}
function _f(e) {
  const t = [];
  e.message && t.push(e.message);
  try {
    const n = e.exception.values[e.exception.values.length - 1];
    n?.value && (t.push(n.value), n.type && t.push(`${n.type}: ${n.value}`));
  } catch {}
  return t;
}
function XS(e) {
  const {
    trace_id: t,
    parent_span_id: n,
    span_id: r,
    status: s,
    origin: i,
    data: o,
    op: a,
  } = e.contexts?.trace ?? {};
  return {
    data: o ?? {},
    description: e.transaction,
    op: a,
    parent_span_id: n,
    span_id: r ?? "",
    start_timestamp: e.start_timestamp ?? 0,
    status: s,
    timestamp: e.timestamp,
    trace_id: t ?? "",
    origin: i,
    profile_id: o?.[Zo],
    exclusive_time: o?.[Jo],
    measurements: e.measurements,
    is_segment: !0,
  };
}
function KS(e) {
  return {
    type: "transaction",
    timestamp: e.timestamp,
    start_timestamp: e.start_timestamp,
    transaction: e.description,
    contexts: {
      trace: {
        trace_id: e.trace_id,
        span_id: e.span_id,
        parent_span_id: e.parent_span_id,
        op: e.op,
        status: e.status,
        origin: e.origin,
        data: {
          ...e.data,
          ...(e.profile_id && { [Zo]: e.profile_id }),
          ...(e.exclusive_time && { [Jo]: e.exclusive_time }),
        },
      },
    },
    measurements: e.measurements,
  };
}
const vu = "Not capturing exception because it's already been captured.",
  Tu = "Discarded session because of missing or non-string release",
  Sf = Symbol.for("SentryInternalError"),
  yf = Symbol.for("SentryDoNotSendEventError");
function us(e) {
  return { message: e, [Sf]: !0 };
}
function Ui(e) {
  return { message: e, [yf]: !0 };
}
function wu(e) {
  return !!e && typeof e == "object" && Sf in e;
}
function Iu(e) {
  return !!e && typeof e == "object" && yf in e;
}
class JS {
  constructor(t) {
    if (
      ((this._options = t),
      (this._integrations = {}),
      (this._numProcessing = 0),
      (this._outcomes = {}),
      (this._hooks = {}),
      (this._eventProcessors = []),
      t.dsn
        ? (this._dsn = Mm(t.dsn))
        : N && S.warn("No DSN provided, client will not send events."),
      this._dsn)
    ) {
      const n = Rd(this._dsn, t.tunnel, t._metadata ? t._metadata.sdk : void 0);
      this._transport = t.transport({
        tunnel: this._options.tunnel,
        recordDroppedEvent: this.recordDroppedEvent.bind(this),
        ...t.transportOptions,
        url: n,
      });
    }
  }
  captureException(t, n, r) {
    const s = Un();
    if ($c(t)) return (N && S.log(vu), s);
    const i = { event_id: s, ...n };
    return (
      this._process(
        this.eventFromException(t, i).then((o) => this._captureEvent(o, i, r)),
      ),
      i.event_id
    );
  }
  captureMessage(t, n, r, s) {
    const i = { event_id: Un(), ...r },
      o = sa(t) ? t : String(t),
      a = ri(t)
        ? this.eventFromMessage(o, n, i)
        : this.eventFromException(t, i);
    return (
      this._process(a.then((c) => this._captureEvent(c, i, s))),
      i.event_id
    );
  }
  captureEvent(t, n, r) {
    const s = Un();
    if (n?.originalException && $c(n.originalException))
      return (N && S.log(vu), s);
    const i = { event_id: s, ...n },
      o = t.sdkProcessingMetadata || {},
      a = o.capturedSpanScope,
      c = o.capturedSpanIsolationScope;
    return (this._process(this._captureEvent(t, i, a || r, c)), i.event_id);
  }
  captureSession(t) {
    (this.sendSession(t), Dc(t, { init: !1 }));
  }
  getDsn() {
    return this._dsn;
  }
  getOptions() {
    return this._options;
  }
  getSdkMetadata() {
    return this._options._metadata;
  }
  getTransport() {
    return this._transport;
  }
  async flush(t) {
    const n = this._transport;
    if (!n) return !0;
    this.emit("flush");
    const r = await this._isClientDoneProcessing(t),
      s = await n.flush(t);
    return r && s;
  }
  async close(t) {
    const n = await this.flush(t);
    return ((this.getOptions().enabled = !1), this.emit("close"), n);
  }
  getEventProcessors() {
    return this._eventProcessors;
  }
  addEventProcessor(t) {
    this._eventProcessors.push(t);
  }
  init() {
    (this._isEnabled() ||
      this._options.integrations.some(({ name: t }) =>
        t.startsWith("Spotlight"),
      )) &&
      this._setupIntegrations();
  }
  getIntegrationByName(t) {
    return this._integrations[t];
  }
  addIntegration(t) {
    const n = this._integrations[t.name];
    (gf(this, t, this._integrations), n || Eu(this, [t]));
  }
  sendEvent(t, n = {}) {
    this.emit("beforeSendEvent", t, n);
    let r = CS(t, this._dsn, this._options._metadata, this._options.tunnel);
    for (const s of n.attachments || []) r = _S(r, vS(s));
    this.sendEnvelope(r).then((s) => this.emit("afterSendEvent", t, s));
  }
  sendSession(t) {
    const { release: n, environment: r = xd } = this._options;
    if ("aggregates" in t) {
      const i = t.attrs || {};
      if (!i.release && !n) {
        N && S.warn(Tu);
        return;
      }
      ((i.release = i.release || n),
        (i.environment = i.environment || r),
        (t.attrs = i));
    } else {
      if (!t.release && !n) {
        N && S.warn(Tu);
        return;
      }
      ((t.release = t.release || n), (t.environment = t.environment || r));
    }
    this.emit("beforeSendSession", t);
    const s = kS(t, this._dsn, this._options._metadata, this._options.tunnel);
    this.sendEnvelope(s);
  }
  recordDroppedEvent(t, n, r = 1) {
    if (this._options.sendClientReports) {
      const s = `${t}:${n}`;
      (N && S.log(`Recording outcome: "${s}"${r > 1 ? ` (${r} times)` : ""}`),
        (this._outcomes[s] = (this._outcomes[s] || 0) + r));
    }
  }
  on(t, n) {
    const r = (this._hooks[t] = this._hooks[t] || new Set()),
      s = (...i) => n(...i);
    return (
      r.add(s),
      () => {
        r.delete(s);
      }
    );
  }
  emit(t, ...n) {
    const r = this._hooks[t];
    r && r.forEach((s) => s(...n));
  }
  async sendEnvelope(t) {
    if ((this.emit("beforeEnvelope", t), this._isEnabled() && this._transport))
      try {
        return await this._transport.send(t);
      } catch (n) {
        return (N && S.error("Error while sending envelope:", n), {});
      }
    return (N && S.error("Transport disabled"), {});
  }
  _setupIntegrations() {
    const { integrations: t } = this._options;
    ((this._integrations = GS(this, t)), Eu(this, t));
  }
  _updateSessionFromEvent(t, n) {
    let r = n.level === "fatal",
      s = !1;
    const i = n.exception?.values;
    if (i) {
      s = !0;
      for (const c of i)
        if (c.mechanism?.handled === !1) {
          r = !0;
          break;
        }
    }
    const o = t.status === "ok";
    ((o && t.errors === 0) || (o && r)) &&
      (Dc(t, {
        ...(r && { status: "crashed" }),
        errors: t.errors || Number(s || r),
      }),
      this.captureSession(t));
  }
  async _isClientDoneProcessing(t) {
    let n = 0;
    for (; !t || n < t;) {
      if ((await new Promise((r) => setTimeout(r, 1)), !this._numProcessing))
        return !0;
      n++;
    }
    return !1;
  }
  _isEnabled() {
    return this.getOptions().enabled !== !1 && this._transport !== void 0;
  }
  _prepareEvent(t, n, r, s) {
    const i = this.getOptions(),
      o = Object.keys(this._integrations);
    return (
      !n.integrations && o?.length && (n.integrations = o),
      this.emit("preprocessEvent", t, n),
      t.type || s.setLastEventId(t.event_id || n.event_id),
      Nm(i, t, n, r, this, s).then((a) => {
        if (a === null) return a;
        (this.emit("postprocessEvent", a, n),
          (a.contexts = { trace: Ad(r), ...a.contexts }));
        const c = ra(this, r);
        return (
          (a.sdkProcessingMetadata = {
            dynamicSamplingContext: c,
            ...a.sdkProcessingMetadata,
          }),
          a
        );
      })
    );
  }
  _captureEvent(t, n = {}, r = ue(), s = Cn()) {
    return (
      N &&
        Eo(t) &&
        S.log(`Captured error event \`${_f(t)[0] || "<unknown>"}\``),
      this._processEvent(t, n, r, s).then(
        (i) => i.event_id,
        (i) => {
          N &&
            (Iu(i) ? S.log(i.message) : wu(i) ? S.warn(i.message) : S.warn(i));
        },
      )
    );
  }
  _processEvent(t, n, r, s) {
    const i = this.getOptions(),
      { sampleRate: o } = i,
      a = bf(t),
      c = Eo(t),
      u = t.type || "error",
      d = `before send for type \`${u}\``,
      l = typeof o > "u" ? void 0 : Qo(o);
    if (c && typeof l == "number" && Math.random() > l)
      return (
        this.recordDroppedEvent("sample_rate", "error"),
        Md(
          Ui(
            `Discarding event because it's not included in the random sample (sampling rate = ${o})`,
          ),
        )
      );
    const p = u === "replay_event" ? "replay" : u;
    return this._prepareEvent(t, n, r, s)
      .then((f) => {
        if (f === null)
          throw (
            this.recordDroppedEvent("event_processor", p),
            Ui("An event processor returned `null`, will not send event.")
          );
        if (n.data && n.data.__sentry__ === !0) return f;
        const m = QS(this, i, f, n);
        return ZS(m, d);
      })
      .then((f) => {
        if (f === null) {
          if ((this.recordDroppedEvent("before_send", p), a)) {
            const _ = 1 + (t.spans || []).length;
            this.recordDroppedEvent("before_send", "span", _);
          }
          throw Ui(`${d} returned \`null\`, will not send event.`);
        }
        const h = r.getSession() || s.getSession();
        if ((c && h && this._updateSessionFromEvent(h, f), a)) {
          const g = f.sdkProcessingMetadata?.spanCountBeforeProcessing || 0,
            _ = f.spans ? f.spans.length : 0,
            y = g - _;
          y > 0 && this.recordDroppedEvent("before_send", "span", y);
        }
        const m = f.transaction_info;
        if (a && m && f.transaction !== t.transaction) {
          const g = "custom";
          f.transaction_info = { ...m, source: g };
        }
        return (this.sendEvent(f, n), f);
      })
      .then(null, (f) => {
        throw Iu(f) || wu(f)
          ? f
          : (this.captureException(f, {
              mechanism: { handled: !1, type: "internal" },
              data: { __sentry__: !0 },
              originalException: f,
            }),
            us(`Event processing pipeline threw an error, original event will not be sent. Details have been sent as a new event.
Reason: ${f}`));
      });
  }
  _process(t) {
    (this._numProcessing++,
      t.then(
        (n) => (this._numProcessing--, n),
        (n) => (this._numProcessing--, n),
      ));
  }
  _clearOutcomes() {
    const t = this._outcomes;
    return (
      (this._outcomes = {}),
      Object.entries(t).map(([n, r]) => {
        const [s, i] = n.split(":");
        return { reason: s, category: i, quantity: r };
      })
    );
  }
  _flushOutcomes() {
    N && S.log("Flushing outcomes...");
    const t = this._clearOutcomes();
    if (t.length === 0) {
      N && S.log("No outcomes to send");
      return;
    }
    if (!this._dsn) {
      N && S.log("No dsn provided, will not send outcomes");
      return;
    }
    N && S.log("Sending outcomes:", t);
    const n = YS(t, this._options.tunnel && kn(this._dsn));
    this.sendEnvelope(n);
  }
}
function ZS(e, t) {
  const n = `${t} must return \`null\` or a valid event.`;
  if (wd(e))
    return e.then(
      (r) => {
        if (!qt(r) && r !== null) throw us(n);
        return r;
      },
      (r) => {
        throw us(`${t} rejected with ${r}`);
      },
    );
  if (!qt(e) && e !== null) throw us(n);
  return e;
}
function QS(e, t, n, r) {
  const {
    beforeSend: s,
    beforeSendTransaction: i,
    beforeSendSpan: o,
    ignoreSpans: a,
  } = t;
  let c = n;
  if (Eo(c) && s) return s(c, r);
  if (bf(c)) {
    if (o || a) {
      const u = XS(c);
      if (a?.length && ks(u, a)) return null;
      if (o) {
        const d = o(u);
        d ? (c = Om(n, KS(d))) : uo();
      }
      if (c.spans) {
        const d = [],
          l = c.spans;
        for (const f of l) {
          if (a?.length && ks(f, a)) {
            mS(l, f);
            continue;
          }
          if (o) {
            const h = o(f);
            h ? d.push(h) : (uo(), d.push(f));
          } else d.push(f);
        }
        const p = c.spans.length - d.length;
        (p && e.recordDroppedEvent("before_send", "span", p), (c.spans = d));
      }
    }
    if (i) {
      if (c.spans) {
        const u = c.spans.length;
        c.sdkProcessingMetadata = {
          ...n.sdkProcessingMetadata,
          spanCountBeforeProcessing: u,
        };
      }
      return i(c, r);
    }
  }
  return c;
}
function Eo(e) {
  return e.type === void 0;
}
function bf(e) {
  return e.type === "transaction";
}
function ey(e, t) {
  return t
    ? qe(t, () => {
        const n = Pe(),
          r = n ? Lm(n) : Ad(t);
        return [n ? Ct(n) : ra(e, t), r];
      })
    : [void 0, void 0];
}
const ty = { trace: 1, debug: 5, info: 9, warn: 13, error: 17, fatal: 21 };
function ny(e) {
  return [
    {
      type: "log",
      item_count: e.length,
      content_type: "application/vnd.sentry.items.log+json",
    },
    { items: e },
  ];
}
function ry(e, t, n, r) {
  const s = {};
  return (
    t?.sdk && (s.sdk = { name: t.sdk.name, version: t.sdk.version }),
    n && r && (s.dsn = kn(r)),
    Mt(s, [ny(e)])
  );
}
const sy = 100;
function iy(e) {
  switch (typeof e) {
    case "number":
      return Number.isInteger(e)
        ? { value: e, type: "integer" }
        : { value: e, type: "double" };
    case "boolean":
      return { value: e, type: "boolean" };
    case "string":
      return { value: e, type: "string" };
    default: {
      let t = "";
      try {
        t = JSON.stringify(e) ?? "";
      } catch {}
      return { value: t, type: "string" };
    }
  }
}
function Ye(e, t, n, r = !0) {
  n && (!e[t] || r) && (e[t] = n);
}
function oy(e, t) {
  const n = wa(),
    r = Ef(e);
  r === void 0
    ? n.set(e, [t])
    : (n.set(e, [...r, t]), r.length >= sy && ls(e, r));
}
function As(e, t = ue(), n = oy) {
  const r = t?.getClient() ?? W();
  if (!r) {
    N && S.warn("No client available to capture log.");
    return;
  }
  const {
    release: s,
    environment: i,
    enableLogs: o = !1,
    beforeSendLog: a,
  } = r.getOptions();
  if (!o) {
    N && S.warn("logging option not enabled, log will not be captured.");
    return;
  }
  const [, c] = ey(r, t),
    u = { ...e.attributes },
    {
      user: { id: d, email: l, username: p },
    } = ay(t);
  (Ye(u, "user.id", d, !1),
    Ye(u, "user.email", l, !1),
    Ye(u, "user.name", p, !1),
    Ye(u, "sentry.release", s),
    Ye(u, "sentry.environment", i));
  const { name: f, version: h } = r.getSdkMetadata()?.sdk ?? {};
  (Ye(u, "sentry.sdk.name", f), Ye(u, "sentry.sdk.version", h));
  const m = r.getIntegrationByName("Replay"),
    g = m?.getReplayId(!0);
  (Ye(u, "sentry.replay_id", g),
    g &&
      m?.getRecordingMode() === "buffer" &&
      Ye(u, "sentry._internal.replay_is_buffering", !0));
  const _ = e.message;
  if (sa(_)) {
    const {
      __sentry_template_string__: k,
      __sentry_template_values__: O = [],
    } = _;
    (O?.length && (u["sentry.message.template"] = k),
      O.forEach((v, x) => {
        u[`sentry.message.parameter.${x}`] = v;
      }));
  }
  const y = Id(t);
  Ye(u, "sentry.trace.parent_span_id", y?.spanContext().spanId);
  const M = { ...e, attributes: u };
  r.emit("beforeCaptureLog", M);
  const w = a ? si(() => a(M)) : M;
  if (!w) {
    (r.recordDroppedEvent("before_send", "log_item", 1),
      N && S.warn("beforeSendLog returned null, log will not be captured."));
    return;
  }
  const { level: A, message: C, attributes: E = {}, severityNumber: I } = w,
    b = {
      timestamp: ke(),
      level: A,
      body: C,
      trace_id: c?.trace_id,
      severity_number: I ?? ty[A],
      attributes: Object.keys(E).reduce((k, O) => ((k[O] = iy(E[O])), k), {}),
    };
  (n(r, b), r.emit("afterCaptureLog", w));
}
function ls(e, t) {
  const n = t ?? Ef(e) ?? [];
  if (n.length === 0) return;
  const r = e.getOptions(),
    s = ry(n, r._metadata, r.tunnel, e.getDsn());
  (wa().set(e, []), e.emit("flushLogs"), e.sendEnvelope(s));
}
function Ef(e) {
  return wa().get(e);
}
function ay(e) {
  const t = Nd().getScopeData();
  return (Pc(t, Cn().getScopeData()), Pc(t, e.getScopeData()), t);
}
function wa() {
  return $m("clientToLogBufferMap", () => new WeakMap());
}
function cy(e, t) {
  (t.debug === !0 &&
    (N
      ? S.enable()
      : si(() => {
          console.warn(
            "[Sentry] Cannot initialize SDK with `debug` option using a non-debug bundle.",
          );
        })),
    ue().update(t.initialScope));
  const r = new e(t);
  return (vf(r), r.init(), r);
}
function vf(e) {
  ue().setClient(e);
}
const Tf = Symbol.for("SentryBufferFullError");
function uy(e = 100) {
  const t = new Set();
  function n() {
    return t.size < e;
  }
  function r(o) {
    t.delete(o);
  }
  function s(o) {
    if (!n()) return Md(Tf);
    const a = o();
    return (
      t.add(a),
      a.then(
        () => r(a),
        () => r(a),
      ),
      a
    );
  }
  function i(o) {
    if (!t.size) return ia(!0);
    const a = Promise.allSettled(Array.from(t)).then(() => !0);
    if (!o) return a;
    const c = [a, new Promise((u) => setTimeout(() => u(!1), o))];
    return Promise.race(c);
  }
  return {
    get $() {
      return Array.from(t);
    },
    add: s,
    drain: i,
  };
}
const ly = 60 * 1e3;
function wf(e, t = Date.now()) {
  const n = parseInt(`${e}`, 10);
  if (!isNaN(n)) return n * 1e3;
  const r = Date.parse(`${e}`);
  return isNaN(r) ? ly : r - t;
}
function dy(e, t) {
  return e[t] || e.all || 0;
}
function fy(e, t, n = Date.now()) {
  return dy(e, t) > n;
}
function py(e, { statusCode: t, headers: n }, r = Date.now()) {
  const s = { ...e },
    i = n?.["x-sentry-rate-limits"],
    o = n?.["retry-after"];
  if (i)
    for (const a of i.trim().split(",")) {
      const [c, u, , , d] = a.split(":", 5),
        l = parseInt(c, 10),
        p = (isNaN(l) ? 60 : l) * 1e3;
      if (!u) s.all = r + p;
      else
        for (const f of u.split(";"))
          f === "metric_bucket"
            ? (!d || d.split(";").includes("custom")) && (s[f] = r + p)
            : (s[f] = r + p);
    }
  else o ? (s.all = r + wf(o, r)) : t === 429 && (s.all = r + 60 * 1e3);
  return s;
}
const hy = 64;
function If(e, t, n = uy(e.bufferSize || hy)) {
  let r = {};
  const s = (o) => n.drain(o);
  function i(o) {
    const a = [];
    if (
      (Vt(o, (l, p) => {
        const f = hu(p);
        fy(r, f) ? e.recordDroppedEvent("ratelimit_backoff", f) : a.push(l);
      }),
      a.length === 0)
    )
      return Promise.resolve({});
    const c = Mt(o[0], a),
      u = (l) => {
        Vt(c, (p, f) => {
          e.recordDroppedEvent(l, hu(f));
        });
      },
      d = () =>
        t({ body: Rs(c) }).then(
          (l) => (
            l.statusCode !== void 0 &&
              (l.statusCode < 200 || l.statusCode >= 300) &&
              N &&
              S.warn(
                `Sentry responded with status code ${l.statusCode} to sent event.`,
              ),
            (r = py(r, l)),
            l
          ),
          (l) => {
            throw (
              u("network_error"),
              N && S.error("Encountered error running transport request:", l),
              l
            );
          },
        );
    return n.add(d).then(
      (l) => l,
      (l) => {
        if (l === Tf)
          return (
            N && S.error("Skipped sending event because buffer is full."),
            u("queue_overflow"),
            Promise.resolve({})
          );
        throw l;
      },
    );
  }
  return { send: i, flush: s };
}
const Hi = 100,
  Wi = 5e3,
  my = 36e5;
function gy(e) {
  function t(...n) {
    N && S.log("[Offline]:", ...n);
  }
  return (n) => {
    const r = e(n);
    if (!n.createStore)
      throw new Error("No `createStore` function was provided");
    const s = n.createStore(n);
    let i = Wi,
      o;
    function a(l, p, f) {
      return pu(l, ["client_report"])
        ? !1
        : n.shouldStore
          ? n.shouldStore(l, p, f)
          : !0;
    }
    function c(l) {
      (o && clearTimeout(o),
        (o = setTimeout(async () => {
          o = void 0;
          const p = await s.shift();
          p &&
            (t("Attempting to send previously queued event"),
            (p[0].sent_at = new Date().toISOString()),
            d(p, !0).catch((f) => {
              t("Failed to retry sending", f);
            }));
        }, l)),
        typeof o != "number" && o.unref && o.unref());
    }
    function u() {
      o || (c(i), (i = Math.min(i * 2, my)));
    }
    async function d(l, p = !1) {
      if (!p && pu(l, ["replay_event", "replay_recording"]))
        return (await s.push(l), c(Hi), {});
      try {
        if (n.shouldSend && (await n.shouldSend(l)) === !1)
          throw new Error(
            "Envelope not sent because `shouldSend` callback returned false",
          );
        const f = await r.send(l);
        let h = Hi;
        if (f) {
          if (f.headers?.["retry-after"]) h = wf(f.headers["retry-after"]);
          else if (f.headers?.["x-sentry-rate-limits"]) h = 6e4;
          else if ((f.statusCode || 0) >= 400) return f;
        }
        return (c(h), (i = Wi), f);
      } catch (f) {
        if (await a(l, f, i))
          return (
            p ? await s.unshift(l) : await s.push(l),
            u(),
            t("Error sending. Event queued.", f),
            {}
          );
        throw f;
      }
    }
    return (
      n.flushAtStartup && u(),
      { send: d, flush: (l) => (l === void 0 && ((i = Wi), c(Hi)), r.flush(l)) }
    );
  };
}
function kf(e, t) {
  let n;
  return (
    Vt(
      e,
      (r, s) => (t.includes(s) && (n = Array.isArray(r) ? r[1] : void 0), !!n),
    ),
    n
  );
}
function _y(e, t) {
  return (n) => {
    const r = e(n);
    return {
      ...r,
      send: async (s) => {
        const i = kf(s, ["event", "transaction", "profile", "replay_event"]);
        return (i && (i.release = t), r.send(s));
      },
    };
  };
}
function Sy(e, t) {
  return Mt(t ? { ...e[0], dsn: t } : e[0], e[1]);
}
function yy(e, t) {
  return (n) => {
    const r = e(n),
      s = new Map();
    function i(c, u) {
      const d = u ? `${c}:${u}` : c;
      let l = s.get(d);
      if (!l) {
        const p = Dm(c);
        if (!p) return;
        const f = Rd(p, n.tunnel);
        ((l = u ? _y(e, u)({ ...n, url: f }) : e({ ...n, url: f })),
          s.set(d, l));
      }
      return [c, l];
    }
    async function o(c) {
      function u(f) {
        const h = f?.length ? f : ["event"];
        return kf(c, h);
      }
      const d = t({ envelope: c, getEvent: u })
          .map((f) =>
            typeof f == "string" ? i(f, void 0) : i(f.dsn, f.release),
          )
          .filter((f) => !!f),
        l = d.length ? d : [["", r]];
      return (await Promise.all(l.map(([f, h]) => h.send(Sy(c, f)))))[0];
    }
    async function a(c) {
      const u = [...s.values(), r];
      return (await Promise.all(u.map((l) => l.flush(c)))).every((l) => l);
    }
    return { send: o, flush: a };
  };
}
const by = "thismessage:/";
function Ia(e) {
  return "isRelative" in e;
}
function ka(e, t) {
  const n = e.indexOf("://") <= 0 && e.indexOf("//") !== 0,
    r = n ? by : void 0;
  try {
    if ("canParse" in URL && !URL.canParse(e, r)) return;
    const s = new URL(e, r);
    return n
      ? { isRelative: n, pathname: s.pathname, search: s.search, hash: s.hash }
      : s;
  } catch {}
}
function Ey(e) {
  if (Ia(e)) return e.pathname;
  const t = new URL(e);
  return (
    (t.search = ""),
    (t.hash = ""),
    ["80", "443"].includes(t.port) && (t.port = ""),
    t.password && (t.password = "%filtered%"),
    t.username && (t.username = "%filtered%"),
    t.toString()
  );
}
function ln(e) {
  if (!e) return {};
  const t = e.match(
    /^(([^:/?#]+):)?(\/\/([^/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?$/,
  );
  if (!t) return {};
  const n = t[6] || "",
    r = t[8] || "";
  return {
    host: t[4],
    path: t[5],
    protocol: t[2],
    search: n,
    hash: r,
    relative: t[5] + n + r,
  };
}
function Cf(e) {
  return e.split(/[?#]/, 1)[0];
}
function vy(e, t) {
  const n = t?.getDsn(),
    r = t?.getOptions().tunnel;
  return wy(e, n) || Ty(e, r);
}
function Ty(e, t) {
  return t ? ku(e) === ku(t) : !1;
}
function wy(e, t) {
  const n = ka(e);
  return !n || Ia(n)
    ? !1
    : t
      ? n.host.includes(t.host) && /(^|&|\?)sentry_key=/.test(n.search)
      : !1;
}
function ku(e) {
  return e[e.length - 1] === "/" ? e.slice(0, -1) : e;
}
function Rf(e, ...t) {
  const n = new String(String.raw(e, ...t));
  return (
    (n.__sentry_template_string__ = e
      .join("\0")
      .replace(/%/g, "%%")
      .replace(/\0/g, "%s")),
    (n.__sentry_template_values__ = t),
    n
  );
}
const Iy = Rf;
function ky(e) {
  "aggregates" in e
    ? e.attrs?.ip_address === void 0 &&
      (e.attrs = { ...e.attrs, ip_address: "{{auto}}" })
    : e.ipAddress === void 0 && (e.ipAddress = "{{auto}}");
}
function Cy(e, t, n = [t], r = "npm") {
  const s = e._metadata || {};
  (s.sdk ||
    (s.sdk = {
      name: `sentry.javascript.${t}`,
      packages: n.map((i) => ({ name: `${r}:@sentry/${i}`, version: bs })),
      version: bs,
    }),
    (e._metadata = s));
}
function Ca(e = {}) {
  const t = e.client || W();
  if (!Od() || !t) return {};
  const n = ea(),
    r = ta(n);
  if (r.getTraceData) return r.getTraceData(e);
  const s = e.scope || ue(),
    i = e.span || Pe(),
    o = i ? Ld(i) : Ry(s),
    a = i ? Ct(i) : ra(t, s),
    c = Pm(a);
  if (!Fm.test(o))
    return (
      S.warn("Invalid sentry-trace data. Cannot generate trace data"),
      {}
    );
  const d = { "sentry-trace": o, baggage: c };
  if (e.propagateTraceparent) {
    const l = i ? Bm(i) : xy(s);
    l && (d.traceparent = l);
  }
  return d;
}
function Ry(e) {
  const {
    traceId: t,
    sampled: n,
    propagationSpanId: r,
  } = e.getPropagationContext();
  return Um(t, r, n);
}
function xy(e) {
  const {
    traceId: t,
    sampled: n,
    propagationSpanId: r,
  } = e.getPropagationContext();
  return Hm(t, r, n);
}
const Ay = 100;
function ht(e, t) {
  const n = W(),
    r = Cn();
  if (!n) return;
  const { beforeBreadcrumb: s = null, maxBreadcrumbs: i = Ay } = n.getOptions();
  if (i <= 0) return;
  const a = { timestamp: ni(), ...e },
    c = s ? si(() => s(a, t)) : a;
  c !== null &&
    (n.emit && n.emit("beforeAddBreadcrumb", c, t), r.addBreadcrumb(c, i));
}
let Cu;
const My = "FunctionToString",
  Ru = new WeakMap(),
  Ny = () => ({
    name: My,
    setupOnce() {
      Cu = Function.prototype.toString;
      try {
        Function.prototype.toString = function (...e) {
          const t = $d(this),
            n = Ru.has(W()) && t !== void 0 ? t : this;
          return Cu.apply(n, e);
        };
      } catch {}
    },
    setup(e) {
      Ru.set(e, !0);
    },
  }),
  xf = Ny,
  Oy = [
    /^Script error\.?$/,
    /^Javascript error: Script error\.? on line 0$/,
    /^ResizeObserver loop completed with undelivered notifications.$/,
    /^Cannot redefine property: googletag$/,
    /^Can't find variable: gmo$/,
    /^undefined is not an object \(evaluating 'a\.[A-Z]'\)$/,
    `can't redefine non-configurable property "solana"`,
    "vv().getRestrictions is not a function. (In 'vv().getRestrictions(1,a)', 'vv().getRestrictions' is undefined)",
    "Can't find variable: _AutofillCallbackHandler",
    /^Non-Error promise rejection captured with value: Object Not Found Matching Id:\d+, MethodName:simulateEvent, ParamCount:\d+$/,
    /^Java exception was raised during method invocation$/,
  ],
  Ly = "EventFilters",
  Af = (e = {}) => {
    let t;
    return {
      name: Ly,
      setup(n) {
        const r = n.getOptions();
        t = xu(e, r);
      },
      processEvent(n, r, s) {
        if (!t) {
          const i = s.getOptions();
          t = xu(e, i);
        }
        return $y(n, t) ? null : n;
      },
    };
  },
  Mf = (e = {}) => ({ ...Af(e), name: "InboundFilters" });
function xu(e = {}, t = {}) {
  return {
    allowUrls: [...(e.allowUrls || []), ...(t.allowUrls || [])],
    denyUrls: [...(e.denyUrls || []), ...(t.denyUrls || [])],
    ignoreErrors: [
      ...(e.ignoreErrors || []),
      ...(t.ignoreErrors || []),
      ...(e.disableErrorDefaults ? [] : Oy),
    ],
    ignoreTransactions: [
      ...(e.ignoreTransactions || []),
      ...(t.ignoreTransactions || []),
    ],
  };
}
function $y(e, t) {
  if (e.type) {
    if (e.type === "transaction" && Py(e, t.ignoreTransactions))
      return (
        N &&
          S.warn(`Event dropped due to being matched by \`ignoreTransactions\` option.
Event: ${Lt(e)}`),
        !0
      );
  } else {
    if (Dy(e, t.ignoreErrors))
      return (
        N &&
          S.warn(`Event dropped due to being matched by \`ignoreErrors\` option.
Event: ${Lt(e)}`),
        !0
      );
    if (Hy(e))
      return (
        N &&
          S.warn(`Event dropped due to not having an error message, error type or stacktrace.
Event: ${Lt(e)}`),
        !0
      );
    if (Fy(e, t.denyUrls))
      return (
        N &&
          S.warn(`Event dropped due to being matched by \`denyUrls\` option.
Event: ${Lt(e)}.
Url: ${Ms(e)}`),
        !0
      );
    if (!By(e, t.allowUrls))
      return (
        N &&
          S.warn(`Event dropped due to not being matched by \`allowUrls\` option.
Event: ${Lt(e)}.
Url: ${Ms(e)}`),
        !0
      );
  }
  return !1;
}
function Dy(e, t) {
  return t?.length ? _f(e).some((n) => it(n, t)) : !1;
}
function Py(e, t) {
  if (!t?.length) return !1;
  const n = e.transaction;
  return n ? it(n, t) : !1;
}
function Fy(e, t) {
  if (!t?.length) return !1;
  const n = Ms(e);
  return n ? it(n, t) : !1;
}
function By(e, t) {
  if (!t?.length) return !0;
  const n = Ms(e);
  return n ? it(n, t) : !0;
}
function Uy(e = []) {
  for (let t = e.length - 1; t >= 0; t--) {
    const n = e[t];
    if (n && n.filename !== "<anonymous>" && n.filename !== "[native code]")
      return n.filename || null;
  }
  return null;
}
function Ms(e) {
  try {
    const n = [...(e.exception?.values ?? [])]
      .reverse()
      .find(
        (r) =>
          r.mechanism?.parent_id === void 0 && r.stacktrace?.frames?.length,
      )?.stacktrace?.frames;
    return n ? Uy(n) : null;
  } catch {
    return (N && S.error(`Cannot extract url for event ${Lt(e)}`), null);
  }
}
function Hy(e) {
  return e.exception?.values?.length
    ? !e.message &&
        !e.exception.values.some(
          (t) => t.stacktrace || (t.type && t.type !== "Error") || t.value,
        )
    : !1;
}
function Wy(e, t, n, r, s, i) {
  if (!s.exception?.values || !i || !Es(i.originalException, Error)) return;
  const o =
    s.exception.values.length > 0
      ? s.exception.values[s.exception.values.length - 1]
      : void 0;
  o &&
    (s.exception.values = vo(
      e,
      t,
      r,
      i.originalException,
      n,
      s.exception.values,
      o,
      0,
    ));
}
function vo(e, t, n, r, s, i, o, a) {
  if (i.length >= n + 1) return i;
  let c = [...i];
  if (Es(r[s], Error)) {
    Au(o, a);
    const u = e(t, r[s]),
      d = c.length;
    (Mu(u, s, d, a), (c = vo(e, t, n, r[s], s, [u, ...c], u, d)));
  }
  return (
    Array.isArray(r.errors) &&
      r.errors.forEach((u, d) => {
        if (Es(u, Error)) {
          Au(o, a);
          const l = e(t, u),
            p = c.length;
          (Mu(l, `errors[${d}]`, p, a),
            (c = vo(e, t, n, u, s, [l, ...c], l, p)));
        }
      }),
    c
  );
}
function Au(e, t) {
  e.mechanism = {
    handled: !0,
    type: "auto.core.linked_errors",
    ...e.mechanism,
    ...(e.type === "AggregateError" && { is_exception_group: !0 }),
    exception_id: t,
  };
}
function Mu(e, t, n, r) {
  e.mechanism = {
    handled: !0,
    ...e.mechanism,
    type: "chained",
    source: t,
    exception_id: n,
    parent_id: r,
  };
}
const Nf = new Map(),
  Nu = new Set();
function zy(e) {
  if (ne._sentryModuleMetadata)
    for (const t of Object.keys(ne._sentryModuleMetadata)) {
      const n = ne._sentryModuleMetadata[t];
      if (Nu.has(t)) continue;
      Nu.add(t);
      const r = e(t);
      for (const s of r.reverse())
        if (s.filename) {
          Nf.set(s.filename, n);
          break;
        }
    }
}
function jy(e, t) {
  return (zy(e), Nf.get(t));
}
function Of(e, t) {
  t.exception?.values?.forEach((n) => {
    n.stacktrace?.frames?.forEach((r) => {
      if (!r.filename || r.module_metadata) return;
      const s = jy(e, r.filename);
      s && (r.module_metadata = s);
    });
  });
}
function Lf(e) {
  e.exception?.values?.forEach((t) => {
    t.stacktrace?.frames?.forEach((n) => {
      delete n.module_metadata;
    });
  });
}
const qy = () => ({
  name: "ModuleMetadata",
  setup(e) {
    (e.on("beforeEnvelope", (t) => {
      Vt(t, (n, r) => {
        if (r === "event") {
          const s = Array.isArray(n) ? n[1] : void 0;
          s && (Lf(s), (n[1] = s));
        }
      });
    }),
      e.on("applyFrameMetadata", (t) => {
        if (t.type) return;
        const n = e.getOptions().stackParser;
        Of(n, t);
      }));
  },
});
function Ra(e) {
  const t = "console";
  (_r(t, e), Sr(t, Gy));
}
function Gy() {
  "console" in ne &&
    oa.forEach(function (e) {
      e in ne.console &&
        Xe(ne.console, e, function (t) {
          return (
            (Fc[e] = t),
            function (...n) {
              (Ht("console", { args: n, level: e }),
                Fc[e]?.apply(ne.console, n));
            }
          );
        });
    });
}
function $f(e) {
  return e === "warn"
    ? "warning"
    : ["fatal", "error", "warning", "log", "info", "debug"].includes(e)
      ? e
      : "log";
}
const Vy = "CaptureConsole",
  Yy = (e = {}) => {
    const t = e.levels || oa,
      n = e.handled ?? !0;
    return {
      name: Vy,
      setup(r) {
        "console" in ne &&
          Ra(({ args: s, level: i }) => {
            W() !== r || !t.includes(i) || Ky(s, i, n);
          });
      },
    };
  },
  Xy = Yy;
function Ky(e, t, n) {
  const r = { level: $f(t), extra: { arguments: e } };
  qe((s) => {
    if (
      (s.addEventProcessor(
        (a) => (
          (a.logger = "console"),
          Gt(a, { handled: n, type: "auto.core.capture_console" }),
          a
        ),
      ),
      t === "assert")
    ) {
      if (!e[0]) {
        const a = `Assertion failed: ${vs(e.slice(1), " ") || "console.assert"}`;
        (s.setExtra("arguments", e.slice(1)), Ts(a, r));
      }
      return;
    }
    const i = e.find((a) => a instanceof Error);
    if (i) {
      Qn(i, r);
      return;
    }
    const o = vs(e, " ");
    Ts(o, r);
  });
}
const Jy = "Dedupe",
  Zy = () => {
    let e;
    return {
      name: Jy,
      processEvent(t) {
        if (t.type) return t;
        try {
          if (Qy(t, e))
            return (
              N &&
                S.warn(
                  "Event dropped due to being a duplicate of previously captured event.",
                ),
              null
            );
        } catch {}
        return (e = t);
      },
    };
  },
  Df = Zy;
function Qy(e, t) {
  return t ? !!(eb(e, t) || tb(e, t)) : !1;
}
function eb(e, t) {
  const n = e.message,
    r = t.message;
  return !(
    (!n && !r) ||
    (n && !r) ||
    (!n && r) ||
    n !== r ||
    !Ff(e, t) ||
    !Pf(e, t)
  );
}
function tb(e, t) {
  const n = Ou(t),
    r = Ou(e);
  return !(
    !n ||
    !r ||
    n.type !== r.type ||
    n.value !== r.value ||
    !Ff(e, t) ||
    !Pf(e, t)
  );
}
function Pf(e, t) {
  let n = lo(e),
    r = lo(t);
  if (!n && !r) return !0;
  if ((n && !r) || (!n && r) || ((n = n), (r = r), r.length !== n.length))
    return !1;
  for (let s = 0; s < r.length; s++) {
    const i = r[s],
      o = n[s];
    if (
      i.filename !== o.filename ||
      i.lineno !== o.lineno ||
      i.colno !== o.colno ||
      i.function !== o.function
    )
      return !1;
  }
  return !0;
}
function Ff(e, t) {
  let n = e.fingerprint,
    r = t.fingerprint;
  if (!n && !r) return !0;
  if ((n && !r) || (!n && r)) return !1;
  ((n = n), (r = r));
  try {
    return n.join("") === r.join("");
  } catch {
    return !1;
  }
}
function Ou(e) {
  return e.exception?.values?.[0];
}
const nb = "ExtraErrorData",
  rb = (e = {}) => {
    const { depth: t = 3, captureErrorCause: n = !0 } = e;
    return {
      name: nb,
      processEvent(r, s, i) {
        const { maxValueLength: o = 250 } = i.getOptions();
        return ib(r, s, t, n, o);
      },
    };
  },
  sb = rb;
function ib(e, t = {}, n, r, s) {
  if (!t.originalException || !Bt(t.originalException)) return e;
  const i = t.originalException.name || t.originalException.constructor.name,
    o = Bf(t.originalException, r, s);
  if (o) {
    const a = { ...e.contexts },
      c = Ko(o, n);
    return (
      qt(c) && (aa(c, "__sentry_skip_normalization__", !0), (a[i] = c)),
      { ...e, contexts: a }
    );
  }
  return e;
}
function Bf(e, t, n) {
  try {
    const r = [
        "name",
        "message",
        "stack",
        "line",
        "column",
        "fileName",
        "lineNumber",
        "columnNumber",
        "toJSON",
      ],
      s = {};
    for (const i of Object.keys(e)) {
      if (r.indexOf(i) !== -1) continue;
      const o = e[i];
      s[i] = Bt(o) || typeof o == "string" ? Dd(`${o}`, n) : o;
    }
    if (t && e.cause !== void 0)
      if (Bt(e.cause)) {
        const i = e.cause.name || e.cause.constructor.name;
        s.cause = { [i]: Bf(e.cause, !1, n) };
      } else s.cause = e.cause;
    if (typeof e.toJSON == "function") {
      const i = e.toJSON();
      for (const o of Object.keys(i)) {
        const a = i[o];
        s[o] = Bt(a) ? a.toString() : a;
      }
    }
    return s;
  } catch (r) {
    N && S.error("Unable to extract extra data from the Error object:", r);
  }
  return null;
}
function ob(e, t) {
  let n = 0;
  for (let r = e.length - 1; r >= 0; r--) {
    const s = e[r];
    s === "."
      ? e.splice(r, 1)
      : s === ".."
        ? (e.splice(r, 1), n++)
        : n && (e.splice(r, 1), n--);
  }
  if (t) for (; n--; n) e.unshift("..");
  return e;
}
const ab =
  /^(\S+:\\|\/?)([\s\S]*?)((?:\.{1,2}|[^/\\]+?|)(\.[^./\\]*|))(?:[/\\]*)$/;
function cb(e) {
  const t = e.length > 1024 ? `<truncated>${e.slice(-1024)}` : e,
    n = ab.exec(t);
  return n ? n.slice(1) : [];
}
function Lu(...e) {
  let t = "",
    n = !1;
  for (let r = e.length - 1; r >= -1 && !n; r--) {
    const s = r >= 0 ? e[r] : "/";
    s && ((t = `${s}/${t}`), (n = s.charAt(0) === "/"));
  }
  return (
    (t = ob(
      t.split("/").filter((r) => !!r),
      !n,
    ).join("/")),
    (n ? "/" : "") + t || "."
  );
}
function $u(e) {
  let t = 0;
  for (; t < e.length && e[t] === ""; t++);
  let n = e.length - 1;
  for (; n >= 0 && e[n] === ""; n--);
  return t > n ? [] : e.slice(t, n - t + 1);
}
function ub(e, t) {
  ((e = Lu(e).slice(1)), (t = Lu(t).slice(1)));
  const n = $u(e.split("/")),
    r = $u(t.split("/")),
    s = Math.min(n.length, r.length);
  let i = s;
  for (let a = 0; a < s; a++)
    if (n[a] !== r[a]) {
      i = a;
      break;
    }
  let o = [];
  for (let a = i; a < n.length; a++) o.push("..");
  return ((o = o.concat(r.slice(i))), o.join("/"));
}
function lb(e, t) {
  return cb(e)[2] || "";
}
const db = "RewriteFrames",
  fb = (e = {}) => {
    const t = e.root,
      n = e.prefix || "app:///",
      r = "window" in ne && !!ne.window,
      s = e.iteratee || pb({ isBrowser: r, root: t, prefix: n });
    function i(a) {
      try {
        return {
          ...a,
          exception: {
            ...a.exception,
            values: a.exception.values.map((c) => ({
              ...c,
              ...(c.stacktrace && { stacktrace: o(c.stacktrace) }),
            })),
          },
        };
      } catch {
        return a;
      }
    }
    function o(a) {
      return { ...a, frames: a?.frames?.map((c) => s(c)) };
    }
    return {
      name: db,
      processEvent(a) {
        let c = a;
        return (
          a.exception && Array.isArray(a.exception.values) && (c = i(c)),
          c
        );
      },
    };
  };
function pb({ isBrowser: e, root: t, prefix: n }) {
  return (r) => {
    if (!r.filename) return r;
    const s =
        /^[a-zA-Z]:\\/.test(r.filename) ||
        (r.filename.includes("\\") && !r.filename.includes("/")),
      i = /^\//.test(r.filename);
    if (e) {
      if (t) {
        const o = r.filename;
        o.indexOf(t) === 0 && (r.filename = o.replace(t, n));
      }
    } else if (s || i) {
      const o = s
          ? r.filename.replace(/^[a-zA-Z]:/, "").replace(/\\/g, "/")
          : r.filename,
        a = t ? ub(t, o) : lb(o);
      r.filename = `${n}${a}`;
    }
    return r;
  };
}
const hb = [
    "reauthenticate",
    "signInAnonymously",
    "signInWithOAuth",
    "signInWithIdToken",
    "signInWithOtp",
    "signInWithPassword",
    "signInWithSSO",
    "signOut",
    "signUp",
    "verifyOtp",
  ],
  mb = [
    "createUser",
    "deleteUser",
    "listUsers",
    "getUserById",
    "updateUserById",
    "inviteUserByEmail",
  ],
  gb = {
    eq: "eq",
    neq: "neq",
    gt: "gt",
    gte: "gte",
    lt: "lt",
    lte: "lte",
    like: "like",
    "like(all)": "likeAllOf",
    "like(any)": "likeAnyOf",
    ilike: "ilike",
    "ilike(all)": "ilikeAllOf",
    "ilike(any)": "ilikeAnyOf",
    is: "is",
    in: "in",
    cs: "contains",
    cd: "containedBy",
    sr: "rangeGt",
    nxl: "rangeGte",
    sl: "rangeLt",
    nxr: "rangeLte",
    adj: "rangeAdjacent",
    ov: "overlaps",
    fts: "",
    plfts: "plain",
    phfts: "phrase",
    wfts: "websearch",
    not: "not",
  },
  Uf = ["select", "insert", "upsert", "update", "delete"];
function di(e) {
  try {
    e.__SENTRY_INSTRUMENTED__ = !0;
  } catch {}
}
function fi(e) {
  try {
    return e.__SENTRY_INSTRUMENTED__;
  } catch {
    return !1;
  }
}
function _b(e, t = {}) {
  switch (e) {
    case "GET":
      return "select";
    case "POST":
      return t.Prefer?.includes("resolution=") ? "upsert" : "insert";
    case "PATCH":
      return "update";
    case "DELETE":
      return "delete";
    default:
      return "<unknown-op>";
  }
}
function Sb(e, t) {
  if (t === "" || t === "*") return "select(*)";
  if (e === "select") return `select(${t})`;
  if (e === "or" || e.endsWith(".or")) return `${e}${t}`;
  const [n, ...r] = t.split(".");
  let s;
  return (
    n?.startsWith("fts")
      ? (s = "textSearch")
      : n?.startsWith("plfts")
        ? (s = "textSearch[plain]")
        : n?.startsWith("phfts")
          ? (s = "textSearch[phrase]")
          : n?.startsWith("wfts")
            ? (s = "textSearch[websearch]")
            : (s = (n && gb[n]) || "filter"),
    `${s}(${e}, ${r.join(".")})`
  );
}
function Du(e, t = !1) {
  return new Proxy(e, {
    apply(n, r, s) {
      return ba(
        {
          name: `auth ${t ? "(admin) " : ""}${e.name}`,
          attributes: {
            [Ze]: "auto.db.supabase",
            [Rt]: "db",
            "db.system": "postgresql",
            "db.operation": `auth.${t ? "admin." : ""}${e.name}`,
          },
        },
        (i) =>
          Reflect.apply(n, r, s)
            .then(
              (o) => (
                o && typeof o == "object" && "error" in o && o.error
                  ? (i.setStatus({ code: lt }),
                    Qn(o.error, {
                      mechanism: { handled: !1, type: "auto.db.supabase.auth" },
                    }))
                  : i.setStatus({ code: Wm }),
                i.end(),
                o
              ),
            )
            .catch((o) => {
              throw (
                i.setStatus({ code: lt }),
                i.end(),
                Qn(o, {
                  mechanism: { handled: !1, type: "auto.db.supabase.auth" },
                }),
                o
              );
            })
            .then(...s),
      );
    },
  });
}
function yb(e) {
  const t = e.auth;
  if (!(!t || fi(e.auth))) {
    for (const n of hb) {
      const r = t[n];
      r && typeof e.auth[n] == "function" && (e.auth[n] = Du(r));
    }
    for (const n of mb) {
      const r = t.admin[n];
      r &&
        typeof e.auth.admin[n] == "function" &&
        (e.auth.admin[n] = Du(r, !0));
    }
    di(e.auth);
  }
}
function bb(e) {
  fi(e.prototype.from) ||
    ((e.prototype.from = new Proxy(e.prototype.from, {
      apply(t, n, r) {
        const s = Reflect.apply(t, n, r),
          i = s.constructor;
        return (vb(i), s);
      },
    })),
    di(e.prototype.from));
}
function Eb(e) {
  fi(e.prototype.then) ||
    ((e.prototype.then = new Proxy(e.prototype.then, {
      apply(t, n, r) {
        const s = Uf,
          i = n,
          o = _b(i.method, i.headers);
        if (
          !s.includes(o) ||
          !i?.url?.pathname ||
          typeof i.url.pathname != "string"
        )
          return Reflect.apply(t, n, r);
        const a = i.url.pathname.split("/"),
          c = a.length > 0 ? a[a.length - 1] : "",
          u = [];
        for (const [f, h] of i.url.searchParams.entries()) u.push(Sb(f, h));
        const d = Object.create(null);
        if (qt(i.body)) for (const [f, h] of Object.entries(i.body)) d[f] = h;
        const l = `${o === "select" ? "" : `${o}${d ? "(...) " : ""}`}${u.join(" ")} from(${c})`,
          p = {
            "db.table": c,
            "db.schema": i.schema,
            "db.url": i.url.origin,
            "db.sdk": i.headers["X-Client-Info"],
            "db.system": "postgresql",
            "db.operation": o,
            [Ze]: "auto.db.supabase",
            [Rt]: "db",
          };
        return (
          u.length && (p["db.query"] = u),
          Object.keys(d).length && (p["db.body"] = d),
          ba({ name: l, attributes: p }, (f) =>
            Reflect.apply(t, n, [])
              .then(
                (h) => {
                  if (
                    (f &&
                      (h &&
                        typeof h == "object" &&
                        "status" in h &&
                        er(f, h.status || 500),
                      f.end()),
                    h.error)
                  ) {
                    const _ = new Error(h.error.message);
                    (h.error.code && (_.code = h.error.code),
                      h.error.details && (_.details = h.error.details));
                    const y = {};
                    (u.length && (y.query = u),
                      Object.keys(d).length && (y.body = d),
                      Qn(
                        _,
                        (M) => (
                          M.addEventProcessor(
                            (w) => (
                              Gt(w, {
                                handled: !1,
                                type: "auto.db.supabase.postgres",
                              }),
                              w
                            ),
                          ),
                          M.setContext("supabase", y),
                          M
                        ),
                      ));
                  }
                  const m = {
                      type: "supabase",
                      category: `db.${o}`,
                      message: l,
                    },
                    g = {};
                  return (
                    u.length && (g.query = u),
                    Object.keys(d).length && (g.body = d),
                    Object.keys(g).length && (m.data = g),
                    ht(m),
                    h
                  );
                },
                (h) => {
                  throw (f && (er(f, 500), f.end()), h);
                },
              )
              .then(...r),
          )
        );
      },
    })),
    di(e.prototype.then));
}
function vb(e) {
  for (const t of Uf)
    fi(e.prototype[t]) ||
      ((e.prototype[t] = new Proxy(e.prototype[t], {
        apply(n, r, s) {
          const i = Reflect.apply(n, r, s),
            o = i.constructor;
          return (
            N && S.log(`Instrumenting ${t} operation's PostgRESTFilterBuilder`),
            Eb(o),
            i
          );
        },
      })),
      di(e.prototype[t]));
}
const Hf = (e) => {
    if (!e) {
      N &&
        S.warn(
          "Supabase integration was not installed because no Supabase client was provided.",
        );
      return;
    }
    const t = e.constructor === Function ? e : e.constructor;
    (bb(t), yb(e));
  },
  Tb = "Supabase",
  wb = (e) => ({
    setupOnce() {
      Hf(e);
    },
    name: Tb,
  }),
  Ib = (e) => wb(e.supabaseClient),
  kb = 10,
  Cb = "ZodErrors";
function Rb(e) {
  return Bt(e) && e.name === "ZodError" && Array.isArray(e.issues);
}
function xb(e) {
  return {
    ...e,
    path: "path" in e && Array.isArray(e.path) ? e.path.join(".") : void 0,
    keys: "keys" in e ? JSON.stringify(e.keys) : void 0,
    unionErrors: "unionErrors" in e ? JSON.stringify(e.unionErrors) : void 0,
  };
}
function Ab(e) {
  return e.map((t) => (typeof t == "number" ? "<array>" : t)).join(".");
}
function Mb(e) {
  const t = new Set();
  for (const r of e.issues) {
    const s = Ab(r.path);
    s.length > 0 && t.add(s);
  }
  const n = Array.from(t);
  if (n.length === 0) {
    let r = "variable";
    if (e.issues.length > 0) {
      const s = e.issues[0];
      s !== void 0 &&
        "expected" in s &&
        typeof s.expected == "string" &&
        (r = s.expected);
    }
    return `Failed to validate ${r}`;
  }
  return `Failed to validate keys: ${Dd(n.join(", "), 100)}`;
}
function Nb(e, t = !1, n, r) {
  if (
    !n.exception?.values ||
    !r.originalException ||
    !Rb(r.originalException) ||
    r.originalException.issues.length === 0
  )
    return n;
  try {
    const i = (
      t ? r.originalException.issues : r.originalException.issues.slice(0, e)
    ).map(xb);
    return (
      t &&
        (Array.isArray(r.attachments) || (r.attachments = []),
        r.attachments.push({
          filename: "zod_issues.json",
          data: JSON.stringify({ issues: i }),
        })),
      {
        ...n,
        exception: {
          ...n.exception,
          values: [
            { ...n.exception.values[0], value: Mb(r.originalException) },
            ...n.exception.values.slice(1),
          ],
        },
        extra: { ...n.extra, "zoderror.issues": i.slice(0, e) },
      }
    );
  } catch (s) {
    return {
      ...n,
      extra: {
        ...n.extra,
        "zoderrors sentry integration parse error": {
          message:
            "an exception was thrown while processing ZodError within applyZodErrorsToEvent()",
          error:
            s instanceof Error
              ? `${s.name}: ${s.message}
${s.stack}`
              : "unknown",
        },
      },
    };
  }
}
const Ob = (e = {}) => {
    const t = e.limit ?? kb;
    return {
      name: Cb,
      processEvent(n, r) {
        return Nb(t, e.saveZodIssuesAsAttachment, n, r);
      },
    };
  },
  Lb = Ob,
  $b = (e) => ({
    name: "ThirdPartyErrorsFilter",
    setup(t) {
      (t.on("beforeEnvelope", (n) => {
        Vt(n, (r, s) => {
          if (s === "event") {
            const i = Array.isArray(r) ? r[1] : void 0;
            i && (Lf(i), (r[1] = i));
          }
        });
      }),
        t.on("applyFrameMetadata", (n) => {
          if (n.type) return;
          const r = t.getOptions().stackParser;
          Of(r, n);
        }));
    },
    processEvent(t) {
      const n = Db(t);
      if (n) {
        const r =
          e.behaviour === "drop-error-if-contains-third-party-frames" ||
          e.behaviour === "apply-tag-if-contains-third-party-frames"
            ? "some"
            : "every";
        if (n[r]((i) => !i.some((o) => e.filterKeys.includes(o)))) {
          if (
            e.behaviour === "drop-error-if-contains-third-party-frames" ||
            e.behaviour ===
              "drop-error-if-exclusively-contains-third-party-frames"
          )
            return null;
          t.tags = { ...t.tags, third_party_code: !0 };
        }
      }
      return t;
    },
  });
function Db(e) {
  const t = lo(e);
  if (t)
    return t
      .filter((n) => !!n.filename && (n.lineno ?? n.colno) != null)
      .map((n) =>
        n.module_metadata
          ? Object.keys(n.module_metadata)
              .filter((r) => r.startsWith(Pu))
              .map((r) => r.slice(Pu.length))
          : [],
      );
}
const Pu = "_sentryBundlerPluginAppKey:",
  Pb = 100,
  Fb = 10,
  Br = "flag.evaluation.";
function Er(e) {
  const n = ue().getScopeData().contexts.flags,
    r = n ? n.values : [];
  return (
    r.length &&
      (e.contexts === void 0 && (e.contexts = {}),
      (e.contexts.flags = { values: [...r] })),
    e
  );
}
function mn(e, t, n = Pb) {
  const r = ue().getScopeData().contexts;
  r.flags || (r.flags = { values: [] });
  const s = r.flags.values;
  Bb(s, e, t, n);
}
function Bb(e, t, n, r) {
  if (typeof n != "boolean") return;
  if (e.length > r) {
    N &&
      S.error(
        `[Feature Flags] insertToFlagBuffer called on a buffer larger than maxSize=${r}`,
      );
    return;
  }
  const s = e.findIndex((i) => i.flag === t);
  (s !== -1 && e.splice(s, 1),
    e.length === r && e.shift(),
    e.push({ flag: t, result: n }));
}
function gn(e, t, n = Fb) {
  if (typeof t != "boolean") return;
  const r = Pe();
  if (!r) return;
  const s = ee(r).data;
  if (`${Br}${e}` in s) {
    r.setAttribute(`${Br}${e}`, t);
    return;
  }
  Object.keys(s).filter((o) => o.startsWith(Br)).length < n &&
    r.setAttribute(`${Br}${e}`, t);
}
const Ub = () => ({
  name: "FeatureFlags",
  processEvent(e, t, n) {
    return Er(e);
  },
  addFeatureFlag(e, t) {
    (mn(e, t), gn(e, t));
  },
});
function Hb(e, t, n, r, s) {
  if (!e.fetchData) return;
  const { method: i, url: o } = e.fetchData,
    a = Je() && t(o);
  if (e.endTimestamp && a) {
    const f = e.fetchData.__span;
    if (!f) return;
    const h = r[f];
    h && (zb(h, e), delete r[f]);
    return;
  }
  const { spanOrigin: c = "auto.http.browser", propagateTraceparent: u = !1 } =
      typeof s == "object" ? s : { spanOrigin: s },
    d = !!Pe(),
    l = a && d ? yr(qb(o, i, c)) : new pt();
  if (
    ((e.fetchData.__span = l.spanContext().spanId),
    (r[l.spanContext().spanId] = l),
    n(e.fetchData.url))
  ) {
    const f = e.args[0],
      h = e.args[1] || {},
      m = Wb(f, h, Je() && d ? l : void 0, u);
    m && ((e.args[1] = h), (h.headers = m));
  }
  const p = W();
  if (p) {
    const f = {
      input: e.args,
      response: e.response,
      startTimestamp: e.startTimestamp,
      endTimestamp: e.endTimestamp,
    };
    p.emit("beforeOutgoingRequestSpan", l, f);
  }
  return l;
}
function Wb(e, t, n, r) {
  const s = Ca({ span: n, propagateTraceparent: r }),
    i = s["sentry-trace"],
    o = s.baggage,
    a = s.traceparent;
  if (!i) return;
  const c = t.headers || (Pd(e) ? e.headers : void 0);
  if (c)
    if (jb(c)) {
      const u = new Headers(c);
      if (
        (u.get("sentry-trace") || u.set("sentry-trace", i),
        r && a && !u.get("traceparent") && u.set("traceparent", a),
        o)
      ) {
        const d = u.get("baggage");
        d ? Ur(d) || u.set("baggage", `${d},${o}`) : u.set("baggage", o);
      }
      return u;
    } else if (Array.isArray(c)) {
      const u = [...c];
      (c.find((l) => l[0] === "sentry-trace") || u.push(["sentry-trace", i]),
        r &&
          a &&
          !c.find((l) => l[0] === "traceparent") &&
          u.push(["traceparent", a]));
      const d = c.find((l) => l[0] === "baggage" && Ur(l[1]));
      return (o && !d && u.push(["baggage", o]), u);
    } else {
      const u = "sentry-trace" in c ? c["sentry-trace"] : void 0,
        d = "traceparent" in c ? c.traceparent : void 0,
        l = "baggage" in c ? c.baggage : void 0,
        p = l ? (Array.isArray(l) ? [...l] : [l]) : [],
        f = l && (Array.isArray(l) ? l.find((m) => Ur(m)) : Ur(l));
      o && !f && p.push(o);
      const h = {
        ...c,
        "sentry-trace": u ?? i,
        baggage: p.length > 0 ? p.join(",") : void 0,
      };
      return (r && a && !d && (h.traceparent = a), h);
    }
  else return { ...s };
}
function zb(e, t) {
  if (t.response) {
    er(e, t.response.status);
    const n = t.response?.headers?.get("content-length");
    if (n) {
      const r = parseInt(n);
      r > 0 && e.setAttribute("http.response_content_length", r);
    }
  } else t.error && e.setStatus({ code: lt, message: "internal_error" });
  e.end();
}
function Ur(e) {
  return e.split(",").some((t) => t.trim().startsWith(zm));
}
function jb(e) {
  return typeof Headers < "u" && Es(e, Headers);
}
function qb(e, t, n) {
  const r = ka(e);
  return { name: r ? `${t} ${Ey(r)}` : t, attributes: Gb(e, r, t, n) };
}
function Gb(e, t, n, r) {
  const s = {
    url: e,
    type: "fetch",
    "http.method": n,
    [Ze]: r,
    [Rt]: "http.client",
  };
  return (
    t &&
      (Ia(t) || ((s["http.url"] = t.href), (s["server.address"] = t.host)),
      t.search && (s["http.query"] = t.search),
      t.hash && (s["http.fragment"] = t.hash)),
    s
  );
}
function Vb(e, t = {}, n = ue()) {
  const {
      message: r,
      name: s,
      email: i,
      url: o,
      source: a,
      associatedEventId: c,
      tags: u,
    } = e,
    d = {
      contexts: {
        feedback: {
          contact_email: i,
          name: s,
          message: r,
          url: o,
          source: a,
          associated_event_id: c,
        },
      },
      type: "feedback",
      level: "info",
      tags: u,
    },
    l = n?.getClient() || W();
  return (l && l.emit("beforeSendFeedback", d, t), n.captureEvent(d, t));
}
function Rn(e, t, n, r, s) {
  As({ level: e, message: t, attributes: n, severityNumber: s }, r);
}
function Yb(e, t, { scope: n } = {}) {
  Rn("trace", e, t, n);
}
function Xb(e, t, { scope: n } = {}) {
  Rn("debug", e, t, n);
}
function Kb(e, t, { scope: n } = {}) {
  Rn("info", e, t, n);
}
function Jb(e, t, { scope: n } = {}) {
  Rn("warn", e, t, n);
}
function Zb(e, t, { scope: n } = {}) {
  Rn("error", e, t, n);
}
function Qb(e, t, { scope: n } = {}) {
  Rn("fatal", e, t, n);
}
const eE = Object.freeze(
  Object.defineProperty(
    {
      __proto__: null,
      debug: Xb,
      error: Zb,
      fatal: Qb,
      fmt: Iy,
      info: Kb,
      trace: Yb,
      warn: Jb,
    },
    Symbol.toStringTag,
    { value: "Module" },
  ),
);
function To(e, t, n) {
  return "util" in ne && typeof ne.util.format == "function"
    ? ne.util.format(...e)
    : tE(e, t, n);
}
function tE(e, t, n) {
  return e
    .map((r) => (ri(r) ? String(r) : JSON.stringify(Ko(r, t, n))))
    .join(" ");
}
function nE(e) {
  return /%[sdifocO]/.test(e);
}
function rE(e, t) {
  const n = {},
    r = new Array(t.length).fill("{}").join(" ");
  return (
    (n["sentry.message.template"] = `${e} ${r}`),
    t.forEach((s, i) => {
      n[`sentry.message.parameter.${i}`] = s;
    }),
    n
  );
}
const sE = "ConsoleLogs",
  Fu = { [Ze]: "auto.console.logging" },
  iE = (e = {}) => {
    const t = e.levels || oa;
    return {
      name: sE,
      setup(n) {
        const {
          enableLogs: r,
          normalizeDepth: s = 3,
          normalizeMaxBreadth: i = 1e3,
        } = n.getOptions();
        if (!r) {
          N &&
            S.warn(
              "`enableLogs` is not enabled, ConsoleLogs integration disabled",
            );
          return;
        }
        Ra(({ args: o, level: a }) => {
          if (W() !== n || !t.includes(a)) return;
          const c = o[0],
            u = o.slice(1);
          if (a === "assert") {
            if (!c) {
              const f =
                u.length > 0
                  ? `Assertion failed: ${To(u, s, i)}`
                  : "Assertion failed";
              As({ level: "error", message: f, attributes: Fu });
            }
            return;
          }
          const d = a === "log",
            l = o.length > 1 && typeof o[0] == "string" && !nE(o[0]),
            p = { ...Fu, ...(l ? rE(c, u) : {}) };
          As({
            level: d ? "info" : a,
            message: To(o, s, i),
            severityNumber: d ? 10 : void 0,
            attributes: p,
          });
        });
      },
    };
  },
  oE = iE,
  aE = ["trace", "debug", "info", "warn", "error", "fatal"];
function cE(e = {}) {
  const t = new Set(e.levels ?? aE),
    n = e.client;
  return {
    log(r) {
      const {
          type: s,
          level: i,
          message: o,
          args: a,
          tag: c,
          date: u,
          ...d
        } = r,
        l = n || W();
      if (!l) return;
      const p = dE(s, i);
      if (!t.has(p)) return;
      const { normalizeDepth: f = 3, normalizeMaxBreadth: h = 1e3 } =
          l.getOptions(),
        m = [];
      (o && m.push(o), a && a.length > 0 && m.push(To(a, f, h)));
      const g = m.join(" ");
      ((d["sentry.origin"] = "auto.logging.consola"),
        c && (d["consola.tag"] = c),
        s && (d["consola.type"] = s),
        i != null && typeof i == "number" && (d["consola.level"] = i),
        As({ level: p, message: g, attributes: d }));
    },
  };
}
const uE = {
    silent: "trace",
    fatal: "fatal",
    error: "error",
    warn: "warn",
    log: "info",
    info: "info",
    success: "info",
    fail: "error",
    ready: "info",
    start: "info",
    box: "info",
    debug: "debug",
    trace: "trace",
    verbose: "debug",
    critical: "fatal",
    notice: "info",
  },
  lE = { 0: "fatal", 1: "warn", 2: "info", 3: "info", 4: "debug", 5: "trace" };
function dE(e, t) {
  if (e === "verbose") return "debug";
  if (e === "silent") return "trace";
  if (e) {
    const n = uE[e];
    if (n) return n;
  }
  if (typeof t == "number") {
    const n = lE[t];
    if (n) return n;
  }
  return "info";
}
function Wf(e) {
  if (e !== void 0)
    return e >= 400 && e < 500 ? "warning" : e >= 500 ? "error" : void 0;
}
const Ns = ne;
function fE() {
  if (!("fetch" in Ns)) return !1;
  try {
    return (
      new Headers(),
      new Request("http://www.example.com"),
      new Response(),
      !0
    );
  } catch {
    return !1;
  }
}
function Bu(e) {
  return (
    e && /^function\s+\w+\(\)\s+\{\s+\[native code\]\s+\}$/.test(e.toString())
  );
}
function zf() {
  if (typeof EdgeRuntime == "string") return !0;
  if (!fE()) return !1;
  if (Bu(Ns.fetch)) return !0;
  let e = !1;
  const t = Ns.document;
  if (t && typeof t.createElement == "function")
    try {
      const n = t.createElement("iframe");
      ((n.hidden = !0),
        t.head.appendChild(n),
        n.contentWindow?.fetch && (e = Bu(n.contentWindow.fetch)),
        t.head.removeChild(n));
    } catch (n) {
      N &&
        S.warn(
          "Could not create sandbox iframe for pure fetch check, bailing to window.fetch: ",
          n,
        );
    }
  return e;
}
function pE() {
  return "ReportingObserver" in Ns;
}
function xa(e, t) {
  const n = "fetch";
  (_r(n, e), Sr(n, () => jf(void 0, t)));
}
function hE(e) {
  const t = "fetch-body-resolved";
  (_r(t, e), Sr(t, () => jf(gE)));
}
function jf(e, t = !1) {
  (t && !zf()) ||
    Xe(ne, "fetch", function (n) {
      return function (...r) {
        const s = new Error(),
          { method: i, url: o } = _E(r),
          a = {
            args: r,
            fetchData: { method: i, url: o },
            startTimestamp: ke() * 1e3,
            virtualError: s,
            headers: SE(r),
          };
        return (
          e || Ht("fetch", { ...a }),
          n.apply(ne, r).then(
            async (c) => (
              e
                ? e(c)
                : Ht("fetch", { ...a, endTimestamp: ke() * 1e3, response: c }),
              c
            ),
            (c) => {
              if (
                (Ht("fetch", { ...a, endTimestamp: ke() * 1e3, error: c }),
                Bt(c) &&
                  c.stack === void 0 &&
                  ((c.stack = s.stack), aa(c, "framesToPop", 1)),
                c instanceof TypeError &&
                  (c.message === "Failed to fetch" ||
                    c.message === "Load failed" ||
                    c.message ===
                      "NetworkError when attempting to fetch resource."))
              )
                try {
                  const u = new URL(a.fetchData.url);
                  c.message = `${c.message} (${u.host})`;
                } catch {}
              throw c;
            },
          )
        );
      };
    });
}
async function mE(e, t) {
  if (e?.body) {
    const n = e.body,
      r = n.getReader(),
      s = setTimeout(() => {
        n.cancel().then(null, () => {});
      }, 90 * 1e3);
    let i = !0;
    for (; i;) {
      let o;
      try {
        o = setTimeout(() => {
          n.cancel().then(null, () => {});
        }, 5e3);
        const { done: a } = await r.read();
        (clearTimeout(o), a && (t(), (i = !1)));
      } catch {
        i = !1;
      } finally {
        clearTimeout(o);
      }
    }
    (clearTimeout(s), r.releaseLock(), n.cancel().then(null, () => {}));
  }
}
function gE(e) {
  let t;
  try {
    t = e.clone();
  } catch {
    return;
  }
  mE(t, () => {
    Ht("fetch-body-resolved", { endTimestamp: ke() * 1e3, response: e });
  });
}
function wo(e, t) {
  return !!e && typeof e == "object" && !!e[t];
}
function Uu(e) {
  return typeof e == "string"
    ? e
    : e
      ? wo(e, "url")
        ? e.url
        : e.toString
          ? e.toString()
          : ""
      : "";
}
function _E(e) {
  if (e.length === 0) return { method: "GET", url: "" };
  if (e.length === 2) {
    const [n, r] = e;
    return {
      url: Uu(n),
      method: wo(r, "method") ? String(r.method).toUpperCase() : "GET",
    };
  }
  const t = e[0];
  return {
    url: Uu(t),
    method: wo(t, "method") ? String(t.method).toUpperCase() : "GET",
  };
}
function SE(e) {
  const [t, n] = e;
  try {
    if (typeof n == "object" && n !== null && "headers" in n && n.headers)
      return new Headers(n.headers);
    if (Pd(t)) return new Headers(t.headers);
  } catch {}
}
function yE() {
  return "npm";
}
const bE = {
    replayIntegration: "replay",
    replayCanvasIntegration: "replay-canvas",
    feedbackIntegration: "feedback",
    feedbackModalIntegration: "feedback-modal",
    feedbackScreenshotIntegration: "feedback-screenshot",
    captureConsoleIntegration: "captureconsole",
    contextLinesIntegration: "contextlines",
    linkedErrorsIntegration: "linkederrors",
    dedupeIntegration: "dedupe",
    extraErrorDataIntegration: "extraerrordata",
    graphqlClientIntegration: "graphqlclient",
    httpClientIntegration: "httpclient",
    reportingObserverIntegration: "reportingobserver",
    rewriteFramesIntegration: "rewriteframes",
    browserProfilingIntegration: "browserprofiling",
    moduleMetadataIntegration: "modulemetadata",
  },
  Hu = B;
async function qf(e, t) {
  const n = bE[e],
    r = (Hu.Sentry = Hu.Sentry || {});
  if (!n) throw new Error(`Cannot lazy load integration: ${e}`);
  const s = r[e];
  if (typeof s == "function" && !("_isShim" in s)) return s;
  const i = EE(n),
    o = B.document.createElement("script");
  ((o.src = i),
    (o.crossOrigin = "anonymous"),
    (o.referrerPolicy = "strict-origin"),
    t && o.setAttribute("nonce", t));
  const a = new Promise((l, p) => {
      (o.addEventListener("load", () => l()), o.addEventListener("error", p));
    }),
    c = B.document.currentScript,
    u = B.document.body || B.document.head || c?.parentElement;
  if (u) u.appendChild(o);
  else
    throw new Error(
      `Could not find parent element to insert lazy-loaded ${e} script`,
    );
  try {
    await a;
  } catch {
    throw new Error(`Error when loading integration: ${e}`);
  }
  const d = r[e];
  if (typeof d != "function")
    throw new Error(`Could not load integration: ${e}`);
  return d;
}
function EE(e) {
  const n = W()?.getOptions()?.cdnBaseUrl || "https://browser.sentry-cdn.com";
  return new URL(`/${bs}/${e}.min.js`, n).toString();
}
const vE = Xd({ lazyLoadIntegration: qf }),
  Wu = Xd({
    getModalIntegration: () => iS,
    getScreenshotIntegration: () => fS,
  });
function pi(e, t) {
  const n = Aa(e, t),
    r = { type: CE(t), value: RE(t) };
  return (
    n.length && (r.stacktrace = { frames: n }),
    r.type === void 0 &&
      r.value === "" &&
      (r.value = "Unrecoverable error caught"),
    r
  );
}
function TE(e, t, n, r) {
  const i = W()?.getOptions().normalizeDepth,
    o = ME(t),
    a = { __serialized__: qm(t, i) };
  if (o) return { exception: { values: [pi(e, o)] }, extra: a };
  const c = {
    exception: {
      values: [
        {
          type: ca(t) ? t.constructor.name : r ? "UnhandledRejection" : "Error",
          value: xE(t, { isUnhandledRejection: r }),
        },
      ],
    },
    extra: a,
  };
  if (n) {
    const u = Aa(e, n);
    u.length && (c.exception.values[0].stacktrace = { frames: u });
  }
  return c;
}
function zi(e, t) {
  return { exception: { values: [pi(e, t)] } };
}
function Aa(e, t) {
  const n = t.stacktrace || t.stack || "",
    r = IE(t),
    s = kE(t);
  try {
    return e(n, r, s);
  } catch {}
  return [];
}
const wE = /Minified React error #\d+;/i;
function IE(e) {
  return e && wE.test(e.message) ? 1 : 0;
}
function kE(e) {
  return typeof e.framesToPop == "number" ? e.framesToPop : 0;
}
function Gf(e) {
  return typeof WebAssembly < "u" && typeof WebAssembly.Exception < "u"
    ? e instanceof WebAssembly.Exception
    : !1;
}
function CE(e) {
  const t = e?.name;
  return !t && Gf(e)
    ? e.message && Array.isArray(e.message) && e.message.length == 2
      ? e.message[0]
      : "WebAssembly.Exception"
    : t;
}
function RE(e) {
  const t = e?.message;
  return Gf(e)
    ? Array.isArray(e.message) && e.message.length == 2
      ? e.message[1]
      : "wasm exception"
    : t
      ? t.error && typeof t.error.message == "string"
        ? t.error.message
        : t
      : "No error message";
}
function Vf(e, t, n, r) {
  const s = n?.syntheticException || void 0,
    i = Ma(e, t, s, r);
  return (
    Gt(i),
    (i.level = "error"),
    n?.event_id && (i.event_id = n.event_id),
    ia(i)
  );
}
function Yf(e, t, n = "info", r, s) {
  const i = r?.syntheticException || void 0,
    o = Io(e, t, i, s);
  return ((o.level = n), r?.event_id && (o.event_id = r.event_id), ia(o));
}
function Ma(e, t, n, r, s) {
  let i;
  if (Fd(t) && t.error) return zi(e, t.error);
  if (Bc(t) || jm(t)) {
    const o = t;
    if ("stack" in t) i = zi(e, t);
    else {
      const a = o.name || (Bc(o) ? "DOMError" : "DOMException"),
        c = o.message ? `${a}: ${o.message}` : a;
      ((i = Io(e, c, n, r)), Uc(i, c));
    }
    return (
      "code" in o && (i.tags = { ...i.tags, "DOMException.code": `${o.code}` }),
      i
    );
  }
  return Bt(t)
    ? zi(e, t)
    : qt(t) || ca(t)
      ? ((i = TE(e, t, n, s)), Gt(i, { synthetic: !0 }), i)
      : ((i = Io(e, t, n, r)), Uc(i, `${t}`), Gt(i, { synthetic: !0 }), i);
}
function Io(e, t, n, r) {
  const s = {};
  if (r && n) {
    const i = Aa(e, n);
    (i.length &&
      (s.exception = { values: [{ value: t, stacktrace: { frames: i } }] }),
      Gt(s, { synthetic: !0 }));
  }
  if (sa(t)) {
    const { __sentry_template_string__: i, __sentry_template_values__: o } = t;
    return ((s.logentry = { message: i, params: o }), s);
  }
  return ((s.message = t), s);
}
function xE(e, { isUnhandledRejection: t }) {
  const n = Gm(e),
    r = t ? "promise rejection" : "exception";
  return Fd(e)
    ? `Event \`ErrorEvent\` captured as ${r} with message \`${e.message}\``
    : ca(e)
      ? `Event \`${AE(e)}\` (type=${e.type}) captured as ${r}`
      : `Object captured as ${r} with keys: ${n}`;
}
function AE(e) {
  try {
    const t = Object.getPrototypeOf(e);
    return t ? t.constructor.name : void 0;
  } catch {}
}
function ME(e) {
  for (const t in e)
    if (Object.prototype.hasOwnProperty.call(e, t)) {
      const n = e[t];
      if (n instanceof Error) return n;
    }
}
const NE = 5e3;
class Xf extends JS {
  constructor(t) {
    const n = OE(t),
      r = B.SENTRY_SDK_SOURCE || yE();
    (Cy(n, "browser", ["browser"], r),
      n._metadata?.sdk &&
        (n._metadata.sdk.settings = {
          infer_ip: n.sendDefaultPii ? "auto" : "never",
          ...n._metadata.sdk.settings,
        }),
      super(n));
    const {
      sendDefaultPii: s,
      sendClientReports: i,
      enableLogs: o,
    } = this._options;
    (B.document &&
      (i || o) &&
      B.document.addEventListener("visibilitychange", () => {
        B.document.visibilityState === "hidden" &&
          (i && this._flushOutcomes(), o && ls(this));
      }),
      o &&
        (this.on("flush", () => {
          ls(this);
        }),
        this.on("afterCaptureLog", () => {
          (this._logFlushIdleTimeout && clearTimeout(this._logFlushIdleTimeout),
            (this._logFlushIdleTimeout = setTimeout(() => {
              ls(this);
            }, NE)));
        })),
      s && this.on("beforeSendSession", ky));
  }
  eventFromException(t, n) {
    return Vf(this._options.stackParser, t, n, this._options.attachStacktrace);
  }
  eventFromMessage(t, n = "info", r) {
    return Yf(
      this._options.stackParser,
      t,
      n,
      r,
      this._options.attachStacktrace,
    );
  }
  _prepareEvent(t, n, r, s) {
    return (
      (t.platform = t.platform || "javascript"),
      super._prepareEvent(t, n, r, s)
    );
  }
}
function OE(e) {
  return {
    release:
      typeof __SENTRY_RELEASE__ == "string"
        ? __SENTRY_RELEASE__
        : B.SENTRY_RELEASE?.id,
    sendClientReports: !0,
    parentSpanIsAlwaysRootSpan: !0,
    ...e,
  };
}
const he = typeof __SENTRY_DEBUG__ > "u" || __SENTRY_DEBUG__,
  Oe = globalThis,
  zn = "10.17.0";
function xn() {
  return (Na(Oe), Oe);
}
function Na(e) {
  const t = (e.__SENTRY__ = e.__SENTRY__ || {});
  return ((t.version = t.version || zn), (t[zn] = t[zn] || {}));
}
function Oa(e, t, n = Oe) {
  const r = (n.__SENTRY__ = n.__SENTRY__ || {}),
    s = (r[zn] = r[zn] || {});
  return s[e] || (s[e] = t());
}
const LE = "Sentry Logger ",
  zu = {};
function Kf(e) {
  if (!("console" in Oe)) return e();
  const t = Oe.console,
    n = {},
    r = Object.keys(zu);
  r.forEach((s) => {
    const i = zu[s];
    ((n[s] = t[s]), (t[s] = i));
  });
  try {
    return e();
  } finally {
    r.forEach((s) => {
      t[s] = n[s];
    });
  }
}
function $E() {
  $a().enabled = !0;
}
function DE() {
  $a().enabled = !1;
}
function Jf() {
  return $a().enabled;
}
function PE(...e) {
  La("log", ...e);
}
function FE(...e) {
  La("warn", ...e);
}
function BE(...e) {
  La("error", ...e);
}
function La(e, ...t) {
  he &&
    Jf() &&
    Kf(() => {
      Oe.console[e](`${LE}[${e}]:`, ...t);
    });
}
function $a() {
  return he ? Oa("loggerSettings", () => ({ enabled: !1 })) : { enabled: !1 };
}
const ce = {
    enable: $E,
    disable: DE,
    isEnabled: Jf,
    log: PE,
    warn: FE,
    error: BE,
  },
  ji = "<anonymous>";
function Zf(e) {
  try {
    return !e || typeof e != "function" ? ji : e.name || ji;
  } catch {
    return ji;
  }
}
const ds = {},
  ju = {};
function Da(e, t) {
  ((ds[e] = ds[e] || []), ds[e].push(t));
}
function Pa(e, t) {
  if (!ju[e]) {
    ju[e] = !0;
    try {
      t();
    } catch (n) {
      he && ce.error(`Error while instrumenting ${e}`, n);
    }
  }
}
function sr(e, t) {
  const n = e && ds[e];
  if (n)
    for (const r of n)
      try {
        r(t);
      } catch (s) {
        he &&
          ce.error(
            `Error while triggering instrumentation handler.
Type: ${e}
Name: ${Zf(r)}
Error:`,
            s,
          );
      }
}
const UE = Object.prototype.toString;
function Fa(e, t) {
  return UE.call(e) === `[object ${t}]`;
}
function Tt(e) {
  return Fa(e, "String");
}
function HE(e) {
  return (
    typeof e == "object" &&
    e !== null &&
    "__sentry_template_string__" in e &&
    "__sentry_template_values__" in e
  );
}
function qu(e) {
  return (
    e === null || HE(e) || (typeof e != "object" && typeof e != "function")
  );
}
function WE(e) {
  return Fa(e, "Object");
}
function zE(e) {
  return Fa(e, "RegExp");
}
function Qf(e) {
  return !!(e?.then && typeof e.then == "function");
}
const ep = Oe,
  jE = 80;
function xt(e, t = {}) {
  if (!e) return "<unknown>";
  try {
    let n = e;
    const r = 5,
      s = [];
    let i = 0,
      o = 0;
    const a = " > ",
      c = a.length;
    let u;
    const d = Array.isArray(t) ? t : t.keyAttrs,
      l = (!Array.isArray(t) && t.maxStringLength) || jE;
    for (
      ;
      n &&
      i++ < r &&
      ((u = qE(n, d)),
      !(u === "html" || (i > 1 && o + s.length * c + u.length >= l)));
    )
      (s.push(u), (o += u.length), (n = n.parentNode));
    return s.reverse().join(a);
  } catch {
    return "<unknown>";
  }
}
function qE(e, t) {
  const n = e,
    r = [];
  if (!n?.tagName) return "";
  if (ep.HTMLElement && n instanceof HTMLElement && n.dataset) {
    if (n.dataset.sentryComponent) return n.dataset.sentryComponent;
    if (n.dataset.sentryElement) return n.dataset.sentryElement;
  }
  r.push(n.tagName.toLowerCase());
  const s = t?.length
    ? t.filter((o) => n.getAttribute(o)).map((o) => [o, n.getAttribute(o)])
    : null;
  if (s?.length)
    s.forEach((o) => {
      r.push(`[${o[0]}="${o[1]}"]`);
    });
  else {
    n.id && r.push(`#${n.id}`);
    const o = n.className;
    if (o && Tt(o)) {
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
function GE(e) {
  if (!ep.HTMLElement) return null;
  let t = e;
  const n = 5;
  for (let r = 0; r < n; r++) {
    if (!t) return null;
    if (t instanceof HTMLElement) {
      if (t.dataset.sentryComponent) return t.dataset.sentryComponent;
      if (t.dataset.sentryElement) return t.dataset.sentryElement;
    }
    t = t.parentNode;
  }
  return null;
}
function VE(e, t = 0) {
  return typeof e != "string" || t === 0 || e.length <= t
    ? e
    : `${e.slice(0, t)}...`;
}
function fs(e, t, n = !1) {
  return Tt(e)
    ? zE(t)
      ? t.test(e)
      : Tt(t)
        ? n
          ? e === t
          : e.includes(t)
        : !1
    : !1;
}
function YE(e, t = [], n = !1) {
  return t.some((r) => fs(e, r, n));
}
function Os(e, t, n) {
  if (!(t in e)) return;
  const r = e[t];
  if (typeof r != "function") return;
  const s = n(r);
  typeof s == "function" && XE(s, r);
  try {
    e[t] = s;
  } catch {
    he && ce.log(`Failed to replace method "${t}" in object`, e);
  }
}
function mt(e, t, n) {
  try {
    Object.defineProperty(e, t, { value: n, writable: !0, configurable: !0 });
  } catch {
    he && ce.log(`Failed to add non-enumerable property "${t}" to object`, e);
  }
}
function XE(e, t) {
  try {
    const n = t.prototype || {};
    ((e.prototype = t.prototype = n), mt(e, "__sentry_original__", t));
  } catch {}
}
function KE() {
  const e = Oe;
  return e.crypto || e.msCrypto;
}
function Wt(e = KE()) {
  let t = () => Math.random() * 16;
  try {
    if (e?.randomUUID) return e.randomUUID().replace(/-/g, "");
    e?.getRandomValues &&
      (t = () => {
        const n = new Uint8Array(1);
        return (e.getRandomValues(n), n[0]);
      });
  } catch {}
  return ("10000000100040008000" + 1e11).replace(/[018]/g, (n) =>
    (n ^ ((t() & 15) >> (n / 4))).toString(16),
  );
}
const tp = 1e3;
function np() {
  return Date.now() / tp;
}
function JE() {
  const { performance: e } = Oe;
  if (!e?.now || !e.timeOrigin) return np;
  const t = e.timeOrigin;
  return () => (t + e.now()) / tp;
}
let Gu;
function at() {
  return (Gu ?? (Gu = JE()))();
}
let qi;
function ZE() {
  const { performance: e } = Oe;
  if (!e?.now) return [void 0, "none"];
  const t = 3600 * 1e3,
    n = e.now(),
    r = Date.now(),
    s = e.timeOrigin ? Math.abs(e.timeOrigin + n - r) : t,
    i = s < t,
    o = e.timing?.navigationStart,
    c = typeof o == "number" ? Math.abs(o + n - r) : t,
    u = c < t;
  return i || u
    ? s <= c
      ? [e.timeOrigin, "timeOrigin"]
      : [o, "navigationStart"]
    : [r, "dateNow"];
}
function Fe() {
  return (qi || (qi = ZE()), qi[0]);
}
function QE(e, t = {}) {
  if (
    (t.user &&
      (!e.ipAddress && t.user.ip_address && (e.ipAddress = t.user.ip_address),
      !e.did &&
        !t.did &&
        (e.did = t.user.id || t.user.email || t.user.username)),
    (e.timestamp = t.timestamp || at()),
    t.abnormal_mechanism && (e.abnormal_mechanism = t.abnormal_mechanism),
    t.ignoreDuration && (e.ignoreDuration = t.ignoreDuration),
    t.sid && (e.sid = t.sid.length === 32 ? t.sid : Wt()),
    t.init !== void 0 && (e.init = t.init),
    !e.did && t.did && (e.did = `${t.did}`),
    typeof t.started == "number" && (e.started = t.started),
    e.ignoreDuration)
  )
    e.duration = void 0;
  else if (typeof t.duration == "number") e.duration = t.duration;
  else {
    const n = e.timestamp - e.started;
    e.duration = n >= 0 ? n : 0;
  }
  (t.release && (e.release = t.release),
    t.environment && (e.environment = t.environment),
    !e.ipAddress && t.ipAddress && (e.ipAddress = t.ipAddress),
    !e.userAgent && t.userAgent && (e.userAgent = t.userAgent),
    typeof t.errors == "number" && (e.errors = t.errors),
    t.status && (e.status = t.status));
}
function rp(e, t, n = 2) {
  if (!t || typeof t != "object" || n <= 0) return t;
  if (e && Object.keys(t).length === 0) return e;
  const r = { ...e };
  for (const s in t)
    Object.prototype.hasOwnProperty.call(t, s) &&
      (r[s] = rp(r[s], t[s], n - 1));
  return r;
}
function Ls() {
  return Wt();
}
function sp() {
  return Wt().substring(16);
}
const ko = "_sentrySpan";
function $s(e, t) {
  t ? mt(e, ko, t) : delete e[ko];
}
function Ds(e) {
  return e[ko];
}
const ev = 100;
let Ps = class Co {
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
      (this._propagationContext = {
        traceId: Ls(),
        sampleRand: Math.random(),
      }));
  }
  clone() {
    const t = new Co();
    return (
      (t._breadcrumbs = [...this._breadcrumbs]),
      (t._tags = { ...this._tags }),
      (t._extra = { ...this._extra }),
      (t._contexts = { ...this._contexts }),
      this._contexts.flags &&
        (t._contexts.flags = { values: [...this._contexts.flags.values] }),
      (t._user = this._user),
      (t._level = this._level),
      (t._session = this._session),
      (t._transactionName = this._transactionName),
      (t._fingerprint = this._fingerprint),
      (t._eventProcessors = [...this._eventProcessors]),
      (t._attachments = [...this._attachments]),
      (t._sdkProcessingMetadata = { ...this._sdkProcessingMetadata }),
      (t._propagationContext = { ...this._propagationContext }),
      (t._client = this._client),
      (t._lastEventId = this._lastEventId),
      $s(t, Ds(this)),
      t
    );
  }
  setClient(t) {
    this._client = t;
  }
  setLastEventId(t) {
    this._lastEventId = t;
  }
  getClient() {
    return this._client;
  }
  lastEventId() {
    return this._lastEventId;
  }
  addScopeListener(t) {
    this._scopeListeners.push(t);
  }
  addEventProcessor(t) {
    return (this._eventProcessors.push(t), this);
  }
  setUser(t) {
    return (
      (this._user = t || {
        email: void 0,
        id: void 0,
        ip_address: void 0,
        username: void 0,
      }),
      this._session && QE(this._session, { user: t }),
      this._notifyScopeListeners(),
      this
    );
  }
  getUser() {
    return this._user;
  }
  setTags(t) {
    return (
      (this._tags = { ...this._tags, ...t }),
      this._notifyScopeListeners(),
      this
    );
  }
  setTag(t, n) {
    return (
      (this._tags = { ...this._tags, [t]: n }),
      this._notifyScopeListeners(),
      this
    );
  }
  setExtras(t) {
    return (
      (this._extra = { ...this._extra, ...t }),
      this._notifyScopeListeners(),
      this
    );
  }
  setExtra(t, n) {
    return (
      (this._extra = { ...this._extra, [t]: n }),
      this._notifyScopeListeners(),
      this
    );
  }
  setFingerprint(t) {
    return ((this._fingerprint = t), this._notifyScopeListeners(), this);
  }
  setLevel(t) {
    return ((this._level = t), this._notifyScopeListeners(), this);
  }
  setTransactionName(t) {
    return ((this._transactionName = t), this._notifyScopeListeners(), this);
  }
  setContext(t, n) {
    return (
      n === null ? delete this._contexts[t] : (this._contexts[t] = n),
      this._notifyScopeListeners(),
      this
    );
  }
  setSession(t) {
    return (
      t ? (this._session = t) : delete this._session,
      this._notifyScopeListeners(),
      this
    );
  }
  getSession() {
    return this._session;
  }
  update(t) {
    if (!t) return this;
    const n = typeof t == "function" ? t(this) : t,
      r = n instanceof Co ? n.getScopeData() : WE(n) ? t : void 0,
      {
        tags: s,
        extra: i,
        user: o,
        contexts: a,
        level: c,
        fingerprint: u = [],
        propagationContext: d,
      } = r || {};
    return (
      (this._tags = { ...this._tags, ...s }),
      (this._extra = { ...this._extra, ...i }),
      (this._contexts = { ...this._contexts, ...a }),
      o && Object.keys(o).length && (this._user = o),
      c && (this._level = c),
      u.length && (this._fingerprint = u),
      d && (this._propagationContext = d),
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
      $s(this, void 0),
      (this._attachments = []),
      this.setPropagationContext({ traceId: Ls(), sampleRand: Math.random() }),
      this._notifyScopeListeners(),
      this
    );
  }
  addBreadcrumb(t, n) {
    const r = typeof n == "number" ? n : ev;
    if (r <= 0) return this;
    const s = {
      timestamp: np(),
      ...t,
      message: t.message ? VE(t.message, 2048) : t.message,
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
  addAttachment(t) {
    return (this._attachments.push(t), this);
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
      span: Ds(this),
    };
  }
  setSDKProcessingMetadata(t) {
    return (
      (this._sdkProcessingMetadata = rp(this._sdkProcessingMetadata, t, 2)),
      this
    );
  }
  setPropagationContext(t) {
    return ((this._propagationContext = t), this);
  }
  getPropagationContext() {
    return this._propagationContext;
  }
  captureException(t, n) {
    const r = n?.event_id || Wt();
    if (!this._client)
      return (
        he &&
          ce.warn(
            "No client configured on scope - will not capture exception!",
          ),
        r
      );
    const s = new Error("Sentry syntheticException");
    return (
      this._client.captureException(
        t,
        { originalException: t, syntheticException: s, ...n, event_id: r },
        this,
      ),
      r
    );
  }
  captureMessage(t, n, r) {
    const s = r?.event_id || Wt();
    if (!this._client)
      return (
        he &&
          ce.warn("No client configured on scope - will not capture message!"),
        s
      );
    const i = new Error(t);
    return (
      this._client.captureMessage(
        t,
        n,
        { originalException: t, syntheticException: i, ...r, event_id: s },
        this,
      ),
      s
    );
  }
  captureEvent(t, n) {
    const r = n?.event_id || Wt();
    return this._client
      ? (this._client.captureEvent(t, { ...n, event_id: r }, this), r)
      : (he &&
          ce.warn("No client configured on scope - will not capture event!"),
        r);
  }
  _notifyScopeListeners() {
    this._notifyingListeners ||
      ((this._notifyingListeners = !0),
      this._scopeListeners.forEach((t) => {
        t(this);
      }),
      (this._notifyingListeners = !1));
  }
};
function tv() {
  return Oa("defaultCurrentScope", () => new Ps());
}
function nv() {
  return Oa("defaultIsolationScope", () => new Ps());
}
let rv = class {
  constructor(t, n) {
    let r;
    t ? (r = t) : (r = new Ps());
    let s;
    (n ? (s = n) : (s = new Ps()),
      (this._stack = [{ scope: r }]),
      (this._isolationScope = s));
  }
  withScope(t) {
    const n = this._pushScope();
    let r;
    try {
      r = t(n);
    } catch (s) {
      throw (this._popScope(), s);
    }
    return Qf(r)
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
    const t = this.getScope().clone();
    return (this._stack.push({ client: this.getClient(), scope: t }), t);
  }
  _popScope() {
    return this._stack.length <= 1 ? !1 : !!this._stack.pop();
  }
};
function _n() {
  const e = xn(),
    t = Na(e);
  return (t.stack = t.stack || new rv(tv(), nv()));
}
function sv(e) {
  return _n().withScope(e);
}
function iv(e, t) {
  const n = _n();
  return n.withScope(() => ((n.getStackTop().scope = e), t(e)));
}
function Vu(e) {
  return _n().withScope(() => e(_n().getIsolationScope()));
}
function ov() {
  return {
    withIsolationScope: Vu,
    withScope: sv,
    withSetScope: iv,
    withSetIsolationScope: (e, t) => Vu(t),
    getCurrentScope: () => _n().getScope(),
    getIsolationScope: () => _n().getIsolationScope(),
  };
}
function vr(e) {
  const t = Na(e);
  return t.acs ? t.acs : ov();
}
function et() {
  const e = xn();
  return vr(e).getCurrentScope();
}
function av() {
  const e = xn();
  return vr(e).getIsolationScope();
}
function Ba(...e) {
  const t = xn(),
    n = vr(t);
  if (e.length === 2) {
    const [r, s] = e;
    return r ? n.withSetScope(r, s) : n.withScope(s);
  }
  return n.withScope(e[0]);
}
function Nt() {
  return et().getClient();
}
const ir = "sentry.source",
  ip = "sentry.sample_rate",
  cv = "sentry.previous_trace_sample_rate",
  Yt = "sentry.op",
  we = "sentry.origin",
  Tr = "sentry.measurement_unit",
  wr = "sentry.measurement_value",
  Yu = "sentry.custom_span_name",
  uv = "sentry.profile_id",
  hi = "sentry.exclusive_time",
  lv = 0,
  dv = 1,
  fv = 2,
  op = "_sentryScope",
  ap = "_sentryIsolationScope";
function pv(e) {
  try {
    const t = Oe.WeakRef;
    if (typeof t == "function") return new t(e);
  } catch {}
  return e;
}
function hv(e) {
  if (e) {
    if (typeof e == "object" && "deref" in e && typeof e.deref == "function")
      try {
        return e.deref();
      } catch {
        return;
      }
    return e;
  }
}
function mv(e, t, n) {
  e && (mt(e, ap, pv(n)), mt(e, op, t));
}
function Ro(e) {
  const t = e;
  return { scope: t[op], isolationScope: hv(t[ap]) };
}
const gv = "sentry-",
  _v = /^sentry-/;
function Sv(e) {
  const t = yv(e);
  if (!t) return;
  const n = Object.entries(t).reduce((r, [s, i]) => {
    if (s.match(_v)) {
      const o = s.slice(gv.length);
      r[o] = i;
    }
    return r;
  }, {});
  if (Object.keys(n).length > 0) return n;
}
function yv(e) {
  if (!(!e || (!Tt(e) && !Array.isArray(e))))
    return Array.isArray(e)
      ? e.reduce((t, n) => {
          const r = Xu(n);
          return (
            Object.entries(r).forEach(([s, i]) => {
              t[s] = i;
            }),
            t
          );
        }, {})
      : Xu(e);
}
function Xu(e) {
  return e
    .split(",")
    .map((t) =>
      t.split("=").map((n) => {
        try {
          return decodeURIComponent(n.trim());
        } catch {
          return;
        }
      }),
    )
    .reduce((t, [n, r]) => (n && r && (t[n] = r), t), {});
}
const bv = /^o(\d+)\./;
function Ev(e, t = !1) {
  const {
    host: n,
    path: r,
    pass: s,
    port: i,
    projectId: o,
    protocol: a,
    publicKey: c,
  } = e;
  return `${a}://${c}${t && s ? `:${s}` : ""}@${n}${i ? `:${i}` : ""}/${r && `${r}/`}${o}`;
}
function vv(e) {
  return e.match(bv)?.[1];
}
function Tv(e) {
  const t = e.getOptions(),
    { host: n } = e.getDsn() || {};
  let r;
  return (t.orgId ? (r = String(t.orgId)) : n && (r = vv(n)), r);
}
function cp(e) {
  if (typeof e == "boolean") return Number(e);
  const t = typeof e == "string" ? parseFloat(e) : e;
  if (!(typeof t != "number" || isNaN(t) || t < 0 || t > 1)) return t;
}
const up = 0,
  Ua = 1;
let Ku = !1;
function wv(e) {
  const { spanId: t, traceId: n } = e.spanContext(),
    {
      data: r,
      op: s,
      parent_span_id: i,
      status: o,
      origin: a,
      links: c,
    } = be(e);
  return {
    parent_span_id: i,
    span_id: t,
    trace_id: n,
    data: r,
    op: s,
    status: o,
    origin: a,
    links: c,
  };
}
function lp(e) {
  if (e && e.length > 0)
    return e.map(
      ({
        context: { spanId: t, traceId: n, traceFlags: r, ...s },
        attributes: i,
      }) => ({
        span_id: t,
        trace_id: n,
        sampled: r === Ua,
        attributes: i,
        ...s,
      }),
    );
}
function dn(e) {
  return typeof e == "number"
    ? Ju(e)
    : Array.isArray(e)
      ? e[0] + e[1] / 1e9
      : e instanceof Date
        ? Ju(e.getTime())
        : at();
}
function Ju(e) {
  return e > 9999999999 ? e / 1e3 : e;
}
function be(e) {
  if (kv(e)) return e.getSpanJSON();
  const { spanId: t, traceId: n } = e.spanContext();
  if (Iv(e)) {
    const {
        attributes: r,
        startTime: s,
        name: i,
        endTime: o,
        status: a,
        links: c,
      } = e,
      u =
        "parentSpanId" in e
          ? e.parentSpanId
          : "parentSpanContext" in e
            ? e.parentSpanContext?.spanId
            : void 0;
    return {
      span_id: t,
      trace_id: n,
      data: r,
      description: i,
      parent_span_id: u,
      start_timestamp: dn(s),
      timestamp: dn(o) || void 0,
      status: dp(a),
      op: r[Yt],
      origin: r[we],
      links: lp(c),
    };
  }
  return { span_id: t, trace_id: n, start_timestamp: 0, data: {} };
}
function Iv(e) {
  const t = e;
  return (
    !!t.attributes && !!t.startTime && !!t.name && !!t.endTime && !!t.status
  );
}
function kv(e) {
  return typeof e.getSpanJSON == "function";
}
function Ir(e) {
  const { traceFlags: t } = e.spanContext();
  return t === Ua;
}
function dp(e) {
  if (!(!e || e.code === lv))
    return e.code === dv ? "ok" : e.message || "unknown_error";
}
const jn = "_sentryChildSpans",
  xo = "_sentryRootSpan";
function fp(e, t) {
  const n = e[xo] || e;
  (mt(t, xo, n), e[jn] ? e[jn].add(t) : mt(e, jn, new Set([t])));
}
function Cv(e) {
  const t = new Set();
  function n(r) {
    if (!t.has(r) && Ir(r)) {
      t.add(r);
      const s = r[jn] ? Array.from(r[jn]) : [];
      for (const i of s) n(i);
    }
  }
  return (n(e), Array.from(t));
}
function ze(e) {
  return e[xo] || e;
}
function Jt() {
  const e = xn(),
    t = vr(e);
  return t.getActiveSpan ? t.getActiveSpan() : Ds(et());
}
function Rv() {
  Ku ||
    (Kf(() => {
      console.warn(
        "[Sentry] Returning null from `beforeSendSpan` is disallowed. To drop certain spans, configure the respective integrations directly or use `ignoreSpans`.",
      );
    }),
    (Ku = !0));
}
function Ha(e) {
  if (typeof __SENTRY_TRACING__ == "boolean" && !__SENTRY_TRACING__) return !1;
  const t = e || Nt()?.getOptions();
  return !!t && (t.tracesSampleRate != null || !!t.tracesSampler);
}
function Zu(e) {
  ce.log(
    `Ignoring span ${e.op} - ${e.description} because it matches \`ignoreSpans\`.`,
  );
}
function xv(e, t) {
  if (!t?.length || !e.description) return !1;
  for (const n of t) {
    if (Av(n)) {
      if (fs(e.description, n)) return (he && Zu(e), !0);
      continue;
    }
    if (!n.name && !n.op) continue;
    const r = n.name ? fs(e.description, n.name) : !0,
      s = n.op ? e.op && fs(e.op, n.op) : !0;
    if (r && s) return (he && Zu(e), !0);
  }
  return !1;
}
function Av(e) {
  return typeof e == "string" || e instanceof RegExp;
}
const Mv = "production",
  pp = "_frozenDsc";
function Gi(e, t) {
  mt(e, pp, t);
}
function Nv(e, t) {
  const n = t.getOptions(),
    { publicKey: r } = t.getDsn() || {},
    s = {
      environment: n.environment || Mv,
      release: n.release,
      public_key: r,
      trace_id: e,
      org_id: Tv(t),
    };
  return (t.emit("createDsc", s), s);
}
function Fs(e) {
  const t = Nt();
  if (!t) return {};
  const n = ze(e),
    r = be(n),
    s = r.data,
    i = n.spanContext().traceState,
    o = i?.get("sentry.sample_rate") ?? s[ip] ?? s[cv];
  function a(h) {
    return (
      (typeof o == "number" || typeof o == "string") &&
        (h.sample_rate = `${o}`),
      h
    );
  }
  const c = n[pp];
  if (c) return a(c);
  const u = i?.get("sentry.dsc"),
    d = u && Sv(u);
  if (d) return a(d);
  const l = Nv(e.spanContext().traceId, t),
    p = s[ir],
    f = r.description;
  return (
    p !== "url" && f && (l.transaction = f),
    Ha() &&
      ((l.sampled = String(Ir(n))),
      (l.sample_rand =
        i?.get("sentry.sample_rand") ??
        Ro(n).scope?.getPropagationContext().sampleRand.toString())),
    a(l),
    t.emit("createDsc", l, n),
    l
  );
}
class mi {
  constructor(t = {}) {
    ((this._traceId = t.traceId || Ls()), (this._spanId = t.spanId || sp()));
  }
  spanContext() {
    return { spanId: this._spanId, traceId: this._traceId, traceFlags: up };
  }
  end(t) {}
  setAttribute(t, n) {
    return this;
  }
  setAttributes(t) {
    return this;
  }
  setStatus(t) {
    return this;
  }
  updateName(t) {
    return this;
  }
  isRecording() {
    return !1;
  }
  addEvent(t, n, r) {
    return this;
  }
  addLink(t) {
    return this;
  }
  addLinks(t) {
    return this;
  }
  recordException(t, n) {}
}
function Ov(e, t = []) {
  return [e, t];
}
function Lv(e) {
  return [{ type: "span" }, e];
}
function $v(e, t) {
  function n(f) {
    return !!f.trace_id && !!f.public_key;
  }
  const r = Fs(e[0]),
    s = t?.getDsn(),
    i = t?.getOptions().tunnel,
    o = {
      sent_at: new Date().toISOString(),
      ...(n(r) && { trace: r }),
      ...(!!i && s && { dsn: Ev(s) }),
    },
    { beforeSendSpan: a, ignoreSpans: c } = t?.getOptions() || {},
    u = c?.length ? e.filter((f) => !xv(be(f), c)) : e,
    d = e.length - u.length;
  d && t?.recordDroppedEvent("before_send", "span", d);
  const l = a
      ? (f) => {
          const h = be(f),
            m = a(h);
          return m || (Rv(), h);
        }
      : be,
    p = [];
  for (const f of u) {
    const h = l(f);
    h && p.push(Lv(h));
  }
  return Ov(o, p);
}
function Dv(e) {
  if (!he) return;
  const {
      description: t = "< unknown name >",
      op: n = "< unknown op >",
      parent_span_id: r,
    } = be(e),
    { spanId: s } = e.spanContext(),
    i = Ir(e),
    o = ze(e),
    a = o === e,
    c = `[Tracing] Starting ${i ? "sampled" : "unsampled"} ${a ? "root " : ""}span`,
    u = [`op: ${n}`, `name: ${t}`, `ID: ${s}`];
  if ((r && u.push(`parent ID: ${r}`), !a)) {
    const { op: d, description: l } = be(o);
    (u.push(`root ID: ${o.spanContext().spanId}`),
      d && u.push(`root op: ${d}`),
      l && u.push(`root description: ${l}`));
  }
  ce.log(`${c}
  ${u.join(`
  `)}`);
}
function Pv(e) {
  if (!he) return;
  const { description: t = "< unknown name >", op: n = "< unknown op >" } =
      be(e),
    { spanId: r } = e.spanContext(),
    i = ze(e) === e,
    o = `[Tracing] Finishing "${n}" ${i ? "root " : ""}span "${t}" with ID ${r}`;
  ce.log(o);
}
function Fv(e, t, n, r = Jt()) {
  const s = r && ze(r);
  s &&
    (he &&
      ce.log(
        `[Measurement] Setting measurement on root span: ${e} = ${t} ${n}`,
      ),
    s.addEvent(e, { [wr]: t, [Tr]: n }));
}
function Qu(e) {
  if (!e || e.length === 0) return;
  const t = {};
  return (
    e.forEach((n) => {
      const r = n.attributes || {},
        s = r[Tr],
        i = r[wr];
      typeof s == "string" &&
        typeof i == "number" &&
        (t[n.name] = { value: i, unit: s });
    }),
    t
  );
}
const el = 1e3;
class Wa {
  constructor(t = {}) {
    ((this._traceId = t.traceId || Ls()),
      (this._spanId = t.spanId || sp()),
      (this._startTime = t.startTimestamp || at()),
      (this._links = t.links),
      (this._attributes = {}),
      this.setAttributes({ [we]: "manual", [Yt]: t.op, ...t.attributes }),
      (this._name = t.name),
      t.parentSpanId && (this._parentSpanId = t.parentSpanId),
      "sampled" in t && (this._sampled = t.sampled),
      t.endTimestamp && (this._endTime = t.endTimestamp),
      (this._events = []),
      (this._isStandaloneSpan = t.isStandalone),
      this._endTime && this._onSpanEnded());
  }
  addLink(t) {
    return (this._links ? this._links.push(t) : (this._links = [t]), this);
  }
  addLinks(t) {
    return (this._links ? this._links.push(...t) : (this._links = t), this);
  }
  recordException(t, n) {}
  spanContext() {
    const { _spanId: t, _traceId: n, _sampled: r } = this;
    return { spanId: t, traceId: n, traceFlags: r ? Ua : up };
  }
  setAttribute(t, n) {
    return (
      n === void 0 ? delete this._attributes[t] : (this._attributes[t] = n),
      this
    );
  }
  setAttributes(t) {
    return (Object.keys(t).forEach((n) => this.setAttribute(n, t[n])), this);
  }
  updateStartTime(t) {
    this._startTime = dn(t);
  }
  setStatus(t) {
    return ((this._status = t), this);
  }
  updateName(t) {
    return ((this._name = t), this.setAttribute(ir, "custom"), this);
  }
  end(t) {
    this._endTime || ((this._endTime = dn(t)), Pv(this), this._onSpanEnded());
  }
  getSpanJSON() {
    return {
      data: this._attributes,
      description: this._name,
      op: this._attributes[Yt],
      parent_span_id: this._parentSpanId,
      span_id: this._spanId,
      start_timestamp: this._startTime,
      status: dp(this._status),
      timestamp: this._endTime,
      trace_id: this._traceId,
      origin: this._attributes[we],
      profile_id: this._attributes[uv],
      exclusive_time: this._attributes[hi],
      measurements: Qu(this._events),
      is_segment: (this._isStandaloneSpan && ze(this) === this) || void 0,
      segment_id: this._isStandaloneSpan
        ? ze(this).spanContext().spanId
        : void 0,
      links: lp(this._links),
    };
  }
  isRecording() {
    return !this._endTime && !!this._sampled;
  }
  addEvent(t, n, r) {
    he && ce.log("[Tracing] Adding an event to span:", t);
    const s = tl(n) ? n : r || at(),
      i = tl(n) ? {} : n || {},
      o = { name: t, time: dn(s), attributes: i };
    return (this._events.push(o), this);
  }
  isStandaloneSpan() {
    return !!this._isStandaloneSpan;
  }
  _onSpanEnded() {
    const t = Nt();
    if (
      (t && t.emit("spanEnd", this),
      !(this._isStandaloneSpan || this === ze(this)))
    )
      return;
    if (this._isStandaloneSpan) {
      this._sampled
        ? Uv($v([this], t))
        : (he &&
            ce.log(
              "[Tracing] Discarding standalone span because its trace was not chosen to be sampled.",
            ),
          t && t.recordDroppedEvent("sample_rate", "span"));
      return;
    }
    const r = this._convertSpanToTransaction();
    r && (Ro(this).scope || et()).captureEvent(r);
  }
  _convertSpanToTransaction() {
    if (!nl(be(this))) return;
    this._name ||
      (he &&
        ce.warn(
          "Transaction has no name, falling back to `<unlabeled transaction>`.",
        ),
      (this._name = "<unlabeled transaction>"));
    const { scope: t, isolationScope: n } = Ro(this),
      r = t?.getScopeData().sdkProcessingMetadata?.normalizedRequest;
    if (this._sampled !== !0) return;
    const i = Cv(this)
        .filter((d) => d !== this && !Bv(d))
        .map((d) => be(d))
        .filter(nl),
      o = this._attributes[ir];
    (delete this._attributes[Yu],
      i.forEach((d) => {
        delete d.data[Yu];
      }));
    const a = {
        contexts: { trace: wv(this) },
        spans:
          i.length > el
            ? i
                .sort((d, l) => d.start_timestamp - l.start_timestamp)
                .slice(0, el)
            : i,
        start_timestamp: this._startTime,
        timestamp: this._endTime,
        transaction: this._name,
        type: "transaction",
        sdkProcessingMetadata: {
          capturedSpanScope: t,
          capturedSpanIsolationScope: n,
          dynamicSamplingContext: Fs(this),
        },
        request: r,
        ...(o && { transaction_info: { source: o } }),
      },
      c = Qu(this._events);
    return (
      c &&
        Object.keys(c).length &&
        (he &&
          ce.log(
            "[Measurements] Adding measurements to transaction event",
            JSON.stringify(c, void 0, 2),
          ),
        (a.measurements = c)),
      a
    );
  }
}
function tl(e) {
  return (e && typeof e == "number") || e instanceof Date || Array.isArray(e);
}
function nl(e) {
  return !!e.start_timestamp && !!e.timestamp && !!e.span_id && !!e.trace_id;
}
function Bv(e) {
  return e instanceof Wa && e.isStandaloneSpan();
}
function Uv(e) {
  const t = Nt();
  if (!t) return;
  const n = e[1];
  if (!n || n.length === 0) {
    t.recordDroppedEvent("before_send", "span");
    return;
  }
  t.sendEnvelope(e);
}
function Hv(e, t, n = () => {}, r = () => {}) {
  let s;
  try {
    s = e();
  } catch (i) {
    throw (t(i), n(), i);
  }
  return Wv(s, t, n, r);
}
function Wv(e, t, n, r) {
  return Qf(e)
    ? e.then(
        (s) => (n(), r(s), s),
        (s) => {
          throw (t(s), n(), s);
        },
      )
    : (n(), r(e), e);
}
function zv(e, t, n) {
  if (!Ha(e)) return [!1];
  let r, s;
  typeof e.tracesSampler == "function"
    ? ((s = e.tracesSampler({
        ...t,
        inheritOrSampleWith: (a) =>
          typeof t.parentSampleRate == "number"
            ? t.parentSampleRate
            : typeof t.parentSampled == "boolean"
              ? Number(t.parentSampled)
              : a,
      })),
      (r = !0))
    : t.parentSampled !== void 0
      ? (s = t.parentSampled)
      : typeof e.tracesSampleRate < "u" && ((s = e.tracesSampleRate), (r = !0));
  const i = cp(s);
  if (i === void 0)
    return (
      he &&
        ce.warn(
          `[Tracing] Discarding root span because of invalid sample rate. Sample rate must be a boolean or a number between 0 and 1. Got ${JSON.stringify(s)} of type ${JSON.stringify(typeof s)}.`,
        ),
      [!1]
    );
  if (!i)
    return (
      he &&
        ce.log(
          `[Tracing] Discarding transaction because ${typeof e.tracesSampler == "function" ? "tracesSampler returned 0 or false" : "a negative sampling decision was inherited or tracesSampleRate is set to 0"}`,
        ),
      [!1, i, r]
    );
  const o = n < i;
  return (
    o ||
      (he &&
        ce.log(
          `[Tracing] Discarding transaction because it's not included in the random sample (sampling rate = ${Number(s)})`,
        )),
    [o, i, r]
  );
}
const hp = "__SENTRY_SUPPRESS_TRACING__";
function jv(e, t) {
  const n = ja();
  if (n.startSpan) return n.startSpan(e, t);
  const r = _p(e),
    { forceTransaction: s, parentSpan: i, scope: o } = e,
    a = o?.clone();
  return Ba(a, () =>
    Gv(i)(() => {
      const u = et(),
        d = Sp(u, i),
        p =
          e.onlyIfParent && !d
            ? new mi()
            : gp({
                parentSpan: d,
                spanArguments: r,
                forceTransaction: s,
                scope: u,
              });
      return (
        $s(u, p),
        Hv(
          () => t(p),
          () => {
            const { status: f } = be(p);
            p.isRecording() &&
              (!f || f === "ok") &&
              p.setStatus({ code: fv, message: "internal_error" });
          },
          () => {
            p.end();
          },
        )
      );
    }),
  );
}
function mp(e) {
  const t = ja();
  if (t.startInactiveSpan) return t.startInactiveSpan(e);
  const n = _p(e),
    { forceTransaction: r, parentSpan: s } = e;
  return (
    e.scope
      ? (o) => Ba(e.scope, o)
      : s !== void 0
        ? (o) => za(s, o)
        : (o) => o()
  )(() => {
    const o = et(),
      a = Sp(o, s);
    return e.onlyIfParent && !a
      ? new mi()
      : gp({ parentSpan: a, spanArguments: n, forceTransaction: r, scope: o });
  });
}
function za(e, t) {
  const n = ja();
  return n.withActiveSpan
    ? n.withActiveSpan(e, t)
    : Ba((r) => ($s(r, e || void 0), t(r)));
}
function gp({
  parentSpan: e,
  spanArguments: t,
  forceTransaction: n,
  scope: r,
}) {
  if (!Ha()) {
    const o = new mi();
    if (n || !e) {
      const a = {
        sampled: "false",
        sample_rate: "0",
        transaction: t.name,
        ...Fs(o),
      };
      Gi(o, a);
    }
    return o;
  }
  const s = av();
  let i;
  if (e && !n) ((i = qv(e, r, t)), fp(e, i));
  else if (e) {
    const o = Fs(e),
      { traceId: a, spanId: c } = e.spanContext(),
      u = Ir(e);
    ((i = rl({ traceId: a, parentSpanId: c, ...t }, r, u)), Gi(i, o));
  } else {
    const {
      traceId: o,
      dsc: a,
      parentSpanId: c,
      sampled: u,
    } = { ...s.getPropagationContext(), ...r.getPropagationContext() };
    ((i = rl({ traceId: o, parentSpanId: c, ...t }, r, u)), a && Gi(i, a));
  }
  return (Dv(i), mv(i, r, s), i);
}
function _p(e) {
  const n = { isStandalone: (e.experimental || {}).standalone, ...e };
  if (e.startTime) {
    const r = { ...n };
    return ((r.startTimestamp = dn(e.startTime)), delete r.startTime, r);
  }
  return n;
}
function ja() {
  const e = xn();
  return vr(e);
}
function rl(e, t, n) {
  const r = Nt(),
    s = r?.getOptions() || {},
    { name: i = "" } = e,
    o = { spanAttributes: { ...e.attributes }, spanName: i, parentSampled: n };
  r?.emit("beforeSampling", o, { decision: !1 });
  const a = o.parentSampled ?? n,
    c = o.spanAttributes,
    u = t.getPropagationContext(),
    [d, l, p] = t.getScopeData().sdkProcessingMetadata[hp]
      ? [!1]
      : zv(
          s,
          {
            name: i,
            parentSampled: a,
            attributes: c,
            parentSampleRate: cp(u.dsc?.sample_rate),
          },
          u.sampleRand,
        ),
    f = new Wa({
      ...e,
      attributes: {
        [ir]: "custom",
        [ip]: l !== void 0 && p ? l : void 0,
        ...c,
      },
      sampled: d,
    });
  return (
    !d &&
      r &&
      (he &&
        ce.log(
          "[Tracing] Discarding root span because its trace was not chosen to be sampled.",
        ),
      r.recordDroppedEvent("sample_rate", "transaction")),
    r && r.emit("spanStart", f),
    f
  );
}
function qv(e, t, n) {
  const { spanId: r, traceId: s } = e.spanContext(),
    i = t.getScopeData().sdkProcessingMetadata[hp] ? !1 : Ir(e),
    o = i
      ? new Wa({ ...n, parentSpanId: r, traceId: s, sampled: i })
      : new mi({ traceId: s });
  fp(e, o);
  const a = Nt();
  return (
    a && (a.emit("spanStart", o), n.endTimestamp && a.emit("spanEnd", o)),
    o
  );
}
function Sp(e, t) {
  if (t) return t;
  if (t === null) return;
  const n = Ds(e);
  if (!n) return;
  const r = Nt();
  return (r ? r.getOptions() : {}).parentSpanIsAlwaysRootSpan ? ze(n) : n;
}
function Gv(e) {
  return e !== void 0 ? (t) => za(e, t) : (t) => t();
}
function Vv(e) {
  if (!e) return {};
  const t = e.match(
    /^(([^:/?#]+):)?(\/\/([^/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?$/,
  );
  if (!t) return {};
  const n = t[6] || "",
    r = t[8] || "";
  return {
    host: t[4],
    path: t[5],
    protocol: t[2],
    search: n,
    hash: r,
    relative: t[5] + n + r,
  };
}
const sl = Oe;
function Yv() {
  return "history" in sl && !!sl.history;
}
function Xv(e) {
  return (
    e && /^function\s+\w+\(\)\s+\{\s+\[native code\]\s+\}$/.test(e.toString())
  );
}
const Sn = typeof __SENTRY_DEBUG__ > "u" || __SENTRY_DEBUG__,
  H = Oe,
  Kv = (e, t) => (e > t[1] ? "poor" : e > t[0] ? "needs-improvement" : "good"),
  kr = (e, t, n, r) => {
    let s, i;
    return (o) => {
      t.value >= 0 &&
        (o || r) &&
        ((i = t.value - (s ?? 0)),
        (i || s === void 0) &&
          ((s = t.value), (t.delta = i), (t.rating = Kv(t.value, n)), e(t)));
    };
  },
  Jv = () =>
    `v5-${Date.now()}-${Math.floor(Math.random() * (9e12 - 1)) + 1e12}`,
  Cr = (e = !0) => {
    const t = H.performance?.getEntriesByType?.("navigation")[0];
    if (!e || (t && t.responseStart > 0 && t.responseStart < performance.now()))
      return t;
  },
  An = () => Cr()?.activationStart ?? 0,
  Rr = (e, t = -1) => {
    const n = Cr();
    let r = "navigate";
    return (
      n &&
        (H.document?.prerendering || An() > 0
          ? (r = "prerender")
          : H.document?.wasDiscarded
            ? (r = "restore")
            : n.type && (r = n.type.replace(/_/g, "-"))),
      {
        name: e,
        value: t,
        rating: "good",
        delta: 0,
        entries: [],
        id: Jv(),
        navigationType: r,
      }
    );
  },
  Vi = new WeakMap();
function qa(e, t) {
  return (Vi.get(e) || Vi.set(e, new t()), Vi.get(e));
}
class Bs {
  constructor() {
    (Bs.prototype.__init.call(this), Bs.prototype.__init2.call(this));
  }
  __init() {
    this._sessionValue = 0;
  }
  __init2() {
    this._sessionEntries = [];
  }
  _processEntry(t) {
    if (t.hadRecentInput) return;
    const n = this._sessionEntries[0],
      r = this._sessionEntries[this._sessionEntries.length - 1];
    (this._sessionValue &&
    n &&
    r &&
    t.startTime - r.startTime < 1e3 &&
    t.startTime - n.startTime < 5e3
      ? ((this._sessionValue += t.value), this._sessionEntries.push(t))
      : ((this._sessionValue = t.value), (this._sessionEntries = [t])),
      this._onAfterProcessingUnexpectedShift?.(t));
  }
}
const Mn = (e, t, n = {}) => {
    try {
      if (PerformanceObserver.supportedEntryTypes.includes(e)) {
        const r = new PerformanceObserver((s) => {
          Promise.resolve().then(() => {
            t(s.getEntries());
          });
        });
        return (r.observe({ type: e, buffered: !0, ...n }), r);
      }
    } catch {}
  },
  Ga = (e) => {
    let t = !1;
    return () => {
      t || (e(), (t = !0));
    };
  };
let qn = -1;
const Zv = () =>
    H.document?.visibilityState === "hidden" && !H.document?.prerendering
      ? 0
      : 1 / 0,
  Us = (e) => {
    H.document.visibilityState === "hidden" &&
      qn > -1 &&
      ((qn = e.type === "visibilitychange" ? e.timeStamp : 0), eT());
  },
  Qv = () => {
    (addEventListener("visibilitychange", Us, !0),
      addEventListener("prerenderingchange", Us, !0));
  },
  eT = () => {
    (removeEventListener("visibilitychange", Us, !0),
      removeEventListener("prerenderingchange", Us, !0));
  },
  Va = () => {
    if (H.document && qn < 0) {
      const e = An();
      ((qn =
        (H.document.prerendering
          ? void 0
          : globalThis.performance
              .getEntriesByType("visibility-state")
              .filter((n) => n.name === "hidden" && n.startTime > e)[0]
              ?.startTime) ?? Zv()),
        Qv());
    }
    return {
      get firstHiddenTime() {
        return qn;
      },
    };
  },
  gi = (e) => {
    H.document?.prerendering
      ? addEventListener("prerenderingchange", () => e(), !0)
      : e();
  },
  tT = [1800, 3e3],
  nT = (e, t = {}) => {
    gi(() => {
      const n = Va(),
        r = Rr("FCP");
      let s;
      const o = Mn("paint", (a) => {
        for (const c of a)
          c.name === "first-contentful-paint" &&
            (o.disconnect(),
            c.startTime < n.firstHiddenTime &&
              ((r.value = Math.max(c.startTime - An(), 0)),
              r.entries.push(c),
              s(!0)));
      });
      o && (s = kr(e, r, tT, t.reportAllChanges));
    });
  },
  rT = [0.1, 0.25],
  sT = (e, t = {}) => {
    nT(
      Ga(() => {
        const n = Rr("CLS", 0);
        let r;
        const s = qa(t, Bs),
          i = (a) => {
            for (const c of a) s._processEntry(c);
            s._sessionValue > n.value &&
              ((n.value = s._sessionValue),
              (n.entries = s._sessionEntries),
              r());
          },
          o = Mn("layout-shift", i);
        o &&
          ((r = kr(e, n, rT, t.reportAllChanges)),
          H.document?.addEventListener("visibilitychange", () => {
            H.document?.visibilityState === "hidden" &&
              (i(o.takeRecords()), r(!0));
          }),
          H?.setTimeout?.(r));
      }),
    );
  };
let yp = 0,
  Yi = 1 / 0,
  Hr = 0;
const iT = (e) => {
  e.forEach((t) => {
    t.interactionId &&
      ((Yi = Math.min(Yi, t.interactionId)),
      (Hr = Math.max(Hr, t.interactionId)),
      (yp = Hr ? (Hr - Yi) / 7 + 1 : 0));
  });
};
let Ao;
const bp = () => (Ao ? yp : performance.interactionCount || 0),
  oT = () => {
    "interactionCount" in performance ||
      Ao ||
      (Ao = Mn("event", iT, {
        type: "event",
        buffered: !0,
        durationThreshold: 0,
      }));
  },
  Xi = 10;
let Ep = 0;
const aT = () => bp() - Ep;
class Hs {
  constructor() {
    (Hs.prototype.__init.call(this), Hs.prototype.__init2.call(this));
  }
  __init() {
    this._longestInteractionList = [];
  }
  __init2() {
    this._longestInteractionMap = new Map();
  }
  _resetInteractions() {
    ((Ep = bp()),
      (this._longestInteractionList.length = 0),
      this._longestInteractionMap.clear());
  }
  _estimateP98LongestInteraction() {
    const t = Math.min(
      this._longestInteractionList.length - 1,
      Math.floor(aT() / 50),
    );
    return this._longestInteractionList[t];
  }
  _processEntry(t) {
    if (
      (this._onBeforeProcessingEntry?.(t),
      !(t.interactionId || t.entryType === "first-input"))
    )
      return;
    const n = this._longestInteractionList.at(-1);
    let r = this._longestInteractionMap.get(t.interactionId);
    if (
      r ||
      this._longestInteractionList.length < Xi ||
      t.duration > n._latency
    ) {
      if (
        (r
          ? t.duration > r._latency
            ? ((r.entries = [t]), (r._latency = t.duration))
            : t.duration === r._latency &&
              t.startTime === r.entries[0].startTime &&
              r.entries.push(t)
          : ((r = { id: t.interactionId, entries: [t], _latency: t.duration }),
            this._longestInteractionMap.set(r.id, r),
            this._longestInteractionList.push(r)),
        this._longestInteractionList.sort((s, i) => i._latency - s._latency),
        this._longestInteractionList.length > Xi)
      ) {
        const s = this._longestInteractionList.splice(Xi);
        for (const i of s) this._longestInteractionMap.delete(i.id);
      }
      this._onAfterProcessingINPCandidate?.(r);
    }
  }
}
const Ya = (e) => {
    const t = (n) => {
      (n.type === "pagehide" || H.document?.visibilityState === "hidden") &&
        e(n);
    };
    H.document &&
      (addEventListener("visibilitychange", t, !0),
      addEventListener("pagehide", t, !0));
  },
  vp = (e) => {
    const t = H.requestIdleCallback || H.setTimeout;
    H.document?.visibilityState === "hidden" ? e() : ((e = Ga(e)), t(e), Ya(e));
  },
  cT = [200, 500],
  uT = 40,
  lT = (e, t = {}) => {
    globalThis.PerformanceEventTiming &&
      "interactionId" in PerformanceEventTiming.prototype &&
      gi(() => {
        oT();
        const n = Rr("INP");
        let r;
        const s = qa(t, Hs),
          i = (a) => {
            vp(() => {
              for (const u of a) s._processEntry(u);
              const c = s._estimateP98LongestInteraction();
              c &&
                c._latency !== n.value &&
                ((n.value = c._latency), (n.entries = c.entries), r());
            });
          },
          o = Mn("event", i, { durationThreshold: t.durationThreshold ?? uT });
        ((r = kr(e, n, cT, t.reportAllChanges)),
          o &&
            (o.observe({ type: "first-input", buffered: !0 }),
            Ya(() => {
              (i(o.takeRecords()), r(!0));
            })));
      });
  };
class dT {
  _processEntry(t) {
    this._onBeforeProcessingEntry?.(t);
  }
}
const fT = [2500, 4e3],
  pT = (e, t = {}) => {
    gi(() => {
      const n = Va(),
        r = Rr("LCP");
      let s;
      const i = qa(t, dT),
        o = (c) => {
          t.reportAllChanges || (c = c.slice(-1));
          for (const u of c)
            (i._processEntry(u),
              u.startTime < n.firstHiddenTime &&
                ((r.value = Math.max(u.startTime - An(), 0)),
                (r.entries = [u]),
                s()));
        },
        a = Mn("largest-contentful-paint", o);
      if (a) {
        s = kr(e, r, fT, t.reportAllChanges);
        const c = Ga(() => {
          (o(a.takeRecords()), a.disconnect(), s(!0));
        });
        for (const u of ["keydown", "click", "visibilitychange"])
          H.document &&
            addEventListener(u, () => vp(c), { capture: !0, once: !0 });
      }
    });
  },
  hT = [800, 1800],
  Mo = (e) => {
    H.document?.prerendering
      ? gi(() => Mo(e))
      : H.document?.readyState !== "complete"
        ? addEventListener("load", () => Mo(e), !0)
        : setTimeout(e);
  },
  mT = (e, t = {}) => {
    const n = Rr("TTFB"),
      r = kr(e, n, hT, t.reportAllChanges);
    Mo(() => {
      const s = Cr();
      s &&
        ((n.value = Math.max(s.responseStart - An(), 0)),
        (n.entries = [s]),
        r(!0));
    });
  },
  Gn = {},
  Ws = {};
let Tp, wp, Ip, kp;
function Xa(e, t = !1) {
  return _i("cls", e, _T, Tp, t);
}
function Ka(e, t = !1) {
  return _i("lcp", e, ST, wp, t);
}
function gT(e) {
  return _i("ttfb", e, yT, Ip);
}
function Cp(e) {
  return _i("inp", e, bT, kp);
}
function Xt(e, t) {
  return (Rp(e, t), Ws[e] || (ET(e), (Ws[e] = !0)), xp(e, t));
}
function xr(e, t) {
  const n = Gn[e];
  if (n?.length)
    for (const r of n)
      try {
        r(t);
      } catch (s) {
        Sn &&
          ce.error(
            `Error while triggering instrumentation handler.
Type: ${e}
Name: ${Zf(r)}
Error:`,
            s,
          );
      }
}
function _T() {
  return sT(
    (e) => {
      (xr("cls", { metric: e }), (Tp = e));
    },
    { reportAllChanges: !0 },
  );
}
function ST() {
  return pT(
    (e) => {
      (xr("lcp", { metric: e }), (wp = e));
    },
    { reportAllChanges: !0 },
  );
}
function yT() {
  return mT((e) => {
    (xr("ttfb", { metric: e }), (Ip = e));
  });
}
function bT() {
  return lT((e) => {
    (xr("inp", { metric: e }), (kp = e));
  });
}
function _i(e, t, n, r, s = !1) {
  Rp(e, t);
  let i;
  return (
    Ws[e] || ((i = n()), (Ws[e] = !0)),
    r && t({ metric: r }),
    xp(e, t, s ? i : void 0)
  );
}
function ET(e) {
  const t = {};
  (e === "event" && (t.durationThreshold = 0),
    Mn(
      e,
      (n) => {
        xr(e, { entries: n });
      },
      t,
    ));
}
function Rp(e, t) {
  ((Gn[e] = Gn[e] || []), Gn[e].push(t));
}
function xp(e, t, n) {
  return () => {
    n && n();
    const r = Gn[e];
    if (!r) return;
    const s = r.indexOf(t);
    s !== -1 && r.splice(s, 1);
  };
}
function vT(e) {
  return "duration" in e;
}
function Ki(e) {
  return typeof e == "number" && isFinite(e);
}
function At(e, t, n, { ...r }) {
  const s = be(e).start_timestamp;
  return (
    s &&
      s > t &&
      typeof e.updateStartTime == "function" &&
      e.updateStartTime(t),
    za(e, () => {
      const i = mp({ startTime: t, ...r });
      return (i && i.end(n), i);
    })
  );
}
function Ja(e) {
  const t = Nt();
  if (!t) return;
  const { name: n, transaction: r, attributes: s, startTime: i } = e,
    { release: o, environment: a, sendDefaultPii: c } = t.getOptions(),
    d = t.getIntegrationByName("Replay")?.getReplayId(),
    l = et(),
    p = l.getUser(),
    f = p !== void 0 ? p.email || p.id || p.ip_address : void 0;
  let h;
  try {
    h = l.getScopeData().contexts.profile.profile_id;
  } catch {}
  const m = {
    release: o,
    environment: a,
    user: f || void 0,
    profile_id: h || void 0,
    replay_id: d || void 0,
    transaction: r,
    "user_agent.original": H.navigator?.userAgent,
    "client.address": c ? "{{auto}}" : void 0,
    ...s,
  };
  return mp({
    name: n,
    attributes: m,
    startTime: i,
    experimental: { standalone: !0 },
  });
}
function Ar() {
  return H.addEventListener && H.performance;
}
function me(e) {
  return e / 1e3;
}
function TT(e) {
  let t = "unknown",
    n = "unknown",
    r = "";
  for (const s of e) {
    if (s === "/") {
      [t, n] = e.split("/");
      break;
    }
    if (!isNaN(Number(s))) {
      ((t = r === "h" ? "http" : r), (n = e.split(r)[1]));
      break;
    }
    r += s;
  }
  return (r === e && (t = r), { name: t, version: n });
}
function Ap(e) {
  try {
    return PerformanceObserver.supportedEntryTypes.includes(e);
  } catch {
    return !1;
  }
}
function Mp(e, t) {
  let n,
    r = !1;
  function s(a) {
    (!r && n && t(a, n), (r = !0));
  }
  Ya(() => {
    s("pagehide");
  });
  const i = e.on("beforeStartNavigationSpan", (a, c) => {
      c?.isRedirect || (s("navigation"), i(), o());
    }),
    o = e.on("afterStartPageLoadSpan", (a) => {
      ((n = a.spanContext().spanId), o());
    });
}
function wT(e) {
  let t = 0,
    n;
  if (!Ap("layout-shift")) return;
  const r = Xa(({ metric: s }) => {
    const i = s.entries[s.entries.length - 1];
    i && ((t = s.value), (n = i));
  }, !0);
  Mp(e, (s, i) => {
    (IT(t, n, i, s), r());
  });
}
function IT(e, t, n, r) {
  Sn && ce.log(`Sending CLS span (${e})`);
  const s = t ? me((Fe() || 0) + t.startTime) : at(),
    i = et().getScopeData().transactionName,
    o = t ? xt(t.sources[0]?.node) : "Layout shift",
    a = {
      [we]: "auto.http.browser.cls",
      [Yt]: "ui.webvital.cls",
      [hi]: 0,
      "sentry.pageload.span_id": n,
      "sentry.report_event": r,
    };
  t?.sources &&
    t.sources.forEach((u, d) => {
      a[`cls.source.${d + 1}`] = xt(u.node);
    });
  const c = Ja({ name: o, transaction: i, attributes: a, startTime: s });
  c && (c.addEvent("cls", { [Tr]: "", [wr]: e }), c.end(s));
}
function kT(e) {
  let t = 0,
    n;
  if (!Ap("largest-contentful-paint")) return;
  const r = Ka(({ metric: s }) => {
    const i = s.entries[s.entries.length - 1];
    i && ((t = s.value), (n = i));
  }, !0);
  Mp(e, (s, i) => {
    (CT(t, n, i, s), r());
  });
}
function CT(e, t, n, r) {
  Sn && ce.log(`Sending LCP span (${e})`);
  const s = me((Fe() || 0) + (t?.startTime || 0)),
    i = et().getScopeData().transactionName,
    o = t ? xt(t.element) : "Largest contentful paint",
    a = {
      [we]: "auto.http.browser.lcp",
      [Yt]: "ui.webvital.lcp",
      [hi]: 0,
      "sentry.pageload.span_id": n,
      "sentry.report_event": r,
    };
  t &&
    (t.element && (a["lcp.element"] = xt(t.element)),
    t.id && (a["lcp.id"] = t.id),
    t.url && (a["lcp.url"] = t.url.trim().slice(0, 200)),
    t.loadTime != null && (a["lcp.loadTime"] = t.loadTime),
    t.renderTime != null && (a["lcp.renderTime"] = t.renderTime),
    t.size != null && (a["lcp.size"] = t.size));
  const c = Ja({ name: o, transaction: i, attributes: a, startTime: s });
  c && (c.addEvent("lcp", { [Tr]: "millisecond", [wr]: e }), c.end(s));
}
function De(e) {
  return e && ((Fe() || performance.timeOrigin) + e) / 1e3;
}
function Np(e) {
  const t = {};
  if (e.nextHopProtocol != null) {
    const { name: n, version: r } = TT(e.nextHopProtocol);
    ((t["network.protocol.version"] = r), (t["network.protocol.name"] = n));
  }
  return Fe() || Ar()?.timeOrigin
    ? RT({
        ...t,
        "http.request.redirect_start": De(e.redirectStart),
        "http.request.redirect_end": De(e.redirectEnd),
        "http.request.worker_start": De(e.workerStart),
        "http.request.fetch_start": De(e.fetchStart),
        "http.request.domain_lookup_start": De(e.domainLookupStart),
        "http.request.domain_lookup_end": De(e.domainLookupEnd),
        "http.request.connect_start": De(e.connectStart),
        "http.request.secure_connection_start": De(e.secureConnectionStart),
        "http.request.connection_end": De(e.connectEnd),
        "http.request.request_start": De(e.requestStart),
        "http.request.response_start": De(e.responseStart),
        "http.request.response_end": De(e.responseEnd),
        "http.request.time_to_first_byte":
          e.responseStart != null ? e.responseStart / 1e3 : void 0,
      })
    : t;
}
function RT(e) {
  return Object.fromEntries(Object.entries(e).filter(([, t]) => t != null));
}
const xT = 2147483647;
let il = 0,
  He = {},
  Ie,
  zs;
function AT({
  recordClsStandaloneSpans: e,
  recordLcpStandaloneSpans: t,
  client: n,
}) {
  const r = Ar();
  if (r && Fe()) {
    r.mark && H.performance.mark("sentry-tracing-init");
    const s = t ? kT(n) : $T(),
      i = DT(),
      o = e ? wT(n) : LT();
    return () => {
      (s?.(), i(), o?.());
    };
  }
  return () => {};
}
function MT() {
  Xt("longtask", ({ entries: e }) => {
    const t = Jt();
    if (!t) return;
    const { op: n, start_timestamp: r } = be(t);
    for (const s of e) {
      const i = me(Fe() + s.startTime),
        o = me(s.duration);
      (n === "navigation" && r && i < r) ||
        At(t, i, i + o, {
          name: "Main UI thread blocked",
          op: "ui.long-task",
          attributes: { [we]: "auto.ui.browser.metrics" },
        });
    }
  });
}
function NT() {
  new PerformanceObserver((t) => {
    const n = Jt();
    if (n)
      for (const r of t.getEntries()) {
        if (!r.scripts[0]) continue;
        const s = me(Fe() + r.startTime),
          { start_timestamp: i, op: o } = be(n);
        if (o === "navigation" && i && s < i) continue;
        const a = me(r.duration),
          c = { [we]: "auto.ui.browser.metrics" },
          u = r.scripts[0],
          {
            invoker: d,
            invokerType: l,
            sourceURL: p,
            sourceFunctionName: f,
            sourceCharPosition: h,
          } = u;
        ((c["browser.script.invoker"] = d),
          (c["browser.script.invoker_type"] = l),
          p && (c["code.filepath"] = p),
          f && (c["code.function"] = f),
          h !== -1 && (c["browser.script.source_char_position"] = h),
          At(n, s, s + a, {
            name: "Main UI thread blocked",
            op: "ui.long-animation-frame",
            attributes: c,
          }));
      }
  }).observe({ type: "long-animation-frame", buffered: !0 });
}
function OT() {
  Xt("event", ({ entries: e }) => {
    const t = Jt();
    if (t) {
      for (const n of e)
        if (n.name === "click") {
          const r = me(Fe() + n.startTime),
            s = me(n.duration),
            i = {
              name: xt(n.target),
              op: `ui.interaction.${n.name}`,
              startTime: r,
              attributes: { [we]: "auto.ui.browser.metrics" },
            },
            o = GE(n.target);
          (o && (i.attributes["ui.component_name"] = o), At(t, r, r + s, i));
        }
    }
  });
}
function LT() {
  return Xa(({ metric: e }) => {
    const t = e.entries[e.entries.length - 1];
    t && ((He.cls = { value: e.value, unit: "" }), (zs = t));
  }, !0);
}
function $T() {
  return Ka(({ metric: e }) => {
    const t = e.entries[e.entries.length - 1];
    t && ((He.lcp = { value: e.value, unit: "millisecond" }), (Ie = t));
  }, !0);
}
function DT() {
  return gT(({ metric: e }) => {
    e.entries[e.entries.length - 1] &&
      (He.ttfb = { value: e.value, unit: "millisecond" });
  });
}
function PT(e, t) {
  const n = Ar(),
    r = Fe();
  if (!n?.getEntries || !r) return;
  const s = me(r),
    i = n.getEntries(),
    { op: o, start_timestamp: a } = be(e);
  (i.slice(il).forEach((c) => {
    const u = me(c.startTime),
      d = me(Math.max(0, c.duration));
    if (!(o === "navigation" && a && s + u < a))
      switch (c.entryType) {
        case "navigation": {
          UT(e, c, s);
          break;
        }
        case "mark":
        case "paint":
        case "measure": {
          FT(e, c, u, d, s, t.ignorePerformanceApiSpans);
          const l = Va(),
            p = c.startTime < l.firstHiddenTime;
          (c.name === "first-paint" &&
            p &&
            (He.fp = { value: c.startTime, unit: "millisecond" }),
            c.name === "first-contentful-paint" &&
              p &&
              (He.fcp = { value: c.startTime, unit: "millisecond" }));
          break;
        }
        case "resource": {
          zT(e, c, c.name, u, d, s, t.ignoreResourceSpans);
          break;
        }
      }
  }),
    (il = Math.max(i.length - 1, 0)),
    jT(e),
    o === "pageload" &&
      (VT(He),
      t.recordClsOnPageloadSpan || delete He.cls,
      t.recordLcpOnPageloadSpan || delete He.lcp,
      Object.entries(He).forEach(([c, u]) => {
        Fv(c, u.value, u.unit);
      }),
      e.setAttribute("performance.timeOrigin", s),
      e.setAttribute("performance.activationStart", An()),
      qT(e, t)),
    (Ie = void 0),
    (zs = void 0),
    (He = {}));
}
function FT(e, t, n, r, s, i) {
  if (["mark", "measure"].includes(t.entryType) && YE(t.name, i)) return;
  const o = Cr(!1),
    a = me(o ? o.requestStart : 0),
    c = s + Math.max(n, a),
    u = s + n,
    d = u + r,
    l = { [we]: "auto.resource.browser.metrics" };
  (c !== u &&
    ((l["sentry.browser.measure_happened_before_request"] = !0),
    (l["sentry.browser.measure_start_time"] = c)),
    BT(l, t),
    c <= d && At(e, c, d, { name: t.name, op: t.entryType, attributes: l }));
}
function BT(e, t) {
  try {
    const n = t.detail;
    if (!n) return;
    if (typeof n == "object") {
      for (const [r, s] of Object.entries(n))
        if (s && qu(s)) e[`sentry.browser.measure.detail.${r}`] = s;
        else if (s !== void 0)
          try {
            e[`sentry.browser.measure.detail.${r}`] = JSON.stringify(s);
          } catch {}
      return;
    }
    if (qu(n)) {
      e["sentry.browser.measure.detail"] = n;
      return;
    }
    try {
      e["sentry.browser.measure.detail"] = JSON.stringify(n);
    } catch {}
  } catch {}
}
function UT(e, t, n) {
  ([
    "unloadEvent",
    "redirect",
    "domContentLoadedEvent",
    "loadEvent",
    "connect",
  ].forEach((r) => {
    Wr(e, t, r, n);
  }),
    Wr(e, t, "secureConnection", n, "TLS/SSL"),
    Wr(e, t, "fetch", n, "cache"),
    Wr(e, t, "domainLookup", n, "DNS"),
    WT(e, t, n));
}
function Wr(e, t, n, r, s = n) {
  const i = HT(n),
    o = t[i],
    a = t[`${n}Start`];
  !a ||
    !o ||
    At(e, r + me(a), r + me(o), {
      op: `browser.${s}`,
      name: t.name,
      attributes: {
        [we]: "auto.ui.browser.metrics",
        ...(n === "redirect" && t.redirectCount != null
          ? { "http.redirect_count": t.redirectCount }
          : {}),
      },
    });
}
function HT(e) {
  return e === "secureConnection"
    ? "connectEnd"
    : e === "fetch"
      ? "domainLookupStart"
      : `${e}End`;
}
function WT(e, t, n) {
  const r = n + me(t.requestStart),
    s = n + me(t.responseEnd),
    i = n + me(t.responseStart);
  t.responseEnd &&
    (At(e, r, s, {
      op: "browser.request",
      name: t.name,
      attributes: { [we]: "auto.ui.browser.metrics" },
    }),
    At(e, i, s, {
      op: "browser.response",
      name: t.name,
      attributes: { [we]: "auto.ui.browser.metrics" },
    }));
}
function zT(e, t, n, r, s, i, o) {
  if (t.initiatorType === "xmlhttprequest" || t.initiatorType === "fetch")
    return;
  const a = t.initiatorType ? `resource.${t.initiatorType}` : "resource.other";
  if (o?.includes(a)) return;
  const c = { [we]: "auto.resource.browser.metrics" },
    u = Vv(n);
  (u.protocol && (c["url.scheme"] = u.protocol.split(":").pop()),
    u.host && (c["server.address"] = u.host),
    (c["url.same_origin"] = n.includes(H.location.origin)),
    GT(t, c, [
      ["responseStatus", "http.response.status_code"],
      ["transferSize", "http.response_transfer_size"],
      ["encodedBodySize", "http.response_content_length"],
      ["decodedBodySize", "http.decoded_response_content_length"],
      ["renderBlockingStatus", "resource.render_blocking_status"],
      ["deliveryType", "http.response_delivery_type"],
    ]));
  const d = { ...c, ...Np(t) },
    l = i + r,
    p = l + s;
  At(e, l, p, { name: n.replace(H.location.origin, ""), op: a, attributes: d });
}
function jT(e) {
  const t = H.navigator;
  if (!t) return;
  const n = t.connection;
  (n &&
    (n.effectiveType &&
      e.setAttribute("effectiveConnectionType", n.effectiveType),
    n.type && e.setAttribute("connectionType", n.type),
    Ki(n.rtt) &&
      (He["connection.rtt"] = { value: n.rtt, unit: "millisecond" })),
    Ki(t.deviceMemory) &&
      e.setAttribute("deviceMemory", `${t.deviceMemory} GB`),
    Ki(t.hardwareConcurrency) &&
      e.setAttribute("hardwareConcurrency", String(t.hardwareConcurrency)));
}
function qT(e, t) {
  (Ie &&
    t.recordLcpOnPageloadSpan &&
    (Ie.element && e.setAttribute("lcp.element", xt(Ie.element)),
    Ie.id && e.setAttribute("lcp.id", Ie.id),
    Ie.url && e.setAttribute("lcp.url", Ie.url.trim().slice(0, 200)),
    Ie.loadTime != null && e.setAttribute("lcp.loadTime", Ie.loadTime),
    Ie.renderTime != null && e.setAttribute("lcp.renderTime", Ie.renderTime),
    e.setAttribute("lcp.size", Ie.size)),
    zs?.sources &&
      t.recordClsOnPageloadSpan &&
      zs.sources.forEach((n, r) =>
        e.setAttribute(`cls.source.${r + 1}`, xt(n.node)),
      ));
}
function GT(e, t, n) {
  n.forEach(([r, s]) => {
    const i = e[r];
    i != null &&
      ((typeof i == "number" && i < xT) || typeof i == "string") &&
      (t[s] = i);
  });
}
function VT(e) {
  const t = Cr(!1);
  if (!t) return;
  const { responseStart: n, requestStart: r } = t;
  r <= n && (e["ttfb.requestTime"] = { value: n - r, unit: "millisecond" });
}
function YT() {
  return Ar() && Fe() ? Xt("element", XT) : () => {};
}
const XT = ({ entries: e }) => {
    const t = Jt(),
      n = t ? ze(t) : void 0,
      r = n ? be(n).description : et().getScopeData().transactionName;
    e.forEach((s) => {
      const i = s;
      if (!i.identifier) return;
      const o = i.name,
        a = i.renderTime,
        c = i.loadTime,
        [u, d] = c
          ? [me(c), "load-time"]
          : a
            ? [me(a), "render-time"]
            : [at(), "entry-emission"],
        l = o === "image-paint" ? me(Math.max(0, (a ?? 0) - (c ?? 0))) : 0,
        p = {
          [we]: "auto.ui.browser.elementtiming",
          [Yt]: "ui.elementtiming",
          [ir]: "component",
          "sentry.span_start_time_source": d,
          "sentry.transaction_name": r,
          "element.id": i.id,
          "element.type": i.element?.tagName?.toLowerCase() || "unknown",
          "element.size":
            i.naturalWidth && i.naturalHeight
              ? `${i.naturalWidth}x${i.naturalHeight}`
              : void 0,
          "element.render_time": a,
          "element.load_time": c,
          "element.url": i.url || void 0,
          "element.identifier": i.identifier,
          "element.paint_type": o,
        };
      jv(
        {
          name: `element[${i.identifier}]`,
          attributes: p,
          startTime: u,
          onlyIfParent: !0,
        },
        (f) => {
          f.end(u + l);
        },
      );
    });
  },
  KT = 1e3;
let ol, No, Oo;
function Op(e) {
  (Da("dom", e), Pa("dom", JT));
}
function JT() {
  if (!H.document) return;
  const e = sr.bind(null, "dom"),
    t = al(e, !0);
  (H.document.addEventListener("click", t, !1),
    H.document.addEventListener("keypress", t, !1),
    ["EventTarget", "Node"].forEach((n) => {
      const s = H[n]?.prototype;
      s?.hasOwnProperty?.("addEventListener") &&
        (Os(s, "addEventListener", function (i) {
          return function (o, a, c) {
            if (o === "click" || o == "keypress")
              try {
                const u = (this.__sentry_instrumentation_handlers__ =
                    this.__sentry_instrumentation_handlers__ || {}),
                  d = (u[o] = u[o] || { refCount: 0 });
                if (!d.handler) {
                  const l = al(e);
                  ((d.handler = l), i.call(this, o, l, c));
                }
                d.refCount++;
              } catch {}
            return i.call(this, o, a, c);
          };
        }),
        Os(s, "removeEventListener", function (i) {
          return function (o, a, c) {
            if (o === "click" || o == "keypress")
              try {
                const u = this.__sentry_instrumentation_handlers__ || {},
                  d = u[o];
                d &&
                  (d.refCount--,
                  d.refCount <= 0 &&
                    (i.call(this, o, d.handler, c),
                    (d.handler = void 0),
                    delete u[o]),
                  Object.keys(u).length === 0 &&
                    delete this.__sentry_instrumentation_handlers__);
              } catch {}
            return i.call(this, o, a, c);
          };
        }));
    }));
}
function ZT(e) {
  if (e.type !== No) return !1;
  try {
    if (!e.target || e.target._sentryId !== Oo) return !1;
  } catch {}
  return !0;
}
function QT(e, t) {
  return e !== "keypress"
    ? !1
    : t?.tagName
      ? !(
          t.tagName === "INPUT" ||
          t.tagName === "TEXTAREA" ||
          t.isContentEditable
        )
      : !0;
}
function al(e, t = !1) {
  return (n) => {
    if (!n || n._sentryCaptured) return;
    const r = e0(n);
    if (QT(n.type, r)) return;
    (mt(n, "_sentryCaptured", !0),
      r && !r._sentryId && mt(r, "_sentryId", Wt()));
    const s = n.type === "keypress" ? "input" : n.type;
    (ZT(n) ||
      (e({ event: n, name: s, global: t }),
      (No = n.type),
      (Oo = r ? r._sentryId : void 0)),
      clearTimeout(ol),
      (ol = H.setTimeout(() => {
        ((Oo = void 0), (No = void 0));
      }, KT)));
  };
}
function e0(e) {
  try {
    return e.target;
  } catch {
    return null;
  }
}
let zr;
function Si(e) {
  const t = "history";
  (Da(t, e), Pa(t, t0));
}
function t0() {
  if (
    (H.addEventListener("popstate", () => {
      const t = H.location.href,
        n = zr;
      if (((zr = t), n === t)) return;
      sr("history", { from: n, to: t });
    }),
    !Yv())
  )
    return;
  function e(t) {
    return function (...n) {
      const r = n.length > 2 ? n[2] : void 0;
      if (r) {
        const s = zr,
          i = n0(String(r));
        if (((zr = i), s === i)) return t.apply(this, n);
        sr("history", { from: s, to: i });
      }
      return t.apply(this, n);
    };
  }
  (Os(H.history, "pushState", e), Os(H.history, "replaceState", e));
}
function n0(e) {
  try {
    return new URL(e, H.location.origin).toString();
  } catch {
    return e;
  }
}
const ps = {};
function Za(e) {
  const t = ps[e];
  if (t) return t;
  let n = H[e];
  if (Xv(n)) return (ps[e] = n.bind(H));
  const r = H.document;
  if (r && typeof r.createElement == "function")
    try {
      const s = r.createElement("iframe");
      ((s.hidden = !0), r.head.appendChild(s));
      const i = s.contentWindow;
      (i?.[e] && (n = i[e]), r.head.removeChild(s));
    } catch (s) {
      Sn &&
        ce.warn(
          `Could not create sandbox iframe for ${e} check, bailing to window.${e}: `,
          s,
        );
    }
  return n && (ps[e] = n.bind(H));
}
function r0(e) {
  ps[e] = void 0;
}
function Mr(...e) {
  return Za("setTimeout")(...e);
}
const st = "__sentry_xhr_v3__";
function Qa(e) {
  (Da("xhr", e), Pa("xhr", s0));
}
function s0() {
  if (!H.XMLHttpRequest) return;
  const e = XMLHttpRequest.prototype;
  ((e.open = new Proxy(e.open, {
    apply(t, n, r) {
      const s = new Error(),
        i = at() * 1e3,
        o = Tt(r[0]) ? r[0].toUpperCase() : void 0,
        a = i0(r[1]);
      if (!o || !a) return t.apply(n, r);
      ((n[st] = { method: o, url: a, request_headers: {} }),
        o === "POST" &&
          a.match(/sentry_key/) &&
          (n.__sentry_own_request__ = !0));
      const c = () => {
        const u = n[st];
        if (u && n.readyState === 4) {
          try {
            u.status_code = n.status;
          } catch {}
          const d = {
            endTimestamp: at() * 1e3,
            startTimestamp: i,
            xhr: n,
            virtualError: s,
          };
          sr("xhr", d);
        }
      };
      return (
        "onreadystatechange" in n && typeof n.onreadystatechange == "function"
          ? (n.onreadystatechange = new Proxy(n.onreadystatechange, {
              apply(u, d, l) {
                return (c(), u.apply(d, l));
              },
            }))
          : n.addEventListener("readystatechange", c),
        (n.setRequestHeader = new Proxy(n.setRequestHeader, {
          apply(u, d, l) {
            const [p, f] = l,
              h = d[st];
            return (
              h && Tt(p) && Tt(f) && (h.request_headers[p.toLowerCase()] = f),
              u.apply(d, l)
            );
          },
        })),
        t.apply(n, r)
      );
    },
  })),
    (e.send = new Proxy(e.send, {
      apply(t, n, r) {
        const s = n[st];
        if (!s) return t.apply(n, r);
        r[0] !== void 0 && (s.body = r[0]);
        const i = { startTimestamp: at() * 1e3, xhr: n };
        return (sr("xhr", i), t.apply(n, r));
      },
    })));
}
function i0(e) {
  if (Tt(e)) return e;
  try {
    return e.toString();
  } catch {}
}
function Lp(e) {
  return new URLSearchParams(e).toString();
}
function js(e, t = ce) {
  try {
    if (typeof e == "string") return [e];
    if (e instanceof URLSearchParams) return [e.toString()];
    if (e instanceof FormData) return [Lp(e)];
    if (!e) return [void 0];
  } catch (n) {
    return (
      Sn && t.error(n, "Failed to serialize body", e),
      [void 0, "BODY_PARSE_ERROR"]
    );
  }
  return (
    Sn && t.log("Skipping network body because of body type", e),
    [void 0, "UNPARSEABLE_BODY_TYPE"]
  );
}
function ec(e = []) {
  if (!(e.length !== 2 || typeof e[1] != "object")) return e[1].body;
}
const Ji = [],
  hs = new Map(),
  o0 = 60;
function a0() {
  if (Ar() && Fe()) {
    const t = c0();
    return () => {
      t();
    };
  }
  return () => {};
}
const cl = {
  click: "click",
  pointerdown: "click",
  pointerup: "click",
  mousedown: "click",
  mouseup: "click",
  touchstart: "click",
  touchend: "click",
  mouseover: "hover",
  mouseout: "hover",
  mouseenter: "hover",
  mouseleave: "hover",
  pointerover: "hover",
  pointerout: "hover",
  pointerenter: "hover",
  pointerleave: "hover",
  dragstart: "drag",
  dragend: "drag",
  drag: "drag",
  dragenter: "drag",
  dragleave: "drag",
  dragover: "drag",
  drop: "drag",
  keydown: "press",
  keyup: "press",
  keypress: "press",
  input: "press",
};
function c0() {
  return Cp(u0);
}
const u0 = ({ metric: e }) => {
  if (e.value == null) return;
  const t = me(e.value);
  if (t > o0) return;
  const n = e.entries.find((h) => h.duration === e.value && cl[h.name]);
  if (!n) return;
  const { interactionId: r } = n,
    s = cl[n.name],
    i = me(Fe() + n.startTime),
    o = Jt(),
    a = o ? ze(o) : void 0,
    u = (r != null ? hs.get(r) : void 0) || a,
    d = u ? be(u).description : et().getScopeData().transactionName,
    l = xt(n.target),
    p = {
      [we]: "auto.http.browser.inp",
      [Yt]: `ui.interaction.${s}`,
      [hi]: n.duration,
    },
    f = Ja({ name: l, transaction: d, attributes: p, startTime: i });
  f &&
    (f.addEvent("inp", { [Tr]: "millisecond", [wr]: e.value }), f.end(i + t));
};
function l0() {
  const e = ({ entries: t }) => {
    const n = Jt(),
      r = n && ze(n);
    t.forEach((s) => {
      if (!vT(s) || !r) return;
      const i = s.interactionId;
      if (i != null && !hs.has(i)) {
        if (Ji.length > 10) {
          const o = Ji.shift();
          hs.delete(o);
        }
        (Ji.push(i), hs.set(i, r));
      }
    });
  };
  (Xt("event", e), Xt("first-input", e));
}
function tc(e, t = Za("fetch")) {
  let n = 0,
    r = 0;
  async function s(i) {
    const o = i.body.length;
    ((n += o), r++);
    const a = {
      body: i.body,
      method: "POST",
      referrerPolicy: "strict-origin",
      headers: e.headers,
      keepalive: n <= 6e4 && r < 15,
      ...e.fetchOptions,
    };
    try {
      const c = await t(e.url, a);
      return {
        statusCode: c.status,
        headers: {
          "x-sentry-rate-limits": c.headers.get("X-Sentry-Rate-Limits"),
          "retry-after": c.headers.get("Retry-After"),
        },
      };
    } catch (c) {
      throw (r0("fetch"), c);
    } finally {
      ((n -= o), r--);
    }
  }
  return If(e, s);
}
const d0 = 10,
  f0 = 20,
  p0 = 30,
  h0 = 40,
  m0 = 50;
function yn(e, t, n, r) {
  const s = { filename: e, function: t === "<anonymous>" ? dt : t, in_app: !0 };
  return (n !== void 0 && (s.lineno = n), r !== void 0 && (s.colno = r), s);
}
const g0 = /^\s*at (\S+?)(?::(\d+))(?::(\d+))\s*$/i,
  _0 =
    /^\s*at (?:(.+?\)(?: \[.+\])?|.*?) ?\((?:address at )?)?(?:async )?((?:<anonymous>|[-a-z]+:|.*bundle|\/)?.*?)(?::(\d+))?(?::(\d+))?\)?\s*$/i,
  S0 = /\((\S*)(?::(\d+))(?::(\d+))\)/,
  y0 = /at (.+?) ?\(data:(.+?),/,
  b0 = (e) => {
    const t = e.match(y0);
    if (t) return { filename: `<data:${t[2]}>`, function: t[1] };
    const n = g0.exec(e);
    if (n) {
      const [, s, i, o] = n;
      return yn(s, dt, +i, +o);
    }
    const r = _0.exec(e);
    if (r) {
      if (r[2] && r[2].indexOf("eval") === 0) {
        const a = S0.exec(r[2]);
        a && ((r[2] = a[1]), (r[3] = a[2]), (r[4] = a[3]));
      }
      const [i, o] = Bp(r[1] || dt, r[2]);
      return yn(o, i, r[3] ? +r[3] : void 0, r[4] ? +r[4] : void 0);
    }
  },
  $p = [p0, b0],
  E0 =
    /^\s*(.*?)(?:\((.*?)\))?(?:^|@)?((?:[-a-z]+)?:\/.*?|\[native code\]|[^@]*(?:bundle|\d+\.js)|\/[\w\-. /=]+)(?::(\d+))?(?::(\d+))?\s*$/i,
  v0 = /(\S+) line (\d+)(?: > eval line \d+)* > eval/i,
  T0 = (e) => {
    const t = E0.exec(e);
    if (t) {
      if (t[3] && t[3].indexOf(" > eval") > -1) {
        const i = v0.exec(t[3]);
        i &&
          ((t[1] = t[1] || "eval"), (t[3] = i[1]), (t[4] = i[2]), (t[5] = ""));
      }
      let r = t[3],
        s = t[1] || dt;
      return (
        ([s, r] = Bp(s, r)),
        yn(r, s, t[4] ? +t[4] : void 0, t[5] ? +t[5] : void 0)
      );
    }
  },
  Dp = [m0, T0],
  w0 =
    /^\s*at (?:((?:\[object object\])?.+) )?\(?((?:[-a-z]+):.*?):(\d+)(?::(\d+))?\)?\s*$/i,
  I0 = (e) => {
    const t = w0.exec(e);
    return t ? yn(t[2], t[1] || dt, +t[3], t[4] ? +t[4] : void 0) : void 0;
  },
  k0 = [h0, I0],
  C0 = / line (\d+).*script (?:in )?(\S+)(?:: in function (\S+))?$/i,
  R0 = (e) => {
    const t = C0.exec(e);
    return t ? yn(t[2], t[3] || dt, +t[1]) : void 0;
  },
  x0 = [d0, R0],
  A0 =
    / line (\d+), column (\d+)\s*(?:in (?:<anonymous function: ([^>]+)>|([^)]+))\(.*\))? in (.*):\s*$/i,
  M0 = (e) => {
    const t = A0.exec(e);
    return t ? yn(t[5], t[3] || t[4] || dt, +t[1], +t[2]) : void 0;
  },
  N0 = [f0, M0],
  Pp = [$p, Dp],
  Fp = Vm(...Pp),
  Bp = (e, t) => {
    const n = e.indexOf("safari-extension") !== -1,
      r = e.indexOf("safari-web-extension") !== -1;
    return n || r
      ? [
          e.indexOf("@") !== -1 ? e.split("@")[0] : dt,
          n ? `safari-extension:${t}` : `safari-web-extension:${t}`,
        ]
      : [e, t];
  };
function O0(e, { metadata: t, tunnel: n, dsn: r }) {
  const s = {
      event_id: e.event_id,
      sent_at: new Date().toISOString(),
      ...(t?.sdk && { sdk: { name: t.sdk.name, version: t.sdk.version } }),
      ...(!!n && !!r && { dsn: kn(r) }),
    },
    i = L0(e);
  return Mt(s, [i]);
}
function L0(e) {
  return [{ type: "user_report" }, e];
}
const jr = 1024,
  $0 = "Breadcrumbs",
  D0 = (e = {}) => {
    const t = {
      console: !0,
      dom: !0,
      fetch: !0,
      history: !0,
      sentry: !0,
      xhr: !0,
      ...e,
    };
    return {
      name: $0,
      setup(n) {
        (t.console && Ra(B0(n)),
          t.dom && Op(F0(n, t.dom)),
          t.xhr && Qa(U0(n)),
          t.fetch && xa(H0(n)),
          t.history && Si(W0(n)),
          t.sentry && n.on("beforeSendEvent", P0(n)));
      },
    };
  },
  nc = D0;
function P0(e) {
  return function (n) {
    W() === e &&
      ht(
        {
          category: `sentry.${n.type === "transaction" ? "transaction" : "event"}`,
          event_id: n.event_id,
          level: n.level,
          message: Lt(n),
        },
        { event: n },
      );
  };
}
function F0(e, t) {
  return function (r) {
    if (W() !== e) return;
    let s,
      i,
      o = typeof t == "object" ? t.serializeAttribute : void 0,
      a =
        typeof t == "object" && typeof t.maxStringLength == "number"
          ? t.maxStringLength
          : void 0;
    (a &&
      a > jr &&
      (G &&
        S.warn(
          `\`dom.maxStringLength\` cannot exceed ${jr}, but a value of ${a} was configured. Sentry will use ${jr} instead.`,
        ),
      (a = jr)),
      typeof o == "string" && (o = [o]));
    try {
      const u = r.event,
        d = z0(u) ? u.target : u;
      ((s = Ym(d, { keyAttrs: o, maxStringLength: a })), (i = Xm(d)));
    } catch {
      s = "<unknown>";
    }
    if (s.length === 0) return;
    const c = { category: `ui.${r.name}`, message: s };
    (i && (c.data = { "ui.component_name": i }),
      ht(c, { event: r.event, name: r.name, global: r.global }));
  };
}
function B0(e) {
  return function (n) {
    if (W() !== e) return;
    const r = {
      category: "console",
      data: { arguments: n.args, logger: "console" },
      level: $f(n.level),
      message: vs(n.args, " "),
    };
    if (n.level === "assert")
      if (n.args[0] === !1)
        ((r.message = `Assertion failed: ${vs(n.args.slice(1), " ") || "console.assert"}`),
          (r.data.arguments = n.args.slice(1)));
      else return;
    ht(r, { input: n.args, level: n.level });
  };
}
function U0(e) {
  return function (n) {
    if (W() !== e) return;
    const { startTimestamp: r, endTimestamp: s } = n,
      i = n.xhr[st];
    if (!r || !s || !i) return;
    const { method: o, url: a, status_code: c, body: u } = i,
      d = { method: o, url: a, status_code: c },
      l = { xhr: n.xhr, input: u, startTimestamp: r, endTimestamp: s },
      p = { category: "xhr", data: d, type: "http", level: Wf(c) };
    (e.emit("beforeOutgoingRequestBreadcrumb", p, l), ht(p, l));
  };
}
function H0(e) {
  return function (n) {
    if (W() !== e) return;
    const { startTimestamp: r, endTimestamp: s } = n;
    if (
      s &&
      !(n.fetchData.url.match(/sentry_key/) && n.fetchData.method === "POST")
    )
      if ((n.fetchData.method, n.fetchData.url, n.error)) {
        const i = n.fetchData,
          o = {
            data: n.error,
            input: n.args,
            startTimestamp: r,
            endTimestamp: s,
          },
          a = { category: "fetch", data: i, level: "error", type: "http" };
        (e.emit("beforeOutgoingRequestBreadcrumb", a, o), ht(a, o));
      } else {
        const i = n.response,
          o = { ...n.fetchData, status_code: i?.status };
        (n.fetchData.request_body_size,
          n.fetchData.response_body_size,
          i?.status);
        const a = {
            input: n.args,
            response: i,
            startTimestamp: r,
            endTimestamp: s,
          },
          c = {
            category: "fetch",
            data: o,
            type: "http",
            level: Wf(o.status_code),
          };
        (e.emit("beforeOutgoingRequestBreadcrumb", c, a), ht(c, a));
      }
  };
}
function W0(e) {
  return function (n) {
    if (W() !== e) return;
    let r = n.from,
      s = n.to;
    const i = ln(B.location.href);
    let o = r ? ln(r) : void 0;
    const a = ln(s);
    (o?.path || (o = i),
      i.protocol === a.protocol && i.host === a.host && (s = a.relative),
      i.protocol === o.protocol && i.host === o.host && (r = o.relative),
      ht({ category: "navigation", data: { from: r, to: s } }));
  };
}
function z0(e) {
  return !!e && !!e.target;
}
const j0 = [
    "EventTarget",
    "Window",
    "Node",
    "ApplicationCache",
    "AudioTrackList",
    "BroadcastChannel",
    "ChannelMergerNode",
    "CryptoOperation",
    "EventSource",
    "FileReader",
    "HTMLUnknownElement",
    "IDBDatabase",
    "IDBRequest",
    "IDBTransaction",
    "KeyOperation",
    "MediaController",
    "MessagePort",
    "ModalWindow",
    "Notification",
    "SVGElementInstance",
    "Screen",
    "SharedWorker",
    "TextTrack",
    "TextTrackCue",
    "TextTrackList",
    "WebSocket",
    "WebSocketWorker",
    "Worker",
    "XMLHttpRequest",
    "XMLHttpRequestEventTarget",
    "XMLHttpRequestUpload",
  ],
  q0 = "BrowserApiErrors",
  G0 = (e = {}) => {
    const t = {
      XMLHttpRequest: !0,
      eventTarget: !0,
      requestAnimationFrame: !0,
      setInterval: !0,
      setTimeout: !0,
      unregisterOriginalCallbacks: !1,
      ...e,
    };
    return {
      name: q0,
      setupOnce() {
        (t.setTimeout && Xe(B, "setTimeout", ul),
          t.setInterval && Xe(B, "setInterval", ul),
          t.requestAnimationFrame && Xe(B, "requestAnimationFrame", V0),
          t.XMLHttpRequest &&
            "XMLHttpRequest" in B &&
            Xe(XMLHttpRequest.prototype, "send", Y0));
        const n = t.eventTarget;
        n && (Array.isArray(n) ? n : j0).forEach((s) => X0(s, t));
      },
    };
  },
  Up = G0;
function ul(e) {
  return function (...t) {
    const n = t[0];
    return (
      (t[0] = tr(n, {
        mechanism: {
          handled: !1,
          type: `auto.browser.browserapierrors.${zt(e)}`,
        },
      })),
      e.apply(this, t)
    );
  };
}
function V0(e) {
  return function (t) {
    return e.apply(this, [
      tr(t, {
        mechanism: {
          data: { handler: zt(e) },
          handled: !1,
          type: "auto.browser.browserapierrors.requestAnimationFrame",
        },
      }),
    ]);
  };
}
function Y0(e) {
  return function (...t) {
    const n = this;
    return (
      ["onload", "onerror", "onprogress", "onreadystatechange"].forEach((s) => {
        s in n &&
          typeof n[s] == "function" &&
          Xe(n, s, function (i) {
            const o = {
                mechanism: {
                  data: { handler: zt(i) },
                  handled: !1,
                  type: `auto.browser.browserapierrors.xhr.${s}`,
                },
              },
              a = $d(i);
            return (a && (o.mechanism.data.handler = zt(a)), tr(i, o));
          });
      }),
      e.apply(this, t)
    );
  };
}
function X0(e, t) {
  const r = B[e]?.prototype;
  r?.hasOwnProperty?.("addEventListener") &&
    (Xe(r, "addEventListener", function (s) {
      return function (i, o, a) {
        try {
          K0(o) &&
            (o.handleEvent = tr(o.handleEvent, {
              mechanism: {
                data: { handler: zt(o), target: e },
                handled: !1,
                type: "auto.browser.browserapierrors.handleEvent",
              },
            }));
        } catch {}
        return (
          t.unregisterOriginalCallbacks && J0(this, i, o),
          s.apply(this, [
            i,
            tr(o, {
              mechanism: {
                data: { handler: zt(o), target: e },
                handled: !1,
                type: "auto.browser.browserapierrors.addEventListener",
              },
            }),
            a,
          ])
        );
      };
    }),
    Xe(r, "removeEventListener", function (s) {
      return function (i, o, a) {
        try {
          const c = o.__sentry_wrapped__;
          c && s.call(this, i, c, a);
        } catch {}
        return s.call(this, i, o, a);
      };
    }));
}
function K0(e) {
  return typeof e.handleEvent == "function";
}
function J0(e, t, n) {
  e &&
    typeof e == "object" &&
    "removeEventListener" in e &&
    typeof e.removeEventListener == "function" &&
    e.removeEventListener(t, n);
}
const Hp = () => ({
    name: "BrowserSession",
    setupOnce() {
      if (typeof B.document > "u") {
        G &&
          S.warn(
            "Using the `browserSessionIntegration` in non-browser environments is not supported.",
          );
        return;
      }
      (fo({ ignoreDuration: !0 }),
        po(),
        Si(({ from: e, to: t }) => {
          e !== void 0 && e !== t && (fo({ ignoreDuration: !0 }), po());
        }));
    },
  }),
  Z0 = "GlobalHandlers",
  Q0 = (e = {}) => {
    const t = { onerror: !0, onunhandledrejection: !0, ...e };
    return {
      name: Z0,
      setupOnce() {
        Error.stackTraceLimit = 50;
      },
      setup(n) {
        (t.onerror && (ew(n), ll("onerror")),
          t.onunhandledrejection && (tw(n), ll("onunhandledrejection")));
      },
    };
  },
  Wp = Q0;
function ew(e) {
  af((t) => {
    const { stackParser: n, attachStacktrace: r } = zp();
    if (W() !== e || Bd()) return;
    const { msg: s, url: i, line: o, column: a, error: c } = t,
      u = sw(Ma(n, c || s, void 0, r, !1), i, o, a);
    ((u.level = "error"),
      pr(u, {
        originalException: c,
        mechanism: {
          handled: !1,
          type: "auto.browser.global_handlers.onerror",
        },
      }));
  });
}
function tw(e) {
  cf((t) => {
    const { stackParser: n, attachStacktrace: r } = zp();
    if (W() !== e || Bd()) return;
    const s = nw(t),
      i = ri(s) ? rw(s) : Ma(n, s, void 0, r, !0);
    ((i.level = "error"),
      pr(i, {
        originalException: s,
        mechanism: {
          handled: !1,
          type: "auto.browser.global_handlers.onunhandledrejection",
        },
      }));
  });
}
function nw(e) {
  if (ri(e)) return e;
  try {
    if ("reason" in e) return e.reason;
    if ("detail" in e && "reason" in e.detail) return e.detail.reason;
  } catch {}
  return e;
}
function rw(e) {
  return {
    exception: {
      values: [
        {
          type: "UnhandledRejection",
          value: `Non-Error promise rejection captured with value: ${String(e)}`,
        },
      ],
    },
  };
}
function sw(e, t, n, r) {
  const s = (e.exception = e.exception || {}),
    i = (s.values = s.values || []),
    o = (i[0] = i[0] || {}),
    a = (o.stacktrace = o.stacktrace || {}),
    c = (a.frames = a.frames || []),
    u = r,
    d = n,
    l = iw(t) ?? ii();
  return (
    c.length === 0 &&
      c.push({ colno: u, filename: l, function: dt, in_app: !0, lineno: d }),
    e
  );
}
function ll(e) {
  G && S.log(`Global Handler attached: ${e}`);
}
function zp() {
  return W()?.getOptions() || { stackParser: () => [], attachStacktrace: !1 };
}
function iw(e) {
  if (!(!ho(e) || e.length === 0)) {
    if (e.startsWith("data:")) {
      const t = e.match(/^data:([^;]+)/),
        n = t ? t[1] : "text/javascript",
        r = e.includes("base64,");
      return `<data:${n}${r ? ",base64" : ""}>`;
    }
    return e.slice(0, 1024);
  }
}
const jp = () => ({
    name: "HttpContext",
    preprocessEvent(e) {
      if (!B.navigator && !B.location && !B.document) return;
      const t = ua(),
        n = { ...t.headers, ...e.request?.headers };
      e.request = { ...t, ...e.request, headers: n };
    },
  }),
  ow = "cause",
  aw = 5,
  cw = "LinkedErrors",
  uw = (e = {}) => {
    const t = e.limit || aw,
      n = e.key || ow;
    return {
      name: cw,
      preprocessEvent(r, s, i) {
        const o = i.getOptions();
        Wy(pi, o.stackParser, n, t, r, s);
      },
    };
  },
  qp = uw;
function lw() {
  return dw()
    ? (G &&
        si(() => {
          console.error(
            "[Sentry] You cannot use Sentry.init() in a browser extension, see: https://docs.sentry.io/platforms/javascript/best-practices/browser-extensions/",
          );
        }),
      !0)
    : !1;
}
function dw() {
  if (typeof B.window > "u") return !1;
  const e = B;
  if (e.nw || !(e.chrome || e.browser)?.runtime?.id) return !1;
  const n = ii(),
    r = [
      "chrome-extension",
      "moz-extension",
      "ms-browser-extension",
      "safari-web-extension",
    ];
  return !(B === B.top && r.some((i) => n.startsWith(`${i}://`)));
}
function Gp(e) {
  return [Mf(), xf(), Up(), nc(), Wp(), qp(), Df(), jp(), Hp()];
}
function Vp(e = {}) {
  const t = !e.skipBrowserExtensionCheck && lw(),
    n = {
      ...e,
      enabled: t ? !1 : e.enabled,
      stackParser: Km(e.stackParser || Fp),
      integrations: qS({
        integrations: e.integrations,
        defaultIntegrations:
          e.defaultIntegrations == null ? Gp() : e.defaultIntegrations,
      }),
      transport: e.transport || tc,
    };
  return cy(Xf, n);
}
function fw() {}
function pw(e) {
  e();
}
const hw = ne,
  mw = "ReportingObserver",
  dl = new WeakMap(),
  gw = (e = {}) => {
    const t = e.types || ["crash", "deprecation", "intervention"];
    function n(r) {
      if (dl.has(W()))
        for (const s of r)
          qe((i) => {
            i.setExtra("url", s.url);
            const o = `ReportingObserver [${s.type}]`;
            let a = "No details available";
            if (s.body) {
              const c = {};
              for (const u in s.body) c[u] = s.body[u];
              if ((i.setExtra("body", c), s.type === "crash")) {
                const u = s.body;
                a = [u.crashId || "", u.reason || ""].join(" ").trim() || a;
              } else a = s.body.message || a;
            }
            Ts(`${o}: ${a}`);
          });
    }
    return {
      name: mw,
      setupOnce() {
        if (!pE()) return;
        new hw.ReportingObserver(n, { buffered: !0, types: t }).observe();
      },
      setup(r) {
        dl.set(r, !0);
      },
    };
  },
  _w = gw,
  Sw = "HttpClient",
  yw = (e = {}) => {
    const t = {
      failedRequestStatusCodes: [[500, 599]],
      failedRequestTargets: [/.*/],
      ...e,
    };
    return {
      name: Sw,
      setup(n) {
        (Rw(n, t), xw(n, t));
      },
    };
  },
  bw = yw;
function Ew(e, t, n, r, s) {
  if (Xp(e, n.status, n.url)) {
    const i = Aw(t, r);
    let o, a, c, u;
    Jp() && (([o, c] = fl("Cookie", i)), ([a, u] = fl("Set-Cookie", n)));
    const d = Kp({
      url: i.url,
      method: i.method,
      status: n.status,
      requestHeaders: o,
      responseHeaders: a,
      requestCookies: c,
      responseCookies: u,
      error: s,
      type: "fetch",
    });
    pr(d);
  }
}
function fl(e, t) {
  const n = ww(t.headers);
  let r;
  try {
    const s = n[e] || n[e.toLowerCase()] || void 0;
    s && (r = Yp(s));
  } catch {}
  return [n, r];
}
function vw(e, t, n, r, s) {
  if (Xp(e, t.status, t.responseURL)) {
    let i, o, a;
    if (Jp()) {
      try {
        const u =
          t.getResponseHeader("Set-Cookie") ||
          t.getResponseHeader("set-cookie") ||
          void 0;
        u && (o = Yp(u));
      } catch {}
      try {
        a = Iw(t);
      } catch {}
      i = r;
    }
    const c = Kp({
      url: t.responseURL,
      method: n,
      status: t.status,
      requestHeaders: i,
      responseHeaders: a,
      responseCookies: o,
      error: s,
      type: "xhr",
    });
    pr(c);
  }
}
function Tw(e) {
  if (e) {
    const t = e["Content-Length"] || e["content-length"];
    if (t) return parseInt(t, 10);
  }
}
function Yp(e) {
  return e.split("; ").reduce((t, n) => {
    const [r, s] = n.split("=");
    return (r && s && (t[r] = s), t);
  }, {});
}
function ww(e) {
  const t = {};
  return (
    e.forEach((n, r) => {
      t[r] = n;
    }),
    t
  );
}
function Iw(e) {
  const t = e.getAllResponseHeaders();
  return t
    ? t
        .split(
          `\r
`,
        )
        .reduce((n, r) => {
          const [s, i] = r.split(": ");
          return (s && i && (n[s] = i), n);
        }, {})
    : {};
}
function kw(e, t) {
  return e.some((n) => (typeof n == "string" ? t.includes(n) : n.test(t)));
}
function Cw(e, t) {
  return e.some((n) =>
    typeof n == "number" ? n === t : t >= n[0] && t <= n[1],
  );
}
function Rw(e, t) {
  zf() &&
    xa((n) => {
      if (W() !== e) return;
      const { response: r, args: s, error: i, virtualError: o } = n,
        [a, c] = s;
      r && Ew(t, a, r, c, i || o);
    }, !1);
}
function xw(e, t) {
  "XMLHttpRequest" in ne &&
    Qa((n) => {
      if (W() !== e) return;
      const { error: r, virtualError: s } = n,
        i = n.xhr,
        o = i[st];
      if (!o) return;
      const { method: a, request_headers: c } = o;
      try {
        vw(t, i, a, c, r || s);
      } catch (u) {
        G &&
          S.warn("Error while extracting response event form XHR response", u);
      }
    });
}
function Xp(e, t, n) {
  return (
    Cw(e.failedRequestStatusCodes, t) &&
    kw(e.failedRequestTargets, n) &&
    !vy(n, W())
  );
}
function Kp(e) {
  const t = W(),
    n = t && e.error && e.error instanceof Error ? e.error.stack : void 0,
    r = n && t ? t.getOptions().stackParser(n, 0, 1) : void 0,
    s = `HTTP Client Error with status code: ${e.status}`,
    i = {
      message: s,
      exception: {
        values: [
          { type: "Error", value: s, stacktrace: r ? { frames: r } : void 0 },
        ],
      },
      request: {
        url: e.url,
        method: e.method,
        headers: e.requestHeaders,
        cookies: e.requestCookies,
      },
      contexts: {
        response: {
          status_code: e.status,
          headers: e.responseHeaders,
          cookies: e.responseCookies,
          body_size: Tw(e.responseHeaders),
        },
      },
    };
  return (Gt(i, { type: `auto.http.client.${e.type}`, handled: !1 }), i);
}
function Aw(e, t) {
  return (!t && e instanceof Request) || (e instanceof Request && e.bodyUsed)
    ? e
    : new Request(e, t);
}
function Jp() {
  const e = W();
  return e ? !!e.getOptions().sendDefaultPii : !1;
}
const Zi = ne,
  Mw = 7,
  Nw = "ContextLines",
  Ow = (e = {}) => {
    const t = e.frameContextLines != null ? e.frameContextLines : Mw;
    return {
      name: Nw,
      processEvent(n) {
        return $w(n, t);
      },
    };
  },
  Lw = Ow;
function $w(e, t) {
  const n = Zi.document,
    r = Zi.location && Cf(Zi.location.href);
  if (!n || !r) return e;
  const s = e.exception?.values;
  if (!s?.length) return e;
  const i = n.documentElement.innerHTML;
  if (!i) return e;
  const o = [
    "<!DOCTYPE html>",
    "<html>",
    ...i.split(`
`),
    "</html>",
  ];
  return (
    s.forEach((a) => {
      const c = a.stacktrace;
      c?.frames && (c.frames = c.frames.map((u) => Dw(u, o, r, t)));
    }),
    e
  );
}
function Dw(e, t, n, r) {
  return (e.filename !== n || !e.lineno || !t.length || Jm(t, e, r), e);
}
const Pw = "GraphQLClient",
  Fw = (e) => ({
    name: Pw,
    setup(t) {
      (Bw(t, e), Uw(t, e));
    },
  });
function Bw(e, t) {
  e.on("beforeOutgoingRequestSpan", (n, r) => {
    const i = ee(n).data || {};
    if (!(i[Rt] === "http.client")) return;
    const c = i[Zm] || i["http.url"],
      u = i[Qm] || i["http.method"];
    if (!ho(c) || !ho(u)) return;
    const { endpoints: d } = t,
      l = it(c, d),
      p = Qp(r);
    if (l && p) {
      const f = eh(p);
      if (f) {
        const h = Zp(f);
        (n.updateName(`${u} ${c} (${h})`),
          n.setAttribute("graphql.document", p));
      }
    }
  });
}
function Uw(e, t) {
  e.on("beforeOutgoingRequestBreadcrumb", (n, r) => {
    const { category: s, type: i, data: o } = n;
    if (i === "http" && (s === "fetch" || s === "xhr")) {
      const d = o?.url,
        { endpoints: l } = t,
        p = it(d, l),
        f = Qp(r);
      if (p && o && f) {
        const h = eh(f);
        if (!o.graphql && h) {
          const m = Zp(h);
          ((o["graphql.document"] = h.query), (o["graphql.operation"] = m));
        }
      }
    }
  });
}
function Zp(e) {
  const { query: t, operationName: n } = e,
    { operationName: r = n, operationType: s } = Hw(t);
  return r ? `${s} ${r}` : `${s}`;
}
function Qp(e) {
  const t = "xhr" in e;
  let n;
  if (t) {
    const r = e.xhr[st];
    n = r && js(r.body)[0];
  } else {
    const r = ec(e.input);
    n = js(r)[0];
  }
  return n;
}
function Hw(e) {
  const t = /^(?:\s*)(query|mutation|subscription)(?:\s*)(\w+)(?:\s*)[{(]/,
    n = /^(?:\s*)(query|mutation|subscription)(?:\s*)[{(]/,
    r = e.match(t);
  if (r) return { operationType: r[1], operationName: r[2] };
  const s = e.match(n);
  return s
    ? { operationType: s[1], operationName: void 0 }
    : { operationType: void 0, operationName: void 0 };
}
function eh(e) {
  let t;
  try {
    const n = JSON.parse(e);
    n.query && (t = n);
  } finally {
    return t;
  }
}
const Ww = Fw,
  wt = typeof __SENTRY_DEBUG__ > "u" || __SENTRY_DEBUG__,
  Ce = globalThis,
  Vn = "10.17.0";
function yi() {
  return (rc(Ce), Ce);
}
function rc(e) {
  const t = (e.__SENTRY__ = e.__SENTRY__ || {});
  return ((t.version = t.version || Vn), (t[Vn] = t[Vn] || {}));
}
function bi(e, t, n = Ce) {
  const r = (n.__SENTRY__ = n.__SENTRY__ || {}),
    s = (r[Vn] = r[Vn] || {});
  return s[e] || (s[e] = t());
}
const zw = "Sentry Logger ",
  pl = {};
function sc(e) {
  if (!("console" in Ce)) return e();
  const t = Ce.console,
    n = {},
    r = Object.keys(pl);
  r.forEach((s) => {
    const i = pl[s];
    ((n[s] = t[s]), (t[s] = i));
  });
  try {
    return e();
  } finally {
    r.forEach((s) => {
      t[s] = n[s];
    });
  }
}
function jw() {
  oc().enabled = !0;
}
function qw() {
  oc().enabled = !1;
}
function th() {
  return oc().enabled;
}
function Gw(...e) {
  ic("log", ...e);
}
function Vw(...e) {
  ic("warn", ...e);
}
function Yw(...e) {
  ic("error", ...e);
}
function ic(e, ...t) {
  wt &&
    th() &&
    sc(() => {
      Ce.console[e](`${zw}[${e}]:`, ...t);
    });
}
function oc() {
  return wt ? bi("loggerSettings", () => ({ enabled: !1 })) : { enabled: !1 };
}
const ct = {
    enable: jw,
    disable: qw,
    isEnabled: th,
    log: Gw,
    warn: Vw,
    error: Yw,
  },
  Qi = "<anonymous>";
function Xw(e) {
  try {
    return !e || typeof e != "function" ? Qi : e.name || Qi;
  } catch {
    return Qi;
  }
}
const nh = Object.prototype.toString;
function Kw(e) {
  switch (nh.call(e)) {
    case "[object Error]":
    case "[object Exception]":
    case "[object DOMException]":
    case "[object WebAssembly.Exception]":
      return !0;
    default:
      return vi(e, Error);
  }
}
function ac(e, t) {
  return nh.call(e) === `[object ${t}]`;
}
function qs(e) {
  return ac(e, "String");
}
function rh(e) {
  return ac(e, "Object");
}
function Jw(e) {
  return typeof Event < "u" && vi(e, Event);
}
function Zw(e) {
  return typeof Element < "u" && vi(e, Element);
}
function Qw(e) {
  return ac(e, "RegExp");
}
function Ei(e) {
  return !!(e?.then && typeof e.then == "function");
}
function eI(e) {
  return (
    rh(e) &&
    "nativeEvent" in e &&
    "preventDefault" in e &&
    "stopPropagation" in e
  );
}
function vi(e, t) {
  try {
    return e instanceof t;
  } catch {
    return !1;
  }
}
function tI(e) {
  return !!(typeof e == "object" && e !== null && (e.__isVue || e._isVue));
}
const sh = Ce,
  nI = 80;
function cc(e, t = {}) {
  if (!e) return "<unknown>";
  try {
    let n = e;
    const r = 5,
      s = [];
    let i = 0,
      o = 0;
    const a = " > ",
      c = a.length;
    let u;
    const d = Array.isArray(t) ? t : t.keyAttrs,
      l = (!Array.isArray(t) && t.maxStringLength) || nI;
    for (
      ;
      n &&
      i++ < r &&
      ((u = rI(n, d)),
      !(u === "html" || (i > 1 && o + s.length * c + u.length >= l)));
    )
      (s.push(u), (o += u.length), (n = n.parentNode));
    return s.reverse().join(a);
  } catch {
    return "<unknown>";
  }
}
function rI(e, t) {
  const n = e,
    r = [];
  if (!n?.tagName) return "";
  if (sh.HTMLElement && n instanceof HTMLElement && n.dataset) {
    if (n.dataset.sentryComponent) return n.dataset.sentryComponent;
    if (n.dataset.sentryElement) return n.dataset.sentryElement;
  }
  r.push(n.tagName.toLowerCase());
  const s = t?.length
    ? t.filter((o) => n.getAttribute(o)).map((o) => [o, n.getAttribute(o)])
    : null;
  if (s?.length)
    s.forEach((o) => {
      r.push(`[${o[0]}="${o[1]}"]`);
    });
  else {
    n.id && r.push(`#${n.id}`);
    const o = n.className;
    if (o && qs(o)) {
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
function sI() {
  try {
    return sh.document.location.href;
  } catch {
    return "";
  }
}
function ih(e, t = 0) {
  return typeof e != "string" || t === 0 || e.length <= t
    ? e
    : `${e.slice(0, t)}...`;
}
function iI(e, t, n = !1) {
  return qs(e)
    ? Qw(t)
      ? t.test(e)
      : qs(t)
        ? n
          ? e === t
          : e.includes(t)
        : !1
    : !1;
}
function oI(e, t = [], n = !1) {
  return t.some((r) => iI(e, r, n));
}
function aI(e, t, n) {
  if (!(t in e)) return;
  const r = e[t];
  if (typeof r != "function") return;
  const s = n(r);
  typeof s == "function" && cI(s, r);
  try {
    e[t] = s;
  } catch {
    wt && ct.log(`Failed to replace method "${t}" in object`, e);
  }
}
function oh(e, t, n) {
  try {
    Object.defineProperty(e, t, { value: n, writable: !0, configurable: !0 });
  } catch {
    wt && ct.log(`Failed to add non-enumerable property "${t}" to object`, e);
  }
}
function cI(e, t) {
  try {
    const n = t.prototype || {};
    ((e.prototype = t.prototype = n), oh(e, "__sentry_original__", t));
  } catch {}
}
function uI(e) {
  if (Kw(e))
    return { message: e.message, name: e.name, stack: e.stack, ...ml(e) };
  if (Jw(e)) {
    const t = {
      type: e.type,
      target: hl(e.target),
      currentTarget: hl(e.currentTarget),
      ...ml(e),
    };
    return (
      typeof CustomEvent < "u" && vi(e, CustomEvent) && (t.detail = e.detail),
      t
    );
  } else return e;
}
function hl(e) {
  try {
    return Zw(e) ? cc(e) : Object.prototype.toString.call(e);
  } catch {
    return "<unknown>";
  }
}
function ml(e) {
  if (typeof e == "object" && e !== null) {
    const t = {};
    for (const n in e)
      Object.prototype.hasOwnProperty.call(e, n) && (t[n] = e[n]);
    return t;
  } else return {};
}
function lI() {
  const e = Ce;
  return e.crypto || e.msCrypto;
}
function It(e = lI()) {
  let t = () => Math.random() * 16;
  try {
    if (e?.randomUUID) return e.randomUUID().replace(/-/g, "");
    e?.getRandomValues &&
      (t = () => {
        const n = new Uint8Array(1);
        return (e.getRandomValues(n), n[0]);
      });
  } catch {}
  return ("10000000100040008000" + 1e11).replace(/[018]/g, (n) =>
    (n ^ ((t() & 15) >> (n / 4))).toString(16),
  );
}
function dI(e) {
  return e.exception?.values?.[0];
}
function fI(e, t) {
  const n = dI(e);
  if (!n) return;
  const r = { type: "generic", handled: !0 },
    s = n.mechanism;
  if (((n.mechanism = { ...r, ...s, ...t }), t && "data" in t)) {
    const i = { ...s?.data, ...t.data };
    n.mechanism.data = i;
  }
}
const ah = 1e3;
function Ti() {
  return Date.now() / ah;
}
function pI() {
  const { performance: e } = Ce;
  if (!e?.now || !e.timeOrigin) return Ti;
  const t = e.timeOrigin;
  return () => (t + e.now()) / ah;
}
let gl;
function ch() {
  return (gl ?? (gl = pI()))();
}
let eo;
function hI() {
  const { performance: e } = Ce;
  if (!e?.now) return [void 0, "none"];
  const t = 3600 * 1e3,
    n = e.now(),
    r = Date.now(),
    s = e.timeOrigin ? Math.abs(e.timeOrigin + n - r) : t,
    i = s < t,
    o = e.timing?.navigationStart,
    c = typeof o == "number" ? Math.abs(o + n - r) : t,
    u = c < t;
  return i || u
    ? s <= c
      ? [e.timeOrigin, "timeOrigin"]
      : [o, "navigationStart"]
    : [r, "dateNow"];
}
function mI() {
  return (eo || (eo = hI()), eo[0]);
}
function gI(e, t = {}) {
  if (
    (t.user &&
      (!e.ipAddress && t.user.ip_address && (e.ipAddress = t.user.ip_address),
      !e.did &&
        !t.did &&
        (e.did = t.user.id || t.user.email || t.user.username)),
    (e.timestamp = t.timestamp || ch()),
    t.abnormal_mechanism && (e.abnormal_mechanism = t.abnormal_mechanism),
    t.ignoreDuration && (e.ignoreDuration = t.ignoreDuration),
    t.sid && (e.sid = t.sid.length === 32 ? t.sid : It()),
    t.init !== void 0 && (e.init = t.init),
    !e.did && t.did && (e.did = `${t.did}`),
    typeof t.started == "number" && (e.started = t.started),
    e.ignoreDuration)
  )
    e.duration = void 0;
  else if (typeof t.duration == "number") e.duration = t.duration;
  else {
    const n = e.timestamp - e.started;
    e.duration = n >= 0 ? n : 0;
  }
  (t.release && (e.release = t.release),
    t.environment && (e.environment = t.environment),
    !e.ipAddress && t.ipAddress && (e.ipAddress = t.ipAddress),
    !e.userAgent && t.userAgent && (e.userAgent = t.userAgent),
    typeof t.errors == "number" && (e.errors = t.errors),
    t.status && (e.status = t.status));
}
function wi(e, t, n = 2) {
  if (!t || typeof t != "object" || n <= 0) return t;
  if (e && Object.keys(t).length === 0) return e;
  const r = { ...e };
  for (const s in t)
    Object.prototype.hasOwnProperty.call(t, s) &&
      (r[s] = wi(r[s], t[s], n - 1));
  return r;
}
function _l() {
  return It();
}
function _I() {
  return It().substring(16);
}
const Lo = "_sentrySpan";
function Sl(e, t) {
  t ? oh(e, Lo, t) : delete e[Lo];
}
function $o(e) {
  return e[Lo];
}
const SI = 100;
class Qe {
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
      (this._propagationContext = {
        traceId: _l(),
        sampleRand: Math.random(),
      }));
  }
  clone() {
    const t = new Qe();
    return (
      (t._breadcrumbs = [...this._breadcrumbs]),
      (t._tags = { ...this._tags }),
      (t._extra = { ...this._extra }),
      (t._contexts = { ...this._contexts }),
      this._contexts.flags &&
        (t._contexts.flags = { values: [...this._contexts.flags.values] }),
      (t._user = this._user),
      (t._level = this._level),
      (t._session = this._session),
      (t._transactionName = this._transactionName),
      (t._fingerprint = this._fingerprint),
      (t._eventProcessors = [...this._eventProcessors]),
      (t._attachments = [...this._attachments]),
      (t._sdkProcessingMetadata = { ...this._sdkProcessingMetadata }),
      (t._propagationContext = { ...this._propagationContext }),
      (t._client = this._client),
      (t._lastEventId = this._lastEventId),
      Sl(t, $o(this)),
      t
    );
  }
  setClient(t) {
    this._client = t;
  }
  setLastEventId(t) {
    this._lastEventId = t;
  }
  getClient() {
    return this._client;
  }
  lastEventId() {
    return this._lastEventId;
  }
  addScopeListener(t) {
    this._scopeListeners.push(t);
  }
  addEventProcessor(t) {
    return (this._eventProcessors.push(t), this);
  }
  setUser(t) {
    return (
      (this._user = t || {
        email: void 0,
        id: void 0,
        ip_address: void 0,
        username: void 0,
      }),
      this._session && gI(this._session, { user: t }),
      this._notifyScopeListeners(),
      this
    );
  }
  getUser() {
    return this._user;
  }
  setTags(t) {
    return (
      (this._tags = { ...this._tags, ...t }),
      this._notifyScopeListeners(),
      this
    );
  }
  setTag(t, n) {
    return (
      (this._tags = { ...this._tags, [t]: n }),
      this._notifyScopeListeners(),
      this
    );
  }
  setExtras(t) {
    return (
      (this._extra = { ...this._extra, ...t }),
      this._notifyScopeListeners(),
      this
    );
  }
  setExtra(t, n) {
    return (
      (this._extra = { ...this._extra, [t]: n }),
      this._notifyScopeListeners(),
      this
    );
  }
  setFingerprint(t) {
    return ((this._fingerprint = t), this._notifyScopeListeners(), this);
  }
  setLevel(t) {
    return ((this._level = t), this._notifyScopeListeners(), this);
  }
  setTransactionName(t) {
    return ((this._transactionName = t), this._notifyScopeListeners(), this);
  }
  setContext(t, n) {
    return (
      n === null ? delete this._contexts[t] : (this._contexts[t] = n),
      this._notifyScopeListeners(),
      this
    );
  }
  setSession(t) {
    return (
      t ? (this._session = t) : delete this._session,
      this._notifyScopeListeners(),
      this
    );
  }
  getSession() {
    return this._session;
  }
  update(t) {
    if (!t) return this;
    const n = typeof t == "function" ? t(this) : t,
      r = n instanceof Qe ? n.getScopeData() : rh(n) ? t : void 0,
      {
        tags: s,
        extra: i,
        user: o,
        contexts: a,
        level: c,
        fingerprint: u = [],
        propagationContext: d,
      } = r || {};
    return (
      (this._tags = { ...this._tags, ...s }),
      (this._extra = { ...this._extra, ...i }),
      (this._contexts = { ...this._contexts, ...a }),
      o && Object.keys(o).length && (this._user = o),
      c && (this._level = c),
      u.length && (this._fingerprint = u),
      d && (this._propagationContext = d),
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
      Sl(this, void 0),
      (this._attachments = []),
      this.setPropagationContext({ traceId: _l(), sampleRand: Math.random() }),
      this._notifyScopeListeners(),
      this
    );
  }
  addBreadcrumb(t, n) {
    const r = typeof n == "number" ? n : SI;
    if (r <= 0) return this;
    const s = {
      timestamp: Ti(),
      ...t,
      message: t.message ? ih(t.message, 2048) : t.message,
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
  addAttachment(t) {
    return (this._attachments.push(t), this);
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
      span: $o(this),
    };
  }
  setSDKProcessingMetadata(t) {
    return (
      (this._sdkProcessingMetadata = wi(this._sdkProcessingMetadata, t, 2)),
      this
    );
  }
  setPropagationContext(t) {
    return ((this._propagationContext = t), this);
  }
  getPropagationContext() {
    return this._propagationContext;
  }
  captureException(t, n) {
    const r = n?.event_id || It();
    if (!this._client)
      return (
        wt &&
          ct.warn(
            "No client configured on scope - will not capture exception!",
          ),
        r
      );
    const s = new Error("Sentry syntheticException");
    return (
      this._client.captureException(
        t,
        { originalException: t, syntheticException: s, ...n, event_id: r },
        this,
      ),
      r
    );
  }
  captureMessage(t, n, r) {
    const s = r?.event_id || It();
    if (!this._client)
      return (
        wt &&
          ct.warn("No client configured on scope - will not capture message!"),
        s
      );
    const i = new Error(t);
    return (
      this._client.captureMessage(
        t,
        n,
        { originalException: t, syntheticException: i, ...r, event_id: s },
        this,
      ),
      s
    );
  }
  captureEvent(t, n) {
    const r = n?.event_id || It();
    return this._client
      ? (this._client.captureEvent(t, { ...n, event_id: r }, this), r)
      : (wt &&
          ct.warn("No client configured on scope - will not capture event!"),
        r);
  }
  _notifyScopeListeners() {
    this._notifyingListeners ||
      ((this._notifyingListeners = !0),
      this._scopeListeners.forEach((t) => {
        t(this);
      }),
      (this._notifyingListeners = !1));
  }
}
function yI() {
  return bi("defaultCurrentScope", () => new Qe());
}
function bI() {
  return bi("defaultIsolationScope", () => new Qe());
}
class EI {
  constructor(t, n) {
    let r;
    t ? (r = t) : (r = new Qe());
    let s;
    (n ? (s = n) : (s = new Qe()),
      (this._stack = [{ scope: r }]),
      (this._isolationScope = s));
  }
  withScope(t) {
    const n = this._pushScope();
    let r;
    try {
      r = t(n);
    } catch (s) {
      throw (this._popScope(), s);
    }
    return Ei(r)
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
    const t = this.getScope().clone();
    return (this._stack.push({ client: this.getClient(), scope: t }), t);
  }
  _popScope() {
    return this._stack.length <= 1 ? !1 : !!this._stack.pop();
  }
}
function bn() {
  const e = yi(),
    t = rc(e);
  return (t.stack = t.stack || new EI(yI(), bI()));
}
function vI(e) {
  return bn().withScope(e);
}
function TI(e, t) {
  const n = bn();
  return n.withScope(() => ((n.getStackTop().scope = e), t(e)));
}
function yl(e) {
  return bn().withScope(() => e(bn().getIsolationScope()));
}
function wI() {
  return {
    withIsolationScope: yl,
    withScope: vI,
    withSetScope: TI,
    withSetIsolationScope: (e, t) => yl(t),
    getCurrentScope: () => bn().getScope(),
    getIsolationScope: () => bn().getIsolationScope(),
  };
}
function uc(e) {
  const t = rc(e);
  return t.acs ? t.acs : wI();
}
function Nr() {
  const e = yi();
  return uc(e).getCurrentScope();
}
function Ii() {
  const e = yi();
  return uc(e).getIsolationScope();
}
function II() {
  return bi("globalScope", () => new Qe());
}
function Ge() {
  return Nr().getClient();
}
const uh = "sentry.source",
  kI = "sentry.sample_rate",
  CI = "sentry.previous_trace_sample_rate",
  RI = "sentry.op",
  xI = "sentry.origin",
  AI = 0,
  MI = 1,
  NI = "_sentryScope",
  OI = "_sentryIsolationScope";
function LI(e) {
  if (e) {
    if (typeof e == "object" && "deref" in e && typeof e.deref == "function")
      try {
        return e.deref();
      } catch {
        return;
      }
    return e;
  }
}
function lh(e) {
  const t = e;
  return { scope: t[NI], isolationScope: LI(t[OI]) };
}
const $I = "sentry-",
  DI = /^sentry-/;
function PI(e) {
  const t = FI(e);
  if (!t) return;
  const n = Object.entries(t).reduce((r, [s, i]) => {
    if (s.match(DI)) {
      const o = s.slice($I.length);
      r[o] = i;
    }
    return r;
  }, {});
  if (Object.keys(n).length > 0) return n;
}
function FI(e) {
  if (!(!e || (!qs(e) && !Array.isArray(e))))
    return Array.isArray(e)
      ? e.reduce((t, n) => {
          const r = bl(n);
          return (
            Object.entries(r).forEach(([s, i]) => {
              t[s] = i;
            }),
            t
          );
        }, {})
      : bl(e);
}
function bl(e) {
  return e
    .split(",")
    .map((t) =>
      t.split("=").map((n) => {
        try {
          return decodeURIComponent(n.trim());
        } catch {
          return;
        }
      }),
    )
    .reduce((t, [n, r]) => (n && r && (t[n] = r), t), {});
}
const BI = /^o(\d+)\./;
function UI(e, t = !1) {
  const {
    host: n,
    path: r,
    pass: s,
    port: i,
    projectId: o,
    protocol: a,
    publicKey: c,
  } = e;
  return `${a}://${c}${t && s ? `:${s}` : ""}@${n}${i ? `:${i}` : ""}/${r && `${r}/`}${o}`;
}
function HI(e) {
  return e.match(BI)?.[1];
}
function WI(e) {
  const t = e.getOptions(),
    { host: n } = e.getDsn() || {};
  let r;
  return (t.orgId ? (r = String(t.orgId)) : n && (r = HI(n)), r);
}
function El(e) {
  if (typeof e == "boolean") return Number(e);
  const t = typeof e == "string" ? parseFloat(e) : e;
  if (!(typeof t != "number" || isNaN(t) || t < 0 || t > 1)) return t;
}
const dh = 1;
function zI(e) {
  const { spanId: t, traceId: n, isRemote: r } = e.spanContext(),
    s = r ? t : or(e).parent_span_id,
    i = lh(e).scope,
    o = r ? i?.getPropagationContext().propagationSpanId || _I() : t;
  return { parent_span_id: s, span_id: o, trace_id: n };
}
function jI(e) {
  if (e && e.length > 0)
    return e.map(
      ({
        context: { spanId: t, traceId: n, traceFlags: r, ...s },
        attributes: i,
      }) => ({
        span_id: t,
        trace_id: n,
        sampled: r === dh,
        attributes: i,
        ...s,
      }),
    );
}
function vl(e) {
  return typeof e == "number"
    ? Tl(e)
    : Array.isArray(e)
      ? e[0] + e[1] / 1e9
      : e instanceof Date
        ? Tl(e.getTime())
        : ch();
}
function Tl(e) {
  return e > 9999999999 ? e / 1e3 : e;
}
function or(e) {
  if (GI(e)) return e.getSpanJSON();
  const { spanId: t, traceId: n } = e.spanContext();
  if (qI(e)) {
    const {
        attributes: r,
        startTime: s,
        name: i,
        endTime: o,
        status: a,
        links: c,
      } = e,
      u =
        "parentSpanId" in e
          ? e.parentSpanId
          : "parentSpanContext" in e
            ? e.parentSpanContext?.spanId
            : void 0;
    return {
      span_id: t,
      trace_id: n,
      data: r,
      description: i,
      parent_span_id: u,
      start_timestamp: vl(s),
      timestamp: vl(o) || void 0,
      status: YI(a),
      op: r[RI],
      origin: r[xI],
      links: jI(c),
    };
  }
  return { span_id: t, trace_id: n, start_timestamp: 0, data: {} };
}
function qI(e) {
  const t = e;
  return (
    !!t.attributes && !!t.startTime && !!t.name && !!t.endTime && !!t.status
  );
}
function GI(e) {
  return typeof e.getSpanJSON == "function";
}
function VI(e) {
  const { traceFlags: t } = e.spanContext();
  return t === dh;
}
function YI(e) {
  if (!(!e || e.code === AI))
    return e.code === MI ? "ok" : e.message || "unknown_error";
}
const XI = "_sentryRootSpan";
function lc(e) {
  return e[XI] || e;
}
function fh() {
  const e = yi(),
    t = uc(e);
  return t.getActiveSpan ? t.getActiveSpan() : $o(Nr());
}
function KI(e) {
  if (typeof __SENTRY_TRACING__ == "boolean" && !__SENTRY_TRACING__) return !1;
  const t = Ge()?.getOptions();
  return !!t && (t.tracesSampleRate != null || !!t.tracesSampler);
}
const ph = "production",
  JI = "_frozenDsc";
function ZI(e, t) {
  const n = t.getOptions(),
    { publicKey: r } = t.getDsn() || {},
    s = {
      environment: n.environment || ph,
      release: n.release,
      public_key: r,
      trace_id: e,
      org_id: WI(t),
    };
  return (t.emit("createDsc", s), s);
}
function hh(e) {
  const t = Ge();
  if (!t) return {};
  const n = lc(e),
    r = or(n),
    s = r.data,
    i = n.spanContext().traceState,
    o = i?.get("sentry.sample_rate") ?? s[kI] ?? s[CI];
  function a(h) {
    return (
      (typeof o == "number" || typeof o == "string") &&
        (h.sample_rate = `${o}`),
      h
    );
  }
  const c = n[JI];
  if (c) return a(c);
  const u = i?.get("sentry.dsc"),
    d = u && PI(u);
  if (d) return a(d);
  const l = ZI(e.spanContext().traceId, t),
    p = s[uh],
    f = r.description;
  return (
    p !== "url" && f && (l.transaction = f),
    KI() &&
      ((l.sampled = String(VI(n))),
      (l.sample_rand =
        i?.get("sentry.sample_rand") ??
        lh(n).scope?.getPropagationContext().sampleRand.toString())),
    a(l),
    t.emit("createDsc", l, n),
    l
  );
}
function nt(e, t = 100, n = 1 / 0) {
  try {
    return Do("", e, t, n);
  } catch (r) {
    return { ERROR: `**non-serializable** (${r})` };
  }
}
function Do(e, t, n = 1 / 0, r = 1 / 0, s = t1()) {
  const [i, o] = s;
  if (
    t == null ||
    ["boolean", "string"].includes(typeof t) ||
    (typeof t == "number" && Number.isFinite(t))
  )
    return t;
  const a = QI(e, t);
  if (!a.startsWith("[object ")) return a;
  if (t.__sentry_skip_normalization__) return t;
  const c =
    typeof t.__sentry_override_normalization_depth__ == "number"
      ? t.__sentry_override_normalization_depth__
      : n;
  if (c === 0) return a.replace("object ", "");
  if (i(t)) return "[Circular ~]";
  const u = t;
  if (u && typeof u.toJSON == "function")
    try {
      const f = u.toJSON();
      return Do("", f, c - 1, r, s);
    } catch {}
  const d = Array.isArray(t) ? [] : {};
  let l = 0;
  const p = uI(t);
  for (const f in p) {
    if (!Object.prototype.hasOwnProperty.call(p, f)) continue;
    if (l >= r) {
      d[f] = "[MaxProperties ~]";
      break;
    }
    const h = p[f];
    ((d[f] = Do(f, h, c - 1, r, s)), l++);
  }
  return (o(t), d);
}
function QI(e, t) {
  try {
    if (e === "domain" && t && typeof t == "object" && t._events)
      return "[Domain]";
    if (e === "domainEmitter") return "[DomainEmitter]";
    if (typeof ws < "u" && t === ws) return "[Global]";
    if (typeof window < "u" && t === window) return "[Window]";
    if (typeof document < "u" && t === document) return "[Document]";
    if (tI(t)) return "[VueViewModel]";
    if (eI(t)) return "[SyntheticEvent]";
    if (typeof t == "number" && !Number.isFinite(t)) return `[${t}]`;
    if (typeof t == "function") return `[Function: ${Xw(t)}]`;
    if (typeof t == "symbol") return `[${String(t)}]`;
    if (typeof t == "bigint") return `[BigInt: ${String(t)}]`;
    const n = e1(t);
    return /^HTML(\w*)Element$/.test(n)
      ? `[HTMLElement: ${n}]`
      : `[object ${n}]`;
  } catch (n) {
    return `**non-serializable** (${n})`;
  }
}
function e1(e) {
  const t = Object.getPrototypeOf(e);
  return t?.constructor ? t.constructor.name : "null prototype";
}
function t1() {
  const e = new WeakSet();
  function t(r) {
    return e.has(r) ? !0 : (e.add(r), !1);
  }
  function n(r) {
    e.delete(r);
  }
  return [t, n];
}
function n1(e, t = []) {
  return [e, t];
}
function r1(e) {
  if (!e?.sdk) return;
  const { name: t, version: n } = e.sdk;
  return { name: t, version: n };
}
function s1(e, t, n, r) {
  const s = e.sdkProcessingMetadata?.dynamicSamplingContext;
  return {
    event_id: e.event_id,
    sent_at: new Date().toISOString(),
    ...(t && { sdk: t }),
    ...(!!n && r && { dsn: UI(r) }),
    ...(s && { trace: s }),
  };
}
const to = 0,
  wl = 1,
  Il = 2;
function i1(e) {
  return new ar((t) => {
    t(e);
  });
}
function o1(e) {
  return new ar((t, n) => {
    n(e);
  });
}
class ar {
  constructor(t) {
    ((this._state = to), (this._handlers = []), this._runExecutor(t));
  }
  then(t, n) {
    return new ar((r, s) => {
      (this._handlers.push([
        !1,
        (i) => {
          if (!t) r(i);
          else
            try {
              r(t(i));
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
  catch(t) {
    return this.then((n) => n, t);
  }
  finally(t) {
    return new ar((n, r) => {
      let s, i;
      return this.then(
        (o) => {
          ((i = !1), (s = o), t && t());
        },
        (o) => {
          ((i = !0), (s = o), t && t());
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
    if (this._state === to) return;
    const t = this._handlers.slice();
    ((this._handlers = []),
      t.forEach((n) => {
        n[0] ||
          (this._state === wl && n[1](this._value),
          this._state === Il && n[2](this._value),
          (n[0] = !0));
      }));
  }
  _runExecutor(t) {
    const n = (i, o) => {
        if (this._state === to) {
          if (Ei(o)) {
            o.then(r, s);
            return;
          }
          ((this._state = i), (this._value = o), this._executeHandlers());
        }
      },
      r = (i) => {
        n(wl, i);
      },
      s = (i) => {
        n(Il, i);
      };
    try {
      t(r, s);
    } catch (i) {
      s(i);
    }
  }
}
function a1(e, t, n, r = 0) {
  try {
    const s = Po(t, n, e, r);
    return Ei(s) ? s : i1(s);
  } catch (s) {
    return o1(s);
  }
}
function Po(e, t, n, r) {
  const s = n[r];
  if (!e || !s) return e;
  const i = s({ ...e }, t);
  return (
    wt &&
      i === null &&
      ct.log(`Event processor "${s.id || "?"}" dropped event`),
    Ei(i) ? i.then((o) => Po(o, t, n, r + 1)) : Po(i, t, n, r + 1)
  );
}
function c1(e, t) {
  const {
    fingerprint: n,
    span: r,
    breadcrumbs: s,
    sdkProcessingMetadata: i,
  } = t;
  (u1(e, t), r && f1(e, r), p1(e, n), l1(e, s), d1(e, i));
}
function kl(e, t) {
  const {
    extra: n,
    tags: r,
    user: s,
    contexts: i,
    level: o,
    sdkProcessingMetadata: a,
    breadcrumbs: c,
    fingerprint: u,
    eventProcessors: d,
    attachments: l,
    propagationContext: p,
    transactionName: f,
    span: h,
  } = t;
  (qr(e, "extra", n),
    qr(e, "tags", r),
    qr(e, "user", s),
    qr(e, "contexts", i),
    (e.sdkProcessingMetadata = wi(e.sdkProcessingMetadata, a, 2)),
    o && (e.level = o),
    f && (e.transactionName = f),
    h && (e.span = h),
    c.length && (e.breadcrumbs = [...e.breadcrumbs, ...c]),
    u.length && (e.fingerprint = [...e.fingerprint, ...u]),
    d.length && (e.eventProcessors = [...e.eventProcessors, ...d]),
    l.length && (e.attachments = [...e.attachments, ...l]),
    (e.propagationContext = { ...e.propagationContext, ...p }));
}
function qr(e, t, n) {
  e[t] = wi(e[t], n, 1);
}
function u1(e, t) {
  const {
    extra: n,
    tags: r,
    user: s,
    contexts: i,
    level: o,
    transactionName: a,
  } = t;
  (Object.keys(n).length && (e.extra = { ...n, ...e.extra }),
    Object.keys(r).length && (e.tags = { ...r, ...e.tags }),
    Object.keys(s).length && (e.user = { ...s, ...e.user }),
    Object.keys(i).length && (e.contexts = { ...i, ...e.contexts }),
    o && (e.level = o),
    a && e.type !== "transaction" && (e.transaction = a));
}
function l1(e, t) {
  const n = [...(e.breadcrumbs || []), ...t];
  e.breadcrumbs = n.length ? n : void 0;
}
function d1(e, t) {
  e.sdkProcessingMetadata = { ...e.sdkProcessingMetadata, ...t };
}
function f1(e, t) {
  ((e.contexts = { trace: zI(t), ...e.contexts }),
    (e.sdkProcessingMetadata = {
      dynamicSamplingContext: hh(t),
      ...e.sdkProcessingMetadata,
    }));
  const n = lc(t),
    r = or(n).description;
  r && !e.transaction && e.type === "transaction" && (e.transaction = r);
}
function p1(e, t) {
  ((e.fingerprint = e.fingerprint
    ? Array.isArray(e.fingerprint)
      ? e.fingerprint
      : [e.fingerprint]
    : []),
    t && (e.fingerprint = e.fingerprint.concat(t)),
    e.fingerprint.length || delete e.fingerprint);
}
let Gr, Cl, Vr;
function h1(e) {
  const t = Ce._sentryDebugIds;
  if (!t) return {};
  const n = Object.keys(t);
  return (
    (Vr && n.length === Cl) ||
      ((Cl = n.length),
      (Vr = n.reduce((r, s) => {
        Gr || (Gr = {});
        const i = Gr[s];
        if (i) r[i[0]] = i[1];
        else {
          const o = e(s);
          for (let a = o.length - 1; a >= 0; a--) {
            const u = o[a]?.filename,
              d = t[s];
            if (u && d) {
              ((r[u] = d), (Gr[s] = [u, d]));
              break;
            }
          }
        }
        return r;
      }, {}))),
    Vr
  );
}
function m1(e, t, n, r, s, i) {
  const { normalizeDepth: o = 3, normalizeMaxBreadth: a = 1e3 } = e,
    c = {
      ...t,
      event_id: t.event_id || n.event_id || It(),
      timestamp: t.timestamp || Ti(),
    },
    u = n.integrations || e.integrations.map((g) => g.name);
  (g1(c, e),
    y1(c, u),
    s && s.emit("applyFrameMetadata", t),
    t.type === void 0 && _1(c, e.stackParser));
  const d = E1(r, n.captureContext);
  n.mechanism && fI(c, n.mechanism);
  const l = s ? s.getEventProcessors() : [],
    p = II().getScopeData();
  if (i) {
    const g = i.getScopeData();
    kl(p, g);
  }
  if (d) {
    const g = d.getScopeData();
    kl(p, g);
  }
  const f = [...(n.attachments || []), ...p.attachments];
  (f.length && (n.attachments = f), c1(c, p));
  const h = [...l, ...p.eventProcessors];
  return a1(h, c, n).then(
    (g) => (g && S1(g), typeof o == "number" && o > 0 ? b1(g, o, a) : g),
  );
}
function g1(e, t) {
  const { environment: n, release: r, dist: s, maxValueLength: i = 250 } = t;
  ((e.environment = e.environment || n || ph),
    !e.release && r && (e.release = r),
    !e.dist && s && (e.dist = s));
  const o = e.request;
  o?.url && (o.url = ih(o.url, i));
}
function _1(e, t) {
  const n = h1(t);
  e.exception?.values?.forEach((r) => {
    r.stacktrace?.frames?.forEach((s) => {
      s.filename && (s.debug_id = n[s.filename]);
    });
  });
}
function S1(e) {
  const t = {};
  if (
    (e.exception?.values?.forEach((r) => {
      r.stacktrace?.frames?.forEach((s) => {
        s.debug_id &&
          (s.abs_path
            ? (t[s.abs_path] = s.debug_id)
            : s.filename && (t[s.filename] = s.debug_id),
          delete s.debug_id);
      });
    }),
    Object.keys(t).length === 0)
  )
    return;
  ((e.debug_meta = e.debug_meta || {}),
    (e.debug_meta.images = e.debug_meta.images || []));
  const n = e.debug_meta.images;
  Object.entries(t).forEach(([r, s]) => {
    n.push({ type: "sourcemap", code_file: r, debug_id: s });
  });
}
function y1(e, t) {
  t.length > 0 &&
    ((e.sdk = e.sdk || {}),
    (e.sdk.integrations = [...(e.sdk.integrations || []), ...t]));
}
function b1(e, t, n) {
  if (!e) return null;
  const r = {
    ...e,
    ...(e.breadcrumbs && {
      breadcrumbs: e.breadcrumbs.map((s) => ({
        ...s,
        ...(s.data && { data: nt(s.data, t, n) }),
      })),
    }),
    ...(e.user && { user: nt(e.user, t, n) }),
    ...(e.contexts && { contexts: nt(e.contexts, t, n) }),
    ...(e.extra && { extra: nt(e.extra, t, n) }),
  };
  return (
    e.contexts?.trace &&
      r.contexts &&
      ((r.contexts.trace = e.contexts.trace),
      e.contexts.trace.data &&
        (r.contexts.trace.data = nt(e.contexts.trace.data, t, n))),
    e.spans &&
      (r.spans = e.spans.map((s) => ({
        ...s,
        ...(s.data && { data: nt(s.data, t, n) }),
      }))),
    e.contexts?.flags &&
      r.contexts &&
      (r.contexts.flags = nt(e.contexts.flags, 3, n)),
    r
  );
}
function E1(e, t) {
  if (!t) return e;
  const n = e ? e.clone() : new Qe();
  return (n.update(t), n);
}
function v1(e) {
  if (e)
    return T1(e) ? { captureContext: e } : I1(e) ? { captureContext: e } : e;
}
function T1(e) {
  return e instanceof Qe || typeof e == "function";
}
const w1 = [
  "user",
  "level",
  "extra",
  "contexts",
  "tags",
  "fingerprint",
  "propagationContext",
];
function I1(e) {
  return Object.keys(e).some((t) => w1.includes(t));
}
function k1(e, t) {
  return Nr().captureException(e, v1(t));
}
function C1(e, t) {
  Ii().setContext(e, t);
}
function R1(e) {
  Ii().addEventProcessor(e);
}
const x1 = 60 * 1e3;
function A1(e, t = Date.now()) {
  const n = parseInt(`${e}`, 10);
  if (!isNaN(n)) return n * 1e3;
  const r = Date.parse(`${e}`);
  return isNaN(r) ? x1 : r - t;
}
function M1(e, t) {
  return e[t] || e.all || 0;
}
function N1(e, t, n = Date.now()) {
  return M1(e, t) > n;
}
function O1(e, { statusCode: t, headers: n }, r = Date.now()) {
  const s = { ...e },
    i = n?.["x-sentry-rate-limits"],
    o = n?.["retry-after"];
  if (i)
    for (const a of i.trim().split(",")) {
      const [c, u, , , d] = a.split(":", 5),
        l = parseInt(c, 10),
        p = (isNaN(l) ? 60 : l) * 1e3;
      if (!u) s.all = r + p;
      else
        for (const f of u.split(";"))
          f === "metric_bucket"
            ? (!d || d.split(";").includes("custom")) && (s[f] = r + p)
            : (s[f] = r + p);
    }
  else o ? (s.all = r + A1(o, r)) : t === 429 && (s.all = r + 60 * 1e3);
  return s;
}
const L1 = "thismessage:/";
function $1(e) {
  return "isRelative" in e;
}
function D1(e, t) {
  const n = e.indexOf("://") <= 0 && e.indexOf("//") !== 0,
    r = n ? L1 : void 0;
  try {
    if ("canParse" in URL && !URL.canParse(e, r)) return;
    const s = new URL(e, r);
    return n
      ? { isRelative: n, pathname: s.pathname, search: s.search, hash: s.hash }
      : s;
  } catch {}
}
function P1(e, t) {
  const n = t?.getDsn(),
    r = t?.getOptions().tunnel;
  return B1(e, n) || F1(e, r);
}
function F1(e, t) {
  return t ? Rl(e) === Rl(t) : !1;
}
function B1(e, t) {
  const n = D1(e);
  return !n || $1(n)
    ? !1
    : t
      ? n.host.includes(t.host) && /(^|&|\?)sentry_key=/.test(n.search)
      : !1;
}
function Rl(e) {
  return e[e.length - 1] === "/" ? e.slice(0, -1) : e;
}
function U1(e, t, n) {
  let r, s, i;
  const o = n?.maxWait ? Math.max(n.maxWait, t) : 0,
    a = n?.setTimeoutImpl || setTimeout;
  function c() {
    return (u(), (r = e()), r);
  }
  function u() {
    (s !== void 0 && clearTimeout(s),
      i !== void 0 && clearTimeout(i),
      (s = i = void 0));
  }
  function d() {
    return s !== void 0 || i !== void 0 ? c() : r;
  }
  function l() {
    return (
      s && clearTimeout(s),
      (s = a(c, t)),
      o && i === void 0 && (i = a(c, o)),
      r
    );
  }
  return ((l.cancel = u), (l.flush = d), l);
}
const H1 = 100;
function W1(e, t) {
  const n = Ge(),
    r = Ii();
  if (!n) return;
  const { beforeBreadcrumb: s = null, maxBreadcrumbs: i = H1 } = n.getOptions();
  if (i <= 0) return;
  const a = { timestamp: Ti(), ...e },
    c = s ? sc(() => s(a, t)) : a;
  c !== null &&
    (n.emit && n.emit("beforeAddBreadcrumb", c, t), r.addBreadcrumb(c, i));
}
function z1(e) {
  return e === "warn"
    ? "warning"
    : ["fatal", "error", "warning", "log", "info", "debug"].includes(e)
      ? e
      : "log";
}
function j1() {
  return typeof __SENTRY_BROWSER_BUNDLE__ < "u" && !!__SENTRY_BROWSER_BUNDLE__;
}
function q1() {
  return (
    !j1() &&
    Object.prototype.toString.call(typeof ys < "u" ? ys : 0) ===
      "[object process]"
  );
}
function xl() {
  return typeof window < "u" && (!q1() || G1());
}
function G1() {
  return Ce.process?.type === "renderer";
}
const ae = Ce,
  dc = "sentryReplaySession",
  V1 = "replay_event",
  fc = "Unable to send Replay",
  Y1 = 3e5,
  X1 = 9e5,
  K1 = 5e3,
  J1 = 5500,
  Z1 = 6e4,
  Q1 = 5e3,
  ek = 3,
  Al = 15e4,
  Yr = 5e3,
  tk = 3e3,
  nk = 300,
  pc = 2e7,
  rk = 4999,
  sk = 15e3,
  Ml = 36e5;
var ik = Object.defineProperty,
  ok = (e, t, n) =>
    t in e
      ? ik(e, t, { enumerable: !0, configurable: !0, writable: !0, value: n })
      : (e[t] = n),
  Nl = (e, t, n) => ok(e, typeof t != "symbol" ? t + "" : t, n),
  _e = ((e) => (
    (e[(e.Document = 0)] = "Document"),
    (e[(e.DocumentType = 1)] = "DocumentType"),
    (e[(e.Element = 2)] = "Element"),
    (e[(e.Text = 3)] = "Text"),
    (e[(e.CDATA = 4)] = "CDATA"),
    (e[(e.Comment = 5)] = "Comment"),
    e
  ))(_e || {});
function ak(e) {
  return e.nodeType === e.ELEMENT_NODE;
}
function Yn(e) {
  return e?.host?.shadowRoot === e;
}
function Xn(e) {
  return Object.prototype.toString.call(e) === "[object ShadowRoot]";
}
function ck(e) {
  return (
    e.includes(" background-clip: text;") &&
      !e.includes(" -webkit-background-clip: text;") &&
      (e = e.replace(
        /\sbackground-clip:\s*text;/g,
        " -webkit-background-clip: text; background-clip: text;",
      )),
    e
  );
}
function uk(e) {
  const { cssText: t } = e;
  if (t.split('"').length < 3) return t;
  const n = ["@import", `url(${JSON.stringify(e.href)})`];
  return (
    e.layerName === ""
      ? n.push("layer")
      : e.layerName && n.push(`layer(${e.layerName})`),
    e.supportsText && n.push(`supports(${e.supportsText})`),
    e.media.length && n.push(e.media.mediaText),
    n.join(" ") + ";"
  );
}
function Gs(e) {
  try {
    const t = e.rules || e.cssRules;
    return t ? ck(Array.from(t, mh).join("")) : null;
  } catch {
    return null;
  }
}
function lk(e) {
  let t = "";
  for (let n = 0; n < e.style.length; n++) {
    const r = e.style,
      s = r[n],
      i = r.getPropertyPriority(s);
    t += `${s}:${r.getPropertyValue(s)}${i ? " !important" : ""};`;
  }
  return `${e.selectorText} { ${t} }`;
}
function mh(e) {
  let t;
  if (fk(e))
    try {
      t = Gs(e.styleSheet) || uk(e);
    } catch {}
  else if (pk(e)) {
    let n = e.cssText;
    const r = e.selectorText.includes(":"),
      s = typeof e.style.all == "string" && e.style.all;
    if ((s && (n = lk(e)), r && (n = dk(n)), r || s)) return n;
  }
  return t || e.cssText;
}
function dk(e) {
  const t = /(\[(?:[\w-]+)[^\\])(:(?:[\w-]+)\])/gm;
  return e.replace(t, "$1\\$2");
}
function fk(e) {
  return "styleSheet" in e;
}
function pk(e) {
  return "selectorText" in e;
}
let gh = class {
  constructor() {
    (Nl(this, "idNodeMap", new Map()), Nl(this, "nodeMetaMap", new WeakMap()));
  }
  getId(t) {
    return t ? (this.getMeta(t)?.id ?? -1) : -1;
  }
  getNode(t) {
    return this.idNodeMap.get(t) || null;
  }
  getIds() {
    return Array.from(this.idNodeMap.keys());
  }
  getMeta(t) {
    return this.nodeMetaMap.get(t) || null;
  }
  removeNodeFromMap(t) {
    const n = this.getId(t);
    (this.idNodeMap.delete(n),
      t.childNodes && t.childNodes.forEach((r) => this.removeNodeFromMap(r)));
  }
  has(t) {
    return this.idNodeMap.has(t);
  }
  hasNode(t) {
    return this.nodeMetaMap.has(t);
  }
  add(t, n) {
    const r = n.id;
    (this.idNodeMap.set(r, t), this.nodeMetaMap.set(t, n));
  }
  replace(t, n) {
    const r = this.getNode(t);
    if (r) {
      const s = this.nodeMetaMap.get(r);
      s && this.nodeMetaMap.set(n, s);
    }
    this.idNodeMap.set(t, n);
  }
  reset() {
    ((this.idNodeMap = new Map()), (this.nodeMetaMap = new WeakMap()));
  }
};
function hk() {
  return new gh();
}
function ki({ maskInputOptions: e, tagName: t, type: n }) {
  return (
    t === "OPTION" && (t = "SELECT"),
    !!(
      e[t.toLowerCase()] ||
      (n && e[n]) ||
      n === "password" ||
      (t === "INPUT" && !n && e.text)
    )
  );
}
function cr({ isMasked: e, element: t, value: n, maskInputFn: r }) {
  let s = n || "";
  return e ? (r && (s = r(s, t)), "*".repeat(s.length)) : s;
}
function En(e) {
  return e.toLowerCase();
}
function Fo(e) {
  return e.toUpperCase();
}
const Ol = "__rrweb_original__";
function mk(e) {
  const t = e.getContext("2d");
  if (!t) return !0;
  const n = 50;
  for (let r = 0; r < e.width; r += n)
    for (let s = 0; s < e.height; s += n) {
      const i = t.getImageData,
        o = Ol in i ? i[Ol] : i;
      if (
        new Uint32Array(
          o.call(t, r, s, Math.min(n, e.width - r), Math.min(n, e.height - s))
            .data.buffer,
        ).some((c) => c !== 0)
      )
        return !1;
    }
  return !0;
}
function hc(e) {
  const t = e.type;
  return e.hasAttribute("data-rr-is-password") ? "password" : t ? En(t) : null;
}
function Vs(e, t, n) {
  return t === "INPUT" && (n === "radio" || n === "checkbox")
    ? e.getAttribute("value") || ""
    : e.value;
}
function _h(e, t) {
  let n;
  try {
    n = new URL(e, t ?? window.location.href);
  } catch {
    return null;
  }
  const r = /\.([0-9a-z]+)(?:$)/i;
  return n.pathname.match(r)?.[1] ?? null;
}
const Ll = {};
function Sh(e) {
  const t = Ll[e];
  if (t) return t;
  const n = window.document;
  let r = window[e];
  if (n && typeof n.createElement == "function")
    try {
      const s = n.createElement("iframe");
      ((s.hidden = !0), n.head.appendChild(s));
      const i = s.contentWindow;
      (i && i[e] && (r = i[e]), n.head.removeChild(s));
    } catch {}
  return (Ll[e] = r.bind(window));
}
function Bo(...e) {
  return Sh("setTimeout")(...e);
}
function yh(...e) {
  return Sh("clearTimeout")(...e);
}
function bh(e) {
  try {
    return e.contentDocument;
  } catch {}
}
let gk = 1;
const _k = new RegExp("[^a-z0-9-_:]"),
  ur = -2;
function mc() {
  return gk++;
}
function Sk(e) {
  if (e instanceof HTMLFormElement) return "form";
  const t = En(e.tagName);
  return _k.test(t) ? "div" : t;
}
function yk(e) {
  let t = "";
  return (
    e.indexOf("//") > -1
      ? (t = e.split("/").slice(0, 3).join("/"))
      : (t = e.split("/")[0]),
    (t = t.split("?")[0]),
    t
  );
}
let Qt, $l;
const bk = /url\((?:(')([^']*)'|(")(.*?)"|([^)]*))\)/gm,
  Ek = /^(?:[a-z+]+:)?\/\//i,
  vk = /^www\..*/i,
  Tk = /^(data:)([^,]*),(.*)/i;
function Ys(e, t) {
  return (e || "").replace(bk, (n, r, s, i, o, a) => {
    const c = s || o || a,
      u = r || i || "";
    if (!c) return n;
    if (Ek.test(c) || vk.test(c)) return `url(${u}${c}${u})`;
    if (Tk.test(c)) return `url(${u}${c}${u})`;
    if (c[0] === "/") return `url(${u}${yk(t) + c}${u})`;
    const d = t.split("/"),
      l = c.split("/");
    d.pop();
    for (const p of l) p !== "." && (p === ".." ? d.pop() : d.push(p));
    return `url(${u}${d.join("/")}${u})`;
  });
}
const wk = /^[^ \t\n\r\u000c]+/,
  Ik = /^[, \t\n\r\u000c]+/;
function kk(e, t) {
  if (t.trim() === "") return t;
  let n = 0;
  function r(i) {
    let o;
    const a = i.exec(t.substring(n));
    return a ? ((o = a[0]), (n += o.length), o) : "";
  }
  const s = [];
  for (; r(Ik), !(n >= t.length);) {
    let i = r(wk);
    if (i.slice(-1) === ",")
      ((i = rn(e, i.substring(0, i.length - 1))), s.push(i));
    else {
      let o = "";
      i = rn(e, i);
      let a = !1;
      for (;;) {
        const c = t.charAt(n);
        if (c === "") {
          s.push((i + o).trim());
          break;
        } else if (a) c === ")" && (a = !1);
        else if (c === ",") {
          ((n += 1), s.push((i + o).trim()));
          break;
        } else c === "(" && (a = !0);
        ((o += c), (n += 1));
      }
    }
  }
  return s.join(", ");
}
const Dl = new WeakMap();
function rn(e, t) {
  return !t || t.trim() === "" ? t : Ci(e, t);
}
function Ck(e) {
  return !!(e.tagName === "svg" || e.ownerSVGElement);
}
function Ci(e, t) {
  let n = Dl.get(e);
  if ((n || ((n = e.createElement("a")), Dl.set(e, n)), !t)) t = "";
  else if (t.startsWith("blob:") || t.startsWith("data:")) return t;
  return (n.setAttribute("href", t), n.href);
}
function Eh(e, t, n, r, s, i) {
  return (
    r &&
    (n === "src" ||
    (n === "href" && !(t === "use" && r[0] === "#")) ||
    (n === "xlink:href" && r[0] !== "#") ||
    (n === "background" && (t === "table" || t === "td" || t === "th"))
      ? rn(e, r)
      : n === "srcset"
        ? kk(e, r)
        : n === "style"
          ? Ys(r, Ci(e))
          : t === "object" && n === "data"
            ? rn(e, r)
            : typeof i == "function"
              ? i(n, r, s)
              : r)
  );
}
function vh(e, t, n) {
  return (e === "video" || e === "audio") && t === "autoplay";
}
function Rk(e, t, n, r) {
  try {
    if (r && e.matches(r)) return !1;
    if (typeof t == "string") {
      if (e.classList.contains(t)) return !0;
    } else
      for (let s = e.classList.length; s--;) {
        const i = e.classList[s];
        if (t.test(i)) return !0;
      }
    if (n) return e.matches(n);
  } catch {}
  return !1;
}
function xk(e, t) {
  for (let n = e.classList.length; n--;) {
    const r = e.classList[n];
    if (t.test(r)) return !0;
  }
  return !1;
}
function Pt(e, t, n = 1 / 0, r = 0) {
  return !e || e.nodeType !== e.ELEMENT_NODE || r > n
    ? -1
    : t(e)
      ? r
      : Pt(e.parentNode, t, n, r + 1);
}
function sn(e, t) {
  return (n) => {
    const r = n;
    if (r === null) return !1;
    try {
      if (e) {
        if (typeof e == "string") {
          if (r.matches(`.${e}`)) return !0;
        } else if (xk(r, e)) return !0;
      }
      return !!(t && r.matches(t));
    } catch {
      return !1;
    }
  };
}
function vn(e, t, n, r, s, i) {
  try {
    const o = e.nodeType === e.ELEMENT_NODE ? e : e.parentElement;
    if (o === null) return !1;
    if (o.tagName === "INPUT") {
      const u = o.getAttribute("autocomplete");
      if (
        [
          "current-password",
          "new-password",
          "cc-number",
          "cc-exp",
          "cc-exp-month",
          "cc-exp-year",
          "cc-csc",
        ].includes(u)
      )
        return !0;
    }
    let a = -1,
      c = -1;
    if (i) {
      if (((c = Pt(o, sn(r, s))), c < 0)) return !0;
      a = Pt(o, sn(t, n), c >= 0 ? c : 1 / 0);
    } else {
      if (((a = Pt(o, sn(t, n))), a < 0)) return !1;
      c = Pt(o, sn(r, s), a >= 0 ? a : 1 / 0);
    }
    return a >= 0 ? (c >= 0 ? a <= c : !0) : c >= 0 ? !1 : !!i;
  } catch {}
  return !!i;
}
function Ak(e, t, n) {
  const r = e.contentWindow;
  if (!r) return;
  let s = !1,
    i;
  try {
    i = r.document.readyState;
  } catch {
    return;
  }
  if (i !== "complete") {
    const a = Bo(() => {
      s || (t(), (s = !0));
    }, n);
    e.addEventListener("load", () => {
      (yh(a), (s = !0), t());
    });
    return;
  }
  const o = "about:blank";
  if (r.location.href !== o || e.src === o || e.src === "")
    return (Bo(t, 0), e.addEventListener("load", t));
  e.addEventListener("load", t);
}
function Mk(e, t, n) {
  let r = !1,
    s;
  try {
    s = e.sheet;
  } catch {
    return;
  }
  if (s) return;
  const i = Bo(() => {
    r || (t(), (r = !0));
  }, n);
  e.addEventListener("load", () => {
    (yh(i), (r = !0), t());
  });
}
function Nk(e, t) {
  const {
      doc: n,
      mirror: r,
      blockClass: s,
      blockSelector: i,
      unblockSelector: o,
      maskAllText: a,
      maskAttributeFn: c,
      maskTextClass: u,
      unmaskTextClass: d,
      maskTextSelector: l,
      unmaskTextSelector: p,
      inlineStylesheet: f,
      maskInputOptions: h = {},
      maskTextFn: m,
      maskInputFn: g,
      dataURLOptions: _ = {},
      inlineImages: y,
      recordCanvas: M,
      keepIframeSrcFn: w,
      newlyAddedElement: A = !1,
    } = t,
    C = Ok(n, r);
  switch (e.nodeType) {
    case e.DOCUMENT_NODE:
      return e.compatMode !== "CSS1Compat"
        ? { type: _e.Document, childNodes: [], compatMode: e.compatMode }
        : { type: _e.Document, childNodes: [] };
    case e.DOCUMENT_TYPE_NODE:
      return {
        type: _e.DocumentType,
        name: e.name,
        publicId: e.publicId,
        systemId: e.systemId,
        rootId: C,
      };
    case e.ELEMENT_NODE:
      return $k(e, {
        doc: n,
        blockClass: s,
        blockSelector: i,
        unblockSelector: o,
        inlineStylesheet: f,
        maskAttributeFn: c,
        maskInputOptions: h,
        maskInputFn: g,
        dataURLOptions: _,
        inlineImages: y,
        recordCanvas: M,
        keepIframeSrcFn: w,
        newlyAddedElement: A,
        rootId: C,
        maskTextClass: u,
        unmaskTextClass: d,
        maskTextSelector: l,
        unmaskTextSelector: p,
      });
    case e.TEXT_NODE:
      return Lk(e, {
        doc: n,
        maskAllText: a,
        maskTextClass: u,
        unmaskTextClass: d,
        maskTextSelector: l,
        unmaskTextSelector: p,
        maskTextFn: m,
        maskInputOptions: h,
        maskInputFn: g,
        rootId: C,
      });
    case e.CDATA_SECTION_NODE:
      return { type: _e.CDATA, textContent: "", rootId: C };
    case e.COMMENT_NODE:
      return { type: _e.Comment, textContent: e.textContent || "", rootId: C };
    default:
      return !1;
  }
}
function Ok(e, t) {
  if (!t.hasNode(e)) return;
  const n = t.getId(e);
  return n === 1 ? void 0 : n;
}
function Lk(e, t) {
  const {
      maskAllText: n,
      maskTextClass: r,
      unmaskTextClass: s,
      maskTextSelector: i,
      unmaskTextSelector: o,
      maskTextFn: a,
      maskInputOptions: c,
      maskInputFn: u,
      rootId: d,
    } = t,
    l = e.parentNode && e.parentNode.tagName;
  let p = e.textContent;
  const f = l === "STYLE" ? !0 : void 0,
    h = l === "SCRIPT" ? !0 : void 0,
    m = l === "TEXTAREA" ? !0 : void 0;
  if (f && p) {
    try {
      e.nextSibling ||
        e.previousSibling ||
        (e.parentNode.sheet?.cssRules && (p = Gs(e.parentNode.sheet)));
    } catch (_) {
      console.warn(
        `Cannot get CSS styles from text's parentNode. Error: ${_}`,
        e,
      );
    }
    p = Ys(p, Ci(t.doc));
  }
  h && (p = "SCRIPT_PLACEHOLDER");
  const g = vn(e, r, i, s, o, n);
  if (
    (!f &&
      !h &&
      !m &&
      p &&
      g &&
      (p = a ? a(p, e.parentElement) : p.replace(/[\S]/g, "*")),
    m &&
      p &&
      (c.textarea || g) &&
      (p = u ? u(p, e.parentNode) : p.replace(/[\S]/g, "*")),
    l === "OPTION" && p)
  ) {
    const _ = ki({ type: null, tagName: l, maskInputOptions: c });
    p = cr({
      isMasked: vn(e, r, i, s, o, _),
      element: e,
      value: p,
      maskInputFn: u,
    });
  }
  return { type: _e.Text, textContent: p || "", isStyle: f, rootId: d };
}
function $k(e, t) {
  const {
      doc: n,
      blockClass: r,
      blockSelector: s,
      unblockSelector: i,
      inlineStylesheet: o,
      maskInputOptions: a = {},
      maskAttributeFn: c,
      maskInputFn: u,
      dataURLOptions: d = {},
      inlineImages: l,
      recordCanvas: p,
      keepIframeSrcFn: f,
      newlyAddedElement: h = !1,
      rootId: m,
      maskTextClass: g,
      unmaskTextClass: _,
      maskTextSelector: y,
      unmaskTextSelector: M,
    } = t,
    w = Rk(e, r, s, i),
    A = Sk(e);
  let C = {};
  const E = e.attributes.length;
  for (let b = 0; b < E; b++) {
    const k = e.attributes[b];
    k.name &&
      !vh(A, k.name, k.value) &&
      (C[k.name] = Eh(n, A, En(k.name), k.value, e, c));
  }
  if (A === "link" && o) {
    const b = Array.from(n.styleSheets).find((O) => O.href === e.href);
    let k = null;
    (b && (k = Gs(b)),
      k &&
        ((C.rel = null),
        (C.href = null),
        (C.crossorigin = null),
        (C._cssText = Ys(k, b.href))));
  }
  if (
    A === "style" &&
    e.sheet &&
    !(e.innerText || e.textContent || "").trim().length
  ) {
    const b = Gs(e.sheet);
    b && (C._cssText = Ys(b, Ci(n)));
  }
  if (A === "input" || A === "textarea" || A === "select" || A === "option") {
    const b = e,
      k = hc(b),
      O = Vs(b, Fo(A), k),
      v = b.checked;
    if (k !== "submit" && k !== "button" && O) {
      const x = vn(
        b,
        g,
        y,
        _,
        M,
        ki({ type: k, tagName: Fo(A), maskInputOptions: a }),
      );
      C.value = cr({ isMasked: x, element: b, value: O, maskInputFn: u });
    }
    v && (C.checked = v);
  }
  if (
    (A === "option" &&
      (e.selected && !a.select ? (C.selected = !0) : delete C.selected),
    A === "canvas" && p)
  ) {
    if (e.__context === "2d")
      mk(e) || (C.rr_dataURL = e.toDataURL(d.type, d.quality));
    else if (!("__context" in e)) {
      const b = e.toDataURL(d.type, d.quality),
        k = n.createElement("canvas");
      ((k.width = e.width), (k.height = e.height));
      const O = k.toDataURL(d.type, d.quality);
      b !== O && (C.rr_dataURL = b);
    }
  }
  if (A === "img" && l) {
    Qt || ((Qt = n.createElement("canvas")), ($l = Qt.getContext("2d")));
    const b = e,
      k = b.currentSrc || b.getAttribute("src") || "<unknown-src>",
      O = b.crossOrigin,
      v = () => {
        b.removeEventListener("load", v);
        try {
          ((Qt.width = b.naturalWidth),
            (Qt.height = b.naturalHeight),
            $l.drawImage(b, 0, 0),
            (C.rr_dataURL = Qt.toDataURL(d.type, d.quality)));
        } catch (x) {
          if (b.crossOrigin !== "anonymous") {
            ((b.crossOrigin = "anonymous"),
              b.complete && b.naturalWidth !== 0
                ? v()
                : b.addEventListener("load", v));
            return;
          } else console.warn(`Cannot inline img src=${k}! Error: ${x}`);
        }
        b.crossOrigin === "anonymous" &&
          (O ? (C.crossOrigin = O) : b.removeAttribute("crossorigin"));
      };
    b.complete && b.naturalWidth !== 0 ? v() : b.addEventListener("load", v);
  }
  if (
    ((A === "audio" || A === "video") &&
      ((C.rr_mediaState = e.paused ? "paused" : "played"),
      (C.rr_mediaCurrentTime = e.currentTime)),
    h ||
      (e.scrollLeft && (C.rr_scrollLeft = e.scrollLeft),
      e.scrollTop && (C.rr_scrollTop = e.scrollTop)),
    w)
  ) {
    const { width: b, height: k } = e.getBoundingClientRect();
    C = { class: C.class, rr_width: `${b}px`, rr_height: `${k}px` };
  }
  A === "iframe" &&
    !f(C.src) &&
    (!w && !bh(e) && (C.rr_src = C.src), delete C.src);
  let I;
  try {
    customElements.get(A) && (I = !0);
  } catch {}
  return {
    type: _e.Element,
    tagName: A,
    attributes: C,
    childNodes: [],
    isSVG: Ck(e) || void 0,
    needBlock: w,
    rootId: m,
    isCustom: I,
  };
}
function oe(e) {
  return e == null ? "" : e.toLowerCase();
}
function Dk(e, t) {
  if (t.comment && e.type === _e.Comment) return !0;
  if (e.type === _e.Element) {
    if (
      t.script &&
      (e.tagName === "script" ||
        (e.tagName === "link" &&
          (e.attributes.rel === "preload" ||
            e.attributes.rel === "modulepreload")) ||
        (e.tagName === "link" &&
          e.attributes.rel === "prefetch" &&
          typeof e.attributes.href == "string" &&
          _h(e.attributes.href) === "js"))
    )
      return !0;
    if (
      t.headFavicon &&
      ((e.tagName === "link" && e.attributes.rel === "shortcut icon") ||
        (e.tagName === "meta" &&
          (oe(e.attributes.name).match(/^msapplication-tile(image|color)$/) ||
            oe(e.attributes.name) === "application-name" ||
            oe(e.attributes.rel) === "icon" ||
            oe(e.attributes.rel) === "apple-touch-icon" ||
            oe(e.attributes.rel) === "shortcut icon")))
    )
      return !0;
    if (e.tagName === "meta") {
      if (
        t.headMetaDescKeywords &&
        oe(e.attributes.name).match(/^description|keywords$/)
      )
        return !0;
      if (
        t.headMetaSocial &&
        (oe(e.attributes.property).match(/^(og|twitter|fb):/) ||
          oe(e.attributes.name).match(/^(og|twitter):/) ||
          oe(e.attributes.name) === "pinterest")
      )
        return !0;
      if (
        t.headMetaRobots &&
        (oe(e.attributes.name) === "robots" ||
          oe(e.attributes.name) === "googlebot" ||
          oe(e.attributes.name) === "bingbot")
      )
        return !0;
      if (t.headMetaHttpEquiv && e.attributes["http-equiv"] !== void 0)
        return !0;
      if (
        t.headMetaAuthorship &&
        (oe(e.attributes.name) === "author" ||
          oe(e.attributes.name) === "generator" ||
          oe(e.attributes.name) === "framework" ||
          oe(e.attributes.name) === "publisher" ||
          oe(e.attributes.name) === "progid" ||
          oe(e.attributes.property).match(/^article:/) ||
          oe(e.attributes.property).match(/^product:/))
      )
        return !0;
      if (
        t.headMetaVerification &&
        (oe(e.attributes.name) === "google-site-verification" ||
          oe(e.attributes.name) === "yandex-verification" ||
          oe(e.attributes.name) === "csrf-token" ||
          oe(e.attributes.name) === "p:domain_verify" ||
          oe(e.attributes.name) === "verify-v1" ||
          oe(e.attributes.name) === "verification" ||
          oe(e.attributes.name) === "shopify-checkout-api-token")
      )
        return !0;
    }
  }
  return !1;
}
function on(e, t) {
  const {
    doc: n,
    mirror: r,
    blockClass: s,
    blockSelector: i,
    unblockSelector: o,
    maskAllText: a,
    maskTextClass: c,
    unmaskTextClass: u,
    maskTextSelector: d,
    unmaskTextSelector: l,
    skipChild: p = !1,
    inlineStylesheet: f = !0,
    maskInputOptions: h = {},
    maskAttributeFn: m,
    maskTextFn: g,
    maskInputFn: _,
    slimDOMOptions: y,
    dataURLOptions: M = {},
    inlineImages: w = !1,
    recordCanvas: A = !1,
    onSerialize: C,
    onIframeLoad: E,
    iframeLoadTimeout: I = 5e3,
    onBlockedImageLoad: b,
    onStylesheetLoad: k,
    stylesheetLoadTimeout: O = 5e3,
    keepIframeSrcFn: v = () => !1,
    newlyAddedElement: x = !1,
  } = t;
  let { preserveWhiteSpace: U = !0 } = t;
  const q = Nk(e, {
    doc: n,
    mirror: r,
    blockClass: s,
    blockSelector: i,
    maskAllText: a,
    unblockSelector: o,
    maskTextClass: c,
    unmaskTextClass: u,
    maskTextSelector: d,
    unmaskTextSelector: l,
    inlineStylesheet: f,
    maskInputOptions: h,
    maskAttributeFn: m,
    maskTextFn: g,
    maskInputFn: _,
    dataURLOptions: M,
    inlineImages: w,
    recordCanvas: A,
    keepIframeSrcFn: v,
    newlyAddedElement: x,
  });
  if (!q) return (console.warn(e, "not serialized"), null);
  let K;
  r.hasNode(e)
    ? (K = r.getId(e))
    : Dk(q, y) ||
        (!U &&
          q.type === _e.Text &&
          !q.isStyle &&
          !q.textContent.replace(/^\s+|\s+$/gm, "").length)
      ? (K = ur)
      : (K = mc());
  const T = Object.assign(q, { id: K });
  if ((r.add(e, T), K === ur)) return null;
  C && C(e);
  let P = !p;
  if (T.type === _e.Element) {
    P = P && !T.needBlock;
    const R = e.shadowRoot;
    R && Xn(R) && (T.isShadowHost = !0);
  }
  if ((T.type === _e.Document || T.type === _e.Element) && P) {
    y.headWhitespace &&
      T.type === _e.Element &&
      T.tagName === "head" &&
      (U = !1);
    const R = {
        doc: n,
        mirror: r,
        blockClass: s,
        blockSelector: i,
        maskAllText: a,
        unblockSelector: o,
        maskTextClass: c,
        unmaskTextClass: u,
        maskTextSelector: d,
        unmaskTextSelector: l,
        skipChild: p,
        inlineStylesheet: f,
        maskInputOptions: h,
        maskAttributeFn: m,
        maskTextFn: g,
        maskInputFn: _,
        slimDOMOptions: y,
        dataURLOptions: M,
        inlineImages: w,
        recordCanvas: A,
        preserveWhiteSpace: U,
        onSerialize: C,
        onIframeLoad: E,
        iframeLoadTimeout: I,
        onBlockedImageLoad: b,
        onStylesheetLoad: k,
        stylesheetLoadTimeout: O,
        keepIframeSrcFn: v,
      },
      L = e.childNodes ? Array.from(e.childNodes) : [];
    for (const V of L) {
      const Q = on(V, R);
      Q && T.childNodes.push(Q);
    }
    if (ak(e) && e.shadowRoot)
      for (const V of Array.from(e.shadowRoot.childNodes)) {
        const Q = on(V, R);
        Q && (Xn(e.shadowRoot) && (Q.isShadow = !0), T.childNodes.push(Q));
      }
  }
  if (
    (e.parentNode && Yn(e.parentNode) && Xn(e.parentNode) && (T.isShadow = !0),
    T.type === _e.Element &&
      T.tagName === "iframe" &&
      !T.needBlock &&
      Ak(
        e,
        () => {
          const R = bh(e);
          if (R && E) {
            const L = on(R, {
              doc: R,
              mirror: r,
              blockClass: s,
              blockSelector: i,
              unblockSelector: o,
              maskAllText: a,
              maskTextClass: c,
              unmaskTextClass: u,
              maskTextSelector: d,
              unmaskTextSelector: l,
              skipChild: !1,
              inlineStylesheet: f,
              maskInputOptions: h,
              maskAttributeFn: m,
              maskTextFn: g,
              maskInputFn: _,
              slimDOMOptions: y,
              dataURLOptions: M,
              inlineImages: w,
              recordCanvas: A,
              preserveWhiteSpace: U,
              onSerialize: C,
              onIframeLoad: E,
              iframeLoadTimeout: I,
              onStylesheetLoad: k,
              stylesheetLoadTimeout: O,
              keepIframeSrcFn: v,
            });
            L && E(e, L);
          }
        },
        I,
      ),
    T.type === _e.Element && T.tagName === "img" && !e.complete && T.needBlock)
  ) {
    const R = e,
      L = () => {
        if (R.isConnected && !R.complete && b)
          try {
            const V = R.getBoundingClientRect();
            V.width > 0 && V.height > 0 && b(R, T, V);
          } catch {}
        R.removeEventListener("load", L);
      };
    R.isConnected && R.addEventListener("load", L);
  }
  return (
    T.type === _e.Element &&
      T.tagName === "link" &&
      typeof T.attributes.rel == "string" &&
      (T.attributes.rel === "stylesheet" ||
        (T.attributes.rel === "preload" &&
          typeof T.attributes.href == "string" &&
          _h(T.attributes.href) === "css")) &&
      Mk(
        e,
        () => {
          if (k) {
            const R = on(e, {
              doc: n,
              mirror: r,
              blockClass: s,
              blockSelector: i,
              unblockSelector: o,
              maskAllText: a,
              maskTextClass: c,
              unmaskTextClass: u,
              maskTextSelector: d,
              unmaskTextSelector: l,
              skipChild: !1,
              inlineStylesheet: f,
              maskInputOptions: h,
              maskAttributeFn: m,
              maskTextFn: g,
              maskInputFn: _,
              slimDOMOptions: y,
              dataURLOptions: M,
              inlineImages: w,
              recordCanvas: A,
              preserveWhiteSpace: U,
              onSerialize: C,
              onIframeLoad: E,
              iframeLoadTimeout: I,
              onStylesheetLoad: k,
              stylesheetLoadTimeout: O,
              keepIframeSrcFn: v,
            });
            R && k(e, R);
          }
        },
        O,
      ),
    T.type === _e.Element && delete T.needBlock,
    T
  );
}
function Pk(e, t) {
  const {
    mirror: n = new gh(),
    blockClass: r = "rr-block",
    blockSelector: s = null,
    unblockSelector: i = null,
    maskAllText: o = !1,
    maskTextClass: a = "rr-mask",
    unmaskTextClass: c = null,
    maskTextSelector: u = null,
    unmaskTextSelector: d = null,
    inlineStylesheet: l = !0,
    inlineImages: p = !1,
    recordCanvas: f = !1,
    maskAllInputs: h = !1,
    maskAttributeFn: m,
    maskTextFn: g,
    maskInputFn: _,
    slimDOM: y = !1,
    dataURLOptions: M,
    preserveWhiteSpace: w,
    onSerialize: A,
    onIframeLoad: C,
    iframeLoadTimeout: E,
    onBlockedImageLoad: I,
    onStylesheetLoad: b,
    stylesheetLoadTimeout: k,
    keepIframeSrcFn: O = () => !1,
  } = t || {};
  return on(e, {
    doc: e,
    mirror: n,
    blockClass: r,
    blockSelector: s,
    unblockSelector: i,
    maskAllText: o,
    maskTextClass: a,
    unmaskTextClass: c,
    maskTextSelector: u,
    unmaskTextSelector: d,
    skipChild: !1,
    inlineStylesheet: l,
    maskInputOptions:
      h === !0
        ? {
            color: !0,
            date: !0,
            "datetime-local": !0,
            email: !0,
            month: !0,
            number: !0,
            range: !0,
            search: !0,
            tel: !0,
            text: !0,
            time: !0,
            url: !0,
            week: !0,
            textarea: !0,
            select: !0,
          }
        : h === !1
          ? {}
          : h,
    maskAttributeFn: m,
    maskTextFn: g,
    maskInputFn: _,
    slimDOMOptions:
      y === !0 || y === "all"
        ? {
            script: !0,
            comment: !0,
            headFavicon: !0,
            headWhitespace: !0,
            headMetaDescKeywords: y === "all",
            headMetaSocial: !0,
            headMetaRobots: !0,
            headMetaHttpEquiv: !0,
            headMetaAuthorship: !0,
            headMetaVerification: !0,
          }
        : y === !1
          ? {}
          : y,
    dataURLOptions: M,
    inlineImages: p,
    recordCanvas: f,
    preserveWhiteSpace: w,
    onSerialize: A,
    onIframeLoad: C,
    iframeLoadTimeout: E,
    onBlockedImageLoad: I,
    onStylesheetLoad: b,
    stylesheetLoadTimeout: k,
    keepIframeSrcFn: O,
    newlyAddedElement: !1,
  });
}
function Te(e, t, n = document) {
  const r = { capture: !0, passive: !0 };
  return (n.addEventListener(e, t, r), () => n.removeEventListener(e, t, r));
}
const en = `Please stop import mirror directly. Instead of that,\r
now you can use replayer.getMirror() to access the mirror instance of a replayer,\r
or you can use record.mirror to access the mirror instance during recording.`;
let Pl = {
  map: {},
  getId() {
    return (console.error(en), -1);
  },
  getNode() {
    return (console.error(en), null);
  },
  removeNodeFromMap() {
    console.error(en);
  },
  has() {
    return (console.error(en), !1);
  },
  reset() {
    console.error(en);
  },
};
typeof window < "u" &&
  window.Proxy &&
  window.Reflect &&
  (Pl = new Proxy(Pl, {
    get(e, t, n) {
      return (t === "map" && console.error(en), Reflect.get(e, t, n));
    },
  }));
function lr(e, t, n = {}) {
  let r = null,
    s = 0;
  return function (...i) {
    const o = Date.now();
    !s && n.leading === !1 && (s = o);
    const a = t - (o - s),
      c = this;
    a <= 0 || a > t
      ? (r && (jk(r), (r = null)), (s = o), e.apply(c, i))
      : !r &&
        n.trailing !== !1 &&
        (r = Ri(() => {
          ((s = n.leading === !1 ? 0 : Date.now()), (r = null), e.apply(c, i));
        }, a));
  };
}
function Th(e, t, n, r, s = window) {
  const i = s.Object.getOwnPropertyDescriptor(e, t);
  return (
    s.Object.defineProperty(
      e,
      t,
      r
        ? n
        : {
            set(o) {
              (Ri(() => {
                n.set.call(this, o);
              }, 0),
                i && i.set && i.set.call(this, o));
            },
          },
    ),
    () => Th(e, t, i || {}, !0)
  );
}
function gc(e, t, n) {
  try {
    if (!(t in e)) return () => {};
    const r = e[t],
      s = n(r);
    return (
      typeof s == "function" &&
        ((s.prototype = s.prototype || {}),
        Object.defineProperties(s, {
          __rrweb_original__: { enumerable: !1, value: r },
        })),
      (e[t] = s),
      () => {
        e[t] = r;
      }
    );
  } catch {
    return () => {};
  }
}
let Xs = Date.now;
/[1-9][0-9]{12}/.test(Date.now().toString()) ||
  (Xs = () => new Date().getTime());
function wh(e) {
  const t = e.document;
  return {
    left: t.scrollingElement
      ? t.scrollingElement.scrollLeft
      : e.pageXOffset !== void 0
        ? e.pageXOffset
        : t?.documentElement.scrollLeft ||
          t?.body?.parentElement?.scrollLeft ||
          t?.body?.scrollLeft ||
          0,
    top: t.scrollingElement
      ? t.scrollingElement.scrollTop
      : e.pageYOffset !== void 0
        ? e.pageYOffset
        : t?.documentElement.scrollTop ||
          t?.body?.parentElement?.scrollTop ||
          t?.body?.scrollTop ||
          0,
  };
}
function Ih() {
  return (
    window.innerHeight ||
    (document.documentElement && document.documentElement.clientHeight) ||
    (document.body && document.body.clientHeight)
  );
}
function kh() {
  return (
    window.innerWidth ||
    (document.documentElement && document.documentElement.clientWidth) ||
    (document.body && document.body.clientWidth)
  );
}
function Ch(e) {
  if (!e) return null;
  try {
    return e.nodeType === e.ELEMENT_NODE ? e : e.parentElement;
  } catch {
    return null;
  }
}
function Ae(e, t, n, r, s) {
  if (!e) return !1;
  const i = Ch(e);
  if (!i) return !1;
  const o = sn(t, n);
  if (!s) {
    const u = r && i.matches(r);
    return o(i) && !u;
  }
  const a = Pt(i, o);
  let c = -1;
  return a < 0
    ? !1
    : (r && (c = Pt(i, sn(null, r))), a > -1 && c < 0 ? !0 : a < c);
}
function Fk(e, t) {
  return t.getId(e) !== -1;
}
function no(e, t) {
  return t.getId(e) === ur;
}
function Rh(e, t) {
  if (Yn(e)) return !1;
  const n = t.getId(e);
  return t.has(n)
    ? e.parentNode && e.parentNode.nodeType === e.DOCUMENT_NODE
      ? !1
      : e.parentNode
        ? Rh(e.parentNode, t)
        : !0
    : !0;
}
function Uo(e) {
  return !!e.changedTouches;
}
function Bk(e = window) {
  ("NodeList" in e &&
    !e.NodeList.prototype.forEach &&
    (e.NodeList.prototype.forEach = Array.prototype.forEach),
    "DOMTokenList" in e &&
      !e.DOMTokenList.prototype.forEach &&
      (e.DOMTokenList.prototype.forEach = Array.prototype.forEach),
    Node.prototype.contains ||
      (Node.prototype.contains = (...t) => {
        let n = t[0];
        if (!(0 in t)) throw new TypeError("1 argument is required");
        do if (this === n) return !0;
        while ((n = n && n.parentNode));
        return !1;
      }));
}
function xh(e, t) {
  return !!(e.nodeName === "IFRAME" && t.getMeta(e));
}
function Ah(e, t) {
  return !!(
    e.nodeName === "LINK" &&
    e.nodeType === e.ELEMENT_NODE &&
    e.getAttribute &&
    e.getAttribute("rel") === "stylesheet" &&
    t.getMeta(e)
  );
}
function Ho(e) {
  return !!e?.shadowRoot;
}
class Uk {
  constructor() {
    ((this.id = 1),
      (this.styleIDMap = new WeakMap()),
      (this.idStyleMap = new Map()));
  }
  getId(t) {
    return this.styleIDMap.get(t) ?? -1;
  }
  has(t) {
    return this.styleIDMap.has(t);
  }
  add(t, n) {
    if (this.has(t)) return this.getId(t);
    let r;
    return (
      n === void 0 ? (r = this.id++) : (r = n),
      this.styleIDMap.set(t, r),
      this.idStyleMap.set(r, t),
      r
    );
  }
  getStyle(t) {
    return this.idStyleMap.get(t) || null;
  }
  reset() {
    ((this.styleIDMap = new WeakMap()),
      (this.idStyleMap = new Map()),
      (this.id = 1));
  }
  generateId() {
    return this.id++;
  }
}
function Mh(e) {
  let t = null;
  return (
    e.getRootNode?.()?.nodeType === Node.DOCUMENT_FRAGMENT_NODE &&
      e.getRootNode().host &&
      (t = e.getRootNode().host),
    t
  );
}
function Hk(e) {
  let t = e,
    n;
  for (; (n = Mh(t));) t = n;
  return t;
}
function Wk(e) {
  const t = e.ownerDocument;
  if (!t) return !1;
  const n = Hk(e);
  return t.contains(n);
}
function Nh(e) {
  const t = e.ownerDocument;
  return t ? t.contains(e) || Wk(e) : !1;
}
const Fl = {};
function _c(e) {
  const t = Fl[e];
  if (t) return t;
  const n = window.document;
  let r = window[e];
  if (n && typeof n.createElement == "function")
    try {
      const s = n.createElement("iframe");
      ((s.hidden = !0), n.head.appendChild(s));
      const i = s.contentWindow;
      (i && i[e] && (r = i[e]), n.head.removeChild(s));
    } catch {}
  return (Fl[e] = r.bind(window));
}
function zk(...e) {
  return _c("requestAnimationFrame")(...e);
}
function Ri(...e) {
  return _c("setTimeout")(...e);
}
function jk(...e) {
  return _c("clearTimeout")(...e);
}
var z = ((e) => (
    (e[(e.DomContentLoaded = 0)] = "DomContentLoaded"),
    (e[(e.Load = 1)] = "Load"),
    (e[(e.FullSnapshot = 2)] = "FullSnapshot"),
    (e[(e.IncrementalSnapshot = 3)] = "IncrementalSnapshot"),
    (e[(e.Meta = 4)] = "Meta"),
    (e[(e.Custom = 5)] = "Custom"),
    (e[(e.Plugin = 6)] = "Plugin"),
    e
  ))(z || {}),
  F = ((e) => (
    (e[(e.Mutation = 0)] = "Mutation"),
    (e[(e.MouseMove = 1)] = "MouseMove"),
    (e[(e.MouseInteraction = 2)] = "MouseInteraction"),
    (e[(e.Scroll = 3)] = "Scroll"),
    (e[(e.ViewportResize = 4)] = "ViewportResize"),
    (e[(e.Input = 5)] = "Input"),
    (e[(e.TouchMove = 6)] = "TouchMove"),
    (e[(e.MediaInteraction = 7)] = "MediaInteraction"),
    (e[(e.StyleSheetRule = 8)] = "StyleSheetRule"),
    (e[(e.CanvasMutation = 9)] = "CanvasMutation"),
    (e[(e.Font = 10)] = "Font"),
    (e[(e.Log = 11)] = "Log"),
    (e[(e.Drag = 12)] = "Drag"),
    (e[(e.StyleDeclaration = 13)] = "StyleDeclaration"),
    (e[(e.Selection = 14)] = "Selection"),
    (e[(e.AdoptedStyleSheet = 15)] = "AdoptedStyleSheet"),
    (e[(e.CustomElement = 16)] = "CustomElement"),
    e
  ))(F || {}),
  ve = ((e) => (
    (e[(e.MouseUp = 0)] = "MouseUp"),
    (e[(e.MouseDown = 1)] = "MouseDown"),
    (e[(e.Click = 2)] = "Click"),
    (e[(e.ContextMenu = 3)] = "ContextMenu"),
    (e[(e.DblClick = 4)] = "DblClick"),
    (e[(e.Focus = 5)] = "Focus"),
    (e[(e.Blur = 6)] = "Blur"),
    (e[(e.TouchStart = 7)] = "TouchStart"),
    (e[(e.TouchMove_Departed = 8)] = "TouchMove_Departed"),
    (e[(e.TouchEnd = 9)] = "TouchEnd"),
    (e[(e.TouchCancel = 10)] = "TouchCancel"),
    e
  ))(ve || {}),
  tt = ((e) => (
    (e[(e.Mouse = 0)] = "Mouse"),
    (e[(e.Pen = 1)] = "Pen"),
    (e[(e.Touch = 2)] = "Touch"),
    e
  ))(tt || {}),
  tn = ((e) => (
    (e[(e.Play = 0)] = "Play"),
    (e[(e.Pause = 1)] = "Pause"),
    (e[(e.Seeked = 2)] = "Seeked"),
    (e[(e.VolumeChange = 3)] = "VolumeChange"),
    (e[(e.RateChange = 4)] = "RateChange"),
    e
  ))(tn || {});
function Sc(e) {
  try {
    return e.contentDocument;
  } catch {}
}
function qk(e) {
  try {
    return e.contentWindow;
  } catch {}
}
function Bl(e) {
  return "__ln" in e;
}
class Gk {
  constructor() {
    ((this.length = 0), (this.head = null), (this.tail = null));
  }
  get(t) {
    if (t >= this.length) throw new Error("Position outside of list range");
    let n = this.head;
    for (let r = 0; r < t; r++) n = n?.next || null;
    return n;
  }
  addNode(t) {
    const n = { value: t, previous: null, next: null };
    if (((t.__ln = n), t.previousSibling && Bl(t.previousSibling))) {
      const r = t.previousSibling.__ln.next;
      ((n.next = r),
        (n.previous = t.previousSibling.__ln),
        (t.previousSibling.__ln.next = n),
        r && (r.previous = n));
    } else if (
      t.nextSibling &&
      Bl(t.nextSibling) &&
      t.nextSibling.__ln.previous
    ) {
      const r = t.nextSibling.__ln.previous;
      ((n.previous = r),
        (n.next = t.nextSibling.__ln),
        (t.nextSibling.__ln.previous = n),
        r && (r.next = n));
    } else
      (this.head && (this.head.previous = n),
        (n.next = this.head),
        (this.head = n));
    (n.next === null && (this.tail = n), this.length++);
  }
  removeNode(t) {
    const n = t.__ln;
    this.head &&
      (n.previous
        ? ((n.previous.next = n.next),
          n.next ? (n.next.previous = n.previous) : (this.tail = n.previous))
        : ((this.head = n.next),
          this.head ? (this.head.previous = null) : (this.tail = null)),
      t.__ln && delete t.__ln,
      this.length--);
  }
}
const Ul = (e, t) => `${e}@${t}`;
class Vk {
  constructor() {
    ((this.frozen = !1),
      (this.locked = !1),
      (this.texts = []),
      (this.attributes = []),
      (this.attributeMap = new WeakMap()),
      (this.removes = []),
      (this.mapRemoves = []),
      (this.movedMap = {}),
      (this.addedSet = new Set()),
      (this.movedSet = new Set()),
      (this.droppedSet = new Set()),
      (this.processMutations = (t) => {
        (t.forEach(this.processMutation), this.emit());
      }),
      (this.emit = () => {
        if (this.frozen || this.locked) return;
        const t = [],
          n = new Set(),
          r = new Gk(),
          s = (c) => {
            let u = c,
              d = ur;
            for (; d === ur;)
              ((u = u && u.nextSibling), (d = u && this.mirror.getId(u)));
            return d;
          },
          i = (c) => {
            if (!c.parentNode || !Nh(c)) return;
            const u = Yn(c.parentNode)
                ? this.mirror.getId(Mh(c))
                : this.mirror.getId(c.parentNode),
              d = s(c);
            if (u === -1 || d === -1) return r.addNode(c);
            const l = on(c, {
              doc: this.doc,
              mirror: this.mirror,
              blockClass: this.blockClass,
              blockSelector: this.blockSelector,
              maskAllText: this.maskAllText,
              unblockSelector: this.unblockSelector,
              maskTextClass: this.maskTextClass,
              unmaskTextClass: this.unmaskTextClass,
              maskTextSelector: this.maskTextSelector,
              unmaskTextSelector: this.unmaskTextSelector,
              skipChild: !0,
              newlyAddedElement: !0,
              inlineStylesheet: this.inlineStylesheet,
              maskInputOptions: this.maskInputOptions,
              maskAttributeFn: this.maskAttributeFn,
              maskTextFn: this.maskTextFn,
              maskInputFn: this.maskInputFn,
              slimDOMOptions: this.slimDOMOptions,
              dataURLOptions: this.dataURLOptions,
              recordCanvas: this.recordCanvas,
              inlineImages: this.inlineImages,
              onSerialize: (p) => {
                (xh(p, this.mirror) &&
                  !Ae(
                    p,
                    this.blockClass,
                    this.blockSelector,
                    this.unblockSelector,
                    !1,
                  ) &&
                  this.iframeManager.addIframe(p),
                  Ah(p, this.mirror) &&
                    this.stylesheetManager.trackLinkElement(p),
                  Ho(c) &&
                    this.shadowDomManager.addShadowRoot(
                      c.shadowRoot,
                      this.doc,
                    ));
              },
              onIframeLoad: (p, f) => {
                Ae(
                  p,
                  this.blockClass,
                  this.blockSelector,
                  this.unblockSelector,
                  !1,
                ) ||
                  (this.iframeManager.attachIframe(p, f),
                  p.contentWindow &&
                    this.canvasManager.addWindow(p.contentWindow),
                  this.shadowDomManager.observeAttachShadow(p));
              },
              onStylesheetLoad: (p, f) => {
                this.stylesheetManager.attachLinkElement(p, f);
              },
              onBlockedImageLoad: (p, f, { width: h, height: m }) => {
                this.mutationCb({
                  adds: [],
                  removes: [],
                  texts: [],
                  attributes: [
                    {
                      id: f.id,
                      attributes: {
                        style: { width: `${h}px`, height: `${m}px` },
                      },
                    },
                  ],
                });
              },
            });
            l && (t.push({ parentId: u, nextId: d, node: l }), n.add(l.id));
          };
        for (; this.mapRemoves.length;)
          this.mirror.removeNodeFromMap(this.mapRemoves.shift());
        for (const c of this.movedSet)
          (Hl(this.removes, c, this.mirror) &&
            !this.movedSet.has(c.parentNode)) ||
            i(c);
        for (const c of this.addedSet)
          (!Wl(this.droppedSet, c) && !Hl(this.removes, c, this.mirror)) ||
          Wl(this.movedSet, c)
            ? i(c)
            : this.droppedSet.add(c);
        let o = null;
        for (; r.length;) {
          let c = null;
          if (o) {
            const u = this.mirror.getId(o.value.parentNode),
              d = s(o.value);
            u !== -1 && d !== -1 && (c = o);
          }
          if (!c) {
            let u = r.tail;
            for (; u;) {
              const d = u;
              if (((u = u.previous), d)) {
                const l = this.mirror.getId(d.value.parentNode);
                if (s(d.value) === -1) continue;
                if (l !== -1) {
                  c = d;
                  break;
                } else {
                  const f = d.value;
                  if (
                    f.parentNode &&
                    f.parentNode.nodeType === Node.DOCUMENT_FRAGMENT_NODE
                  ) {
                    const h = f.parentNode.host;
                    if (this.mirror.getId(h) !== -1) {
                      c = d;
                      break;
                    }
                  }
                }
              }
            }
          }
          if (!c) {
            for (; r.head;) r.removeNode(r.head.value);
            break;
          }
          ((o = c.previous), r.removeNode(c.value), i(c.value));
        }
        const a = {
          texts: this.texts
            .map((c) => ({ id: this.mirror.getId(c.node), value: c.value }))
            .filter((c) => !n.has(c.id))
            .filter((c) => this.mirror.has(c.id)),
          attributes: this.attributes
            .map((c) => {
              const { attributes: u } = c;
              if (typeof u.style == "string") {
                const d = JSON.stringify(c.styleDiff),
                  l = JSON.stringify(c._unchangedStyles);
                d.length < u.style.length &&
                  (d + l).split("var(").length ===
                    u.style.split("var(").length &&
                  (u.style = c.styleDiff);
              }
              return { id: this.mirror.getId(c.node), attributes: u };
            })
            .filter((c) => !n.has(c.id))
            .filter((c) => this.mirror.has(c.id)),
          removes: this.removes,
          adds: t,
        };
        (!a.texts.length &&
          !a.attributes.length &&
          !a.removes.length &&
          !a.adds.length) ||
          ((this.texts = []),
          (this.attributes = []),
          (this.attributeMap = new WeakMap()),
          (this.removes = []),
          (this.addedSet = new Set()),
          (this.movedSet = new Set()),
          (this.droppedSet = new Set()),
          (this.movedMap = {}),
          this.mutationCb(a));
      }),
      (this.processMutation = (t) => {
        if (!no(t.target, this.mirror))
          switch (t.type) {
            case "characterData": {
              const n = t.target.textContent;
              !Ae(
                t.target,
                this.blockClass,
                this.blockSelector,
                this.unblockSelector,
                !1,
              ) &&
                n !== t.oldValue &&
                this.texts.push({
                  value:
                    vn(
                      t.target,
                      this.maskTextClass,
                      this.maskTextSelector,
                      this.unmaskTextClass,
                      this.unmaskTextSelector,
                      this.maskAllText,
                    ) && n
                      ? this.maskTextFn
                        ? this.maskTextFn(n, Ch(t.target))
                        : n.replace(/[\S]/g, "*")
                      : n,
                  node: t.target,
                });
              break;
            }
            case "attributes": {
              const n = t.target;
              let r = t.attributeName,
                s = t.target.getAttribute(r);
              if (r === "value") {
                const o = hc(n),
                  a = n.tagName;
                s = Vs(n, a, o);
                const c = ki({
                    maskInputOptions: this.maskInputOptions,
                    tagName: a,
                    type: o,
                  }),
                  u = vn(
                    t.target,
                    this.maskTextClass,
                    this.maskTextSelector,
                    this.unmaskTextClass,
                    this.unmaskTextSelector,
                    c,
                  );
                s = cr({
                  isMasked: u,
                  element: n,
                  value: s,
                  maskInputFn: this.maskInputFn,
                });
              }
              if (
                Ae(
                  t.target,
                  this.blockClass,
                  this.blockSelector,
                  this.unblockSelector,
                  !1,
                ) ||
                s === t.oldValue
              )
                return;
              let i = this.attributeMap.get(t.target);
              if (
                n.tagName === "IFRAME" &&
                r === "src" &&
                !this.keepIframeSrcFn(s)
              )
                if (!Sc(n)) r = "rr_src";
                else return;
              if (
                (i ||
                  ((i = {
                    node: t.target,
                    attributes: {},
                    styleDiff: {},
                    _unchangedStyles: {},
                  }),
                  this.attributes.push(i),
                  this.attributeMap.set(t.target, i)),
                r === "type" &&
                  n.tagName === "INPUT" &&
                  (t.oldValue || "").toLowerCase() === "password" &&
                  n.setAttribute("data-rr-is-password", "true"),
                !vh(n.tagName, r) &&
                  ((i.attributes[r] = Eh(
                    this.doc,
                    En(n.tagName),
                    En(r),
                    s,
                    n,
                    this.maskAttributeFn,
                  )),
                  r === "style"))
              ) {
                if (!this.unattachedDoc)
                  try {
                    this.unattachedDoc =
                      document.implementation.createHTMLDocument();
                  } catch {
                    this.unattachedDoc = this.doc;
                  }
                const o = this.unattachedDoc.createElement("span");
                t.oldValue && o.setAttribute("style", t.oldValue);
                for (const a of Array.from(n.style)) {
                  const c = n.style.getPropertyValue(a),
                    u = n.style.getPropertyPriority(a);
                  c !== o.style.getPropertyValue(a) ||
                  u !== o.style.getPropertyPriority(a)
                    ? u === ""
                      ? (i.styleDiff[a] = c)
                      : (i.styleDiff[a] = [c, u])
                    : (i._unchangedStyles[a] = [c, u]);
                }
                for (const a of Array.from(o.style))
                  n.style.getPropertyValue(a) === "" && (i.styleDiff[a] = !1);
              }
              break;
            }
            case "childList": {
              if (
                Ae(
                  t.target,
                  this.blockClass,
                  this.blockSelector,
                  this.unblockSelector,
                  !0,
                )
              )
                return;
              (t.addedNodes.forEach((n) => this.genAdds(n, t.target)),
                t.removedNodes.forEach((n) => {
                  const r = this.mirror.getId(n),
                    s = Yn(t.target)
                      ? this.mirror.getId(t.target.host)
                      : this.mirror.getId(t.target);
                  Ae(
                    t.target,
                    this.blockClass,
                    this.blockSelector,
                    this.unblockSelector,
                    !1,
                  ) ||
                    no(n, this.mirror) ||
                    !Fk(n, this.mirror) ||
                    (this.addedSet.has(n)
                      ? (Wo(this.addedSet, n), this.droppedSet.add(n))
                      : (this.addedSet.has(t.target) && r === -1) ||
                        Rh(t.target, this.mirror) ||
                        (this.movedSet.has(n) && this.movedMap[Ul(r, s)]
                          ? Wo(this.movedSet, n)
                          : this.removes.push({
                              parentId: s,
                              id: r,
                              isShadow:
                                Yn(t.target) && Xn(t.target) ? !0 : void 0,
                            })),
                    this.mapRemoves.push(n));
                }));
              break;
            }
          }
      }),
      (this.genAdds = (t, n) => {
        if (
          !this.processedNodeManager.inOtherBuffer(t, this) &&
          !(this.addedSet.has(t) || this.movedSet.has(t))
        ) {
          if (this.mirror.hasNode(t)) {
            if (no(t, this.mirror)) return;
            this.movedSet.add(t);
            let r = null;
            (n && this.mirror.hasNode(n) && (r = this.mirror.getId(n)),
              r &&
                r !== -1 &&
                (this.movedMap[Ul(this.mirror.getId(t), r)] = !0));
          } else (this.addedSet.add(t), this.droppedSet.delete(t));
          Ae(
            t,
            this.blockClass,
            this.blockSelector,
            this.unblockSelector,
            !1,
          ) ||
            (t.childNodes && t.childNodes.forEach((r) => this.genAdds(r)),
            Ho(t) &&
              t.shadowRoot.childNodes.forEach((r) => {
                (this.processedNodeManager.add(r, this), this.genAdds(r, t));
              }));
        }
      }));
  }
  init(t) {
    [
      "mutationCb",
      "blockClass",
      "blockSelector",
      "unblockSelector",
      "maskAllText",
      "maskTextClass",
      "unmaskTextClass",
      "maskTextSelector",
      "unmaskTextSelector",
      "inlineStylesheet",
      "maskInputOptions",
      "maskAttributeFn",
      "maskTextFn",
      "maskInputFn",
      "keepIframeSrcFn",
      "recordCanvas",
      "inlineImages",
      "slimDOMOptions",
      "dataURLOptions",
      "doc",
      "mirror",
      "iframeManager",
      "stylesheetManager",
      "shadowDomManager",
      "canvasManager",
      "processedNodeManager",
    ].forEach((n) => {
      this[n] = t[n];
    });
  }
  freeze() {
    ((this.frozen = !0), this.canvasManager.freeze());
  }
  unfreeze() {
    ((this.frozen = !1), this.canvasManager.unfreeze(), this.emit());
  }
  isFrozen() {
    return this.frozen;
  }
  lock() {
    ((this.locked = !0), this.canvasManager.lock());
  }
  unlock() {
    ((this.locked = !1), this.canvasManager.unlock(), this.emit());
  }
  reset() {
    (this.shadowDomManager.reset(), this.canvasManager.reset());
  }
}
function Wo(e, t) {
  (e.delete(t), t.childNodes?.forEach((n) => Wo(e, n)));
}
function Hl(e, t, n) {
  return e.length === 0 ? !1 : Yk(e, t, n);
}
function Yk(e, t, n) {
  let r = t.parentNode;
  for (; r;) {
    const s = n.getId(r);
    if (e.some((i) => i.id === s)) return !0;
    r = r.parentNode;
  }
  return !1;
}
function Wl(e, t) {
  return e.size === 0 ? !1 : Oh(e, t);
}
function Oh(e, t) {
  const { parentNode: n } = t;
  return n ? (e.has(n) ? !0 : Oh(e, n)) : !1;
}
let Kn;
function Xk(e) {
  Kn = e;
}
function Kk() {
  Kn = void 0;
}
const J = (e) =>
    Kn
      ? (...n) => {
          try {
            return e(...n);
          } catch (r) {
            if (Kn && Kn(r) === !0) return () => {};
            throw r;
          }
        }
      : e,
  an = [];
function Or(e) {
  try {
    if ("composedPath" in e) {
      const t = e.composedPath();
      if (t.length) return t[0];
    } else if ("path" in e && e.path.length) return e.path[0];
  } catch {}
  return e && e.target;
}
function Lh(e, t) {
  const n = new Vk();
  (an.push(n), n.init(e));
  let r = window.MutationObserver || window.__rrMutationObserver;
  const s = window?.Zone?.__symbol__?.("MutationObserver");
  s && window[s] && (r = window[s]);
  const i = new r(
    J((o) => {
      (e.onMutation && e.onMutation(o) === !1) || n.processMutations.bind(n)(o);
    }),
  );
  return (
    i.observe(t, {
      attributes: !0,
      attributeOldValue: !0,
      characterData: !0,
      characterDataOldValue: !0,
      childList: !0,
      subtree: !0,
    }),
    i
  );
}
function Jk({ mousemoveCb: e, sampling: t, doc: n, mirror: r }) {
  if (t.mousemove === !1) return () => {};
  const s = typeof t.mousemove == "number" ? t.mousemove : 50,
    i = typeof t.mousemoveCallback == "number" ? t.mousemoveCallback : 500;
  let o = [],
    a;
  const c = lr(
      J((l) => {
        const p = Date.now() - a;
        (e(
          o.map((f) => ((f.timeOffset -= p), f)),
          l,
        ),
          (o = []),
          (a = null));
      }),
      i,
    ),
    u = J(
      lr(
        J((l) => {
          const p = Or(l),
            { clientX: f, clientY: h } = Uo(l) ? l.changedTouches[0] : l;
          (a || (a = Xs()),
            o.push({ x: f, y: h, id: r.getId(p), timeOffset: Xs() - a }),
            c(
              typeof DragEvent < "u" && l instanceof DragEvent
                ? F.Drag
                : l instanceof MouseEvent
                  ? F.MouseMove
                  : F.TouchMove,
            ));
        }),
        s,
        { trailing: !1 },
      ),
    ),
    d = [Te("mousemove", u, n), Te("touchmove", u, n), Te("drag", u, n)];
  return J(() => {
    d.forEach((l) => l());
  });
}
function Zk({
  mouseInteractionCb: e,
  doc: t,
  mirror: n,
  blockClass: r,
  blockSelector: s,
  unblockSelector: i,
  sampling: o,
}) {
  if (o.mouseInteraction === !1) return () => {};
  const a =
      o.mouseInteraction === !0 || o.mouseInteraction === void 0
        ? {}
        : o.mouseInteraction,
    c = [];
  let u = null;
  const d = (l) => (p) => {
    const f = Or(p);
    if (Ae(f, r, s, i, !0)) return;
    let h = null,
      m = l;
    if ("pointerType" in p) {
      switch (p.pointerType) {
        case "mouse":
          h = tt.Mouse;
          break;
        case "touch":
          h = tt.Touch;
          break;
        case "pen":
          h = tt.Pen;
          break;
      }
      h === tt.Touch
        ? ve[l] === ve.MouseDown
          ? (m = "TouchStart")
          : ve[l] === ve.MouseUp && (m = "TouchEnd")
        : tt.Pen;
    } else Uo(p) && (h = tt.Touch);
    h !== null
      ? ((u = h),
        ((m.startsWith("Touch") && h === tt.Touch) ||
          (m.startsWith("Mouse") && h === tt.Mouse)) &&
          (h = null))
      : ve[l] === ve.Click && ((h = u), (u = null));
    const g = Uo(p) ? p.changedTouches[0] : p;
    if (!g) return;
    const _ = n.getId(f),
      { clientX: y, clientY: M } = g;
    J(e)({
      type: ve[m],
      id: _,
      x: y,
      y: M,
      ...(h !== null && { pointerType: h }),
    });
  };
  return (
    Object.keys(ve)
      .filter(
        (l) =>
          Number.isNaN(Number(l)) && !l.endsWith("_Departed") && a[l] !== !1,
      )
      .forEach((l) => {
        let p = En(l);
        const f = d(l);
        if (window.PointerEvent)
          switch (ve[l]) {
            case ve.MouseDown:
            case ve.MouseUp:
              p = p.replace("mouse", "pointer");
              break;
            case ve.TouchStart:
            case ve.TouchEnd:
              return;
          }
        c.push(Te(p, f, t));
      }),
    J(() => {
      c.forEach((l) => l());
    })
  );
}
function $h({
  scrollCb: e,
  doc: t,
  mirror: n,
  blockClass: r,
  blockSelector: s,
  unblockSelector: i,
  sampling: o,
}) {
  const a = J(
    lr(
      J((c) => {
        const u = Or(c);
        if (!u || Ae(u, r, s, i, !0)) return;
        const d = n.getId(u);
        if (u === t && t.defaultView) {
          const l = wh(t.defaultView);
          e({ id: d, x: l.left, y: l.top });
        } else e({ id: d, x: u.scrollLeft, y: u.scrollTop });
      }),
      o.scroll || 100,
    ),
  );
  return Te("scroll", a, t);
}
function Qk({ viewportResizeCb: e }, { win: t }) {
  let n = -1,
    r = -1;
  const s = J(
    lr(
      J(() => {
        const i = Ih(),
          o = kh();
        (n !== i || r !== o) &&
          (e({ width: Number(o), height: Number(i) }), (n = i), (r = o));
      }),
      200,
    ),
  );
  return Te("resize", s, t);
}
const eC = ["INPUT", "TEXTAREA", "SELECT"],
  zl = new WeakMap();
function tC({
  inputCb: e,
  doc: t,
  mirror: n,
  blockClass: r,
  blockSelector: s,
  unblockSelector: i,
  ignoreClass: o,
  ignoreSelector: a,
  maskInputOptions: c,
  maskInputFn: u,
  sampling: d,
  userTriggeredOnInput: l,
  maskTextClass: p,
  unmaskTextClass: f,
  maskTextSelector: h,
  unmaskTextSelector: m,
}) {
  function g(E) {
    let I = Or(E);
    const b = E.isTrusted,
      k = I && Fo(I.tagName);
    if (
      (k === "OPTION" && (I = I.parentElement),
      !I || !k || eC.indexOf(k) < 0 || Ae(I, r, s, i, !0))
    )
      return;
    const O = I;
    if (O.classList.contains(o) || (a && O.matches(a))) return;
    const v = hc(I);
    let x = Vs(O, k, v),
      U = !1;
    const q = ki({ maskInputOptions: c, tagName: k, type: v }),
      K = vn(I, p, h, f, m, q);
    ((v === "radio" || v === "checkbox") && (U = I.checked),
      (x = cr({ isMasked: K, element: I, value: x, maskInputFn: u })),
      _(
        I,
        l
          ? { text: x, isChecked: U, userTriggered: b }
          : { text: x, isChecked: U },
      ));
    const T = I.name;
    v === "radio" &&
      T &&
      U &&
      t.querySelectorAll(`input[type="radio"][name="${T}"]`).forEach((P) => {
        if (P !== I) {
          const R = cr({
            isMasked: K,
            element: P,
            value: Vs(P, k, v),
            maskInputFn: u,
          });
          _(
            P,
            l
              ? { text: R, isChecked: !U, userTriggered: !1 }
              : { text: R, isChecked: !U },
          );
        }
      });
  }
  function _(E, I) {
    const b = zl.get(E);
    if (!b || b.text !== I.text || b.isChecked !== I.isChecked) {
      zl.set(E, I);
      const k = n.getId(E);
      J(e)({ ...I, id: k });
    }
  }
  const M = (d.input === "last" ? ["change"] : ["input", "change"]).map((E) =>
      Te(E, J(g), t),
    ),
    w = t.defaultView;
  if (!w)
    return () => {
      M.forEach((E) => E());
    };
  const A = w.Object.getOwnPropertyDescriptor(
      w.HTMLInputElement.prototype,
      "value",
    ),
    C = [
      [w.HTMLInputElement.prototype, "value"],
      [w.HTMLInputElement.prototype, "checked"],
      [w.HTMLSelectElement.prototype, "value"],
      [w.HTMLTextAreaElement.prototype, "value"],
      [w.HTMLSelectElement.prototype, "selectedIndex"],
      [w.HTMLOptionElement.prototype, "selected"],
    ];
  return (
    A &&
      A.set &&
      M.push(
        ...C.map((E) =>
          Th(
            E[0],
            E[1],
            {
              set() {
                J(g)({ target: this, isTrusted: !1 });
              },
            },
            !1,
            w,
          ),
        ),
      ),
    J(() => {
      M.forEach((E) => E());
    })
  );
}
function Ks(e) {
  const t = [];
  function n(r, s) {
    if (
      (Xr("CSSGroupingRule") && r.parentRule instanceof CSSGroupingRule) ||
      (Xr("CSSMediaRule") && r.parentRule instanceof CSSMediaRule) ||
      (Xr("CSSSupportsRule") && r.parentRule instanceof CSSSupportsRule) ||
      (Xr("CSSConditionRule") && r.parentRule instanceof CSSConditionRule)
    ) {
      const o = Array.from(r.parentRule.cssRules).indexOf(r);
      s.unshift(o);
    } else if (r.parentStyleSheet) {
      const o = Array.from(r.parentStyleSheet.cssRules).indexOf(r);
      s.unshift(o);
    }
    return s;
  }
  return n(e, t);
}
function bt(e, t, n) {
  let r, s;
  return e
    ? (e.ownerNode ? (r = t.getId(e.ownerNode)) : (s = n.getId(e)),
      { styleId: s, id: r })
    : {};
}
function nC(
  { styleSheetRuleCb: e, mirror: t, stylesheetManager: n },
  { win: r },
) {
  if (!r.CSSStyleSheet || !r.CSSStyleSheet.prototype) return () => {};
  const s = r.CSSStyleSheet.prototype.insertRule;
  r.CSSStyleSheet.prototype.insertRule = new Proxy(s, {
    apply: J((d, l, p) => {
      const [f, h] = p,
        { id: m, styleId: g } = bt(l, t, n.styleMirror);
      return (
        ((m && m !== -1) || (g && g !== -1)) &&
          e({ id: m, styleId: g, adds: [{ rule: f, index: h }] }),
        d.apply(l, p)
      );
    }),
  });
  const i = r.CSSStyleSheet.prototype.deleteRule;
  r.CSSStyleSheet.prototype.deleteRule = new Proxy(i, {
    apply: J((d, l, p) => {
      const [f] = p,
        { id: h, styleId: m } = bt(l, t, n.styleMirror);
      return (
        ((h && h !== -1) || (m && m !== -1)) &&
          e({ id: h, styleId: m, removes: [{ index: f }] }),
        d.apply(l, p)
      );
    }),
  });
  let o;
  r.CSSStyleSheet.prototype.replace &&
    ((o = r.CSSStyleSheet.prototype.replace),
    (r.CSSStyleSheet.prototype.replace = new Proxy(o, {
      apply: J((d, l, p) => {
        const [f] = p,
          { id: h, styleId: m } = bt(l, t, n.styleMirror);
        return (
          ((h && h !== -1) || (m && m !== -1)) &&
            e({ id: h, styleId: m, replace: f }),
          d.apply(l, p)
        );
      }),
    })));
  let a;
  r.CSSStyleSheet.prototype.replaceSync &&
    ((a = r.CSSStyleSheet.prototype.replaceSync),
    (r.CSSStyleSheet.prototype.replaceSync = new Proxy(a, {
      apply: J((d, l, p) => {
        const [f] = p,
          { id: h, styleId: m } = bt(l, t, n.styleMirror);
        return (
          ((h && h !== -1) || (m && m !== -1)) &&
            e({ id: h, styleId: m, replaceSync: f }),
          d.apply(l, p)
        );
      }),
    })));
  const c = {};
  Kr("CSSGroupingRule")
    ? (c.CSSGroupingRule = r.CSSGroupingRule)
    : (Kr("CSSMediaRule") && (c.CSSMediaRule = r.CSSMediaRule),
      Kr("CSSConditionRule") && (c.CSSConditionRule = r.CSSConditionRule),
      Kr("CSSSupportsRule") && (c.CSSSupportsRule = r.CSSSupportsRule));
  const u = {};
  return (
    Object.entries(c).forEach(([d, l]) => {
      ((u[d] = {
        insertRule: l.prototype.insertRule,
        deleteRule: l.prototype.deleteRule,
      }),
        (l.prototype.insertRule = new Proxy(u[d].insertRule, {
          apply: J((p, f, h) => {
            const [m, g] = h,
              { id: _, styleId: y } = bt(f.parentStyleSheet, t, n.styleMirror);
            return (
              ((_ && _ !== -1) || (y && y !== -1)) &&
                e({
                  id: _,
                  styleId: y,
                  adds: [{ rule: m, index: [...Ks(f), g || 0] }],
                }),
              p.apply(f, h)
            );
          }),
        })),
        (l.prototype.deleteRule = new Proxy(u[d].deleteRule, {
          apply: J((p, f, h) => {
            const [m] = h,
              { id: g, styleId: _ } = bt(f.parentStyleSheet, t, n.styleMirror);
            return (
              ((g && g !== -1) || (_ && _ !== -1)) &&
                e({ id: g, styleId: _, removes: [{ index: [...Ks(f), m] }] }),
              p.apply(f, h)
            );
          }),
        })));
    }),
    J(() => {
      ((r.CSSStyleSheet.prototype.insertRule = s),
        (r.CSSStyleSheet.prototype.deleteRule = i),
        o && (r.CSSStyleSheet.prototype.replace = o),
        a && (r.CSSStyleSheet.prototype.replaceSync = a),
        Object.entries(c).forEach(([d, l]) => {
          ((l.prototype.insertRule = u[d].insertRule),
            (l.prototype.deleteRule = u[d].deleteRule));
        }));
    })
  );
}
function Dh({ mirror: e, stylesheetManager: t }, n) {
  let r = null;
  n.nodeName === "#document" ? (r = e.getId(n)) : (r = e.getId(n.host));
  const s =
      n.nodeName === "#document"
        ? n.defaultView?.Document
        : n.ownerDocument?.defaultView?.ShadowRoot,
    i = s?.prototype
      ? Object.getOwnPropertyDescriptor(s?.prototype, "adoptedStyleSheets")
      : void 0;
  return r === null || r === -1 || !s || !i
    ? () => {}
    : (Object.defineProperty(n, "adoptedStyleSheets", {
        configurable: i.configurable,
        enumerable: i.enumerable,
        get() {
          return i.get?.call(this);
        },
        set(o) {
          const a = i.set?.call(this, o);
          if (r !== null && r !== -1)
            try {
              t.adoptStyleSheets(o, r);
            } catch {}
          return a;
        },
      }),
      J(() => {
        Object.defineProperty(n, "adoptedStyleSheets", {
          configurable: i.configurable,
          enumerable: i.enumerable,
          get: i.get,
          set: i.set,
        });
      }));
}
function rC(
  {
    styleDeclarationCb: e,
    mirror: t,
    ignoreCSSAttributes: n,
    stylesheetManager: r,
  },
  { win: s },
) {
  const i = s.CSSStyleDeclaration.prototype.setProperty;
  s.CSSStyleDeclaration.prototype.setProperty = new Proxy(i, {
    apply: J((a, c, u) => {
      const [d, l, p] = u;
      if (n.has(d)) return i.apply(c, [d, l, p]);
      const { id: f, styleId: h } = bt(
        c.parentRule?.parentStyleSheet,
        t,
        r.styleMirror,
      );
      return (
        ((f && f !== -1) || (h && h !== -1)) &&
          e({
            id: f,
            styleId: h,
            set: { property: d, value: l, priority: p },
            index: Ks(c.parentRule),
          }),
        a.apply(c, u)
      );
    }),
  });
  const o = s.CSSStyleDeclaration.prototype.removeProperty;
  return (
    (s.CSSStyleDeclaration.prototype.removeProperty = new Proxy(o, {
      apply: J((a, c, u) => {
        const [d] = u;
        if (n.has(d)) return o.apply(c, [d]);
        const { id: l, styleId: p } = bt(
          c.parentRule?.parentStyleSheet,
          t,
          r.styleMirror,
        );
        return (
          ((l && l !== -1) || (p && p !== -1)) &&
            e({
              id: l,
              styleId: p,
              remove: { property: d },
              index: Ks(c.parentRule),
            }),
          a.apply(c, u)
        );
      }),
    })),
    J(() => {
      ((s.CSSStyleDeclaration.prototype.setProperty = i),
        (s.CSSStyleDeclaration.prototype.removeProperty = o));
    })
  );
}
function sC({
  mediaInteractionCb: e,
  blockClass: t,
  blockSelector: n,
  unblockSelector: r,
  mirror: s,
  sampling: i,
  doc: o,
}) {
  const a = J((u) =>
      lr(
        J((d) => {
          const l = Or(d);
          if (!l || Ae(l, t, n, r, !0)) return;
          const { currentTime: p, volume: f, muted: h, playbackRate: m } = l;
          e({
            type: u,
            id: s.getId(l),
            currentTime: p,
            volume: f,
            muted: h,
            playbackRate: m,
          });
        }),
        i.media || 500,
      ),
    ),
    c = [
      Te("play", a(tn.Play), o),
      Te("pause", a(tn.Pause), o),
      Te("seeked", a(tn.Seeked), o),
      Te("volumechange", a(tn.VolumeChange), o),
      Te("ratechange", a(tn.RateChange), o),
    ];
  return J(() => {
    c.forEach((u) => u());
  });
}
function iC({ fontCb: e, doc: t }) {
  const n = t.defaultView;
  if (!n) return () => {};
  const r = [],
    s = new WeakMap(),
    i = n.FontFace;
  n.FontFace = function (c, u, d) {
    const l = new i(c, u, d);
    return (
      s.set(l, {
        family: c,
        buffer: typeof u != "string",
        descriptors: d,
        fontSource:
          typeof u == "string"
            ? u
            : JSON.stringify(Array.from(new Uint8Array(u))),
      }),
      l
    );
  };
  const o = gc(t.fonts, "add", function (a) {
    return function (c) {
      return (
        Ri(
          J(() => {
            const u = s.get(c);
            u && (e(u), s.delete(c));
          }),
          0,
        ),
        a.apply(this, [c])
      );
    };
  });
  return (
    r.push(() => {
      n.FontFace = i;
    }),
    r.push(o),
    J(() => {
      r.forEach((a) => a());
    })
  );
}
function oC(e) {
  const {
    doc: t,
    mirror: n,
    blockClass: r,
    blockSelector: s,
    unblockSelector: i,
    selectionCb: o,
  } = e;
  let a = !0;
  const c = J(() => {
    const u = t.getSelection();
    if (!u || (a && u?.isCollapsed)) return;
    a = u.isCollapsed || !1;
    const d = [],
      l = u.rangeCount || 0;
    for (let p = 0; p < l; p++) {
      const f = u.getRangeAt(p),
        {
          startContainer: h,
          startOffset: m,
          endContainer: g,
          endOffset: _,
        } = f;
      Ae(h, r, s, i, !0) ||
        Ae(g, r, s, i, !0) ||
        d.push({
          start: n.getId(h),
          startOffset: m,
          end: n.getId(g),
          endOffset: _,
        });
    }
    o({ ranges: d });
  });
  return (c(), Te("selectionchange", c));
}
function aC({ doc: e, customElementCb: t }) {
  const n = e.defaultView;
  return !n || !n.customElements
    ? () => {}
    : gc(n.customElements, "define", function (s) {
        return function (i, o, a) {
          try {
            t({ define: { name: i } });
          } catch {}
          return s.apply(this, [i, o, a]);
        };
      });
}
function cC(e, t = {}) {
  const n = e.doc.defaultView;
  if (!n) return () => {};
  let r;
  e.recordDOM && (r = Lh(e, e.doc));
  const s = Jk(e),
    i = Zk(e),
    o = $h(e),
    a = Qk(e, { win: n }),
    c = tC(e),
    u = sC(e);
  let d = () => {},
    l = () => {},
    p = () => {},
    f = () => {};
  e.recordDOM &&
    ((d = nC(e, { win: n })),
    (l = Dh(e, e.doc)),
    (p = rC(e, { win: n })),
    e.collectFonts && (f = iC(e)));
  const h = oC(e),
    m = aC(e),
    g = [];
  for (const _ of e.plugins) g.push(_.observer(_.callback, n, _.options));
  return J(() => {
    (an.forEach((_) => _.reset()),
      r?.disconnect(),
      s(),
      i(),
      o(),
      a(),
      c(),
      u(),
      d(),
      l(),
      p(),
      f(),
      h(),
      m(),
      g.forEach((_) => _()));
  });
}
function Xr(e) {
  return typeof window[e] < "u";
}
function Kr(e) {
  return !!(
    typeof window[e] < "u" &&
    window[e].prototype &&
    "insertRule" in window[e].prototype &&
    "deleteRule" in window[e].prototype
  );
}
class zo {
  constructor(t) {
    ((this.generateIdFn = t),
      (this.iframeIdToRemoteIdMap = new WeakMap()),
      (this.iframeRemoteIdToIdMap = new WeakMap()));
  }
  getId(t, n, r, s) {
    const i = r || this.getIdToRemoteIdMap(t),
      o = s || this.getRemoteIdToIdMap(t);
    let a = i.get(n);
    return (a || ((a = this.generateIdFn()), i.set(n, a), o.set(a, n)), a);
  }
  getIds(t, n) {
    const r = this.getIdToRemoteIdMap(t),
      s = this.getRemoteIdToIdMap(t);
    return n.map((i) => this.getId(t, i, r, s));
  }
  getRemoteId(t, n, r) {
    const s = r || this.getRemoteIdToIdMap(t);
    if (typeof n != "number") return n;
    const i = s.get(n);
    return i || -1;
  }
  getRemoteIds(t, n) {
    const r = this.getRemoteIdToIdMap(t);
    return n.map((s) => this.getRemoteId(t, s, r));
  }
  reset(t) {
    if (!t) {
      ((this.iframeIdToRemoteIdMap = new WeakMap()),
        (this.iframeRemoteIdToIdMap = new WeakMap()));
      return;
    }
    (this.iframeIdToRemoteIdMap.delete(t),
      this.iframeRemoteIdToIdMap.delete(t));
  }
  getIdToRemoteIdMap(t) {
    let n = this.iframeIdToRemoteIdMap.get(t);
    return (n || ((n = new Map()), this.iframeIdToRemoteIdMap.set(t, n)), n);
  }
  getRemoteIdToIdMap(t) {
    let n = this.iframeRemoteIdToIdMap.get(t);
    return (n || ((n = new Map()), this.iframeRemoteIdToIdMap.set(t, n)), n);
  }
}
class uC {
  constructor() {
    ((this.crossOriginIframeMirror = new zo(mc)),
      (this.crossOriginIframeRootIdMap = new WeakMap()));
  }
  addIframe() {}
  addLoadListener() {}
  attachIframe() {}
}
class lC {
  constructor(t) {
    ((this.iframes = new WeakMap()),
      (this.crossOriginIframeMap = new WeakMap()),
      (this.crossOriginIframeMirror = new zo(mc)),
      (this.crossOriginIframeRootIdMap = new WeakMap()),
      (this.mutationCb = t.mutationCb),
      (this.wrappedEmit = t.wrappedEmit),
      (this.stylesheetManager = t.stylesheetManager),
      (this.recordCrossOriginIframes = t.recordCrossOriginIframes),
      (this.crossOriginIframeStyleMirror = new zo(
        this.stylesheetManager.styleMirror.generateId.bind(
          this.stylesheetManager.styleMirror,
        ),
      )),
      (this.mirror = t.mirror),
      this.recordCrossOriginIframes &&
        window.addEventListener("message", this.handleMessage.bind(this)));
  }
  addIframe(t) {
    (this.iframes.set(t, !0),
      t.contentWindow && this.crossOriginIframeMap.set(t.contentWindow, t));
  }
  addLoadListener(t) {
    this.loadListener = t;
  }
  attachIframe(t, n) {
    (this.mutationCb({
      adds: [{ parentId: this.mirror.getId(t), nextId: null, node: n }],
      removes: [],
      texts: [],
      attributes: [],
      isAttachIframe: !0,
    }),
      this.recordCrossOriginIframes &&
        t.contentWindow?.addEventListener(
          "message",
          this.handleMessage.bind(this),
        ),
      this.loadListener?.(t));
    const r = Sc(t);
    r &&
      r.adoptedStyleSheets &&
      r.adoptedStyleSheets.length > 0 &&
      this.stylesheetManager.adoptStyleSheets(
        r.adoptedStyleSheets,
        this.mirror.getId(r),
      );
  }
  handleMessage(t) {
    const n = t;
    if (n.data.type !== "rrweb" || n.origin !== n.data.origin || !t.source)
      return;
    const s = this.crossOriginIframeMap.get(t.source);
    if (!s) return;
    const i = this.transformCrossOriginEvent(s, n.data.event);
    i && this.wrappedEmit(i, n.data.isCheckout);
  }
  transformCrossOriginEvent(t, n) {
    switch (n.type) {
      case z.FullSnapshot: {
        (this.crossOriginIframeMirror.reset(t),
          this.crossOriginIframeStyleMirror.reset(t),
          this.replaceIdOnNode(n.data.node, t));
        const r = n.data.node.id;
        return (
          this.crossOriginIframeRootIdMap.set(t, r),
          this.patchRootIdOnNode(n.data.node, r),
          {
            timestamp: n.timestamp,
            type: z.IncrementalSnapshot,
            data: {
              source: F.Mutation,
              adds: [
                {
                  parentId: this.mirror.getId(t),
                  nextId: null,
                  node: n.data.node,
                },
              ],
              removes: [],
              texts: [],
              attributes: [],
              isAttachIframe: !0,
            },
          }
        );
      }
      case z.Meta:
      case z.Load:
      case z.DomContentLoaded:
        return !1;
      case z.Plugin:
        return n;
      case z.Custom:
        return (
          this.replaceIds(n.data.payload, t, [
            "id",
            "parentId",
            "previousId",
            "nextId",
          ]),
          n
        );
      case z.IncrementalSnapshot:
        switch (n.data.source) {
          case F.Mutation:
            return (
              n.data.adds.forEach((r) => {
                (this.replaceIds(r, t, ["parentId", "nextId", "previousId"]),
                  this.replaceIdOnNode(r.node, t));
                const s = this.crossOriginIframeRootIdMap.get(t);
                s && this.patchRootIdOnNode(r.node, s);
              }),
              n.data.removes.forEach((r) => {
                this.replaceIds(r, t, ["parentId", "id"]);
              }),
              n.data.attributes.forEach((r) => {
                this.replaceIds(r, t, ["id"]);
              }),
              n.data.texts.forEach((r) => {
                this.replaceIds(r, t, ["id"]);
              }),
              n
            );
          case F.Drag:
          case F.TouchMove:
          case F.MouseMove:
            return (
              n.data.positions.forEach((r) => {
                this.replaceIds(r, t, ["id"]);
              }),
              n
            );
          case F.ViewportResize:
            return !1;
          case F.MediaInteraction:
          case F.MouseInteraction:
          case F.Scroll:
          case F.CanvasMutation:
          case F.Input:
            return (this.replaceIds(n.data, t, ["id"]), n);
          case F.StyleSheetRule:
          case F.StyleDeclaration:
            return (
              this.replaceIds(n.data, t, ["id"]),
              this.replaceStyleIds(n.data, t, ["styleId"]),
              n
            );
          case F.Font:
            return n;
          case F.Selection:
            return (
              n.data.ranges.forEach((r) => {
                this.replaceIds(r, t, ["start", "end"]);
              }),
              n
            );
          case F.AdoptedStyleSheet:
            return (
              this.replaceIds(n.data, t, ["id"]),
              this.replaceStyleIds(n.data, t, ["styleIds"]),
              n.data.styles?.forEach((r) => {
                this.replaceStyleIds(r, t, ["styleId"]);
              }),
              n
            );
        }
    }
    return !1;
  }
  replace(t, n, r, s) {
    for (const i of s)
      (!Array.isArray(n[i]) && typeof n[i] != "number") ||
        (Array.isArray(n[i])
          ? (n[i] = t.getIds(r, n[i]))
          : (n[i] = t.getId(r, n[i])));
    return n;
  }
  replaceIds(t, n, r) {
    return this.replace(this.crossOriginIframeMirror, t, n, r);
  }
  replaceStyleIds(t, n, r) {
    return this.replace(this.crossOriginIframeStyleMirror, t, n, r);
  }
  replaceIdOnNode(t, n) {
    (this.replaceIds(t, n, ["id", "rootId"]),
      "childNodes" in t &&
        t.childNodes.forEach((r) => {
          this.replaceIdOnNode(r, n);
        }));
  }
  patchRootIdOnNode(t, n) {
    (t.type !== _e.Document && !t.rootId && (t.rootId = n),
      "childNodes" in t &&
        t.childNodes.forEach((r) => {
          this.patchRootIdOnNode(r, n);
        }));
  }
}
class dC {
  init() {}
  addShadowRoot() {}
  observeAttachShadow() {}
  reset() {}
}
class fC {
  constructor(t) {
    ((this.shadowDoms = new WeakSet()),
      (this.restoreHandlers = []),
      (this.mutationCb = t.mutationCb),
      (this.scrollCb = t.scrollCb),
      (this.bypassOptions = t.bypassOptions),
      (this.mirror = t.mirror),
      this.init());
  }
  init() {
    (this.reset(), this.patchAttachShadow(Element, document));
  }
  addShadowRoot(t, n) {
    if (!Xn(t) || this.shadowDoms.has(t)) return;
    (this.shadowDoms.add(t), this.bypassOptions.canvasManager.addShadowRoot(t));
    const r = Lh(
      {
        ...this.bypassOptions,
        doc: n,
        mutationCb: this.mutationCb,
        mirror: this.mirror,
        shadowDomManager: this,
      },
      t,
    );
    (this.restoreHandlers.push(() => r.disconnect()),
      this.restoreHandlers.push(
        $h({
          ...this.bypassOptions,
          scrollCb: this.scrollCb,
          doc: t,
          mirror: this.mirror,
        }),
      ),
      Ri(() => {
        (t.adoptedStyleSheets &&
          t.adoptedStyleSheets.length > 0 &&
          this.bypassOptions.stylesheetManager.adoptStyleSheets(
            t.adoptedStyleSheets,
            this.mirror.getId(t.host),
          ),
          this.restoreHandlers.push(
            Dh(
              {
                mirror: this.mirror,
                stylesheetManager: this.bypassOptions.stylesheetManager,
              },
              t,
            ),
          ));
      }, 0));
  }
  observeAttachShadow(t) {
    const n = Sc(t),
      r = qk(t);
    !n || !r || this.patchAttachShadow(r.Element, n);
  }
  patchAttachShadow(t, n) {
    const r = this;
    this.restoreHandlers.push(
      gc(t.prototype, "attachShadow", function (s) {
        return function (i) {
          const o = s.call(this, i);
          return (
            this.shadowRoot && Nh(this) && r.addShadowRoot(this.shadowRoot, n),
            o
          );
        };
      }),
    );
  }
  reset() {
    (this.restoreHandlers.forEach((t) => {
      try {
        t();
      } catch {}
    }),
      (this.restoreHandlers = []),
      (this.shadowDoms = new WeakSet()),
      this.bypassOptions.canvasManager.resetShadowRoots());
  }
}
var jl = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",
  pC = typeof Uint8Array > "u" ? [] : new Uint8Array(256);
for (var Jr = 0; Jr < jl.length; Jr++) pC[jl.charCodeAt(Jr)] = Jr;
class ql {
  reset() {}
  freeze() {}
  unfreeze() {}
  lock() {}
  unlock() {}
  snapshot() {}
  addWindow() {}
  addShadowRoot() {}
  resetShadowRoots() {}
}
class hC {
  constructor(t) {
    ((this.trackedLinkElements = new WeakSet()),
      (this.styleMirror = new Uk()),
      (this.mutationCb = t.mutationCb),
      (this.adoptedStyleSheetCb = t.adoptedStyleSheetCb));
  }
  attachLinkElement(t, n) {
    ("_cssText" in n.attributes &&
      this.mutationCb({
        adds: [],
        removes: [],
        texts: [],
        attributes: [{ id: n.id, attributes: n.attributes }],
      }),
      this.trackLinkElement(t));
  }
  trackLinkElement(t) {
    this.trackedLinkElements.has(t) ||
      (this.trackedLinkElements.add(t), this.trackStylesheetInLinkElement(t));
  }
  adoptStyleSheets(t, n) {
    if (t.length === 0) return;
    const r = { id: n, styleIds: [] },
      s = [];
    for (const i of t) {
      let o;
      (this.styleMirror.has(i)
        ? (o = this.styleMirror.getId(i))
        : ((o = this.styleMirror.add(i)),
          s.push({
            styleId: o,
            rules: Array.from(i.rules || CSSRule, (a, c) => ({
              rule: mh(a),
              index: c,
            })),
          })),
        r.styleIds.push(o));
    }
    (s.length > 0 && (r.styles = s), this.adoptedStyleSheetCb(r));
  }
  reset() {
    (this.styleMirror.reset(), (this.trackedLinkElements = new WeakSet()));
  }
  trackStylesheetInLinkElement(t) {}
}
class mC {
  constructor() {
    ((this.nodeMap = new WeakMap()), (this.active = !1));
  }
  inOtherBuffer(t, n) {
    const r = this.nodeMap.get(t);
    return r && Array.from(r).some((s) => s !== n);
  }
  add(t, n) {
    (this.active ||
      ((this.active = !0),
      zk(() => {
        ((this.nodeMap = new WeakMap()), (this.active = !1));
      })),
      this.nodeMap.set(t, (this.nodeMap.get(t) || new Set()).add(n)));
  }
  destroy() {}
}
let pe, Js;
try {
  if (Array.from([1], (e) => e * 2)[0] !== 2) {
    const e = document.createElement("iframe");
    (document.body.appendChild(e),
      (Array.from = e.contentWindow?.Array.from || Array.from),
      document.body.removeChild(e));
  }
} catch (e) {
  console.debug("Unable to override Array.from", e);
}
const Ue = hk();
function ut(e = {}) {
  const {
    emit: t,
    checkoutEveryNms: n,
    checkoutEveryNth: r,
    blockClass: s = "rr-block",
    blockSelector: i = null,
    unblockSelector: o = null,
    ignoreClass: a = "rr-ignore",
    ignoreSelector: c = null,
    maskAllText: u = !1,
    maskTextClass: d = "rr-mask",
    unmaskTextClass: l = null,
    maskTextSelector: p = null,
    unmaskTextSelector: f = null,
    inlineStylesheet: h = !0,
    maskAllInputs: m,
    maskInputOptions: g,
    slimDOMOptions: _,
    maskAttributeFn: y,
    maskInputFn: M,
    maskTextFn: w,
    maxCanvasSize: A = null,
    packFn: C,
    sampling: E = {},
    dataURLOptions: I = {},
    mousemoveWait: b,
    recordDOM: k = !0,
    recordCanvas: O = !1,
    recordCrossOriginIframes: v = !1,
    recordAfter: x = e.recordAfter === "DOMContentLoaded"
      ? e.recordAfter
      : "load",
    userTriggeredOnInput: U = !1,
    collectFonts: q = !1,
    inlineImages: K = !1,
    plugins: T,
    keepIframeSrcFn: P = () => !1,
    ignoreCSSAttributes: R = new Set([]),
    errorHandler: L,
    onMutation: V,
    getCanvasManager: Q,
  } = e;
  Xk(L);
  const ge = v ? window.parent === window : !0;
  let le = !1;
  if (!ge)
    try {
      window.parent.document && (le = !1);
    } catch {
      le = !0;
    }
  if (ge && !t) throw new Error("emit function is required");
  if (!ge && !le) return () => {};
  (b !== void 0 && E.mousemove === void 0 && (E.mousemove = b), Ue.reset());
  const gt =
      m === !0
        ? {
            color: !0,
            date: !0,
            "datetime-local": !0,
            email: !0,
            month: !0,
            number: !0,
            range: !0,
            search: !0,
            tel: !0,
            text: !0,
            time: !0,
            url: !0,
            week: !0,
            textarea: !0,
            select: !0,
            radio: !0,
            checkbox: !0,
          }
        : g !== void 0
          ? g
          : {},
    Be =
      _ === !0 || _ === "all"
        ? {
            script: !0,
            comment: !0,
            headFavicon: !0,
            headWhitespace: !0,
            headMetaSocial: !0,
            headMetaRobots: !0,
            headMetaHttpEquiv: !0,
            headMetaVerification: !0,
            headMetaAuthorship: _ === "all",
            headMetaDescKeywords: _ === "all",
          }
        : _ || {};
  Bk();
  let Le,
    Re = 0;
  const _t = (Y) => {
    for (const xe of T || []) xe.eventProcessor && (Y = xe.eventProcessor(Y));
    return (C && !le && (Y = C(Y)), Y);
  };
  pe = (Y, xe) => {
    const X = Y;
    if (
      ((X.timestamp = Xs()),
      an[0]?.isFrozen() &&
        X.type !== z.FullSnapshot &&
        !(X.type === z.IncrementalSnapshot && X.data.source === F.Mutation) &&
        an.forEach((ye) => ye.unfreeze()),
      ge)
    )
      t?.(_t(X), xe);
    else if (le) {
      const ye = {
        type: "rrweb",
        event: _t(X),
        origin: window.location.origin,
        isCheckout: xe,
      };
      window.parent.postMessage(ye, "*");
    }
    if (X.type === z.FullSnapshot) ((Le = X), (Re = 0));
    else if (X.type === z.IncrementalSnapshot) {
      if (X.data.source === F.Mutation && X.data.isAttachIframe) return;
      Re++;
      const ye = r && Re >= r,
        Z = n && Le && X.timestamp - Le.timestamp > n;
      (ye || Z) && Ve(!0);
    }
  };
  const St = (Y) => {
      pe({ type: z.IncrementalSnapshot, data: { source: F.Mutation, ...Y } });
    },
    Nn = (Y) =>
      pe({ type: z.IncrementalSnapshot, data: { source: F.Scroll, ...Y } }),
    $r = (Y) =>
      pe({
        type: z.IncrementalSnapshot,
        data: { source: F.CanvasMutation, ...Y },
      }),
    On = (Y) =>
      pe({
        type: z.IncrementalSnapshot,
        data: { source: F.AdoptedStyleSheet, ...Y },
      }),
    te = new hC({ mutationCb: St, adoptedStyleSheetCb: On }),
    de =
      typeof __RRWEB_EXCLUDE_IFRAME__ == "boolean" && __RRWEB_EXCLUDE_IFRAME__
        ? new uC()
        : new lC({
            mirror: Ue,
            mutationCb: St,
            stylesheetManager: te,
            recordCrossOriginIframes: v,
            wrappedEmit: pe,
          });
  for (const Y of T || [])
    Y.getMirror &&
      Y.getMirror({
        nodeMirror: Ue,
        crossOriginIframeMirror: de.crossOriginIframeMirror,
        crossOriginIframeStyleMirror: de.crossOriginIframeStyleMirror,
      });
  const $e = new mC(),
    Se = _C(Q, {
      mirror: Ue,
      win: window,
      mutationCb: (Y) =>
        pe({
          type: z.IncrementalSnapshot,
          data: { source: F.CanvasMutation, ...Y },
        }),
      recordCanvas: O,
      blockClass: s,
      blockSelector: i,
      unblockSelector: o,
      maxCanvasSize: A,
      sampling: E.canvas,
      dataURLOptions: I,
      errorHandler: L,
    }),
    Ee =
      typeof __RRWEB_EXCLUDE_SHADOW_DOM__ == "boolean" &&
      __RRWEB_EXCLUDE_SHADOW_DOM__
        ? new dC()
        : new fC({
            mutationCb: St,
            scrollCb: Nn,
            bypassOptions: {
              onMutation: V,
              blockClass: s,
              blockSelector: i,
              unblockSelector: o,
              maskAllText: u,
              maskTextClass: d,
              unmaskTextClass: l,
              maskTextSelector: p,
              unmaskTextSelector: f,
              inlineStylesheet: h,
              maskInputOptions: gt,
              dataURLOptions: I,
              maskAttributeFn: y,
              maskTextFn: w,
              maskInputFn: M,
              recordCanvas: O,
              inlineImages: K,
              sampling: E,
              slimDOMOptions: Be,
              iframeManager: de,
              stylesheetManager: te,
              canvasManager: Se,
              keepIframeSrcFn: P,
              processedNodeManager: $e,
            },
            mirror: Ue,
          }),
    Ve = (Y = !1) => {
      if (!k) return;
      (pe(
        {
          type: z.Meta,
          data: { href: window.location.href, width: kh(), height: Ih() },
        },
        Y,
      ),
        te.reset(),
        Ee.init(),
        an.forEach((X) => X.lock()));
      const xe = Pk(document, {
        mirror: Ue,
        blockClass: s,
        blockSelector: i,
        unblockSelector: o,
        maskAllText: u,
        maskTextClass: d,
        unmaskTextClass: l,
        maskTextSelector: p,
        unmaskTextSelector: f,
        inlineStylesheet: h,
        maskAllInputs: gt,
        maskAttributeFn: y,
        maskInputFn: M,
        maskTextFn: w,
        slimDOM: Be,
        dataURLOptions: I,
        recordCanvas: O,
        inlineImages: K,
        onSerialize: (X) => {
          (xh(X, Ue) && de.addIframe(X),
            Ah(X, Ue) && te.trackLinkElement(X),
            Ho(X) && Ee.addShadowRoot(X.shadowRoot, document));
        },
        onIframeLoad: (X, ye) => {
          (de.attachIframe(X, ye),
            X.contentWindow && Se.addWindow(X.contentWindow),
            Ee.observeAttachShadow(X));
        },
        onStylesheetLoad: (X, ye) => {
          te.attachLinkElement(X, ye);
        },
        onBlockedImageLoad: (X, ye, { width: Z, height: Ln }) => {
          St({
            adds: [],
            removes: [],
            texts: [],
            attributes: [
              {
                id: ye.id,
                attributes: { style: { width: `${Z}px`, height: `${Ln}px` } },
              },
            ],
          });
        },
        keepIframeSrcFn: P,
      });
      if (!xe) return console.warn("Failed to snapshot the document");
      (pe({
        type: z.FullSnapshot,
        data: { node: xe, initialOffset: wh(window) },
      }),
        an.forEach((X) => X.unlock()),
        document.adoptedStyleSheets &&
          document.adoptedStyleSheets.length > 0 &&
          te.adoptStyleSheets(document.adoptedStyleSheets, Ue.getId(document)));
    };
  Js = Ve;
  try {
    const Y = [],
      xe = (ye) =>
        J(cC)(
          {
            onMutation: V,
            mutationCb: St,
            mousemoveCb: (Z, Ln) =>
              pe({
                type: z.IncrementalSnapshot,
                data: { source: Ln, positions: Z },
              }),
            mouseInteractionCb: (Z) =>
              pe({
                type: z.IncrementalSnapshot,
                data: { source: F.MouseInteraction, ...Z },
              }),
            scrollCb: Nn,
            viewportResizeCb: (Z) =>
              pe({
                type: z.IncrementalSnapshot,
                data: { source: F.ViewportResize, ...Z },
              }),
            inputCb: (Z) =>
              pe({
                type: z.IncrementalSnapshot,
                data: { source: F.Input, ...Z },
              }),
            mediaInteractionCb: (Z) =>
              pe({
                type: z.IncrementalSnapshot,
                data: { source: F.MediaInteraction, ...Z },
              }),
            styleSheetRuleCb: (Z) =>
              pe({
                type: z.IncrementalSnapshot,
                data: { source: F.StyleSheetRule, ...Z },
              }),
            styleDeclarationCb: (Z) =>
              pe({
                type: z.IncrementalSnapshot,
                data: { source: F.StyleDeclaration, ...Z },
              }),
            canvasMutationCb: $r,
            fontCb: (Z) =>
              pe({
                type: z.IncrementalSnapshot,
                data: { source: F.Font, ...Z },
              }),
            selectionCb: (Z) => {
              pe({
                type: z.IncrementalSnapshot,
                data: { source: F.Selection, ...Z },
              });
            },
            customElementCb: (Z) => {
              pe({
                type: z.IncrementalSnapshot,
                data: { source: F.CustomElement, ...Z },
              });
            },
            blockClass: s,
            ignoreClass: a,
            ignoreSelector: c,
            maskAllText: u,
            maskTextClass: d,
            unmaskTextClass: l,
            maskTextSelector: p,
            unmaskTextSelector: f,
            maskInputOptions: gt,
            inlineStylesheet: h,
            sampling: E,
            recordDOM: k,
            recordCanvas: O,
            inlineImages: K,
            userTriggeredOnInput: U,
            collectFonts: q,
            doc: ye,
            maskAttributeFn: y,
            maskInputFn: M,
            maskTextFn: w,
            keepIframeSrcFn: P,
            blockSelector: i,
            unblockSelector: o,
            slimDOMOptions: Be,
            dataURLOptions: I,
            mirror: Ue,
            iframeManager: de,
            stylesheetManager: te,
            shadowDomManager: Ee,
            processedNodeManager: $e,
            canvasManager: Se,
            ignoreCSSAttributes: R,
            plugins:
              T?.filter((Z) => Z.observer)?.map((Z) => ({
                observer: Z.observer,
                options: Z.options,
                callback: (Ln) =>
                  pe({ type: z.Plugin, data: { plugin: Z.name, payload: Ln } }),
              })) || [],
          },
          {},
        );
    de.addLoadListener((ye) => {
      try {
        Y.push(xe(ye.contentDocument));
      } catch (Z) {
        console.warn(Z);
      }
    });
    const X = () => {
      (Ve(), Y.push(xe(document)));
    };
    return (
      document.readyState === "interactive" ||
      document.readyState === "complete"
        ? X()
        : (Y.push(
            Te("DOMContentLoaded", () => {
              (pe({ type: z.DomContentLoaded, data: {} }),
                x === "DOMContentLoaded" && X());
            }),
          ),
          Y.push(
            Te(
              "load",
              () => {
                (pe({ type: z.Load, data: {} }), x === "load" && X());
              },
              window,
            ),
          )),
      () => {
        (Y.forEach((ye) => ye()), $e.destroy(), (Js = void 0), Kk());
      }
    );
  } catch (Y) {
    console.warn(Y);
  }
}
function gC(e) {
  if (!Js) throw new Error("please take full snapshot after start recording");
  Js(e);
}
ut.mirror = Ue;
ut.takeFullSnapshot = gC;
function _C(e, t) {
  try {
    return e ? e(t) : new ql();
  } catch {
    return (console.warn("Unable to initialize CanvasManager"), new ql());
  }
}
var Gl;
(function (e) {
  ((e[(e.NotStarted = 0)] = "NotStarted"),
    (e[(e.Running = 1)] = "Running"),
    (e[(e.Stopped = 2)] = "Stopped"));
})(Gl || (Gl = {}));
const SC = 3,
  yC = 5;
function yc(e) {
  return e > 9999999999 ? e : e * 1e3;
}
function ro(e) {
  return e > 9999999999 ? e / 1e3 : e;
}
function Lr(e, t) {
  t.category !== "sentry.transaction" &&
    (["ui.click", "ui.input"].includes(t.category)
      ? e.triggerUserActivity()
      : e.checkAndHandleExpiredSession(),
    e.addUpdate(
      () => (
        e.throttledAddEvent({
          type: z.Custom,
          timestamp: (t.timestamp || 0) * 1e3,
          data: { tag: "breadcrumb", payload: nt(t, 10, 1e3) },
        }),
        t.category === "console"
      ),
    ));
}
const bC = "button,a";
function Ph(e) {
  return e.closest(bC) || e;
}
function Fh(e) {
  const t = Bh(e);
  return !t || !(t instanceof Element) ? t : Ph(t);
}
function Bh(e) {
  return EC(e) ? e.target : e;
}
function EC(e) {
  return typeof e == "object" && !!e && "target" in e;
}
let Et;
function vC(e) {
  return (
    Et || ((Et = []), TC()),
    Et.push(e),
    () => {
      const t = Et ? Et.indexOf(e) : -1;
      t > -1 && Et.splice(t, 1);
    }
  );
}
function TC() {
  aI(ae, "open", function (e) {
    return function (...t) {
      if (Et)
        try {
          Et.forEach((n) => n());
        } catch {}
      return e.apply(ae, t);
    };
  });
}
const wC = new Set([
  F.Mutation,
  F.StyleSheetRule,
  F.StyleDeclaration,
  F.AdoptedStyleSheet,
  F.CanvasMutation,
  F.Selection,
  F.MediaInteraction,
]);
function IC(e, t, n) {
  e.handleClick(t, n);
}
class kC {
  constructor(t, n, r = Lr) {
    ((this._lastMutation = 0),
      (this._lastScroll = 0),
      (this._clicks = []),
      (this._timeout = n.timeout / 1e3),
      (this._threshold = n.threshold / 1e3),
      (this._scrollTimeout = n.scrollTimeout / 1e3),
      (this._replay = t),
      (this._ignoreSelector = n.ignoreSelector),
      (this._addBreadcrumbEvent = r));
  }
  addListeners() {
    const t = vC(() => {
      this._lastMutation = Vl();
    });
    this._teardown = () => {
      (t(),
        (this._clicks = []),
        (this._lastMutation = 0),
        (this._lastScroll = 0));
    };
  }
  removeListeners() {
    (this._teardown && this._teardown(),
      this._checkClickTimeout && clearTimeout(this._checkClickTimeout));
  }
  handleClick(t, n) {
    if (RC(n, this._ignoreSelector) || !xC(t)) return;
    const r = {
      timestamp: ro(t.timestamp),
      clickBreadcrumb: t,
      clickCount: 0,
      node: n,
    };
    this._clicks.some(
      (s) => s.node === r.node && Math.abs(s.timestamp - r.timestamp) < 1,
    ) ||
      (this._clicks.push(r),
      this._clicks.length === 1 && this._scheduleCheckClicks());
  }
  registerMutation(t = Date.now()) {
    this._lastMutation = ro(t);
  }
  registerScroll(t = Date.now()) {
    this._lastScroll = ro(t);
  }
  registerClick(t) {
    const n = Ph(t);
    this._handleMultiClick(n);
  }
  _handleMultiClick(t) {
    this._getClicks(t).forEach((n) => {
      n.clickCount++;
    });
  }
  _getClicks(t) {
    return this._clicks.filter((n) => n.node === t);
  }
  _checkClicks() {
    const t = [],
      n = Vl();
    this._clicks.forEach((r) => {
      (!r.mutationAfter &&
        this._lastMutation &&
        (r.mutationAfter =
          r.timestamp <= this._lastMutation
            ? this._lastMutation - r.timestamp
            : void 0),
        !r.scrollAfter &&
          this._lastScroll &&
          (r.scrollAfter =
            r.timestamp <= this._lastScroll
              ? this._lastScroll - r.timestamp
              : void 0),
        r.timestamp + this._timeout <= n && t.push(r));
    });
    for (const r of t) {
      const s = this._clicks.indexOf(r);
      s > -1 && (this._generateBreadcrumbs(r), this._clicks.splice(s, 1));
    }
    this._clicks.length && this._scheduleCheckClicks();
  }
  _generateBreadcrumbs(t) {
    const n = this._replay,
      r = t.scrollAfter && t.scrollAfter <= this._scrollTimeout,
      s = t.mutationAfter && t.mutationAfter <= this._threshold,
      i = !r && !s,
      { clickCount: o, clickBreadcrumb: a } = t;
    if (i) {
      const c = Math.min(t.mutationAfter || this._timeout, this._timeout) * 1e3,
        u = c < this._timeout * 1e3 ? "mutation" : "timeout",
        d = {
          type: "default",
          message: a.message,
          timestamp: a.timestamp,
          category: "ui.slowClickDetected",
          data: {
            ...a.data,
            url: ae.location.href,
            route: n.getCurrentRoute(),
            timeAfterClickMs: c,
            endReason: u,
            clickCount: o || 1,
          },
        };
      this._addBreadcrumbEvent(n, d);
      return;
    }
    if (o > 1) {
      const c = {
        type: "default",
        message: a.message,
        timestamp: a.timestamp,
        category: "ui.multiClick",
        data: {
          ...a.data,
          url: ae.location.href,
          route: n.getCurrentRoute(),
          clickCount: o,
          metric: !0,
        },
      };
      this._addBreadcrumbEvent(n, c);
    }
  }
  _scheduleCheckClicks() {
    (this._checkClickTimeout && clearTimeout(this._checkClickTimeout),
      (this._checkClickTimeout = Mr(() => this._checkClicks(), 1e3)));
  }
}
const CC = ["A", "BUTTON", "INPUT"];
function RC(e, t) {
  return !!(
    !CC.includes(e.tagName) ||
    (e.tagName === "INPUT" &&
      !["submit", "button"].includes(e.getAttribute("type") || "")) ||
    (e.tagName === "A" &&
      (e.hasAttribute("download") ||
        (e.hasAttribute("target") && e.getAttribute("target") !== "_self"))) ||
    (t && e.matches(t))
  );
}
function xC(e) {
  return !!(e.data && typeof e.data.nodeId == "number" && e.timestamp);
}
function Vl() {
  return Date.now() / 1e3;
}
function AC(e, t) {
  try {
    if (!MC(t)) return;
    const { source: n } = t.data;
    if (
      (wC.has(n) && e.registerMutation(t.timestamp),
      n === F.Scroll && e.registerScroll(t.timestamp),
      NC(t))
    ) {
      const { type: r, id: s } = t.data,
        i = ut.mirror.getNode(s);
      i instanceof HTMLElement && r === ve.Click && e.registerClick(i);
    }
  } catch {}
}
function MC(e) {
  return e.type === SC;
}
function NC(e) {
  return e.data.source === F.MouseInteraction;
}
function Ke(e) {
  return { timestamp: Date.now() / 1e3, type: "default", ...e };
}
var bc = ((e) => (
  (e[(e.Document = 0)] = "Document"),
  (e[(e.DocumentType = 1)] = "DocumentType"),
  (e[(e.Element = 2)] = "Element"),
  (e[(e.Text = 3)] = "Text"),
  (e[(e.CDATA = 4)] = "CDATA"),
  (e[(e.Comment = 5)] = "Comment"),
  e
))(bc || {});
const OC = new Set([
  "id",
  "class",
  "aria-label",
  "role",
  "name",
  "alt",
  "title",
  "data-test-id",
  "data-testid",
  "disabled",
  "aria-disabled",
  "data-sentry-component",
]);
function LC(e) {
  const t = {};
  !e["data-sentry-component"] &&
    e["data-sentry-element"] &&
    (e["data-sentry-component"] = e["data-sentry-element"]);
  for (const n in e)
    if (OC.has(n)) {
      let r = n;
      ((n === "data-testid" || n === "data-test-id") && (r = "testId"),
        (t[r] = e[n]));
    }
  return t;
}
const $C = (e) => (t) => {
  if (!e.isEnabled()) return;
  const n = DC(t);
  if (!n) return;
  const r = t.name === "click",
    s = r ? t.event : void 0;
  (r &&
    e.clickDetector &&
    s?.target &&
    !s.altKey &&
    !s.metaKey &&
    !s.ctrlKey &&
    !s.shiftKey &&
    IC(e.clickDetector, n, Fh(t.event)),
    Lr(e, n));
};
function Uh(e, t) {
  const n = ut.mirror.getId(e),
    r = n && ut.mirror.getNode(n),
    s = r && ut.mirror.getMeta(r),
    i = s && FC(s) ? s : null;
  return {
    message: t,
    data: i
      ? {
          nodeId: n,
          node: {
            id: n,
            tagName: i.tagName,
            textContent: Array.from(i.childNodes)
              .map((o) => o.type === bc.Text && o.textContent)
              .filter(Boolean)
              .map((o) => o.trim())
              .join(""),
            attributes: LC(i.attributes),
          },
        }
      : {},
  };
}
function DC(e) {
  const { target: t, message: n } = PC(e);
  return Ke({ category: `ui.${e.name}`, ...Uh(t, n) });
}
function PC(e) {
  const t = e.name === "click";
  let n,
    r = null;
  try {
    ((r = t ? Fh(e.event) : Bh(e.event)),
      (n = cc(r, { maxStringLength: 200 }) || "<unknown>"));
  } catch {
    n = "<unknown>";
  }
  return { target: r, message: n };
}
function FC(e) {
  return e.type === bc.Element;
}
function BC(e, t) {
  if (!e.isEnabled()) return;
  e.updateUserActivity();
  const n = UC(t);
  n && Lr(e, n);
}
function UC(e) {
  const {
    metaKey: t,
    shiftKey: n,
    ctrlKey: r,
    altKey: s,
    key: i,
    target: o,
  } = e;
  if (!o || HC(o) || !i) return null;
  const a = t || r || s,
    c = i.length === 1;
  if (!a && c) return null;
  const u = cc(o, { maxStringLength: 200 }) || "<unknown>",
    d = Uh(o, u);
  return Ke({
    category: "ui.keyDown",
    message: u,
    data: { ...d.data, metaKey: t, shiftKey: n, ctrlKey: r, altKey: s, key: i },
  });
}
function HC(e) {
  return (
    e.tagName === "INPUT" || e.tagName === "TEXTAREA" || e.isContentEditable
  );
}
const WC = { resource: VC, paint: qC, navigation: GC };
function so(e, t) {
  return ({ metric: n }) => {
    t.replayPerformanceEntries.push(e(n));
  };
}
function zC(e) {
  return e.map(jC).filter(Boolean);
}
function jC(e) {
  const t = WC[e.entryType];
  return t ? t(e) : null;
}
function Tn(e) {
  return ((mI() || ae.performance.timeOrigin) + e) / 1e3;
}
function qC(e) {
  const { duration: t, entryType: n, name: r, startTime: s } = e,
    i = Tn(s);
  return { type: n, name: r, start: i, end: i + t, data: void 0 };
}
function GC(e) {
  const {
    entryType: t,
    name: n,
    decodedBodySize: r,
    duration: s,
    domComplete: i,
    encodedBodySize: o,
    domContentLoadedEventStart: a,
    domContentLoadedEventEnd: c,
    domInteractive: u,
    loadEventStart: d,
    loadEventEnd: l,
    redirectCount: p,
    startTime: f,
    transferSize: h,
    type: m,
  } = e;
  return s === 0
    ? null
    : {
        type: `${t}.${m}`,
        start: Tn(f),
        end: Tn(i),
        name: n,
        data: {
          size: h,
          decodedBodySize: r,
          encodedBodySize: o,
          duration: s,
          domInteractive: u,
          domContentLoadedEventStart: a,
          domContentLoadedEventEnd: c,
          loadEventStart: d,
          loadEventEnd: l,
          domComplete: i,
          redirectCount: p,
        },
      };
}
function VC(e) {
  const {
    entryType: t,
    initiatorType: n,
    name: r,
    responseEnd: s,
    startTime: i,
    decodedBodySize: o,
    encodedBodySize: a,
    responseStatus: c,
    transferSize: u,
  } = e;
  return ["fetch", "xmlhttprequest"].includes(n)
    ? null
    : {
        type: `${t}.${n}`,
        start: Tn(i),
        end: Tn(s),
        name: r,
        data: {
          size: u,
          statusCode: c,
          decodedBodySize: o,
          encodedBodySize: a,
        },
      };
}
function YC(e) {
  const t = e.entries[e.entries.length - 1],
    n = t?.element ? [t.element] : void 0;
  return Ec(e, "largest-contentful-paint", n);
}
function XC(e) {
  return e.sources !== void 0;
}
function KC(e) {
  const t = [],
    n = [];
  for (const r of e.entries)
    if (XC(r)) {
      const s = [];
      for (const i of r.sources)
        if (i.node) {
          n.push(i.node);
          const o = ut.mirror.getId(i.node);
          o && s.push(o);
        }
      t.push({ value: r.value, nodeIds: s.length ? s : void 0 });
    }
  return Ec(e, "cumulative-layout-shift", n, t);
}
function JC(e) {
  const t = e.entries[e.entries.length - 1],
    n = t?.target ? [t.target] : void 0;
  return Ec(e, "interaction-to-next-paint", n);
}
function Ec(e, t, n, r) {
  const s = e.value,
    i = e.rating,
    o = Tn(s);
  return {
    type: "web-vital",
    name: t,
    start: o,
    end: o,
    data: {
      value: s,
      size: s,
      rating: i,
      nodeIds: n ? n.map((a) => ut.mirror.getId(a)) : void 0,
      attributions: r,
    },
  };
}
function ZC(e) {
  function t(s) {
    e.performanceEntries.includes(s) || e.performanceEntries.push(s);
  }
  function n({ entries: s }) {
    s.forEach(t);
  }
  const r = [];
  return (
    ["navigation", "paint", "resource"].forEach((s) => {
      r.push(Xt(s, n));
    }),
    r.push(Ka(so(YC, e)), Xa(so(KC, e)), Cp(so(JC, e))),
    () => {
      r.forEach((s) => s());
    }
  );
}
const $ = typeof __SENTRY_DEBUG__ > "u" || __SENTRY_DEBUG__,
  QC =
    'var t=Uint8Array,n=Uint16Array,r=Int32Array,e=new t([0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0,0,0,0]),i=new t([0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13,0,0]),s=new t([16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15]),a=function(t,e){for(var i=new n(31),s=0;s<31;++s)i[s]=e+=1<<t[s-1];var a=new r(i[30]);for(s=1;s<30;++s)for(var o=i[s];o<i[s+1];++o)a[o]=o-i[s]<<5|s;return{b:i,r:a}},o=a(e,2),h=o.b,f=o.r;h[28]=258,f[258]=28;for(var l=a(i,0).r,u=new n(32768),c=0;c<32768;++c){var v=(43690&c)>>1|(21845&c)<<1;v=(61680&(v=(52428&v)>>2|(13107&v)<<2))>>4|(3855&v)<<4,u[c]=((65280&v)>>8|(255&v)<<8)>>1}var d=function(t,r,e){for(var i=t.length,s=0,a=new n(r);s<i;++s)t[s]&&++a[t[s]-1];var o,h=new n(r);for(s=1;s<r;++s)h[s]=h[s-1]+a[s-1]<<1;if(e){o=new n(1<<r);var f=15-r;for(s=0;s<i;++s)if(t[s])for(var l=s<<4|t[s],c=r-t[s],v=h[t[s]-1]++<<c,d=v|(1<<c)-1;v<=d;++v)o[u[v]>>f]=l}else for(o=new n(i),s=0;s<i;++s)t[s]&&(o[s]=u[h[t[s]-1]++]>>15-t[s]);return o},p=new t(288);for(c=0;c<144;++c)p[c]=8;for(c=144;c<256;++c)p[c]=9;for(c=256;c<280;++c)p[c]=7;for(c=280;c<288;++c)p[c]=8;var g=new t(32);for(c=0;c<32;++c)g[c]=5;var w=d(p,9,0),y=d(g,5,0),m=function(t){return(t+7)/8|0},b=function(n,r,e){return(null==e||e>n.length)&&(e=n.length),new t(n.subarray(r,e))},M=["unexpected EOF","invalid block type","invalid length/literal","invalid distance","stream finished","no stream handler",,"no callback","invalid UTF-8 data","extra field too long","date not in range 1980-2099","filename too long","stream finishing","invalid zip data"],E=function(t,n,r){var e=new Error(n||M[t]);if(e.code=t,Error.captureStackTrace&&Error.captureStackTrace(e,E),!r)throw e;return e},z=function(t,n,r){r<<=7&n;var e=n/8|0;t[e]|=r,t[e+1]|=r>>8},_=function(t,n,r){r<<=7&n;var e=n/8|0;t[e]|=r,t[e+1]|=r>>8,t[e+2]|=r>>16},x=function(r,e){for(var i=[],s=0;s<r.length;++s)r[s]&&i.push({s:s,f:r[s]});var a=i.length,o=i.slice();if(!a)return{t:F,l:0};if(1==a){var h=new t(i[0].s+1);return h[i[0].s]=1,{t:h,l:1}}i.sort(function(t,n){return t.f-n.f}),i.push({s:-1,f:25001});var f=i[0],l=i[1],u=0,c=1,v=2;for(i[0]={s:-1,f:f.f+l.f,l:f,r:l};c!=a-1;)f=i[i[u].f<i[v].f?u++:v++],l=i[u!=c&&i[u].f<i[v].f?u++:v++],i[c++]={s:-1,f:f.f+l.f,l:f,r:l};var d=o[0].s;for(s=1;s<a;++s)o[s].s>d&&(d=o[s].s);var p=new n(d+1),g=A(i[c-1],p,0);if(g>e){s=0;var w=0,y=g-e,m=1<<y;for(o.sort(function(t,n){return p[n.s]-p[t.s]||t.f-n.f});s<a;++s){var b=o[s].s;if(!(p[b]>e))break;w+=m-(1<<g-p[b]),p[b]=e}for(w>>=y;w>0;){var M=o[s].s;p[M]<e?w-=1<<e-p[M]++-1:++s}for(;s>=0&&w;--s){var E=o[s].s;p[E]==e&&(--p[E],++w)}g=e}return{t:new t(p),l:g}},A=function(t,n,r){return-1==t.s?Math.max(A(t.l,n,r+1),A(t.r,n,r+1)):n[t.s]=r},D=function(t){for(var r=t.length;r&&!t[--r];);for(var e=new n(++r),i=0,s=t[0],a=1,o=function(t){e[i++]=t},h=1;h<=r;++h)if(t[h]==s&&h!=r)++a;else{if(!s&&a>2){for(;a>138;a-=138)o(32754);a>2&&(o(a>10?a-11<<5|28690:a-3<<5|12305),a=0)}else if(a>3){for(o(s),--a;a>6;a-=6)o(8304);a>2&&(o(a-3<<5|8208),a=0)}for(;a--;)o(s);a=1,s=t[h]}return{c:e.subarray(0,i),n:r}},T=function(t,n){for(var r=0,e=0;e<n.length;++e)r+=t[e]*n[e];return r},k=function(t,n,r){var e=r.length,i=m(n+2);t[i]=255&e,t[i+1]=e>>8,t[i+2]=255^t[i],t[i+3]=255^t[i+1];for(var s=0;s<e;++s)t[i+s+4]=r[s];return 8*(i+4+e)},U=function(t,r,a,o,h,f,l,u,c,v,m){z(r,m++,a),++h[256];for(var b=x(h,15),M=b.t,E=b.l,A=x(f,15),U=A.t,C=A.l,F=D(M),I=F.c,S=F.n,L=D(U),O=L.c,j=L.n,q=new n(19),B=0;B<I.length;++B)++q[31&I[B]];for(B=0;B<O.length;++B)++q[31&O[B]];for(var G=x(q,7),H=G.t,J=G.l,K=19;K>4&&!H[s[K-1]];--K);var N,P,Q,R,V=v+5<<3,W=T(h,p)+T(f,g)+l,X=T(h,M)+T(f,U)+l+14+3*K+T(q,H)+2*q[16]+3*q[17]+7*q[18];if(c>=0&&V<=W&&V<=X)return k(r,m,t.subarray(c,c+v));if(z(r,m,1+(X<W)),m+=2,X<W){N=d(M,E,0),P=M,Q=d(U,C,0),R=U;var Y=d(H,J,0);z(r,m,S-257),z(r,m+5,j-1),z(r,m+10,K-4),m+=14;for(B=0;B<K;++B)z(r,m+3*B,H[s[B]]);m+=3*K;for(var Z=[I,O],$=0;$<2;++$){var tt=Z[$];for(B=0;B<tt.length;++B){var nt=31&tt[B];z(r,m,Y[nt]),m+=H[nt],nt>15&&(z(r,m,tt[B]>>5&127),m+=tt[B]>>12)}}}else N=w,P=p,Q=y,R=g;for(B=0;B<u;++B){var rt=o[B];if(rt>255){_(r,m,N[(nt=rt>>18&31)+257]),m+=P[nt+257],nt>7&&(z(r,m,rt>>23&31),m+=e[nt]);var et=31&rt;_(r,m,Q[et]),m+=R[et],et>3&&(_(r,m,rt>>5&8191),m+=i[et])}else _(r,m,N[rt]),m+=P[rt]}return _(r,m,N[256]),m+P[256]},C=new r([65540,131080,131088,131104,262176,1048704,1048832,2114560,2117632]),F=new t(0),I=function(){for(var t=new Int32Array(256),n=0;n<256;++n){for(var r=n,e=9;--e;)r=(1&r&&-306674912)^r>>>1;t[n]=r}return t}(),S=function(){var t=1,n=0;return{p:function(r){for(var e=t,i=n,s=0|r.length,a=0;a!=s;){for(var o=Math.min(a+2655,s);a<o;++a)i+=e+=r[a];e=(65535&e)+15*(e>>16),i=(65535&i)+15*(i>>16)}t=e,n=i},d:function(){return(255&(t%=65521))<<24|(65280&t)<<8|(255&(n%=65521))<<8|n>>8}}},L=function(s,a,o,h,u){if(!u&&(u={l:1},a.dictionary)){var c=a.dictionary.subarray(-32768),v=new t(c.length+s.length);v.set(c),v.set(s,c.length),s=v,u.w=c.length}return function(s,a,o,h,u,c){var v=c.z||s.length,d=new t(h+v+5*(1+Math.ceil(v/7e3))+u),p=d.subarray(h,d.length-u),g=c.l,w=7&(c.r||0);if(a){w&&(p[0]=c.r>>3);for(var y=C[a-1],M=y>>13,E=8191&y,z=(1<<o)-1,_=c.p||new n(32768),x=c.h||new n(z+1),A=Math.ceil(o/3),D=2*A,T=function(t){return(s[t]^s[t+1]<<A^s[t+2]<<D)&z},F=new r(25e3),I=new n(288),S=new n(32),L=0,O=0,j=c.i||0,q=0,B=c.w||0,G=0;j+2<v;++j){var H=T(j),J=32767&j,K=x[H];if(_[J]=K,x[H]=J,B<=j){var N=v-j;if((L>7e3||q>24576)&&(N>423||!g)){w=U(s,p,0,F,I,S,O,q,G,j-G,w),q=L=O=0,G=j;for(var P=0;P<286;++P)I[P]=0;for(P=0;P<30;++P)S[P]=0}var Q=2,R=0,V=E,W=J-K&32767;if(N>2&&H==T(j-W))for(var X=Math.min(M,N)-1,Y=Math.min(32767,j),Z=Math.min(258,N);W<=Y&&--V&&J!=K;){if(s[j+Q]==s[j+Q-W]){for(var $=0;$<Z&&s[j+$]==s[j+$-W];++$);if($>Q){if(Q=$,R=W,$>X)break;var tt=Math.min(W,$-2),nt=0;for(P=0;P<tt;++P){var rt=j-W+P&32767,et=rt-_[rt]&32767;et>nt&&(nt=et,K=rt)}}}W+=(J=K)-(K=_[J])&32767}if(R){F[q++]=268435456|f[Q]<<18|l[R];var it=31&f[Q],st=31&l[R];O+=e[it]+i[st],++I[257+it],++S[st],B=j+Q,++L}else F[q++]=s[j],++I[s[j]]}}for(j=Math.max(j,B);j<v;++j)F[q++]=s[j],++I[s[j]];w=U(s,p,g,F,I,S,O,q,G,j-G,w),g||(c.r=7&w|p[w/8|0]<<3,w-=7,c.h=x,c.p=_,c.i=j,c.w=B)}else{for(j=c.w||0;j<v+g;j+=65535){var at=j+65535;at>=v&&(p[w/8|0]=g,at=v),w=k(p,w+1,s.subarray(j,at))}c.i=v}return b(d,0,h+m(w)+u)}(s,null==a.level?6:a.level,null==a.mem?u.l?Math.ceil(1.5*Math.max(8,Math.min(13,Math.log(s.length)))):20:12+a.mem,o,h,u)},O=function(t,n,r){for(;r;++n)t[n]=r,r>>>=8},j=function(){function n(n,r){if("function"==typeof n&&(r=n,n={}),this.ondata=r,this.o=n||{},this.s={l:0,i:32768,w:32768,z:32768},this.b=new t(98304),this.o.dictionary){var e=this.o.dictionary.subarray(-32768);this.b.set(e,32768-e.length),this.s.i=32768-e.length}}return n.prototype.p=function(t,n){this.ondata(L(t,this.o,0,0,this.s),n)},n.prototype.push=function(n,r){this.ondata||E(5),this.s.l&&E(4);var e=n.length+this.s.z;if(e>this.b.length){if(e>2*this.b.length-32768){var i=new t(-32768&e);i.set(this.b.subarray(0,this.s.z)),this.b=i}var s=this.b.length-this.s.z;this.b.set(n.subarray(0,s),this.s.z),this.s.z=this.b.length,this.p(this.b,!1),this.b.set(this.b.subarray(-32768)),this.b.set(n.subarray(s),32768),this.s.z=n.length-s+32768,this.s.i=32766,this.s.w=32768}else this.b.set(n,this.s.z),this.s.z+=n.length;this.s.l=1&r,(this.s.z>this.s.w+8191||r)&&(this.p(this.b,r||!1),this.s.w=this.s.i,this.s.i-=2)},n.prototype.flush=function(){this.ondata||E(5),this.s.l&&E(4),this.p(this.b,!1),this.s.w=this.s.i,this.s.i-=2},n}();function q(t,n){n||(n={});var r=function(){var t=-1;return{p:function(n){for(var r=t,e=0;e<n.length;++e)r=I[255&r^n[e]]^r>>>8;t=r},d:function(){return~t}}}(),e=t.length;r.p(t);var i,s=L(t,n,10+((i=n).filename?i.filename.length+1:0),8),a=s.length;return function(t,n){var r=n.filename;if(t[0]=31,t[1]=139,t[2]=8,t[8]=n.level<2?4:9==n.level?2:0,t[9]=3,0!=n.mtime&&O(t,4,Math.floor(new Date(n.mtime||Date.now())/1e3)),r){t[3]=8;for(var e=0;e<=r.length;++e)t[e+10]=r.charCodeAt(e)}}(s,n),O(s,a-8,r.d()),O(s,a-4,e),s}var B=function(){function t(t,n){this.c=S(),this.v=1,j.call(this,t,n)}return t.prototype.push=function(t,n){this.c.p(t),j.prototype.push.call(this,t,n)},t.prototype.p=function(t,n){var r=L(t,this.o,this.v&&(this.o.dictionary?6:2),n&&4,this.s);this.v&&(function(t,n){var r=n.level,e=0==r?0:r<6?1:9==r?3:2;if(t[0]=120,t[1]=e<<6|(n.dictionary&&32),t[1]|=31-(t[0]<<8|t[1])%31,n.dictionary){var i=S();i.p(n.dictionary),O(t,2,i.d())}}(r,this.o),this.v=0),n&&O(r,r.length-4,this.c.d()),this.ondata(r,n)},t.prototype.flush=function(){j.prototype.flush.call(this)},t}(),G="undefined"!=typeof TextEncoder&&new TextEncoder,H="undefined"!=typeof TextDecoder&&new TextDecoder;try{H.decode(F,{stream:!0})}catch(t){}var J=function(){function t(t){this.ondata=t}return t.prototype.push=function(t,n){this.ondata||E(5),this.d&&E(4),this.ondata(K(t),this.d=n||!1)},t}();function K(n,r){if(G)return G.encode(n);for(var e=n.length,i=new t(n.length+(n.length>>1)),s=0,a=function(t){i[s++]=t},o=0;o<e;++o){if(s+5>i.length){var h=new t(s+8+(e-o<<1));h.set(i),i=h}var f=n.charCodeAt(o);f<128||r?a(f):f<2048?(a(192|f>>6),a(128|63&f)):f>55295&&f<57344?(a(240|(f=65536+(1047552&f)|1023&n.charCodeAt(++o))>>18),a(128|f>>12&63),a(128|f>>6&63),a(128|63&f)):(a(224|f>>12),a(128|f>>6&63),a(128|63&f))}return b(i,0,s)}const N=new class{constructor(){this._init()}clear(){this._init()}addEvent(t){if(!t)throw new Error("Adding invalid event");const n=this._hasEvents?",":"";this.stream.push(n+t),this._hasEvents=!0}finish(){this.stream.push("]",!0);const t=function(t){let n=0;for(const r of t)n+=r.length;const r=new Uint8Array(n);for(let n=0,e=0,i=t.length;n<i;n++){const i=t[n];r.set(i,e),e+=i.length}return r}(this._deflatedData);return this._init(),t}_init(){this._hasEvents=!1,this._deflatedData=[],this.deflate=new B,this.deflate.ondata=(t,n)=>{this._deflatedData.push(t)},this.stream=new J((t,n)=>{this.deflate.push(t,n)}),this.stream.push("[")}},P={clear:()=>{N.clear()},addEvent:t=>N.addEvent(t),finish:()=>N.finish(),compress:t=>function(t){return q(K(t))}(t)};addEventListener("message",function(t){const n=t.data.method,r=t.data.id,e=t.data.arg;if(n in P&&"function"==typeof P[n])try{const t=P[n](e);postMessage({id:r,method:n,success:!0,response:t})}catch(t){postMessage({id:r,method:n,success:!1,response:t.message}),console.error(t)}}),postMessage({id:void 0,method:"init",success:!0,response:void 0});';
function eR() {
  const e = new Blob([QC]);
  return URL.createObjectURL(e);
}
const Yl = ["log", "warn", "error"],
  ms = "[Replay] ";
function io(e, t = "info") {
  W1(
    {
      category: "console",
      data: { logger: "replay" },
      level: t,
      message: `${ms}${e}`,
    },
    { level: t },
  );
}
function tR() {
  let e = !1,
    t = !1;
  const n = {
    exception: () => {},
    infoTick: () => {},
    setConfig: (r) => {
      ((e = !!r.captureExceptions), (t = !!r.traceInternals));
    },
  };
  return (
    $
      ? (Yl.forEach((r) => {
          n[r] = (...s) => {
            (ct[r](ms, ...s), t && io(s.join(""), z1(r)));
          };
        }),
        (n.exception = (r, ...s) => {
          (s.length && n.error && n.error(...s),
            ct.error(ms, r),
            e
              ? k1(r, {
                  mechanism: {
                    handled: !0,
                    type: "auto.function.replay.debug",
                  },
                })
              : t && io(r, "error"));
        }),
        (n.infoTick = (...r) => {
          (ct.log(ms, ...r), t && setTimeout(() => io(r[0]), 0));
        }))
      : Yl.forEach((r) => {
          n[r] = () => {};
        }),
    n
  );
}
const D = tR();
class vc extends Error {
  constructor() {
    super(`Event buffer exceeded maximum size of ${pc}.`);
  }
}
class Hh {
  constructor() {
    ((this.events = []),
      (this._totalSize = 0),
      (this.hasCheckout = !1),
      (this.waitForCheckout = !1));
  }
  get hasEvents() {
    return this.events.length > 0;
  }
  get type() {
    return "sync";
  }
  destroy() {
    this.events = [];
  }
  async addEvent(t) {
    const n = JSON.stringify(t).length;
    if (((this._totalSize += n), this._totalSize > pc)) throw new vc();
    this.events.push(t);
  }
  finish() {
    return new Promise((t) => {
      const n = this.events;
      (this.clear(), t(JSON.stringify(n)));
    });
  }
  clear() {
    ((this.events = []), (this._totalSize = 0), (this.hasCheckout = !1));
  }
  getEarliestTimestamp() {
    const t = this.events.map((n) => n.timestamp).sort()[0];
    return t ? yc(t) : null;
  }
}
class nR {
  constructor(t) {
    ((this._worker = t), (this._id = 0));
  }
  ensureReady() {
    return this._ensureReadyPromise
      ? this._ensureReadyPromise
      : ((this._ensureReadyPromise = new Promise((t, n) => {
          (this._worker.addEventListener(
            "message",
            ({ data: r }) => {
              r.success ? t() : n();
            },
            { once: !0 },
          ),
            this._worker.addEventListener(
              "error",
              (r) => {
                n(r);
              },
              { once: !0 },
            ));
        })),
        this._ensureReadyPromise);
  }
  destroy() {
    ($ && D.log("Destroying compression worker"), this._worker.terminate());
  }
  postMessage(t, n) {
    const r = this._getAndIncrementId();
    return new Promise((s, i) => {
      const o = ({ data: a }) => {
        const c = a;
        if (c.method === t && c.id === r) {
          if ((this._worker.removeEventListener("message", o), !c.success)) {
            ($ && D.error("Error in compression worker: ", c.response),
              i(new Error("Error in compression worker")));
            return;
          }
          s(c.response);
        }
      };
      (this._worker.addEventListener("message", o),
        this._worker.postMessage({ id: r, method: t, arg: n }));
    });
  }
  _getAndIncrementId() {
    return this._id++;
  }
}
class rR {
  constructor(t) {
    ((this._worker = new nR(t)),
      (this._earliestTimestamp = null),
      (this._totalSize = 0),
      (this.hasCheckout = !1),
      (this.waitForCheckout = !1));
  }
  get hasEvents() {
    return !!this._earliestTimestamp;
  }
  get type() {
    return "worker";
  }
  ensureReady() {
    return this._worker.ensureReady();
  }
  destroy() {
    this._worker.destroy();
  }
  addEvent(t) {
    const n = yc(t.timestamp);
    (!this._earliestTimestamp || n < this._earliestTimestamp) &&
      (this._earliestTimestamp = n);
    const r = JSON.stringify(t);
    return (
      (this._totalSize += r.length),
      this._totalSize > pc
        ? Promise.reject(new vc())
        : this._sendEventToWorker(r)
    );
  }
  finish() {
    return this._finishRequest();
  }
  clear() {
    ((this._earliestTimestamp = null),
      (this._totalSize = 0),
      (this.hasCheckout = !1),
      this._worker.postMessage("clear").then(null, (t) => {
        $ && D.exception(t, 'Sending "clear" message to worker failed', t);
      }));
  }
  getEarliestTimestamp() {
    return this._earliestTimestamp;
  }
  _sendEventToWorker(t) {
    return this._worker.postMessage("addEvent", t);
  }
  async _finishRequest() {
    const t = await this._worker.postMessage("finish");
    return ((this._earliestTimestamp = null), (this._totalSize = 0), t);
  }
}
class sR {
  constructor(t) {
    ((this._fallback = new Hh()),
      (this._compression = new rR(t)),
      (this._used = this._fallback),
      (this._ensureWorkerIsLoadedPromise = this._ensureWorkerIsLoaded()));
  }
  get waitForCheckout() {
    return this._used.waitForCheckout;
  }
  get type() {
    return this._used.type;
  }
  get hasEvents() {
    return this._used.hasEvents;
  }
  get hasCheckout() {
    return this._used.hasCheckout;
  }
  set hasCheckout(t) {
    this._used.hasCheckout = t;
  }
  set waitForCheckout(t) {
    this._used.waitForCheckout = t;
  }
  destroy() {
    (this._fallback.destroy(), this._compression.destroy());
  }
  clear() {
    return this._used.clear();
  }
  getEarliestTimestamp() {
    return this._used.getEarliestTimestamp();
  }
  addEvent(t) {
    return this._used.addEvent(t);
  }
  async finish() {
    return (await this.ensureWorkerIsLoaded(), this._used.finish());
  }
  ensureWorkerIsLoaded() {
    return this._ensureWorkerIsLoadedPromise;
  }
  async _ensureWorkerIsLoaded() {
    try {
      await this._compression.ensureReady();
    } catch (t) {
      $ &&
        D.exception(
          t,
          "Failed to load the compression worker, falling back to simple buffer",
        );
      return;
    }
    await this._switchToCompressionWorker();
  }
  async _switchToCompressionWorker() {
    const { events: t, hasCheckout: n, waitForCheckout: r } = this._fallback,
      s = [];
    for (const i of t) s.push(this._compression.addEvent(i));
    ((this._compression.hasCheckout = n),
      (this._compression.waitForCheckout = r),
      (this._used = this._compression));
    try {
      (await Promise.all(s), this._fallback.clear());
    } catch (i) {
      $ && D.exception(i, "Failed to add events when switching buffers.");
    }
  }
}
function iR({ useCompression: e, workerUrl: t }) {
  if (e && window.Worker) {
    const n = oR(t);
    if (n) return n;
  }
  return ($ && D.log("Using simple buffer"), new Hh());
}
function oR(e) {
  try {
    const t = e || aR();
    if (!t) return;
    $ && D.log(`Using compression worker${e ? ` from ${e}` : ""}`);
    const n = new Worker(t);
    return new sR(n);
  } catch (t) {
    $ && D.exception(t, "Failed to create compression worker");
  }
}
function aR() {
  return typeof __SENTRY_EXCLUDE_REPLAY_WORKER__ > "u" ||
    !__SENTRY_EXCLUDE_REPLAY_WORKER__
    ? eR()
    : "";
}
function Tc() {
  try {
    return "sessionStorage" in ae && !!ae.sessionStorage;
  } catch {
    return !1;
  }
}
function cR(e) {
  (uR(), (e.session = void 0));
}
function uR() {
  if (Tc())
    try {
      ae.sessionStorage.removeItem(dc);
    } catch {}
}
function Wh(e) {
  return e === void 0 ? !1 : Math.random() < e;
}
function wc(e) {
  if (Tc())
    try {
      ae.sessionStorage.setItem(dc, JSON.stringify(e));
    } catch {}
}
function zh(e) {
  const t = Date.now(),
    n = e.id || It(),
    r = e.started || t,
    s = e.lastActivity || t,
    i = e.segmentId || 0,
    o = e.sampled,
    a = e.previousSessionId;
  return {
    id: n,
    started: r,
    lastActivity: s,
    segmentId: i,
    sampled: o,
    previousSessionId: a,
  };
}
function lR(e, t) {
  return Wh(e) ? "session" : t ? "buffer" : !1;
}
function Xl(
  { sessionSampleRate: e, allowBuffering: t, stickySession: n = !1 },
  { previousSessionId: r } = {},
) {
  const s = lR(e, t),
    i = zh({ sampled: s, previousSessionId: r });
  return (n && wc(i), i);
}
function dR() {
  if (!Tc()) return null;
  try {
    const e = ae.sessionStorage.getItem(dc);
    if (!e) return null;
    const t = JSON.parse(e);
    return ($ && D.infoTick("Loading existing session"), zh(t));
  } catch {
    return null;
  }
}
function jo(e, t, n = +new Date()) {
  return e === null || t === void 0 || t < 0 ? !0 : t === 0 ? !1 : e + t <= n;
}
function jh(
  e,
  { maxReplayDuration: t, sessionIdleExpire: n, targetTime: r = Date.now() },
) {
  return jo(e.started, t, r) || jo(e.lastActivity, n, r);
}
function qh(e, { sessionIdleExpire: t, maxReplayDuration: n }) {
  return !(
    !jh(e, { sessionIdleExpire: t, maxReplayDuration: n }) ||
    (e.sampled === "buffer" && e.segmentId === 0)
  );
}
function oo(
  { sessionIdleExpire: e, maxReplayDuration: t, previousSessionId: n },
  r,
) {
  const s = r.stickySession && dR();
  return s
    ? qh(s, { sessionIdleExpire: e, maxReplayDuration: t })
      ? ($ &&
          D.infoTick(
            "Session in sessionStorage is expired, creating new one...",
          ),
        Xl(r, { previousSessionId: s.id }))
      : s
    : ($ && D.infoTick("Creating new session"),
      Xl(r, { previousSessionId: n }));
}
function fR(e) {
  return e.type === z.Custom;
}
function Ic(e, t, n) {
  return Vh(e, t) ? (Gh(e, t, n), !0) : !1;
}
function pR(e, t, n) {
  return Vh(e, t) ? Gh(e, t, n) : Promise.resolve(null);
}
async function Gh(e, t, n) {
  const { eventBuffer: r } = e;
  if (!r || (r.waitForCheckout && !n)) return null;
  const s = e.recordingMode === "buffer";
  try {
    (n && s && r.clear(),
      n && ((r.hasCheckout = !0), (r.waitForCheckout = !1)));
    const i = e.getOptions(),
      o = hR(t, i.beforeAddRecordingEvent);
    return o ? await r.addEvent(o) : void 0;
  } catch (i) {
    const o = i && i instanceof vc,
      a = o ? "addEventSizeExceeded" : "addEvent";
    if (o && s) return (r.clear(), (r.waitForCheckout = !0), null);
    (e.handleException(i), await e.stop({ reason: a }));
    const c = Ge();
    c && c.recordDroppedEvent("internal_sdk_error", "replay");
  }
}
function Vh(e, t) {
  if (!e.eventBuffer || e.isPaused() || !e.isEnabled()) return !1;
  const n = yc(t.timestamp);
  return n + e.timeouts.sessionIdlePause < Date.now()
    ? !1
    : n > e.getContext().initialTimestamp + e.getOptions().maxReplayDuration
      ? ($ &&
          D.infoTick(
            `Skipping event with timestamp ${n} because it is after maxReplayDuration`,
          ),
        !1)
      : !0;
}
function hR(e, t) {
  try {
    if (typeof t == "function" && fR(e)) return t(e);
  } catch (n) {
    return (
      $ &&
        D.exception(
          n,
          "An error occurred in the `beforeAddRecordingEvent` callback, skipping the event...",
        ),
      null
    );
  }
  return e;
}
function kc(e) {
  return !e.type;
}
function qo(e) {
  return e.type === "transaction";
}
function mR(e) {
  return e.type === "replay_event";
}
function Kl(e) {
  return e.type === "feedback";
}
function gR(e) {
  return (t, n) => {
    if (!e.isEnabled() || (!kc(t) && !qo(t))) return;
    const r = n.statusCode;
    if (!(!r || r < 200 || r >= 300)) {
      if (qo(t)) {
        _R(e, t);
        return;
      }
      SR(e, t);
    }
  };
}
function _R(e, t) {
  const n = e.getContext();
  t.contexts?.trace?.trace_id &&
    n.traceIds.size < 100 &&
    n.traceIds.add(t.contexts.trace.trace_id);
}
function SR(e, t) {
  const n = e.getContext();
  if (
    (t.event_id && n.errorIds.size < 100 && n.errorIds.add(t.event_id),
    e.recordingMode !== "buffer" || !t.tags || !t.tags.replayId)
  )
    return;
  const { beforeErrorSampling: r } = e.getOptions();
  (typeof r == "function" && !r(t)) ||
    Mr(async () => {
      try {
        await e.sendBufferedReplayOrFlush();
      } catch (s) {
        e.handleException(s);
      }
    });
}
function yR(e) {
  return (t) => {
    !e.isEnabled() || !kc(t) || bR(e, t);
  };
}
function bR(e, t) {
  const n = t.exception?.values?.[0]?.value;
  if (
    typeof n == "string" &&
    (n.match(
      /(reactjs\.org\/docs\/error-decoder\.html\?invariant=|react\.dev\/errors\/)(418|419|422|423|425)/,
    ) ||
      n.match(
        /(does not match server-rendered HTML|Hydration failed because)/i,
      ))
  ) {
    const r = Ke({ category: "replay.hydrate-error", data: { url: sI() } });
    Lr(e, r);
  }
}
function ER(e) {
  const t = Ge();
  t && t.on("beforeAddBreadcrumb", (n) => vR(e, n));
}
function vR(e, t) {
  if (!e.isEnabled() || !Yh(t)) return;
  const n = TR(t);
  n && Lr(e, n);
}
function TR(e) {
  return !Yh(e) ||
    ["fetch", "xhr", "sentry.event", "sentry.transaction"].includes(
      e.category,
    ) ||
    e.category.startsWith("ui.")
    ? null
    : e.category === "console"
      ? wR(e)
      : Ke(e);
}
function wR(e) {
  const t = e.data?.arguments;
  if (!Array.isArray(t) || t.length === 0) return Ke(e);
  let n = !1;
  const r = t.map((s) => {
    if (!s) return s;
    if (typeof s == "string")
      return s.length > Yr ? ((n = !0), `${s.slice(0, Yr)}…`) : s;
    if (typeof s == "object")
      try {
        const i = nt(s, 7);
        return JSON.stringify(i).length > Yr
          ? ((n = !0), `${JSON.stringify(i, null, 2).slice(0, Yr)}…`)
          : i;
      } catch {}
    return s;
  });
  return Ke({
    ...e,
    data: {
      ...e.data,
      arguments: r,
      ...(n ? { _meta: { warnings: ["CONSOLE_ARG_TRUNCATED"] } } : {}),
    },
  });
}
function Yh(e) {
  return !!e.category;
}
function IR(e, t) {
  return e.type || !e.exception?.values?.length
    ? !1
    : !!t.originalException?.__rrweb__;
}
function Xh() {
  const e = Nr().getPropagationContext().dsc;
  e && delete e.replay_id;
  const t = fh();
  if (t) {
    const n = hh(t);
    delete n.replay_id;
  }
}
function kR(e, t) {
  (e.triggerUserActivity(),
    e.addUpdate(() =>
      t.timestamp
        ? (e.throttledAddEvent({
            type: z.Custom,
            timestamp: t.timestamp * 1e3,
            data: {
              tag: "breadcrumb",
              payload: {
                timestamp: t.timestamp,
                type: "default",
                category: "sentry.feedback",
                data: { feedbackId: t.event_id },
              },
            },
          }),
          !1)
        : !0,
    ));
}
function CR(e, t) {
  return e.recordingMode !== "buffer" ||
    t.message === fc ||
    !t.exception ||
    t.type
    ? !1
    : Wh(e.getOptions().errorSampleRate);
}
function RR(e) {
  return Object.assign(
    (t, n) =>
      !e.isEnabled() || e.isPaused()
        ? t
        : mR(t)
          ? (delete t.breadcrumbs, t)
          : !kc(t) && !qo(t) && !Kl(t)
            ? t
            : e.checkAndHandleExpiredSession()
              ? Kl(t)
                ? (e.flush(),
                  (t.contexts.feedback.replay_id = e.getSessionId()),
                  kR(e, t),
                  t)
                : IR(t, n) && !e.getOptions()._experiments.captureExceptions
                  ? ($ && D.log("Ignoring error from rrweb internals", t), null)
                  : ((CR(e, t) || e.recordingMode === "session") &&
                      (t.tags = { ...t.tags, replayId: e.getSessionId() }),
                    t)
              : (Xh(), t),
    { id: "Replay" },
  );
}
function xi(e, t) {
  return t.map(({ type: n, start: r, end: s, name: i, data: o }) => {
    const a = e.throttledAddEvent({
      type: z.Custom,
      timestamp: r,
      data: {
        tag: "performanceSpan",
        payload: {
          op: n,
          description: i,
          startTimestamp: r,
          endTimestamp: s,
          data: o,
        },
      },
    });
    return typeof a == "string" ? Promise.resolve(null) : a;
  });
}
function xR(e) {
  const { from: t, to: n } = e,
    r = Date.now() / 1e3;
  return {
    type: "navigation.push",
    start: r,
    end: r,
    name: n,
    data: { previous: t },
  };
}
function AR(e) {
  return (t) => {
    if (!e.isEnabled()) return;
    const n = xR(t);
    n !== null &&
      (e.getContext().urls.push(n.name),
      e.triggerUserActivity(),
      e.addUpdate(() => (xi(e, [n]), !1)));
  };
}
function MR(e, t) {
  return $ && e.getOptions()._experiments.traceInternals ? !1 : P1(t, Ge());
}
function Kh(e, t) {
  e.isEnabled() &&
    t !== null &&
    (MR(e, t.name) || e.addUpdate(() => (xi(e, [t]), !0)));
}
function Ai(e) {
  if (!e) return;
  const t = new TextEncoder();
  try {
    if (typeof e == "string") return t.encode(e).length;
    if (e instanceof URLSearchParams) return t.encode(e.toString()).length;
    if (e instanceof FormData) {
      const n = Lp(e);
      return t.encode(n).length;
    }
    if (e instanceof Blob) return e.size;
    if (e instanceof ArrayBuffer) return e.byteLength;
  } catch {}
}
function Jh(e) {
  if (!e) return;
  const t = parseInt(e, 10);
  return isNaN(t) ? void 0 : t;
}
function Zs(e, t) {
  if (!e) return { headers: {}, size: void 0, _meta: { warnings: [t] } };
  const n = { ...e._meta },
    r = n.warnings || [];
  return ((n.warnings = [...r, t]), (e._meta = n), e);
}
function Zh(e, t) {
  if (!t) return null;
  const {
    startTimestamp: n,
    endTimestamp: r,
    url: s,
    method: i,
    statusCode: o,
    request: a,
    response: c,
  } = t;
  return {
    type: e,
    start: n / 1e3,
    end: r / 1e3,
    name: s,
    data: { method: i, statusCode: o, request: a, response: c },
  };
}
function dr(e) {
  return { headers: {}, size: e, _meta: { warnings: ["URL_SKIPPED"] } };
}
function kt(e, t, n) {
  if (!t && Object.keys(e).length === 0) return;
  if (!t) return { headers: e };
  if (!n) return { headers: e, size: t };
  const r = { headers: e, size: t },
    { body: s, warnings: i } = NR(n);
  return ((r.body = s), i?.length && (r._meta = { warnings: i }), r);
}
function Go(e, t) {
  return Object.entries(e).reduce((n, [r, s]) => {
    const i = r.toLowerCase();
    return (t.includes(i) && e[r] && (n[i] = s), n);
  }, {});
}
function NR(e) {
  if (!e || typeof e != "string") return { body: e };
  const t = e.length > Al,
    n = OR(e);
  if (t) {
    const r = e.slice(0, Al);
    return n
      ? { body: r, warnings: ["MAYBE_JSON_TRUNCATED"] }
      : { body: `${r}…`, warnings: ["TEXT_TRUNCATED"] };
  }
  if (n)
    try {
      return { body: JSON.parse(e) };
    } catch {}
  return { body: e };
}
function OR(e) {
  const t = e[0],
    n = e[e.length - 1];
  return (t === "[" && n === "]") || (t === "{" && n === "}");
}
function Qs(e, t) {
  const n = LR(e);
  return oI(n, t);
}
function LR(e, t = ae.document.baseURI) {
  if (
    e.startsWith("http://") ||
    e.startsWith("https://") ||
    e.startsWith(ae.location.origin)
  )
    return e;
  const n = new URL(e, t);
  if (n.origin !== new URL(t).origin) return e;
  const r = n.href;
  return !e.endsWith("/") && r.endsWith("/") ? r.slice(0, -1) : r;
}
async function $R(e, t, n) {
  try {
    const r = await PR(e, t, n),
      s = Zh("resource.fetch", r);
    Kh(n.replay, s);
  } catch (r) {
    $ && D.exception(r, "Failed to capture fetch breadcrumb");
  }
}
function DR(e, t) {
  const { input: n, response: r } = t,
    s = n ? ec(n) : void 0,
    i = Ai(s),
    o = r ? Jh(r.headers.get("content-length")) : void 0;
  (i !== void 0 && (e.data.request_body_size = i),
    o !== void 0 && (e.data.response_body_size = o));
}
async function PR(e, t, n) {
  const r = Date.now(),
    { startTimestamp: s = r, endTimestamp: i = r } = t,
    {
      url: o,
      method: a,
      status_code: c = 0,
      request_body_size: u,
      response_body_size: d,
    } = e.data,
    l = Qs(o, n.networkDetailAllowUrls) && !Qs(o, n.networkDetailDenyUrls),
    p = l ? FR(n, t.input, u) : dr(u),
    f = await BR(l, n, t.response, d);
  return {
    startTimestamp: s,
    endTimestamp: i,
    url: o,
    method: a,
    statusCode: c,
    request: p,
    response: f,
  };
}
function FR({ networkCaptureBodies: e, networkRequestHeaders: t }, n, r) {
  const s = n ? WR(n, t) : {};
  if (!e) return kt(s, r, void 0);
  const i = ec(n),
    [o, a] = js(i, D),
    c = kt(s, r, o);
  return a ? Zs(c, a) : c;
}
async function BR(
  e,
  { networkCaptureBodies: t, networkResponseHeaders: n },
  r,
  s,
) {
  if (!e && s !== void 0) return dr(s);
  const i = r ? Qh(r.headers, n) : {};
  if (!r || (!t && s !== void 0)) return kt(i, s, void 0);
  const [o, a] = await HR(r),
    c = UR(o, {
      networkCaptureBodies: t,
      responseBodySize: s,
      captureDetails: e,
      headers: i,
    });
  return a ? Zs(c, a) : c;
}
function UR(
  e,
  {
    networkCaptureBodies: t,
    responseBodySize: n,
    captureDetails: r,
    headers: s,
  },
) {
  try {
    const i = e?.length && n === void 0 ? Ai(e) : n;
    return r ? (t ? kt(s, i, e) : kt(s, i, void 0)) : dr(i);
  } catch (i) {
    return (
      $ && D.exception(i, "Failed to serialize response body"),
      kt(s, n, void 0)
    );
  }
}
async function HR(e) {
  const t = zR(e);
  if (!t) return [void 0, "BODY_PARSE_ERROR"];
  try {
    return [await jR(t)];
  } catch (n) {
    return n instanceof Error && n.message.indexOf("Timeout") > -1
      ? ($ && D.warn("Parsing text body from response timed out"),
        [void 0, "BODY_PARSE_TIMEOUT"])
      : ($ && D.exception(n, "Failed to get text body from response"),
        [void 0, "BODY_PARSE_ERROR"]);
  }
}
function Qh(e, t) {
  const n = {};
  return (
    t.forEach((r) => {
      e.get(r) && (n[r] = e.get(r));
    }),
    n
  );
}
function WR(e, t) {
  return e.length === 1 && typeof e[0] != "string"
    ? Jl(e[0], t)
    : e.length === 2
      ? Jl(e[1], t)
      : {};
}
function Jl(e, t) {
  if (!e) return {};
  const n = e.headers;
  return n
    ? n instanceof Headers
      ? Qh(n, t)
      : Array.isArray(n)
        ? {}
        : Go(n, t)
    : {};
}
function zR(e) {
  try {
    return e.clone();
  } catch (t) {
    $ && D.exception(t, "Failed to clone response body");
  }
}
function jR(e) {
  return new Promise((t, n) => {
    const r = Mr(
      () => n(new Error("Timeout while trying to read response body")),
      500,
    );
    qR(e)
      .then(
        (s) => t(s),
        (s) => n(s),
      )
      .finally(() => clearTimeout(r));
  });
}
async function qR(e) {
  return await e.text();
}
async function GR(e, t, n) {
  try {
    const r = YR(e, t, n),
      s = Zh("resource.xhr", r);
    Kh(n.replay, s);
  } catch (r) {
    $ && D.exception(r, "Failed to capture xhr breadcrumb");
  }
}
function VR(e, t) {
  const { xhr: n, input: r } = t;
  if (!n) return;
  const s = Ai(r),
    i = n.getResponseHeader("content-length")
      ? Jh(n.getResponseHeader("content-length"))
      : ZR(n.response, n.responseType);
  (s !== void 0 && (e.data.request_body_size = s),
    i !== void 0 && (e.data.response_body_size = i));
}
function YR(e, t, n) {
  const r = Date.now(),
    { startTimestamp: s = r, endTimestamp: i = r, input: o, xhr: a } = t,
    {
      url: c,
      method: u,
      status_code: d = 0,
      request_body_size: l,
      response_body_size: p,
    } = e.data;
  if (!c) return null;
  if (
    !a ||
    !Qs(c, n.networkDetailAllowUrls) ||
    Qs(c, n.networkDetailDenyUrls)
  ) {
    const C = dr(l),
      E = dr(p);
    return {
      startTimestamp: s,
      endTimestamp: i,
      url: c,
      method: u,
      statusCode: d,
      request: C,
      response: E,
    };
  }
  const f = a[st],
    h = f ? Go(f.request_headers, n.networkRequestHeaders) : {},
    m = Go(XR(a), n.networkResponseHeaders),
    [g, _] = n.networkCaptureBodies ? js(o, D) : [void 0],
    [y, M] = n.networkCaptureBodies ? KR(a) : [void 0],
    w = kt(h, l, g),
    A = kt(m, p, y);
  return {
    startTimestamp: s,
    endTimestamp: i,
    url: c,
    method: u,
    statusCode: d,
    request: _ ? Zs(w, _) : w,
    response: M ? Zs(A, M) : A,
  };
}
function XR(e) {
  const t = e.getAllResponseHeaders();
  return t
    ? t
        .split(
          `\r
`,
        )
        .reduce((n, r) => {
          const [s, i] = r.split(": ");
          return (i && (n[s.toLowerCase()] = i), n);
        }, {})
    : {};
}
function KR(e) {
  const t = [];
  try {
    return [e.responseText];
  } catch (n) {
    t.push(n);
  }
  try {
    return JR(e.response, e.responseType);
  } catch (n) {
    t.push(n);
  }
  return ($ && D.warn("Failed to get xhr response body", ...t), [void 0]);
}
function JR(e, t) {
  try {
    if (typeof e == "string") return [e];
    if (e instanceof Document) return [e.body.outerHTML];
    if (t === "json" && e && typeof e == "object") return [JSON.stringify(e)];
    if (!e) return [void 0];
  } catch (n) {
    return (
      $ && D.exception(n, "Failed to serialize body", e),
      [void 0, "BODY_PARSE_ERROR"]
    );
  }
  return (
    $ && D.log("Skipping network body because of body type", e),
    [void 0, "UNPARSEABLE_BODY_TYPE"]
  );
}
function ZR(e, t) {
  try {
    const n = t === "json" && e && typeof e == "object" ? JSON.stringify(e) : e;
    return Ai(n);
  } catch {
    return;
  }
}
function QR(e) {
  const t = Ge();
  try {
    const {
        networkDetailAllowUrls: n,
        networkDetailDenyUrls: r,
        networkCaptureBodies: s,
        networkRequestHeaders: i,
        networkResponseHeaders: o,
      } = e.getOptions(),
      a = {
        replay: e,
        networkDetailAllowUrls: n,
        networkDetailDenyUrls: r,
        networkCaptureBodies: s,
        networkRequestHeaders: i,
        networkResponseHeaders: o,
      };
    t && t.on("beforeAddBreadcrumb", (c, u) => ex(a, c, u));
  } catch {}
}
function ex(e, t, n) {
  if (t.data)
    try {
      (tx(t) && rx(n) && (VR(t, n), GR(t, n, e)),
        nx(t) && sx(n) && (DR(t, n), $R(t, n, e)));
    } catch (r) {
      $ && D.exception(r, "Error when enriching network breadcrumb");
    }
}
function tx(e) {
  return e.category === "xhr";
}
function nx(e) {
  return e.category === "fetch";
}
function rx(e) {
  return e?.xhr;
}
function sx(e) {
  return e?.response;
}
function ix(e) {
  const t = Ge();
  (Op($C(e)), Si(AR(e)), ER(e), QR(e));
  const n = RR(e);
  (R1(n),
    t &&
      (t.on("beforeSendEvent", yR(e)),
      t.on("afterSendEvent", gR(e)),
      t.on("createDsc", (r) => {
        const s = e.getSessionId();
        s &&
          e.isEnabled() &&
          e.recordingMode === "session" &&
          e.checkAndHandleExpiredSession() &&
          (r.replay_id = s);
      }),
      t.on("spanStart", (r) => {
        e.lastActiveSpan = r;
      }),
      t.on("spanEnd", (r) => {
        e.lastActiveSpan = r;
      }),
      t.on("beforeSendFeedback", async (r, s) => {
        const i = e.getSessionId();
        s?.includeReplay &&
          e.isEnabled() &&
          i &&
          r.contexts?.feedback &&
          (r.contexts.feedback.source === "api" &&
            (await e.sendBufferedReplayOrFlush()),
          (r.contexts.feedback.replay_id = i));
      }),
      t.on("openFeedbackWidget", async () => {
        await e.sendBufferedReplayOrFlush();
      })));
}
async function ox(e) {
  try {
    return Promise.all(xi(e, [ax(ae.performance.memory)]));
  } catch {
    return [];
  }
}
function ax(e) {
  const { jsHeapSizeLimit: t, totalJSHeapSize: n, usedJSHeapSize: r } = e,
    s = Date.now() / 1e3;
  return {
    type: "memory",
    name: "memory",
    start: s,
    end: s,
    data: {
      memory: { jsHeapSizeLimit: t, totalJSHeapSize: n, usedJSHeapSize: r },
    },
  };
}
function cx(e, t, n) {
  return U1(e, t, { ...n, setTimeoutImpl: Mr });
}
const Zr = Ce.navigator;
function ux() {
  return /iPhone|iPad|iPod/i.test(Zr?.userAgent ?? "") ||
    (/Macintosh/i.test(Zr?.userAgent ?? "") &&
      Zr?.maxTouchPoints &&
      Zr?.maxTouchPoints > 1)
    ? { sampling: { mousemove: !1 } }
    : {};
}
function lx(e) {
  let t = !1;
  return (n, r) => {
    if (!e.checkAndHandleExpiredSession()) {
      $ && D.warn("Received replay event after session expired.");
      return;
    }
    const s = r || !t;
    ((t = !0),
      e.clickDetector && AC(e.clickDetector, n),
      e.addUpdate(() => {
        if (
          (e.recordingMode === "buffer" && s && e.setInitialState(),
          !Ic(e, n, s))
        )
          return !0;
        if (!s) return !1;
        const i = e.session;
        if ((fx(e, s), e.recordingMode === "buffer" && i && e.eventBuffer)) {
          const o = e.eventBuffer.getEarliestTimestamp();
          o &&
            ($ &&
              D.log(
                `Updating session start time to earliest event in buffer to ${new Date(o)}`,
              ),
            (i.started = o),
            e.getOptions().stickySession && wc(i));
        }
        return (
          i?.previousSessionId || (e.recordingMode === "session" && e.flush()),
          !0
        );
      }));
  };
}
function dx(e) {
  const t = e.getOptions();
  return {
    type: z.Custom,
    timestamp: Date.now(),
    data: {
      tag: "options",
      payload: {
        shouldRecordCanvas: e.isRecordingCanvas(),
        sessionSampleRate: t.sessionSampleRate,
        errorSampleRate: t.errorSampleRate,
        useCompressionOption: t.useCompression,
        blockAllMedia: t.blockAllMedia,
        maskAllText: t.maskAllText,
        maskAllInputs: t.maskAllInputs,
        useCompression: e.eventBuffer ? e.eventBuffer.type === "worker" : !1,
        networkDetailHasUrls: t.networkDetailAllowUrls.length > 0,
        networkCaptureBodies: t.networkCaptureBodies,
        networkRequestHasHeaders: t.networkRequestHeaders.length > 0,
        networkResponseHasHeaders: t.networkResponseHeaders.length > 0,
      },
    },
  };
}
function fx(e, t) {
  !t || !e.session || e.session.segmentId !== 0 || Ic(e, dx(e), !1);
}
function px(e) {
  if (!e) return null;
  try {
    return e.nodeType === e.ELEMENT_NODE ? e : e.parentElement;
  } catch {
    return null;
  }
}
function hx(e, t, n, r) {
  return n1(s1(e, r1(e), r, n), [
    [{ type: "replay_event" }, e],
    [
      {
        type: "replay_recording",
        length:
          typeof t == "string" ? new TextEncoder().encode(t).length : t.length,
      },
      t,
    ],
  ]);
}
function mx({ recordingData: e, headers: t }) {
  let n;
  const r = `${JSON.stringify(t)}
`;
  if (typeof e == "string") n = `${r}${e}`;
  else {
    const i = new TextEncoder().encode(r);
    ((n = new Uint8Array(i.length + e.length)), n.set(i), n.set(e, i.length));
  }
  return n;
}
async function gx({ client: e, scope: t, replayId: n, event: r }) {
  const s =
      typeof e._integrations == "object" &&
      e._integrations !== null &&
      !Array.isArray(e._integrations)
        ? Object.keys(e._integrations)
        : void 0,
    i = { event_id: n, integrations: s };
  e.emit("preprocessEvent", r, i);
  const o = await m1(e.getOptions(), r, i, t, e, Ii());
  if (!o) return null;
  (e.emit("postprocessEvent", o, i), (o.platform = o.platform || "javascript"));
  const a = e.getSdkMetadata(),
    { name: c, version: u, settings: d } = a?.sdk || {};
  return (
    (o.sdk = {
      ...o.sdk,
      name: c || "sentry.javascript.unknown",
      version: u || "0.0.0",
      settings: d,
    }),
    o
  );
}
async function _x({
  recordingData: e,
  replayId: t,
  segmentId: n,
  eventContext: r,
  timestamp: s,
  session: i,
}) {
  const o = mx({ recordingData: e, headers: { segment_id: n } }),
    { urls: a, errorIds: c, traceIds: u, initialTimestamp: d } = r,
    l = Ge(),
    p = Nr(),
    f = l?.getTransport(),
    h = l?.getDsn();
  if (!l || !f || !h || !i.sampled) return Promise.resolve({});
  const m = {
      type: V1,
      replay_start_timestamp: d / 1e3,
      timestamp: s / 1e3,
      error_ids: c,
      trace_ids: u,
      urls: a,
      replay_id: t,
      segment_id: n,
      replay_type: i.sampled,
    },
    g = await gx({ scope: p, client: l, replayId: t, event: m });
  if (!g)
    return (
      l.recordDroppedEvent("event_processor", "replay"),
      $ && D.log("An event processor returned `null`, will not send event."),
      Promise.resolve({})
    );
  delete g.sdkProcessingMetadata;
  const _ = hx(g, o, h, l.getOptions().tunnel);
  let y;
  try {
    y = await f.send(_);
  } catch (w) {
    const A = new Error(fc);
    try {
      A.cause = w;
    } catch {}
    throw A;
  }
  if (
    typeof y.statusCode == "number" &&
    (y.statusCode < 200 || y.statusCode >= 300)
  )
    throw new em(y.statusCode);
  const M = O1({}, y);
  if (N1(M, "replay")) throw new Cc(M);
  return y;
}
class em extends Error {
  constructor(t) {
    super(`Transport returned status code ${t}`);
  }
}
class Cc extends Error {
  constructor(t) {
    (super("Rate limit hit"), (this.rateLimits = t));
  }
}
async function tm(e, t = { count: 0, interval: Q1 }) {
  const { recordingData: n, onError: r } = e;
  if (n.length)
    try {
      return (await _x(e), !0);
    } catch (s) {
      if (s instanceof em || s instanceof Cc) throw s;
      if ((C1("Replays", { _retryCount: t.count }), r && r(s), t.count >= ek)) {
        const i = new Error(`${fc} - max retries exceeded`);
        try {
          i.cause = s;
        } catch {}
        throw i;
      }
      return (
        (t.interval *= ++t.count),
        new Promise((i, o) => {
          Mr(async () => {
            try {
              (await tm(e, t), i(!0));
            } catch (a) {
              o(a);
            }
          }, t.interval);
        })
      );
    }
}
const nm = "__THROTTLED",
  Sx = "__SKIPPED";
function yx(e, t, n) {
  const r = new Map(),
    s = (a) => {
      const c = a - n;
      r.forEach((u, d) => {
        d < c && r.delete(d);
      });
    },
    i = () => [...r.values()].reduce((a, c) => a + c, 0);
  let o = !1;
  return (...a) => {
    const c = Math.floor(Date.now() / 1e3);
    if ((s(c), i() >= t)) {
      const d = o;
      return ((o = !0), d ? Sx : nm);
    }
    o = !1;
    const u = r.get(c) || 0;
    return (r.set(c, u + 1), e(...a));
  };
}
class bx {
  constructor({ options: t, recordingOptions: n }) {
    ((this.eventBuffer = null),
      (this.performanceEntries = []),
      (this.replayPerformanceEntries = []),
      (this.recordingMode = "session"),
      (this.timeouts = { sessionIdlePause: Y1, sessionIdleExpire: X1 }),
      (this._lastActivity = Date.now()),
      (this._isEnabled = !1),
      (this._isPaused = !1),
      (this._requiresManualStart = !1),
      (this._hasInitializedCoreListeners = !1),
      (this._context = {
        errorIds: new Set(),
        traceIds: new Set(),
        urls: [],
        initialTimestamp: Date.now(),
        initialUrl: "",
      }),
      (this._recordingOptions = n),
      (this._options = t),
      (this._debouncedFlush = cx(
        () => this._flush(),
        this._options.flushMinDelay,
        { maxWait: this._options.flushMaxDelay },
      )),
      (this._throttledAddEvent = yx((o, a) => pR(this, o, a), 300, 5)));
    const { slowClickTimeout: r, slowClickIgnoreSelectors: s } =
        this.getOptions(),
      i = r
        ? {
            threshold: Math.min(tk, r),
            timeout: r,
            scrollTimeout: nk,
            ignoreSelector: s ? s.join(",") : "",
          }
        : void 0;
    if ((i && (this.clickDetector = new kC(this, i)), $)) {
      const o = t._experiments;
      D.setConfig({
        captureExceptions: !!o.captureExceptions,
        traceInternals: !!o.traceInternals,
      });
    }
    ((this._handleVisibilityChange = () => {
      ae.document.visibilityState === "visible"
        ? this._doChangeToForegroundTasks()
        : this._doChangeToBackgroundTasks();
    }),
      (this._handleWindowBlur = () => {
        const o = Ke({ category: "ui.blur" });
        this._doChangeToBackgroundTasks(o);
      }),
      (this._handleWindowFocus = () => {
        const o = Ke({ category: "ui.focus" });
        this._doChangeToForegroundTasks(o);
      }),
      (this._handleKeyboardEvent = (o) => {
        BC(this, o);
      }));
  }
  getContext() {
    return this._context;
  }
  isEnabled() {
    return this._isEnabled;
  }
  isPaused() {
    return this._isPaused;
  }
  isRecordingCanvas() {
    return !!this._canvas;
  }
  getOptions() {
    return this._options;
  }
  handleException(t) {
    ($ && D.exception(t), this._options.onError && this._options.onError(t));
  }
  initializeSampling(t) {
    const { errorSampleRate: n, sessionSampleRate: r } = this._options,
      s = n <= 0 && r <= 0;
    if (((this._requiresManualStart = s), !s)) {
      if ((this._initializeSessionForSampling(t), !this.session)) {
        $ && D.exception(new Error("Unable to initialize and create session"));
        return;
      }
      this.session.sampled !== !1 &&
        ((this.recordingMode =
          this.session.sampled === "buffer" && this.session.segmentId === 0
            ? "buffer"
            : "session"),
        $ && D.infoTick(`Starting replay in ${this.recordingMode} mode`),
        this._initializeRecording());
    }
  }
  start() {
    if (this._isEnabled && this.recordingMode === "session") {
      $ && D.log("Recording is already in progress");
      return;
    }
    if (this._isEnabled && this.recordingMode === "buffer") {
      $ && D.log("Buffering is in progress, call `flush()` to save the replay");
      return;
    }
    ($ && D.infoTick("Starting replay in session mode"),
      this._updateUserActivity());
    const t = oo(
      {
        maxReplayDuration: this._options.maxReplayDuration,
        sessionIdleExpire: this.timeouts.sessionIdleExpire,
      },
      {
        stickySession: this._options.stickySession,
        sessionSampleRate: 1,
        allowBuffering: !1,
      },
    );
    ((this.session = t),
      (this.recordingMode = "session"),
      this._initializeRecording());
  }
  startBuffering() {
    if (this._isEnabled) {
      $ && D.log("Buffering is in progress, call `flush()` to save the replay");
      return;
    }
    $ && D.infoTick("Starting replay in buffer mode");
    const t = oo(
      {
        sessionIdleExpire: this.timeouts.sessionIdleExpire,
        maxReplayDuration: this._options.maxReplayDuration,
      },
      {
        stickySession: this._options.stickySession,
        sessionSampleRate: 0,
        allowBuffering: !0,
      },
    );
    ((this.session = t),
      (this.recordingMode = "buffer"),
      this._initializeRecording());
  }
  startRecording() {
    try {
      const t = this._canvas;
      this._stopRecording = ut({
        ...this._recordingOptions,
        ...(this.recordingMode === "buffer"
          ? { checkoutEveryNms: Z1 }
          : this._options._experiments.continuousCheckout && {
              checkoutEveryNms: Math.max(
                36e4,
                this._options._experiments.continuousCheckout,
              ),
            }),
        emit: lx(this),
        ...ux(),
        onMutation: this._onMutationHandler.bind(this),
        ...(t
          ? {
              recordCanvas: t.recordCanvas,
              getCanvasManager: t.getCanvasManager,
              sampling: t.sampling,
              dataURLOptions: t.dataURLOptions,
            }
          : {}),
      });
    } catch (t) {
      this.handleException(t);
    }
  }
  stopRecording() {
    try {
      return (
        this._stopRecording &&
          (this._stopRecording(), (this._stopRecording = void 0)),
        !0
      );
    } catch (t) {
      return (this.handleException(t), !1);
    }
  }
  async stop({ forceFlush: t = !1, reason: n } = {}) {
    if (this._isEnabled) {
      ((this._isEnabled = !1), (this.recordingMode = "buffer"));
      try {
        ($ && D.log(`Stopping Replay${n ? ` triggered by ${n}` : ""}`),
          Xh(),
          this._removeListeners(),
          this.stopRecording(),
          this._debouncedFlush.cancel(),
          t && (await this._flush({ force: !0 })),
          this.eventBuffer?.destroy(),
          (this.eventBuffer = null),
          cR(this));
      } catch (r) {
        this.handleException(r);
      }
    }
  }
  pause() {
    this._isPaused ||
      ((this._isPaused = !0),
      this.stopRecording(),
      $ && D.log("Pausing replay"));
  }
  resume() {
    !this._isPaused ||
      !this._checkSession() ||
      ((this._isPaused = !1),
      this.startRecording(),
      $ && D.log("Resuming replay"));
  }
  async sendBufferedReplayOrFlush({ continueRecording: t = !0 } = {}) {
    if (this.recordingMode === "session") return this.flushImmediate();
    const n = Date.now();
    ($ && D.log("Converting buffer to session"), await this.flushImmediate());
    const r = this.stopRecording();
    !t ||
      !r ||
      (this.recordingMode !== "session" &&
        ((this.recordingMode = "session"),
        this.session &&
          (this._updateUserActivity(n),
          this._updateSessionActivity(n),
          this._maybeSaveSession()),
        this.startRecording()));
  }
  addUpdate(t) {
    const n = t();
    this.recordingMode === "buffer" ||
      !this._isEnabled ||
      (n !== !0 && this._debouncedFlush());
  }
  triggerUserActivity() {
    if ((this._updateUserActivity(), !this._stopRecording)) {
      if (!this._checkSession()) return;
      this.resume();
      return;
    }
    (this.checkAndHandleExpiredSession(), this._updateSessionActivity());
  }
  updateUserActivity() {
    (this._updateUserActivity(), this._updateSessionActivity());
  }
  conditionalFlush() {
    return this.recordingMode === "buffer"
      ? Promise.resolve()
      : this.flushImmediate();
  }
  flush() {
    return this._debouncedFlush();
  }
  flushImmediate() {
    return (this._debouncedFlush(), this._debouncedFlush.flush());
  }
  cancelFlush() {
    this._debouncedFlush.cancel();
  }
  getSessionId(t) {
    if (!(t && this.session?.sampled === !1)) return this.session?.id;
  }
  checkAndHandleExpiredSession() {
    if (
      this._lastActivity &&
      jo(this._lastActivity, this.timeouts.sessionIdlePause) &&
      this.session &&
      this.session.sampled === "session"
    ) {
      this.pause();
      return;
    }
    return !!this._checkSession();
  }
  setInitialState() {
    const t = `${ae.location.pathname}${ae.location.hash}${ae.location.search}`,
      n = `${ae.location.origin}${t}`;
    ((this.performanceEntries = []),
      (this.replayPerformanceEntries = []),
      this._clearContext(),
      (this._context.initialUrl = n),
      (this._context.initialTimestamp = Date.now()),
      this._context.urls.push(n));
  }
  throttledAddEvent(t, n) {
    const r = this._throttledAddEvent(t, n);
    if (r === nm) {
      const s = Ke({ category: "replay.throttled" });
      this.addUpdate(
        () =>
          !Ic(this, {
            type: yC,
            timestamp: s.timestamp || 0,
            data: { tag: "breadcrumb", payload: s, metric: !0 },
          }),
      );
    }
    return r;
  }
  getCurrentRoute() {
    const t = this.lastActiveSpan || fh(),
      n = t && lc(t),
      s = ((n && or(n).data) || {})[uh];
    if (!(!n || !s || !["route", "custom"].includes(s)))
      return or(n).description;
  }
  _initializeRecording() {
    (this.setInitialState(),
      this._updateSessionActivity(),
      (this.eventBuffer = iR({
        useCompression: this._options.useCompression,
        workerUrl: this._options.workerUrl,
      })),
      this._removeListeners(),
      this._addListeners(),
      (this._isEnabled = !0),
      (this._isPaused = !1),
      this.startRecording());
  }
  _initializeSessionForSampling(t) {
    const n = this._options.errorSampleRate > 0,
      r = oo(
        {
          sessionIdleExpire: this.timeouts.sessionIdleExpire,
          maxReplayDuration: this._options.maxReplayDuration,
          previousSessionId: t,
        },
        {
          stickySession: this._options.stickySession,
          sessionSampleRate: this._options.sessionSampleRate,
          allowBuffering: n,
        },
      );
    this.session = r;
  }
  _checkSession() {
    if (!this.session) return !1;
    const t = this.session;
    return qh(t, {
      sessionIdleExpire: this.timeouts.sessionIdleExpire,
      maxReplayDuration: this._options.maxReplayDuration,
    })
      ? (this._refreshSession(t), !1)
      : !0;
  }
  async _refreshSession(t) {
    this._isEnabled &&
      (await this.stop({ reason: "refresh session" }),
      this.initializeSampling(t.id));
  }
  _addListeners() {
    try {
      (ae.document.addEventListener(
        "visibilitychange",
        this._handleVisibilityChange,
      ),
        ae.addEventListener("blur", this._handleWindowBlur),
        ae.addEventListener("focus", this._handleWindowFocus),
        ae.addEventListener("keydown", this._handleKeyboardEvent),
        this.clickDetector && this.clickDetector.addListeners(),
        this._hasInitializedCoreListeners ||
          (ix(this), (this._hasInitializedCoreListeners = !0)));
    } catch (t) {
      this.handleException(t);
    }
    this._performanceCleanupCallback = ZC(this);
  }
  _removeListeners() {
    try {
      (ae.document.removeEventListener(
        "visibilitychange",
        this._handleVisibilityChange,
      ),
        ae.removeEventListener("blur", this._handleWindowBlur),
        ae.removeEventListener("focus", this._handleWindowFocus),
        ae.removeEventListener("keydown", this._handleKeyboardEvent),
        this.clickDetector && this.clickDetector.removeListeners(),
        this._performanceCleanupCallback && this._performanceCleanupCallback());
    } catch (t) {
      this.handleException(t);
    }
  }
  _doChangeToBackgroundTasks(t) {
    !this.session ||
      jh(this.session, {
        maxReplayDuration: this._options.maxReplayDuration,
        sessionIdleExpire: this.timeouts.sessionIdleExpire,
      }) ||
      (t && this._createCustomBreadcrumb(t), this.conditionalFlush());
  }
  _doChangeToForegroundTasks(t) {
    if (!this.session) return;
    if (!this.checkAndHandleExpiredSession()) {
      $ && D.log("Document has become active, but session has expired");
      return;
    }
    t && this._createCustomBreadcrumb(t);
  }
  _updateUserActivity(t = Date.now()) {
    this._lastActivity = t;
  }
  _updateSessionActivity(t = Date.now()) {
    this.session && ((this.session.lastActivity = t), this._maybeSaveSession());
  }
  _createCustomBreadcrumb(t) {
    this.addUpdate(() => {
      this.throttledAddEvent({
        type: z.Custom,
        timestamp: t.timestamp || 0,
        data: { tag: "breadcrumb", payload: t },
      });
    });
  }
  _addPerformanceEntries() {
    let t = zC(this.performanceEntries).concat(this.replayPerformanceEntries);
    if (
      ((this.performanceEntries = []),
      (this.replayPerformanceEntries = []),
      this._requiresManualStart)
    ) {
      const n = this._context.initialTimestamp / 1e3;
      t = t.filter((r) => r.start >= n);
    }
    return Promise.all(xi(this, t));
  }
  _clearContext() {
    (this._context.errorIds.clear(),
      this._context.traceIds.clear(),
      (this._context.urls = []));
  }
  _updateInitialTimestampFromEventBuffer() {
    const { session: t, eventBuffer: n } = this;
    if (!t || !n || this._requiresManualStart || t.segmentId) return;
    const r = n.getEarliestTimestamp();
    r &&
      r < this._context.initialTimestamp &&
      (this._context.initialTimestamp = r);
  }
  _popEventContext() {
    const t = {
      initialTimestamp: this._context.initialTimestamp,
      initialUrl: this._context.initialUrl,
      errorIds: Array.from(this._context.errorIds),
      traceIds: Array.from(this._context.traceIds),
      urls: this._context.urls,
    };
    return (this._clearContext(), t);
  }
  async _runFlush() {
    const t = this.getSessionId();
    if (!this.session || !this.eventBuffer || !t) {
      $ && D.error("No session or eventBuffer found to flush.");
      return;
    }
    if (
      (await this._addPerformanceEntries(),
      !!this.eventBuffer?.hasEvents &&
        (await ox(this), !!this.eventBuffer && t === this.getSessionId()))
    )
      try {
        this._updateInitialTimestampFromEventBuffer();
        const n = Date.now();
        if (
          n - this._context.initialTimestamp >
          this._options.maxReplayDuration + 3e4
        )
          throw new Error("Session is too long, not sending replay");
        const r = this._popEventContext(),
          s = this.session.segmentId++;
        this._maybeSaveSession();
        const i = await this.eventBuffer.finish();
        await tm({
          replayId: t,
          recordingData: i,
          segmentId: s,
          eventContext: r,
          session: this.session,
          timestamp: n,
          onError: (o) => this.handleException(o),
        });
      } catch (n) {
        (this.handleException(n), this.stop({ reason: "sendReplay" }));
        const r = Ge();
        if (r) {
          const s = n instanceof Cc ? "ratelimit_backoff" : "send_error";
          r.recordDroppedEvent(s, "replay");
        }
      }
  }
  async _flush({ force: t = !1 } = {}) {
    if (!this._isEnabled && !t) return;
    if (!this.checkAndHandleExpiredSession()) {
      $ && D.error("Attempting to finish replay event after session expired.");
      return;
    }
    if (!this.session) return;
    const n = this.session.started,
      s = Date.now() - n;
    this._debouncedFlush.cancel();
    const i = s < this._options.minReplayDuration,
      o = s > this._options.maxReplayDuration + 5e3;
    if (i || o) {
      ($ &&
        D.log(
          `Session duration (${Math.floor(s / 1e3)}s) is too ${i ? "short" : "long"}, not sending replay.`,
        ),
        i && this._debouncedFlush());
      return;
    }
    const a = this.eventBuffer;
    a &&
      this.session.segmentId === 0 &&
      !a.hasCheckout &&
      $ &&
      D.log("Flushing initial segment without checkout.");
    const c = !!this._flushLock;
    this._flushLock || (this._flushLock = this._runFlush());
    try {
      await this._flushLock;
    } catch (u) {
      this.handleException(u);
    } finally {
      ((this._flushLock = void 0), c && this._debouncedFlush());
    }
  }
  _maybeSaveSession() {
    this.session && this._options.stickySession && wc(this.session);
  }
  _onMutationHandler(t) {
    const { ignoreMutations: n } = this._options._experiments;
    if (
      n?.length &&
      t.some((a) => {
        const c = px(a.target),
          u = n.join(",");
        return c?.matches(u);
      })
    )
      return !1;
    const r = t.length,
      s = this._options.mutationLimit,
      i = this._options.mutationBreadcrumbLimit,
      o = s && r > s;
    if (r > i || o) {
      const a = Ke({
        category: "replay.mutations",
        data: { count: r, limit: o },
      });
      this._createCustomBreadcrumb(a);
    }
    return o
      ? (this.stop({
          reason: "mutationLimit",
          forceFlush: this.recordingMode === "session",
        }),
        !1)
      : !0;
  }
}
function $n(e, t) {
  return [...e, ...t].join(",");
}
function Ex({ mask: e, unmask: t, block: n, unblock: r, ignore: s }) {
  const i = ["base", "iframe[srcdoc]:not([src])"],
    o = $n(e, [".sentry-mask", "[data-sentry-mask]"]),
    a = $n(t, []);
  return {
    maskTextSelector: o,
    unmaskTextSelector: a,
    blockSelector: $n(n, [".sentry-block", "[data-sentry-block]", ...i]),
    unblockSelector: $n(r, []),
    ignoreSelector: $n(s, [
      ".sentry-ignore",
      "[data-sentry-ignore]",
      'input[type="file"]',
    ]),
  };
}
function vx({
  el: e,
  key: t,
  maskAttributes: n,
  maskAllText: r,
  privacyOptions: s,
  value: i,
}) {
  return !r || (s.unmaskTextSelector && e.matches(s.unmaskTextSelector))
    ? i
    : n.includes(t) ||
        (t === "value" &&
          e.tagName === "INPUT" &&
          ["submit", "button"].includes(e.getAttribute("type") || ""))
      ? i.replace(/[\S]/g, "*")
      : i;
}
const Zl =
    'img,image,svg,video,object,picture,embed,map,audio,link[rel="icon"],link[rel="apple-touch-icon"]',
  Tx = ["content-length", "content-type", "accept"];
let Ql = !1;
const wx = (e) => new Ix(e);
class Ix {
  constructor({
    flushMinDelay: t = K1,
    flushMaxDelay: n = J1,
    minReplayDuration: r = rk,
    maxReplayDuration: s = Ml,
    stickySession: i = !0,
    useCompression: o = !0,
    workerUrl: a,
    _experiments: c = {},
    maskAllText: u = !0,
    maskAllInputs: d = !0,
    blockAllMedia: l = !0,
    mutationBreadcrumbLimit: p = 750,
    mutationLimit: f = 1e4,
    slowClickTimeout: h = 7e3,
    slowClickIgnoreSelectors: m = [],
    networkDetailAllowUrls: g = [],
    networkDetailDenyUrls: _ = [],
    networkCaptureBodies: y = !0,
    networkRequestHeaders: M = [],
    networkResponseHeaders: w = [],
    mask: A = [],
    maskAttributes: C = ["title", "placeholder", "aria-label"],
    unmask: E = [],
    block: I = [],
    unblock: b = [],
    ignore: k = [],
    maskFn: O,
    beforeAddRecordingEvent: v,
    beforeErrorSampling: x,
    onError: U,
  } = {}) {
    this.name = "Replay";
    const q = Ex({ mask: A, unmask: E, block: I, unblock: b, ignore: k });
    if (
      ((this._recordingOptions = {
        maskAllInputs: d,
        maskAllText: u,
        maskInputOptions: { password: !0 },
        maskTextFn: O,
        maskInputFn: O,
        maskAttributeFn: (K, T, P) =>
          vx({
            maskAttributes: C,
            maskAllText: u,
            privacyOptions: q,
            key: K,
            value: T,
            el: P,
          }),
        ...q,
        slimDOMOptions: "all",
        inlineStylesheet: !0,
        inlineImages: !1,
        collectFonts: !0,
        errorHandler: (K) => {
          try {
            K.__rrweb__ = !0;
          } catch {}
        },
        recordCrossOriginIframes: !!c.recordCrossOriginIframes,
      }),
      (this._initialOptions = {
        flushMinDelay: t,
        flushMaxDelay: n,
        minReplayDuration: Math.min(r, sk),
        maxReplayDuration: Math.min(s, Ml),
        stickySession: i,
        useCompression: o,
        workerUrl: a,
        blockAllMedia: l,
        maskAllInputs: d,
        maskAllText: u,
        mutationBreadcrumbLimit: p,
        mutationLimit: f,
        slowClickTimeout: h,
        slowClickIgnoreSelectors: m,
        networkDetailAllowUrls: g,
        networkDetailDenyUrls: _,
        networkCaptureBodies: y,
        networkRequestHeaders: ed(M),
        networkResponseHeaders: ed(w),
        beforeAddRecordingEvent: v,
        beforeErrorSampling: x,
        onError: U,
        _experiments: c,
      }),
      this._initialOptions.blockAllMedia &&
        (this._recordingOptions.blockSelector = this._recordingOptions
          .blockSelector
          ? `${this._recordingOptions.blockSelector},${Zl}`
          : Zl),
      this._isInitialized && xl())
    )
      throw new Error(
        "Multiple Sentry Session Replay instances are not supported",
      );
    this._isInitialized = !0;
  }
  get _isInitialized() {
    return Ql;
  }
  set _isInitialized(t) {
    Ql = t;
  }
  afterAllSetup(t) {
    !xl() || this._replay || (this._setup(t), this._initialize(t));
  }
  start() {
    this._replay && this._replay.start();
  }
  startBuffering() {
    this._replay && this._replay.startBuffering();
  }
  stop() {
    return this._replay
      ? this._replay.stop({
          forceFlush: this._replay.recordingMode === "session",
        })
      : Promise.resolve();
  }
  flush(t) {
    return this._replay
      ? this._replay.isEnabled()
        ? this._replay.sendBufferedReplayOrFlush(t)
        : (this._replay.start(), Promise.resolve())
      : Promise.resolve();
  }
  getReplayId(t) {
    if (this._replay?.isEnabled()) return this._replay.getSessionId(t);
  }
  getRecordingMode() {
    if (this._replay?.isEnabled()) return this._replay.recordingMode;
  }
  _initialize(t) {
    this._replay &&
      (this._maybeLoadFromReplayCanvasIntegration(t),
      this._replay.initializeSampling());
  }
  _setup(t) {
    const n = kx(this._initialOptions, t);
    this._replay = new bx({
      options: n,
      recordingOptions: this._recordingOptions,
    });
  }
  _maybeLoadFromReplayCanvasIntegration(t) {
    try {
      const n = t.getIntegrationByName("ReplayCanvas");
      if (!n) return;
      this._replay._canvas = n.getOptions();
    } catch {}
  }
}
function kx(e, t) {
  const n = t.getOptions(),
    r = { sessionSampleRate: 0, errorSampleRate: 0, ...e },
    s = El(n.replaysSessionSampleRate),
    i = El(n.replaysOnErrorSampleRate);
  return (
    s == null &&
      i == null &&
      sc(() => {
        console.warn(
          "Replay is disabled because neither `replaysSessionSampleRate` nor `replaysOnErrorSampleRate` are set.",
        );
      }),
    s != null && (r.sessionSampleRate = s),
    i != null && (r.errorSampleRate = i),
    r
  );
}
function ed(e) {
  return [...Tx, ...e.map((t) => t.toLowerCase())];
}
function Cx() {
  return Ge()?.getIntegrationByName("Replay");
}
var Rx = Object.defineProperty,
  xx = (e, t, n) =>
    t in e
      ? Rx(e, t, { enumerable: !0, configurable: !0, writable: !0, value: n })
      : (e[t] = n),
  td = (e, t, n) => xx(e, typeof t != "symbol" ? t + "" : t, n);
class Ax {
  constructor() {
    (td(this, "idNodeMap", new Map()), td(this, "nodeMetaMap", new WeakMap()));
  }
  getId(t) {
    return t ? (this.getMeta(t)?.id ?? -1) : -1;
  }
  getNode(t) {
    return this.idNodeMap.get(t) || null;
  }
  getIds() {
    return Array.from(this.idNodeMap.keys());
  }
  getMeta(t) {
    return this.nodeMetaMap.get(t) || null;
  }
  removeNodeFromMap(t) {
    const n = this.getId(t);
    (this.idNodeMap.delete(n),
      t.childNodes && t.childNodes.forEach((r) => this.removeNodeFromMap(r)));
  }
  has(t) {
    return this.idNodeMap.has(t);
  }
  hasNode(t) {
    return this.nodeMetaMap.has(t);
  }
  add(t, n) {
    const r = n.id;
    (this.idNodeMap.set(r, t), this.nodeMetaMap.set(t, n));
  }
  replace(t, n) {
    const r = this.getNode(t);
    if (r) {
      const s = this.nodeMetaMap.get(r);
      s && this.nodeMetaMap.set(n, s);
    }
    this.idNodeMap.set(t, n);
  }
  reset() {
    ((this.idNodeMap = new Map()), (this.nodeMetaMap = new WeakMap()));
  }
}
function Mx() {
  return new Ax();
}
function Nx(e, t) {
  for (let n = e.classList.length; n--;) {
    const r = e.classList[n];
    if (t.test(r)) return !0;
  }
  return !1;
}
function Vo(e, t, n = 1 / 0, r = 0) {
  return !e || e.nodeType !== e.ELEMENT_NODE || r > n
    ? -1
    : t(e)
      ? r
      : Vo(e.parentNode, t, n, r + 1);
}
function nd(e, t) {
  return (n) => {
    const r = n;
    if (r === null) return !1;
    try {
      if (e) {
        if (typeof e == "string") {
          if (r.matches(`.${e}`)) return !0;
        } else if (Nx(r, e)) return !0;
      }
      return !!(t && r.matches(t));
    } catch {
      return !1;
    }
  };
}
const nn = `Please stop import mirror directly. Instead of that,\r
now you can use replayer.getMirror() to access the mirror instance of a replayer,\r
or you can use record.mirror to access the mirror instance during recording.`;
let rd = {
  map: {},
  getId() {
    return (console.error(nn), -1);
  },
  getNode() {
    return (console.error(nn), null);
  },
  removeNodeFromMap() {
    console.error(nn);
  },
  has() {
    return (console.error(nn), !1);
  },
  reset() {
    console.error(nn);
  },
};
typeof window < "u" &&
  window.Proxy &&
  window.Reflect &&
  (rd = new Proxy(rd, {
    get(e, t, n) {
      return (t === "map" && console.error(nn), Reflect.get(e, t, n));
    },
  }));
function Rc(e, t, n, r, s = window) {
  const i = s.Object.getOwnPropertyDescriptor(e, t);
  return (
    s.Object.defineProperty(
      e,
      t,
      r
        ? n
        : {
            set(o) {
              (sm(() => {
                n.set.call(this, o);
              }, 0),
                i && i.set && i.set.call(this, o));
            },
          },
    ),
    () => Rc(e, t, i || {}, !0)
  );
}
function xc(e, t, n) {
  try {
    if (!(t in e)) return () => {};
    const r = e[t],
      s = n(r);
    return (
      typeof s == "function" &&
        ((s.prototype = s.prototype || {}),
        Object.defineProperties(s, {
          __rrweb_original__: { enumerable: !1, value: r },
        })),
      (e[t] = s),
      () => {
        e[t] = r;
      }
    );
  } catch {
    return () => {};
  }
}
Date.now().toString();
function Ox(e) {
  if (!e) return null;
  try {
    return e.nodeType === e.ELEMENT_NODE ? e : e.parentElement;
  } catch {
    return null;
  }
}
function Mi(e, t, n, r, s) {
  if (!e) return !1;
  const i = Ox(e);
  if (!i) return !1;
  const o = nd(t, n),
    a = Vo(i, o);
  let c = -1;
  return a < 0
    ? !1
    : (r && (c = Vo(i, nd(null, r))), a > -1 && c < 0 ? !0 : a < c);
}
const sd = {};
function rm(e) {
  const t = sd[e];
  if (t) return t;
  const n = window.document;
  let r = window[e];
  if (n && typeof n.createElement == "function")
    try {
      const s = n.createElement("iframe");
      ((s.hidden = !0), n.head.appendChild(s));
      const i = s.contentWindow;
      (i && i[e] && (r = i[e]), n.head.removeChild(s));
    } catch {}
  return (sd[e] = r.bind(window));
}
function Ot(...e) {
  return rm("requestAnimationFrame")(...e);
}
function sm(...e) {
  return rm("setTimeout")(...e);
}
var wn = ((e) => (
  (e[(e["2D"] = 0)] = "2D"),
  (e[(e.WebGL = 1)] = "WebGL"),
  (e[(e.WebGL2 = 2)] = "WebGL2"),
  e
))(wn || {});
let gs;
function Lx(e) {
  gs = e;
}
const ao = (e) =>
  gs
    ? (...n) => {
        try {
          return e(...n);
        } catch (r) {
          if (gs && gs(r) === !0) return () => {};
          throw r;
        }
      }
    : e;
var cn = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",
  $x = typeof Uint8Array > "u" ? [] : new Uint8Array(256);
for (var Qr = 0; Qr < cn.length; Qr++) $x[cn.charCodeAt(Qr)] = Qr;
var Dx = function (e) {
  var t = new Uint8Array(e),
    n,
    r = t.length,
    s = "";
  for (n = 0; n < r; n += 3)
    ((s += cn[t[n] >> 2]),
      (s += cn[((t[n] & 3) << 4) | (t[n + 1] >> 4)]),
      (s += cn[((t[n + 1] & 15) << 2) | (t[n + 2] >> 6)]),
      (s += cn[t[n + 2] & 63]));
  return (
    r % 3 === 2
      ? (s = s.substring(0, s.length - 1) + "=")
      : r % 3 === 1 && (s = s.substring(0, s.length - 2) + "=="),
    s
  );
};
const id = new Map();
function Px(e, t) {
  let n = id.get(e);
  return (
    n || ((n = new Map()), id.set(e, n)),
    n.has(t) || n.set(t, []),
    n.get(t)
  );
}
const im = (e, t, n) => {
  if (!e || !(am(e, t) || typeof e == "object")) return;
  const r = e.constructor.name,
    s = Px(n, r);
  let i = s.indexOf(e);
  return (i === -1 && ((i = s.length), s.push(e)), i);
};
function _s(e, t, n) {
  if (e instanceof Array) return e.map((r) => _s(r, t, n));
  if (e === null) return e;
  if (
    e instanceof Float32Array ||
    e instanceof Float64Array ||
    e instanceof Int32Array ||
    e instanceof Uint32Array ||
    e instanceof Uint8Array ||
    e instanceof Uint16Array ||
    e instanceof Int16Array ||
    e instanceof Int8Array ||
    e instanceof Uint8ClampedArray
  )
    return { rr_type: e.constructor.name, args: [Object.values(e)] };
  if (e instanceof ArrayBuffer) {
    const r = e.constructor.name,
      s = Dx(e);
    return { rr_type: r, base64: s };
  } else {
    if (e instanceof DataView)
      return {
        rr_type: e.constructor.name,
        args: [_s(e.buffer, t, n), e.byteOffset, e.byteLength],
      };
    if (e instanceof HTMLImageElement) {
      const r = e.constructor.name,
        { src: s } = e;
      return { rr_type: r, src: s };
    } else if (e instanceof HTMLCanvasElement) {
      const r = "HTMLImageElement",
        s = e.toDataURL();
      return { rr_type: r, src: s };
    } else {
      if (e instanceof ImageData)
        return {
          rr_type: e.constructor.name,
          args: [_s(e.data, t, n), e.width, e.height],
        };
      if (am(e, t) || typeof e == "object") {
        const r = e.constructor.name,
          s = im(e, t, n);
        return { rr_type: r, index: s };
      }
    }
  }
  return e;
}
const om = (e, t, n) => e.map((r) => _s(r, t, n)),
  am = (e, t) =>
    !![
      "WebGLActiveInfo",
      "WebGLBuffer",
      "WebGLFramebuffer",
      "WebGLProgram",
      "WebGLRenderbuffer",
      "WebGLShader",
      "WebGLShaderPrecisionFormat",
      "WebGLTexture",
      "WebGLUniformLocation",
      "WebGLVertexArrayObject",
      "WebGLVertexArrayObjectOES",
    ]
      .filter((s) => typeof t[s] == "function")
      .find((s) => e instanceof t[s]);
function Fx(e, t, n, r, s) {
  const i = [],
    o = Object.getOwnPropertyNames(t.CanvasRenderingContext2D.prototype);
  for (const a of o)
    try {
      if (typeof t.CanvasRenderingContext2D.prototype[a] != "function")
        continue;
      const c = xc(t.CanvasRenderingContext2D.prototype, a, function (u) {
        return function (...d) {
          return (
            Mi(this.canvas, n, r, s, !0) ||
              sm(() => {
                const l = om(d, t, this);
                e(this.canvas, { type: wn["2D"], property: a, args: l });
              }, 0),
            u.apply(this, d)
          );
        };
      });
      i.push(c);
    } catch {
      const c = Rc(t.CanvasRenderingContext2D.prototype, a, {
        set(u) {
          e(this.canvas, {
            type: wn["2D"],
            property: a,
            args: [u],
            setter: !0,
          });
        },
      });
      i.push(c);
    }
  return () => {
    i.forEach((a) => a());
  };
}
function Bx(e) {
  return e === "experimental-webgl" ? "webgl" : e;
}
function od(e, t, n, r, s) {
  const i = [];
  try {
    const o = xc(e.HTMLCanvasElement.prototype, "getContext", function (a) {
      return function (c, ...u) {
        if (!Mi(this, t, n, r, !0)) {
          const d = Bx(c);
          if (
            ("__context" in this || (this.__context = d),
            s && ["webgl", "webgl2"].includes(d))
          )
            if (u[0] && typeof u[0] == "object") {
              const l = u[0];
              l.preserveDrawingBuffer || (l.preserveDrawingBuffer = !0);
            } else u.splice(0, 1, { preserveDrawingBuffer: !0 });
        }
        return a.apply(this, [c, ...u]);
      };
    });
    i.push(o);
  } catch {
    console.error("failed to patch HTMLCanvasElement.prototype.getContext");
  }
  return () => {
    i.forEach((o) => o());
  };
}
function ad(e, t, n, r, s, i, o, a) {
  const c = [],
    u = Object.getOwnPropertyNames(e);
  for (const d of u)
    if (
      ![
        "isContextLost",
        "canvas",
        "drawingBufferWidth",
        "drawingBufferHeight",
      ].includes(d)
    )
      try {
        if (typeof e[d] != "function") continue;
        const l = xc(e, d, function (p) {
          return function (...f) {
            const h = p.apply(this, f);
            if (
              (im(h, a, this),
              "tagName" in this.canvas && !Mi(this.canvas, r, s, i, !0))
            ) {
              const m = om(f, a, this),
                g = { type: t, property: d, args: m };
              n(this.canvas, g);
            }
            return h;
          };
        });
        c.push(l);
      } catch {
        const l = Rc(e, d, {
          set(p) {
            n(this.canvas, { type: t, property: d, args: [p], setter: !0 });
          },
        });
        c.push(l);
      }
  return c;
}
function Ux(e, t, n, r, s, i) {
  const o = [];
  return (
    o.push(
      ...ad(t.WebGLRenderingContext.prototype, wn.WebGL, e, n, r, s, i, t),
    ),
    typeof t.WebGL2RenderingContext < "u" &&
      o.push(
        ...ad(t.WebGL2RenderingContext.prototype, wn.WebGL2, e, n, r, s, i, t),
      ),
    () => {
      o.forEach((a) => a());
    }
  );
}
const Hx =
  'for(var e="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",t="undefined"==typeof Uint8Array?[]:new Uint8Array(256),a=0;a<64;a++)t[e.charCodeAt(a)]=a;var n=function(t){var a,n=new Uint8Array(t),r=n.length,s="";for(a=0;a<r;a+=3)s+=e[n[a]>>2],s+=e[(3&n[a])<<4|n[a+1]>>4],s+=e[(15&n[a+1])<<2|n[a+2]>>6],s+=e[63&n[a+2]];return r%3==2?s=s.substring(0,s.length-1)+"=":r%3==1&&(s=s.substring(0,s.length-2)+"=="),s};const r=new Map,s=new Map;const i=self;i.onmessage=async function(e){if(!("OffscreenCanvas"in globalThis))return i.postMessage({id:e.data.id});{const{id:t,bitmap:a,width:o,height:f,maxCanvasSize:c,dataURLOptions:g}=e.data,u=async function(e,t,a){const r=e+"-"+t;if("OffscreenCanvas"in globalThis){if(s.has(r))return s.get(r);const i=new OffscreenCanvas(e,t);i.getContext("2d");const o=await i.convertToBlob(a),f=await o.arrayBuffer(),c=n(f);return s.set(r,c),c}return""}(o,f,g),[h,d]=function(e,t,a){if(!a)return[e,t];const[n,r]=a;if(e<=n&&t<=r)return[e,t];let s=e,i=t;return s>n&&(i=Math.floor(n*t/e),s=n),i>r&&(s=Math.floor(r*e/t),i=r),[s,i]}(o,f,c),l=new OffscreenCanvas(h,d),w=l.getContext("bitmaprenderer"),p=h===o&&d===f?a:await createImageBitmap(a,{resizeWidth:h,resizeHeight:d,resizeQuality:"low"});w?.transferFromImageBitmap(p),a.close();const y=await l.convertToBlob(g),v=y.type,b=await y.arrayBuffer(),m=n(b);if(p.close(),!r.has(t)&&await u===m)return r.set(t,m),i.postMessage({id:t});if(r.get(t)===m)return i.postMessage({id:t});i.postMessage({id:t,type:v,base64:m,width:o,height:f}),r.set(t,m)}};';
function Wx() {
  const e = new Blob([Hx]);
  return URL.createObjectURL(e);
}
class zx {
  constructor(t) {
    ((this.pendingCanvasMutations = new Map()),
      (this.rafStamps = { latestId: 0, invokeId: null }),
      (this.shadowDoms = new Set()),
      (this.windowsSet = new WeakSet()),
      (this.windows = []),
      (this.restoreHandlers = []),
      (this.frozen = !1),
      (this.locked = !1),
      (this.snapshotInProgressMap = new Map()),
      (this.worker = null),
      (this.lastSnapshotTime = 0),
      (this.processMutation = (a, c) => {
        (((this.rafStamps.invokeId &&
          this.rafStamps.latestId !== this.rafStamps.invokeId) ||
          !this.rafStamps.invokeId) &&
          (this.rafStamps.invokeId = this.rafStamps.latestId),
          this.pendingCanvasMutations.has(a) ||
            this.pendingCanvasMutations.set(a, []),
          this.pendingCanvasMutations.get(a).push(c));
      }));
    const {
      enableManualSnapshot: n,
      sampling: r = "all",
      win: s,
      recordCanvas: i,
      errorHandler: o,
    } = t;
    ((t.sampling = r),
      (this.mutationCb = t.mutationCb),
      (this.mirror = t.mirror),
      (this.options = t),
      o && Lx(o),
      ((i && typeof r == "number") || n) &&
        (this.worker = this.initFPSWorker()),
      this.addWindow(s),
      !n &&
        ao(() => {
          (i &&
            r === "all" &&
            (this.startRAFTimestamping(),
            this.startPendingCanvasMutationFlusher()),
            i && typeof r == "number" && this.initCanvasFPSObserver());
        })());
  }
  reset() {
    (this.pendingCanvasMutations.clear(),
      this.restoreHandlers.forEach((t) => {
        try {
          t();
        } catch {}
      }),
      (this.restoreHandlers = []),
      (this.windowsSet = new WeakSet()),
      (this.windows = []),
      (this.shadowDoms = new Set()),
      this.worker?.terminate(),
      (this.worker = null),
      (this.snapshotInProgressMap = new Map()));
  }
  freeze() {
    this.frozen = !0;
  }
  unfreeze() {
    this.frozen = !1;
  }
  lock() {
    this.locked = !0;
  }
  unlock() {
    this.locked = !1;
  }
  addWindow(t) {
    const {
      sampling: n = "all",
      blockClass: r,
      blockSelector: s,
      unblockSelector: i,
      recordCanvas: o,
      enableManualSnapshot: a,
    } = this.options;
    if (!this.windowsSet.has(t)) {
      if (a) {
        (this.windowsSet.add(t), this.windows.push(new WeakRef(t)));
        return;
      }
      (ao(() => {
        if (
          (o && n === "all" && this.initCanvasMutationObserver(t, r, s, i),
          o && typeof n == "number")
        ) {
          const c = od(t, r, s, i, !0);
          this.restoreHandlers.push(() => {
            c();
          });
        }
      })(),
        this.windowsSet.add(t),
        this.windows.push(new WeakRef(t)));
    }
  }
  addShadowRoot(t) {
    this.shadowDoms.add(new WeakRef(t));
  }
  resetShadowRoots() {
    this.shadowDoms = new Set();
  }
  snapshot(t, n) {
    if (n?.skipRequestAnimationFrame) {
      this.takeSnapshot(performance.now(), !0, t);
      return;
    }
    Ot((r) => this.takeSnapshot(r, !0, t));
  }
  initFPSWorker() {
    const t = new Worker(Wx());
    return (
      (t.onmessage = (n) => {
        const r = n.data,
          { id: s } = r;
        if ((this.snapshotInProgressMap.set(s, !1), !("base64" in r))) return;
        const { base64: i, type: o, width: a, height: c } = r;
        this.mutationCb({
          id: s,
          type: wn["2D"],
          commands: [
            { property: "clearRect", args: [0, 0, a, c] },
            {
              property: "drawImage",
              args: [
                {
                  rr_type: "ImageBitmap",
                  args: [
                    {
                      rr_type: "Blob",
                      data: [{ rr_type: "ArrayBuffer", base64: i }],
                      type: o,
                    },
                  ],
                },
                0,
                0,
                a,
                c,
              ],
            },
          ],
        });
      }),
      t
    );
  }
  initCanvasFPSObserver() {
    let t;
    if (!this.windows.length && !this.shadowDoms.size) return;
    const n = (r) => {
      (this.takeSnapshot(r, !1), (t = Ot(n)));
    };
    ((t = Ot(n)),
      this.restoreHandlers.push(() => {
        t && cancelAnimationFrame(t);
      }));
  }
  initCanvasMutationObserver(t, n, r, s) {
    const i = od(t, n, r, s, !1),
      o = Fx(this.processMutation.bind(this), t, n, r, s),
      a = Ux(this.processMutation.bind(this), t, n, r, s, this.mirror);
    this.restoreHandlers.push(() => {
      (i(), o(), a());
    });
  }
  getCanvasElements(t, n, r) {
    const s = [],
      i = (o) => {
        o.querySelectorAll("canvas").forEach((a) => {
          Mi(a, t, n, r) || s.push(a);
        });
      };
    for (const o of this.windows) {
      const a = o.deref();
      let c;
      try {
        c = a && a.document;
      } catch {}
      c && i(c);
    }
    for (const o of this.shadowDoms) {
      const a = o.deref();
      a && i(a);
    }
    return s;
  }
  takeSnapshot(t, n, r) {
    const {
        sampling: s,
        blockClass: i,
        blockSelector: o,
        unblockSelector: a,
        dataURLOptions: c,
        maxCanvasSize: u,
      } = this.options,
      l = 1e3 / (s === "all" ? 2 : s || 2);
    return this.lastSnapshotTime && t - this.lastSnapshotTime < l
      ? !1
      : ((this.lastSnapshotTime = t),
        (r ? [r] : this.getCanvasElements(i, o, a)).forEach((h) => {
          const m = this.mirror.getId(h);
          if (!(
            !this.mirror.hasNode(h) ||
            !h.width ||
            !h.height ||
            this.snapshotInProgressMap.get(m)
          )) {
            if (
              (this.snapshotInProgressMap.set(m, !0),
              !n && ["webgl", "webgl2"].includes(h.__context))
            ) {
              const g = h.getContext(h.__context);
              g?.getContextAttributes()?.preserveDrawingBuffer === !1 &&
                g.clear(g.COLOR_BUFFER_BIT);
            }
            createImageBitmap(h)
              .then((g) => {
                this.worker?.postMessage(
                  {
                    id: m,
                    bitmap: g,
                    width: h.width,
                    height: h.height,
                    dataURLOptions: c,
                    maxCanvasSize: u,
                  },
                  [g],
                );
              })
              .catch((g) => {
                ao(() => {
                  throw (this.snapshotInProgressMap.delete(m), g);
                })();
              });
          }
        }),
        !0);
  }
  startPendingCanvasMutationFlusher() {
    Ot(() => this.flushPendingCanvasMutations());
  }
  startRAFTimestamping() {
    const t = (n) => {
      ((this.rafStamps.latestId = n), Ot(t));
    };
    Ot(t);
  }
  flushPendingCanvasMutations() {
    (this.pendingCanvasMutations.forEach((t, n) => {
      const r = this.mirror.getId(n);
      this.flushPendingCanvasMutationFor(n, r);
    }),
      Ot(() => this.flushPendingCanvasMutations()));
  }
  flushPendingCanvasMutationFor(t, n) {
    if (this.frozen || this.locked) return;
    const r = this.pendingCanvasMutations.get(t);
    if (!r || n === -1) return;
    const s = r.map((o) => {
        const { type: a, ...c } = o;
        return c;
      }),
      { type: i } = r[0];
    (this.mutationCb({ id: n, type: i, commands: s }),
      this.pendingCanvasMutations.delete(t));
  }
}
try {
  if (Array.from([1], (e) => e * 2)[0] !== 2) {
    const e = document.createElement("iframe");
    (document.body.appendChild(e),
      (Array.from = e.contentWindow?.Array.from || Array.from),
      document.body.removeChild(e));
  }
} catch (e) {
  console.debug("Unable to override Array.from", e);
}
Mx();
var cd;
(function (e) {
  ((e[(e.NotStarted = 0)] = "NotStarted"),
    (e[(e.Running = 1)] = "Running"),
    (e[(e.Stopped = 2)] = "Stopped"));
})(cd || (cd = {}));
const ud = {
    low: {
      sampling: { canvas: 1 },
      dataURLOptions: { type: "image/webp", quality: 0.25 },
    },
    medium: {
      sampling: { canvas: 2 },
      dataURLOptions: { type: "image/webp", quality: 0.4 },
    },
    high: {
      sampling: { canvas: 4 },
      dataURLOptions: { type: "image/webp", quality: 0.5 },
    },
  },
  jx = "ReplayCanvas",
  es = 1280,
  qx = (e = {}) => {
    const [t, n] = e.maxCanvasSize || [],
      r = {
        quality: e.quality || "medium",
        enableManualSnapshot: e.enableManualSnapshot,
        maxCanvasSize: [t ? Math.min(t, es) : es, n ? Math.min(n, es) : es],
      };
    let s;
    const i = new Promise((o) => (s = o));
    return {
      name: jx,
      getOptions() {
        const { quality: o, enableManualSnapshot: a, maxCanvasSize: c } = r;
        return {
          enableManualSnapshot: a,
          recordCanvas: !0,
          getCanvasManager: (u) => {
            const d = new zx({
              ...u,
              enableManualSnapshot: a,
              maxCanvasSize: c,
              errorHandler: (l) => {
                try {
                  typeof l == "object" && (l.__rrweb__ = !0);
                } catch {}
              },
            });
            return (s(d), d);
          },
          ...(ud[o] || ud.medium),
        };
      },
      async snapshot(o, a) {
        (await i).snapshot(o, a);
      },
    };
  },
  Gx = qx,
  ld = new WeakMap(),
  co = new Map(),
  Ac = {
    traceFetch: !0,
    traceXHR: !0,
    enableHTTPTimings: !0,
    trackFetchStreamPerformance: !1,
  };
function cm(e, t) {
  const {
      traceFetch: n,
      traceXHR: r,
      trackFetchStreamPerformance: s,
      shouldCreateSpanForRequest: i,
      enableHTTPTimings: o,
      tracePropagationTargets: a,
      onRequestSpanStart: c,
    } = { ...Ac, ...t },
    u = typeof i == "function" ? i : (f) => !0,
    d = (f) => Yx(f, a),
    l = {},
    p = e.getOptions().propagateTraceparent;
  (n &&
    (e.addEventProcessor(
      (f) => (
        f.type === "transaction" &&
          f.spans &&
          f.spans.forEach((h) => {
            if (h.op === "http.client") {
              const m = co.get(h.span_id);
              m && ((h.timestamp = m / 1e3), co.delete(h.span_id));
            }
          }),
        f
      ),
    ),
    s &&
      hE((f) => {
        if (f.response) {
          const h = ld.get(f.response);
          h && f.endTimestamp && co.set(h, f.endTimestamp);
        }
      }),
    xa((f) => {
      const h = Hb(f, u, d, l, { propagateTraceparent: p });
      if (
        (f.response &&
          f.fetchData.__span &&
          ld.set(f.response, f.fetchData.__span),
        h)
      ) {
        const m = um(f.fetchData.url),
          g = m ? ln(m).host : void 0;
        (h.setAttributes({ "http.url": m, "server.address": g }),
          o && dd(h),
          c?.(h, { headers: f.headers }));
      }
    })),
    r &&
      Qa((f) => {
        const h = Xx(f, u, d, l, p);
        if (h) {
          o && dd(h);
          let m;
          try {
            m = new Headers(f.xhr.__sentry_xhr_v3__?.request_headers);
          } catch {}
          c?.(h, { headers: m });
        }
      }));
}
function Vx(e) {
  return (
    e.entryType === "resource" &&
    "initiatorType" in e &&
    typeof e.nextHopProtocol == "string" &&
    (e.initiatorType === "fetch" || e.initiatorType === "xmlhttprequest")
  );
}
function dd(e) {
  const { url: t } = ee(e).data;
  if (!t || typeof t != "string") return;
  const n = Xt("resource", ({ entries: r }) => {
    r.forEach((s) => {
      Vx(s) && s.name.endsWith(t) && (e.setAttributes(Np(s)), setTimeout(n));
    });
  });
}
function Yx(e, t) {
  const n = ii();
  if (n) {
    let r, s;
    try {
      ((r = new URL(e, n)), (s = new URL(n).origin));
    } catch {
      return !1;
    }
    const i = r.origin === s;
    return t ? it(r.toString(), t) || (i && it(r.pathname, t)) : i;
  } else {
    const r = !!e.match(/^\/(?!\/)/);
    return t ? it(e, t) : r;
  }
}
function Xx(e, t, n, r, s) {
  const i = e.xhr,
    o = i?.[st];
  if (!i || i.__sentry_own_request__ || !o) return;
  const { url: a, method: c } = o,
    u = Je() && t(a);
  if (e.endTimestamp && u) {
    const g = i.__sentry_xhr_span_id__;
    if (!g) return;
    const _ = r[g];
    _ &&
      o.status_code !== void 0 &&
      (er(_, o.status_code), _.end(), delete r[g]);
    return;
  }
  const d = um(a),
    l = ln(d || a),
    p = Cf(a),
    f = !!Pe(),
    h =
      u && f
        ? yr({
            name: `${c} ${p}`,
            attributes: {
              url: a,
              type: "xhr",
              "http.method": c,
              "http.url": d,
              "server.address": l?.host,
              [Ze]: "auto.http.browser",
              [Rt]: "http.client",
              ...(l?.search && { "http.query": l?.search }),
              ...(l?.hash && { "http.fragment": l?.hash }),
            },
          })
        : new pt();
  ((i.__sentry_xhr_span_id__ = h.spanContext().spanId),
    (r[i.__sentry_xhr_span_id__] = h),
    n(a) && Kx(i, Je() && f ? h : void 0, s));
  const m = W();
  return (m && m.emit("beforeOutgoingRequestSpan", h, e), h);
}
function Kx(e, t, n) {
  const {
    "sentry-trace": r,
    baggage: s,
    traceparent: i,
  } = Ca({ span: t, propagateTraceparent: n });
  r && Jx(e, r, s, i);
}
function Jx(e, t, n, r) {
  const s = e.__sentry_xhr_v3__?.request_headers;
  if (!(s?.["sentry-trace"] || !e.setRequestHeader))
    try {
      if (
        (e.setRequestHeader("sentry-trace", t),
        r && !s?.traceparent && e.setRequestHeader("traceparent", r),
        n)
      ) {
        const i = s?.baggage;
        (!i || !Zx(i)) && e.setRequestHeader("baggage", n);
      }
    } catch {}
}
function Zx(e) {
  return e.split(",").some((t) => t.trim().startsWith("sentry-"));
}
function um(e) {
  try {
    return new URL(e, B.location.origin).href;
  } catch {
    return;
  }
}
function Qx() {
  B.document
    ? B.document.addEventListener("visibilitychange", () => {
        const e = Pe();
        if (!e) return;
        const t = Ne(e);
        if (B.document.hidden && t) {
          const n = "cancelled",
            { op: r, status: s } = ee(t);
          (G &&
            S.log(
              `[Tracing] Transaction: ${n} -> since tab moved to the background, op: ${r}`,
            ),
            s || t.setStatus({ code: lt, message: n }),
            t.setAttribute("sentry.cancellation_reason", "document.hidden"),
            t.end());
        }
      })
    : G &&
      S.warn(
        "[Tracing] Could not set up background tab detection due to lack of global document",
      );
}
const eA = 3600,
  lm = "sentry_previous_trace",
  tA = "sentry.previous_trace";
function nA(e, { linkPreviousTrace: t, consistentTraceSampling: n }) {
  const r = t === "session-storage";
  let s = r ? iA() : void 0;
  e.on("spanStart", (o) => {
    if (Ne(o) !== o) return;
    const a = ue().getPropagationContext();
    ((s = rA(s, o, a)), r && sA(s));
  });
  let i = !0;
  n &&
    e.on("beforeSampling", (o) => {
      if (!s) return;
      const a = ue(),
        c = a.getPropagationContext();
      if (i && c.parentSpanId) {
        i = !1;
        return;
      }
      (a.setPropagationContext({
        ...c,
        dsc: {
          ...c.dsc,
          sample_rate: String(s.sampleRate),
          sampled: String(Yo(s.spanContext)),
        },
        sampleRand: s.sampleRand,
      }),
        (o.parentSampled = Yo(s.spanContext)),
        (o.parentSampleRate = s.sampleRate),
        (o.spanAttributes = { ...o.spanAttributes, [eg]: s.sampleRate }));
    });
}
function rA(e, t, n) {
  const r = ee(t);
  function s() {
    try {
      return Number(n.dsc?.sample_rate) ?? Number(r.data?.[na]);
    } catch {
      return 0;
    }
  }
  const i = {
    spanContext: t.spanContext(),
    startTimestamp: r.start_timestamp,
    sampleRate: s(),
    sampleRand: n.sampleRand,
  };
  if (!e) return i;
  const o = e.spanContext;
  return o.traceId === r.trace_id
    ? e
    : (Date.now() / 1e3 - e.startTimestamp <= eA &&
        (G &&
          S.log(
            `Adding previous_trace ${o} link to span ${{ op: r.op, ...t.spanContext() }}`,
          ),
        t.addLink({ context: o, attributes: { [tg]: "previous_trace" } }),
        t.setAttribute(tA, `${o.traceId}-${o.spanId}-${Yo(o) ? 1 : 0}`)),
      i);
}
function sA(e) {
  try {
    B.sessionStorage.setItem(lm, JSON.stringify(e));
  } catch (t) {
    G && S.warn("Could not store previous trace in sessionStorage", t);
  }
}
function iA() {
  try {
    const e = B.sessionStorage?.getItem(lm);
    return JSON.parse(e);
  } catch {
    return;
  }
}
function Yo(e) {
  return e.traceFlags === 1;
}
const oA = "BrowserTracing",
  aA = {
    ...cs,
    instrumentNavigation: !0,
    instrumentPageLoad: !0,
    markBackgroundSpan: !0,
    enableLongTask: !0,
    enableLongAnimationFrame: !0,
    enableInp: !0,
    enableElementTiming: !0,
    ignoreResourceSpans: [],
    ignorePerformanceApiSpans: [],
    detectRedirects: !0,
    linkPreviousTrace: "in-memory",
    consistentTraceSampling: !1,
    enableReportPageLoaded: !1,
    _experiments: {},
    ...Ac,
  },
  dm = (e = {}) => {
    const t = { name: void 0, source: void 0 },
      n = B.document,
      {
        enableInp: r,
        enableElementTiming: s,
        enableLongTask: i,
        enableLongAnimationFrame: o,
        _experiments: {
          enableInteractions: a,
          enableStandaloneClsSpans: c,
          enableStandaloneLcpSpans: u,
        },
        beforeStartSpan: d,
        idleTimeout: l,
        finalTimeout: p,
        childSpanTimeout: f,
        markBackgroundSpan: h,
        traceFetch: m,
        traceXHR: g,
        trackFetchStreamPerformance: _,
        shouldCreateSpanForRequest: y,
        enableHTTPTimings: M,
        ignoreResourceSpans: w,
        ignorePerformanceApiSpans: A,
        instrumentPageLoad: C,
        instrumentNavigation: E,
        detectRedirects: I,
        linkPreviousTrace: b,
        consistentTraceSampling: k,
        enableReportPageLoaded: O,
        onRequestSpanStart: v,
      } = { ...aA, ...e };
    let x, U, q;
    function K(T, P, R = !0) {
      const L = P.op === "pageload",
        V = P.name,
        Q = d ? d(P) : P,
        ge = Q.attributes || {};
      if ((V !== Q.name && ((ge[rt] = "custom"), (Q.attributes = ge)), !R)) {
        const Be = ni();
        yr({ ...Q, startTime: Be }).end(Be);
        return;
      }
      ((t.name = Q.name), (t.source = ge[rt]));
      const le = mf(Q, {
        idleTimeout: l,
        finalTimeout: p,
        childSpanTimeout: f,
        disableAutoFinish: L,
        beforeSpanEnd: (Be) => {
          (x?.(),
            PT(Be, {
              recordClsOnPageloadSpan: !c,
              recordLcpOnPageloadSpan: !u,
              ignoreResourceSpans: w,
              ignorePerformanceApiSpans: A,
            }),
            pd(T, void 0));
          const Le = ue(),
            Re = Le.getPropagationContext();
          (Le.setPropagationContext({
            ...Re,
            traceId: le.spanContext().traceId,
            sampled: ti(le),
            dsc: Ct(Be),
          }),
            L && (q = void 0));
        },
        trimIdleSpanEndTimestamp: !O,
      });
      (L && O && (q = le), pd(T, le));
      function gt() {
        n &&
          ["interactive", "complete"].includes(n.readyState) &&
          T.emit("idleSpanEnableAutoFinish", le);
      }
      L &&
        !O &&
        n &&
        (n.addEventListener("readystatechange", () => {
          gt();
        }),
        gt());
    }
    return {
      name: oA,
      setup(T) {
        if (
          (uf(),
          (x = AT({
            recordClsStandaloneSpans: c || !1,
            recordLcpStandaloneSpans: u || !1,
            client: T,
          })),
          r && a0(),
          s && YT(),
          o &&
          ne.PerformanceObserver &&
          PerformanceObserver.supportedEntryTypes &&
          PerformanceObserver.supportedEntryTypes.includes(
            "long-animation-frame",
          )
            ? NT()
            : i && MT(),
          a && OT(),
          I && n)
        ) {
          const R = () => {
            U = ke();
          };
          (addEventListener("click", R, { capture: !0 }),
            addEventListener("keydown", R, { capture: !0, passive: !0 }));
        }
        function P() {
          const R = fr(T);
          R &&
            !ee(R).timestamp &&
            (G &&
              S.log(
                `[Tracing] Finishing current active span with op: ${ee(R).op}`,
              ),
            R.setAttribute(Zn, "cancelled"),
            R.end());
        }
        (T.on("startNavigationSpan", (R, L) => {
          if (W() !== T) return;
          if (L?.isRedirect) {
            (G &&
              S.warn(
                "[Tracing] Detected redirect, navigation span will not be the root span, but a child span.",
              ),
              K(T, { op: "navigation.redirect", ...R }, !1));
            return;
          }
          ((U = void 0),
            P(),
            Cn().setPropagationContext({
              traceId: Jn(),
              sampleRand: Math.random(),
              propagationSpanId: Je() ? void 0 : Pn(),
            }));
          const V = ue();
          (V.setPropagationContext({
            traceId: Jn(),
            sampleRand: Math.random(),
            propagationSpanId: Je() ? void 0 : Pn(),
          }),
            V.setSDKProcessingMetadata({ normalizedRequest: void 0 }),
            K(T, {
              op: "navigation",
              ...R,
              parentSpan: null,
              forceTransaction: !0,
            }));
        }),
          T.on("startPageLoadSpan", (R, L = {}) => {
            if (W() !== T) return;
            P();
            const V = L.sentryTrace || fd("sentry-trace"),
              Q = L.baggage || fd("baggage"),
              ge = Cd(V, Q),
              le = ue();
            (le.setPropagationContext(ge),
              Je() || (le.getPropagationContext().propagationSpanId = Pn()),
              le.setSDKProcessingMetadata({ normalizedRequest: ua() }),
              K(T, { op: "pageload", ...R }));
          }),
          T.on("endPageloadSpan", () => {
            O && q && (q.setAttribute(Zn, "reportPageLoaded"), q.end());
          }));
      },
      afterAllSetup(T) {
        let P = ii();
        if (
          (b !== "off" &&
            nA(T, { linkPreviousTrace: b, consistentTraceSampling: k }),
          B.location)
        ) {
          if (C) {
            const R = Ud();
            fm(T, {
              name: B.location.pathname,
              startTime: R ? R / 1e3 : void 0,
              attributes: { [rt]: "url", [Ze]: "auto.pageload.browser" },
            });
          }
          E &&
            Si(({ to: R, from: L }) => {
              if (L === void 0 && P?.indexOf(R) !== -1) {
                P = void 0;
                return;
              }
              P = void 0;
              const V = ka(R),
                Q = fr(T),
                ge = Q && I && uA(Q, U);
              pm(
                T,
                {
                  name: V?.pathname || B.location.pathname,
                  attributes: { [rt]: "url", [Ze]: "auto.navigation.browser" },
                },
                { url: R, isRedirect: ge },
              );
            });
        }
        (h && Qx(),
          a && cA(T, l, p, f, t),
          r && l0(),
          cm(T, {
            traceFetch: m,
            traceXHR: g,
            trackFetchStreamPerformance: _,
            tracePropagationTargets: T.getOptions().tracePropagationTargets,
            shouldCreateSpanForRequest: y,
            enableHTTPTimings: M,
            onRequestSpanStart: v,
          }));
      },
    };
  };
function fm(e, t, n) {
  (e.emit("startPageLoadSpan", t, n), ue().setTransactionName(t.name));
  const r = fr(e);
  return (r && e.emit("afterStartPageLoadSpan", r), r);
}
function pm(e, t, n) {
  const { url: r, isRedirect: s } = n || {};
  (e.emit("beforeStartNavigationSpan", t, { isRedirect: s }),
    e.emit("startNavigationSpan", t, { isRedirect: s }));
  const i = ue();
  return (
    i.setTransactionName(t.name),
    r &&
      !s &&
      i.setSDKProcessingMetadata({ normalizedRequest: { ...ua(), url: r } }),
    fr(e)
  );
}
function fd(e) {
  return (
    B.document?.querySelector(`meta[name=${e}]`)?.getAttribute("content") ||
    void 0
  );
}
function cA(e, t, n, r, s) {
  const i = B.document;
  let o;
  const a = () => {
    const c = "ui.action.click",
      u = fr(e);
    if (u) {
      const d = ee(u).op;
      if (["navigation", "pageload"].includes(d)) {
        G &&
          S.warn(
            `[Tracing] Did not create ${c} span because a pageload or navigation span is in progress.`,
          );
        return;
      }
    }
    if (
      (o &&
        (o.setAttribute(Zn, "interactionInterrupted"), o.end(), (o = void 0)),
      !s.name)
    ) {
      G &&
        S.warn(
          `[Tracing] Did not create ${c} transaction because _latestRouteName is missing.`,
        );
      return;
    }
    o = mf(
      { name: s.name, op: c, attributes: { [rt]: s.source || "url" } },
      { idleTimeout: t, finalTimeout: n, childSpanTimeout: r },
    );
  };
  i && addEventListener("click", a, { capture: !0 });
}
const hm = "_sentry_idleSpan";
function fr(e) {
  return e[hm];
}
function pd(e, t) {
  aa(e, hm, t);
}
const hd = 1.5;
function uA(e, t) {
  const n = ee(e),
    r = ni(),
    s = n.start_timestamp;
  return !(r - s > hd || (t && r - t <= hd));
}
function lA(e = W()) {
  e?.emit("endPageloadSpan");
}
function dA(e) {
  const t = Pe();
  if (t === e) return;
  const n = ue();
  ((e.end = new Proxy(e.end, {
    apply(r, s, i) {
      return (jt(n, t), Reflect.apply(r, s, i));
    },
  })),
    jt(n, e));
}
function In(e) {
  return new Promise((t, n) => {
    ((e.oncomplete = e.onsuccess = () => t(e.result)),
      (e.onabort = e.onerror = () => n(e.error)));
  });
}
function fA(e, t) {
  const n = indexedDB.open(e);
  n.onupgradeneeded = () => n.result.createObjectStore(t);
  const r = In(n);
  return (s) => r.then((i) => s(i.transaction(t, "readwrite").objectStore(t)));
}
function Mc(e) {
  return In(e.getAllKeys());
}
function pA(e, t, n) {
  return e((r) =>
    Mc(r).then((s) => {
      if (!(s.length >= n))
        return (r.put(t, Math.max(...s, 0) + 1), In(r.transaction));
    }),
  );
}
function hA(e, t, n) {
  return e((r) =>
    Mc(r).then((s) => {
      if (!(s.length >= n))
        return (r.put(t, Math.min(...s, 0) - 1), In(r.transaction));
    }),
  );
}
function mA(e) {
  return e((t) =>
    Mc(t).then((n) => {
      const r = n[0];
      if (r != null)
        return In(t.get(r)).then(
          (s) => (t.delete(r), In(t.transaction).then(() => s)),
        );
    }),
  );
}
function gA(e) {
  let t;
  function n() {
    return (
      t == null &&
        (t = fA(e.dbName || "sentry-offline", e.storeName || "queue")),
      t
    );
  }
  return {
    push: async (r) => {
      try {
        const s = await Rs(r);
        await pA(n(), s, e.maxQueueSize || 30);
      } catch {}
    },
    unshift: async (r) => {
      try {
        const s = await Rs(r);
        await hA(n(), s, e.maxQueueSize || 30);
      } catch {}
    },
    shift: async () => {
      try {
        const r = await mA(n());
        if (r) return bS(r);
      } catch {}
    },
  };
}
function _A(e) {
  return (t) => {
    const n = e({ ...t, createStore: gA });
    return (
      B.addEventListener("online", async (r) => {
        await n.flush();
      }),
      n
    );
  };
}
function SA(e = tc) {
  return _A(gy(e));
}
const md = 1e6,
  Ss = String(0),
  yA = "main",
  ei = B.navigator;
let mm = "",
  gm = "",
  _m = "",
  Xo = ei?.userAgent || "",
  Sm = "";
const bA = ei?.language || ei?.languages?.[0] || "";
function EA(e) {
  return typeof e == "object" && e !== null && "getHighEntropyValues" in e;
}
const gd = ei?.userAgentData;
EA(gd) &&
  gd
    .getHighEntropyValues([
      "architecture",
      "model",
      "platform",
      "platformVersion",
      "fullVersionList",
    ])
    .then((e) => {
      if (
        ((mm = e.platform || ""),
        (_m = e.architecture || ""),
        (Sm = e.model || ""),
        (gm = e.platformVersion || ""),
        e.fullVersionList?.length)
      ) {
        const t = e.fullVersionList[e.fullVersionList.length - 1];
        Xo = `${t.brand} ${t.version}`;
      }
    })
    .catch((e) => {});
function vA(e) {
  return !("thread_metadata" in e);
}
function TA(e) {
  return vA(e) ? kA(e) : e;
}
function wA(e) {
  const t = e.contexts?.trace?.trace_id;
  return (
    typeof t == "string" &&
      t.length !== 32 &&
      G &&
      S.log(`[Profiling] Invalid traceId: ${t} on profiled event`),
    typeof t != "string" ? "" : t
  );
}
function IA(e, t, n, r) {
  if (r.type !== "transaction")
    throw new TypeError(
      "Profiling events may only be attached to transactions, this should never occur.",
    );
  if (n == null)
    throw new TypeError(
      `Cannot construct profiling event envelope without a valid profile. Got ${n} instead.`,
    );
  const s = wA(r),
    i = TA(n),
    o =
      t ||
      (typeof r.start_timestamp == "number"
        ? r.start_timestamp * 1e3
        : ke() * 1e3),
    a = typeof r.timestamp == "number" ? r.timestamp * 1e3 : ke() * 1e3;
  return {
    event_id: e,
    timestamp: new Date(o).toISOString(),
    platform: "javascript",
    version: "1",
    release: r.release || "",
    environment: r.environment || xd,
    runtime: { name: "javascript", version: B.navigator.userAgent },
    os: { name: mm, version: gm, build_number: Xo },
    device: {
      locale: bA,
      model: Sm,
      manufacturer: Xo,
      architecture: _m,
      is_emulator: !1,
    },
    debug_meta: { images: xA(n.resources) },
    profile: i,
    transactions: [
      {
        name: r.transaction || "",
        id: r.event_id || Un(),
        trace_id: s,
        active_thread_id: Ss,
        relative_start_ns: "0",
        relative_end_ns: ((a - o) * 1e6).toFixed(0),
      },
    ],
  };
}
function ym(e) {
  return ee(e).op === "pageload";
}
function kA(e) {
  let t,
    n = 0;
  const r = {
      samples: [],
      stacks: [],
      frames: [],
      thread_metadata: { [Ss]: { name: yA } },
    },
    s = e.samples[0];
  if (!s) return r;
  const i = s.timestamp,
    o = Ud(),
    a =
      typeof performance.timeOrigin == "number"
        ? performance.timeOrigin
        : o || 0,
    c = a - (o || a);
  return (
    e.samples.forEach((u, d) => {
      if (u.stackId === void 0) {
        (t === void 0 && ((t = n), (r.stacks[t] = []), n++),
          (r.samples[d] = {
            elapsed_since_start_ns: ((u.timestamp + c - i) * md).toFixed(0),
            stack_id: t,
            thread_id: Ss,
          }));
        return;
      }
      let l = e.stacks[u.stackId];
      const p = [];
      for (; l;) {
        p.push(l.frameId);
        const h = e.frames[l.frameId];
        (h &&
          r.frames[l.frameId] === void 0 &&
          (r.frames[l.frameId] = {
            function: h.name,
            abs_path:
              typeof h.resourceId == "number"
                ? e.resources[h.resourceId]
                : void 0,
            lineno: h.line,
            colno: h.column,
          }),
          (l = l.parentId === void 0 ? void 0 : e.stacks[l.parentId]));
      }
      const f = {
        elapsed_since_start_ns: ((u.timestamp + c - i) * md).toFixed(0),
        stack_id: n,
        thread_id: Ss,
      };
      ((r.stacks[n] = p), (r.samples[d] = f), n++);
    }),
    r
  );
}
function CA(e, t) {
  if (!t.length) return e;
  for (const n of t) e[1].push([{ type: "profile" }, n]);
  return e;
}
function RA(e) {
  const t = [];
  return (
    Vt(e, (n, r) => {
      if (r === "transaction")
        for (let s = 1; s < n.length; s++)
          n[s]?.contexts?.profile?.profile_id && t.push(n[s]);
    }),
    t
  );
}
function xA(e) {
  const r = W()?.getOptions()?.stackParser;
  return r ? ng(r, e) : [];
}
function AA(e) {
  return (typeof e != "number" && typeof e != "boolean") ||
    (typeof e == "number" && isNaN(e))
    ? (G &&
        S.warn(
          `[Profiling] Invalid sample rate. Sample rate must be a boolean or a number between 0 and 1. Got ${JSON.stringify(e)} of type ${JSON.stringify(typeof e)}.`,
        ),
      !1)
    : e === !0 || e === !1
      ? !0
      : e < 0 || e > 1
        ? (G &&
            S.warn(
              `[Profiling] Invalid sample rate. Sample rate must be between 0 and 1. Got ${e}.`,
            ),
          !1)
        : !0;
}
function MA(e) {
  return e.samples.length < 2
    ? (G &&
        S.log(
          "[Profiling] Discarding profile because it contains less than 2 samples",
        ),
      !1)
    : e.frames.length
      ? !0
      : (G &&
          S.log("[Profiling] Discarding profile because it contains no frames"),
        !1);
}
let bm = !1;
const Em = 3e4;
function NA(e) {
  return typeof e == "function";
}
function OA() {
  const e = B.Profiler;
  if (!NA(e)) {
    G &&
      S.log(
        "[Profiling] Profiling is not supported by this browser, Profiler interface missing on window object.",
      );
    return;
  }
  const t = 10,
    n = Math.floor(Em / t);
  try {
    return new e({ sampleInterval: t, maxBufferSize: n });
  } catch {
    (G &&
      (S.log(
        "[Profiling] Failed to initialize the Profiling constructor, this is likely due to a missing 'Document-Policy': 'js-profiling' header.",
      ),
      S.log("[Profiling] Disabling profiling for current user session.")),
      (bm = !0));
  }
}
function _d(e) {
  if (bm)
    return (
      G &&
        S.log(
          "[Profiling] Profiling has been disabled for the duration of the current user session.",
        ),
      !1
    );
  if (!e.isRecording())
    return (
      G &&
        S.log(
          "[Profiling] Discarding profile because transaction was not sampled.",
        ),
      !1
    );
  const n = W()?.getOptions();
  if (!n)
    return (
      G && S.log("[Profiling] Profiling disabled, no options found."),
      !1
    );
  const r = n.profilesSampleRate;
  return AA(r)
    ? r
      ? (r === !0 ? !0 : Math.random() < r)
        ? !0
        : (G &&
            S.log(
              `[Profiling] Discarding profile because it's not included in the random sample (sampling rate = ${Number(r)})`,
            ),
          !1)
      : (G &&
          S.log(
            "[Profiling] Discarding profile because a negative sampling decision was inherited or profileSampleRate is set to 0",
          ),
        !1)
    : (G &&
        S.warn(
          "[Profiling] Discarding profile because of invalid sample rate.",
        ),
      !1);
}
function LA(e, t, n, r) {
  return MA(n) ? IA(e, t, n, r) : null;
}
const Ft = new Map();
function $A() {
  return Ft.size;
}
function DA(e) {
  const t = Ft.get(e);
  return (t && Ft.delete(e), t);
}
function PA(e, t) {
  if ((Ft.set(e, t), Ft.size > 30)) {
    const n = Ft.keys().next().value;
    Ft.delete(n);
  }
}
function Sd(e) {
  let t;
  ym(e) && (t = ke() * 1e3);
  const n = OA();
  if (!n) return;
  G && S.log(`[Profiling] started profiling span: ${ee(e).description}`);
  const r = Un();
  ue().setContext("profile", { profile_id: r, start_timestamp: t });
  async function s() {
    if (e && n)
      return n
        .stop()
        .then((c) => {
          if (
            (i && (B.clearTimeout(i), (i = void 0)),
            G &&
              S.log(
                `[Profiling] stopped profiling of span: ${ee(e).description}`,
              ),
            !c)
          ) {
            G &&
              S.log(
                `[Profiling] profiler returned null profile for: ${ee(e).description}`,
                "this may indicate an overlapping span or a call to stopProfiling with a profile title that was never started",
              );
            return;
          }
          PA(r, c);
        })
        .catch((c) => {
          G && S.log("[Profiling] error while stopping profiler:", c);
        });
  }
  let i = B.setTimeout(() => {
    (G &&
      S.log(
        "[Profiling] max profile duration elapsed, stopping profiling for:",
        ee(e).description,
      ),
      s());
  }, Em);
  const o = e.end.bind(e);
  function a() {
    return e
      ? (s().then(
          () => {
            o();
          },
          () => {
            o();
          },
        ),
        e)
      : o();
  }
  e.end = a;
}
const FA = "BrowserProfiling",
  BA = () => ({
    name: FA,
    setup(e) {
      const t = Pe(),
        n = t && Ne(t);
      (n && ym(n) && _d(n) && Sd(n),
        e.on("spanStart", (r) => {
          r === Ne(r) && _d(r) && Sd(r);
        }),
        e.on("beforeEnvelope", (r) => {
          if (!$A()) return;
          const s = RA(r);
          if (!s.length) return;
          const i = [];
          for (const o of s) {
            const a = o?.contexts,
              c = a?.profile?.profile_id,
              u = a?.profile?.start_timestamp;
            if (typeof c != "string") {
              G &&
                S.log(
                  "[Profiling] cannot find profile for a span without a profile context",
                );
              continue;
            }
            if (!c) {
              G &&
                S.log(
                  "[Profiling] cannot find profile for a span without a profile context",
                );
              continue;
            }
            a?.profile && delete a.profile;
            const d = DA(c);
            if (!d) {
              G &&
                S.log(`[Profiling] Could not retrieve profile for span: ${c}`);
              continue;
            }
            const l = LA(c, u, d, o);
            l && i.push(l);
          }
          CA(r, i);
        }));
    },
  }),
  UA = BA,
  HA = "SpotlightBrowser",
  WA = (e = {}) => {
    const t = e.sidecarUrl || "http://localhost:8969/stream";
    return {
      name: HA,
      setup: () => {
        G && S.log("Using Sidecar URL", t);
      },
      processEvent: (n) => (qA(n) ? null : n),
      afterAllSetup: (n) => {
        zA(n, t);
      },
    };
  };
function zA(e, t) {
  const n = Za("fetch");
  let r = 0;
  e.on("beforeEnvelope", (s) => {
    if (r > 3) {
      S.warn(
        "[Spotlight] Disabled Sentry -> Spotlight integration due to too many failed requests:",
        r,
      );
      return;
    }
    n(t, {
      method: "POST",
      body: Rs(s),
      headers: { "Content-Type": "application/x-sentry-envelope" },
      mode: "cors",
    }).then(
      (i) => {
        i.status >= 200 && i.status < 400 && (r = 0);
      },
      (i) => {
        (r++,
          S.error(
            "Sentry SDK can't connect to Sidecar is it running? See: https://spotlightjs.com/sidecar/npx/",
            i,
          ));
      },
    );
  });
}
const jA = WA;
function qA(e) {
  return !!(
    e.type === "transaction" &&
    e.spans &&
    e.contexts?.trace &&
    e.contexts.trace.op === "ui.action.click" &&
    e.spans.some(({ description: t }) => t?.includes("#sentry-spotlight"))
  );
}
const GA = () => ({
  name: "LaunchDarkly",
  processEvent(e, t, n) {
    return Er(e);
  },
});
function VA() {
  return {
    name: "sentry-flag-auditor",
    type: "flag-used",
    synchronous: !0,
    method: (e, t, n) => {
      (mn(e, t.value), gn(e, t.value));
    },
  };
}
const YA = () => ({
  name: "OpenFeature",
  processEvent(e, t, n) {
    return Er(e);
  },
});
class XA {
  after(t, n) {
    (mn(n.flagKey, n.value), gn(n.flagKey, n.value));
  }
  error(t, n, r) {
    (mn(t.flagKey, t.defaultValue), gn(t.flagKey, t.defaultValue));
  }
}
const KA = ({ featureFlagClientClass: e }) => ({
  name: "Unleash",
  setupOnce() {
    const t = e.prototype;
    Xe(t, "isEnabled", JA);
  },
  processEvent(t, n, r) {
    return Er(t);
  },
});
function JA(e) {
  return function (...t) {
    const n = t[0],
      r = e.apply(this, t);
    return (
      typeof n == "string" && typeof r == "boolean"
        ? (mn(n, r), gn(n, r))
        : G &&
          S.error(
            `[Feature Flags] UnleashClient.isEnabled does not match expected signature. arg0: ${n} (${typeof n}), result: ${r} (${typeof r})`,
          ),
      r
    );
  };
}
const ZA = ({ featureFlagClient: e }) => ({
  name: "Statsig",
  setup(t) {
    e.on("gate_evaluation", (n) => {
      (mn(n.gate.name, n.gate.value), gn(n.gate.name, n.gate.value));
    });
  },
  processEvent(t, n, r) {
    return Er(t);
  },
});
async function QA() {
  const e = W();
  if (!e) return "no-client-active";
  if (!e.getDsn()) return "no-dsn-configured";
  try {
    await ff(() =>
      fetch(
        "https://o447951.ingest.sentry.io/api/4509632503087104/envelope/?sentry_version=7&sentry_key=c1dfb07d783ad5325c245c1fd3725390&sentry_client=sentry.javascript.browser%2F1.33.7",
        { body: "{}", method: "POST", mode: "cors", credentials: "omit" },
      ),
    );
  } catch {
    return "sentry-unreachable";
  }
}
const eM = "WebWorker",
  tM = ({ worker: e }) => ({
    name: eM,
    setupOnce: () => {
      (Array.isArray(e) ? e : [e]).forEach((t) => yd(t));
    },
    addWorker: (t) => yd(t),
  });
function yd(e) {
  e.addEventListener("message", (t) => {
    rM(t.data) &&
      (t.stopImmediatePropagation(),
      G && S.log("Sentry debugId web worker message received", t.data),
      (B._sentryDebugIds = {
        ...t.data._sentryDebugIds,
        ...B._sentryDebugIds,
      }));
  });
}
function nM({ self: e }) {
  e.postMessage({
    _sentryMessage: !0,
    _sentryDebugIds: e._sentryDebugIds ?? void 0,
  });
}
function rM(e) {
  return (
    qt(e) &&
    e._sentryMessage === !0 &&
    "_sentryDebugIds" in e &&
    (qt(e._sentryDebugIds) || e._sentryDebugIds === void 0)
  );
}
const sM = Object.freeze(
  Object.defineProperty(
    {
      __proto__: null,
      BrowserClient: Xf,
      OpenFeatureIntegrationHook: XA,
      SDK_VERSION: bs,
      SEMANTIC_ATTRIBUTE_SENTRY_OP: Rt,
      SEMANTIC_ATTRIBUTE_SENTRY_ORIGIN: Ze,
      SEMANTIC_ATTRIBUTE_SENTRY_SAMPLE_RATE: na,
      SEMANTIC_ATTRIBUTE_SENTRY_SOURCE: rt,
      Scope: rg,
      WINDOW: B,
      addBreadcrumb: ht,
      addEventProcessor: sg,
      addIntegration: VS,
      breadcrumbsIntegration: nc,
      browserApiErrorsIntegration: Up,
      browserProfilingIntegration: UA,
      browserSessionIntegration: Hp,
      browserTracingIntegration: dm,
      buildLaunchDarklyFlagUsedHandler: VA,
      captureConsoleIntegration: Xy,
      captureEvent: pr,
      captureException: Qn,
      captureFeedback: Vb,
      captureMessage: Ts,
      captureSession: po,
      chromeStackLineParser: $p,
      close: ig,
      consoleLoggingIntegration: oE,
      contextLinesIntegration: Lw,
      continueTrace: PS,
      createConsolaReporter: cE,
      createTransport: If,
      createUserFeedbackEnvelope: O0,
      dedupeIntegration: Df,
      defaultRequestInstrumentationOptions: Ac,
      defaultStackLineParsers: Pp,
      defaultStackParser: Fp,
      diagnoseSdkConnectivity: QA,
      endSession: og,
      eventFiltersIntegration: Af,
      eventFromException: Vf,
      eventFromMessage: Yf,
      exceptionFromError: pi,
      extraErrorDataIntegration: sb,
      featureFlagsIntegration: Ub,
      feedbackAsyncIntegration: vE,
      feedbackIntegration: Wu,
      feedbackSyncIntegration: Wu,
      flush: ag,
      forceLoad: fw,
      functionToStringIntegration: xf,
      geckoStackLineParser: Dp,
      getActiveSpan: Pe,
      getClient: W,
      getCurrentScope: ue,
      getDefaultIntegrations: Gp,
      getFeedback: k_,
      getGlobalScope: Nd,
      getIsolationScope: Cn,
      getReplay: Cx,
      getRootSpan: Ne,
      getSpanDescendants: Bn,
      getSpanStatusFromHttpCode: cg,
      getTraceData: Ca,
      globalHandlersIntegration: Wp,
      graphqlClientIntegration: Ww,
      httpClientIntegration: bw,
      httpContextIntegration: jp,
      inboundFiltersIntegration: Mf,
      init: Vp,
      instrumentOutgoingRequests: cm,
      instrumentSupabaseClient: Hf,
      isEnabled: Od,
      isInitialized: ug,
      lastEventId: lg,
      launchDarklyIntegration: GA,
      lazyLoadIntegration: qf,
      linkedErrorsIntegration: qp,
      logger: eE,
      makeBrowserOfflineTransport: SA,
      makeFetchTransport: tc,
      makeMultiplexedTransport: yy,
      moduleMetadataIntegration: qy,
      onLoad: pw,
      openFeatureIntegration: YA,
      opera10StackLineParser: x0,
      opera11StackLineParser: N0,
      parameterize: Rf,
      registerSpanErrorInstrumentation: uf,
      registerWebWorker: nM,
      replayCanvasIntegration: Gx,
      replayIntegration: wx,
      reportPageLoaded: lA,
      reportingObserverIntegration: _w,
      rewriteFramesIntegration: fb,
      sendFeedback: Vd,
      setActiveSpanInBrowser: dA,
      setContext: dg,
      setCurrentClient: vf,
      setExtra: fg,
      setExtras: pg,
      setHttpStatus: er,
      setMeasurement: MS,
      setTag: la,
      setTags: hg,
      setUser: mg,
      showReportDialog: gg,
      spanToBaggageHeader: _g,
      spanToJSON: ee,
      spanToTraceHeader: Ld,
      spotlightBrowserIntegration: jA,
      startBrowserTracingNavigationSpan: pm,
      startBrowserTracingPageLoadSpan: fm,
      startInactiveSpan: yr,
      startNewTrace: pf,
      startSession: fo,
      startSpan: ba,
      startSpanManual: DS,
      statsigIntegration: ZA,
      supabaseIntegration: Ib,
      suppressTracing: ff,
      thirdPartyErrorFilterIntegration: $b,
      unleashIntegration: KA,
      updateSpanName: Sg,
      webWorkerIntegration: tM,
      winjsStackLineParser: k0,
      withActiveSpan: li,
      withIsolationScope: yg,
      withScope: qe,
      zodErrorsIntegration: Lb,
    },
    Symbol.toStringTag,
    { value: "Module" },
  ),
);
Vp({
  ...Nc,
  ignoreErrors: [
    ...(Nc.ignoreErrors ?? []),
    "ResizeObserver loop limit exceeded",
  ],
  integrations: (e) => [
    ...e.filter((t) => t.name !== "Breadcrumbs"),
    nc({ console: !1, dom: !0, fetch: !1, history: !1, xhr: !1 }),
    dm({ instrumentPageLoad: !1, instrumentNavigation: !1 }),
  ],
});
la("realm", "renderer");
la("device_id", vm);
globalThis.Sentry = sM;
export { sM as default };
//# sourceMappingURL=init-sentry-browser-C19iq1G1.js.map
