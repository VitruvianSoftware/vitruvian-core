import u from "crypto";
(function () {
  try {
    var n =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    n.SENTRY_RELEASE = { id: "4.3.209" };
    var i = new n.Error().stack;
    i &&
      ((n._sentryDebugIds = n._sentryDebugIds || {}),
      (n._sentryDebugIds[i] = "3783cde1-0a29-4e25-b755-89c80c469ed0"),
      (n._sentryDebugIdIdentifier =
        "sentry-dbid-3783cde1-0a29-4e25-b755-89c80c469ed0"));
  } catch {}
})();
const r = new Uint8Array(256);
let l = r.length;
function o() {
  return (
    l > r.length - 16 && (u.randomFillSync(r), (l = 0)),
    r.slice(l, (l += 16))
  );
}
const y =
  /^(?:[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}|00000000-0000-0000-0000-000000000000)$/i;
function g(n) {
  return typeof n == "string" && y.test(n);
}
const e = [];
for (let n = 0; n < 256; ++n) e.push((n + 256).toString(16).substr(1));
function s(n, i = 0) {
  const t = (
    e[n[i + 0]] +
    e[n[i + 1]] +
    e[n[i + 2]] +
    e[n[i + 3]] +
    "-" +
    e[n[i + 4]] +
    e[n[i + 5]] +
    "-" +
    e[n[i + 6]] +
    e[n[i + 7]] +
    "-" +
    e[n[i + 8]] +
    e[n[i + 9]] +
    "-" +
    e[n[i + 10]] +
    e[n[i + 11]] +
    e[n[i + 12]] +
    e[n[i + 13]] +
    e[n[i + 14]] +
    e[n[i + 15]]
  ).toLowerCase();
  if (!g(t)) throw TypeError("Stringified UUID is invalid");
  return t;
}
function b(n, i, t) {
  n = n || {};
  const d = n.random || (n.rng || o)();
  if (((d[6] = (d[6] & 15) | 64), (d[8] = (d[8] & 63) | 128), i)) {
    t = t || 0;
    for (let c = 0; c < 16; ++c) i[t + c] = d[c];
    return i;
  }
  return s(d);
}
export { g as a, o as r, s, b as v };
//# sourceMappingURL=v4-BcIr5opf.mjs.map
