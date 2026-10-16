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
    var n = new t.Error().stack;
    n &&
      ((t._sentryDebugIds = t._sentryDebugIds || {}),
      (t._sentryDebugIds[n] = "538c1cce-b24d-4834-b793-cbe4a101bb78"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-538c1cce-b24d-4834-b793-cbe4a101bb78"));
  } catch {}
})();
const u = (t, n = "") => `data:${n};base64,${t.toString("base64")}`,
  f = (t) => Array.isArray(t),
  g = (t) => typeof t == "string",
  b = (t) => typeof t == "object" && t !== null,
  d = (t) => b(t) && t.type === "Buffer" && (f(t.data) || g(t.data)),
  c = (t) => t instanceof Error,
  l = (t, n) =>
    JSON.stringify(
      t,
      (s, r) =>
        c(r)
          ? { message: r.message, name: r.name, cause: r.cause }
          : typeof r == "bigint"
            ? r.toString()
            : d(r)
              ? u(Buffer.from(r.data))
              : r,
      n,
    );
function h(t, n) {
  try {
    return JSON.parse(t);
  } catch {
    return n;
  }
}
class y {
  constructor(n, s = []) {
    ((this.content = n), (this.exclusions = s));
  }
  toOriginal() {
    return this.content;
  }
  toRedactedString(n, s = !1) {
    const { exclusions: r } = this,
      e = s ? n : this.content;
    switch (typeof e) {
      case "boolean":
        return `boolean:${e}`;
      case "string":
        return `string:string[${e.length}]`;
      case "bigint":
        return `bigint:${e}`;
      case "function":
        return `function:${e}`;
      case "number":
        return `number:${e}`;
      case "undefined":
        return "undefined:undefined";
      case "symbol":
        return "symbol:symbol";
      case "object":
        return e === null
          ? "object:null"
          : Array.isArray(e) && e.length > 0
            ? e.map((i) => this.toRedactedString(i, !0))
            : e instanceof Date
              ? `object:${e.toISOString()}`
              : e instanceof RegExp
                ? `object:${e.source}`
                : JSON.stringify(
                    Object.entries(e).reduce(
                      (i, [o, a]) => ({
                        ...i,
                        [o]: r.includes(o) ? n : this.toRedactedString(a, !0),
                      }),
                      {},
                    ),
                  );
      default:
        return "unknown";
    }
  }
}
const S = (t) => (c(t) ? String(t) : l(t)),
  p = (t) => logger.log(`[AppStart] ${t}`),
  m = Object.freeze(
    Object.defineProperty(
      {
        __proto__: null,
        RedactedContent: y,
        logAppStart: p,
        stringifyForLogMessage: S,
      },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  );
export { y as R, m as a, S as b, p as l, l as s, h as t };
//# sourceMappingURL=logger-DoW0T1f3.mjs.map
