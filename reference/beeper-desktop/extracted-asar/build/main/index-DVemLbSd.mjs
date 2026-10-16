import { O as u, r as n, i as l, b as f } from "./client-DMtubo6I.mjs";
import { A as xr, P as Tr, t as Dr } from "./client-DMtubo6I.mjs";
import { O as a } from "./index-BJhQkpW6.mjs";
import {
  A as Vr,
  a as kr,
  b as qr,
  c as Lr,
  d as Zr,
  B as Cr,
  h as Hr,
  k as Mr,
  l as Yr,
  N as $r,
  P as jr,
  R as zr,
  U as Fr,
} from "./index-BJhQkpW6.mjs";
import "crypto";
import "worker_threads";
import "./Keychain-CHHka2u7.mjs";
import "./constants-BL_pdRyX.mjs";
import "path";
import "os";
import "url";
import "./index-DKkZ9dV1.mjs";
import "fs";
import "./util-CrY9x2BW.mjs";
import "./_commonjsHelpers-CBUqixCJ.mjs";
import "./sentry-common-CDPx3Glo.mjs";
import "./package-CIHfweXK.mjs";
import "./sentry-enabled-COAVq6nC.mjs";
import "tty";
import "node:crypto";
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
import "node:stream";
import "node:child_process";
import "node:events";
import "node:os";
import "./index-CMOlVndj.mjs";
import "assert";
import "events";
import "buffer";
import "stream";
import "util";
import "node:fs";
import "node:module";
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
    var r = new e.Error().stack;
    r &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[r] = "39c3eee2-4fe3-47c6-9800-5d287ef0a6d4"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-39c3eee2-4fe3-47c6-9800-5d287ef0a6d4"));
  } catch {}
})();
class Rr extends u {
  constructor({
    baseURL: r = n("OPENAI_BASE_URL"),
    apiKey: t = n("AZURE_OPENAI_API_KEY"),
    apiVersion: i = n("OPENAI_API_VERSION"),
    endpoint: o,
    deployment: d,
    azureADTokenProvider: p,
    dangerouslyAllowBrowser: m,
    ...s
  } = {}) {
    if (!i)
      throw new a(
        "The OPENAI_API_VERSION environment variable is missing or empty; either provide it, or instantiate the AzureOpenAI client with an apiVersion option, like new AzureOpenAI({ apiVersion: 'My API Version' }).",
      );
    if ((typeof p == "function" && (m = !0), !p && !t))
      throw new a(
        "Missing credentials. Please pass one of `apiKey` and `azureADTokenProvider`, or set the `AZURE_OPENAI_API_KEY` environment variable.",
      );
    if (p && t)
      throw new a(
        "The `apiKey` and `azureADTokenProvider` arguments are mutually exclusive; only one can be passed at a time.",
      );
    if (((s.defaultQuery = { ...s.defaultQuery, "api-version": i }), r)) {
      if (o) throw new a("baseURL and endpoint are mutually exclusive");
    } else {
      if ((o || (o = process.env.AZURE_OPENAI_ENDPOINT), !o))
        throw new a(
          "Must provide one of the `baseURL` or `endpoint` arguments, or the `AZURE_OPENAI_ENDPOINT` environment variable",
        );
      r = `${o}/openai`;
    }
    (super({
      apiKey: p ?? t,
      baseURL: r,
      ...s,
      ...(m !== void 0 ? { dangerouslyAllowBrowser: m } : {}),
    }),
      (this.apiVersion = ""),
      (this.apiVersion = i),
      (this.deploymentName = d));
  }
  async buildRequest(r, t = {}) {
    if (E.has(r.path) && r.method === "post" && r.body !== void 0) {
      if (!l(r.body)) throw new Error("Expected request body to be an object");
      const i = this.deploymentName || r.body.model || r.__metadata?.model;
      i !== void 0 &&
        !this.baseURL.includes("/deployments") &&
        (r.path = `/deployments/${i}${r.path}`);
    }
    return super.buildRequest(r, t);
  }
  async authHeaders(r) {
    return typeof this._options.apiKey == "string"
      ? f([{ "api-key": this.apiKey }])
      : super.authHeaders(r);
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
  Vr as APIConnectionError,
  kr as APIConnectionTimeoutError,
  qr as APIError,
  xr as APIPromise,
  Lr as APIUserAbortError,
  Zr as AuthenticationError,
  Rr as AzureOpenAI,
  Cr as BadRequestError,
  Hr as ConflictError,
  Mr as InternalServerError,
  Yr as InvalidWebhookSignatureError,
  $r as NotFoundError,
  u as OpenAI,
  a as OpenAIError,
  Tr as PagePromise,
  jr as PermissionDeniedError,
  zr as RateLimitError,
  Fr as UnprocessableEntityError,
  u as default,
  Dr as toFile,
};
//# sourceMappingURL=index-DVemLbSd.mjs.map
