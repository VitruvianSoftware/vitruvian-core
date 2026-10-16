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
      (t._sentryDebugIds[e] = "b7908d8d-227c-4e30-8bb5-fee95ccbfdd9"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-b7908d8d-227c-4e30-8bb5-fee95ccbfdd9"));
  } catch {}
})();
class a {
  constructor(e) {
    this.html = e;
  }
  parseTags(...e) {
    const s = (n) => new RegExp(`<${n}[^>]*>(.*?)</${n}>`, "gi"),
      d = new Map();
    for (const n of e) {
      const c = s(n),
        r = [];
      let o;
      for (; (o = c.exec(this.html)) !== null;) r.push(o[1]);
      d.set(n, r);
    }
    return d;
  }
  static removeHtmlTags(e) {
    const s = /(<([^>]+)>)/gi;
    return e.replace(s, "");
  }
}
export { a as default };
//# sourceMappingURL=SimpleHTMLParser-DYKa0uJQ.mjs.map
