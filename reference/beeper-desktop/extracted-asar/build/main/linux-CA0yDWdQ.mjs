import { promises as r } from "fs";
import a from "path";
import { e as c } from "./index-CMOlVndj.mjs";
import f from "./package-CIHfweXK.mjs";
import { e as n } from "./fs-xattr-D7o0ii7n.mjs";
import { app as m } from "electron";
import "./_commonjsHelpers-CBUqixCJ.mjs";
import "child_process";
import "os";
import "assert";
import "events";
import "buffer";
import "stream";
import "util";
import "crypto";
import "./constants-BL_pdRyX.mjs";
import "url";
import u from "node:module";
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
      (e._sentryDebugIds[t] = "7cdb0aae-3b49-4db4-a0e8-29f6ca4f0f07"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-7cdb0aae-3b49-4db4-a0e8-29f6ca4f0f07"));
  } catch {}
})();
const C = import.meta.filename,
  g = import.meta.dirname,
  j = u.createRequire(import.meta.url),
  h = `[Desktop Entry]
Name=${n.APP_NAME}
Exec=${process.env.APPIMAGE} %u
Type=Application
Terminal=false
Comment=${f.description}
Categories=Network;Chat;
MimeType=x-scheme-handler/beeper;
StartupWMClass=${n.APP_NAME}
StartupNotify=true
`;
async function q() {
  const e = `${n.APP_NAME}.desktop`,
    t = `${m.getPath("home")}/.local/share/applications/`,
    i = `${m.getPath("home")}/.local/share/icons`,
    p = a.join(t, e),
    l = a.join(t, "beepertexts.desktop");
  try {
    (await r.mkdir(t, { recursive: !0 }), await r.mkdir(i, { recursive: !0 }));
    try {
      await r.rm(l, { force: !0 });
    } catch (d) {
      logger.warn(d);
    }
    await r.writeFile(p, h, "utf-8");
    const o = a.resolve(g, "..", "app-icons", "Beeper Squared.png"),
      s = `${i}/beeper.png`;
    (await r.copyFile(o, s),
      await c("/usr/bin/desktop-file-install", [
        "--dir",
        t,
        "--set-icon",
        s,
        p,
      ]),
      await c("xdg-mime", ["default", e, "x-scheme-handler/beeper"]));
  } catch (o) {
    (Sentry.captureException(o), logger.error(o));
  }
}
export { q as registerLinuxConfig };
//# sourceMappingURL=linux-CA0yDWdQ.mjs.map
