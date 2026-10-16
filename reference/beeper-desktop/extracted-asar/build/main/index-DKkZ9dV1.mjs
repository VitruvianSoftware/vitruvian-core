import { workerData as s } from "worker_threads";
import { USER_CONF_PATH as n } from "./constants-BL_pdRyX.mjs";
import { readFileSync as o, promises as r } from "fs";
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
      (e._sentryDebugIds[t] = "5c941b26-7ef3-48d2-977a-8e990d90f2de"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-5c941b26-7ef3-48d2-977a-8e990d90f2de"));
  } catch {}
})();
const y = (e) =>
    r
      .access(e)
      .then(() => !0)
      .catch(() => !1),
  h = (e) =>
    r
      .stat(e)
      .then((t) => t.size > 0)
      .catch(() => !1),
  a = (e) => {
    try {
      return JSON.parse(o(e, { encoding: "utf-8" }));
    } catch {}
  },
  d = s ? s.userConf : a(n),
  c = d ?? {},
  p = c.hw_acceleration ?? !0;
export { h as a, p as h, y as p, c as u };
//# sourceMappingURL=index-DKkZ9dV1.mjs.map
