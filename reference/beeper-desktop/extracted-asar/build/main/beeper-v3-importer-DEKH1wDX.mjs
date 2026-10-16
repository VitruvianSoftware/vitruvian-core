import y from "classic-level";
import a from "path";
import f from "os";
import r from "fs/promises";
import { IS_MAC_OS as _, IS_WINDOWS as g } from "./constants-BL_pdRyX.mjs";
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
    var t = new e.Error().stack;
    t &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[t] = "70ef481a-1577-4873-b7d5-cd6176a15be7"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-70ef481a-1577-4873-b7d5-cd6176a15be7"));
  } catch {}
})();
const { ClassicLevel: w } = y,
  n = "Beeper";
function D() {
  return _
    ? a.join(f.homedir(), "Library", "Application Support", n)
    : g
      ? process.env.APPDATA
        ? a.join(process.env.APPDATA, n)
        : a.join(f.homedir(), n)
      : a.join(
          process.env.XDG_CONFIG_HOME ?? a.join(f.homedir(), ".config"),
          n,
        );
}
const p = a.join(D(), "Local Storage", "leveldb"),
  m = async (e, t) => {
    let o = !1;
    const s = t ? a.join(e, t) : e;
    try {
      (await r.access(s), (o = !0));
    } catch {
      o = !1;
    }
    return o;
  },
  u = (e, t) => `${e}\0${t}`,
  v = (e) => e?.replace(/\x01/g, "");
async function j() {
  if (!(await m(p))) {
    console.log("old app is probably not installed");
    return;
  }
  const t = Date.now(),
    o = `${p}-${t}`;
  try {
    (await r.cp(p, o, { recursive: !0 }),
      console.log(`database copied to ${o}`));
    const s = a.join(o, "LOCK");
    (await m(o, "LOCK")) &&
      (await r.unlink(s), console.log("LOCK file removed"));
    const c = new w(o, { valueEncoding: "utf8", createIfMissing: !1 });
    let l,
      b = !1,
      d;
    try {
      await c.open();
      const i = await c.getMany([
        u("_nova://nova-web", "bpAnalyticsEmail"),
        u("_nova://nova-web", "mx_crypto_initialised"),
        u("_nova://nova-web", "mx_device_id"),
      ]);
      ((l = i[0]), (b = v(i[1]) === "true"), (d = i[2]));
    } catch (i) {
      console.error("error reading from leveldb:", i);
    } finally {
      await c.close();
    }
    return {
      email: l ? v(l) : void 0,
      cryptoInitialised: b,
      deviceID: d ? v(d) : void 0,
    };
  } finally {
    (await r.rm(o, { recursive: !0, force: !0 }),
      console.log(`cleaned up backup database at ${o}`));
  }
}
export { j as getDataFromBeeperDesktopV3LevelDB };
//# sourceMappingURL=beeper-v3-importer-DEKH1wDX.mjs.map
