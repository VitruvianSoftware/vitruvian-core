import { O as l, g as s, r as u, j as c, i as p } from "./client-CsqrubtG.js";
import {
  A as O,
  a as w,
  b as R,
  c as U,
  d as S,
  e as T,
  B as x,
  C as D,
  I as K,
  f as V,
  N as q,
  P as C,
  h as L,
  R as Z,
  U as j,
  t as k,
} from "./client-CsqrubtG.js";
import "./matrix-util-Cr_UwXbj.js";
import "./sentry-common-BxRELKId.js";
import "./index-Cw3pknxT.js";
import "./main-process-state-wkFhis-C.js";
import "./index-Dhe7xemD.js";
import "./index-CcYzEQCb.js";
(function () {
  try {
    var r =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    r.SENTRY_RELEASE = { id: "4.3.209" };
    var e = new r.Error().stack;
    e &&
      ((r._sentryDebugIds = r._sentryDebugIds || {}),
      (r._sentryDebugIds[e] = "c2574bc9-df2e-48ce-9edf-c79efaedc6a6"),
      (r._sentryDebugIdIdentifier =
        "sentry-dbid-c2574bc9-df2e-48ce-9edf-c79efaedc6a6"));
  } catch {}
})();
var m = {};
class v extends l {
  constructor({
    baseURL: e = u("OPENAI_BASE_URL"),
    apiKey: t = u("AZURE_OPENAI_API_KEY"),
    apiVersion: a = u("OPENAI_API_VERSION"),
    endpoint: i,
    deployment: f,
    azureADTokenProvider: n,
    dangerouslyAllowBrowser: o,
    ...d
  } = {}) {
    if (!a)
      throw new s(
        "The OPENAI_API_VERSION environment variable is missing or empty; either provide it, or instantiate the AzureOpenAI client with an apiVersion option, like new AzureOpenAI({ apiVersion: 'My API Version' }).",
      );
    if ((typeof n == "function" && (o = !0), !n && !t))
      throw new s(
        "Missing credentials. Please pass one of `apiKey` and `azureADTokenProvider`, or set the `AZURE_OPENAI_API_KEY` environment variable.",
      );
    if (n && t)
      throw new s(
        "The `apiKey` and `azureADTokenProvider` arguments are mutually exclusive; only one can be passed at a time.",
      );
    if (((d.defaultQuery = { ...d.defaultQuery, "api-version": a }), e)) {
      if (i) throw new s("baseURL and endpoint are mutually exclusive");
    } else {
      if ((i || (i = m.AZURE_OPENAI_ENDPOINT), !i))
        throw new s(
          "Must provide one of the `baseURL` or `endpoint` arguments, or the `AZURE_OPENAI_ENDPOINT` environment variable",
        );
      e = `${i}/openai`;
    }
    (super({
      apiKey: n ?? t,
      baseURL: e,
      ...d,
      ...(o !== void 0 ? { dangerouslyAllowBrowser: o } : {}),
    }),
      (this.apiVersion = ""),
      (this.apiVersion = a),
      (this.deploymentName = f));
  }
  async buildRequest(e, t = {}) {
    if (E.has(e.path) && e.method === "post" && e.body !== void 0) {
      if (!c(e.body)) throw new Error("Expected request body to be an object");
      const a = this.deploymentName || e.body.model || e.__metadata?.model;
      a !== void 0 &&
        !this.baseURL.includes("/deployments") &&
        (e.path = `/deployments/${a}${e.path}`);
    }
    return super.buildRequest(e, t);
  }
  async authHeaders(e) {
    return typeof this._options.apiKey == "string"
      ? p([{ "api-key": this.apiKey }])
      : super.authHeaders(e);
  }
}
const E = new Set([
  "/completions",
  "/chat/completions",
  "/embeddings",
  "/audio/transcriptions",
  "/audio/translations",
  "/audio/speech",
  "/images/generations",
  "/batches",
  "/images/edits",
]);
export {
  O as APIConnectionError,
  w as APIConnectionTimeoutError,
  R as APIError,
  U as APIPromise,
  S as APIUserAbortError,
  T as AuthenticationError,
  v as AzureOpenAI,
  x as BadRequestError,
  D as ConflictError,
  K as InternalServerError,
  V as InvalidWebhookSignatureError,
  q as NotFoundError,
  l as OpenAI,
  s as OpenAIError,
  C as PagePromise,
  L as PermissionDeniedError,
  Z as RateLimitError,
  j as UnprocessableEntityError,
  l as default,
  k as toFile,
};
//# sourceMappingURL=index-PJhymApj.js.map
