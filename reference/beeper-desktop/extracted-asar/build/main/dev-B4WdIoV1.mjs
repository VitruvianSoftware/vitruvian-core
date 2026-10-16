import c from "node:module";
import { normalize as v, sep as u, join as p } from "node:path";
import { fileURLToPath as m } from "node:url";
import {
  IS_WINDOWS as _,
  IS_MAC_OS as h,
  IS_LINUX as g,
} from "./constants-BL_pdRyX.mjs";
import "path";
import "os";
import "url";
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
    var o = new e.Error().stack;
    o &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[o] = "ae3fbfc6-0654-44d0-8113-ead6e6e270d4"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-ae3fbfc6-0654-44d0-8113-ead6e6e270d4"));
  } catch {}
})();
function C() {}
function D() {
  const e = {
    "beeper_client_sdk_napi_binding.node": "@beeper/beeper-client-sdk/node",
    "diskusage.node": "diskusage",
    "better_sqlite3.node": "better-sqlite3",
    "permissions.node": "node-mac-permissions",
    "contacts.node": "node-mac-contacts",
    "node.napi.node": "utf-8-validate",
    "cbor-extract.node": "cbor-extract",
  };
  function o() {
    if (_)
      return `classic-level/prebuilds/win32-${process.arch === "x64" ? "x64" : "ia32"}/classic-level.node`;
    if (h) return "classic-level/prebuilds/darwin-x64+arm64/classic-level.node";
    const s =
      g && process.report?.getReport()?.header?.glibcVersionRuntime === void 0;
    return process.arch === "arm64"
      ? "classic-level/prebuilds/linux-arm64/classic-level.armv8.node"
      : `classic-level/prebuilds/linux-x64/classic-level${s ? ".musl" : ""}.node`;
  }
  const n = c._resolveFilename;
  c._resolveFilename = function (...t) {
    const [i] = t;
    if (!i.endsWith(".node")) return n(...t);
    const r = v(i).split(u),
      l = r.at(-1);
    if (!l) return n(...t);
    const d = "../../";
    if (i.includes("classic-level"))
      return m(new URL(p(d, "node_modules", o()), import.meta.url));
    const a = e[l];
    if (!a) return n(...t);
    const f = r.slice(-3).join(u),
      b = p(d, "node_modules", a, f);
    return m(new URL(b, import.meta.url));
  };
}
export { C as addAppNodeModulesPath, D as registerNativeModuleResolutionHooks };
//# sourceMappingURL=dev-B4WdIoV1.mjs.map
