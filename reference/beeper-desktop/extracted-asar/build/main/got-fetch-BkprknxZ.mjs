import { g as o } from "./got-_wC7Q_ix.mjs";
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
      (e._sentryDebugIds[t] = "ecff3960-78eb-40de-952b-2f6e1687297e"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-ecff3960-78eb-40de-952b-2f6e1687297e"));
  } catch {}
})();
class n {
  async requestAsString(t, r) {
    const s = await o({
      throwHttpErrors: !1,
      url: t,
      ...r,
      responseType: "text",
    });
    return { statusCode: s.statusCode, headers: s.headers, body: s.body };
  }
  async requestAsBuffer(t, r) {
    const s = await o({
      throwHttpErrors: !1,
      url: t,
      ...r,
      responseType: "buffer",
    });
    return { statusCode: s.statusCode, headers: s.headers, body: s.body };
  }
}
const a = () => new n();
export { a as c };
//# sourceMappingURL=got-fetch-BkprknxZ.mjs.map
