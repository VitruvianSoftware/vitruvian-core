import a from "child_process";
import i from "path";
import { e as c } from "./index-CMOlVndj.mjs";
import { i as s } from "./AsyncSqlite-CpInlfQ-.mjs";
import { PUBLIC_DIR_PATH_UNPACKED as d } from "./constants-BL_pdRyX.mjs";
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
      (t._sentryDebugIds[n] = "b33edd08-33a0-450e-8787-91a7a306cb75"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-b33edd08-33a0-450e-8787-91a7a306cb75"));
  } catch {}
})();
const o = i.join(d, "ContactsServer");
async function f(t) {
  s && console.time("macos contacts server exec");
  const { stdout: n } = await c(o, [t]);
  if ((s && console.timeEnd("macos contacts server exec"), !n.startsWith("{")))
    throw (
      logger.error("contacts server non-json response", n),
      Error("contacts server non-json response")
    );
  s && console.time("macos contacts server parse");
  const r = JSON.parse(n);
  return (
    s && console.timeEnd("macos contacts server parse"),
    { data: r, size: n.length }
  );
}
const b = async () => {
  const t = (e) =>
      typeof e != "object" || e == null || !("identifier" in e)
        ? !1
        : (Object.assign(e, { id: e.identifier }), "id" in e),
    n = (e) =>
      typeof e.data == "object" &&
      e.data != null &&
      "response" in e.data &&
      Array.isArray(e.data.response) &&
      e.data.response.every(t),
    r = await f("fetch-all");
  if (!n(r))
    throw new Error(
      "ContactsServer returned malformed data when trying to fetch all contacts",
    );
  return r;
};
function h(t) {
  const n = a.spawn(o, ["listen"]);
  (n.stdout.on("data", (r) => {
    r.toString().includes("contacts_changed") && t();
  }),
    n.on("error", (r) => {
      (logger.error("ContactsServer.listenForContactsChanges -> cp.error", r),
        globalThis.Sentry.captureException(r));
    }));
}
export { b as f, h as l };
//# sourceMappingURL=macos-contacts-server-D9gt4gn9.mjs.map
