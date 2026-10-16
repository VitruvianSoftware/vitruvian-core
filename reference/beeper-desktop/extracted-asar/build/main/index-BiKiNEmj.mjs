import * as c from "node:path";
import * as o from "node:module";
import p from "node:module";
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
      (i._sentryDebugIds[e] = "e3ce1ca3-2ac9-4599-adec-d3ffa8beb448"),
      (i._sentryDebugIdIdentifier =
        "sentry-dbid-e3ce1ca3-2ac9-4599-adec-d3ffa8beb448"));
  } catch {}
})();
const y = import.meta.filename,
  m = import.meta.dirname,
  b = p.createRequire(import.meta.url),
  d = { napi_versions: [8] },
  _ = { binary: d },
  h = o.createRequire(import.meta.url),
  { BeeperClient: f } = h(
    c.join(
      import.meta.dirname,
      "lib",
      `napi-v${_.binary.napi_versions}`,
      "beeper_client_sdk_napi_binding.node",
    ),
  );
class a extends Error {
  internalError;
  displayError;
  canRetry;
  methodName;
  constructor(e, t) {
    if (e && typeof e == "object" && e.internalError !== void 0)
      (super(e.displayError || e.internalError),
        (this.name = "SDKError"),
        (this.internalError = e.internalError),
        (this.displayError = e.displayError),
        (this.canRetry = !!e.canRetry),
        (this.message = this.displayError || this.internalError),
        t && (this.message = `${t} failed: ${this.message}`));
    else if (e instanceof Error)
      (super(e.message),
        (this.name = "SDKError"),
        (this.message = t ? `${t} failed: ${e.message}` : e.message),
        (this.cause = e),
        (this.internalError = e.message),
        (this.displayError = ""),
        (this.canRetry = !1));
    else
      throw new TypeError(
        "SDKError is only constructible from an upstream Error or SDKError object",
      );
    ((this.methodName = t), Error.captureStackTrace?.(this, a));
  }
  static getDisplayErrorMessage(e) {
    let t;
    return (
      typeof e == "object" &&
      e !== null &&
      "name" in e &&
      e.name === "SDKError" &&
      ("internalError" in e || "displayError" in e)
        ? (t = e.displayError || e.internalError)
        : e instanceof Error && (t = e.message),
      t && t.trim().length > 0 ? t : "Something went wrong"
    );
  }
}
let g = class l {
  constructor(e) {
    ((this.__native = new f(
      e.dataDirPath,
      e.deviceName,
      e.appVersion,
      e.deviceModel,
      e.deviceType,
      e.callback,
      e.appType ?? (process.env.BEEPER_SERVER_EDITION ? "server" : "desktop"),
    )),
      (this.__cancelables = new Set()),
      (this.__disposed = !1));
    for (let t in this.__native)
      t in l.prototype || (l.prototype[t] = this.wrapMethod(t));
  }
  async dispose() {
    this.__disposed = !0;
    for (let e of this.__cancelables) e("client disposed");
    return (await this.__native.stop(), this.__native.releaseFFICallbacks());
  }
  wrapMethod =
    (e) =>
    (...t) => {
      if (this.__disposed) throw new a(new Error("SDK is disposed"), e);
      try {
        const s = this.__native[e](...t);
        if (s?.__sdkCancelable) {
          const n = s.cancelWithCause;
          return (
            this.__cancelables.add(n),
            s?.promise.then(
              (r) => (this.__cancelables.delete(n), r),
              (r) => {
                throw (this.__cancelables.delete(n), new a(r, e));
              },
            )
          );
        }
        return s?.then
          ? s.catch((n) => {
              throw new a(n, e);
            })
          : s;
      } catch (s) {
        throw new a(s, e);
      }
    };
};
export { g as BeeperClient, a as SDKError };
//# sourceMappingURL=index-BiKiNEmj.mjs.map
