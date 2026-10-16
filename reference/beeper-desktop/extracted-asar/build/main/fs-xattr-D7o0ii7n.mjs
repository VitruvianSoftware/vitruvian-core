import a from "crypto";
import t from "fs";
import { e as s } from "./index-CMOlVndj.mjs";
import {
  IS_MAC_OS as r,
  IS_VENTURA_OR_UP as f,
  IS_WINDOWS as i,
  IS_LINUX as d,
} from "./constants-BL_pdRyX.mjs";
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
    var n = new e.Error().stack;
    n &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[n] = "fe79ba1d-04c3-41e3-8cd7-a419aa653032"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-fe79ba1d-04c3-41e3-8cd7-a419aa653032"));
  } catch {}
})();
function c() {
  if (r) return f ? "System Settings" : "System Preferences";
  if (i) return "Windows Settings";
  if (d) return "Settings/Preferences";
}
const _ = Object.freeze({
    BRAND_NAME: "Beeper",
    APP_NAME: "Beeper",
    BROWSER_EXTENSION_NAME: "Beeper browser extension",
    SYSTEM_PREFS_LABEL: c(),
    TRAY_NAME: r ? "Menu Bar" : "Tray",
    SHOW_IN_FOLDER_LABEL: r ? "Show in Finder" : "Show in folder",
  }),
  S = Buffer.from(`[ZoneTransfer]\r
ZoneId=3`);
async function o(e) {
  if (!t.existsSync(e))
    throw new Error("writeWindowsZoneIdentifier didn't find the original file");
  await t.promises.writeFile(`${e}:Zone.Identifier`, S, { flag: "wx" });
}
const l = "0003";
async function u(e) {
  if (r) {
    const n = [
      l,
      Math.trunc(Date.now() / 1e3).toString(16),
      _.APP_NAME,
      a.randomUUID(),
    ].join(";");
    await s("/usr/bin/xattr", ["-w", "com.apple.quarantine", n, e], {
      reject: !1,
    });
  } else i && (await o(e).catch((n) => logger.error(n)));
}
const p = Object.freeze(
  Object.defineProperty(
    { __proto__: null, quarantineFile: u, writeWindowsZoneIdentifier: o },
    Symbol.toStringTag,
    { value: "Module" },
  ),
);
export { _ as e, p as f, u as q };
//# sourceMappingURL=fs-xattr-D7o0ii7n.mjs.map
