import { L as J } from "./index-o5KnLmKX.mjs";
import {
  bz as g,
  ap as k,
  am as s,
  cA as n,
  by as O,
  aj as F,
  V as ee,
  al as te,
  bo as oe,
} from "./Keychain-CHHka2u7.mjs";
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
      (e._sentryDebugIds[t] = "e99ef77f-5d1b-49dd-a16d-5cd056a326cf"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-e99ef77f-5d1b-49dd-a16d-5cd056a326cf"));
  } catch {}
})();
let W;
W =
  globalThis.crypto?.webcrypto ??
  globalThis.crypto ??
  import("node:crypto").then((e) => e.webcrypto);
async function ne(e) {
  return (await W).getRandomValues(new Uint8Array(e));
}
async function re(e) {
  const t =
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~";
  let r = "";
  const o = await ne(e);
  for (let i = 0; i < e; i++) {
    const c = o[i] % t.length;
    r += t[c];
  }
  return r;
}
async function ie(e) {
  return await re(e);
}
async function se(e) {
  const t = await (
    await W
  ).subtle.digest("SHA-256", new TextEncoder().encode(e));
  return btoa(String.fromCharCode(...new Uint8Array(t)))
    .replace(/\//g, "_")
    .replace(/\+/g, "-")
    .replace(/=/g, "");
}
async function ae(e) {
  if ((e || (e = 43), e < 43 || e > 128))
    throw `Expected a length between 43 and 128. Received ${e}.`;
  const t = await ie(e),
    r = await se(t);
  return { code_verifier: t, code_challenge: r };
}
const _ = n()
    .url()
    .superRefine((e, t) => {
      if (!URL.canParse(e))
        return (
          t.addIssue({
            code: F.custom,
            message: "URL must be parseable",
            fatal: !0,
          }),
          ee
        );
    })
    .refine(
      (e) => {
        const t = new URL(e);
        return (
          t.protocol !== "javascript:" &&
          t.protocol !== "data:" &&
          t.protocol !== "vbscript:"
        );
      },
      { message: "URL cannot use javascript:, data:, or vbscript: scheme" },
    ),
  ce = g({
    resource: n().url(),
    authorization_servers: s(_).optional(),
    jwks_uri: n().url().optional(),
    scopes_supported: s(n()).optional(),
    bearer_methods_supported: s(n()).optional(),
    resource_signing_alg_values_supported: s(n()).optional(),
    resource_name: n().optional(),
    resource_documentation: n().optional(),
    resource_policy_uri: n().url().optional(),
    resource_tos_uri: n().url().optional(),
    tls_client_certificate_bound_access_tokens: k().optional(),
    authorization_details_types_supported: s(n()).optional(),
    dpop_signing_alg_values_supported: s(n()).optional(),
    dpop_bound_access_tokens_required: k().optional(),
  }).passthrough(),
  Y = g({
    issuer: n(),
    authorization_endpoint: _,
    token_endpoint: _,
    registration_endpoint: _.optional(),
    scopes_supported: s(n()).optional(),
    response_types_supported: s(n()),
    response_modes_supported: s(n()).optional(),
    grant_types_supported: s(n()).optional(),
    token_endpoint_auth_methods_supported: s(n()).optional(),
    token_endpoint_auth_signing_alg_values_supported: s(n()).optional(),
    service_documentation: _.optional(),
    revocation_endpoint: _.optional(),
    revocation_endpoint_auth_methods_supported: s(n()).optional(),
    revocation_endpoint_auth_signing_alg_values_supported: s(n()).optional(),
    introspection_endpoint: n().optional(),
    introspection_endpoint_auth_methods_supported: s(n()).optional(),
    introspection_endpoint_auth_signing_alg_values_supported: s(n()).optional(),
    code_challenge_methods_supported: s(n()).optional(),
  }).passthrough(),
  le = g({
    issuer: n(),
    authorization_endpoint: _,
    token_endpoint: _,
    userinfo_endpoint: _.optional(),
    jwks_uri: _,
    registration_endpoint: _.optional(),
    scopes_supported: s(n()).optional(),
    response_types_supported: s(n()),
    response_modes_supported: s(n()).optional(),
    grant_types_supported: s(n()).optional(),
    acr_values_supported: s(n()).optional(),
    subject_types_supported: s(n()),
    id_token_signing_alg_values_supported: s(n()),
    id_token_encryption_alg_values_supported: s(n()).optional(),
    id_token_encryption_enc_values_supported: s(n()).optional(),
    userinfo_signing_alg_values_supported: s(n()).optional(),
    userinfo_encryption_alg_values_supported: s(n()).optional(),
    userinfo_encryption_enc_values_supported: s(n()).optional(),
    request_object_signing_alg_values_supported: s(n()).optional(),
    request_object_encryption_alg_values_supported: s(n()).optional(),
    request_object_encryption_enc_values_supported: s(n()).optional(),
    token_endpoint_auth_methods_supported: s(n()).optional(),
    token_endpoint_auth_signing_alg_values_supported: s(n()).optional(),
    display_values_supported: s(n()).optional(),
    claim_types_supported: s(n()).optional(),
    claims_supported: s(n()).optional(),
    service_documentation: n().optional(),
    claims_locales_supported: s(n()).optional(),
    ui_locales_supported: s(n()).optional(),
    claims_parameter_supported: k().optional(),
    request_parameter_supported: k().optional(),
    request_uri_parameter_supported: k().optional(),
    require_request_uri_registration: k().optional(),
    op_policy_uri: _.optional(),
    op_tos_uri: _.optional(),
  }).passthrough(),
  ue = le.merge(Y.pick({ code_challenge_methods_supported: !0 })),
  K = g({
    access_token: n(),
    id_token: n().optional(),
    token_type: n(),
    expires_in: O().optional(),
    scope: n().optional(),
    refresh_token: n().optional(),
  }).strip(),
  de = g({
    error: n(),
    error_description: n().optional(),
    error_uri: n().optional(),
  }),
  G = _.optional().or(oe("").transform(() => {})),
  pe = g({
    redirect_uris: s(_),
    token_endpoint_auth_method: n().optional(),
    grant_types: s(n()).optional(),
    response_types: s(n()).optional(),
    client_name: n().optional(),
    client_uri: _.optional(),
    logo_uri: G,
    scope: n().optional(),
    contacts: s(n()).optional(),
    tos_uri: G,
    policy_uri: n().optional(),
    jwks_uri: _.optional(),
    jwks: te().optional(),
    software_id: n().optional(),
    software_version: n().optional(),
    software_statement: n().optional(),
  }).strip(),
  _e = g({
    client_id: n(),
    client_secret: n().optional(),
    client_id_issued_at: O().optional(),
    client_secret_expires_at: O().optional(),
  }).strip(),
  he = pe.merge(_e);
g({ error: n(), error_description: n().optional() }).strip();
g({ token: n(), token_type_hint: n().optional() }).strip();
function fe(e) {
  const t = typeof e == "string" ? new URL(e) : new URL(e.href);
  return ((t.hash = ""), t);
}
function we({ requestedResource: e, configuredResource: t }) {
  const r = typeof e == "string" ? new URL(e) : new URL(e.href),
    o = typeof t == "string" ? new URL(t) : new URL(t.href);
  if (r.origin !== o.origin || r.pathname.length < o.pathname.length) return !1;
  const i = r.pathname.endsWith("/") ? r.pathname : r.pathname + "/",
    c = o.pathname.endsWith("/") ? o.pathname : o.pathname + "/";
  return i.startsWith(c);
}
class h extends Error {
  constructor(t, r) {
    (super(t), (this.errorUri = r), (this.name = this.constructor.name));
  }
  toResponseObject() {
    const t = { error: this.errorCode, error_description: this.message };
    return (this.errorUri && (t.error_uri = this.errorUri), t);
  }
  get errorCode() {
    return this.constructor.errorCode;
  }
}
class P extends h {}
P.errorCode = "invalid_request";
class R extends h {}
R.errorCode = "invalid_client";
class C extends h {}
C.errorCode = "invalid_grant";
class b extends h {}
b.errorCode = "unauthorized_client";
class x extends h {}
x.errorCode = "unsupported_grant_type";
class S extends h {}
S.errorCode = "invalid_scope";
class I extends h {}
I.errorCode = "access_denied";
class U extends h {}
U.errorCode = "server_error";
class $ extends h {}
$.errorCode = "temporarily_unavailable";
class j extends h {}
j.errorCode = "unsupported_response_type";
class z extends h {}
z.errorCode = "unsupported_token_type";
class M extends h {}
M.errorCode = "invalid_token";
class V extends h {}
V.errorCode = "method_not_allowed";
class q extends h {}
q.errorCode = "too_many_requests";
class D extends h {}
D.errorCode = "invalid_client_metadata";
class H extends h {}
H.errorCode = "insufficient_scope";
const ye = {
  [P.errorCode]: P,
  [R.errorCode]: R,
  [C.errorCode]: C,
  [b.errorCode]: b,
  [x.errorCode]: x,
  [S.errorCode]: S,
  [I.errorCode]: I,
  [U.errorCode]: U,
  [$.errorCode]: $,
  [j.errorCode]: j,
  [z.errorCode]: z,
  [M.errorCode]: M,
  [V.errorCode]: V,
  [q.errorCode]: q,
  [D.errorCode]: D,
  [H.errorCode]: H,
};
class $e extends Error {
  constructor(t) {
    super(t ?? "Unauthorized");
  }
}
function ge(e) {
  return ["client_secret_basic", "client_secret_post", "none"].includes(e);
}
const T = "code",
  A = "S256";
function Q(e, t) {
  const r = e.client_secret !== void 0;
  return t.length === 0
    ? r
      ? "client_secret_post"
      : "none"
    : "token_endpoint_auth_method" in e &&
        e.token_endpoint_auth_method &&
        ge(e.token_endpoint_auth_method) &&
        t.includes(e.token_endpoint_auth_method)
      ? e.token_endpoint_auth_method
      : r && t.includes("client_secret_basic")
        ? "client_secret_basic"
        : r && t.includes("client_secret_post")
          ? "client_secret_post"
          : t.includes("none")
            ? "none"
            : r
              ? "client_secret_post"
              : "none";
}
function X(e, t, r, o) {
  const { client_id: i, client_secret: c } = t;
  switch (e) {
    case "client_secret_basic":
      me(i, c, r);
      return;
    case "client_secret_post":
      ve(i, c, o);
      return;
    case "none":
      ke(i, o);
      return;
    default:
      throw new Error(`Unsupported client authentication method: ${e}`);
  }
}
function me(e, t, r) {
  if (!t)
    throw new Error(
      "client_secret_basic authentication requires a client_secret",
    );
  const o = btoa(`${e}:${t}`);
  r.set("Authorization", `Basic ${o}`);
}
function ve(e, t, r) {
  (r.set("client_id", e), t && r.set("client_secret", t));
}
function ke(e, t) {
  t.set("client_id", e);
}
async function N(e) {
  const t = e instanceof Response ? e.status : void 0,
    r = e instanceof Response ? await e.text() : e;
  try {
    const o = de.parse(JSON.parse(r)),
      { error: i, error_description: c, error_uri: l } = o,
      a = ye[i] || U;
    return new a(c || "", l);
  } catch (o) {
    const i = `${t ? `HTTP ${t}: ` : ""}Invalid OAuth error response: ${o}. Raw body: ${r}`;
    return new U(i);
  }
}
async function je(e, t) {
  var r, o;
  try {
    return await L(e, t);
  } catch (i) {
    if (i instanceof R || i instanceof b)
      return (
        await ((r = e.invalidateCredentials) === null || r === void 0
          ? void 0
          : r.call(e, "all")),
        await L(e, t)
      );
    if (i instanceof C)
      return (
        await ((o = e.invalidateCredentials) === null || o === void 0
          ? void 0
          : o.call(e, "tokens")),
        await L(e, t)
      );
    throw i;
  }
}
async function L(
  e,
  {
    serverUrl: t,
    authorizationCode: r,
    scope: o,
    resourceMetadataUrl: i,
    fetchFn: c,
  },
) {
  let l, a;
  try {
    ((l = await Re(t, { resourceMetadataUrl: i }, c)),
      l.authorization_servers &&
        l.authorization_servers.length > 0 &&
        (a = l.authorization_servers[0]));
  } catch {}
  a || (a = t);
  const u = await Ue(t, e, l),
    p = await Ae(a, { fetchFn: c });
  let d = await Promise.resolve(e.clientInformation());
  if (!d) {
    if (r !== void 0)
      throw new Error(
        "Existing OAuth client information is required when exchanging an authorization code",
      );
    if (!e.saveClientInformation)
      throw new Error(
        "OAuth client information must be saveable for dynamic registration",
      );
    const f = await xe(a, {
      metadata: p,
      clientMetadata: e.clientMetadata,
      fetchFn: c,
    });
    (await e.saveClientInformation(f), (d = f));
  }
  if (r !== void 0) {
    const f = await e.codeVerifier(),
      E = await Oe(a, {
        metadata: p,
        clientInformation: d,
        authorizationCode: r,
        codeVerifier: f,
        redirectUri: e.redirectUrl,
        resource: u,
        addClientAuthentication: e.addClientAuthentication,
        fetchFn: c,
      });
    return (await e.saveTokens(E), "AUTHORIZED");
  }
  const w = await e.tokens();
  if (w?.refresh_token)
    try {
      const f = await Pe(a, {
        metadata: p,
        clientInformation: d,
        refreshToken: w.refresh_token,
        resource: u,
        addClientAuthentication: e.addClientAuthentication,
        fetchFn: c,
      });
      return (await e.saveTokens(f), "AUTHORIZED");
    } catch (f) {
      if (!(!(f instanceof h) || f instanceof U)) throw f;
    }
  const y = e.state ? await e.state() : void 0,
    { authorizationUrl: m, codeVerifier: v } = await Le(a, {
      metadata: p,
      clientInformation: d,
      state: y,
      redirectUrl: e.redirectUrl,
      scope: o || e.clientMetadata.scope,
      resource: u,
    });
  return (
    await e.saveCodeVerifier(v),
    await e.redirectToAuthorization(m),
    "REDIRECT"
  );
}
async function Ue(e, t, r) {
  const o = fe(e);
  if (t.validateResourceURL) return await t.validateResourceURL(o, r?.resource);
  if (r) {
    if (!we({ requestedResource: o, configuredResource: r.resource }))
      throw new Error(
        `Protected resource ${r.resource} does not match expected ${o} (or origin)`,
      );
    return new URL(r.resource);
  }
}
function ze(e) {
  const t = e.headers.get("WWW-Authenticate");
  if (!t) return;
  const [r, o] = t.split(" ");
  if (r.toLowerCase() !== "bearer" || !o) return;
  const c = /resource_metadata="([^"]*)"/.exec(t);
  if (c)
    try {
      return new URL(c[1]);
    } catch {
      return;
    }
}
async function Re(e, t, r = fetch) {
  const o = await Ee(e, "oauth-protected-resource", r, {
    protocolVersion: t?.protocolVersion,
    metadataUrl: t?.resourceMetadataUrl,
  });
  if (!o || o.status === 404)
    throw new Error(
      "Resource server does not implement OAuth 2.0 Protected Resource Metadata.",
    );
  if (!o.ok)
    throw new Error(
      `HTTP ${o.status} trying to load well-known OAuth protected resource metadata.`,
    );
  return ce.parse(await o.json());
}
async function Z(e, t, r = fetch) {
  try {
    return await r(e, { headers: t });
  } catch (o) {
    if (o instanceof TypeError) return t ? Z(e, void 0, r) : void 0;
    throw o;
  }
}
function Ce(e, t = "", r = {}) {
  return (
    t.endsWith("/") && (t = t.slice(0, -1)),
    r.prependPathname ? `${t}/.well-known/${e}` : `/.well-known/${e}${t}`
  );
}
async function B(e, t, r = fetch) {
  return await Z(e, { "MCP-Protocol-Version": t }, r);
}
function be(e, t) {
  return !e || (e.status >= 400 && e.status < 500 && t !== "/");
}
async function Ee(e, t, r, o) {
  var i, c;
  const l = new URL(e),
    a = (i = o?.protocolVersion) !== null && i !== void 0 ? i : J;
  let u;
  if (o?.metadataUrl) u = new URL(o.metadataUrl);
  else {
    const d = Ce(t, l.pathname);
    ((u = new URL(
      d,
      (c = o?.metadataServerUrl) !== null && c !== void 0 ? c : l,
    )),
      (u.search = l.search));
  }
  let p = await B(u, a, r);
  if (!o?.metadataUrl && be(p, l.pathname)) {
    const d = new URL(`/.well-known/${t}`, l);
    p = await B(d, a, r);
  }
  return p;
}
function Te(e) {
  const t = typeof e == "string" ? new URL(e) : e,
    r = t.pathname !== "/",
    o = [];
  if (!r)
    return (
      o.push({
        url: new URL("/.well-known/oauth-authorization-server", t.origin),
        type: "oauth",
      }),
      o.push({
        url: new URL("/.well-known/openid-configuration", t.origin),
        type: "oidc",
      }),
      o
    );
  let i = t.pathname;
  return (
    i.endsWith("/") && (i = i.slice(0, -1)),
    o.push({
      url: new URL(`/.well-known/oauth-authorization-server${i}`, t.origin),
      type: "oauth",
    }),
    o.push({
      url: new URL("/.well-known/oauth-authorization-server", t.origin),
      type: "oauth",
    }),
    o.push({
      url: new URL(`/.well-known/openid-configuration${i}`, t.origin),
      type: "oidc",
    }),
    o.push({
      url: new URL(`${i}/.well-known/openid-configuration`, t.origin),
      type: "oidc",
    }),
    o
  );
}
async function Ae(e, { fetchFn: t = fetch, protocolVersion: r = J } = {}) {
  const o = { "MCP-Protocol-Version": r, Accept: "application/json" },
    i = Te(e);
  for (const { url: c, type: l } of i) {
    const a = await Z(c, o, t);
    if (a) {
      if (!a.ok) {
        if (a.status >= 400 && a.status < 500) continue;
        throw new Error(
          `HTTP ${a.status} trying to load ${l === "oauth" ? "OAuth" : "OpenID provider"} metadata from ${c}`,
        );
      }
      return l === "oauth" ? Y.parse(await a.json()) : ue.parse(await a.json());
    }
  }
}
async function Le(
  e,
  {
    metadata: t,
    clientInformation: r,
    redirectUrl: o,
    scope: i,
    state: c,
    resource: l,
  },
) {
  let a;
  if (t) {
    if (
      ((a = new URL(t.authorization_endpoint)),
      !t.response_types_supported.includes(T))
    )
      throw new Error(
        `Incompatible auth server: does not support response type ${T}`,
      );
    if (
      t.code_challenge_methods_supported &&
      !t.code_challenge_methods_supported.includes(A)
    )
      throw new Error(
        `Incompatible auth server: does not support code challenge method ${A}`,
      );
  } else a = new URL("/authorize", e);
  const u = await ae(),
    p = u.code_verifier,
    d = u.code_challenge;
  return (
    a.searchParams.set("response_type", T),
    a.searchParams.set("client_id", r.client_id),
    a.searchParams.set("code_challenge", d),
    a.searchParams.set("code_challenge_method", A),
    a.searchParams.set("redirect_uri", String(o)),
    c && a.searchParams.set("state", c),
    i && a.searchParams.set("scope", i),
    i?.includes("offline_access") && a.searchParams.append("prompt", "consent"),
    l && a.searchParams.set("resource", l.href),
    { authorizationUrl: a, codeVerifier: p }
  );
}
async function Oe(
  e,
  {
    metadata: t,
    clientInformation: r,
    authorizationCode: o,
    codeVerifier: i,
    redirectUri: c,
    resource: l,
    addClientAuthentication: a,
    fetchFn: u,
  },
) {
  var p;
  const d = "authorization_code",
    w = t?.token_endpoint ? new URL(t.token_endpoint) : new URL("/token", e);
  if (t?.grant_types_supported && !t.grant_types_supported.includes(d))
    throw new Error(
      `Incompatible auth server: does not support grant type ${d}`,
    );
  const y = new Headers({
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json",
    }),
    m = new URLSearchParams({
      grant_type: d,
      code: o,
      code_verifier: i,
      redirect_uri: String(c),
    });
  if (a) a(y, m, e, t);
  else {
    const f =
        (p = t?.token_endpoint_auth_methods_supported) !== null && p !== void 0
          ? p
          : [],
      E = Q(r, f);
    X(E, r, y, m);
  }
  l && m.set("resource", l.href);
  const v = await (u ?? fetch)(w, { method: "POST", headers: y, body: m });
  if (!v.ok) throw await N(v);
  return K.parse(await v.json());
}
async function Pe(
  e,
  {
    metadata: t,
    clientInformation: r,
    refreshToken: o,
    resource: i,
    addClientAuthentication: c,
    fetchFn: l,
  },
) {
  var a;
  const u = "refresh_token";
  let p;
  if (t) {
    if (
      ((p = new URL(t.token_endpoint)),
      t.grant_types_supported && !t.grant_types_supported.includes(u))
    )
      throw new Error(
        `Incompatible auth server: does not support grant type ${u}`,
      );
  } else p = new URL("/token", e);
  const d = new Headers({
      "Content-Type": "application/x-www-form-urlencoded",
    }),
    w = new URLSearchParams({ grant_type: u, refresh_token: o });
  if (c) c(d, w, e, t);
  else {
    const m =
        (a = t?.token_endpoint_auth_methods_supported) !== null && a !== void 0
          ? a
          : [],
      v = Q(r, m);
    X(v, r, d, w);
  }
  i && w.set("resource", i.href);
  const y = await (l ?? fetch)(p, { method: "POST", headers: d, body: w });
  if (!y.ok) throw await N(y);
  return K.parse({ refresh_token: o, ...(await y.json()) });
}
async function xe(e, { metadata: t, clientMetadata: r, fetchFn: o }) {
  let i;
  if (t) {
    if (!t.registration_endpoint)
      throw new Error(
        "Incompatible auth server: does not support dynamic client registration",
      );
    i = new URL(t.registration_endpoint);
  } else i = new URL("/register", e);
  const c = await (o ?? fetch)(i, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(r),
  });
  if (!c.ok) throw await N(c);
  return he.parse(await c.json());
}
export { $e as U, je as a, ze as e };
//# sourceMappingURL=auth-DECY5s84.mjs.map
