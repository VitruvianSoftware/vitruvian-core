import i from "os";
import { c as s } from "./got-fetch-BkprknxZ.mjs";
import n from "./package-CIHfweXK.mjs";
import { M as d } from "./machine-id-DFkLVgcU.mjs";
import "./got-_wC7Q_ix.mjs";
import "./_commonjsHelpers-CBUqixCJ.mjs";
import "url";
import "events";
import "util";
import "stream";
import "fs";
import "http";
import "https";
import "dns";
import "buffer";
import "zlib";
import "http2";
import "tls";
import "net";
import "./constants-BL_pdRyX.mjs";
import "path";
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
    var o = new t.Error().stack;
    o &&
      ((t._sentryDebugIds = t._sentryDebugIds || {}),
      (t._sentryDebugIds[o] = "0f92ebb2-ba76-485a-9f6d-6f0b79403ca6"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-0f92ebb2-ba76-485a-9f6d-6f0b79403ca6"));
  } catch {}
})();
const a = `${process.platform} ${i.release()} ${i.arch()}`,
  m = { "x-device-id": d, "x-app-version": n.version, "x-os": a },
  f = s();
async function R(t, o, r, p) {
  const e = await f.requestAsString(o, {
    method: t,
    headers: { ...m, ...r },
    body: p || void 0,
  });
  return { statusCode: e.statusCode, body: e.body };
}
export { R as callAppAPI };
//# sourceMappingURL=app-api-NqP9XGk0.mjs.map
