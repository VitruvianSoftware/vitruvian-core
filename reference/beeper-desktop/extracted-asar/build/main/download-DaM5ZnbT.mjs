import l from "path";
import p from "fs";
import b from "url";
import { pipeline as u } from "stream/promises";
import { g as d } from "./got-_wC7Q_ix.mjs";
import "./_commonjsHelpers-CBUqixCJ.mjs";
import "events";
import "util";
import "stream";
import "http";
import "https";
import "dns";
import "os";
import "buffer";
import "zlib";
import "http2";
import "tls";
import "net";
import "./constants-BL_pdRyX.mjs";
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
    var r = new t.Error().stack;
    r &&
      ((t._sentryDebugIds = t._sentryDebugIds || {}),
      (t._sentryDebugIds[r] = "e9168b74-9d80-4456-a111-6772b1b8f8ff"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-e9168b74-9d80-4456-a111-6772b1b8f8ff"));
  } catch {}
})();
function w(t) {
  if (!/^data:/i.test(t))
    throw new TypeError(
      '`uri` does not appear to be a Data URI (must begin with "data:")',
    );
  t = t.replace(/\r?\n/g, "");
  const r = t.indexOf(",");
  if (r === -1 || r <= 4) throw new TypeError("malformed data: URI");
  const e = t.substring(5, r).split(";");
  let o = "",
    a = !1;
  const i = e[0] || "text/plain";
  let n = i;
  for (let s = 1; s < e.length; s++)
    e[s] === "base64"
      ? (a = !0)
      : e[s] &&
        ((n += `;${e[s]}`),
        e[s].indexOf("charset=") === 0 && (o = e[s].substring(8)));
  !e[0] && !o.length && ((n += ";charset=US-ASCII"), (o = "US-ASCII"));
  const m = a ? "base64" : "ascii",
    c = unescape(t.substring(r + 1)),
    f = Buffer.from(c, m);
  return ((f.type = i), (f.typeFull = n), (f.charset = o), f);
}
async function g(t, r, e) {
  const o = l.join(r, e),
    a = l.relative(r, o);
  if (!a || a === ".." || a.startsWith(`..${l.sep}`) || l.isAbsolute(a))
    throw new Error(`Refusing to download outside ${r}: ${e}`);
  if (t.protocol === "file:") await p.promises.copyFile(b.fileURLToPath(t), o);
  else if (t.protocol === "data:") {
    const i = w(t.href);
    await p.promises.writeFile(o, i);
  } else
    try {
      await u(d.stream(t), p.createWriteStream(o));
    } catch (i) {
      if (i.code === "ERR_INVALID_PROTOCOL") {
        logger.error(i);
        const n = await d.head(t, { followRedirect: !1 });
        return g(
          new URL(n.headers.location.replace("fileproxy://", "file://")),
          r,
          e,
        );
      }
      throw i;
    }
  return o;
}
export { g as downloadFile };
//# sourceMappingURL=download-DaM5ZnbT.mjs.map
