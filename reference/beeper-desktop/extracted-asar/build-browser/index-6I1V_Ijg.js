import { O as p, g as s, r as u, j as m, i as E } from "./client-Czi1iXro.js";
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
} from "./client-Czi1iXro.js";
import "./matrix-util-8DbIGEm-.js";
import "./sentry-common-BNqrY_yc.js";
import "./index-Cw3pknxT.js";
import "./main-process-state-BDOn7dvV.js";
import "./index-5FBEE1WD.js";
import "./index-Ch31Akxs.js";
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
      (r._sentryDebugIds[e] = "69c70920-865b-48dc-a3e6-5f4396b6e33b"),
      (r._sentryDebugIdIdentifier =
        "sentry-dbid-69c70920-865b-48dc-a3e6-5f4396b6e33b"));
  } catch {}
})();
var f = {};
class v extends p {
  constructor({
    baseURL: e = u("OPENAI_BASE_URL"),
    apiKey: t = u("AZURE_OPENAI_API_KEY"),
    apiVersion: i = u("OPENAI_API_VERSION"),
    endpoint: a,
    deployment: l,
    azureADTokenProvider: n,
    dangerouslyAllowBrowser: o,
    ...d
  } = {}) {
    if (!i)
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
    if (((d.defaultQuery = { ...d.defaultQuery, "api-version": i }), e)) {
      if (a) throw new s("baseURL and endpoint are mutually exclusive");
    } else {
      if ((a || (a = f.AZURE_OPENAI_ENDPOINT), !a))
        throw new s(
          "Must provide one of the `baseURL` or `endpoint` arguments, or the `AZURE_OPENAI_ENDPOINT` environment variable",
        );
      e = `${a}/openai`;
    }
    (super({
      apiKey: n ?? t,
      baseURL: e,
      ...d,
      ...(o !== void 0 ? { dangerouslyAllowBrowser: o } : {}),
    }),
      (this.apiVersion = ""),
      (this.apiVersion = i),
      (this.deploymentName = l));
  }
  async buildRequest(e, t = {}) {
    if (c.has(e.path) && e.method === "post" && e.body !== void 0) {
      if (!m(e.body)) throw new Error("Expected request body to be an object");
      const i = this.deploymentName || e.body.model || e.__metadata?.model;
      i !== void 0 &&
        !this.baseURL.includes("/deployments") &&
        (e.path = `/deployments/${i}${e.path}`);
    }
    return super.buildRequest(e, t);
  }
  async authHeaders(e) {
    return typeof this._options.apiKey == "string"
      ? E([{ "api-key": this.apiKey }])
      : super.authHeaders(e);
  }
}
const c = new Set([
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
  p as OpenAI,
  s as OpenAIError,
  C as PagePromise,
  L as PermissionDeniedError,
  Z as RateLimitError,
  j as UnprocessableEntityError,
  p as default,
  k as toFile,
};
//# sourceMappingURL=index-6I1V_Ijg.js.map
